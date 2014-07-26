#!/usr/bin/perl -w
#
#   createuser.pl
#
use strict;
use warnings;
use diagnostics;

use Data::Dumper;   #usage:  print Dumper($anyvariable, @another, %andanother);

use FindBin qw($RealDir);
my $home_path = $RealDir;
# optionally, if in a *nix /bin folder, assume home is parent
$home_path =~ s{/bin$}{};

use File::Path qw(mkpath);  #warning: newer version of File::Path renames this as qw(make_path)
use File::Basename qw(dirname);
use File::Spec;

# add local lib folder to perl library include search path
push(@INC, File::Spec->catdir($home_path, 'lib'));
push(@INC, $home_path);

require 'util.pl';
require 'logging.pl';

use JSON;

use Getopt::Long;

my $FALSE = 0;
my $TRUE  = 1;

my $INFO_FILENAME = '_info.js';


my $settings;
{
    #
    # read application configuration
    #
    my $config_path = $ENV{'SUBSIFT_CONFIG'} || File::Spec->catdir($home_path, 'config');
    $settings = _load_and_run(File::Spec->catfile($config_path, 'settings.pl'), 'settings', $home_path, $config_path);
    set_settings($settings);
}

#
# parse and validate command line arguments
#

my ($user_id, $email, $mode, $description, $token, $amend, $help);
GetOptions(
    'user_id=s' => \$user_id,
    'email=s' => \$email,
    'mode=s' => \$mode,
    'description=s' => \$description,
    'token=s' => \$token,
    'amend' => \$amend,
    'help' => \$help,
);

# display usage message and quit if requested or if missing args
if (defined $help || !defined $user_id) {
    my $tool = File::Basename::basename($0);
    print STDERR <<"__";
Creates a new user account for the SubSift REST API.

Usage:
    $tool REQUIRED [OPTIONS]

Required:
    -u, --user_id          user_id (lower case letters and numbers only)
    -e, --email            user's email address

Options:
    -m, --mode             private | public (default: private)
    -d, --description      optional description, e.g. user's name
    -t, --token            specify authorization token string, or '?' for <random> (default: <random>)
    -a, --amend            amend an existing user's info (user_id must already exist)
    -h, --help             display this help message

Use "sudo -u <webuser> createuser.pl ..." to ensure <webuser> has write access to the created user folder.
__
    exit;
}

# validate userid
if (!defined $user_id || $user_id !~ m/^[a-z][a-z\d_]*$/) {
    print STDERR "Invalid user_id. Must be lower cases letters and numbers only.\n";
    exit;
}

# validate amend (or assign a default if missing)
if (!defined $amend || (defined $amend && $amend ne '1')) {
    $amend = 0;
}

#FIXME: this test doesn't work (need to find proper way to test we can write or maybe just try/catch)
#if (!-w $settings->{'USERS_PATH'}) {
#    print STDERR "Folder '$settings->{'USERS_PATH'}' is not writable by the effective user.\n";
#    exit;
#}

my $user_path = File::Spec->catdir($settings->{'USERS_PATH'}, $user_id);
my $user_info_file = File::Spec->catfile($user_path, $INFO_FILENAME);
# if amend specified, then try to use existing user info as defaults
my %info = ();
my $user_info = \%info;
if ($amend) {
    if (-d $user_path) {
        if (-f $user_info_file) {
            $user_info = JSON->new->decode( util_readFile($user_info_file) );
        }
    }
    else {
        print STDERR "User does not exist. Can only amend an existing user.\n";
        exit;
    }
}
else {
    # create user folder if id is not already taken
    if (-d $user_path) {
        print STDERR "User id already exists.\n";
        exit;
    }
    else {
        File::Path::mkpath($user_path);
    }
}

# validate email
$email =  $email || $user_info->{'email'};
if (!defined $email) {
    print STDERR "Missing email address.\n";
    exit;
}

# validate mode
if (!defined $mode) {
    $mode = $user_info->{'mode'} || 'private';
}
else {
    if ($mode ne 'public' && $mode ne 'private') {
        print STDERR "Mode, if specified, must be either 'public' or 'private' (default is 'private').\n";
        exit;
    }
}

# get description (or assign a default if missing)
$description = $description || $user_info->{'description'} || '';

# validate description (or assign a default if missing)
$token = $token || $user_info->{'token'} || '?';
if ($token eq '?') {
    $token = Digest::SHA1::sha1_hex(time . rand());
}


# create info hash which will be serialised to user info file
my $modified = time;
my $created = $user_info->{'created'} || $modified;
%info = (
    'email'         => $email,
    'token'         => $token,
    'mode'          => $mode,
    'description'   => $description,
    'created'       => $created,
    'modified'      => $modified,
);
util_writeFile($user_info_file, JSON->new->canonical->pretty->encode(\%info) );

my $resource_url = $settings->{'SITE_URL'} . '/' . $user_id . '/';
my $op = ($amend) ? 'Amended' : 'Created';
print "$op user: $user_id $token $resource_url\n";



exit;

sub _load_and_run {
    #
    # loads a perl file arg1 and calls a function arg2
    #
    my ($fname, $subname) = @_;
    shift; shift;  #consume first two args but keep rest
    my $ret = undef;
    if (-f $fname) {
        require $fname;
        no strict 'refs';
        $ret = &$subname(@_);
        use strict 'refs';
    }
    return $ret;
}

