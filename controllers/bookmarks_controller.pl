# bookmarks_controller.pl
use strict;
use warnings;

require '_folders_helper.pl';

my $FALSE = 0;
my $TRUE  = 1;

my $FOLDER_TYPE = 'bookmarks';


sub controller_bookmarks {
    my ($settings, $params) = @_;

    if (defined $params->{'folder_id'} && $params->{'action'} ne 'create') {
        my $info = helper_folders_get_info($FOLDER_TYPE, $settings, $params);
        if (defined $info && $info->{'mode'} eq 'private') {
            # insist that request is authenticated
            error_unless_authenticated($settings, $params);
        }
    }
}


sub action_bookmarks_list {
    my ($settings, $params) = @_;

    my $bookmarks_arrayref = helper_list_folders($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $text = serialise({'folder' => $bookmarks_arrayref});
    render({ 'text' => $text });
}


sub action_bookmarks_create {
    my ($settings, $params) = @_;
    
    my $mode = $params->{'mode'};
    my $description = $params->{'description'};

    # create info hash which will be serialised to a file in the created folder
    my %info = (
        'type'          => undef,
        'id'            => undef,
        'mode'          => $mode,
        'description'   => $description,
        'created'       => undef,
        'modified'      => undef,
        'uri'           => undef,
    );
    helper_folders_create($FOLDER_TYPE, $settings, $params, \%info);
    if (performed_render()) {
        return;
    }

    # compose response text
    my $text = serialise({'folder' => \%info});

    render({
        'status'    => '201 Created',
        'headers'   => { 'Location' => $info{'uri'}, },
        'text'      => $text,
    });
}


sub action_bookmarks_destroy {
    my ($settings, $params) = @_;

    my $folder_info = helper_folders_get_info($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    helper_folders_destroy($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $text = serialise({'folder' => $folder_info});
    render({ 'text' => $text });
}


sub action_bookmarks_exists {
    my ($settings, $params) = @_;

    my $exists = helper_folders_exists($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    render({
        'status' => ($exists) ? '200 OK' : '404 Not Found',
        'text' => '',
    });
}


sub action_bookmarks_show {
    my ($settings, $params) = @_;

    my $folder_info = helper_folders_get_info($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $text = serialise({'folder' => $folder_info});
    render({ 'text' => $text });
}


sub action_bookmarks_update {
    my ($settings, $params) = @_;
    
    my $folder_info = helper_folders_get_info($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $mode = $params->{'mode'};
    my $description = $params->{'description'};

    # update info hash which will be serialised to a file in the bookmarks folder
    my $changed = $FALSE;
    my @properties = (
        ['mode',        'mode',         $mode], 
        ['description', 'description',  $description], 
    );
    foreach (@properties) {
        my ($key, $cgi_key, $value) = @$_;
        if (exists $params->{$cgi_key} && (!defined $folder_info->{$key} || $folder_info->{$key} ne $value)) {
            $folder_info->{$key} = $value;
            $changed = $TRUE;
        }
    }
    if ($changed) {
        $folder_info->{'modified'} = time;
        helper_folders_put_info($FOLDER_TYPE, $settings, $params, $folder_info);
        if (performed_render()) {
            return;
        }
    }

    my $text = serialise({'folder' => $folder_info});
    render({ 'text' => $text });
}

=head
sub action_bookmarks_wrong_method {
    my ($settings, $params) = @_;

    render({
        'status' => '400 Bad Request',
        'text'   => serialise_error_message('Wrong http method: ' . get_request_method()),
    });
}
=cut


sub action_bookmarks_unknown {
    my ($settings, $params) = @_;

    my $action_unescaped = $params->{'action'} || 'undef';

    render({
        'status' => '400 Bad Request',
        'text'   => serialise_error_message("Unknown action: $action_unescaped"),
    });
}


1;