#params.pl
use strict;
use warnings;


# IMPORTANT: we do not import CGI into the top level namespace
#            so that access to param can be securely managed
use CGI;

my $TRUE = 1;
my $FALSE = 0;



use vars qw($_Params);

sub get_params {
    return $_Params;
}
sub set_params {
    my ($value) = @_;
    $_Params = $value;
}

sub get_param {
    my ($key) = @_;
    return $_Params->{$key};
}
sub set_param {
    my ($key, $value) = @_;
    return $_Params->{$key} = $value;
}


use vars qw($_Raw_params);

sub get_raw_params {
    return $_Raw_params;
}
sub set_raw_params {
    my ($value) = @_;
    $_Raw_params = $value;
}


sub get_cgi_params {
    #
    # Create a non-tied hash copy of incoming cgi request+post parameters
    # Note:
    #   - Multiple values for same key are returned as "\0" delimited string.
    #   - Non-form encoded uploads are decoded
    #
    my $method = $ENV{'REQUEST_METHOD'} || 'GET';
    my $cgi = ($method eq 'PUT' || $method eq 'DELETE') ? CGI->new(\*STDIN) : CGI->new;

    my %copy_of_cgi_params = ();

    # check for ajax file upload using non-form encoded postdata
    my $file = $cgi->param('POSTDATA') ||  $cgi->param('PUTDATA');
    if (defined $file) {
        # postdata is a single block of data (normally from an ajax file upload)

        # postdata contains no key=value data but query string can have
        my $query_string = $ENV{'QUERY_STRING'};
        if (defined $query_string && $query_string ne '') {
            %copy_of_cgi_params = params_from_query_string($query_string);
        }
        # store the file under supplied key or with default key
        my $key = $copy_of_cgi_params{'param'} || 'file';
        $copy_of_cgi_params{$key} = $file;
    }
    else {
        # postdata is a valid params list, so process normally
        foreach my $k ($cgi->param) {
            # handle uploaded files by storing file data as a normal key=>value pair
            my $lightweight_fh = $cgi->upload($k);
            if (defined $lightweight_fh) {
                # upgrade handle to one compatible with IO::Handle
                my $io_handle = $lightweight_fh->handle;
                # read uploaded file into a string and store under key $k
                my $s = '';
                my $buffer = '';
                while (my $bytesread = $io_handle->read($buffer,1024)) {
                    $s += $buffer;
                }
                #FIXME: assumes not too big for memory, so ought to set $CGI::POST_MAX = X or at least check $ENV{'CONTENT_LENGTH'}
                $copy_of_cgi_params{$k} = $s;
            }
            else {
                # just an ordinary key=value (or possibly an array of them if multiple)
                $copy_of_cgi_params{$k} = join("\0", $cgi->param($k));
            }
        }
    }
    return \%copy_of_cgi_params;
}

sub has_multiple_values {
    #
    # returns true if string is "\0" delimited
    #
    my ($str) = @_;
    return (index($str, "\0") < 0) ? $FALSE : $TRUE;
}

sub get_value {
    #
    # returns first value in possibly multiple value "\0" delimited string
    #
    my ($str) = @_;
    my $ix = index($str, "\0");
    return ($ix < 0) ? $str : substr($str, 0, $ix);
}

sub get_values {
    #
    # returns array_ref of all values in possibly multiple value "\0" delimited string
    #
    my ($str) = @_;
    return split("\0", $str);
}

sub params_from_query_string{
    #
    # returns hash of key=>value pairs from query string passed in
    #
	my ($str) = @_;
	my @pairs = split(/&/, $str);
	my %params = ();
	foreach my $pair (@pairs){
		my ($key, $value) = split(/=/, $pair);
		$key =~ tr/+/ /;
		$key =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack('C', hex($1))/eg;
		$value =~ tr/+/ /;
		$value =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack('C', hex($1))/eg;
		$params{$key} = $value;
	}
	return %params;
}


#
# XForms inspired data model checker
#

my %MODEL_DEFAULTS = (
    type        => 'STR',
    default     => '',
    values      => '',
    required    => $TRUE,
    minlength   => 0,
    maxlength   => 32*1024,     #32K
    minvalue    => undef,       #varies according to type
    maxvalue    => undef,       #varies according to type
    severity    => 'ERROR',
);      
my %MODEL_MINVALUES = (
    BOOL    => $FALSE,
    INT2    => 0x8000,
    INT     => 0x80000000,
    INT4    => 0x80000000,
#    INT8    => 0x8000000000000000,     #requires perl compiled with 64bit word size
    NUM     => -2**63,
    STR     => 0,
);
my %MODEL_MAXVALUES = (
    BOOL    => $TRUE,
    INT2    => 0x7FFF,
    INT     => 0x7FFFFFFF,
    INT4    => 0x7FFFFFFF,
#    INT8    => 0x7FFFFFFFFFFFFFFF,     #requires perl compiled with 64bit word size
    NUM     => 2**63-1,
    STR     => 1,
);

