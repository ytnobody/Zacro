use warnings;
use strict;

use Proc::Simple;
use Memcached::Server::Default;
use AE;
use Gearman::Worker;
use Gearman::Client;
use Cache::Memcached::Fast;
use Benchmark qw/ :all /;
use Time::HiRes qw/ time sleep /;
use Storable qw/ freeze thaw /;
use Data::Dumper;

my $memcached_code = sub {
    Memcached::Server::Default->new( @_ );
    AE::cv->recv;
};

my $zacro_worker_code = sub {
    my $md = Cache::Memcached::Fast->new( {
        servers => [qw/127.0.0.1:65430/],
    } );
    my $zd = Cache::Memcached::Fast->new( {
        servers => [qw/127.0.0.1:65432/],
    } );
    while ( 1 ) {
        sleep 0.001;
        my $val = $zd->get( 'bench' );
        next unless defined $val;
        my $began = time();
        my $elapsed = $began - $val;
        my $total = $md->get( 'zacro_total' );
        my $max = $md->get( 'zacro_max' );
        my $min = $md->get( 'zacro_min' );
        my $count = $md->get( 'zacro_count' );
        $total ||= 0;
        $max ||= 0; 
        $min ||= $elapsed;
        $total += $elapsed;
        $count ||= 0;
        $md->set( 'zacro_total', $total );
        $md->set( 'zacro_max', $elapsed ) if $elapsed >= $max;
        $md->set( 'zacro_min', $elapsed ) if $elapsed <= $min;
        $md->set( 'zacro_count', $count + 1 );
    }
};

my $gearman_worker_code = sub {
    my $md = Cache::Memcached::Fast->new( {
        servers => [qw/127.0.0.1:65430/],
    } );
    my $gw = Gearman::Worker->new();
    $gw->job_servers( qw/ 127.0.0.1:65434 / );
    $gw->register_function( bench => sub {
        my $began = time();
        my ( $val ) = @{ thaw( $_[0]->arg ) };
        my $elapsed = $began - $val;
        my $total = $md->get( 'gearman_total' );
        my $max = $md->get( 'gearman_max' );
        my $min = $md->get( 'gearman_min' );
        my $count = $md->get( 'gearman_count' );
        $total ||= 0;
        $max ||= 0; 
        $min ||= $elapsed;
        $total += $elapsed;
        $count ||= 0;
        $md->set( 'gearman_total', $total );
        $md->set( 'gearman_max', $elapsed ) if $elapsed >= $max;
        $md->set( 'gearman_min', $elapsed ) if $elapsed <= $min;
        $md->set( 'gearman_count', $count + 1 );
    } );
    $gw->work while 1;
};

my $memcached = Proc::Simple->new();
my $zacrod = Proc::Simple->new();
my $zacro_worker = Proc::Simple->new();
my $gearmand = Proc::Simple->new();
my $gearman_worker = Proc::Simple->new();

$memcached->start( $memcached_code, open => [[0, 65430]] );
$zacrod->start( "zacrod -p 65432" );
$zacro_worker->start( $zacro_worker_code );
$gearmand->start( "gearmand --port 65434" );
$gearman_worker->start( $gearman_worker_code );

my $zacro_client = Cache::Memcached::Fast->new( { servers => [qw/127.0.0.1:65432/] } );
my $zacro_bench = sub { $zacro_client->set( 'bench', time() ) };

my $gearman_client = Gearman::Client->new( job_servers => [qw/127.0.0.1:65434/] );
my $gearman_bench = sub { $gearman_client->dispatch_background( 'bench', freeze( [ time() ] ) ) };

my $res = timethese( 100000, {
    Zacro => $zacro_bench,
    Gearman => $gearman_bench,
}, 'set' );

cmpthese( $res );

my $m = Cache::Memcached::Fast->new( {
    servers => [qw/127.0.0.1:65430/],
} );
print Dumper( [
    bless( [
        max => $m->get( 'zacro_max' ),
        min => $m->get( 'zacro_min' ),
        average => $m->get( 'zacro_total' ) / $m->get( 'zacro_count' ),
        total => $m->get( 'zacro_total' ),
    ], 'MyBench::Zacro' ),
    bless( [
        max => $m->get( 'gearman_max' ),
        min => $m->get( 'gearman_min' ),
        average => $m->get( 'gearman_total' ) / $m->get( 'gearman_count' ),
        total => $m->get( 'gearman_total' ),
    ], 'MyBench::Gearman' ),
] );

END {
    $gearman_worker->kill if $gearman_worker;
    $gearmand->kill if $gearmand;
    $zacro_worker->kill if $zacro_worker;
    $zacrod->kill if $zacrod;
    $memcached->kill if $memcached;
}

