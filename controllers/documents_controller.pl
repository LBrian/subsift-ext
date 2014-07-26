# documents_controller.pl
use strict;
use warnings;

require '_folders_helper.pl';
require 'documents_helper.pl';

my $FALSE = 0;
my $TRUE  = 1;

my $FOLDER_TYPE = 'documents';

sub controller_documents {
    my ($settings, $params) = @_;

    if (defined $params->{'folder_id'} && $params->{'action'} !~ /^create/) {
        my $info = helper_folders_get_info($FOLDER_TYPE, $settings, $params);
        if (defined $info && $info->{'mode'} eq 'private') {
            # insist that request is authenticated
            error_unless_authenticated($settings, $params);
        }
    }
}


sub action_documents_list {
    my ($settings, $params) = @_;

    my $full = $params->{'full'};

    my $documents_arrayref = helper_list_folders($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }
    foreach my $folder_info (@$documents_arrayref) {
        # suppress detailed information unless full specified
        if (!$full) {
            delete $folder_info->{'default_item'};
            delete $folder_info->{'prototypes'};
            delete $folder_info->{'value'};
        }
    }

    my $text = serialise({'folder' => $documents_arrayref});
    render({ 'text' => $text });
}


sub action_documents_create {
    my ($settings, $params) = @_;
    
    my $mode = $params->{'mode'};
    my $description = $params->{'description'};
    my $full = $params->{'full'};

    my $data_type = helper_parse_json($params->{'data_type'} || '{"text": "STRING"}');
    if (performed_render()) {
        return;
    }

    # create info hash which will be serialised to a file in the created folder
    my %info = (
        'type'          => undef,           # set by helper_folders_create
        'id'            => undef,
        'mode'          => $mode,
        'description'   => $description,
        'created'       => undef,           # set by helper_folders_create
        'modified'      => undef,           # set by helper_folders_create
        'uri'           => undef,           # set by helper_folders_create
        # define a parent item to hold values that are invariant over all items in folder
        'default_item'  => {
            'type'          => undef,       # set by helper_folders_create
#            'id'            => $item_id,
            'description'   => '',
            'bookmark'      => 'none',
            'source'        => 'text',
            'created'       => undef,       # set by helper_folders_create
            'modified'      => undef,       # set by helper_folders_create
#            'uri'           => undef,
            'data_type'     => $data_type,
#            'data_type'     => {
#                'text' => 'STRING',
#            },
            'value'         => {
                'text'      => '',
            },
        }
    );
    helper_folders_create($FOLDER_TYPE, $settings, $params, \%info);
    if (performed_render()) {
        return;
    }

    # suppress detailed information unless full specified
    if (!$full) {
        delete $info{'default_item'};
        delete $info{'prototypes'};
        delete $info{'value'};
    }

    # compose response text
    my $text = serialise({'folder' => \%info});

    render({
        'status'    => '201 Created',
        'headers'   => { 'Location' => $info{'uri'}, },
        'text'      => $text,
    });
}


