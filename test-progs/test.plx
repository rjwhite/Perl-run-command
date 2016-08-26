#!/usr/bin/env perl
# Force a early ALARM termination

use lib "/usr/local/lib" ;
use Moxad::Rcommand qw( run_command_wait ) ;
use strict ;
use warnings ;

my @output = () ;
my @errors = () ;

my $command = $ARGV[0] ;
if ( not defined( $command )) {
    print "command: " ;
    $command = <> ;
}

my %options = (
    'alarm'     => 3,   
    'stderr'    => 1,
) ;

Moxad::Rcommand::set_debug(0) ;     # turn on debugging
Moxad::Rcommand::set_debug_fd(2) ;  # send debug output to stderr

my $count = 0 ;
my $errs = run_command_wait(
    $command, \@output, \@errors, \%options
) ;

foreach my $line ( @output ) {
    chomp( $line ) ;
    print "Output: $line\n" ;
}
foreach my $line ( @errors ) {
    chomp( $line ) ;
    print "Error: $line\n" ;
}
exit 0 ;
