# rdf_xml.pl
use strict;
use warnings;

#
#   Serialise a Perl variable as RDF XML
#

#TODO: facility to substitute foaf: and dc: properties for sift: ones (namespaces already included in readiness)

use URI::Escape;

my $FALSE = 0;
my $TRUE  = 1;

my $SUBSIFT_NAMESPACE = 'http://vocab.bris.ac.uk/subsift/';


sub serialise_rdf_xml {
    #
    #   STRING serialise_rdf($value[, HASHREF $options])
    #
    #   Returns a RDF XML representation of Perl variable $value.
    #
    #   Options:
    #       'canonical' => $TRUE    sorts hashes on their keys to ensure canonical order. Default = $TRUE
    #       'pretty' => $TRUE       pretty print with indentation. Default = $TRUE
    #       'uri' => <STRING>       uri of resource being serialised (e.g. the REST url)
    #
    #   Note: This serialisation only supports the data structure patterns used in SubSift.
    #   The 'uri' and 'type' hash keys are treated as 'rdf:about' and 'rdf:type' (the latter first being prefixed by $SUBSIFT_NAMESPACE).
    #
    my ($value, $options) = @_;
    
    if (!defined $options || ref($options) ne 'HASH') {
        $options = {};
    }

    $options->{'canonical'} = (defined $options->{'canonical'} && $options->{'canonical'} eq "$FALSE") ? $FALSE : $TRUE;
    $options->{'pretty'}    = (defined $options->{'pretty'}    && $options->{'pretty'} eq "$FALSE")    ? $FALSE : $TRUE;
    # allow either directly passed in uri or, if routing, params & settings modules used, derive uri from instantiated route
    $options->{'uri'} = $options->{'uri'} || (
        (defined &get_setting && defined &get_param) 
        ? (get_setting('SITE_URL') . get_param('path')) 
        : ''
    );
    
    # we overload the options hash to also carry around indentation state information
    $options->{'_indent'} = 0;
    $options->{'_indent_str'}    = ($options->{'pretty'}) ? '    ' : '';
    $options->{'_newline_str'}   = ($options->{'pretty'}) ? "\n" : '';
    $options->{'_separator_str'} = ($options->{'pretty'}) ? ",\n" : ', ';
    
    my $nl = $options->{'_newline_str'};
    
    my $ret = 
        '<?xml version="1.0" encoding="UTF-8"?>' . $nl .
        '<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"' . $nl .
        $options->{'_indent_str'} . 'xmlns:sift="' . $SUBSIFT_NAMESPACE . '"' . $nl .
        $options->{'_indent_str'} . 'xmlns:foaf="http://xmlns.com/foaf/0.1/"' . $nl .
        $options->{'_indent_str'} . 'xmlns:dc="http://purl.org/dc/elements/1.1/">' . $nl;

    if (defined $value && (ref($value) eq 'HASH' || ref($value) eq 'ARRAY' || $value ne '')) {
        $options->{'_indent'}++;
        $options->{'_uri'} = '';
        $options->{'_type'} = '';
        $ret .= serialise_rdf_value($value, $options);
    }
    $ret .= '</rdf:RDF>' . $nl;
    return $ret;
}

sub serialise_rdf_value {
    my ($value, $options) = @_;
    if (!defined $value) {
        return '';
    }
    elsif (ref($value) eq 'HASH') {
        return serialise_rdf_hash($value, $options);
    }
    elsif (ref($value) eq 'ARRAY') {
        return serialise_rdf_array($value, $options);
    }
    elsif ($value ne '') {
        return xml_text_quote($value, $options);
    }
    return '';
}

