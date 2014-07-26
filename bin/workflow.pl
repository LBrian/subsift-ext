#!/usr/bin/perl -w
#
#   workflow.pl
#
use strict;
use warnings;
use diagnostics;

my $start_time = time;

# only enact for a maximum of N seconds (because running via cron)
##FIXME: move out to config so can adjust on per platform basis to suit cron interval
my $EXECUTION_TIMEOUT = 9*60;

use FindBin qw($RealDir);
my $home_path = $RealDir;
# optionally, if in a *nix /bin folder, assume home is parent
$home_path =~ s{/bin$}{};

use File::Path qw(mkpath rmtree);  #warning: newer version of File::Path renames these as qw(make_path remove_tree)
use File::Basename qw(dirname);
use File::Spec;

use File::Glob ':glob';

#use Encode;
#require Encode::Detect;

# module for pretty printing perl variables [for debugging]
use Data::Dumper;   #usage:  print Dumper($anyvariable, @another, %andanother);

# add local lib folder to perl library include search path
push(@INC, File::Spec->catdir($home_path, 'lib'));
push(@INC, $home_path);

require 'util.pl';
require 'logging.pl';

use JSON;

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
}
# make available to lib/*.pl files
set_settings($settings);


# poll all user workflows looking for specially named files requesting an http get of a url
my $filespec = File::Spec->catdir($settings->{'USERS_PATH'}, '*', 'workflows', '*.json');
my @files = bsd_glob($filespec);
LP_WORKFLOW:
for my $workflow_file (@files) {


    # for logging we remove the site url stem to create relative urls
    my $relative_workflow_file = substr($workflow_file, length($settings->{'USERS_PATH'})+1);

    #
    # load user info and retrieve auth token
    #
    my $user_path = File::Basename::dirname($workflow_file);
    # strip off /workflows to obtain parent folder
    $user_path =~ s{[\\/]workflows$}{}gxsm;
    # the id of a user is their folder name (user_id is not stored in user_info)
    my $user_id = File::Basename::basename($user_path);
    # load user metadata
    my $user_info_file = File::Spec->catfile($user_path, $INFO_FILENAME);
    if (!-f $user_info_file) {
        _workflow_log('FAIL', $relative_workflow_file, "0", "No user info file found");
        # as a failsafe, remove troublesome workflow
        unlink $workflow_file;
        next LP_WORKFLOW;
    }
    my $user_info = JSON->new->decode( util_readFile($user_info_file) );
    my $token = $user_info->{'token'};

    my $workflow = _load_workflow($workflow_file);
    if (!defined $workflow) {
        _workflow_log('FAIL', $relative_workflow_file, "0", "Unable to load workflow");
        # as a failsafe, remove any empty workflow files so we don't keep reparsing them
        unlink $workflow_file;
        next LP_WORKFLOW;
    }

    # retrieve array of commands and current index into the array
    my $commands      = $workflow->{'workflow'}{'command'};
    my $current_index = $workflow->{'workflow'}{'current_index'};  #note: not zero-based; is actually line no.s

    if (!defined $commands || scalar(@$commands) == 0 || 
        !defined $current_index || $current_index < 1 || $current_index > scalar(@$commands)) {
        _workflow_log('FAIL', $relative_workflow_file, "0", "Invalid workflow");
        # as a failsafe, remove any empty or completed workflow files so we don't keep reparsing them
        unlink $workflow_file;
        next LP_WORKFLOW;
    }

    #
    # attempt to execute commands specified in the workflow
    #
    LP_COMMAND:
    while ($current_index <=  scalar(@$commands)) {

        # only execute for a maximum of N seconds (because running via cron)
        if ((time - $start_time) > $EXECUTION_TIMEOUT) {
            last LP_WORKFLOW;
        }
        
        # get and validate the current command
        my $command = $commands->[$current_index - 1];
        my $valid = $TRUE;
        if ($command->{'flow'} !~ m{^[\+\-\?\*]$}xsm) {
            _workflow_log('FAIL', $relative_workflow_file, $current_index, $command->{'flow'});
            $valid = $FALSE;
        }
        if ($command->{'method'} !~ m{^(get|delete|head|post|put)$}xsm) {
            _workflow_log('FAIL', $relative_workflow_file, $current_index, $command->{'method'});
            $valid = $FALSE;
        }
        # security: remove up-path ".." strings from path and then check not an absolute url
        $command->{'url'} =~ s{\.\.}{}gxsm;
        # strip off leading slashes
        $command->{'url'} =~ s{^/+}{}gxsm;
        if ($command->{'url'} =~ m{^\s*(http|ftp|mailto)}xsm) {
            _workflow_log('FAIL', $relative_workflow_file, $current_index, $command->{'url'});
            $valid = $FALSE;
        }
        if (!$valid) {
            # remove this invalid workflow file
            unlink $workflow_file;
            next LP_WORKFLOW;
        }
        
        # log the attempt to execute command
        {
            my $paramstr = '';
            foreach my $key (keys %{$command->{'parameters'}}) {
                $paramstr .= $key . '=' . $command->{'parameters'}{$key} . '&'
            }
            $paramstr =~ s/\&$//gxsm;
            _workflow_log('GET', $relative_workflow_file, $current_index, 
                $command->{'flow'} . ', ' . $command->{'method'} . ', ' . $command->{'url'} . ', ' . $paramstr
            );
        }

        my $url = "$settings->{'SITE_URL'}/$user_id/$command->{'url'}";

        # attempt to execute this command
        my $res;
        if ($command->{'method'} eq 'get' || $command->{'method'} eq 'head') {
            $res = http_get(
                url     => $url . (($command->{'method'} eq 'get') ? '' : ('?_method=' . $command->{'method'})), 
                params  => $command->{'parameters'}, 
                headers => { 'Token' => $token, },
            );
        }
        else {
            $res = http_post(
                url     => $url . (($command->{'method'} eq 'post') ? '' : ('?_method=' . $command->{'method'})), 
                params  => $command->{'parameters'}, 
                headers => { 'Token' => $token, },
            );
        }

        if ($res->{'success'}) {
            # command succeeded
            if ($command->{'flow'} eq '-') {
                # succeeded when workflow command expected to fail
                _workflow_log('workflow error: expected failure but got ' . $res->{'message'});
                unlink $workflow_file;
                next LP_WORKFLOW;
            }
            elsif ($command->{'flow'} eq '*') {
                # abort this workflow for now and await next cron invocation before retrying
                _workflow_log('OK', $relative_workflow_file, $current_index, $res->{'status'}, length($res->{'content'}));
                next LP_WORKFLOW;
            }
            else {
                # advance index to next command
                $current_index++;
                $workflow->{'workflow'}{'current_index'} = $current_index;
                _save_workflow($workflow_file, $workflow);
            }
        }
        else {
            # command failed
            if ($command->{'flow'} eq '+') {
                # failed when workflow command expected to succeed
                _workflow_log('workflow error: expected success but got ' . $res->{'message'});
                unlink $workflow_file;
                next LP_WORKFLOW;
            }
            # advance index to next command
            $current_index++;
            $workflow->{'workflow'}{'current_index'} = $current_index;
            _save_workflow($workflow_file, $workflow);
        }
        
        # log enactment step and record filename and length
        _workflow_log('OK', $relative_workflow_file, $current_index, $res->{'status'}, length($res->{'content'}));

    }#foreach command

    # all commands in this workflow completed, so delete the workflow file
    unlink $workflow_file;

}#foreach workflow file

exit;

sub _workflow_log {
    my $str = join("\t", @_);
    util_appendFile($settings->{'WORKFLOW_LOG'}, gmtime(time) . "\t" . $str . "\n");
}

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



sub _load_workflow {
    my ($workflow_file) = @_;    
    # deserialise a json hash
    return JSON->new->decode( util_readFile($workflow_file) );
}

sub _save_workflow {
    my ($workflow_file, $workflow) = @_;
    # serialise a json hash
    util_writeFile($workflow_file, JSON->new->canonical->pretty->encode($workflow));
    return $workflow;
}


