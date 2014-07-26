# _folders_helper.pl
#
#   This is a generic helper for REST services managing folders of things.
#   It looks after both a folder and a descriptive metadata file.
#   Also provides convenience savers/loaders and file management.
#
use strict;
use warnings;

use File::Path qw(mkpath rmtree);  #warning: newer version of File::Path renames these as qw(make_path remove_tree)

my $FALSE = 0;
my $TRUE  = 1;

my $INFO_FILENAME = '_info.js';
my $DATA_FILENAME = '_data.js';

my $TRASH_FOLDER_NAME = 'trash';

my $DOCUMENT_FILE_EXTENSION = '.js';


sub helper_folders_create {
    #
    #   helper_folders_create(STRING $folder_type, HASHREF $settings, HASHREF $params, HASHREF $info)
    #
    #   Creates a folder in user's namespace and stores details in %$info
    #
    my ($folder_type, $settings, $params, $info) = @_;

    my $user_id = $params->{'user_id'};
    my $folder_id = $params->{'folder_id'};

    my $user_path = File::Spec->catdir($settings->{'USERS_PATH'}, $user_id);
    if (!-d $user_path) {
        render({
            'status' => '404 Not Found',
            'text'   => serialise_error_message("No such user: $user_id"),
        });
        return;
    }

    my $folder_path = File::Spec->catdir($user_path, $folder_type, $folder_id);
    if (-d $folder_path) {
        render({
            'status' => '403 Forbidden',
            'text'   => serialise_error_message("\u$folder_type folder already exists: $folder_id"),
        });
        return;
    }

    # populate info hash which will be serialised to a file in the created folder
    my $timestamp = time;
    $info->{'type'} = $folder_type;
    $info->{'id'} = $folder_id;
    $info->{'created'} = $timestamp;
    $info->{'modified'} = $timestamp;
    $info->{'uri'} = $settings->{'SITE_URI_BASE'} . '/' . $user_id . '/' . $folder_type . '/' . $folder_id;
    $info->{'default_item'}{'type'} = $folder_type;
    $info->{'default_item'}{'created'} = $timestamp;
    $info->{'default_item'}{'modified'} = $timestamp;

    # create a folder for this list of things
    my $folder_info = File::Spec->catfile($folder_path, $INFO_FILENAME);
    File::Path::mkpath($folder_path);
    chmod(0775, $folder_path);

    # serialise info data out to a file
    util_writeFile($folder_info, JSON->new->canonical->pretty->encode($info) );    
}


sub helper_folders_destroy {
    #
    # moves things folder to user's trash folder
    #
    my ($folder_type, $settings, $params) = @_;
    
    my $user_id = $params->{'user_id'};
    my $folder_id = $params->{'folder_id'};

    my $user_path = File::Spec->catdir($settings->{'USERS_PATH'}, $user_id);
    if (!-d $user_path) {
        render({
            'status' => '404 Not Found',
            'text'   => serialise_error_message("No such user: $user_id"),
        });
        return;
    }

    my $folder_path = File::Spec->catdir($user_path, $folder_type, $folder_id);
    if (!-d $folder_path) {
        # not an error if try to delete a non-existent folder
        return;
    }

    if ($settings->{'SOFT_DELETE'}) {
        #
        # soft_delete: move folder to user's trash folder (and possibly rename)
        #

        # ensure trash folder exists but preserve any older copies deleted earlier
        my $trash_path = File::Spec->catdir($settings->{'USERS_PATH'}, $user_id, $TRASH_FOLDER_NAME, $folder_type, $folder_id);
        if (-d $trash_path) {
            rename($trash_path, $trash_path . '.' . time);
        }
        File::Path::mkpath($trash_path);

        # move things folder to trash folder
        rename($folder_path, $trash_path);
    }
    else {
        #
        # hard_delete: physically delete the folder
        #
        File::Path::rmtree($folder_path);
    }
}


