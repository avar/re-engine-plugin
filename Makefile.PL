use 5.009005;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME		  => 're::engine::Plugin',
    AUTHOR        => 'Ævar Arnfjörð Bjarmason <avar@cpan.org>',
    ABSTRACT_FROM => 'Plugin.pod',
    VERSION_FROM  => 'Plugin.pm',
    LICENSE       => 'perl',
    test          => {
        TESTS => 't/*.t t/*/*.t t/*/*/*.t',
    },
);

sub MY::postamble {
    return <<END;
ChangeLog: Makefile
	git log --pretty=full . >ChangeLog

META.yml: Makefile
	touch META.yml

END
}

