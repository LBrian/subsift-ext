# _items_index_helper.pl
#
#   Manages a simple single table SQLite database indexing a folder's item ids
#
use strict;
use warnings;

use DBI;

my $FALSE = 0;
my $TRUE  = 1;

my $FOLDER_ITEM_IDS_DB_FILE = '_ids.db';


use vars qw(%_IDS_DB_info);

sub _get_ids_db_info {
    my ($key) = @_;
    return $_IDS_DB_info{$key};
}
sub _set_ids_db_info {
    my ($key, $value) = @_;
    $_IDS_DB_info{$key} = $value;
    if (!defined $value) {
        delete $_IDS_DB_info{$key};
    }
}

=head
    $dbh->do("DROP TABLE IF EXISTS Cars");
    $dbh->do("CREATE TABLE Cars(Id INT PRIMARY KEY, Name TEXT, Price INT)");
    $dbh->do("INSERT INTO Cars VALUES(1,'Audi',52642)");
    $dbh->do("INSERT INTO Cars VALUES(2,'Mercedes',57127)");
    $dbh->do("INSERT INTO Cars VALUES(3,'Skoda',9000)");
    $dbh->do("INSERT INTO Cars VALUES(4,'Volvo',29000)");
    $dbh->do("INSERT INTO Cars VALUES(5,'Bentley',350000)");
    $dbh->do("INSERT INTO Cars VALUES(6,'Citroen',21000)");
    $dbh->do("INSERT INTO Cars VALUES(7,'Hummer',41400)");
    $dbh->do("INSERT INTO Cars VALUES(8,'Volkswagen',21600)");
    my $sth = $dbh->prepare("SELECT * FROM Cars LIMIT 5 OFFSET 3");
    $sth->execute();
    my $row;
    while ($row = $sth->fetchrow_arrayref()) {
        print STDERR "@$row[0] @$row[1] @$row[2]\n";
    }
=cut


sub _helper_items_index_db_open {
    #
    # idempotent sqlite database open, returning a hash of db info
    #
    my ($folder_path) = @_;

    # re-use existing sql instance (created by earlier call)
    my $existing_ids_db_info = _get_ids_db_info($folder_path);
    if (defined $existing_ids_db_info) {
        return $existing_ids_db_info;
    }

    my $ids_db_file = File::Spec->catfile($folder_path, $FOLDER_ITEM_IDS_DB_FILE);
    my $dbh = DBI->connect(          
        "dbi:SQLite:dbname=$ids_db_file", 
        "",
        "",
        { RaiseError => 1}
    ) or die $DBI::errstr;

#FIXME: workaround for 'No such file or directory' error after autocreation of a new db
local $!;
    $dbh->do('CREATE TABLE IF NOT EXISTS item_ids(id TEXT PRIMARY KEY ASC UNIQUE NOT NULL)');
#    $! = undef; #suppress 'No such file or directory' error arising if file had to be created

    my $ids_db_info = {
        'dbh'   => $dbh,
        'file'  => $ids_db_file,
    };
    _set_ids_db_info($folder_path, $ids_db_info);

    return $ids_db_info;
}

sub _helper_items_index_db_close {
    #
    # idempotent sqlite database close
    #
    my ($folder_path) = @_;

    my $ids_db_info = _get_ids_db_info($folder_path);
    if (!defined $ids_db_info) {
        return;
    }
    $ids_db_info->{'dbh'}->disconnect();

    _set_ids_db_info($folder_path, undef);
}


sub helper_items_index_create {
    my ($folder_path, $items_info) = @_;

    my $ids_db_info = _helper_items_index_db_open($folder_path);
    my $dbh = $ids_db_info->{'dbh'};

    my $sth = $dbh->prepare('INSERT INTO item_ids (id) VALUES (?)');
    $dbh->begin_work();
    for my $info (@$items_info) {
        $sth->bind_param(1, $info->{'id'});
        $sth->execute();
    }
    $dbh->commit();
    $sth->finish();

    _helper_items_index_db_close($folder_path);
}


sub helper_items_index_get {
    my ($folder_path, $page, $count) = @_;
    die "Invalid page < 1" if $page < 1.0;
    die "Invalid count < 1" if $count < 1.0;

    my $ids_db_info = _helper_items_index_db_open($folder_path);
    my $dbh = $ids_db_info->{'dbh'};

    my $from = ($page - 1) * $count;

    my $sth = $dbh->prepare('SELECT id FROM item_ids ORDER BY id ASC LIMIT ' . $dbh->quote($count) . ' OFFSET ' . $dbh->quote($from));
    $sth->execute();

    my @item_ids = ();
    my $row;
    while ($row = $sth->fetchrow_arrayref()) {
        push(@item_ids, @$row[0]);
    }
    $sth->finish();

    _helper_items_index_db_close($folder_path);

    return \@item_ids;
}


sub helper_items_index_size {
    my ($folder_path) = @_;

    my $ids_db_info = _helper_items_index_db_open($folder_path);
    my $dbh = $ids_db_info->{'dbh'};

#FIXME: workaround for 'No such file or directory' error after autocreation of a new db
local $!;
    my $count = $dbh->selectrow_array('SELECT count(*) FROM item_ids');

    _helper_items_index_db_close($folder_path);

    return $count;
}


sub helper_items_index_destroy {
    my ($folder_path, $item_id) = @_;

    my $ids_db_info = _helper_items_index_db_open($folder_path);
    my $dbh = $ids_db_info->{'dbh'};

    my $sth = $dbh->prepare("DELETE FROM item_ids WHERE id=?");
    $sth->bind_param(1, $item_id);
    $sth->execute();

    _helper_items_index_db_close($folder_path);
}


sub helper_items_index_destroy_all {
    my ($folder_path) = @_;

    my $ids_db_info = _helper_items_index_db_open($folder_path);
    my $ids_db_file = $ids_db_info->{'file'};
    _helper_items_index_db_close($folder_path);

    $ids_db_info->{'dbh'} = undef;
    $ids_db_info = undef;
    _set_ids_db_info($folder_path, undef);

    # we simply delete the sqlite db file and it will be recreated on next access
    unlink($ids_db_file);
}


1;