sub helper_folders_exists {
    #
    # returns true if things folder exists ($folder_id is optional)
    #
    my ($folder_type, $settings, $params, $folder_id) = @_;
    
    my $user_id = $params->{'user_id'};
    if (!defined $folder_id) {
        $folder_id = $params->{'folder_id'};
    }

    my $user_path = File::Spec->catdir($settings->{'USERS_PATH'}, $user_id);
    if (!-d $user_path) {
        render({
            'status' => '404 Not Found',
            'text'   => serialise_error_message("No such user: $user_id"),
        });
        return;
    }

    my $folder_path = File::Spec->catdir($user_path, $folder_type, $folder_id);
    if (!-d $folder_path) {
        return $FALSE;
    }

    # check existence of info file for this folder
    my $folder_info_file = File::Spec->catfile($folder_path, $INFO_FILENAME);
    if (!-e $folder_info_file) {
        return $FALSE;
    }

    return $TRUE;
}


sub helper_list_folders {
    #
    # lists thing folders (returning metadata for each thing in list)
    #
    my ($folder_type, $settings, $params) = @_;

    my $user_id = $params->{'user_id'};

    my $user_path = File::Spec->catdir($settings->{'USERS_PATH'}, $user_id);
    if (!-d $user_path) {
        render({
            'status' => '404 Not Found',
            'text'   => serialise_error_message("No such user: $user_id"),
        });
        return;
    }

    # build a list of "things" folders for this user
    my $folder_path = File::Spec->catdir($user_path, $folder_type);
    my @things = ();
    if (-d $folder_path) {
        my @files = glob(File::Spec->catdir($folder_path, '*'));
        for my $file (@files) {
            if (-d $file) {
                # we only want the directory name without the path
                my $folder_id = File::Basename::basename($file);
                # load the metadata for this folder
                my $folder_info = helper_folders_get_info($folder_type, $settings, $params, $folder_id);
                # only show folders that the user has permission to see
                if ($folder_info->{'mode'} eq 'public' ||
                    ($folder_info->{'mode'} eq 'private' && is_authenticated($settings, $params))
                   ) {
                       push(@things, $folder_info);
                }
            }
        }
    }

    return \@things;
}


##########


sub helper_folders_path {
    #
    # STRING helper_folders_path(STRING $folder_type, HASHREF $settings, HASHREF $params[, STRING $folder_id])
    #
    my ($folder_type, $settings, $params, $folder_id) = @_;
    
    my $user_id = $params->{'user_id'};

    # set default folder_id if not supplied
    if (!defined $folder_id) {
        $folder_id = $params->{'folder_id'};
    }

    my $user_path = File::Spec->catdir($settings->{'USERS_PATH'}, $user_id);
    if (!-d $user_path) {
        render({
            'status' => '404 Not Found',
            'text'   => serialise_error_message("No such user: $user_id"),
        });
        return;
    }

    my $folder_path = File::Spec->catdir($user_path, $folder_type, $folder_id);
    if (!-d $folder_path) {
        render({
            'status' => '404 Not Found',
            'text'   => serialise_error_message("No such $folder_type folder: $folder_id"),
        });
        return;
    }

    return $folder_path;
}


sub helper_folders_get_info {
    #
    # HASHREF helper_folders_get_info($folder_type, $settings, $params[, $folder_id]);
    #
    my ($folder_type, $settings, $params, $folder_id) = @_;

    my $folder_path = helper_folders_path($folder_type, $settings, $params, $folder_id);
    if (performed_render()) {
        return;
    }

    # deserialise info hash for this things folder
    my $folder_info_file = File::Spec->catfile($folder_path, $INFO_FILENAME);
    if (!-e $folder_info_file) {
        render({
            'status' => '404 Not Found',
            'text'   => serialise_error_message("Missing info file for: $folder_id"),
        });
        return;
    }
    
    return JSON->new->decode( util_readFile($folder_info_file) );
}


