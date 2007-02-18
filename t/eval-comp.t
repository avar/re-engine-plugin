=pod

Having C<eval> catch C<die> in one of the callbacks when called
indirectly as C</pattern/> doesn't work. This is not at all surprising
since the eventual call to the callback sub is not exectuted within
the context that C</pattern> appeared in, but there's a test for it
anyway.

The other eval tests are just copies of this one made because the
interpreter can only die so many times per process.

=cut

use strict;

use Test::More skip_all => 'TODO: make this work';
#use Test::More tests => 1;

use re::engine::Plugin (
    comp => sub { die "died at comp time" },
    exec => sub { 1 },
);

eval { /noes/ };

TODO: {
    local $TODO = 'passing tests for known bug with how we handle eval';
    pass;
}
