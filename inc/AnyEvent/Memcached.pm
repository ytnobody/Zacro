#line 1
package AnyEvent::Memcached;

use 5.8.8;

#line 9

our $VERSION = '0.05';

#line 97

use common::sense 2;m{
use strict;
use warnings;
}x;

use Carp;
use AnyEvent 5;
#use Devel::Leak::Cb;

use AnyEvent::Socket;
use AnyEvent::Handle;
use AnyEvent::Connection;
use AnyEvent::Connection::Util;
use AnyEvent::Memcached::Conn;
use Storable ();

use AnyEvent::Memcached::Peer;
use AnyEvent::Memcached::Hash;
use AnyEvent::Memcached::Buckets;

# flag definitions
use constant F_STORABLE => 1;
use constant F_COMPRESS => 2;

# size savings required before saving compressed value
use constant COMPRESS_SAVINGS => 0.20; # percent

our $HAVE_ZLIB;
BEGIN {
	$HAVE_ZLIB = eval "use Compress::Zlib (); 1;";
}

#line 161

sub new {
	my $self = bless {}, shift;
	my %args = @_;
	$self->{namespace} = exists $args{namespace} ? delete $args{namespace} : '';
	for (qw( debug cv compress_threshold compress_enable timeout noreply cas)) {
		$self->{$_} = exists $args{$_} ? delete $args{$_} : 0;
	}
	$self->{timeout} ||= 3;
	$self->{_bucker} = $args{bucker} || 'AnyEvent::Memcached::Buckets';
	$self->{_hasher} = $args{hasher} || 'AnyEvent::Memcached::Hash';

	$self->set_servers(delete $args{servers});
	$self->{compress_enable} and !$HAVE_ZLIB and Carp::carp("Have no Compress::Zlib installed, but have compress_enable option");
	require Carp; Carp::carp "@{[ keys %args ]} options are not supported yet" if %args;
	$self;
}

#line 184

sub set_servers {
	my $self = shift;
	my $list = shift;
	my $buckets = $self->{_bucker}->new(servers => $list);
	#warn R::Dump($list, $buckets);
	$self->{hash} = $self->{_hasher}->new(buckets => $buckets);
	$self->{peers} = 
	my $peers = $buckets->peers;
	for my $peer ( values %{ $peers } ) {
		$peer->{con} = AnyEvent::Memcached::Peer->new(
			port      => $peer->{port},
			host      => $peer->{host},
			timeout   => $self->{timeout},
			debug     => $self->{debug},
		);
		# Noreply connection
		if ($self->{noreply}) {
			$peer->{nrc} = AnyEvent::Memcached::Peer->new(
				port      => $peer->{port},
				host      => $peer->{host},
				timeout   => $self->{timeout},
				debug     => $self->{debug},# || 1,
			);
		}
	}
	return $self;
}

#line 218

sub connect {
	my $self = shift;
	$_->{con}->connect
		for values %{ $self->{peers} };
}

sub _handle_errors {
	my $self = shift;
	my $peer = shift;
	local $_ = shift;
	if ($_ eq 'ERROR') {
		warn "Error";
	}
	elsif (/(CLIENT|SERVER)_ERROR (.*)/) {
		warn ucfirst(lc $1)." error: $2";
	}
	else {
		warn "Bad response from $peer->{host}:$peer->{port}: $_";
	}
}