sub helper_folders_put_info {
    #
    # HASHREF helper_folders_put_info($folder_type, $settings, $params, $folder_info);
    #
    my ($folder_type, $settings, $params, $folder_info) = @_;

    my $folder_path = helper_folders_path($folder_type, $settings, $params);
    if (performed_render()) {
        return;
    }

    # deserialise info hash for this things folder
    my $folder_info_file = File::Spec->catfile($folder_path, $INFO_FILENAME);
    util_writeFile($folder_info_file, JSON->new->canonical->pretty->encode($folder_info) );
}


#sub helper_folders_put_info_file { die "deprecated"; }
sub helper_folders_put_info_file {
    my ($folder_info_file, $folder_info) = @_;
    
    util_writeFile($folder_info_file, JSON->new->canonical->pretty->encode($folder_info) );
    return $folder_info;
}


#######################################------ FOLLOWING STUFF MOSTLY BELONGS IN _items_helper.pl

#sub helper_load_folder { die "deprecated"; }
sub helper_load_folder {
    my ($folder_type, $settings, $params) = @_;

    my $folder_id = $params->{'folder_id'};

    return helper_load_folder_for($folder_type, $settings, $params, $folder_id);
}

#sub helper_load_folder_for { die "deprecated"; }
sub helper_load_folder_for {
    my ($folder_type, $settings, $params, $folder_id) = @_;

    my $user_id = $params->{'user_id'};

    my $user_path = File::Spec->catdir($settings->{'USERS_PATH'}, $user_id);
    if (!-d $user_path) {
        render({
            'status' => '404 Not Found',
            'text'   => serialise_error_message("No such user: $user_id"),
        });
        return;
    }

    my $folder_path = File::Spec->catdir($user_path, $folder_type, $folder_id);
    if (!-d $folder_path) {
        render({
            'status' => '404 Not Found',
            'text'   => serialise_error_message("No such $folder_type folder: $folder_id"),
        });
        return;
    }

    # deserialise info hash for this folder
    my $folder_info_file = File::Spec->catfile($folder_path, $INFO_FILENAME);
    if (!-e $folder_info_file) {
        render({
            'status' => '404 Not Found',
            'text'   => serialise_error_message("Missing info file for: $folder_id"),
        });
        return;
    }
    my $folder_info = JSON->new->decode( util_readFile($folder_info_file) );

    # create or deserialise this folder's items metadata
    my $things_data_file = File::Spec->catfile($folder_path, $DATA_FILENAME);
    my $things_data;
    if (!-e $things_data_file) {
        $things_data = {};
    }
    else {
        # deserialise an array of item hashes
        my $array_ref = JSON->new->decode( util_readFile($things_data_file) );
        my %hash = (scalar(@$array_ref) > 0)
            ?   map(($_->{'id'}, $_), @$array_ref)
            :   ();
        $things_data = \%hash;
    }

    return ($folder_info_file, $folder_info, $things_data_file, $things_data);
}


#sub helper_save_things_data { die "deprecated"; }
sub helper_save_things_data {
    my ($items_data_file, $items_data) = @_;
    
    my $items_array = array_from_hash($items_data);
    util_writeFile($items_data_file, JSON->new->canonical->pretty->encode($items_array) );   
    return $items_array;
}



###########


