=pod

Test the B<flags> method

=cut

use strict;

use feature ':5.10';

use Test::More tests => 28;

my @tests = (
    sub { cmp_ok shift, 'eq', '', => 'no flags' },
    sub { like shift, qr/c/ => '/c' },
    sub { cmp_ok shift, 'eq', 'g' => '/g' },
    sub { cmp_ok shift, 'eq', 'i' => '/i' },
    sub { cmp_ok shift, 'eq', 'm' => '/m' },
    sub { cmp_ok shift, 'eq', ''  => '/o' },
    sub { cmp_ok shift, 'eq', 's' => '/s' },
    sub { cmp_ok shift, 'eq', 'x' => '/x' },
    sub { cmp_ok shift, 'eq', 'p' => '/p' },
    sub { like $_[0], qr/$_/ => "/$_ in $_[0]" for unpack "(A)*", "xi" },
    sub { like $_[0], qr/$_/ => "/$_ in $_[0]" for unpack "(A)*", "xs" },
    sub { like $_[0], qr/$_/ => "/$_ in $_[0]" for unpack "(A)*", "cgimsxp" },
    sub { like $_[0], qr/$_/ => "/$_ in $_[0]" for unpack "(A)*", "e" },
    sub { like $_[0], qr/$_/ => "/$_ in $_[0]" for unpack "(A)*", "egimsxp" },
);

use re::engine::Plugin (
    exec => sub {
        my ($re, $str) = @_;

        my $t = shift @tests;

        $t->($re->flags);
    }
);

# Provide a pattern that can match to avoid running into regexp
# optimizations that won't call exec on C<"" =~ //>;

"" =~ /x/;
"" =~ /x/cg; # meaningless without /g
"" =~ /x/g;
"" =~ /x/i;
"" =~ /x/m;
"" =~ /x/o;
"" =~ /x/s;
"" =~ /x/x;
"" =~ /x/p;
"" =~ /x/xi;
"" =~ /x/xs;
"" =~ /x/cgimosxp;

my $_ = "";

$_ =~ s/1/2/e;
$_ =~ s/1/2/egimosxp;
