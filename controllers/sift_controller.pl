#sift_controller.pl
use strict;


my $FALSE = 0;
my $TRUE  = 1;

require 'dblp_helper.pl';


sub controller_sift {
    my ($settings, $params) = @_;

    
}

#TODO: add this to documentation as a dblp author search REST service
sub action_sift_search {
    #
    # Search DBLP for each name in submitted list of names and build a new list in csv format:
    # <name>, <author_name>, <author_uri>
    # Also report names for which there were no results on DBLP.
    #
    my ($settings, $params) = @_;

    my $names_list = $params->{'names_list'};
    my $refresh    = $params->{'refresh'};

    my $cache_dblp_path = File::Spec->catdir($settings->{'CACHE_PATH'}, 'dblp_authors');
    my $locals = helper_dblp_search_results($names_list, $refresh, $cache_dblp_path);
    
    my $pretty = $TRUE;
    my $text = serialise($locals);

    render({ 
        'layout' => 0,
        'text' => $text,
    });
}


sub action_sift_disambiguate {
    #
    # Present user with multiple choice for each name matching multiple authors.
    # List itself is not presented to user and is passed through unchanged.
    #
    my ($settings, $params) = @_;

    my $names_uris = $params->{'pages_list'};
    $names_uris =~ s/\r\n|\r/\n/gmxs;

    my @lines = split("\n", $names_uris);
    my %reviewer = ();
    my @names = ();
    my %reviewer_ix = ();
    my $choices = $FALSE;
    my @errors = ();
    for(my $i=0; $i < scalar(@lines); $i++) {
        #FIXME: does not cope with proper CSV quoting of commas
        my ($author_name, $name, $author_uri) = $lines[$i] =~ m{^\s*([^,]+),\s*([^,]+),\s*(.+)\s*$}mxs;

        if (!defined $name || !defined $author_name || !defined $author_uri
            || $author_name eq '?') {
            # warn user of malformed line
            push(@errors, "<strong>Missing author or name or URL at line $i:</strong><br/>&nbsp;&nbsp;&nbsp;" . $lines[$i]);
            next;
        }

        if (!exists $reviewer{$name}) {
            $reviewer_ix{$name} = scalar @names;
            # preserve order
            push(@names, $name);
            # start an array of choices
            my @options = ();
            $reviewer{$name} = \@options;
        }
        else {
            $choices = $TRUE;
        }
        # add to the choices for this name
        my $good_match = (lc($name) eq lc($author_name)) ? $TRUE : $FALSE;
        push(@{$reviewer{$name}}, {
            'id' => '_' . $reviewer_ix{$name} . '_' . scalar @{$reviewer{$name}},
            'name' => $author_name,
            'description' => $name,
            'uri' => $author_uri,
            'checked' => $good_match,
        });
    }    

    my @reviewers = ();
    for(my $i=0; $i < scalar(@names); $i++) {
        $reviewers[$i] = $reviewer{$names[$i]};
    }

    render({
        'layout' => $FALSE,
        'template' => 'demo/_sift_disambiguate',
        'locals' => {
            'list' => $names_uris,
            'reviewers' => (scalar @reviewers > 0) ? \@reviewers : undef,
            'choices' => $choices,
            'errors' => (scalar @errors > 0) ? \@errors : undef,
        },
    });
}

sub action_sift_restrict {
    #
    # Restrict the full list of search results according to user selections and build a new list in csv format:
    # <name>, <author_name>, <aggregated_author_uri>
    # Where <aggregated_author_uri> is the uri of subsift's dblp_extract method
    # with (potentially) multiple uris as arguments (allowing aggregated author pages).
    #
    my ($settings, $params) = @_;

    my $names_list = $params->{'results_list'};

    my $dblp_extract_uri = $settings->{'SITE_URL'} . '/demo/dblp_extract';

    my $authors = helper_dblp_search_restrict($names_list, $dblp_extract_uri);

    render({ 
        'layout' => $FALSE,
        'template' => 'demo/_sift_restrict',
        'locals' => {
            'list' => $authors,
        },
    });
}

# currently using the dblp demo copy of this same function
sub action_sift_dblp_extractXXXXX {
    #
    # Return text of publications from DBLP author homepage of supplied url.
    #
    my ($settings, $params) = @_;

    # unpack possibly multiple values for uri
    my @uris = get_values($params->{'uri'});

    my $refresh = (exists $params->{'refresh'} && $params->{'refresh'} eq '1') ? $TRUE : $FALSE;

    my $cache_dblp_path = File::Spec->catdir($settings->{'CACHE_PATH'}, 'dblp_authors');
    
    my $text = helper_dblp_extract(\@uris, $refresh, $cache_dblp_path);

    render({ 
        'text' => $text,
    });
}



1;