sub params_model {
    #
    # BOOL params_model(HASHREF $params, STRING $id, HASHREF $arg_ref)
    #
    # validator for $params->{$id} with defaulting and error controls
    # inspired by XForms data model checking
    #
    # if validated according to $arg_ref, returns $params->{$id}
    # if invalid and severity=ERROR then throws error else returns ''
    #
    # $params:  values to be validated (typically having come from a cgi param)
    # $id:      key into $params
    # $arg_ref: key=>value pairs...
    #
    #   type        => BOOL|INT|INT2|INT4|INT8|NUM|STR
    #                  expected type of $value
    #   default     => <value> of type $arg_ref->{type}
    #                  value to be used if param value is missing
    #   values      => <STR>
    #                  |-delimited string of legal values for $value
    #                  e.g. 'delete|insert|replace'
    #   required    => <BOOL>
    #                  whether this parameter is mandatory or optional
    #   minlength   => <NAT>
    #   maxlength   => <NAT>
    #                  min/max lengths when type is STR
    #   minvalue    => <NUM>
    #   maxvalue    => <NUM>
    #                  min/max value when type is NUM
    #   severity    => IGNORE|WARN|ERROR
    #                  silent means force to legal value and ignore;
    #                  warn means just log and continue if a problem;
    #                  error means log and abort execution immediately
    #
    my ($params, $id, $arg_ref) = @_;

    # reset error message string to none
    set_params_error(undef);

    # unpack optional arguments and set defaults
    my %arg = (ref $arg_ref eq 'HASH') ? (%MODEL_DEFAULTS, %{$arg_ref})
                                       :  %MODEL_DEFAULTS;

    # validate the %arg model parameters and settings themselves (ie. detect usage errors)

    my $type      = $arg{type};
    #FIXME: INT8 requires a 64bit Perl
    die $id . ' - invalid INT8 requires Perl compiled with 64bit word' if ($type eq 'INT8');
    die $id . ' - invalid params_model: type must be BOOL|INT|INT2|INT4|INT8|NUM|STR' if (!params_any($type, 'BOOL|INT|INT2|INT4|INT8|NUM|STR'));

    my $default   = $arg{default};

    my $values    = $arg{values};

    my $required  = $arg{required};
    die $id . ' - invalid params_model: required must be 0|1' if (!params_any($required, '0|1'));

    my $minlength = $arg{minlength};
    my $maxlength = $arg{maxlength};
    die $id . ' - invalid params_model: minlength and maxlength must be numbers' if (
           !params_isNat($minlength)
        || !params_isNat($maxlength)
    );
    die $id . ' - invalid params_model: minlength must greater than or equal to zero and less than maxlength' if (
           $minlength < 0
        || $minlength > $maxlength
    );

    my $minvalue  = (defined $arg{minvalue}) ? $arg{minvalue}
                                             : $MODEL_MINVALUES{$type};
    my $maxvalue  = (defined $arg{maxvalue}) ? $arg{maxvalue}
                                             : $MODEL_MAXVALUES{$type};
    if ($type eq 'NUM') {
        die $id . ' - invalid params_model: minvalue and maxvalue must be reals' if (
               !params_isReal($minvalue)
            || !params_isReal($maxvalue)
        );
    }
    else {
        die $id . ' - invalid params_model: minvalue and maxvalue must be integers' if (
               !params_isInt($minvalue)
            || !params_isInt($maxvalue)
        );
    }
    die $id . ' - invalid params_model: minvalue must be less than maxvalue' if ($minvalue > $maxvalue);

    my $severity = $arg{severity};
    die $id . ' - invalid params_model: severity must be one of IGNORE|WARN|ERROR' if (!params_any($severity, 'IGNORE|WARN|ERROR'));

    #
    # validate value from $params hash
    #
    
    my $value = $params->{$id};
    my $errmess = '';

    if (!defined $value) {
        $errmess = 'missing value' if ($required);
        # must assign default value even if there was an error
        $value = $default;
    }

    if (!$errmess) {

        $errmess = "not one of $values" if ($values ne '' && !params_any($value, $values));

        if    ($type eq 'STR') {
            my $len = length($value);
            $errmess = "string too short (<$minlength)" if ($len < $minlength);
            $errmess = "string too long (>$maxlength)"  if ($len > $maxlength);
        }
        elsif ($type eq 'BOOL') {
            $errmess = 'boolean not 0|1' if (!params_any($value, '0|1'));
        }
        else {
            # numeric types
            if ($type eq 'NUM') {
                $errmess = 'invalid real' if (!params_isReal($value));
            }
            else {
                $errmess = 'invalid integer' if (!params_isInt($value));
            }
            if (!$errmess) {
                $errmess = "number too small (<$minvalue)" if ($value < $minvalue);
                $errmess = "number too long (>$maxvalue)"  if ($value > $maxvalue);
            }
        }
    }

    if ($errmess ne '') {
        
        # make the error message available via get_params_error
        set_params_error("Invalid $id - $errmess");
        
        if    ($severity eq 'WARN') {
            print STDERR "WARN: params warning - $errmess: '$id'";
        }
        elsif ($severity eq 'ERROR') {
            die "ERROR: params error - $errmess: '$id'";
        }
        # revert to default (will be '' if none supplied)
        $value = $default;
    }

    return $value;
}

# string type checking for numeric types
sub params_isNat {
    my ($str) = @_;
    return (defined $str && $str =~ /^\d+$/);
}
sub params_isInt {
    my ($str) = @_;
    return (defined $str && $str =~ /^[+-]?\d+$/);
}
sub params_isReal {
    my ($str) = @_;
    return (defined $str && $str =~ /^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]\d+)?$/);
}

sub params_any {
    #
    # fast running and simple membership predicate that
    # checks if $value is in "|" delimited string of $possiblevalues
    # e.g. if params_any($str, 'IGNORE|WARN|ERROR') ...
    #
    my ($value, $possiblevalues) = @_;
    return (index("|${possiblevalues}|", "|${value}|") < 0) ? 0 : 1;
}


# error message string or undef if no error
use vars qw($_Params_error);

sub get_params_error {
    return $_Params_error;
}

sub set_params_error {
    my ($value) = @_;
    $_Params_error = $value;
}

1;
