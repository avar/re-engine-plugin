# See Plugin.pod for documentation
package re::engine::Plugin;
use 5.009005;
use strict;
use Carp 'croak';
use Scalar::Util 'weaken';
use XSLoader ();

our $VERSION = '0.01';

XSLoader::load __PACKAGE__, $VERSION;

my $RE_ENGINE_PLUGIN = get_engine_plugin();
my $NULL = 0;

# How many? Used to cheat %^H
my $callback = 0;
# Valid callbacks
my @callback = qw(comp exec intuit checkstr free dupe);
# Where we store our CODE refs
my %callback;

sub import
{
    my ($pkg, %sub) = @_;

    #$sub{$_} = sub {}

    for (@callback) {
        next unless exists $sub{$_};
        my $cb = delete $sub{$_};

        # Convert "package::sub" to CODE if it isn't CODE already
        unless (ref $cb eq 'CODE') {
            no strict 'refs';
            $cb = *{$cb}{CODE};
        }

        # Whine if we don't get a CODE ref or a valid package::sub name
        croak "'$_' is not CODE and neither is the *{$cb}{CODE} fallback"
            unless ref $cb eq 'CODE';

        # Get an ID to use
        my $id = $callback ++;

        # Insert into our callback storage,
        $callback{$_}->{$id} = $cb;

        # Weaken it so we don't end up hanging on to something the
        # caller doesn't care about anymore
        #weaken($callback{$_}->{$id}); # EEK, too weak!

        # Instert into our cache with a key we can retrive later
        # knowing the ID in %^H and what callback we're getting
        my $key = callback_key($_);
        $^H{$key} = $id;
    }

    $^H{regcomp} = $RE_ENGINE_PLUGIN;
}

sub unimport
{
    my ($pkg) = @_;

    # Delete the regcomp hook
    delete $^H{regcomp} if $^H{regcomp} == $RE_ENGINE_PLUGIN;
}

sub callback_key
{
    my ($name) = @_;

    sprintf "rep_%s", $name;
}

# Minimal function to be called from the XS
sub get_callback
{
    my ($name) = @_; # 'comp', 'exec', ...

    my $key = callback_key($name);
    my $h = (caller(0))[10];
    my $id = $h->{$key};

    my $cb = defined $id ? $callback{$name}->{$id} : 0;

    return $cb;
}

1;
