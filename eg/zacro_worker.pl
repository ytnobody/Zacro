#!/usr/bin/env perl

use warnings;
use strict;
use Cache::Memcached::Fast;
use Web::Scraper;
use Encode;
use URI;
use Data::Dumper;

my $memd = Cache::Memcached::Fast->new( { servers => [ qw/ 127.0.0.1:11222 / ] } );
my $scraper = scraper {
    process "//title", title => 'TEXT';
};
my $i = 0;

while ( 1 ) {
    my $val = $memd->get( 'get_title' );
    if ( $val ) {
        $i++;
        my $res = $scraper->scrape( URI->new( $val ) );
        print "[$$] $i ". encode( 'utf8', $res->{ title } )."\n" if $res;
    }
}
