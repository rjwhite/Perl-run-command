#!/usr/bin/env perl
# Force a early ALARM termination

use lib "/usr/local/lib" ;
use Moxad::Rcommand qw( run_command_wait ) ;
use strict ;
use warnings ;

my @output = () ;
my @errors = () ;
my $command = "sleep 25" ;
my %options = (
    'sleep' => 3,   
    'stderr => 2,       # separate stdout and stderr
) ;

Moxad::Rcommand::set_debug(1) ;     # turn on debugging
Moxad::Rcommand::set_debug_fd(2) ;  # send debug output to stderr

my $errs = run_command_wait(
    $command, \@output, \@errors, \%options
) ;

# no output in this (sleep) example - ignore @output

if ( $errs ) {
    foreach my $line ( @errors ) {
        chomp( $line ) ;
        print "Error: $line\n" ;
    }
}
exit 0 ;
