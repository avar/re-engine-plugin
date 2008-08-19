# See Plugin.pod for documentation
package re::engine::Plugin;
use 5.009005;
use strict;
use XSLoader ();

our $VERSION = '0.06';

# All engines should subclass the core Regexp package
our @ISA = 'Regexp';

XSLoader::load __PACKAGE__, $VERSION;

my $RE_ENGINE_PLUGIN = ENGINE();

# How many? Used to cheat %^H
my $callback = 1;

# Where we store our CODE refs
my %callback;

# Generate a key to use in the %^H hash from a string, prefix the
# package name like L<pragma> does
my $key = sub { __PACKAGE__ . "::" . $_[0] };

sub import
{
    my ($pkg, %sub) = @_;

    # Valid callbacks
    my @callback = qw(comp exec);

    for (@callback) {
        next unless exists $sub{$_};
        my $cb = delete $sub{$_};

        unless (ref $cb eq 'CODE') {
            require Carp;
            Carp::croak("'$_' is not CODE");
        }

        # Get an ID to use
        my $id = $callback ++;

        # Insert into our callback storage,
        $callback{$_}->{$id} = $cb;

        # Instert into our cache with a key we can retrive later
        # knowing the ID in %^H and what callback we're getting
        $^H{ $key->($_) } = $id;
    }

    $^H{regcomp} = $RE_ENGINE_PLUGIN;
}

sub unimport
{
    # Delete the regcomp hook
    delete $^H{regcomp}
        if $^H{regcomp} == $RE_ENGINE_PLUGIN;
}

# Minimal function to get CODE for a given key to be called by the
# get_H_callback C function.
sub _get_callback
{
    my ($name) = @_; # 'comp', 'exec', ...

    my $h = (caller(0))[10];
    my $id = $h->{ $key->($name) };

    my $cb = defined $id ? $callback{$name}->{$id} : 0;

    return $cb;
}

sub num_captures
{
    my ($re, %callback) = @_;

    for my $key (keys %callback) {
        $key =~ y/a-z/A-Z/; # ASCII uc
        my $name = '_num_capture_buff_' . $key;
        $re->$name( $callback{$key} );
    }
}

1;
