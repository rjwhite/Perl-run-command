# routines to run an external command
#   run_command      - handle stdin/stderr in different ways
#   run_command_wait - run a command with sleep ALARM timer in case of hang
#   set_debug        - turn debug on or off
#   set_debug_fd     - set where to send debug out to (stdout or stderr)


package Moxad::Rcommand ;

use strict ;
use warnings ;
use version ; our $VERSION = qv('0.0.1') ;
use POSIX ":sys_wait_h";

use Exporter ;
our @ISA = qw( Exporter ) ;

# make some useful labels available for the action for run_command
our @EXPORT = qw( $STDOUT_ONLY $STDIN_AND_STDOUT_TOGETHER
                  $STDIN_AND_STDOUT_SEPARATE ) ;
our @EXPORT_OK = qw( run_command run_command_wait
                  set_debug set_debug_fd ) ;
                  

our $STDOUT_ONLY               = 0 ;
our $STDIN_AND_STDOUT_TOGETHER = 1 ;
our $STDIN_AND_STDOUT_SEPARATE = 2 ;

# globals
my $G_dbg_flag = 0 ;        # set by set_debug()
my $G_dbg_fd   = 1 ;        # stdout


# Run a external command 
# handle stdout and stderr depending on action argument.
# Normally you'd want action (arg 1) set to '2' to separate stdout
# and stderr, unless you require performance and want to avoid
# a (Bourne) sub-shell and a 'sed' process being launched
#
# Arguments:
#   1:  action:
#       0 or undefined - stdout only
#       1 - return stdout and stderr in output array
#       2 - separate stdout and stderr between output and error arrays
#   2:  command to run
#   3:  ARRAY reference to output
#   4:  ARRAY reference to error messages (if action = 2)
# Returns:
#   number (lines of) errors if action == 2

sub run_command {
    my $action      = shift ;
    my $command     = shift ;
    my $stdout_ref  = shift ;
    my $stderr_ref  = shift ;

    my $num_errs = 0 ;
    my $i_am = (caller(0))[3];

    $action = $STDIN_AND_STDOUT_SEPARATE if ( not defined( $action )) ;

    # argument checking
    if ( $action !~ /^\d$/ ) {
        die( "$i_am: arg 1: not an integer\n" ) ;
    }
    if (( not defined( $command )) or ( $command eq "" )) {
        die( "$i_am: arg 2: is undefined or empty string\n" ) ;
    }
    if (( ref( $stdout_ref ) eq "" ) or ( ref( $stdout_ref ) ne "ARRAY" )) {
        die( "$i_am: arg 3: not an ARRAY reference\n" ) ;
    }
    if ( $action == $STDIN_AND_STDOUT_SEPARATE ) {
        if (( ref( $stderr_ref ) eq "" ) or ( ref( $stderr_ref ) ne "ARRAY" )) {
            die( "$i_am: arg 4: not an ARRAY reference\n" ) ;
        }
    }

    if (( not defined( $action )) or ( $action == $STDOUT_ONLY )) {
        # throw away stderr
        @${stdout_ref} = `$command 2>/dev/null` ;
    } elsif ( $action == $STDIN_AND_STDOUT_TOGETHER ) {
        # collect both stdout and stderr
        @${stdout_ref} = `$command 2>&1` ;
    } elsif ( $action == $STDIN_AND_STDOUT_SEPARATE ) {
        my $fd ;
        open( $fd, "( $command | sed 's/^/STDOUT:/' ) 2>&1 |" ) ;

        while ( my $line = <$fd> ) {
            chomp( $line ) ;
            if ( $line =~ s/^STDOUT:// )  {
                push( @{$stdout_ref}, $line ) ;
            } else {
                $num_errs++ ;

                # If there was only a error message, we may now have 
                # 'STDOUT:' at the end of our line.  Get rid of it.

                $line =~ s/STDOUT:$// ;
                push( @{$stderr_ref}, $line ) ;
            }
        }
        close( $fd ) ;
    } else {
        die( "$i_am: action (arg 1) invalid: \'$action\'\n" ) ;
    }

    return( $num_errs ) ;
}


# Run a program that could potentially hang and set timer alarm
#
# Arguments:
#   1:  command to run
#   2:  reference to array of output (both stdout and stderr combined)
#   3:  reference to array of errors
#   4:  optional reference to options hash
#           sleep = number
# Returns (parent):
#   0:  ok
#   1:  not-ok
# Globals:
#   $G_dbg_flag

