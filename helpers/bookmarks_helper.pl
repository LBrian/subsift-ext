# bookmarks_helper.pl
use strict;
use warnings;

require 'csv.pl';


my $FALSE = 0;
my $TRUE  = 1;


sub helper_parse_items_list {
    #
    #   ARRAYREF helper_parse_items_list(STRING $items_list)
    #
    #   Parse string of text lines where each line is one of the formats:
    #       url
    #       id, url
    #       id, description, url
    #
    #   Returns an array of [id, description, url] arrays. If description or id are missing then
    #   unique ids (and/or descriptions) are generated automatically.
    #
    my ($items_list) = @_;
    my @items_list = ();
    if (!defined $items_list) {
        return \@items_list;
    }

    my $err;
    eval{
        @items_list = @{csv_parse_string($items_list)};
    };
    if ($@) {
        $err = $@;
    } elsif ($!) {
        $err = $!;
    }
    if (defined $err) {
        warn_message('csv parse error: ' . $err);
        render({
            'status' => '400 Bad Request',
            'text'   => serialise_error_message('Invalid items_list'),
        });
        return \@items_list;
    }

    my %used_names = ();
    my $i = 0;
    foreach my $item (@items_list) {
        $i++;
        # accept one, two or three fields per line
        my $n = scalar(@$item);
        if ($n > 3) {
            # collapse text of rightmost fields to a single url field
            $item->[2] = join(',', @$item[2..(scalar(@$item)-1)]);
            # truncate to first three fields
            @$item = @$item[0..2];
        }
        elsif ($n == 2) {
            # treat first field as both id and name, shifting the url to third
            $item->[2] = $item->[1];
            $item->[1] = $item->[0];
        }
        elsif ($n == 1) {
            # treat single field as the url and invent a unique id, name
            $item->[2] = $item->[0];
            $item->[1] = "item$i";
            $item->[0] = $item->[1];
        }
        if (!(defined $item->[0] && $item->[0] ne '' &&
              defined $item->[1] && $item->[1] ne '' &&
              defined $item->[2] && $item->[2] ne '')
           ) {
            render({
                'status' => '400 Bad Request',
                'text'   => serialise_error_message("Invalid items_list at line $i"),
            });
            return;
        }
        
        # map id string to an acceptable valid id
        $item->[0] = util_getValidFileName($item->[0]);
        
        if (exists $used_names{$item->[0]}) {
            render({
                'status' => '400 Bad Request',
                'text'   => serialise_error_message("Invalid items_list, id '$item->[0]' is not unique at line $i"),
            });
            return;
        }
        $used_names{$item->[0]} = $TRUE;
    }

    return \@items_list;
}


sub helper_default_url_prefix {
    my ($str) = @_;
    return (defined $str && $str ne '' && $str !~ m{^(?:http|https)://})
        ?   $str = 'http://' . $str
        :   $str;
}


sub helper_is_valid_url {
    my ($str) = @_;
    #FIXME: would be better to use a perl url parsing module function to test the url rather than this simple regex
#    return ($str =~ m{^(?:http|https)://(?:[a-zA-Z0-9][a-zA-Z0-9\-]*)(\.[a-zA-Z0-9])*[a-zA-Z0-9/+=%&_\.~?\-]*$}xms) ? $TRUE : $FALSE;
    #FIXME: the above regex is too strict for general purpose use!!
    return ($str =~ m{^(?:http|https)://.+}xms) ? $TRUE : $FALSE;
}


1;