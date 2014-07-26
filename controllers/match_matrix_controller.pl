# match_matrix_controller.pl
use strict;
use warnings;

require '_folders_helper.pl';
require 'matches_helper.pl';

my $FALSE = 0;
my $TRUE  = 1;

my $FOLDER_TYPE = 'matches';


sub controller_match_matrix {
    my ($settings, $params) = @_;

    if (defined $params->{'folder_id'}) {
        my $info = helper_folders_get_info($FOLDER_TYPE, $settings, $params);
        if (defined $info && $info->{'mode'} eq 'private') {
            # insist that request is authenticated
            error_unless_authenticated($settings, $params);
        }
    }
}


sub action_match_matrix_show {
    my ($settings, $params) = @_;

    my (
        $matches_info_file, $matches_info, 
        $matches_data_file, $matches_data
       ) = helper_load_folder($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $item_name = $params->{'item_id'};
    my $type = $params->{'type'};
    
    my $separator = $params->{'separator'};
    my $separator_char = ',';   #default to comma
    if ($separator eq 'line') {
        $separator_char = "\n";
    }
    elsif ($separator eq 'space') {
        $separator_char = ' ';
    }
    elsif ($separator eq 'tab') {
        $separator_char = "\t";
    }
    elsif ($separator eq 'colon') {
        $separator_char = ':';
    }

    # load similarity matrix
    my ($item_ids1, $item_ids2, $sims, $csv) = helper_load_sim(
        $FOLDER_TYPE, 'folder_id', $settings, $params, 
        similarity_matrix_filename()
    );
    if (performed_render()) {
        return;
    }            

    my $text = '';
    #FIXME: no csv escaping or quoting of strings is done in raw serialisations below...
    if ($type eq 'rows') {
#        $text = serialise({'rows' => @$item_ids1});
        $text = join($separator_char, @$item_ids1);
    }
    elsif ($type eq 'columns') {
        $text = join($separator_char, @$item_ids2);
    }
    elsif ($type eq 'values') {
        my @lines = ();
        foreach my $row (@$sims) {
            push(@lines, join($separator_char, @$row));
        }
        $text = join("\n", @lines);
    }
    else {
        $text = $$csv;
    }
    render({
        'headers' => { 'Content-Disposition' => 'attachment; filename=' . $params->{'type'} . '.csv' },
        'text' => $text,
    });
}


sub action_match_matrix_show_pairs {
    my ($settings, $params) = @_;

    my (
        $matches_info_file, $matches_info, 
        $matches_data_file, $matches_data
       ) = helper_load_folder($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $item_name = $params->{'item_id'};
#    my $type = $params->{'type'};
    my $type = 'all';

    # load similarity pairs
    my ($pairs_hashref, $csv_strref) = helper_load_pairs_all(
        $FOLDER_TYPE, $settings, $params, 
        similarity_pairs_filename(),
        $matches_info, $matches_data
    );
    if (performed_render()) {
        return;
    }            

    #FIXME: no csv escaping of strings is done in raw serialisations below...
    my $text = $$csv_strref;

    render({
        'headers' => { 'Content-Disposition' => 'attachment; filename=' . $type . '.csv' },
        'text' => $text,
    });
}


1;