# profile_items_controller.pl
use strict;
use warnings;

require '_folders_helper.pl';
require 'profiles_helper.pl';

my $FALSE = 0;
my $TRUE  = 1;

my $FOLDER_TYPE = 'profiles';


sub controller_profile_items {
    my ($settings, $params) = @_;

    if (defined $params->{'folder_id'}) {
        my $info = helper_folders_get_info($FOLDER_TYPE, $settings, $params);
        if (defined $info && $info->{'mode'} eq 'private') {
            # insist that request is authenticated
            error_unless_authenticated($settings, $params);
        }
    }
}

sub action_profile_items_list {
    my ($settings, $params) = @_;

    my (
        $profiles_info_file, $profiles_info, 
        $profiles_data_file, $profiles_data
       ) = helper_load_folder($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $full = $params->{'full'};

    my $profile_array = array_from_hash($profiles_data);
    if ($full) {
        # augment with extra data retrieved from associated external file
        for my $item_data (@$profile_array) {
            my $terms = helper_load_terms_for(
                $FOLDER_TYPE, $settings, $params, $profiles_info->{'id'}, $item_data->{'id'}
            );
            if (performed_render()) {
                return;
            }
            $item_data->{'term'} = helper_unpack_terms($params, $terms);
        }
    }

    my $text = serialise({'profile' => $profile_array});
    render({ 'text' => $text });
}


sub action_profile_items_exists {
    my ($settings, $params) = @_;

    my $exists = helper_folders_exists($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $item_id = $params->{'item_id'};

    if ($exists) {
        my (
            $profiles_info_file, $profiles_info, 
            $profiles_data_file, $profiles_data
           ) = helper_load_folder($FOLDER_TYPE, $settings, $params);
        if (performed_render()) {
            return;
        }

        $exists = (exists $profiles_data->{$item_id}) ? $TRUE : $FALSE;
    }
    
    render({
        'status' => ($exists) ? '200 OK' : '404 Not Found',
        'text' => '',
    });
}


sub action_profile_items_show {
    my ($settings, $params) = @_;

    my (
        $profiles_info_file, $profiles_info, 
        $profiles_data_file, $profiles_data
       ) = helper_load_folder($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $folder_id = $params->{'folder_id'};
    my $item_id = $params->{'item_id'};
    my $full = $params->{'full'};

    if (!exists $profiles_data->{$item_id}) {
        render({
            'status' => '404 Not Found',
            'text'   => serialise_error_message("No such profile item: $item_id"),
        });
        return;
    }

    my $item_data = $profiles_data->{$item_id};
    if ($full) {
        # augment $item with extra data retrieved from associated external file
        my $terms = helper_load_terms_for($FOLDER_TYPE, $settings, $params, $folder_id, $item_data->{'id'});
        if (performed_render()) {
            return;
        }
        $item_data->{'term'} = helper_unpack_terms($params, $terms);
    }

    my $text = serialise({'profile' => $item_data});
    render({ 'text' => $text });
}


1;