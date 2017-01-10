#!/usr/bin/env perl
# Force an early ALARM termination

use lib "/usr/local/lib" ;
use Moxad::Rcommand qw( run_command_wait $STDIN_AND_STDOUT_SEPARATE ) ;
use strict ;
use warnings ;

my @output = () ;
my @errors = () ;
my $command = "sleep 25" ;
my %options = (
    'timeout'  => 3,   
    'stderr'   => $STDIN_AND_STDOUT_SEPARATE,
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
        print STDERR "Error: $line\n" ;
    }
}
exit 0 ;