sub serialise_rdf_hash {
    my ($hash_ref, $options) = @_;
    my @keys = keys %$hash_ref;
    if ($options->{'canonical'}) {
        @keys = sort @keys;
    }

    $options->{'_nargs' . $options->{'_indent'}} = scalar(@keys);
    my $nl = $options->{'_newline_str'};
    my @terms = ();
    for my $key (@keys) {
        if ($key eq 'uri' || $key eq 'type') { next; }
        my $value = $hash_ref->{$key};
        my $indent = $options->{'_indent_str'} x $options->{'_indent'};
        if ($value eq '') {
            push(@terms, $indent . '<' . 'sift:' . xml_element_quote($key) . '/>');
        }
        else {
            my $is_root = ($options->{'_indent'} == 1) ? $TRUE : $FALSE;
            my $old_indent = $options->{'_indent'};
            $options->{'_indent'} += (ref($value) eq 'ARRAY' && $is_root) ? 2 : 1;
            $options->{'_nargs' . $options->{'_indent'}} = 0;
            $options->{'_uri'} = $hash_ref->{'uri'};
            $options->{'_type'} = $key;
            my $args = serialise_rdf_value($value, $options);
            if ( $options->{'pretty'} &&
                (
                    $options->{'_nargs' . $options->{'_indent'}} > 1 &&
                    $args !~ m/[\]\)]$/    #ie. no indent after end of list or term body
                ) ||
                $args =~ m/\s$/
               ) {
                $args = $args . $indent;
            }
            if ($args =~ m{^https?://}xms) {
                push(@terms, $indent . '<' . 'sift:' . xml_element_quote($key) . ' rdf:resource="' . xml_resource_quote($args) . '"/>');
            }
            elsif (ref($value) eq 'ARRAY' && $is_root) {
                my $rdftype = (defined $key) ? (' rdf:type="' . $SUBSIFT_NAMESPACE . $key . '"') : '';
                my $rdfabout   = (defined $options->{'uri'})   ? (' rdf:about="' . $options->{'uri'} . '"') : '';
                my $indent2 = $indent . $options->{'_indent_str'};
                push(@terms, 
                    $indent . '<rdf:Description' . $rdftype . $rdfabout . '>' . $nl .
                    $indent2 . '<' . 'sift:' . xml_element_quote($key) . '>' . $args . $options->{'_indent_str'} . '</' . 'sift:' . xml_element_quote($key) . '>' . $nl .
                    $indent . '</rdf:Description>'
                );
            }
            elsif (ref($value) eq 'HASH' && scalar(@keys) == 1 && $is_root) {
                my $rdftype = (defined $value->{'type'}) ? (' rdf:type="' . $SUBSIFT_NAMESPACE . $value->{'type'} . '"') : '';
                my $rdfabout   = (defined $value->{'uri'})   ? (' rdf:about="' . $value->{'uri'} . '"') : '';
                push(@terms, $indent . '<rdf:Description' . $rdftype . $rdfabout . '>' . $args . '</rdf:Description>');
            }
            else {
                push(@terms, $indent . '<' . 'sift:' . xml_element_quote($key) . '>' . $args . '</' . 'sift:' . xml_element_quote($key) . '>');
            }
            $options->{'_indent'} = $old_indent;
        }
    }
    return $nl . join($nl, @terms) . $nl;
}

sub serialise_rdf_array {
    my ($array_ref, $options) = @_;

    my $rdfseqtype = ($options->{'_type'} ne '') ? (' rdf:type="' . $SUBSIFT_NAMESPACE . $options->{'_type'} . '"') : '';
    my $rdfabout   = ($options->{'uri'} ne '')   ? (' rdf:about="' . $options->{'uri'} . '"') : '';

    $options->{'_nargs' . $options->{'_indent'}} = scalar(@$array_ref);
    my $nl = $options->{'_newline_str'};
    my @terms = ();
    my $indent = $options->{'_indent_str'} x $options->{'_indent'};
    for my $value (@$array_ref) {
        if ($value eq '') {
            push(@terms, $indent . '<rdf:li><rdf:Description/></rdf:li>');
        }
        else {
            $options->{'_indent'} += 3;
            $options->{'_nargs' . $options->{'_indent'}} = 0;
            $options->{'_uri'} = '';
            my $args = serialise_rdf_value($value, $options);
            if ($options->{'_nargs' . $options->{'_indent'}} > 1 && (ref($value) ne 'ARRAY')) {
                my $indent2 = $indent . $options->{'_indent_str'};
                my $indent3 = $indent2 . $options->{'_indent_str'};
                my $rdftype = '';
                if (defined $value->{'type'}) {
                    $rdftype =  ' rdf:type="' . $SUBSIFT_NAMESPACE . $value->{'type'} . '"';
                }
                $args = $options->{'_indent_str'} . '<rdf:li>' . $nl .
                        $indent3 . (defined $value->{'uri'} 
                            ?   ('<rdf:Description' . $rdftype . ' rdf:about="' . $value->{'uri'} . '">') 
                            :   '<rdf:Description' . $rdftype . '>'
                        ) . 
                        $args . 
                        $indent3 . '</rdf:Description>' . $nl .
                        $indent2 . '</rdf:li>';
            }
            push(@terms, $indent . $args);
            $options->{'_indent'} -= 3;
        }
    }
    return (
        $nl .
        $indent . '<rdf:Seq' . '>' . $nl .
        join($nl, @terms) . $nl . 
        $indent . '</rdf:Seq>' . $nl
    );
}

sub xml_element_quote {
    my ($str) = @_;
    if (defined $str) {
        if ($str !~ m{^[a-z_][a-zA-Z0-9_]*$}xs) {
            # XML element names are a superset of perl sub names, so can safely use sub name encoding
            $str = util_getValidSubName($str);
        }
    }
    else {
        die 'Undefined element';
    }
    return $str;
}

sub xml_text_quote {
    my ($str) = @_;
    if (defined $str) {
        # lazy xml escaping
        if (m{[\&<>]}xms) {
        	$str =~ s{\&}{\&amp;}gxms;
        	$str =~ s{<}{\&lt;}gsms;
        	$str =~ s{>}{\&gt;}gxms;
        }
    }
    else {
        die 'Undefined string';
    }
    return $str;
}

sub xml_resource_quote {
    my ($str) = @_;
    $str = xml_text_quote($str);
	$str =~ s{\"}{\%34}gxms;
    return $str;
}

1;
