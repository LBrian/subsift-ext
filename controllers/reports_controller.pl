# reports_controller.pl
use strict;
use warnings;

require '_folders_helper.pl';
require 'reports_helper.pl';

my $FALSE = 0;
my $TRUE  = 1;

my $FOLDER_TYPE   = 'reports';
my $PROFILES_TYPE = 'profiles';
my $MATCHES_TYPE  = 'matches';


sub controller_reports {
    my ($settings, $params) = @_;
    
    if (defined $params->{'folder_id'} && $params->{'action'} !~ /^create/xms) {
        my $info = helper_folders_get_info($FOLDER_TYPE, $settings, $params);
        if (defined $info && $info->{'mode'} eq 'private') {
            # insist that request is authenticated
            error_unless_authenticated($settings, $params);
        }
    }
}


sub action_reports_view {
    #
    # render a static file from this reports folder
    #
    my ($settings, $params) = @_;

    my $format = $params->{'format'};
    my $file   = $params->{'file'};
    my $folder_id = $params->{'folder_id'};

    my $folder_path = helper_folders_path($FOLDER_TYPE, $settings, $params, $folder_id);
    if (performed_render()) {
        return;
    }

    my $filename = File::Spec->catfile($folder_path, $file . '.' . $format);
    if (!-e $filename) {
        render({
            'status' => '404 Not Found',
            'text' => '',
        });
        return;
    }

    my $text = util_readFile($filename);
    render({ 'text' => $text });
}


