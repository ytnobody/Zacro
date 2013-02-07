package Zacro;
use strict;
use warnings;
our $VERSION = '0.01';

use parent qw/ Memcached::Server /;
use AnyEvent;

our $queue = {};

sub new {
    my $class = shift;
    my $self = $class->SUPER::new( 
        no_extra => 1,
        cmd => {
            set => \&set,
            get => \&get,
            delete => sub { shift->(1) },
            flush_all => \&flush_all,
        },
        @_ 
    );
    return $self;
}

sub run {
    AE::cv->recv();
}

sub set {
    my ( $cb, $key, $flag, $expire, $data ) = @_;
    _enqueue( $key, $data );
    $cb->(1);
}

sub get {
    my ( $cb, $key ) = @_;
    my $res = _dequeue( $key );
    defined $res ? $cb->( 1, $res ) : $cb->( 0 );
}

sub flush_all {
    $queue = {};
    shift->();
}

sub _enqueue {
    my ( $key, $data ) = @_;
    $queue->{ $key } = [] unless defined $queue->{ $key };
    push @{ $queue->{ $key } }, $data;
}

sub _dequeue {
    my $key = shift;
    my $res = defined $queue->{ $key } ? shift @{ $queue->{ $key } } : undef;
    defined $queue->{ $key } ? 0 : delete $queue->{ $key };
    $res;
}

1;
__END__

=head1 NAME

Zacro - a job queuing daemon with memcached protocol

=head1 INSTALL

  $ git clone git://github.com/ytnobody/Zacro.git
  $ cpanm ./Zacro

=head1 SYNOPSIS

  ### in your shell
  $ zacrod
  
  ### your worker ( uses so much cpu resource )
  use Cache::Memcached::Fast;
  
  sub my_task { ... }
  
  my $m = Cache::Memcached::Fast->new( { ... } );
  while ( 1 ) {
      my $param = $m->get( 'my_queue' );
      my_task() if defined $param;
      ### if you want to thrifty cpu resource
      # sleep 1;
  }

  ### your client
  use Cache::Memcached::Fast;
  my $m = Cache::Memcached::Fast->new( {...} );
  $m->set( 'my_queue', [ 'Tempula-Soba', 'Oyako-Don', 'Miso-Soup' ] );

=head1 usage of zacrod

 $ zacrod [-b bind_address (default=0.0.0.0)] [-p port(default=11222)]

=head1 comparison with gearman

=head2 blocking when fetching queue

Look at these codes.

  ### worker for gearman
  use Gearman::Worker;
  my $worker = Gearman::Worker->new;
  $worker->job_servers( qw/ 127.0.0.1 / );
  $worker->register_function( foo => sub { ... } );
  $worker->work; ### no "while 1"

This is worker for gearman. It waits job-queue, and processes only once when found it.
In brief, if job-queue isn't came, this worker waits indefinitely.

Look at another codes.

  ### worker for Zacro
  use Cache::Memcached::Fast;
  sub my_task { ... }
  my $m = Cache::Memcaced::Fast->new( { ... } );
  my $queue = $m->get( 'job_queue' );
  my_task() if defined $queue;

This code finishes like lightning. Because, Cache::Memcached::Fast->get is *NONBLOCKING*.

=head2 job queuing on foreground

Gearman::Client contains do_task() method. It dispatches a task and waits on the results.

But, Zacro not contains such anything.

=head2 performance

Following is performance of setting job (comparison with Gearman).

 Benchmark: timing 100000 iterations of Gearman, Zacro...
    Gearman: 52 27.51 3.42 0 0 100000 set @ 3233.11/s (n=100000)
      Zacro: 13 1.03 1.24 0 0 100000 set @ 44052.86/s (n=100000)
            Rate Gearman   Zacro
 Gearman  3233/s      --    -93%
 Zacro   44053/s   1263%      --

And, Following are elapse time that's beginning job from setting job.

 $VAR1 = [
           bless( [
                    'max',
                    '12.6957490444183',
                    'min',
                    '0.043057918548584',
                    'average',
                    '6.17617448568342',
                    'total',
                    '506.957278966902'
                  ], 'MyBench::Zacro' ),
           bless( [
                    'max',
                    '64.5056960582733',
                    'min',
                    '0.00426197052001953',
                    'average',
                    '32.3016977689482',
                    'total',
                    '12791.4723165035'
                  ], 'MyBench::Gearman' )
         ];

Benchmark-code included into benchmark dir. Please try it!

=head1 AUTHOR

azuma satoshi E<lt>ytnobody@gmail.comE<gt>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
