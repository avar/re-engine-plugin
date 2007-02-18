=pod

Tests methods on the re object

=cut

use strict;

use feature ':5.10';

use Test::More 'no_plan';#tests => 6;

use re::engine::Plugin (
    comp => sub  {
        my $re = shift;

        # Use a stash to pass a single scalar value to each executing
        # routine, references work perfectly a reference to anything
        # can be passed as well
        $re->stash( { x => 5, y => sub { 6 } } );

        # Return value not used for now..
    },
    exec => sub {
        my ($re, $str) = @_;

        # pattern
        cmp_ok($re->pattern, 'eq', ' foobar zoobar ' => '->pattern ok');

        # flags
        my $f = $re->flags;
        like $f, qr/i/, 'str flags /i';
        like $f, qr/x/, 'str flags /x';
        like $f, qr/^[cgimosx]+$/, 'flags contain all-good characters';

        # stash
        cmp_ok($re->stash->{"x"}, '==', 5, "data correct in stash");
        cmp_ok(ref $re->stash->{"y"}, 'eq', 'CODE', "data correct in stash");
        cmp_ok(ref $re->stash->{"y"}, 'eq', 'CODE', "data correct in stash");
        cmp_ok($re->stash->{"y"}->(), '==', 6, "data correct in stash");

        # This needs a less sucky name
        #
        # Pattern: ' foobar zoobar ', set $1 to "foobar" (if I counted this right:)
#        $re->offset_captures( [1, 7], ... ); 

        # This name sucks as well
#        $re->named_captures2offset_captures( myNameIs => 0 ): # $+{myNameIs} = $1

        # Pattern contains "foo", "bar" and "zoo", return a true
        return $re->pattern =~ /zoo/;
    }
);

my $re = qr< foobar zoobar >xi;

if ("input" =~ $re ) {
    pass 'pattern matched';
} else {
    fail "pattern didn't match";
}

