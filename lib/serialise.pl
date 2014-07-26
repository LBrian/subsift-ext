# serialise.pl
#
#   Serialise a Perl variable as a string in various data formats
#

use strict;
use warnings;

my $FALSE = 0;
my $TRUE  = 1;


sub serialise {
    #
    #   STRING serialise(HASH_OR_ARRAY_REF $value[, HASHREF $options])
    #
    #   Returns a string representation of the Perl hash or array $value.
    #   If $value is not an array or hash it is wrapped in a hash.
    #
    #   Options:
    #       format:             One of csv, json, rdf, terms, yaml, xml. Default = xml
    #       pretty:             TRUE/FALSE, whether to pretty print. Default = TRUE
    #       encode:             Optional post-serialisation encoding (e.g. 'UTF-8').
    #
    #   e.g. serialise({foo=>'bar'})
    #   e.g. serialise({foo=>'bar'}, {'format'=>'xml'})
    #   e.g. serialise({foo=>'bar'}, {'format'=>'xml', 'pretty'=>$TRUE})
    #
    my ($value, $options) = @_;

    if (!defined $value) {
        $value = '';
    }
    if (ref($value) ne 'HASH' && ref($value) ne 'ARRAY') {
        $value = { 'value' => $value };
    }

    # merge supplied options into defaults
    my $default_options = get_default_serialise_options() || {};
    if (!defined $options || ref($options) ne 'HASH') {
        $options = $default_options;
    }
    else {
        while (my ($k,$v) = each(%$default_options)) {
            if (!exists $options->{$k}) {
                $options->{$k} = $v;
            }
        }
    }
    # default format to json
    my $format = (defined $options->{'format'} && $options->{'format'} =~ m{csv|json|rdf|terms|yaml|xml}xms) 
        ?   $options->{'format'} 
        :   'json';   
    # default pretty to true
    my $pretty = (defined $options->{'pretty'} && $options->{'pretty'} eq "$FALSE")
        ?   $FALSE 
        :   $TRUE;

    my $text = '';
    if ($format eq 'csv') {
        require 'csv.pl';
        $text = serialise_csv($value, {'pretty' => $pretty, 'canonical' => $TRUE});
    }
    elsif ($format eq 'json') {
        require JSON;
        $text = ($pretty) 
         ?  JSON->new->canonical->pretty->encode($value) 
         :  JSON->new->canonical->encode($value);
#TODO: the following settings ensure that you always get the same output for the same hash...
#$json->indent(0);
#$json->space_after(0);
#$json->space_before(0);
#$json->canonical(1);
    }
    elsif ($format eq 'rdf') {
        require 'rdf_xml.pl';
        $text = serialise_rdf_xml($value, {'pretty' => $pretty, 'canonical' => $TRUE});
    }
    elsif ($format eq 'terms') {
        require 'terms.pl';
        $text = serialise_term($value, {'pretty' => $pretty, 'canonical' => $TRUE});
    }
    elsif ($format eq 'yaml') {
        require YAML;
        $text = YAML::Dump($value);
    }
    elsif ($format eq 'xml') {
        my $xslt = get_serialise_xslt();
        require XML::Simple;
        $text = XML::Simple::XMLout($value, 
            'XMLDecl' => ((!defined $xslt)
                          ? '<?xml version="1.0" encoding="UTF-8"?>'
                          : ('<?xml version="1.0" encoding="UTF-8" standalone="no"?>' . "\n" .
                             '<?xml-stylesheet type="text/xsl" href="' . $xslt . '"?>')
                          ),
            'RootName' => 'result', 
            'NoAttr' => 1,
            'NoIndent' => (($pretty)?0:1),
        );
    }
    else {
        die "serialise.pl: error - unsupported format '$format'";
    }

    return (
        defined $options->{'encode'}
        ?   Encode::encode($options->{'encode'}, $text) 
        :   $text
    );
}


sub serialise_error_message {
    #
    #   STRING serialise_error_message(STRING $message[, HASHREF $options])
    #
    #   Returns a string representation of the error message $value
    #   e.g. serialise_error_message('no such user')
    #
    my ($message, $options) = @_;
    return serialise({'error' => $message}, $options);
}


#
# allow global default options hash for serialise method
#

use vars qw($_Serialise_default_options);

sub get_default_serialise_options {
    return $_Serialise_default_options;
}

sub set_default_serialise_options {
    my ($value) = @_;
    $_Serialise_default_options = $value;
}



#
# Allow an xslt stylesheet to be specified for insertion into XML declaration.
# Obviously only relevent to XML serialisations. Is entirely optional.
# Value is a url which must resolve to same domain and port as original request.
#

use vars qw($_Xslt_url);

sub get_serialise_xslt {
    return $_Xslt_url;
}

sub set_serialise_xslt {
    my ($value) = @_;
    if (defined $value) {
        # ensure not code injection (not too serious as must be same domain anyway)
        $value =~ s/[\"\n\r]//gxsm;
    }
    $_Xslt_url = $value;
}


1;
