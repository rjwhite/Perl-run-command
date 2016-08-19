#!/usr/bin/env perl

use lib "/usr/local/lib" ;
use Moxad::Rcommand qw( run_command :DEFAULT) ;
use strict ;
use warnings ;

my @output = () ;
my @errors = () ;
my $action = $STDIN_AND_STDOUT_SEPARATE ;
my $command = "who" ;

my $errs = run_command( $action, $command, \@output, \@errors ) ;
print "Num errs = $errs\n\n" ;

foreach my $line ( @output ) {
    chomp( $line ) ;
    print "Output: $line\n" ;
}
foreach my $line ( @errors ) {
    chomp( $line ) ;
    print "Error: $line\n" ;
}
exit 0 ;
