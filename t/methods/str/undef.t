use strict;
use Test::More tests => 3;
use re::engine::Plugin (
    comp => sub {
        my ($re, $str) = @_;

        # Runs three times apperently.
        is($re->str, undef, 'str is undef');

        return;
    },
);

qr/pattern/;
