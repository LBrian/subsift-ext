# logging.pl
use strict;
use warnings;

use vars qw($_Log_level %LOG_LEVEL @LOG_LEVEL);

%LOG_LEVEL = ('NONE'=>0, 'ERROR'=>1, 'WARN'=>2, 'INFO'=>3, 'DEBUG'=>4);
@LOG_LEVEL = ('NONE', 'ERROR', 'WARN', 'INFO', 'DEBUG');;

# Note: unwise to rely on this default under mod_perl (your program should set explicitly)
$_Log_level = $LOG_LEVEL{'WARN'};

sub get_current_log_level {
    #
    #   INT get_current_log_level()
    #
    return $_Log_level;
}

sub set_current_log_level {
    #
    #   INT set_current_log_level(INT $level)
    #   INT set_current_log_level(STRING $level)
    #
    #   Sets types of messages recorded by logging.
    #   $level must be a key or value from %LOG_LEVELS
    #
    my ($level) = @_;
    if ($level =~ /^\d$/xms && $level <= $#LOG_LEVEL) {
        $_Log_level =  $level;
    }
    else {
        $_Log_level =  $LOG_LEVEL{$level};
        if (!defined $_Log_level) {
            die "Invalid log level: $level\n";
        }
    }
    return $_Log_level;
}

sub log_level {
    #
    #   INT log_level(STRING $key)
    #
    my ($key) = @_;
    return $LOG_LEVEL{$key};
}

sub error_message { _message(1, @_); }
sub warn_message  { _message(2, @_); }
sub info_message  { _message(3, @_); }
sub debug_message { _message(4, @_); }


sub _message {
    #
    #   message(INT $level, $value, [$value, ...])
    #
    #   Writes an error message to STDERR where the message is constructed from
    #   the level and a concatenation of all subsequent arguments.
    #
    my $level = shift;
    if (get_current_log_level() >= $level) {
        my $str = $LOG_LEVEL[$level] . ': ' . join(' ', @_) . "\n";
        my $logfile = (defined &get_setting) ? get_setting('ACCESS_LOG') : undef;
        if (defined $logfile && $logfile ne '') {
            util_appendFile($logfile, gmtime(time) . "\t" . $str);
        }
        else {
            print STDERR $str;
        }
    }
    return;
}

   
1;
