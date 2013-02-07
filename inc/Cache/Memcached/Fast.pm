#line 1
# See the end of the file for copyright and license.
#

package Cache::Memcached::Fast;

use 5.006;
use strict;
use warnings;


#line 19

our $VERSION = '0.19';


#line 130


use Carp;
use Storable;

require XSLoader;
XSLoader::load('Cache::Memcached::Fast', $VERSION);


#line 491

our %known_params = (
    servers => [ { address => 1, weight => 1, noreply => 1 } ],
    namespace => 1,
    nowait => 1,
    hash_namespace => 1,
    connect_timeout => 1,
    io_timeout => 1,
    select_timeout => 1,
    close_on_error => 1,
    compress_threshold => 1,
    compress_ratio => 1,
    compress_methods => 1,
    compress_algo => sub {
        carp "compress_algo has been removed in 0.08,"
          . " use compress_methods instead"
    },
    max_failures => 1,
    failure_timeout => 1,
    ketama_points => 1,
    serialize_methods => 1,
    utf8 => 1,
    max_size => 1,
    check_args => 1,
);


sub _check_args {
    my ($checker, $args, $level) = @_;

    $level = 0 unless defined $level;

    my @unknown;

    if (ref($args) ne 'HASH') {
        if (ref($args) eq 'ARRAY' and ref($checker) eq 'ARRAY') {
            foreach my $v (@$args) {
                push @unknown, _check_args($checker->[0], $v, $level + 1);
            }
        }
        return @unknown;
    }

    if (exists $args->{check_args}
        and lc($args->{check_args}) eq 'skip') {
        return;
    }

    while (my ($k, $v) = each %$args) {
        if (exists $checker->{$k}) {
            if (ref($checker->{$k}) eq 'CODE') {
                $checker->{$k}->($args, $k, $v);
            } elsif (ref($checker->{$k})) {
                push @unknown, _check_args($checker->{$k}, $v, $level + 1);
            }
        } else {
            push @unknown, $k;
        }
    }

    if ($level > 0) {
        return @unknown;
    } else {
        carp "Unknown parameter: @unknown" if @unknown;
    }
}


our %instance;

sub new {
    my Cache::Memcached::Fast $class = shift;
    my ($conf) = @_;

    _check_args(\%known_params, $conf);

    if (not $conf->{compress_methods} and eval "require Compress::Zlib") {
        # Note that the functions below can't return false when
        # operation succeed.  This is because "" and "0" compress to a
        # longer values (because of additional format data), and
        # compress_ratio will force them to be stored uncompressed,
        # thus decompression will never return them.
        $conf->{compress_methods} = [
            sub { ${$_[1]} = Compress::Zlib::memGzip(${$_[0]}) },
            sub { ${$_[1]} = Compress::Zlib::memGunzip(${$_[0]}) }
        ];
    }

    if ($conf->{utf8} and $^V lt v5.8.1) {
        carp "'utf8' may be enabled only for Perl >= 5.8.1, disabled";
        undef $conf->{utf8};
    }

    $conf->{serialize_methods} ||= [ \&Storable::nfreeze, \&Storable::thaw ];

    my $memd = Cache::Memcached::Fast::_new($class, $conf);

    if (eval "require Scalar::Util") {
        my $context = [$memd, $conf];
        Scalar::Util::weaken($context->[0]);
        $instance{$$memd} = $context;
    }

    return $memd;
}


sub CLONE {
    my ($class) = @_;

    my @contexts = values %instance;
    %instance = ();
    foreach my $context (@contexts) {
        my $memd = Cache::Memcached::Fast::_new($class, $context->[1]);
        ${$context->[0]} = $$memd;
        $instance{$$memd} = $context;
        $$memd = 0;
    }
}


sub DESTROY {
    my ($memd) = @_;

    return unless $$memd;

    delete $instance{$$memd};

    Cache::Memcached::Fast::_destroy($memd);
}


#line 641

# See Fast.xs.


#line 658

# See Fast.xs.


#line 681

# See Fast.xs.


#line 707

# See Fast.xs.


#line 733

# See Fast.xs.


#line 761

# See Fast.xs.


#line 780

# See Fast.xs.


#line 806

# See Fast.xs.


#line 825

# See Fast.xs.


#line 851

# See Fast.xs.


#line 871

# See Fast.xs.


#line 897

# See Fast.xs.


#line 917

# See Fast.xs.


#line 943

# See Fast.xs.


#line 956

# See Fast.xs.


#line 971

# See Fast.xs.


#line 995

# See Fast.xs.


#line 1012

# See Fast.xs.


#line 1030

# See Fast.xs.


#line 1057

# See Fast.xs.


#line 1078

# See Fast.xs.


#line 1105

# See Fast.xs.


#line 1119

# See Fast.xs.


#line 1128

*remove = \&delete;


#line 1149

# See Fast.xs.


#line 1174

# See Fast.xs.


#line 1197

# See Fast.xs.


#line 1212

# See Fast.xs.


#line 1228

# See Fast.xs.


1;

__END__

#line 1485
