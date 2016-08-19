# Perl functions to run shell commands

## Description
This module is a set of non-OOP Perl functions to handle running a shell
command.

### Functions
- run_command()
- run_command_wait()
- set_debug()
- set_debug_fd()

***run_command()***  allows you to specify how you want STDOUT and STDERR handled.
By default, they are separated and returned in two different arrays.  However,
this requires a (Bourne) sub-shell and a sed process to be launched.  This is 
fine if system overhead is not a concern.  However, if it is, you could instead
specify to return STDOUT and STDERR together, or to only return STDOUT and ignore
STDERR.

***run_command_wait()*** is used when you are calling a program known to be unstable
that could potentially hang, and it is vital that your program does not hang.  This
forks off a child process to run the command, while a ALARM signal is set up to
signal after some number of seconds (which can be changed).  The parent can check 
the return status to see if the child finished normally, or if it didn't, any
error messages are returned.

***set_debug()*** is used to get debugging output from the module.

***set_debug_fd()*** is used to set where debug output goes - stdout by default

## Code example
    #!/usr/bin/env perl
    # Force an early ALARM termination
    
    use lib "/usr/local/lib" ;
    use Moxad::Rcommand qw( run_command_wait ) ;
    use strict ;
    use warnings ;
    
    my @output = () ;
    my @errors = () ;
    my $command = "sleep 25" ;
    my %options = (
        'sleep' => 5,   
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

## Output from code example
    Debug: Moxad::Rcommand::run_command_wait: sleep timer set to 5 seconds
    Debug: Moxad::Rcommand::run_command_wait: I am parent (11761), child = 11762
    Debug: Moxad::Rcommand::run_command_wait: I am child (11762): parent = 11761
    Debug: Moxad::Rcommand::run_command_wait: child(11762): doing exec of 'sleep 25'
    Debug: Moxad::Rcommand::run_command_wait: Got a timeout after 5 seconds for PID 11762. Command: 'sleep 25'
    Debug: Moxad::Rcommand::run_command_wait: Sent sigHUP to PID 11762
    Error: Moxad::Rcommand::run_command_wait: Got a timeout after 5 seconds for PID 11762. Command: 'sleep 25'
