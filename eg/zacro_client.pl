#!/usr/bin/env perl

use warnings;
use strict;
use vars qw( @ARGV );
use Benchmark qw( :all );
use Cache::Memcached::Fast;

my $memd = Cache::Memcached::Fast->new( { servers => [ qw/ 127.0.0.1:11222 / ] } );
my $n = $ARGV[1];
$n ||= 10;

timethis( $n, sub{ $memd->set( 'get_title', $ARGV[0] ) } );

