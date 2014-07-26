# _things_helper.pl
#
#   This is a generic helper for rest services managing folders of things.
#   It looks after both a folder and a descriptive metadata file.
#   Also provides convenience savers/loaders and file management.
#
use strict;
use warnings;

my $FALSE = 0;
my $TRUE  = 1;

my $INFO_FILENAME = '_info.js';
my $DATA_FILENAME = '_data.js';

my $TRASH_FOLDER_NAME = 'trash';


sub helper_create_folder {
    #
    #   helper_create_folder(STRING $folder_type, HASHREF $settings, HASHREF $params, HASHREF $info)
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
    $info->{'uri'} = $settings->{'SITE_URL'} . '/' . $user_id . '/' . $folder_type . '/' . $folder_id;

    # create a folder for this list of things
    my $folder_info = File::Spec->catfile($folder_path, $INFO_FILENAME);
    File::Path::mkpath($folder_path);

    # serialise info data out to a file
    util_writeFile($folder_info, JSON->new->canonical->pretty->encode($info) );    
}


sub helper_destroy_folder {
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
        render({
            'status' => '404 Not Found',
            'text'   => serialise_error_message("No such $folder_type folder: $folder_id"),
        });
        return;
    }

    # ensure trash folder exists but preserve any older copies deleted earlier
    my $trash_path = File::Spec->catdir($settings->{'USERS_PATH'}, $user_id, $TRASH_FOLDER_NAME, $folder_type, $folder_id);
    if (-d $trash_path) {
        rename($trash_path, $trash_path . '.' . time);
    }
    File::Path::mkpath($trash_path);

    # move things folder to trash folder
    rename($folder_path, $trash_path);
}


sub helper_exists_folder {
    #
    # returns true if things folder exists
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
        return $FALSE;
    }

    # deserialise info hash for this things folder
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
                my (
                    $folder_info_file, $folder_info,
                    $things_data_file, $things_data,
                ) = helper_load_folder_for($folder_type, $settings, $params, $folder_id);
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


sub helper_load_folder_info {
    my ($folder_type, $settings, $params) = @_;

    my $user_id = $params->{'user_id'};
    my $folder_id = $params->{'folder_id'};

    return helper_load_folder_info_for($folder_type, $settings, $params, $user_id, $folder_id);
}


sub helper_load_folder_info_for {
    my ($folder_type, $settings, $params, $user_id, $folder_id) = @_;

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



sub helper_load_folder {
    my ($folder_type, $settings, $params) = @_;

    my $folder_id = $params->{'folder_id'};

    return helper_load_folder_for($folder_type, $settings, $params, $folder_id);
}

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
#FIXME: revert to this version once data migration to new representation finished
#            ?   map(($_->{'id'}), $_), @$array_ref)
            ?   map(($_->{'id'} || util_getValidFileName($_->{'name'}), $_), @$array_ref)
            :   ();
        $things_data = \%hash;
    }

    return ($folder_info_file, $folder_info, $things_data_file, $things_data);
}


sub helper_save_folder_info {
    my ($folder_info_file, $folder_info) = @_;
    
    util_writeFile($folder_info_file, JSON->new->canonical->pretty->encode($folder_info) );   
    return $folder_info;
}


sub helper_save_things_data {
    my ($items_data_file, $items_data) = @_;
    
    my $items_array = array_from_hash($items_data);
    util_writeFile($items_data_file, JSON->new->canonical->pretty->encode($items_array) );   
    return $items_array;
}



###########


sub helper_create_file {
    #
    #   helper_create_file(HASHREF $settings, HASHREF $params, HASHREF $info, STRING $data[, BOOL $replace])
    #
    my ($folder_type, $settings, $params, $info, $data, $replace) = @_;

    my $user_id = $params->{'user_id'};
    my $folder_id = $params->{'folder_id'};
    # santise item id so it is a valid filename too and make sure it is okay to use in a url without escaping
    # NOTE: assumes util_getValidFileName is idempotent, i.e. f(f(x)) == f(x), because it may already have been applied
    my $item_id = util_getValidFileName( $params->{'item_id'} );
    
    # whether to allow replacement of an existing file
    $replace = (defined $replace && $replace eq "$TRUE") ? $TRUE : $FALSE;

    my $user_path = File::Spec->catdir($settings->{'USERS_PATH'}, $user_id);
    if (!-d $user_path) {
        render({
            'status' => '404 Not Found',
            'text'   => serialise_error_message("No such user: $user_id"),
        });
        return;
    }

    # ensure folder exists
    my $folder_path = File::Spec->catdir($user_path, $folder_type, $folder_id);
    if (!-d $folder_path) {
        render({
            'status' => '404 Not Found',
            'text'   => serialise_error_message("No such $folder_type folder: $folder_id"),
        });
        return;
    }

    # ensure item data file does not already exist
    my $things_file = File::Spec->catfile($folder_path, $item_id);
    if (-f $things_file && !$replace) {
        render({
            'status' => '403 Forbidden',
            'text'   => serialise_error_message("Item already exists: $item_id"),
        });
        return;
    }

    # create a file for this file
    util_writeFile($things_file, $data, 'UTF-8');

    # populate missing fields in caller's info hash
    my $timestamp = time;  #note: this may be overridden by the called
    $info->{'type'} = $folder_type;
    $info->{'id'} = $item_id;
    $info->{'created'} = $info->{'created'} || $timestamp;
    $info->{'modified'} = $info->{'modified'} || $timestamp;
    $info->{'uri'} = $settings->{'SITE_URL'} . '/' . $user_id . '/' . $folder_type . '/' . $folder_id . '/items/' . $item_id;

    return;
}


sub helper_destroy_file {
    #
    # moves file to user's trash folder
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
    if (!-d $folder_path) {
        render({
            'status' => '404 Not Found',
            'text'   => serialise_error_message("No such $folder_type folder: $folder_id"),
        });
        return;
    }

    # resolve name of file file
    my $item_id = $info->{'id'};
    my $things_file = File::Spec->catfile($folder_path, $item_id);

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
    # fetch file's data (a file)
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
    if (!-d $folder_path) {
        render({
            'status' => '404 Not Found',
            'text'   => serialise_error_message("No such $folder_type folder: $folder_id"),
        });
        return;
    }

    # resolve name of file
    my $item_id = $info->{'id'};
    my $things_file = File::Spec->catfile($folder_path, $item_id);
    if (!-f $things_file) {
        render({
            'status' => '404 Not Found',
            'text'   => serialise_error_message("No data file for: $item_id"),
        });
        return;
    }

    return util_readFile($things_file);  #no UTF-8 conversion or get escaping bug in subsequent serialisation of hash!!
}


sub helper_save_file {
    #
    # store item's data (as a file)
    #
    my ($folder_type, $settings, $params, $info, $data) = @_;
    
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
        render({
            'status' => '404 Not Found',
            'text'   => serialise_error_message("No such $folder_type folder: $folder_id"),
        });
        return;
    }

    # resolve name of file
    my $item_id = $info->{'id'};
    my $things_file = File::Spec->catfile($folder_path, $item_id);

    util_writeFile($things_file, $data, 'UTF-8');
}


sub helper_resolve_path_for {
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

    return $folder_path;
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