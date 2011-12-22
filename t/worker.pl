use strict;
use Cache::Memcached::Fast;
use Data::Dumper;

our @ARGV;

my $port = shift( @ARGV );
my $cache = Cache::Memcached::Fast->new({ servers => [ "127.0.0.1:$port" ] });
while ( 1 ) {
    my $param = $cache->get( 'test' );
    if ( $param ) {
        $cache->set( 'test_response', $param );
    }
    sleep 1;
}
exit;
