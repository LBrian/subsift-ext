# terms.pl
use strict;
use warnings;

#
#   Serialise a Perl variable as Prolog terms
#

my $FALSE = 0;
my $TRUE  = 1;

sub serialise_term {
    #
    #   STRING serialise_term($value, HASHREF $options)  [$options is itself optional]
    #
    #   Returns a prolog terms representation of Perl variable $value.
    #
    #   Options:
    #       'canonical' => $TRUE    sorts hashes on their keys to ensure canonical order. Default = $TRUE
    #       'pretty' => $TRUE       pretty print with indentation. Default = $TRUE
    #
    my ($value, $options) = @_;
    
    if (!defined $options || ref($options) ne 'HASH') {
        $options = {};
    }

    $options->{'canonical'} = (defined $options->{'canonical'} && $options->{'canonical'} eq "$FALSE") ? $FALSE : $TRUE;
    $options->{'pretty'}    = (defined $options->{'pretty'}    && $options->{'pretty'} eq "$FALSE")    ? $FALSE : $TRUE;
    
    # we overload the options hash to also carry around indentation state information
    $options->{'_indent'} = 0;
    $options->{'_indent_str'}    = ($options->{'pretty'}) ? '    ' : '';
    $options->{'_newline_str'}   = ($options->{'pretty'}) ? "\n" : '';
    $options->{'_separator_str'} = ($options->{'pretty'}) ? ",\n" : ', ';
    
    if (defined $value && (ref($value) eq 'HASH' || ref($value) eq 'ARRAY' || $value ne '')) {
        $options->{'_indent'}++;
#        return 'result(' . $options->{'_newline_str'} . 
#            serialise_term_value($value, $options) . $options->{'_newline_str'} . 
#        ').' . $options->{'_newline_str'};
        return 'result(' .  
            serialise_term_value($value, $options) . 
        ').' . $options->{'_newline_str'};
    }
    return "result.\n";
}

sub serialise_term_value {
    #
    #   STRING serialise_term_value($value, $options)
    #
    #   Returns a prolog terms representation of $value.
    #
    my ($value, $options) = @_;
    if (!defined $value) {
        return '';
    }
    elsif (ref($value) eq 'HASH') {
        return serialise_term_hash($value, $options);
    }
    elsif (ref($value) eq 'ARRAY') {
        return serialise_term_array($value, $options);
    }
    elsif ($value ne '') {
        return atomquote_or_number($value, $options);
    }
    return '';
}

sub serialise_term_hash {
    my ($hash_ref, $options) = @_;
    my @keys = keys %$hash_ref;
    if ($options->{'canonical'}) {
        @keys = sort @keys;
    }
    $options->{'_nargs' . $options->{'_indent'}} = scalar(@keys);
    my $nl = '';
    my @terms = ();
    for my $key (@keys) {
        my $value = $hash_ref->{$key};
        $nl = $options->{'_newline_str'};
        my $indent = $options->{'_indent_str'} x $options->{'_indent'};
        if ($value eq '') {
            push(@terms, $indent . atomquote($key));
        }
        else {
            $options->{'_indent'}++;
            $options->{'_nargs' . $options->{'_indent'}} = 0;
            my $args = serialise_term_value($value, $options);
            if ( $options->{'pretty'} &&
                (
                    $options->{'_nargs' . $options->{'_indent'}} > 1 &&
                    $args !~ m/[\]\)]$/    #ie. no indent after end of list or term body
                ) ||
                $args =~ m/\s$/
               ) {
                $args = $args . $indent;
            }
            push(@terms, $indent . atomquote($key) . '(' . $args .')');
            $options->{'_indent'}--;
        }
    }
    return $nl . join($options->{'_separator_str'}, @terms) . $nl;
}

sub serialise_term_array {
    my ($array_ref, $options) = @_;
    $options->{'_nargs' . $options->{'_indent'}} = scalar(@$array_ref);
    my @terms = ();
    my $indent = $options->{'_indent_str'} x $options->{'_indent'};
    for my $value (@$array_ref) {
        if ($value eq '') {
            push(@terms, $indent . "''");
        }
        else {
            $options->{'_indent'}++;
            $options->{'_nargs' . $options->{'_indent'}} = 0;
            my $args = serialise_term_value($value, $options);
            if ($options->{'_nargs' . $options->{'_indent'}} > 0 && (ref($value) ne 'ARRAY')) {
                my $head = (ref($value) eq 'HASH') ? 'object' : 'tuple';
                $args = $head . '(' . $args . $indent . ')';
            }
            push(@terms, $indent . $args);
            $options->{'_indent'}--;
        }
    }
    $indent = ($options->{'pretty'} && $options->{'_nargs' . $options->{'_indent'}} > 0 && $options->{'_indent'} > 1)
                ?   $options->{'_indent_str'} x ($options->{'_indent'} - 1)
                :   '';
    return '[' . $options->{'_newline_str'} . join($options->{'_separator_str'}, @terms) . $options->{'_newline_str'} . $indent . ']';
}

sub atomquote {
    my ($str) = @_;
    if (defined $str) {
        $str =~ s/'/\\'/gsmx;
        if ($str !~ m{^[a-z_][a-zA-Z0-9_]*$}xs) {
            $str =~ s/\n/\\n/gxsm;
            $str = '\'' . $str . '\'';
        } 
    }
    else {
        die 'Undefined string!';
    }
    return $str;
}

sub atomquote_or_number {
    my ($str) = @_;
    if (defined $str) {
        $str =~ s/'/\\'/gsmx;
                    #FIXME: should restrict length/size of numbers to ensure not illegal in Prolog
        if ($str !~ m{^[a-z_][a-zA-Z0-9_]*$|^[+-]?[0-9]+(?:\.[0-9]*)?(?:e[+-][0-9]+)?$}xs) {
            $str =~ s/\n/\\n/gxsm;
            $str = '\'' . $str . '\'';
        }
    }
    else {
        die 'Undefined string!';
    }
    return $str;
}

1;
