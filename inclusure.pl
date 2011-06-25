#!/usr/bin/env perl

use strict;
use warnings;

use Config;
use File::Find;

# Hash in the form directory => file_extension to search for dupes for (not
# from)
my %dirext = ( $Config{ 'privlib' } => 'pm', $Config{ 'archlib' } => 'so' );
my @dirs = keys %dirext;

# Directories where to search dupes
my @incs;
foreach my $noodle (@INC) {
    unless ( grep { $_ eq $noodle } @dirs ) {
        push @incs, $noodle;
    }
}

while ( my ( $dir => $ext ) = each %dirext ) {

    # For every directory make common regex and length for substr
    my $regex   = qr/\.$ext$/;
    my $dir_len = length $dir;
    find(
        {   no_chdir => 1,      # exclude '.' which is typically found in @INC
            wanted   => sub {   # executed on every file in a dir
                my $fn = $File::Find::name;
                if ( $fn =~ m/$regex/ ) {

                    # Short name is a part of a filer name to search in
                    # another directories
                    my $sn = substr( $fn, $dir_len, length($fn) - $dir_len );
                    foreach my $pigdir (@incs) {

                        # Pig name is a name of a file which is a dupe if
                        # exists
                        my $pigname = "$pigdir$sn";
                        if ( -f $pigname ) { print "$pigname\n" }
                    }
                }
                }
        } => $dir    # directory is another argument for find()
    );
}
