# document_items_controller.pl
use strict;
use warnings;
use Encode;

require '_folders_helper.pl';
require '_items_helper.pl';
require 'documents_helper.pl';

my $FALSE = 0;
my $TRUE  = 1;

my $FOLDER_TYPE    = 'documents';
my $BOOKMARKS_TYPE = 'bookmarks';


sub controller_document_items {
    my ($settings, $params) = @_;

    if (defined $params->{'folder_id'}) {
        my $info = helper_folders_get_info($FOLDER_TYPE, $settings, $params);
        if (performed_render()) {
            return;
        }
        if (defined $info && $info->{'mode'} eq 'private') {
            # insist that request is authenticated
            error_unless_authenticated($settings, $params);
        }
    }
}



sub action_document_items_import {
    #
    #   import a set of items (i.e. documents) from urls of supplied bookmarks list
    #
    my ($settings, $params) = @_;

    my (
        $document_info_file, $document_info, 
        $document_data_file, $document_data
       ) = helper_load_folder($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    if (!defined $params->{'bookmarks_id'} || $params->{'bookmarks_id'} eq '') {
        # default to bookmarks folder ID being same as the profiles folder ID
        $params->{'bookmarks_id'} = $params->{'folder_id'};
    }
    my $bookmarks_id = $params->{'bookmarks_id'};

    my (
        $bookmarks_info_file, $bookmarks_info, 
        $bookmarks_data_file, $bookmarks_data
       ) = helper_load_folder_for($BOOKMARKS_TYPE, $settings, $params, $bookmarks_id);
    if (performed_render()) {
        return;
    }

    helper_import_bookmarks($FOLDER_TYPE, $settings, $params, $bookmarks_id, $bookmarks_data);
    if (performed_render()) {
        return;
    }

    render({
        'status'    => '202 Accepted',
        'text'      =>  'ok',
    });
}


sub action_document_items_importing {
    #
    #   test whether import is still in progress (i.e. whether harvesting has finished)
    #
    my ($settings, $params) = @_;

    my (
        $document_info_file, $document_info, 
        $document_data_file, $document_data
       ) = helper_load_folder($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    if (!defined $params->{'bookmarks_id'} || $params->{'bookmarks_id'} eq '') {
        # default to bookmarks folder ID being same as the profiles folder ID
        $params->{'bookmarks_id'} = $params->{'folder_id'};
    }
    my $bookmarks_id = $params->{'bookmarks_id'};

    my (
        $bookmarks_info_file, $bookmarks_info, 
        $bookmarks_data_file, $bookmarks_data
       ) = helper_load_folder_for($BOOKMARKS_TYPE, $settings, $params, $bookmarks_id);
    if (performed_render()) {
        return;
    }

    my $exists = helper_importing_bookmarks($FOLDER_TYPE, $settings, $params, $bookmarks_id, $bookmarks_data);
    if (performed_render()) {
        return;
    }
    render({
        'status' => ($exists) ? '200 OK' : '404 Not Found',
        'text' => '',
    });
}


sub action_document_items_list {
    my ($settings, $params) = @_;

    my $page = $params->{'page'};
    my $count = $params->{'count'};

    my $folder_info = helper_folders_get_info($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    # fetch a slice of persistent sorted list of items (NB. return value obeys 'full' param)
    my $items_info = helper_items_get_range($FOLDER_TYPE, $settings, $params, $page, $count);
    if (performed_render()) {
        return;
    }

    my $text = serialise({'item' => $items_info});
    render({ 'text' => $text });
}


sub action_document_items_create {
    #
    #   Create one or multiple document items.
    #       If 'items_list' param then create an item for each line in list.
    #       Otherwise expects a single 'item_id' parameter.
    #
    my ($settings, $params) = @_;

    my $folder_info = helper_folders_get_info($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $items_list = $params->{'items_list'};
    my $as = $params->{'as'};
    my $is_schema = $params->{'is_schema'};
    my $use_schema = $params->{'use_schema'};
    my $full = $params->{'full'};

    # set id_path to a JSONPath object or undef
    my $id_path;
    if (exists $params->{'id_path'} && $params->{'id_path'} ne '') {
        $id_path = helper_parse_json_path($params->{'id_path'});
        if (performed_render()) {
            return;
        }
    }
    # set description_path to a JSONPath object or undef
    my $description_path;
    if (exists $params->{'description_path'} && $params->{'description_path'} ne '') {
        $description_path = helper_parse_json_path($params->{'description_path'});
        if (performed_render()) {
            return;
        }
    }
    my $items_arrayref = helper_parse_items_list($items_list);
    if (performed_render()) {
        return;
    }

    my $multiple_items = (scalar(@$items_arrayref) > 0) ? $TRUE : $FALSE;
    if (!$multiple_items) {
        if ($as ne 'csv' && $as ne 'arff') {
            my $item_id = util_getValidFileName( $params->{'item_id'} );
            push(@$items_arrayref, [
                $item_id,
                $params->{'description'} || (($params->{'item_id'} ne $item_id) ? $params->{'item_id'} : ''),
                $params->{'value'} || $params->{'text'} || '',
            ]);
        }
        # interpret csv value as bulk item creation
        my $relation = {
            'attributes'            => [],
                # where each attribute is a hash, { attribute_name, attribute_type, attribute_is_numeric }
            'records'               => [],
        };
        if ($as eq 'csv') {
            my $err;
            my @rows = ();
            eval{
                @rows = @{csv_parse_string($params->{'values'})};
            };
            if ($@) {
                $err = $@;
            } elsif ($!) {
                $err = $!;
            }
            if (defined $err && $err ne 'No such file or directory') {      #FIXME: HACK WORKAROUND because 'open'ing from a string gives this error in csv_parse_string
                warn_message('csv parse error: ' . $err);
                render({
                    'status' => '400 Bad Request',
                    'text'   => serialise_error_message('Invalid value'),
                });
                return;
            }
            if ($is_schema && scalar(@rows) > 0) {
                # consume first row of csv as column headings row
                my $names = shift @rows;
                foreach my $name (@$names) {
                    push(@{$relation->{'attributes'}}, {
                        'attribute_name' => $name,
                        'attribute_type' => 'STRING',
                        'attribute_is_numeric' => $FALSE,
                    });
                }
            }
            $relation->{'records'} = \@rows;
            $multiple_items = $TRUE;
        }
        elsif ($as eq 'arff') {
            require 'arff.pl';
#            $relation = arff_parse_string($params->{'values'}, (($is_schema && $use_schema) ? $TRUE : $FALSE));
            $relation = arff_parse_string($params->{'values'}, ($use_schema ? $TRUE : $FALSE));
        }

        if ($as eq 'csv' || $as eq 'arff') {

            # create subsift item metadata for each row

            my $i = 0;
            if (!defined $id_path) {
                # generate ids with numbers starting from current no. items in folder (assumes ids are not already in use)
                my $folder_path = helper_folders_path($FOLDER_TYPE, $settings, $params, $params->{'folder_id'});
                if (performed_render()) {
                    return;
                }
                $i = helper_items_index_size($folder_path);
            }
            foreach my $item (@{$relation->{'records'}}) {
                # generate an automatic item_id
                $i++;
                my $item_id = sprintf('i%06u', $i); #left pad with zeros so alpha sort order is same as numeric sequence
                if (defined $id_path) {
                    # fetch field from specified JSON Path to use as an item_id
                    my $v_arrayref = helper_apply_json_path($id_path, $item);
                    if (performed_render()) {
                        return;
                    }
                    if (scalar(@$v_arrayref) >= 1) {
                        $item_id = util_getValidFileName( join('_', @$v_arrayref) );
                    }
                }
                my $description = '';
                if (defined $description_path) {
                    # fetch field from specified JSON Path to use as an item_id
                    my $v_arrayref = helper_apply_json_path($description_path, $item);
                    if (performed_render()) {
                        return;
                    }
                    if (scalar(@$v_arrayref) >= 1) {
                        $description = join(' ', @$v_arrayref);
                    }
                }

                if ($is_schema && $use_schema) {
                    my %value = ();
                    my $attributes = $relation->{'attributes'};
                    my $attribute_count = scalar(@$attributes);
                    for(my $i=0; $i < $attribute_count; $i++) {
                        $value{$attributes->[$i]{'attribute_name'}} = $item->[$i];
                    }
                    $item = \%value;
                }

                push(@$items_arrayref, [
                    $item_id,
                    $description,
                    $item,
                ]);
            }
        }
    }

    # iterate over either all items in 'item_list' or over a single item
    my $timestamp = time;
    my @items_info = ();
    my @resource_url = ();
    foreach my $item (@$items_arrayref) {
        
        # load params with values from one line of item_list
        $params->{'item_id'}     = $item->[0];
        $params->{'description'} = $item->[1];
        $params->{'value'}       = $item->[2];

        my $item_id     = $params->{'item_id'};
        my $description = $params->{'description'};
        my $item_value  = $params->{'value'} || '';
#        my $item_text   = $params->{'text'} || '';

        # normalise newlines in text value
#        $item_text =~ s/\r\n|\r/\n/gmxs;
        $item_value =~ s/\r\n|\r/\n/gmxs;

        if ($item_value eq '') {
            render({
                'status' => '400 Bad Request',
                'text'   => serialise_error_message('Missing parameter: value or text'),
            });
            return;
        }

        # create the item (only specify non-folder invariant item properties (rest come from default_item on folder
        my %item_info = (
#            'type'          => undef,
            'id'            => $item_id,
#            'description'   => $description,
#            'bookmark'      => 'none',
#            'source'        => 'text',
#            'created'       => $timestamp,
#            'modified'      => $timestamp,
#            'uri'           => undef,
#            'data_type'     => {
#                'text' => 'STRING',
#            }
        );
        if ($description ne '') {
            $item_info{'description'} = $description;
        }

        if ($as eq 'json') {
            my $err;
#           $@ = undef;
#           $! = undef;
            eval {
                $item_info{'value'} = JSON->new->decode($item_value);
            };
            if ($@) {
                $err = $@;
            } elsif ($!) {
                $err = $!;
            }
            if (defined $err) {
                # trim off perl code details from end of error message
                $err =~ s/\)\sat\s.*//xms;
                render({
                    'status' => '400 Bad Request',
                    'text'   => serialise_error_message('Invalid json value - ' .  $item_value . ', ' .$err),
                });
                return;
            }
        }
        elsif ($as eq 'xml') {
            require XML::Simple;
            # strip off xml directives as they easily confuse XML::Simple
            $item_value =~ s/<\?(?:.*?)\?>//gxsm;
            my $err;
#           $@ = undef;
#           $! = undef;
            eval {
                $item_info{'value'} = XML::Simple::XMLin($item_value, 
                    'ContentKey' => 'text', 'ForceArray' => 0, 'KeepRoot' => 1
                );
            };
            if ($@) {
                $err = $@;
            } elsif ($!) {
                $err = $!;
            }
            if (defined $err) {
                # trim off perl code details from end of error message
                $err =~ s/\)\sat\s.*//xms;
                render({
                    'status' => '400 Bad Request',
                    'text'   => serialise_error_message('Invalid xml value - ' .  $item_value . ', ' .$err),
                });
                return;
            }
        }
        elsif ($as eq 'csv' || $as eq 'arff') {
            # csv row already parsed into an array
            $item_info{'value'} = $item_value;
        }
        else {
            # assume $as eq 'text'
            $item_value =~ s/[^[:ascii:]]+//g;	#workaround
            $item_info{'value'} = {
                'text' =>  Encode::decode('Detect', $item_value),
            };
        }

        push(@items_info, \%item_info);

    }# end foreach item
    # check for prior existence of item of items
    my $replace = $FALSE;   #FIXME: make replace a cgi parameter so user can specify behaviour
    if (!$replace) {
        if ($multiple_items) {
            if (helper_items_exists($FOLDER_TYPE, $settings, $params, \@items_info)) {
                if (performed_render()) {
                    return;
                }
                render({
                    'status' => '403 Forbidden',
                    'text'   => serialise_error_message("Document item already exists"),
                });
                return;
            }
        }
        else {
            my $item_id = $items_info[0]{'id'};
            if (helper_items_exists($FOLDER_TYPE, $settings, $params, $item_id)) {
                if (performed_render()) {
                    return;
                }
                render({
                    'status' => '403 Forbidden',
                    'text'   => serialise_error_message("Document item already exists: $item_id"),
                });
                return;
            }
        }
    }

    # create one or more persistent items
    helper_items_create($FOLDER_TYPE, $settings, $params, \@items_info);
    if (performed_render()) {
        return;
    }

    # update timestamp on the containing folder
    $folder_info->{'modified'} = $timestamp;
    helper_folders_put_info($FOLDER_TYPE, $settings, $params, $folder_info);
    if (performed_render()) {
        return;
    }

    if (!$full) {
        # remove values from items
        for my $info (@items_info) {
            delete $info->{'value'};
        }
    }
    my $text = serialise(
        ((scalar(@items_info) > 1) ? {'item' => \@items_info} : {'item' => $items_info[0]})
    );

    # construct uri for the resources being created
    my $user_id = $params->{'user_id'};
    my $folder_id = $params->{'folder_id'};
    my $uri_stem = $settings->{'SITE_URL'} . '/' . $user_id . '/' . $FOLDER_TYPE . '/' . $folder_id . '/items';
    render({
        'status'    => '201 Created',
        'headers'   => { 'Location' => $uri_stem },
        'text'      => $text,
    });
}


sub action_document_items_destroy {
    my ($settings, $params) = @_;

    my $folder_info = helper_folders_get_info($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }
    
    my $item_id = $params->{'item_id'};
    my $full = $params->{'full'};

    my $deleted_item = helper_items_get($FOLDER_TYPE, $settings, $params, $item_id);
    if (performed_render()) {
        return;
    }
    if (!defined $deleted_item) {
        render({
            'status' => '404 Not Found',
            'text'   => serialise_error_message("No such item: $item_id"),
        });
        return;
    }
    
    # create the return string (before we delete all the item files)
    if (!$full) {
        delete $deleted_item->{'value'};
    }

    # delete item from items database
    helper_items_destroy($FOLDER_TYPE, $settings, $params, $item_id);
    if (performed_render()) {
        return;
    }

    # update timestamp on the containing folder
    $folder_info->{'modified'} = time;
    helper_folders_put_info($FOLDER_TYPE, $settings, $params, $folder_info);
    if (performed_render()) {
        return;
    }

    my $text = serialise({'item' => $deleted_item});
    render({ 'text' => $text });
}


sub action_document_items_destroy_all {
    my ($settings, $params) = @_;

    my $folder_info = helper_folders_get_info($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    # delete all item from items database
    helper_items_destroy_all($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    # update timestamp on the containing folder
    $folder_info->{'modified'} = time;
    helper_folders_put_info($FOLDER_TYPE, $settings, $params, $folder_info);
    if (performed_render()) {
        return;
    }

    render({ 'text' => 'ok' });
}


sub action_document_items_exists {
    my ($settings, $params) = @_;

    my $exists = helper_folders_exists($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $item_id = $params->{'item_id'};

    if ($exists) {
        my $folder_info = helper_folders_get_info($FOLDER_TYPE, $settings, $params);
        if (performed_render()) {
            return;
        }

        $exists = helper_items_exists($FOLDER_TYPE, $settings, $params, $item_id);
        if (performed_render()) {
            return;
        }
    }

    render({
        'text' => '',
        'status' => ($exists) ? '200 OK' : '404 Not Found',
    });
}


sub action_document_items_show {
    my ($settings, $params) = @_;

    my $folder_info = helper_folders_get_info($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $item_id = $params->{'item_id'};
    my $full = $params->{'full'};

    my $item_info = helper_items_get($FOLDER_TYPE, $settings, $params, $item_id);
    if (performed_render()) {
        return;
    }
    if (!defined $item_info) {
        render({
            'status' => '404 Not Found',
            'text'   => serialise_error_message("No such item: $item_id"),
        });
        return;
    }
    
    if (!$full) {
        delete $item_info->{'value'};
    }

    my $text = serialise({'item' => $item_info});
    render({ 'text' => $text });
}


sub action_document_items_update {
    my ($settings, $params) = @_;

    my $item_id = $params->{'item_id'};
    my $item_value = $params->{'value'} || '';
    my $item_text = $params->{'text'} || '';
    my $description = $params->{'description'};
    my $full = $params->{'full'};

    my $folder_info = helper_folders_get_info($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $item_info = helper_items_get($FOLDER_TYPE, $settings, $params, $item_id);
    if (performed_render()) {
        return;
    }
    if (!defined $item_info) {
        render({
            'status' => '404 Not Found',
            'text'   => serialise_error_message("No such item: $item_id"),
        });
        return;
    }


    # update info hash which will be serialised to a file in the documents folder
    my $changed = $FALSE;
    if ($item_value ne '') {
        my $err;
#        $@ = undef;
#        $! = undef;
        eval {
            $item_info->{'value'} = JSON->new->decode($item_value);
        };
        if ($@) {
            $err = $@;
        } elsif ($!) {
            $err = $!;
        }
        if (defined $err) {
            # trim off perl code details from end of error message
            $err =~ s/\)\sat\s.*//xms;
            render({
                'status' => '400 Bad Request',
                'text'   => serialise_error_message('Invalid value - ' . $err),
            });
            return;
        }
        #FIXME: should deep compare value rather than assuming it has changed (could do by canonical string compare)
        $changed = $TRUE;
    }
    elsif ($item_text ne '') {
        # update the textual value with the new text
        if ($item_text ne $item_info->{'value'}{'text'}) {
            my %data_value = (
            );
            $item_info->{'value'} = {
                'text' =>  Encode::decode('Detect', $item_text),
            };
            $changed = $TRUE;
        }
    }
    my @properties = (
        ['description', 'description',  $description], 
    );
    foreach (@properties) {
        my ($key, $cgi_key, $value) = @$_;
        if (exists $params->{$cgi_key} && 
            (!exists $item_info->{$key} || $item_info->{$key} ne $value)
           ) {
            $item_info->{$key} = $value;
            $changed = $TRUE;
        }
    }
    if ($changed) {

        my $timestamp = time;
        $item_info->{'modified'} = $timestamp;
        helper_items_put($FOLDER_TYPE, $settings, $params, $item_info);
        if (performed_render()) {
            return;
        }

        $folder_info->{'modified'} = $timestamp;
        helper_folders_put_info($FOLDER_TYPE, $settings, $params, $folder_info);
        if (performed_render()) {
            return;
        }
    }

    if (!$full) {
        delete $item_info->{'value'};
    }

    my $text = serialise({'item' => $item_info});
    render({ 'text' => $text });
}


sub action_document_items_creating {
    #
    #   test whether documents_create_from is still in progress (i.e. whether copy-transform has finished)
    #
    my ($settings, $params) = @_;

    my $exists = helper_creating($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    render({
        'status' => ($exists) ? '200 OK' : '404 Not Found',
        'text' => '',
    });
}




1;