sub _do {
	my $self    = shift;
	my $key     = shift; utf8::decode($key) xor utf8::encode($key) if utf8::is_utf8($key);
	my $command = shift; utf8::decode($command) xor utf8::encode($command) if utf8::is_utf8($command);
	my $worker  = shift; # CODE
	my %args    = @_;
	my $servers = $self->{hash}->servers($key);
	my %res;
	my %err;
	my $res;
	if ($args{noreply} and !$self->{noreply}) {
		if (!$args{cb}) {
			carp "Noreply option not set, but noreply command requested. command ignored";
			return 0;
		} else {
			carp "Noreply option not set, but noreply command requested. fallback to common command";
		}
		delete $args{noreply};
	}
	if ($args{noreply}) {
		for my $srv ( keys %$servers ) {
			for my $real (@{ $servers->{$srv} }) {
				my $cmd = $command.' noreply';
				substr($cmd, index($cmd,'%s'),2) = $real;
				$self->{peers}{$srv}{nrc}->request($cmd);
				$self->{peers}{$srv}{lastnr} = $cmd;
				unless ($self->{peers}{$srv}{nrc}->handles('command')) {
					$self->{peers}{$srv}{nrc}->reg_cb(command => sub { # cb {
						shift;
						warn "Got data from $srv noreply connection (while shouldn't): @_\nLast noreply command was $self->{peers}{$srv}{lastnr}\n";
					});
					$self->{peers}{$srv}{nrc}->want_command();
				}
			}
		}
		$args{cb}(1) if $args{cb};
		return 1;
	}
	$_ and $_->begin for $self->{cv}, $args{cv};
	my $cv = AE::cv {
		#use Data::Dumper;
		#warn Dumper $res,\%res,\%err;
		if ($res != -1) {
			$args{cb}($res);
		}
		elsif (!%err) {
			warn "-1 while not err";
			$args{cb}($res{$key});
		}
		else {
			$args{cb}(undef, dumper($err{$key}));
		}
		#warn "cv end";
		
		$_ and $_->end for $args{cv}, $self->{cv};
	};
	for my $srv ( keys %$servers ) {
		for my $real (@{ $servers->{$srv} }) {
			$cv->begin;
			my $cmd = $command;
			substr($cmd, index($cmd,'%s'),2) = $real;
			$self->{peers}{$srv}{con}->command(
				$cmd,
				cb => sub { # cb {
					if (defined( local $_ = shift )) {
						my ($ok,$fail) = $worker->($_);
						if (defined $ok) {
							$res{$real}{$srv} = $ok;
							$res = (!defined $res ) || $res == $ok ? $ok : -1;
						} else {
							$err{$real}{$srv} = $fail;
							$res = -1;
						}
					} else {
						warn "do failed: @_/$!";
						$err{$real}{$srv} = $_;
						$res = -1;
					}
					$cv->end;
				}
			);
		}
	}
	return;
}

sub _set {
	my $self = shift;
	my $cmd = shift;
	my $key = shift;
	my $cas;
	if ($cmd eq 'cas') {
		$cas = shift;
	}
	my $val = shift;
	my %args = @_;
	return $args{cb}(undef, "Readonly") if $self->{readonly};
	#warn "cv begin";

	use bytes; # return bytes from length()

	warn "value for memkey:$key is not defined" unless defined $val;
	my $flags = 0;
	if (ref $val) {
		local $Carp::CarpLevel = 2;
		$val = Storable::nfreeze($val);
		$flags |= F_STORABLE;
	}
	my $len = length($val);

	if ( $self->{compress_threshold} and $HAVE_ZLIB
	and $self->{compress_enable} and $len >= $self->{compress_threshold}) {

		my $c_val = Compress::Zlib::memGzip($val);
		my $c_len = length($c_val);

		# do we want to keep it?
		if ($c_len < $len*(1 - COMPRESS_SAVINGS)) {
			$val = $c_val;
			$len = $c_len;
			$flags |= F_COMPRESS;
		}
	}

	my $expire = int($args{expire} || 0);
	return $self->_do(
		$key,
		"$cmd $self->{namespace}%s $flags $expire $len".(defined $cas ? ' '.$cas : '')."\015\012$val",
		sub { # cb {
			local $_ = shift;
			if    ($_ eq 'STORED')     { return 1 }
			elsif ($_ eq 'NOT_STORED') { return 0 }
			elsif ($_ eq 'EXISTS')     { return 0 }
			else                       { return undef, $_ }
		},
		cb => $args{cb},
	);
	$_ and $_->begin for $self->{cv}, $args{cv};
	my $servers = $self->{hash}->servers($key);
	my %res;
	my %err;
	my $res;
	my $cv = AE::cv {
		if ($res != -1) {
			$args{cb}($res);
		}
		elsif (!%err) {
			warn "-1 while not err";
			$args{cb}($res{$key});
		}
		else {
			$args{cb}(undef, dumper($err{$key}));
		}
		warn "cv end";
		
		$_ and $_->end for $args{cv}, $self->{cv};
	};
	for my $srv ( keys %$servers ) {
		# ??? Can hasher return more than one key for single key passed?
		# If no, need to remove this inner loop
		#warn "server for $key = $srv, $self->{peers}{$srv}";
		for my $real (@{ $servers->{$srv} }) {
			$cv->begin;
			$self->{peers}{$srv}{con}->command(
				"$cmd $self->{namespace}$real $flags $expire $len\015\012$val",
				cb => sub { # cb {
					if (defined( local $_ = shift )) {
						if ($_ eq 'STORED') {
							$res{$real}{$srv} = 1;
							$res = (!defined $res)||$res == 1 ? 1 : -1;
						}
						elsif ($_ eq 'NOT_STORED') {
							$res{$real}{$srv} = 0;
							$res = (!defined $res)&&$res == 0 ? 0 : -1;
						}
						elsif ($_ eq 'EXISTS') {
							$res{$real}{$srv} = 0;
							$res = (!defined $res)&&$res == 0 ? 0 : -1;
						}
						else {
							$err{$real}{$srv} = $_;
							$res = -1;
						}
					} else {
						warn "set failed: @_/$!";
						#$args{cb}(undef, @_);
						$err{$real}{$srv} = $_;
						$res = -1;
					}
					$cv->end;
				}
			);
		}
	}
	return;
}