sub action_reports_list {
    my ($settings, $params) = @_;

    my $reports_arrayref = helper_list_folders($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $text = serialise({'folder' => $reports_arrayref});
    render({ 'text' => $text });
}

sub action_reports_create_profiles {
    my ($settings, $params) = @_;

    if (!defined $params->{'profiles_id'} || $params->{'profiles_id'} eq '') {
        # default to profiles folder ID being the same as the reports folder ID
        $params->{'profiles_id'} = $params->{'folder_id'};
    }
    # Changes made by Brian Liu
	if($params->{'topic'} == $TRUE) {
		return action_topic_reports_create($settings, $params);
	}else{
    	return action_reports_create($settings, $params);
	}
}

# Author: Brian Liu
sub action_topic_reports_create {
    my ($settings, $params) = @_;
    
    my $mode = $params->{'mode'};
    my $description = $params->{'description'};
    my $type = $params->{'type'};

    my $profiles_id = $params->{'profiles_id'};
    my $matches_id = $params->{'matches_id'};

    # create info hash which will be serialised to a file in the created folder
    my $timestamp = time;
    my %info = (
        'id'            => undef,           # will be supplied by helper
        'mode'          => $mode,
        'description'   => $description,
        'created'       => $timestamp,
        'modified'      => $timestamp,
    );
    if (defined $profiles_id && $profiles_id ne '') {
        $info{'profiles_id'} = $profiles_id;
    }
    if (defined $matches_id && $matches_id ne '') {
        $info{'matches_id'} = $matches_id;
    }

    # create the report folder
    helper_folders_create($FOLDER_TYPE, $settings, $params, \%info);
    if (performed_render()) {
        return;
    }

    # generate report files
    if (defined $profiles_id && $profiles_id ne '') {
        # get the metadata of the profiles we are matching
        # (also validates and gives us access to profile id param)
        my (
            $__profiles_info_file, $profiles_info, 
            $__profiles_data_file, $profiles_data
           ) = helper_load_folder_for($PROFILES_TYPE, $settings, $params, $profiles_id);
        if (performed_render()) {
            return;
        }
        # Author: Brian Liu
        helper_topic_reports_profiles($FOLDER_TYPE, $settings, $params,
            \%info,
            $profiles_info, $profiles_data
        );
        if (performed_render()) {
            return;
        }
    }
    if (defined $matches_id && $matches_id ne '') {
        my (
            $__matches_info_file, $matches_info, 
            $__matches_data_file, $matches_data
        ) = helper_load_folder_for($MATCHES_TYPE, $settings, $params, $matches_id);
        if (performed_render()) {
            return;
        }

        if ($type eq 'html') {
            helper_reports_matches_html($FOLDER_TYPE, $settings, $params,
                \%info,
                $matches_info, $matches_data
            );
        }
        elsif ($type eq 'graphviz') {
            helper_reports_matches_graphviz($FOLDER_TYPE, $settings, $params,
                \%info,
                $matches_info, $matches_data
            );
        }
        if (performed_render()) {
            return;
        }
    }
    
    # compose response text
    my $text = serialise({'folder' => \%info});

    render({
        'status'    => '201 Created',
        'headers'   => { 'Location' => $info{'uri'}, },
        'text'      => $text,
    });
}

sub action_reports_create_matches {
    my ($settings, $params) = @_;

    if (!defined $params->{'matches_id'} || $params->{'matches_id'} eq '') {
        # default to matches folder ID being the same as the reports folder ID
        $params->{'matches_id'} = $params->{'folder_id'};
    }
    # Changes ma Brian Liu
    if($params->{'topic'}) {
		return action_topic_reports_create($settings, $params);
	}else{
    	return action_reports_create($settings, $params);
	}
}

sub action_reports_create {
    my ($settings, $params) = @_;
    
    my $mode = $params->{'mode'};
    my $description = $params->{'description'};
    my $type = $params->{'type'};

    my $profiles_id = $params->{'profiles_id'};
    my $matches_id = $params->{'matches_id'};

    # create info hash which will be serialised to a file in the created folder
    my $timestamp = time;
    my %info = (
        'id'            => undef,           # will be supplied by helper
        'mode'          => $mode,
        'description'   => $description,
        'created'       => $timestamp,
        'modified'      => $timestamp,
    );
    if (defined $profiles_id && $profiles_id ne '') {
        $info{'profiles_id'} = $profiles_id;
    }
    if (defined $matches_id && $matches_id ne '') {
        $info{'matches_id'} = $matches_id;
    }

    # create the report folder
    helper_folders_create($FOLDER_TYPE, $settings, $params, \%info);
    if (performed_render()) {
        return;
    }

    # generate report files
    if (defined $profiles_id && $profiles_id ne '') {
        # get the metadata of the profiles we are matching
        # (also validates and gives us access to profile id param)
        my (
            $__profiles_info_file, $profiles_info, 
            $__profiles_data_file, $profiles_data
           ) = helper_load_folder_for($PROFILES_TYPE, $settings, $params, $profiles_id);
        if (performed_render()) {
            return;
        }
        helper_reports_profiles($FOLDER_TYPE, $settings, $params,
            \%info,
            $profiles_info, $profiles_data
        );
        if (performed_render()) {
            return;
        }
    }
    if (defined $matches_id && $matches_id ne '') {
        my (
            $__matches_info_file, $matches_info, 
            $__matches_data_file, $matches_data
        ) = helper_load_folder_for($MATCHES_TYPE, $settings, $params, $matches_id);
        if (performed_render()) {
            return;
        }

        if ($type eq 'html') {
            helper_reports_matches_html($FOLDER_TYPE, $settings, $params,
                \%info,
                $matches_info, $matches_data
            );
        }
        elsif ($type eq 'graphviz') {
            helper_reports_matches_graphviz($FOLDER_TYPE, $settings, $params,
                \%info,
                $matches_info, $matches_data
            );
        }
        if (performed_render()) {
            return;
        }
    }
    
    # compose response text
    my $text = serialise({'folder' => \%info});

    render({
        'status'    => '201 Created',
        'headers'   => { 'Location' => $info{'uri'}, },
        'text'      => $text,
    });
}


sub action_reports_destroy {
    my ($settings, $params) = @_;

    my (
        $report_info_file, $report_info, 
        $report_data_file, $report_data
       ) = helper_load_folder($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    helper_folders_destroy($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $text = serialise({'folder' => $report_info});
    render({ 'text' => $text });
}


sub action_reports_exists {
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


sub action_reports_show {
    my ($settings, $params) = @_;

    my (
        $report_info_file, $report_info, 
        $report_data_file, $report_data
       ) = helper_load_folder($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $text = serialise({'folder' => $report_info});
    render({ 'text' => $text });

}


sub action_reports_update {
    my ($settings, $params) = @_;
    
    my (
        $report_info_file, $report_info, 
        $report_data_file, $report_data
       ) = helper_load_folder($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $mode = $params->{'mode'};
    my $description = $params->{'description'};

    # update info hash which will be serialised to a file in the report folder
    my $changed = $FALSE;
    my @properties = (
        ['mode',        'mode',         $mode], 
        ['description', 'description',  $description], 
    );
    foreach (@properties) {
        my ($key, $cgi_key, $value) = @$_;
        if (exists $params->{$cgi_key} && $report_info->{$key} ne $value) {
            $report_info->{$key} = $value;
            $changed = $TRUE;
        }
    }
    if ($changed) {
        $report_info->{'modified'} = time;
        my $report_array = helper_folders_put_info_file($report_info_file, $report_info);
        if (performed_render()) {
            return;
        }
    }

    my $text = serialise({'folder' => $report_info});
    render({ 'text' => $text });
}


sub action_reports_unknown {
    my ($settings, $params) = @_;

    my $action_unescaped = $params->{'action'} || 'undef';

    render({
        'status' => '400 Bad Request',
        'text'   => serialise_error_message("Unknown action: $action_unescaped"),
    });
}


1;