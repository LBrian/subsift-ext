use strict;

my $FALSE = 0;
my $TRUE  = 1;

require 'dblp_helper.pl';


sub controller_dblp {
    my ($settings, $params) = @_;

    
}


sub action_dblp_search_results {
    #
    # Search DBLP for each name in submitted list of names and build a new list in csv format:
    # <name>, <author_name>, <author_uri>
    # Also report names for which there were no results on DBLP.
    #
    my ($settings, $params) = @_;

    my $names_list = $params->{'names_list'};
    my $refresh    = $params->{'refresh'};

    my $locals = helper_dblp_search_results($names_list);

    render({ 
        'template' => 'demo/dblp_search_results',
        'locals' => $locals,
    });
}


sub action_dblp_search_restrict {
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
        'template' => 'demo/dblp_search_restrict',
        'locals' => {
            'list' => $authors,
        },
    });
}


sub action_dblp_extract {
    #
    # Return text of publications from DBLP author homepage of supplied url(s).
    #
    my ($settings, $params) = @_;

    # unpack possibly multiple values for uri
    my @uris = get_values($params->{'uri'});

    my $refresh = (exists $params->{'refresh'} && $params->{'refresh'} eq '1') ? $TRUE : $FALSE;
    #FIXME: implement cache on/off switching!

    my $text = helper_dblp_extract(\@uris);

    render({ 
        'text' => $text,
    });
}



1;