sub run_command_wait {
    my $cmd         = shift ;
    my $output_ref  = shift ;
    my $error_ref   = shift ;
    my $options_ref = shift ;

    my $sleep    = 10 ;
    my %children = () ;
    my $i_am     = (caller(0))[3];

    # argument checking
    if (( not defined( $cmd )) or ( $cmd eq "" )) {
        die( "$i_am: arg 1 (command) is undefined or empty string" ) ;
    }
    if (( ref( $output_ref ) eq "" ) or ( ref( $output_ref ) ne "ARRAY" )) {
        die( "$i_am: arg 2 (output) is not an ARRAY reference\n" ) ;
    }
    if (( ref( $error_ref ) eq "" ) or ( ref( $error_ref ) ne "ARRAY" )) {
        die( "$i_am: arg 3 (errors) is not an ARRAY reference\n" ) ;
    }

    # check for any options
    if ( defined( $options_ref ) and ( ref( $options_ref ) eq "HASH" )) {
        my $val = ${$options_ref}{ 'sleep' } ;
        if ( defined( $val ) and ( $val =~ /^\d+$/ )) {
            $sleep = $val ;
        }
    }
    dprint( "${i_am}: sleep timer set to $sleep seconds" ) ;
    
    # set up a pipe
    if ( ! pipe( READER, WRITER )) {
        push( @{$error_ref}, "$i_am: $!" ) ;
        return(1) ;
    }

    local $SIG{ CHLD } = sub {
        # don't change $! and $? outside handler
        local ($!, $?);
        while (( my $pid = waitpid(-1, WNOHANG)) > 0) {
            last if ( $pid == -1 ) ;
            delete( $children{ $pid } ) if ( defined ( $children{ $pid } )) ;
        }
    };

    # fork off a child to run the command
    my $child = fork() ;
    if ( not defined( $child )) {
        push( @{$error_ref}, "$i_am: $!" ) ;
        return(1) ;
    }

    if ( $child ) {
        # I am the parent
        dprint( "${i_am}: I am parent ($$), child = $child" ) ;

        $children{ $child } = 1 ;
        close( WRITER ) ;

        # set up our timeout
        eval {
            local $SIG{ALRM} = sub { die "alarm\n" };  # \n required
            alarm( $sleep ) ;
            while ( <READER> ) {
                push( @{$output_ref}, $_ ) ;
            }
            alarm(0) ;  # clear alarm
        };
        if ( $@ ) {
            if ( $@ ne "alarm\n" ) {
                push( @{$error_ref}, "$i_am: got unexpected sigALARM: $@" ) ;
                return(1) ;
            }
            # timed out
            my $msg = "Got a timeout after $sleep seconds for PID $child. " .
                "Command: \'$cmd\'" ;
            dprint( "${i_am}: ${msg}" ) ;
            push( @{$error_ref}, "$i_am: $msg" ) ;

            kill( 'HUP', $child  );

            dprint( "${i_am}: Sent sigHUP to PID $child" ) ;
            return(1) ;
        }

        dprint( "${i_am}: parent: DONE ok" ) ;
        return(0) ;

    } else {
        # I am the child 
        my $parent = getppid() ;
        dprint( "${i_am}: I am child ($$): parent = $parent" ) ;
        dprint( "${i_am}: child($$): doing exec of \'$cmd\'" ) ;

        # We want STDIN and STDERR to go to the pipe
        close READER ;
        open STDOUT, ">&", \*WRITER or die( "$i_am: $!" ) ;
        open STDERR, ">&", \*WRITER or die( "$i_am: $!" ) ;

        select STDOUT; $| = 1 ;  # make unbuffered
        select STDERR; $| = 1 ;

        exec( $cmd ) or die( "$i_am: exec failed for \'$cmd\'\n" ) ;
        # we don't return from this.
    }
}


# turn debugging for the module on or off
# Arguments:
#   1:  non-0 or case-insensitive 'yes' will turn on
# Returns:
#   old value
# Globals:
#   $G_dbg_flag

sub set_debug {
    my $flag = shift ;

    my $old_value = $G_dbg_flag ;

    if ( $flag =~ /^\d$/ ) {
        $G_dbg_flag = $flag ;
    } else {
        $G_dbg_flag = 1 if ( $flag =~ /^yes$/i ) ;
    }
    return( $old_value ) ;
}

# set where debugging output set to
# anything other than value of 2 (sdterr) will be considered stdout
# Arguments:
#   1:  1=stdout (default), 2=stderr
# Returns:
#   old value
# Globals:
#   $G_dbg_flag
#   $G_dbg_db

sub set_debug_fd {
    my $fd = shift ;

    my $old_value = $G_dbg_fd ;

    $fd = 1 if ( not defined( $fd )) ;
    if ( $fd eq "2" ) {
        $G_dbg_fd = 2 ;
    } else {
        $G_dbg_fd = 1 ;     
    }
    return( $G_dbg_fd ) ;
}



# internal debug print.
sub dprint {
    my $msg     = shift ;

    return(0) if ( ! $G_dbg_flag ) ;

    if ( $G_dbg_fd == 2 ) {
        print STDERR "Debug: $msg\n" ;
    } else {
        print "Debug: $msg\n" ;
    }
    return(0) ;
}

1;