sub action_documents_destroy {
    my ($settings, $params) = @_;

    my $full = $params->{'full'};

    my $folder_info = helper_folders_get_info($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    helper_folders_destroy($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    # suppress detailed information unless full specified
    if (!$full) {
        delete $folder_info->{'default_item'};
        delete $folder_info->{'prototypes'};
        delete $folder_info->{'value'};
    }

    my $text = serialise({'folder' => $folder_info});
    render({'text' => $text,});
}


sub action_documents_exists {
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


sub action_documents_show {
    my ($settings, $params) = @_;

    my $full = $params->{'full'};

    my $folder_info = helper_folders_get_info($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    # suppress detailed information unless full specified
    if (!$full) {
        delete $folder_info->{'default_item'};
        delete $folder_info->{'prototypes'};
        delete $folder_info->{'value'};
    }

    my $text = serialise({'folder' => $folder_info});
    render({ 'text' => $text });
}


sub action_documents_update {
    my ($settings, $params) = @_;
    
    my $folder_info = helper_folders_get_info($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $mode = $params->{'mode'};
    my $description = $params->{'description'};
    my $full = $params->{'full'};

    # update info hash which will be serialised to a file in the documents folder
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

    # suppress detailed information unless full specified
    if (!$full) {
        delete $folder_info->{'default_item'};
        delete $folder_info->{'prototypes'};
        delete $folder_info->{'value'};
    }

    my $text = serialise({'folder' => $folder_info});
    render({ 'text' => $text });
}


sub action_documents_create_from {
    my ($settings, $params) = @_;

    my $generator = $params->{'generator'};
    my $mode = $params->{'mode'};
    my $description = $params->{'description'};
    my $full = $params->{'full'};

    # because there are multiple route patterns that lead to here, document_id may be null
    my $document_ids = $params->{'document_ids'};
    if (!defined $document_ids || $document_ids eq '') {
        # default to document_id 'list' being our own documents folder id
        $document_ids = $params->{'folder_id'};
    }

    # build a list of the document folder ids that are the arguments to this transform
    my @document_ids_list = ();
    my @ids = split(m|\/|, $document_ids);
    for my $id (@ids) {
        if ($id eq '' || $id !~ /[a-z][a-z0-9_]*/) {
            render({
                'status' => '404 Not Found',
                'text'   => serialise_error_message("Specified documents folder does not exist:", $id),
            });
            return;
        }
        my $folder_path = helper_folders_path($FOLDER_TYPE, $settings, $params, $id);
        if (performed_render()) {
            return;
        }
        push(@document_ids_list, $id);
    }

    #FIXME: should be an option with an error reported if overwrite not set to true?
    my $replace = $TRUE;
    if ($replace) {
        # remove any earlier version of the destination folder
        helper_folders_destroy($FOLDER_TYPE, $settings, $params);
        if (performed_render()) {
            return;
        }
    }

    # create document info hash which will be serialised to a file in the created folder
    my %info = (
          # generic "thing" parameters
        'type'                  => undef,
        'id'                    => undef,
        'mode'                  => $mode,
        'description'           => $description,
        'created'               => undef,
        'modified'              => undef,
        'uri'                   => undef,
        # define a parent item to hold values that are invariant over all items in folder
        'default_item'  => {
            'type'          => undef,       # set by helper_folders_create
#            'id'            => $item_id,
            'description'   => '',
            'bookmark'      => 'none',
            'source'        => 'text',
            'created'       => undef,       # set by helper_folders_create
            'modified'      => undef,       # set by helper_folders_create
#            'uri'           => undef,
            'data_type'     => {
                'text' => 'STRING',
            },
            'value'         => {
                'text'      => '',
            },
        },
        # id of document to be copied with transformation
        'document_ids'          => \@document_ids_list,
        'generator'             => $generator,
    );
    helper_folders_create($FOLDER_TYPE, $settings, $params, \%info);
    if (performed_render()) {
        return;
    }
    
    # create a manifest describing the transformation
    helper_create_transform_task($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    # perform as much of the transform as can be done in the available time (may be all of it)
    helper_transform_next($FOLDER_TYPE, $settings, $params, \%info);
    if (performed_render()) {
        return;
    }

    # check whether transform completed within web server time limit
    # or whether remainder queued for incremental execution by transformer
    my $exists = helper_creating($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    # suppress detailed information unless full specified
    if (!$full) {
        delete $info{'default_item'};
        delete $info{'prototypes'};
        delete $info{'value'};
    }

    # return response appropriate for either queued or completed
    render(
        ($exists)
        ?   {
                'status'    => '202 Accepted',
                'text'      =>  'ok',
            }
        :   {
                'status'    => '201 Created',
                'headers'   => { 'Location' => $info{'uri'} },
                'text'      => serialise({'folder' => \%info}),
            }
    );

}


1;