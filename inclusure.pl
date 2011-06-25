#!/usr/bin/env perl

use strict;
use warnings;

use Config;
use File::Find;
use feature ':5.14';

my %dirext = ( $Config{ 'privlib' } => 'pm', $Config{ 'archlib' } => 'so' );
my @dirs = keys %dirext;
my @incs;
foreach my $noodle (@INC) {
    unless ( grep { $_ eq $noodle } @dirs ) {
        push @incs, $noodle;
    }
}

while ( my ( $dir => $ext ) = each %dirext ) {
    my $regex   = qr/\.$ext$/;
    my $dir_len = length $dir;
    find(
        {   no_chdir => 1,
            wanted   => sub {
                my $fn = $File::Find::name;
                if ( $fn =~ m/$regex/ ) {
                    my $sn = substr( $fn, $dir_len, length($fn) - $dir_len );
                    foreach my $pigdir (@incs) {
                        my $pigname = "$pigdir$sn";
                        if ( -f $pigname ) { say $pigname }
                    }
                }
                }
        } => $dir
    );
}