sub helper_create_file {
    #
    #   helper_create_file(HASHREF $settings, HASHREF $params, HASHREF $info, HASHREF $data[, BOOL $replace])
    #
    my ($folder_type, $settings, $params, $info, $data, $replace) = @_;

    my $user_id = $params->{'user_id'};
    my $folder_id = $params->{'folder_id'};

#    # santise item id so it is a valid filename too and make sure it is okay to use in a url without escaping
#    # NOTE: assumes util_getValidFileName is idempotent, i.e. f(f(x)) == f(x), because it may already have been applied
#    my $item_id = util_getValidFileName( $params->{'item_id'} );
    my $item_id = $info->{'id'};
    
    # whether to allow replacement of an existing file
    $replace = (defined $replace && $replace eq "$TRUE") ? $TRUE : $FALSE;

    my $folder_path = helper_folders_path($folder_type, $settings, $params, $folder_id);
    if (performed_render()) {
        return;
    }

    # ensure item data file does not already exist
    my $things_file = File::Spec->catfile($folder_path, $item_id . $DOCUMENT_FILE_EXTENSION);
    if (-f $things_file && !$replace) {
        render({
            'status' => '403 Forbidden',
            'text'   => serialise_error_message("Item already exists: $item_id"),
        });
        return;
    }

    # serialise data to its own file
##    util_writeFile($things_file, $data, 'UTF-8');
    util_writeFile($things_file, JSON->new->canonical->pretty->encode($data) );


    # populate missing fields in caller's info hash
    my $timestamp = time;  #note: this may be overridden by the called
    $info->{'type'} = $folder_type;
    $info->{'id'} = $item_id;
    $info->{'created'} = $info->{'created'} || $timestamp;
    $info->{'modified'} = $info->{'modified'} || $timestamp;
    $info->{'uri'} = $settings->{'SITE_URI_BASE'} . '/' . $user_id . '/' . $folder_type . '/' . $folder_id . '/items/' . $item_id;

    return;
}


sub helper_destroy_file {
    #
    # moves file to user's trash folder
    #
    my ($folder_type, $settings, $params, $info) = @_;
    
    my $user_id = $params->{'user_id'};
    my $folder_id = $params->{'folder_id'};

    my $folder_path = helper_folders_path($folder_type, $settings, $params, $folder_id);
    if (performed_render()) {
        return;
    }

    # resolve name of file file
    my $item_id = $info->{'id'};
    my $things_file = File::Spec->catfile($folder_path, $item_id . $DOCUMENT_FILE_EXTENSION);

    # ensure trash folder exists
    my $trash_path = File::Spec->catdir($settings->{'USERS_PATH'}, $user_id, $TRASH_FOLDER_NAME, $folder_type, $folder_id);
    if (!-d $trash_path) {
        File::Path::mkpath($trash_path);
    }

    # if file already exists in trash folder preserve any older copies deleted earlier
    my $trash_file = File::Spec->catfile($trash_path, $item_id);
    if (-f $trash_file) {
        rename($trash_file, $trash_file . '.' . time);
    }

    # move file to trash folder
    rename($things_file, $trash_file);
}


sub helper_load_file {
    #
    # fetch file's data (a json file)
    #
    my ($folder_type, $settings, $params, $info, $folder_id) = @_;

    my $folder_path = helper_folders_path($folder_type, $settings, $params, $folder_id);
    if (performed_render()) {
        return;
    }

    # resolve name of file
    my $item_id = $info->{'id'};
    my $things_file = File::Spec->catfile($folder_path, $item_id . $DOCUMENT_FILE_EXTENSION);
    if (!-f $things_file) {
        render({
            'status' => '404 Not Found',
            'text'   => serialise_error_message("No data file for: $item_id"),
        });
        return;
    }

#    return util_readFile($things_file);  #no UTF-8 conversion or get escaping bug in subsequent serialisation of hash!!
    return JSON->new->decode( util_readFile($things_file) );

}


sub helper_save_file {
    #
    # store item's data (as a json file)
    #
    my ($folder_type, $settings, $params, $info, $value, $folder_id) = @_;
    
    my $folder_path = helper_folders_path($folder_type, $settings, $params, $folder_id);
    if (performed_render()) {
        return;
    }

    # resolve name of file
    my $item_id = $info->{'id'};
    my $things_file = File::Spec->catfile($folder_path, $item_id . $DOCUMENT_FILE_EXTENSION);

#    util_writeFile($things_file, $data, 'UTF-8');
    util_writeFile($things_file, JSON->new->canonical->pretty->encode($value) );

}


###########

sub array_from_hash {
    #
    # returns canonically ordered (sorted by hash key) array of hash values
    #
    my ($hash_ref) = @_;
    my @array = map($hash_ref->{$_}, sort keys %{$hash_ref});
    return \@array;
}


1;