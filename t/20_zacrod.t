use strict;
use warnings;
use Test::More;
use Test::TCP;
use Cache::Memcached::Fast;
use Proc::Simple;
use Guard ();

subtest zacrod => sub {
    my $port = Test::TCP::empty_port();

    my $server = Proc::Simple->new;
    $server->start("bin/zacrod -p ".$port);

    sleep 1;

    my $worker = Proc::Simple->new;
    $worker->start("env perl t/worker.pl ".$port);

    my $guard = Guard::guard { 
        $worker->kill; 
        $server->kill;
    };

    my $cache = Cache::Memcached::Fast->new( { servers => [ sprintf "127.0.0.1:%s", $port ] } );
    
    $cache->set( 'test', 'anpan' );
    my $res;
    for ( 1 .. 5 ) {
        $res = $cache->get( 'test_response' );
        last if $res;
        sleep 1;
    }
    
    is $res, 'anpan';
};

done_testing;
