use strict;
use Test::More tests => ($] <= 5.010 ? 3 : 1);
use re::engine::Plugin (
    comp => sub {
        my ($re, $str) = @_;

        is($re->str, undef, 'str is undef');

        return;
    },
);

qr/pattern/;
