package Zacro;
use strict;
use warnings;
our $VERSION = '0.01';

use parent qw/ Memcached::Server /;
use SUPER;
use AnyEvent;

our $queue = {};
our %PARAMS = (
    no_extra => 1,
    cmd => {
        set => \&set,
        get => \&get,
        delete => sub { shift->(1) },
        flush_all => \&flush_all,
    },
);

sub new {
    my $class = shift;
    my $self = $class->SUPER::new( %PARAMS, @_ );
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

Zacro - Job queuing daemon with memcached protocol

=head1 SYNOPSIS

  ### in your shell
  $ zacrod
  
  ### worker
  use Cache::Memcached::Fast;
  my $m = Cache::Memcached::Fast->new( {...} );
  while ( 1 ) {
      my $param = $m->get( 'my_queue' );
      sub { ... } if defined $param;
  }
  
  ### client
  use Cache::Memcached::Fast;
  my $m = Cache::Memcached::Fast->new( {...} );
  $m->set( 'my_queue', [ 'Tempula-Soba', 'Oyako-Don', 'Miso-Soup' ] );

=head1 DESCRIPTION

Zacro is a job queueing daemon.

=head1 AUTHOR

ytnobody E<lt>ytnobody@gmail.comE<gt>

=head1 SEE ALSO

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
