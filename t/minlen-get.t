use strict;

use Test::More tests => 2;

use re::engine::Plugin (
    comp => sub {
        my $re = shift;
        $re->minlen(2);
    },
    exec => sub {
        my $re = shift;
        my $minlen = $re->minlen;
        cmp_ok $minlen, '==', 2, 'minlen accessor';
    },
);

pass "making match";
"str" =~ /pattern/;
