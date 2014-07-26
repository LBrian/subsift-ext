# dblp_helper.pl
use strict;
use warnings;

use URI::Escape qw(uri_escape);

# to gain access to raw cgi params
require 'params.pl';

my $FALSE = 0;
my $TRUE  = 1;


sub helper_dblp_search_results {
    #
    #   HASHREF helper_dblp_search_results(STRING $names_list)
    #
    # Search DBLP for each name in submitted list of names and build a new list in csv format:
    # <name>, <author_name>, <author_uri>
    # Also report names for which there were no results on DBLP.
    #
    my ($names_list) = @_;

    my @names = grep( /.+/, split(/\s*[\n\r]+\s*/, $names_list) );

    my @names_found = ();
    my @names_missing = ();
    my @names_singles = ();
    my @names_choices = ();
    my $i = 0;
    for my $name (@names) {
        #
        # search DBLP and get either author page or a DBLP disambiguation page
        #
        my $uri = 'http://dblp.uni-trier.de/search/author?author=' 
                  . URI::Escape::uri_escape($name);

        my $res = http_get(url => $uri);
        if ($res->{'content'} =~ m{<title>Author\ Search</title>}gmxs) {
            # none or multiple matches, so add all returned uris to the list
            my $j = 0;
            my @options = ();
            while ($res->{'content'} =~ m{<li><a\ href="([^"]+)">([^<]+)</a></li>}gmxs) {
                push(@names_found, {'id'=>"_${i}_${j}", 'name'=>$2, 'description'=>$name, 'uri'=>$1});
                my $good_match = (lc($name) eq lc($2)) ? $TRUE : $FALSE;
                push(@options, {'id'=>"_${i}_${j}", 'name'=>$2, 'uri'=>$1, 'checked'=>$good_match});
                $j++;
            }
            if ($j > 0) {
                push(@names_choices, {'search_term'=>$name, 'options'=>\@options});
            }
            else {
                # no matches
                push(@names_found, {'name'=>'?', 'description'=>$name, 'uri'=>'http://www.informatik.uni-trier.de/~ley/db/indices/a-tree/index.html'});
                # remember which names didn't match for subsequent error message
                push(@names_missing, $name);
            }
        }
        else {
            # single match, so just add uri to the list
            my ($matched_name) = $res->{'content'} =~ m{<title>DBLP:\ ([^<]+)</title>}mxs;
            push(@names_found, {'id'=>"_${i}_1", 'name'=>$matched_name, 'description'=>$name, 'uri'=>$uri});
            push(@names_singles, {'id'=>"_${i}_1", 'name'=>$matched_name, 'description'=>$name, 'uri'=>$uri});
        }
        $i++;
    }

    return {
        'list' => \@names_found,
        'choices' => ((scalar @names_choices > 0) ? \@names_choices : undef),
        'singles' => ((scalar @names_singles > 0) ? \@names_singles : undef),
        'missing' => ((scalar @names_missing > 0) ? \@names_missing : undef),
    };
}



sub helper_dblp_search_restrict {
    #
    #   ARRAYREF helper_dblp_search_restrict(STRING $names_list, $aggregate_uri)
    #
    # Restrict the full list of search results according to user selections and build a new list in csv format:
    # <name>, <author_name>, <aggregated_author_uri>
    # Where <aggregated_author_uri> is the uri of subsift's dblp_extract method
    # with (potentially) multiple uris as arguments (allowing aggregated author pages).
    #
    my ($names_list, $dblp_extract_uri) = @_;

    # postpend a query string start character if not there already
    if ($dblp_extract_uri !~ m/\?$/) {
        $dblp_extract_uri .= '?';
    }

    # for each person, build an array of author page(s) details
    my %names_selected = ();
    my $raw_params = get_raw_params();
    for my $line (grep(/.+/, split(/\s*[\n\r]+\s*/, $names_list))) {
        my ($id, $name, $description, $uri) = $line =~ m{^\s*([^,]+),\s*([^,]+),\s*([^,]+),\s*(.+)\s*$}mxs;
        if (defined $raw_params->{$id}) {
            push(@{$names_selected{$description}}, {'name'=>$name, 'description'=>$description, 'uri'=>$uri});
        }
    }
    
    # rebuild list of authors, constructing a single dblp_extract url for each person
    my @authors = ();
    for my $name (sort keys %names_selected) {
        my $aggregate_uri = $dblp_extract_uri;
        my @aliases = ();
        for my $author_page (@{$names_selected{$name}}) {
            push(@aliases, $author_page->{'name'});
            $aggregate_uri .= 'uri=' . URI::Escape::uri_escape($author_page->{'uri'}) . '&';
        }
        $aggregate_uri =~ s/&$//mxs;
        push(@authors, {'name'=>$name, 'aliases'=>\@aliases, 'uri'=>$aggregate_uri});
    }

    return \@authors;
}


sub helper_dblp_extract {
    #
    #   STRING helper_dblp_extract(STRING_ARRAYREF $uris)
    #
    # Return text of publications from DBLP author homepage of supplied urls.
    #
    my ($uris) = @_;

    my @titles = ();
    foreach my $uri (@$uris) {
        # fetch dblp author page
        my $res = http_get(url => $uri);
        # extract just the titles from DBLP author page (throw rest away)
        push(@titles, @{dblp_extractTitles($res->{'content'})});
    }
    return join("\n", @titles);
}


sub dblp_extractTitles {
    #
    # extract titles from a DBLP author bibliography page
    #
    my ($html) = @_;
    ($html) = ($html =~ m{<div\ id=\"publ\-section\"[^>]+>(.*?)<div\ class=\"coauthor\-section[^>]+>}mxs);

    my @titles = ();
    if (defined $html) {
        foreach my $line (split(/<span\ class=\"title\">/, $html)) {
            if ($line eq '' || $line =~ m/^<div/) {
                next;
            }
            $line =~ s/[\r\n]/ /gxsm;
            $line =~ s/<\/span>.*$//xsm;
            push(@titles, $line);
        }
    }
    return \@titles;
}


1;