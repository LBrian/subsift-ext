# matches_controller.pl
use strict;
use warnings;

require '_folders_helper.pl';
require 'matches_helper.pl';

my $FALSE = 0;
my $TRUE  = 1;

my $FOLDER_TYPE = 'matches';
my $PROFILES_TYPE = 'profiles';


sub controller_matches {
    my ($settings, $params) = @_;

    if (defined $params->{'folder_id'} && $params->{'action'} ne 'create') {
        my $info = helper_folders_get_info($FOLDER_TYPE, $settings, $params);
        if (defined $info && $info->{'mode'} eq 'private') {
            # insist that request is authenticated
            error_unless_authenticated($settings, $params);
        }
    }
}


sub action_matches_list {
    my ($settings, $params) = @_;

    my $matches_arrayref = helper_list_folders($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $full = $params->{'full'};

    if ($full) {
        for my $matches_info (@$matches_arrayref) {
            helper_matches_addin_full($FOLDER_TYPE, $settings, $params, $matches_info);
            if (performed_render()) {
                return;
            }
        }
    }

    my $text = serialise({'folder' => $matches_arrayref});
    render({ 'text' => $text });
}


sub action_matches_create {
    my ($settings, $params) = @_;
    
    my $mode = $params->{'mode'};
    my $description = $params->{'description'};
    my $full = $params->{'full'};

    # computational parameters

    my $limit = $params->{'limit'};
    my $threshold = $params->{'threshold'};

    # default profiles folder ID values
    if (!defined $params->{'profiles_id1'} || $params->{'profiles_id1'} eq '') {
        $params->{'profiles_id1'} = $params->{'folder_id'};
    }
    if (!defined $params->{'profiles_id2'} || $params->{'profiles_id2'} eq '') {
        $params->{'profiles_id2'} = $params->{'profiles_id1'};
    }

    # get the metadata of the profiles we are matching
    # (also validates and gives us access to profile id param)
    my (
        $__profiles_info_file1, $profiles_info1, 
        $__profiles_data_file1, $profiles_data1
       ) = helper_load_folder_for($PROFILES_TYPE, $settings, $params, $params->{'profiles_id1'});
    if (performed_render()) {
        return;
    }
    my (
        $__profiles_info_file2, $profiles_info2, 
        $__profiles_data_file2, $profiles_data2
       ) = helper_load_folder_for($PROFILES_TYPE, $settings, $params, $params->{'profiles_id2'});
    if (performed_render()) {
        return;
    }

    # create profile info hash which will be serialised to a file in the created folder
    {
        my %info = (
              # generic "thing" parameters
            'type'              => undef,
            'id'                => undef,
            'mode'              => $mode,
            'description'       => $description,
            'created'           => undef,
            'modified'          => undef,
            'uri'               => undef,
              # ids of profiles to match against each other
            'profiles_id1'       => $profiles_info1->{'id'},
            'profiles_id2'       => $profiles_info2->{'id'},
              # computational parameters
            'limit'             => $limit,
            'threshold'         => $threshold,
        );
        helper_folders_create($FOLDER_TYPE, $settings, $params, \%info);
        if (performed_render()) {
            return;
        }
    }
    
    # get the metadata and file details of the profile just created
    my (
        $matches_info_file, $matches_info, 
        $matches_data_file, $matches_data
       ) = helper_load_folder($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    # compute a match scores for each item pair from the profile1 and profile2
    helper_match_profiles($FOLDER_TYPE, $settings, $params, 
        $matches_info, $matches_data, 
        $profiles_info1, $profiles_data1, $profiles_info2, $profiles_data2
    );
    if (performed_render()) {
        return;
    }

    my $match_array = helper_save_things_data($matches_data_file, $matches_data);
    if (performed_render()) {
        return;
    }
    helper_folders_put_info_file($matches_info_file, $matches_info);
    if (performed_render()) {
        return;
    }

    if ($full) {
        helper_matches_addin_full($FOLDER_TYPE, $settings, $params, $matches_info);
        if (performed_render()) {
            return;
        }
    }

    my $text = serialise({'folder' => $matches_info});
    render({
        'status'    => '201 Created',
        'headers'   => { 'Location' => $matches_info->{'uri'}, },
        'text'      => $text,
    });
}


sub action_matches_destroy {
    my ($settings, $params) = @_;

    my (
        $matches_info_file, $matches_info, 
        $matches_data_file, $matches_data
       ) = helper_load_folder($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $full = $params->{'full'};

    if ($full) {
        helper_matches_addin_full($FOLDER_TYPE, $settings, $params, $matches_info);
        if (performed_render()) {
            return;
        }
    }

    helper_folders_destroy($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $text = serialise({'folder' => $matches_info});
    render({ 'text' => $text });
}


sub action_matches_exists {
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


sub action_matches_show {
    my ($settings, $params) = @_;

    my (
        $matches_info_file, $matches_info, 
        $matches_data_file, $matches_data
       ) = helper_load_folder($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $full = $params->{'full'};

    if ($full) {
        helper_matches_addin_full($FOLDER_TYPE, $settings, $params, $matches_info);
        if (performed_render()) {
            return;
        }
    }

    my $text = serialise({'folder' => $matches_info});
    render({ 'text' => $text });
}


sub action_matches_update {
    my ($settings, $params) = @_;
    
    my (
        $matches_info_file, $matches_info, 
        $matches_data_file, $matches_data
       ) = helper_load_folder($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $mode = $params->{'mode'};
    my $description = $params->{'description'};
    my $full = $params->{'full'};

    # profiles that we are matching against each other
    my $profiles1_id = $matches_info->{'profiles_id1'};
    if (exists $params->{'profiles_id1'} && $params->{'profiles_id1'} ne '') {
        $profiles1_id = $params->{'profiles_id1'};
    }
    my $profiles2_id = $matches_info->{'profiles_id2'};
    if (exists $params->{'profiles_id2'} && $params->{'profiles_id2'} ne '') {
        $profiles2_id = $params->{'profiles_id2'};
    }

    # text processing and computational parameters

    my $limit = $params->{'limit'};
    my $threshold = $params->{'threshold'};


    # determine whether computational parameters have changed and invalidated the current stats
    my $recalculate = (
        $profiles1_id ne $matches_info->{'profiles_id1'} ||
        $profiles2_id ne $matches_info->{'profiles_id2'} ||
        !defined $matches_info->{'limit'} || $limit ne $matches_info->{'limit'} ||
        !defined $matches_info->{'threshold'} || $threshold ne $matches_info->{'threshold'}
    ) ? $TRUE : $FALSE;

    # update info hash which will be serialised to a file in the matches folder
    my $changed = $FALSE;
    my @properties = (
        ['profiles_id1',      'profiles_id1',      $profiles1_id], 
        ['profiles_id2',      'profiles_id2',      $profiles2_id], 
        ['mode',             'mode',             $mode], 
        ['description',      'description',      $description], 
        ['limit',            'limit',            $limit], 
        ['threshold',        'threshold',        $threshold], 
    );
    foreach (@properties) {
        my ($key, $cgi_key, $value) = @$_;
        if (exists $params->{$cgi_key} && (!defined $matches_info->{$key} || $matches_info->{$key} ne $value)) {
            $matches_info->{$key} = $value;
            $changed = $TRUE;
        }
    }
    if ($changed) {
        my $timestamp = time;
        $matches_info->{'modified'} = $timestamp;

        # if changed any of the computational parameters then must recalculate entire profile
        if ($recalculate) {

            # get the metadata of the profiles we are matching
            my (
                $__profiles_info_file1, $profiles_info1, 
                $__profiles_data_file1, $profiles_data1, 
               ) = helper_load_folder_for($PROFILES_TYPE, $settings, $params, $profiles1_id);
            if (performed_render()) {
                return;
            }
            my (
                $__profiles_info_file2, $profiles_info2, 
                $__profiles_data_file2, $profiles_data2, 
               ) = helper_load_folder_for($PROFILES_TYPE, $settings, $params, $profiles2_id);
            if (performed_render()) {
                return;
            }
    
            # compute a match scores for each item pair from the profile1 and profile2
            helper_match_profiles($FOLDER_TYPE, $settings, $params, 
                $matches_info, $matches_data, 
                $profiles_info1, $profiles_data1, $profiles_info2, $profiles_data2
            );
            if (performed_render()) {
                return;
            }

            my $match_array = helper_save_things_data($matches_data_file, $matches_data);
            if (performed_render()) {
                return;
            }
        }
        
        # save the matches folder metadata
        helper_folders_put_info_file($matches_info_file, $matches_info);
        if (performed_render()) {
            return;
        }
    }

    if ($full) {
        helper_matches_addin_full($FOLDER_TYPE, $settings, $params, $matches_info);
        if (performed_render()) {
            return;
        }
    }

    my $text = serialise({'folder' => $matches_info});
    render({ 'text' => $text });
}


sub action_matches_recalculate {
    my ($settings, $params) = @_;

    my (
        $matches_info_file, $matches_info, 
        $matches_data_file, $matches_data
       ) = helper_load_folder($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $full = $params->{'full'};

    my $timestamp = time;
    $matches_info->{'modified'} = $timestamp;

    # recalculate all pairwise comparisons

    # get the metadata of the profiles we are matching against each other
    my $profiles1_id = $matches_info->{'profiles_id1'};
    my (
        $__profiles_info_file1, $profiles_info1, 
        $__profiles_data_file1, $profiles_data1, 
       ) = helper_load_folder_for($PROFILES_TYPE, $settings, $params, $profiles1_id);
    if (performed_render()) {
        return;
    }
    my $profiles2_id = $matches_info->{'profiles_id2'};
    my (
        $__profiles_info_file2, $profiles_info2, 
        $__profiles_data_file2, $profiles_data2, 
       ) = helper_load_folder_for($PROFILES_TYPE, $settings, $params, $profiles2_id);
    if (performed_render()) {
        return;
    }

    # compute a match scores for each item pair from the profile1 and profile2
    helper_match_profiles($FOLDER_TYPE, $settings, $params, 
        $matches_info, $matches_data, 
        $profiles_info1, $profiles_data1, $profiles_info2, $profiles_data2
    );
    if (performed_render()) {
        return;
    }

    my $match_array = helper_save_things_data($matches_data_file, $matches_data);
    if (performed_render()) {
        return;
    }
        
    # save the matches folder metadata
    helper_folders_put_info_file($matches_info_file, $matches_info);
    if (performed_render()) {
        return;
    }

    if ($full) {
        helper_matches_addin_full($FOLDER_TYPE, $settings, $params, $matches_info);
        if (performed_render()) {
            return;
        }
    }

    my $text = serialise({'folder' => $matches_info});
    render({ 'text' => $text });
}


1;