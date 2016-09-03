# routines to run an external command
#   run_command      - handle stdin/stderr in different ways
#   run_command_wait - run a command with ALARM timer in case of hang
#   set_debug        - turn debug on or off
#   set_debug_fd     - set where to send debug out to (stdout or stderr)


package Moxad::Rcommand ;

use strict ;
use warnings ;
use version ; our $VERSION = qv('0.0.2') ;
use POSIX ":sys_wait_h" ;

use Exporter ;
our @ISA = qw( Exporter ) ;

# make some useful labels available for the action for run_command
our @EXPORT = qw( $STDOUT_ONLY $STDIN_AND_STDOUT_TOGETHER
                  $STDIN_AND_STDOUT_SEPARATE ) ;
our @EXPORT_OK = qw( run_command run_command_wait
                  set_debug set_debug_fd ) ;
                  

# we make these available to callers
our $STDOUT_ONLY               = 0 ;
our $STDIN_AND_STDOUT_TOGETHER = 1 ;
our $STDIN_AND_STDOUT_SEPARATE = 2 ;

# The child process for run_command_wait() tags lines passed back
# to the parent to let it know what type of info it really is
my $PREFIX_STDOUT = "stdout: " ;
my $PREFIX_STDERR = "stderr: " ;
my $PREFIX_DEBUG  = "debug: " ;

# globals
my $G_dbg_flag    = 0 ;     # set by set_debug()
my $G_dbg_fd      = 1 ;     # stdout

my $DEFAULT_TIMER = 30 ;    # timer for run_command_wait()