#line 502

sub set     { shift->_set( set => @_) }
sub cas     {
	my $self = shift;
	unless ($self->{cas}) { shift;shift;my %args = @_;return $args{cb}(undef, "CAS not enabled") }
	$self->_set( cas => @_)
}
sub add     { shift->_set( add => @_) }
sub replace { shift->_set( replace => @_) }
sub append  { shift->_set( append => @_) }
sub prepend { shift->_set( prepend => @_) }

#line 535

sub _deflate {
	my $self = shift;
	my $result = shift;
	for (
		ref $result eq 'ARRAY' ? 
			@$result ? @$result[ map { $_*2+1 } 0..int( $#$result / 2 ) ] : ()
			: values %$result
	) {
		if ($HAVE_ZLIB and $_->{flags} & F_COMPRESS) {
			$_->{data} = Compress::Zlib::memGunzip($_->{data});
		}
		if ($_->{flags} & F_STORABLE) {
			eval{ $_->{data} = Storable::thaw($_->{data}); 1 } or delete $_->{data};
		}
		if (exists $_->{cas}) {
			$_ = [$_->{cas},$_->{data}];
		} else {
			$_ = $_->{data};
		}
	}
	return;
}

sub _get {
	my $self = shift;
	my $cmd  = shift;
	my $keys = shift;
	my %args = @_;
	my $array;
	if (ref $keys and ref $keys eq 'ARRAY') {
		$array = 1;
	}
	
	$_ and $_->begin for $self->{cv}, $args{cv};
	my $servers = $self->{hash}->servers($keys, for => 'get');
	my %res;
	my $cv = AE::cv {
		$self->_deflate(\%res);
		$args{cb}( $array ? \%res :  $res{ $keys } );
		$_ and $_->end for $args{cv}, $self->{cv};
	};
	for my $srv ( keys %$servers ) {
		#warn "server for $key = $srv, $self->{peers}{$srv}";
		$cv->begin;
		my $keys = join(' ',map "$self->{namespace}$_", @{ $servers->{$srv} });
		$self->{peers}{$srv}{con}->request( "$cmd $keys" );
		$self->{peers}{$srv}{con}->reader( id => $srv.'+'.$keys, res => \%res, namespace => $self->{namespace}, cb => sub { # cb {
			$cv->end;
		});
	}
	return;
}
sub get  { shift->_get(get => @_) }
sub gets {
	my $self = shift;
	unless ($self->{cas}) { shift;my %args = @_;return $args{cb}(undef, "CAS not enabled") }
	$self->_get(gets => @_)
}

#line 610

sub delete {
	my $self = shift;
	my ($cmd) = (caller(0))[3] =~ /([^:]+)$/;
	my $key = shift;
	my %args = @_;
	return $args{cb}(undef, "Readonly") if $self->{readonly};
	my $time = $args{delay} ? " $args{delay}" : '';
	return $self->_do(
		$key,
		"delete $self->{namespace}%s$time",
		sub { # cb {
			local $_ = shift;
			if    ($_ eq 'DELETED')    { return 1 }
			elsif ($_ eq 'NOT_FOUND')  { return 0 }
			else                       { return undef, $_ }
		},
		cb => $args{cb},
		noreply => $args{noreply},
	);
}
*del   =  \&delete;
*remove = \&delete;

#line 648

sub _delta {
	my $self = shift;
	my ($cmd) = (caller(1))[3] =~ /([^:]+)$/;
	my $key = shift;
	my $val = shift;
	my %args = @_;
	return $args{cb}(undef, "Readonly") if $self->{readonly};
	return $self->_do(
		$key,
		"$cmd $self->{namespace}%s $val",
		sub { # cb {
			local $_ = shift;
			if    ($_ eq 'NOT_FOUND')  { return 0 }
			elsif (/^(\d+)$/)          { return $1 eq '0' ? '0E0' : $_ }
			else                       { return undef, $_ }
		},
		cb => $args{cb},
		noreply => $args{noreply},
	);
}
sub incr { shift->_delta(@_) }
sub decr { shift->_delta(@_) }

#rget <start key> <end key> <left openness flag> <right openness flag> <max items>\r\n
#
#- <start key> where the query starts.
#- <end key>   where the query ends.
#- <left openness flag> indicates the openness of left side, 0 means the result includes <start key>, while 1 means not.
#- <right openness flag> indicates the openness of right side, 0 means the result includes <end key>, while 1 means not.
#- <max items> how many items at most return, max is 100.

# rget ($from,$till, '+left' => 1, '+right' => 0, max => 10, cb => sub { ... } );

#line 715

sub rget {
	my $self = shift;
	#my ($cmd) = (caller(0))[3] =~ /([^:]+)$/;
	my $cmd = 'rget';
	my $from = shift;
	my $till = shift;
	my %args = @_;
	my ($lkey,$rkey);
	#$lkey = ( exists $args{'+left'} && !$args{'+left'} ) ? 1 : 0;
	$lkey = exists $args{'+left'}  ? $args{'+left'}  ? 0 : 1 : 0;
	$rkey = exists $args{'+right'} ? $args{'+right'} ? 0 : 1 : 0;
	$args{max} ||= 100;

	my $result;
	if (lc $args{rv} eq 'array') {
		$result = [];
	} else {
		$result = {};
	}
	my $err;
	my $cv = AnyEvent->condvar;
	$_ and $_->begin for $self->{cv}, $args{cv};
	$cv->begin(sub {
		undef $cv;
		$self->_deflate($result);
		$args{cb}( $err ? (undef,$err) : $result );
		undef $result;
		$_ and $_->end for $args{cv}, $self->{cv};
	});

	for my $peer (keys %{$self->{peers}}) {
		$cv->begin;
		my $do;$do = sub {
			undef $do;
			$self->{peers}{$peer}{con}->request( "$cmd $self->{namespace}$from $self->{namespace}$till $lkey $rkey $args{max}" );
			$self->{peers}{$peer}{con}->reader( id => $peer, res => $result, namespace => $self->{namespace}, cb => sub {
				#warn "rget from: $peer";
				$cv->end;
			});
		};
		if (exists $self->{peers}{$peer}{rget_ok}) {
			if ($self->{peers}{$peer}{rget_ok}) {
				$do->();
			} else {
				#warn
					$err = "rget not supported on peer $peer";
				$cv->end;
			}
		} else {
			$self->{peers}{$peer}{con}->command( "$cmd 1 0 0 0 1", cb => sub {
				local $_ = shift;
				if (defined $_) {
					if ($_ eq 'END') {
						$self->{peers}{$peer}{rget_ok} = 1;
						$do->();
					}
					else {
						#warn
							$err = "rget not supported on peer $peer: @_";
						$self->{peers}{$peer}{rget_ok} = 0;
						undef $do;
						$cv->end;
					}
				} else {
					$err = "@_";
					undef $do;
					$cv->end;
				}
			} );
			
		}
	}
	$cv->end;
	return;
}

#line 797

sub incadd {
	my $self = shift;
	my $key = shift;
	my $val = shift;
	my %args = @_;
	$self->incr($key => $val, cb => sub {
		if (my $rc = shift or @_) {
			#if (@_) {
			#	warn("incr failed: @_");
			#} else {
			#	warn "incr ok";
			#}
			$args{cb}($rc, @_);
		}
		else {
			$self->add( $key, $val, cb => sub {
				if ( my $rc = shift or @_ ) {
					#if (@_) {
					#	warn("add failed: @_");
					#} else {
					#	warn "add ok";
					#}
					$args{cb}($val, @_);
				}
				else {
					#warn "add failed, try again";
					$self->incr_add($key,$val,%args);
				}
			});
		}
	});
}

#line 836

sub AnyEvent::Memcached::destroyed::AUTOLOAD {}

sub destroy {
	my $self = shift;
	$self->DESTROY;
	bless $self, "AnyEvent::Memcached::destroyed";
}

sub DESTROY {
	my $self = shift;
	warn "(".int($self).") Destroying AE:MC" if $self->{debug};
	for (values %{$self->{peers}}) {
		$_->{con} and $_->{con}->destroy;
	}
	%$self = ();
}

#line 872

1; # End of AnyEvent::Memcached
