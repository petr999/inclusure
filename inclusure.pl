#!/usr/bin/env perl

use strict;
use warnings;

use Config;
use File::Find;
use FreeBSD::Pkgs;

our $VERSION = '0.0.1';

# Hash in the form directory => file_extension to search for dupes for (not
# from)
my $dirext = {
    $Config{ 'privlib' } => '\.(pm|pod)$',
    $Config{ 'archlib' } => '\.(so|al|bs)$',
};

# Directories where to search dupes
my $incs = [];
foreach my $noodle (@INC) {
    next if $noodle eq '.';
    unless ( defined $$dirext{ $noodle } ) { push @$incs, $noodle; }
}

my @arguments;
foreach my $arg (@ARGV) {
    my $parsed = $arg;
    $parsed =~ s/-+//;
    push @arguments, ( split //, $parsed );
}
our $dry   = not grep { $_ eq 'f' } @arguments;
our $debug = grep     { $_ eq 'd' } @arguments;

if ( grep { $_ eq 'h' } @arguments ) {
    &print_help_exit;
}

### SUBS

# Prints short help and exits
# Takes     :   n/a
# Returns   :   n/a
sub print_help_exit {
    print <<EOT;
Cleaning secondary perl directories from the ports duplicating the modules
already included in Perl core distribution, lang/perlX port.
    -d      Print (a lot of) debugging information: which file(s) is a dupe, which
files(s) will be included for deletion and so on.
    -f      Run pkg_delete on the packages reported
EOT
    exit;
}

# Passes by perl core tree(s) finding a file(s)  matching the regex
# corresponded by a directory to find the files and finds the same files to
# be found in @INC but present in non-core directory too.
# Can print files it found if global $debug is on
# Takes     :   hash consisting of keys which are the names of the perl core
#               directories and values are the regexes strings to match for
#               the full file names, and array of non-core perl include
#               directories
# Requires  :   global $debug variable to be defined
# Returns   :   HashRef of duplicates files found ( values are 1 )
sub pass_perl_core_tree {
    my ( $dirext => $incs ) = @_;
    my $pigs = {};    # to be returned
    while ( my ( $dir => $ext ) = each %$dirext ) {

        # For every directory make common regex and length for substr
        my $regex   = qr/$ext/;
        my $dir_len = length $dir;
        find(
            {

                # exclude '.' which is typically found in @INC
                no_chdir => 1,
                wanted   => sub {    # executed on every file in a dir
                    my $fn = $File::Find::name;
                    if ( $fn =~ m/$regex/ ) {

                        # Short name is a part of a filer name to search in
                        # another directories
                        my $sn = substr $fn, $dir_len, length($fn) - $dir_len;
                        foreach my $pigdir (@$incs) {

                            # Pig name is a name of a file which is a dupe if
                            # exists
                            my $pigname = "$pigdir$sn";
                            if ( -f $pigname ) {    # found a pig
                                if ($debug) { warn "Dupe found: $pigname\n" }

                                # filling return value
                                $$pigs{ $pigname } = 1;
                            }
                        }
                    }
                    }
            } => $dir    # directory is another argument for find()
        );
    }
    return $pigs;
}

# Passes by packages finding them to be deleted if the files supplied belong
# to them. Deletes unless $dry global variable. Warns about not-duplicate
# files to be deleted if $debug global variable
# Takes     :   HashRef of files (values are 1) to be deleted by pkg_delete(1)
# Requires  :   $dry and $debug global variables to be defined
# Returns   :   n/a
sub pass_pkgs {
    my $pigs  = shift;
    my $pkgdb = FreeBSD::Pkgs->new;
    $pkgdb->parseInstalled;
    my $pkgs        = $$pkgdb{ "packages" };
    my $pkgs_delete = {};                    # packages for deletion
    my $files       = {};                    # files installed by all packages
    while ( my ( $name => $pkg ) = each %$pkgs ) {
        my $prefix = $$pkg{ "contents" }{ "cwd" };
        foreach my $file ( keys %{ $$pkg{ "contents" }{ "files" } } ) {
            $file = "$prefix/$file";
            $$files{ $file } = 1;    # all packages' files uncoditionally

            # Every package suspected in duplication seem to be deleted
            if ( defined $$pigs{ $file } ) {
                if ( defined $$pkgs_delete{ $name } ) {
                    $$pkgs_delete{ $name }{ $file } = 1;
                }
                else { $$pkgs_delete{ $name } = { $file => 1 } }
            }
        }
    }

    # Finding files to be deleted but not belonging to any package
    while ( my ( $file => $val ) = each %$pigs ) {
        if ( $debug and not defined $$files{ $file } ) {
            warn "File is not from packages: $file";
        }
    }

    # Prevent perl from deletion
    my $pkg_delete_names = [ keys %$pkgs_delete ];
    foreach my $pkg (@$pkg_delete_names) {
        if ( $pkg =~ m/^perl(-threaded)?-\d/ ) {
            if ($debug) {
                warn "Dupes found in $pkg package itself:\n";
                foreach my $fn ( keys %{ $$pkgs_delete{ $pkg } } ) {
                    warn "$fn\n";
                }
            }
            delete $$pkgs_delete{ $pkg };
        }
    }

    # finding files to be deleted with packages but about for deletion earlier
    while ( my ( $pkg_delete => $files_delete ) = each %$pkgs_delete ) {
        my $prefix    = $$pkgs{ $pkg_delete }{ "contents" }{ "cwd" };
        my $files_pkg = $$pkgs{ $pkg_delete }{ "contents" }{ "files" };
        while ( my ( $file_pkg => $val ) = each %$files_pkg ) {
            $file_pkg = "$prefix/$file_pkg";
            if ( $debug and not defined $$files_delete{ $file_pkg } ) {
                warn "Additionally file to be deleted by pkg_delete(1)"
                    . " of $pkg_delete: $file_pkg";
            }
        }
        print "About to delete package: $pkg_delete\n";
        unless ($dry) { system 'pkg_delete', '-f', $pkg_delete }
    }
    unless( ( keys %$pkgs_delete ) > 0 ) {
        print "No packages to delete\n";
    }
}

### MAIN

my $files = pass_perl_core_tree( $dirext => $incs );
pass_pkgs($files);

__END__

=pod

=head1 NAME

Inclusure - Remove FreeBSD package/moduless same as those included in perl
package itself.

=head1 VERSION

This documentation refers to Inclusure version 0.0.1.

=head1 USAGE

The best and the first thing to remember is: till you do not pass the -f key to the
Inclusure it will not harm anything.

To know out how much is your problem run:

    $ perl inclosure.pl

This will show you what package(s) Inclusure is about to pkg_delete(1). It
shouldn't output the perl package itself here.

    $ perl inclusure.pl -d

This will show you the duplicates for those modules already found in your
installed Perl package.  The only exclusion is the C<BSDPAN/ExtUtils/*> files
as perl package currently installs more than one copy of those modules. If
however there are other files on the standard error output this may sound as a
reason to delete the certain package(s).

To perform the real action(s) do:

    # perl inclusure.pl -f

=head1 OPTIONS

    -h  show built-in commands help
    -d  show debug information including dupe files found, non-dupe files  to
        be deleted with the packages and dupe files not related to any package
    -f  Perform the package(s) deletion(s)

=head1 DESCRIPTION

As long as more and more modules are being included in every upcoming Perl core
distribution the more of them are getting duplicated in a FreeBSD system
because typically all of them are needed package(s) formerly installed from the
corresponding ports or via BSDPAN for the previous Perl packages installed
earlier those did not contain them yet.

This may lead to errors those are not that easy to discover, e. g., having
different XS modules on the system is not necessarily to warn you about
different XS part of the module loaded for the same particular perl module when
you use it.

Inclusure is a script  to prevent such a situation(s) by mean of finding the
modules files on the other C<@INC> elements than the directories that Perl
treats as its own: that means the dupes. Then Inclusure tries to delete the
packages that installed them if C<-f> command line key is supplied, or prints
them on the standard output if you need to make anything different with them
otherwise.

=head1 DIAGNOSTICS

Warnings use to be generated when C<-d> command line argument is supplied:

    "Dupe found: <file name>"

- name of the file considered to be as dupe

    "File is not from packages: <file name>"

- file name which is a dupe but does not belong to any package.

    "Dupes found in <package name> package itself:"
    <file name> ...

- file name(s) found in the what Inclusure believes to be a Perl package


    "Additionally file to be deleted by pkg_delete(1) of <package name>:
    <file name>"

- file name(s) to be deleted while not being a dupes. Those are typically a
module build helpers and C<man> files but can be of any kind.

=head1 CONFIGURATION AND ENVIRONMENT

You can tweak the C<$dirext> variable on your own opinion on location of files
the duplicate(s) of which can be searched, and the extension(s) or the whole
regexp to correspond to them.

If you use a 'site customize' feature of Perl and custom-make your @INC then
the behavior of Inclusure will depend on those changes.

Be sure to have a consistent packages database on your C<FreeBSD> system and a
C<perl-after-upgrade -f> to transfer all your modules to the new directories
after upgrade before to use Inclusure.

=head1 DEPENDENCIES

L<File::Find> is a part of a core Perl distribution.

L<FreeBSD::Pkgs> is a module that works with package database of C<FreeBSD>
operating system.  Available via the C<sysutils/p5-FreeBSD-Pkgs> port.

=head1 INCOMPATIBILITIES

The packages are used to be deleted despite of their dependencies. This may
break perl and perl-dependent applications present on your system.

=head1 BUGS AND LIMITATIONS

The Perl package is assumed to be the perl-E<lt>numberE<gt> or
perl-threaded-E<lt>numberE<gt>. Any other kind of perl package is about to be
deleted despite of dependencies by now.

You should fix the dependencies on deleted modules yourself, I'd suggest
C<pkgdb -F> tool from C<sysutils/portupgrade> port for this.

This script do not fix the duplicate modules installed with bypassing the
FreeBSD packages system.

The modules installed with the core Perl distribution can have different files
set and functionality and that difference may cause inconsistences in your
existing application(s).

Please report problems to Peter Vereshagin <peter@vereshagin.org>.
Patches are welcome.

=head1 AUTHOR

Peter Vereshagin <peter@vereshagin.org> L<http://vereshagin.org>

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2011 Peter Vereshagin <peter@vereshagin.org>. All rights
reserved.

This module is free software; you can redistribute it and/or modify it under
the terms of BSD license. See the LICENSE file in the archive/repository or
L<http://www.freebsd.org/copyright/freebsd%2Elicense.html> web page.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE.

=head1 SEE ALSO

Latest snapshot is available from L<http://gitweb.vereshagin.org/inclusure>
interface to my public Git repositories.

GitHub page is: L<http://github.com/petr999/inclusure> .

L<perl-after-upgrade>(1) .

=cut
