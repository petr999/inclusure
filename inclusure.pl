#!/usr/bin/env perl

use strict;
use warnings;

use Config;
use File::Find;
use FreeBSD::Pkgs;

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
        if ( $pkg =~ m/^perl-\d/ ) {
            if ($debug) {
                warn "Dupes found in $pkg package itself:";
                foreach my $fn ( keys %{ $$pkgs_delete{ $pkg } } ) {
                    warn $fn;
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
        unless ($dry) { exec 'pkg_delete', '-f', $pkg_delete }
    }
}

### MAIN

my $files = pass_perl_core_tree( $dirext => $incs );
pass_pkgs($files);
