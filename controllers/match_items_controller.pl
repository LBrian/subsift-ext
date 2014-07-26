# match_items_controller.pl
use strict;
use warnings;

require '_folders_helper.pl';
require 'matches_helper.pl';

my $FALSE = 0;
my $TRUE  = 1;

my $FOLDER_TYPE = 'matches';


sub controller_match_items {
    my ($settings, $params) = @_;

    if (defined $params->{'folder_id'}) {
        my $info = helper_folders_get_info($FOLDER_TYPE, $settings, $params);
        if (defined $info && $info->{'mode'} eq 'private') {
            # insist that request is authenticated
            error_unless_authenticated($settings, $params);
        }
    }
}


sub action_match_items_list {
    my ($settings, $params) = @_;

    my (
        $matches_info_file, $matches_info, 
        $matches_data_file, $matches_data
       ) = helper_load_folder($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $user_id = $params->{'user_id'};
    my $profiles_id = $params->{'profiles_id'};     #note: will be '' if none supplied
    my $full = $params->{'full'};

    # filter by profile if one was supplied
    if ($profiles_id ne '') {
        for my $key (keys %$matches_data) {
            if ($matches_data->{$key}{'profiles_id'} ne $profiles_id) {
                delete $matches_data->{$key};
            }
        }
    }

    my $match_array = array_from_hash($matches_data);
    if ($full) {
        # augment metadata with extra data retrieved from associated external file
        for my $item_data (@$match_array) {
            my $terms = helper_load_terms_for($FOLDER_TYPE, $settings, $params, $matches_info->{'id'}, $item_data->{'id'});
            if (performed_render()) {
                return;
            }
            $item_data->{'term'} = helper_unpack_terms($params, $terms);
        }
    }


    # load similarity matrix
    my ($item_ids1, $item_ids2, $sims, $all) = helper_load_sim(
        $FOLDER_TYPE, 'folder_id', $settings, $params, 
        similarity_matrix_filename()
    );
    if (performed_render()) {
        return;
    }            
    # augment metadata with list of items ranked by similarity score
    for my $item_data (@$match_array) {
        my ($profiles_id, $item_name) = ($item_data->{'id'} =~ m/^([^-]+)-(.*)$/gxsm);
        $item_data->{'item'} = helper_get_sim_vector(
            $matches_info, $profiles_id, $item_name, $settings, $params,
            $item_ids1, $item_ids2, $sims
        );
        if (performed_render()) {
            return;
        }
    }

    # strip profiles_id prefix off front of item name
    for my $item_data (@$match_array) {
        ($item_data->{'id'}) = ($item_data->{'id'} =~ m/^[^-]+-(.*)$/gxsm);
    }

    my $text = serialise({'match' => $match_array});
    render({ 'text' => $text });
}


sub action_match_items_exists {
    my ($settings, $params) = @_;

    my $exists = helper_folders_exists($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $item_name = $params->{'item_id'};
    my $profiles_id = $params->{'profiles_id'};     #note: will be '' if none supplied

    if ($exists) {
        my (
            $matches_info_file, $matches_info, 
            $matches_data_file, $matches_data
           ) = helper_load_folder($FOLDER_TYPE, $settings, $params);
        if (performed_render()) {
            return;
        }

        if ($profiles_id eq '') {
            my $item_id1 = $matches_info->{'profiles_id1'} . '-' . $item_name;
            my $item_id2 = $matches_info->{'profiles_id2'} . '-' . $item_name;
            $exists = (exists $matches_data->{$item_id1} || exists $matches_data->{$item_id2}) ? $TRUE : $FALSE;
        }
        else {
            my $item_id = $profiles_id . '-' . $item_name;
            $exists = (exists $matches_data->{$item_id}) ? $TRUE : $FALSE;
        }
    }
    
    render({
        'status' => ($exists) ? '200 OK' : '404 Not Found',
        'text' => '',
    });
}


sub action_match_items_show {
    my ($settings, $params) = @_;

    my (
        $matches_info_file, $matches_info, 
        $matches_data_file, $matches_data
       ) = helper_load_folder($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $folder_id = $params->{'folder_id'};
    my $item_name = $params->{'item_id'};
    my $profiles_id = $params->{'profiles_id'};     #note: will be '' if none supplied
    my $full = $params->{'full'};

    # if no specific profiles supplied, try both
    if ($profiles_id eq '') {
        $profiles_id = $matches_info->{'profiles_id1'};
        if (!exists $matches_data->{ $profiles_id . '-' . $item_name }) {
            $profiles_id = $matches_info->{'profiles_id2'};
        }
    }
    
    my $item_id = $profiles_id . '-' . $item_name;
    if (!exists $matches_data->{$item_id}) {
        render({
            'status' => '404 Not Found',
            'text'   => serialise_error_message("No such match item: $item_name"),
        });
        return;
    }
    

    my $item_data = $matches_data->{$item_id};
    if ($full) {
        # augment $item with extra data retrieved from associated external file
        my $terms = helper_load_terms_for($FOLDER_TYPE, $settings, $params, $folder_id, $item_id);
        if (performed_render()) {
            return;
        }
        $item_data->{'term'} = helper_unpack_terms($params, $terms);
    }

    # load similarity matrix
    my ($item_ids1, $item_ids2, $sims, $all) = helper_load_sim(
        $FOLDER_TYPE, 'folder_id', $settings, $params, 
        similarity_matrix_filename()
    );
    if (performed_render()) {
        return;
    }            
    # augment metadata with list of items ranked by similarity score
    $item_data->{'item'} = helper_get_sim_vector(
        $matches_info, $profiles_id, $item_name, $settings, $params,
        $item_ids1, $item_ids2, $sims
    );


    # strip profiles_id prefix off front of item name
    ($item_data->{'id'}) = ($item_data->{'id'} =~ m/^[^-]+-(.*)$/gxsm);
    
    my $text = serialise({'match' => $item_data});
    render({ 'text' => $text });
}


1;