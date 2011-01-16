use Test::More;
use AnyEvent;
use AnyEvent::Memcached;
use Zacro;

eval { 
    Zacro->new( 
        open => [[0, 11222]] 
    ); 
};
plan skip_all => "Couldn't bind address on 0.0.0.0:11222. Because $@" if $@;
plan tests => 32;

my $cv = AE::cv;

my $memd = AnyEvent::Memcached->new(
    servers => [ qw/ 127.0.0.1:11222 / ],
    namespace => 'zacro_test',
    cv => $cv,
);

for my $i ( 1 .. 10 ) {
    $memd->set( test => $i, cb => sub {
        my $r = shift;
        ok $r, "Set failed: @_";
    } );
}

for my $i ( 1 .. 10 ) {
    $memd->get( 'test', cb => sub {
        my ( $val, $err ) = shift;
        is $err, undef, "Get failed: @_";
        is $val, $i;
    } );
}

$memd->get( 'test', cb => sub {
    my ( $val, $err ) = shift;
    is $err, undef, "Get failed: @_";
    is $val, undef;
} );

$cv->recv;
