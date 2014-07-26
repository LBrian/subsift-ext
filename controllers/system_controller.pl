use strict;
use warnings;

require 'system_helper.pl';

my $FALSE = 0;
my $TRUE  = 1;

my $WORKFLOW_TYPE = 'workflows';


sub controller_system {
    my ($settings, $params) = @_;

}


sub action_system_workflow_create {
    #
    #   create and schedule a workflow for enactment
    #
    my ($settings, $params) = @_;

    my $user_id = $params->{'user_id'};
    my $workflow_id = $params->{'workflow_id'};
    my $commands = $params->{'commands'};

    my $user_path = File::Spec->catdir($settings->{'USERS_PATH'}, $user_id);
    if (!-d $user_path) {
        render({
            'status' => '404 Not Found',
            'text'   => serialise_error_message("No such user: $user_id"),
        });
        return;
    }
    
    my $commands_data = helper_parse_commands($commands);
    if (performed_render()) {
        return;
    }
    my $workflow_data = {
        'workflow' => {
            'command' => $commands_data,
            'current_index' => 1,
        }
    };
    
    # create workflows folder if one does already exist
    my $workflows_path =  File::Spec->catdir($user_path, $WORKFLOW_TYPE);
    File::Path::mkpath($workflows_path);
    # serialise info data out to a file
    my $workflow_file = File::Spec->catfile($workflows_path, util_getValidFileName($workflow_id) . '.json');
    util_writeFile($workflow_file, JSON->new->canonical->pretty->encode($workflow_data) );

    my $text = serialise($workflow_data);
    render({
        'status'    => '201 Created',
        'text'      =>  $text,
    });
}


sub action_system_workflow_enacting {
    #
    #   test whether workflow enactment is still in progress (i.e. whether commands have finished)
    #
    my ($settings, $params) = @_;

    my $user_id = $params->{'user_id'};
    my $workflow_id = $params->{'workflow_id'};

    my $user_path = File::Spec->catdir($settings->{'USERS_PATH'}, $user_id);
    if (!-d $user_path) {
        render({
            'status' => '404 Not Found',
            'text'   => serialise_error_message("No such user: $user_id"),
        });
        return;
    }
    
    # delete workflow if it exists
    my $workflows_path =  File::Spec->catdir($user_path, $WORKFLOW_TYPE);
    my $workflow_file = File::Spec->catfile($workflows_path, util_getValidFileName($workflow_id) . '.json');

    my $exists = (-e $workflow_file) ? $TRUE : $FALSE;

    render({
        'status' => ($exists) ? '200 OK' : '404 Not Found',
        'text' => '',
    });
}


sub action_system_workflow_destroy {
    #
    #   delete and deschedule a workflow
    #
    my ($settings, $params) = @_;

    my $user_id = $params->{'user_id'};
    my $workflow_id = $params->{'workflow_id'};

    my $user_path = File::Spec->catdir($settings->{'USERS_PATH'}, $user_id);
    if (!-d $user_path) {
        render({
            'status' => '404 Not Found',
            'text'   => serialise_error_message("No such user: $user_id"),
        });
        return;
    }
    
    # delete workflow if it exists
    my $workflows_path =  File::Spec->catdir($user_path, $WORKFLOW_TYPE);
    my $workflow_file = File::Spec->catfile($workflows_path, util_getValidFileName($workflow_id) . '.json');
    if (!-e $workflow_file) {
        render({
            'status' => '404 Not Found',
            'text'   => serialise_error_message("No such workflow: $workflow_id"),
        });
        return;
    }
    my $workflow_data = JSON->new->decode( util_readFile($workflow_file) );
    # don't bother to move a copy to trash as the workflow script is already preserved in the log file
    unlink $workflow_file;

    my $text = serialise($workflow_data);
    render({ 'text' => $text });
}





sub action_system_status_test {
    my ($settings, $params) = @_;

    my $text = serialise('ok');

    render({ 'text' => $text });
}

sub action_system_unknown {
    my ($settings, $params) = @_;

    my $action_unescaped = $params->{'action'} || 'undef';

    render({
        'status' => '400 Bad Request',
        'text'   => serialise_error_message('Unknown action: ' . $action_unescaped),
    });
}

1;