# auth.pl
use strict;
use warnings;

use CGI qw/:standard/;
use CGI::Cookie;

use Digest::SHA1 qw(sha1_hex);

require 'render.pl';    #for access to get/set_global_headers

my $FALSE = 0;
my $TRUE  = 1;

my $INFO_FILENAME = '_info.js';

my $PSEUDO_PARAM_NAME = 'AUTHENTICATED';



sub authenticate {
    my ($settings, $params) = @_;

    # create a pseudo parameter for efficient subsequent checks in same response
    $params->{$PSEUDO_PARAM_NAME} = $FALSE;
    # clear out global copy of user_info hash
    set_user_info(undef);

    # can only apply authorization checks to user namespaces
    if (!exists $params->{'user_id'} || !defined $params->{'user_id'}) {
        return $FALSE;
    }
    my $user_id = $params->{'user_id'};

    # get expected token value from user folder's info file
    my $user_path = File::Spec->catdir($settings->{'USERS_PATH'}, $user_id);
    if (!-d $user_path) {
        # no such path
        warn_message("auth - no user path: $user_path");
        return $FALSE;
    }
    my $user_info_file = File::Spec->catfile($user_path, $INFO_FILENAME);
    if (!-f $user_info_file) {
        # no such file
        warn_message("auth - no user info file: $user_info_file");
        return $FALSE;
    }
    my $user_info = JSON->new->decode( util_readFile($user_info_file) );

    # make user_info available via global accessor
    set_user_info($user_info);

    # first look for token as a cookie and then in http header
    my %cookies = fetch CGI::Cookie;
    my $token;
    if (exists $ENV{'HTTP_TOKEN'} && defined $ENV{'HTTP_TOKEN'} && $ENV{'HTTP_TOKEN'} ne '') {
        # retrieve "Token:" value from HTTP request header
        $token = $ENV{'HTTP_TOKEN'};
    }
    else {
        if (exists $cookies{'TOKEN'}) {
            # use cookie instead of http header
            $token = $cookies{'TOKEN'}->value;
        }
    }

    # check for empty token
    if (!defined $token || $token eq '') {
        my $method = get_request_method();
        if ($method ne 'get' && $method ne 'head') {
            warn_message("auth - no token submitted for user: $user_id");
        }
        return $FALSE;
    }

    # compare token from HTTP request against user info token
    if ($token ne $user_info->{'token'}) {
        warn_message("auth - token mismatch for user: $user_id");
        return $FALSE;
    }
    
    # add token cookie to all headers written by render()
    my $headers = get_global_headers();
    if (!defined $headers) {
        my %emptyhash = ();
        $headers = \%emptyhash;
    }
    my $c = new CGI::Cookie(
        -name    =>  'TOKEN',
        -value   =>  $token,
        -expires =>  '+3M'
    );
    $headers->{'Set-Cookie'} = $c;
    set_global_headers($headers);
    
    # set pseudo parameter for efficient subsequent checks in same response
    $params->{$PSEUDO_PARAM_NAME} = $TRUE;

    # user authenticated
    return $TRUE;
}


sub is_authenticated {
    my ($settings, $params) = @_;

    if (exists $params->{$PSEUDO_PARAM_NAME}) {
        return $params->{$PSEUDO_PARAM_NAME};
    }
    return authenticate($settings, $params);
}


sub error_unless_authenticated {
    my ($settings, $params) = @_;

    if (!exists $params->{'user_id'} || !defined $params->{'user_id'}) {
        # error in software/site design and authorisation was called without a user_id
        error_message("error_unless_authenticated - insisting on a user_id in a context where there is not one");
        # try and do something sensible for the caller
        render({
            'status' => '401 Unauthorized',
            'text'   => serialise_error_message('Not authorized'),
        });
    }

    if (!is_authenticated($settings, $params)) {
        render({
            'status' => '401 Unauthorized',
            'text'   => serialise_error_message("Not authorized for $params->{'user_id'}"),
        });
    }
}


use vars qw($_User_info);

sub get_user_info {
    return $_User_info;
}

sub set_user_info {
    my ($value) = @_;
    $_User_info = $value;
}

1;
