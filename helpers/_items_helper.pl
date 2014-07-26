# _items_helper.pl
#
#   Manages random access to folder items held in a BerkeleyDB BTree with nice concurrent behaviour.
#	We use BTree to take advantage of disk locality when iterating through items.
#	Not using a Perl tied hash. Ensures best performance and can use modern BerkeleyDB features.
#
use strict;
use warnings;

use BerkeleyDB;

#FIXME: only require this for certain helper functions so maybe push down into those functions to avoid loading sqlite when not used
require '_items_index_helper.pl';

my $FALSE = 0;
my $TRUE  = 1;

my $ITEMS_DB_FILE = '_items.db';


use vars qw(%_DB_info);

sub _get_items_db {
	my ($key) = @_;
    return $_DB_info{$key};
}
sub _set_items_db {
    my ($key, $value) = @_;
    $_DB_info{$key} = $value;
    if (!defined $value) {
    	delete $_DB_info{$key};
    }
}



sub _helper_items_db_info {
	#
	#	HASHREF _helper_items_db_info(STRING $folder_path);
	#
    # Open a BerkelyDB to provide hash access to items keyed on their ids.
    # Will create a new db if doesn't already exist.
    #
	my ($folder_path) = @_;

	# re-use existing environment and hash instance (created by earlier call)
	my $existing_items_db = _get_items_db($folder_path);
	if (defined $existing_items_db) {
		return $existing_items_db;
	}

    my $db_env = new BerkeleyDB::Env ( 
       -Home   => $folder_path, 
       -Flags  => DB_CREATE | DB_INIT_CDB | DB_INIT_MPOOL
    ) or die "cannot open environment: $BerkeleyDB::Error\n";
    my $items_db_file = File::Spec->catfile($folder_path, $ITEMS_DB_FILE);
    $! = undef if $! eq 'File exists';

	my $items_db  = BerkeleyDB::Hash->new (
	   -Filename => $items_db_file, 
	   -Flags => DB_CREATE,
	   -Env  => $db_env
	) or die "couldn't create: $!, $BerkeleyDB::Error.\n";

	my $items_db_info = {
		'env'	=> $db_env,
		'file'	=> $items_db_file,
		'db' 	=> $items_db,
	};
	# make available globally (and allow us to avoid recreating in same cgi call)
	_set_items_db($folder_path, $items_db_info);

	return $items_db_info;
}


sub helper_items_create {
	my ($folder_type, $settings, $params, $items_info) = @_;

    my $folder_path = helper_folders_path($folder_type, $settings, $params);
    if (performed_render()) {
        return;
    }

    # insert items into random access database
    my $items_db_info = _helper_items_db_info($folder_path);
	my $items_db = $items_db_info->{'db'};
	for my $info (@$items_info) {
		$items_db->db_put($info->{'id'}, JSON->new->canonical->pretty->encode($info));
	}

	# insert item ids into sorted array of all item ids
	helper_items_index_create($folder_path, $items_info);
}


sub helper_items_put {
	my ($folder_type, $settings, $params, $item_info) = @_;

    my $folder_path = helper_folders_path($folder_type, $settings, $params);
    if (performed_render()) {
        return;
    }

    # update item in random access database
    my $items_db_info = _helper_items_db_info($folder_path);
	my $items_db = $items_db_info->{'db'};
	$items_db->db_put($item_info->{'id'}, JSON->new->canonical->pretty->encode($item_info));

	# no need to update item id in ids index as id is immutable
}


sub helper_items_get_range {
	my ($folder_type, $settings, $params, $page, $count, $folder_id) = @_;

    my $full = $params->{'full'};

    my $folder_path = helper_folders_path($folder_type, $settings, $params, $folder_id);
    if (performed_render()) {
        return;
    }

    # read a slice from a persistent sorted array of all item_ids
    my $item_ids = helper_items_index_get($folder_path, $page, $count);
    # random access database of item values, keyed on item_id
	my $items_db_info = _helper_items_db_info($folder_path);
	my $items_db = $items_db_info->{'db'};

    my @items = ();
	for my $item_id (@$item_ids) {
		my $item_str;
		$items_db->db_get($item_id, $item_str);
		my $item = JSON->new->decode($item_str);
		if (!$full) {
			delete $item->{'value'};
		}
		push(@items, $item);
	}

	return \@items;
}


sub helper_items_get {
	my ($folder_type, $settings, $params, $item_id, $folder_id) = @_;

    my $folder_path = helper_folders_path($folder_type, $settings, $params, $folder_id);
    if (performed_render()) {
        return;
    }

	my $items_db_info = _helper_items_db_info($folder_path);
	my $items_db = $items_db_info->{'db'};

	my $item_str;
	$items_db->db_get($item_id, $item_str);

	return (defined $item_str ? JSON->new->decode($item_str) : undef);
}


sub helper_items_exists {
	# checks for existence of a specific item_id or of a list of items
	my ($folder_type, $settings, $params, $items_or_items_id) = @_;

    my $folder_path = helper_folders_path($folder_type, $settings, $params);
    if (performed_render()) {
        return;
    }

	my $items_db_info = _helper_items_db_info($folder_path);
	my $items_db = $items_db_info->{'db'};

    my $arg_type = ref($items_or_items_id);
    my $exists = $FALSE;
    if ($arg_type eq 'ARRAY') {
    	# treat items_or_items_id as an array of items
    	for my $item (@$items_or_items_id) {
	    	my $item_str;
    		$items_db->db_get($item->{'id'}, $item_str);
	    	if (defined $item_str) {
	    		$exists = $TRUE;
	    		last;
	    	}
    	}
    }
    else {
    	# treat items_or_items_id as an item_id
    	my $item_str;
    	$items_db->db_get($items_or_items_id, $item_str);
    	if (defined $item_str) {
    		$exists = $TRUE;
    	}
    }

	return $exists;
}


sub helper_items_destroy {
	my ($folder_type, $settings, $params, $item_id) = @_;

    my $folder_path = helper_folders_path($folder_type, $settings, $params);
    if (performed_render()) {
        return;
    }

    # delete item serialisation from random access database
	my $items_db_info = _helper_items_db_info($folder_path);
	my $items_db = $items_db_info->{'db'};
	$items_db->db_del($item_id);

	# delete item_id from ids index database
	helper_items_index_destroy($folder_path, $item_id);
}


sub helper_items_destroy_all {
	my ($folder_type, $settings, $params) = @_;

    my $folder_path = helper_folders_path($folder_type, $settings, $params);
    if (performed_render()) {
        return;
    }

    # delete the random access database (will be recreated on next access)
	my $items_db_info = _helper_items_db_info($folder_path);
	$items_db_info->{'db'} = undef;
	$items_db_info->{'env'} = undef;
	unlink($items_db_info->{'file'});
	$items_db_info = undef;
	_set_items_db($folder_path, undef);

	# delete the ids index database (will be recreated on next access)
	helper_items_index_destroy_all($folder_path);
}


1;
