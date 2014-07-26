# bookmark_items_controller.pl
use strict;
use warnings;

require '_folders_helper.pl';
require 'bookmarks_helper.pl';

my $FALSE = 0;
my $TRUE  = 1;

my $FOLDER_TYPE = 'bookmarks';


sub controller_bookmark_items {
    my ($settings, $params) = @_;

    if (defined $params->{'folder_id'}) {
        my $info = helper_folders_get_info($FOLDER_TYPE, $settings, $params);
        if (defined $info && $info->{'mode'} eq 'private') {
            # insist that request is authenticated
            error_unless_authenticated($settings, $params);
        }
    }
}



sub action_bookmark_items_list {
    my ($settings, $params) = @_;

    my (
        $bookmarks_info_file, $bookmarks_info, 
        $bookmarks_data_file, $bookmarks_data
       ) = helper_load_folder($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $bookmarks_array = array_from_hash($bookmarks_data);
    my $text = serialise({'item' => $bookmarks_array});
    render({ 'text' => $text });
}


sub action_bookmark_items_create {
    #
    #   Create one or multiple bookmark items.
    #       If 'items_list' param then create an item for each line in list.
    #       Otherwise expects a single 'item_id' parameter.
    #
    my ($settings, $params) = @_;

    my (
        $bookmarks_info_file, $bookmarks_info, 
        $bookmarks_data_file, $bookmarks_data
       ) = helper_load_folder($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $items_list = $params->{'items_list'};
    my $items_arrayref = helper_parse_items_list($items_list);
    my $multiple_items = (scalar(@$items_arrayref) > 0) ? $TRUE : $FALSE;
    if (!$multiple_items) {
        my $item_id = util_getValidFileName( $params->{'item_id'} );
        push(@$items_arrayref, [
            $item_id,
            $params->{'description'} || (($params->{'item_id'} ne $item_id) ? $params->{'item_id'} : ''),
            $params->{'item_url'},
        ]);
    }

    # construct uri for the resources being created
    my $user_id = $params->{'user_id'};
    my $folder_id = $params->{'folder_id'};
    my $uri_stem = $settings->{'SITE_URL'} . '/' . $user_id . '/' . $FOLDER_TYPE . '/' . $folder_id . '/items';

    # iterate over either all items in 'item_list' or over a single item
    my $timestamp = time;
    my @result = ();
    my @resource_url = ();
    foreach my $item (@$items_arrayref) {
        
        # load params with values from one line of item_list
        $params->{'item_id'}     = $item->[0];
        $params->{'description'} = $item->[1];
        $params->{'item_url'}    = $item->[2];

        my $item_id     = $params->{'item_id'};
        my $description = $params->{'description'};
        my $item_url    = $params->{'item_url'};

        if ($item_url eq '') {
            render({
                'status' => '400 Bad Request',
                'text'   => serialise_error_message('Missing parameter: item_url'),
            });
            return;
        }

        # if not a multi-item create then insist on use of http PUT instead of POST for update
        if (!$multiple_items && exists $bookmarks_data->{$item_id}) {
            render({
                'status' => '403 Forbidden',
                'text'   => serialise_error_message("Bookmark item already exists: $item_id"),
            });
            return;
        }

        # default to url starting with http:// if not specified
        $item_url = helper_default_url_prefix($item_url);
        # validate url syntax
        if (!helper_is_valid_url($item_url)) {
            render({
                'status' => '400 Bad Request',
                'text'   => serialise_error_message("Invalid item_url: $item_url"),
            });
            return;
        }

        my $uri = $uri_stem . '/' . $item_id;

        $bookmarks_data->{$item_id} = {
            'type'          => $FOLDER_TYPE,
            'id'            => $item_id,
            'url'           => $item_url,
            'description'   => $description,
            'created'       => $timestamp,
            'modified'      => $timestamp,
            'uri'           => $uri,
        };
        
        push(@result, $bookmarks_data->{$item_id});

        
    }# end foreach item
    
    my $bookmarks_array = helper_save_things_data($bookmarks_data_file, $bookmarks_data);
    if (performed_render()) {
        return;
    }

    $bookmarks_info->{'modified'} = $timestamp;
    helper_folders_put_info_file($bookmarks_info_file, $bookmarks_info);
    if (performed_render()) {
        return;
    }

    my $text = serialise(
        ((scalar(@result) > 1) ? {'item' => \@result} : {'item' => $result[0]})
    );
    

    render({
        'status'    => '201 Created',
        'headers'   => { 'Location' => $uri_stem },
        'text'      => $text,
    });

}


sub action_bookmark_items_destroy {
    my ($settings, $params) = @_;

    my (
        $bookmarks_info_file, $bookmarks_info, 
        $bookmarks_data_file, $bookmarks_data
       ) = helper_load_folder($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }
    
    my $item_id = $params->{'item_id'};

    if (!exists $bookmarks_data->{$item_id}) {
        render({
            'status' => '404 Not Found',
            'text'   => serialise_error_message("No such bookmark item: $item_id"),
        });
        return;
    }
    
    my $deleted_item = $bookmarks_data->{$item_id};
    delete $bookmarks_data->{$item_id};
    helper_save_things_data($bookmarks_data_file, $bookmarks_data);
    if (performed_render()) {
        return;
    }

    $bookmarks_info->{'modified'} = time;
    helper_folders_put_info_file($bookmarks_info_file, $bookmarks_info);
    if (performed_render()) {
        return;
    }

    my $text = serialise({'item' => $deleted_item});
    render({ 'text' => $text });
}


sub action_bookmark_items_destroy_all {
    my ($settings, $params) = @_;

    my (
        $bookmarks_info_file, $bookmarks_info, 
        $bookmarks_data_file, $bookmarks_data
       ) = helper_load_folder($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    # create the return string
    my $bookmarks_array = array_from_hash($bookmarks_data);

    # delete the whole folder (and create a backup in trash folder)
    helper_folders_destroy($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }
    # recreate the folder as an empty folder but with same info properties (except modified timestamp)
    $bookmarks_info->{'modified'} = time;
    helper_folders_create($FOLDER_TYPE, $settings, $params, $bookmarks_info);
    if (performed_render()) {
        return;
    }

    my $text = serialise({'item' => $bookmarks_array});
    render({ 'text' => $text });
}


sub action_bookmark_items_exists {
    my ($settings, $params) = @_;

    my $exists = helper_folders_exists($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $item_id = $params->{'item_id'};

    if ($exists) {
        my (
            $bookmarks_info_file, $bookmarks_info, 
            $bookmarks_data_file, $bookmarks_data
           ) = helper_load_folder($FOLDER_TYPE, $settings, $params);
        if (performed_render()) {
            return;
        }

        $exists = (exists $bookmarks_data->{$item_id}) ? $TRUE : $FALSE;
    }
    
    render({
        'status' => ($exists) ? '200 OK' : '404 Not Found',
        'text' => '',
    });
}


sub action_bookmark_items_show {
    my ($settings, $params) = @_;

    my (
        $bookmarks_info_file, $bookmarks_info, 
        $bookmarks_data_file, $bookmarks_data
       ) = helper_load_folder($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $item_id = $params->{'item_id'};

    if (!exists $bookmarks_data->{$item_id}) {
        render({
            'status' => '404 Not Found',
            'text'   => serialise_error_message("No such bookmark item: $item_id"),
        });
        return;
    }
    
    my $item = $bookmarks_data->{$item_id};

    my $text = serialise({'item' => $item});
    render({ 'text' => $text });
}


sub action_bookmark_items_update {
    my ($settings, $params) = @_;

    my (
        $bookmarks_info_file, $bookmarks_info, 
        $bookmarks_data_file, $bookmarks_data
       ) = helper_load_folder($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $item_id = $params->{'item_id'};
    my $item_url = $params->{'item_url'};
    my $description = $params->{'description'};

    if (!exists $bookmarks_data->{$item_id}) {
        render({
            'status' => '404 Not Found',
            'text'   => serialise_error_message("No such bookmark item: $item_id"),
        });
        return;
    }

    # default to url starting with http:// if not specified
    $item_url = helper_default_url_prefix($item_url);
    # validate url syntax (if one was supplied)
    if ($item_url ne '' && !helper_is_valid_url($item_url)) {
        render({
            'status' => '400 Bad Request',
            'text'   => serialise_error_message("Invalid item_url: $item_url"),
        });
        return;
    }

    # update info hash which will be serialised to a file in the bookmarks folder
    my $changed = $FALSE;
    my @properties = (
        ['url',         'item_url',     $item_url], 
        ['description', 'description',  $description], 
    );
    foreach (@properties) {
        my ($key, $cgi_key, $value) = @$_;
        if (exists $params->{$cgi_key} && 
            (!exists $bookmarks_data->{$item_id}{$key} || ($bookmarks_data->{$item_id}{$key} ne $value && $value ne ''))
           ) {
            $bookmarks_data->{$item_id}{$key} = $value;
            $changed = $TRUE;
        }
    }
    if ($changed) {
        my $timestamp = time;
        $bookmarks_data->{$item_id}{'modified'} = $timestamp;
        helper_save_things_data($bookmarks_data_file, $bookmarks_data);
        if (performed_render()) {
            return;
        }
        $bookmarks_info->{'modified'} = $timestamp;
        helper_folders_put_info_file($bookmarks_info_file, $bookmarks_info);
        if (performed_render()) {
            return;
        }
    }

    my $text = serialise({'item' => $bookmarks_data->{$item_id}});
    render({ 'text' => $text });
}


sub action_bookmark_items_wrong_method {
    my ($settings, $params) = @_;

    render({
        'status' => '400 Bad Request',
        'text'   => serialise_error_message('Wrong http method: ' . get_request_method()),
    });
}


sub action_bookmark_items_unknown {
    my ($settings, $params) = @_;

    my $action_unescaped = $params->{'action'} || 'undef';

    render({
        'status' => '400 Bad Request',
        'text'   => serialise_error_message("Unknown action: $action_unescaped"),
    });
}


1;