# Run a external command 
# handle stdout and stderr depending on action argument.
# Normally you'd want action (arg 1) set to '2' to separate stdout
# and stderr, unless you require performance and want to avoid
# a (Bourne) sub-shell and a 'sed' process being launched
#
# Arguments:
#   1:  action:
#       0 - stdout only
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

    dprint( "${i_am}: command = $command" ) ;

    if (( not defined( $action )) or ( $action == $STDOUT_ONLY )) {
        # throw away stderr
        dprint( "${i_am}: throwing away stderr" ) ;
        @${stdout_ref} = `$command 2>/dev/null` ;
    } elsif ( $action == $STDIN_AND_STDOUT_TOGETHER ) {
        # collect both stdout and stderr
        dprint( "${i_am}: collecting stdout and stderr together" ) ;
        @${stdout_ref} = `$command 2>&1` ;
    } elsif ( $action == $STDIN_AND_STDOUT_SEPARATE ) {
        dprint( "${i_am}: separating stdout and stderr" ) ;
        my $fd ;
        open( $fd, "( $command | sed 's/^/STDOUT:/' ) 2>&1 |" ) ;

        while ( my $line = <$fd> ) {
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
#           alarm = number
#           stderr = undef | 0 | 1 | 2    - see run_command() action
# Returns (parent):
#   number of lines sent to stderr
# Globals:
#   $G_dbg_flag

sub run_command_wait {
    my $cmd         = shift ;
    my $output_ref  = shift ;
    my $error_ref   = shift ;
    my $options_ref = shift ;

    my $alarm = $DEFAULT_TIMER ;
    my %children    = () ;
    my $i_am        = (caller(0))[3];
    my $num_errs    = 0 ;
    my $num_lines   = 0 ;
    my $stderr      = undef ;

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
        dprint( "${i_am}: got an options hash" ) ;
        # sleep timer
        my $val = ${$options_ref}{ 'alarm' } ;
        if ( defined( $val ) and ( $val =~ /^\d+$/ )) {
            $alarm = $val ;
        }

        # how to handle stderr
        # let run_command() deal with an invalid numeric value
        # just check here that it is a single digit, if so, use it
        $val = ${$options_ref}{ 'stderr' } ;
        if ( defined( $val ) and ( $val =~ /^\d$/ )) {
            $stderr = $val ;
            dprint( "${i_am}: stderr value set to $val" ) ;
        }
    }
    dprint( "${i_am}: alarm timer set to $alarm seconds" ) ;
    
    # set up a pipe
    if ( ! pipe( READER, WRITER )) {
        push( @{$error_ref}, "$i_am: $!" ) ;
        return(1) ;
    }

    local $SIG{ CHLD } = sub {
        # don't change $! and $? outside handler
        local ($!, $?);
        while (( my $pid = waitpid( -1, WNOHANG )) > 0 ) {
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

        eval {
            # set up our timeout
            local $SIG{ALRM} = sub { die "alarm\n" };  # \n required
            alarm( $alarm ) ;

            # anything that comes back should be tagged
            while ( my $line = <READER> ) {
                if ( $line =~ /^$PREFIX_STDOUT/ ) {
                    $line =~ s/^$PREFIX_STDOUT// ;
                    push( @{$output_ref}, $line ) ;
                    $num_lines++ ;
                } elsif ( $line =~ /^$PREFIX_STDERR/ ) {
                    $line =~ s/^$PREFIX_STDERR// ;
                    push( @{$error_ref}, $line ) ;
                    $num_errs++ ;
                } elsif ( $line =~ /^$PREFIX_DEBUG/ ) {
                    if ( $G_dbg_fd == 2 ) {     # stderr hack. see dprint()
                        print STDERR "$line" ;
                    } else {
                        print "$line" ;     # just print it
                    }
                } else {
                    # must be an error - like a die() from run_command()
                    push( @{$error_ref}, "$line"  ) ;
                    $num_errs++ ;
                    return( $num_errs ) ;
                }
            }

            alarm(0) ;  # clear alarm
        };
        if ( $@ ) {
            if ( $@ ne "alarm\n" ) {
                push( @{$error_ref}, "$i_am: got unexpected sigALARM: $@" ) ;
                $num_errs++ ;
                return( $num_errs ) ;
            }

            # timed out
            my $msg = "Got a timeout after $alarm seconds for PID $child." ;
            dprint( "${i_am}: ${msg}" ) ;
            push( @{$error_ref}, "$i_am: $msg" ) ;
            $num_errs++ ;

            kill( 'HUP', $child  );
            dprint( "${i_am}: Sent sigHUP to PID $child" ) ;

            return( $num_errs ) ;
        }

        dprint( "${i_am}: parent: \#stderr = $num_errs, \#stdout = $num_lines" ) ;
        return( $num_errs ) ;
    } else {
        # I am the child 
        my $parent = getppid() ;
        dprint( "${i_am}: I am child ($$): parent = $parent" ) ;
        dprint( "${i_am}: child($$): running command of \'$cmd\'" ) ;

        # We want STDIN and STDERR to go to the pipe
        close READER ;
        open STDOUT, ">&", \*WRITER or die( "$i_am: $!" ) ;
        open STDERR, ">&", \*WRITER or die( "$i_am: $!" ) ;

        select STDOUT; $| = 1 ;  # make unbuffered
        select STDERR; $| = 1 ;

        my @output = () ;
        my @errors = () ;
        my $ret = run_command( $stderr, $cmd, \@output, \@errors ) ;

        # we need a sure way to let the parent know whether it is
        # intended for stderr or stdout - so tag what we send back

        dprint( "${i_am}: child($$): got some stderr lines" ) if ( @errors ) ;
        foreach my $err ( @errors ) {
            chomp( $err ) ;
            # tag it as an error for the parent to notice
            print "${PREFIX_STDERR}${err}\n" ;   # really going through pipe
        }

        # normal stdout
        foreach my $line ( @output ) {
            chomp( $line ) ;
            # tag it as meant for stdout
            print "${PREFIX_STDOUT}${line}\n" ;  # really going to pipe
        }
        exit(0) ;
    }
}


# turn debugging for the module on or off
# Arguments:
#   1:  integer  (0=off, non-0= on)
# Returns:
#   old value
# Globals:
#   $G_dbg_flag

sub set_debug {
    my $flag = shift ;

    my $old_value = $G_dbg_flag ;

    if ( $flag =~ /^\d$/ ) {
        $G_dbg_flag = $flag ;
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
    return( $old_value ) ;
}



# internal debug print.
sub dprint {
    my $msg     = shift ;

    return(0) if ( ! $G_dbg_flag ) ;

    my $str = "${PREFIX_DEBUG}$msg\n" ;
    if ( $G_dbg_fd == 2 ) {
        print STDERR $str ;
    } else {
        print $str ;
    }
    return(0) ;
}

1;

__END__

=head1 NAME

Moxad::Rcommand - run a shell command

=head1 SYNOPSIS

use Moxad::Rcommand ;

=head1 DESCRIPTION

This module is a set of non-OOP functions that run a shell command.

One function, run_command(), allows you to better control how
any output to stderr is handled, whether it is ignored, combined
with stdout, or separated from stdout.

Another function, run_command_wait(), allows you to specify a
sleep timer to kill the command if it becomes hung.  This would be
used for a command or program that is considered unstable when
it is vital that your program does not hang.  It leverages off of
the function run_command() to still provide control over stderr.

=head1 functions

=head2 set_debug

Turn debugging on or off

 $old_value = Moxad::Rcommand->set_debug(0) ;   # off (default)
 $old_value = Moxad::Rcommand->set_debug(1) ;   # on

=head2 set_debug_fd

Set where debugging info is send (stdout or stderr)

 $old_value = Moxad::Rcommand::set_debug_fd(1) ;   # stdout
 $old_value = Moxad::Rcommand::set_debug_fd(2) ;   # stderr

=head2 run_command

run a shell command

 $num_errs = Moxad::Rcommand::run_command( $action, $command, \@stdout, \@stderr ) ;

where $action is one of:
    $STDOUT_ONLY (0)
    $STDIN_AND_STDOUT_TOGETHER (1)
    $STDIN_AND_STDOUT_SEPARATE (2)
    undef - default = 2 ($STDIN_AND_STDOUT_SEPARATE)

and $num_errs is the number of lines that are returned in the @stderr
array - which only happens if $action is $STDIN_AND_STDOUT_SEPARATE,
or if some other error occurred.

=head2 run_command_wait

run a shell command with a timer to stop(kill) the command.

 $num_errs = Moxad::Rcommand::run_command_wait( $command, \@stdout, \@stderr, \%options ) ;

where \%options has the following options:
    alarm = number (default = 30 seconds)
    stderr = undef | 0 | 1 | 2 - see $action for run_command()

and $num_errs is the number of lines that are returned in the @stderr
array - which only happens if $action is $STDIN_AND_STDOUT_SEPARATE,
or if some other error occurred.

=head1 Code sample

  #!/usr/bin/env perl
  # Force a early ALARM termination
  
  use Moxad::Rcommand qw( run_command_wait $STDIN_AND_STDOUT_SEPARATE ) ;
  use strict ;
  use warnings ;
  
  my @output = () ;
  my @errors = () ;
  my $command = "sleep 25" ;
  my %options = (
      'alarm'  => 3,     # seconds
      'stderr' => $STDIN_AND_STDOUT_SEPARATE,
  ) ;
  
  Moxad::Rcommand::set_debug(1) ;     # turn on debugging
  Moxad::Rcommand::set_debug_fd(2) ;  # send debug output to stderr
  
  my $errs = run_command_wait(
      $command, \@output, \@errors, \%options
  ) ;
  
  # no output in this (sleep) example - so ignore @output
  if ( $errs ) {
      foreach my $line ( @errors ) {
          chomp( $line ) ;
          print STDERR "Error: $line\n" ;
      }
  }

=head1 sample output with debugging turned on

  debug: Moxad::Rcommand::run_command_wait: got an options hash
  debug: Moxad::Rcommand::run_command_wait: stderr value set to 2
  debug: Moxad::Rcommand::run_command_wait: alarm timer set to 3 seconds
  debug: Moxad::Rcommand::run_command_wait: I am parent (32764), child = 32765
  debug: Moxad::Rcommand::run_command_wait: I am child (32765): parent = 32764
  debug: Moxad::Rcommand::run_command_wait: child(32765): running command of 'sleep 25'
  debug: Moxad::Rcommand::run_command: command = sleep 25
  debug: Moxad::Rcommand::run_command: separating stdout and stderr
  debug: Moxad::Rcommand::run_command_wait: Got a timeout after 3 seconds for PID 32765.
  debug: Moxad::Rcommand::run_command_wait: Sent sigHUP to PID 32765
  Error: Moxad::Rcommand::run_command_wait: Got a timeout after 3 seconds for PID 32765.
