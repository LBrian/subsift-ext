# csv.pl
use strict;
use warnings;

#require Text::CSV_PP;
require Text::CSV;


my $FALSE = 0;
my $TRUE  = 1;


#FIXME: Error reporting back to caller is unusable in a REST error response or UI at the moment - contains Perl jargon.

sub csv_parse_string {
    #
    #   ARRAYREF csv_parse_string(STRING $csv_string)
    #
    #   Returns an array of row arrays or throws error if invalid csv
    #
    my ($csv_string) = @_;

    # normalise line ends
    $csv_string =~ s/\r\n|\n\r|\r/\n/gxsm;

    # read csv file and parse each line

    my $saveslash = $/; #preserve slash
    $/ = "\n";
        
#    my $csv = Text::CSV_PP->new ({
    my $csv = Text::CSV->new ({
         quote_char          => '"',
         escape_char         => '"',
         sep_char            => ',',
         eol                 => $/,     #default was $\,
         always_quote        => 0,
         binary              => 1,      #allow non-ascii and newlines
         keep_meta_info      => 0,
         allow_loose_quotes  => 0,
         allow_loose_escapes => 0,
         allow_whitespace    => 1,      #ignore spaces around sep_char
         blank_is_undef      => 0,
         empty_is_undef      => 0,
         verbatim            => 0,
         auto_diag           => 0,
    }) or die "Cannot use CSV: ".Text::CSV->error_diag ();
    my @rows = ();
    my $fh;
    open($fh, '<', \$csv_string) or die "$!";
    $! = undef; #suppress 'No such file or directory' error on perl open attempts
    while (my $row = $csv->getline($fh)) {
        if (defined $row && scalar(@$row) > 0 && !(scalar(@$row) == 1 && $row->[0] eq '')) {
            push(@rows, $row);
        }
    }
    $csv->eof or $csv->error_diag();
    close $fh;

    $/ = $saveslash;  #restore slash

    if (scalar(@rows) == 0) {
        die "The CSV data is not in expected format";
    }

    return \@rows;
}


#
#   Serialise a Perl variable as CSV (auto-creating columns as required)
#

#TODO: finish csv serialisation

sub serialise_csv {
    #
    #   STRING serialise_csv($value[, HASHREF $options])
    #
    #   Returns a prolog csvs representation of Perl variable $value.
    #
    #   Options:
    #       'canonical' => $TRUE    sorts hashes on their keys to ensure canonical order. Default = $TRUE
    #       'pretty' => $TRUE       pretty print with indentation. Default = $TRUE
    #
    my ($value, $options) = @_;

    if (!defined $options || ref($options) ne 'HASH') {
        $options = {};
    }
    
    reset_csv_uid();

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
#            serialise_csv_value($value, $options) . $options->{'_newline_str'} . 
#        ').' . $options->{'_newline_str'};
        return 'result(' .  
            serialise_csv_value($value, $options) . 
        ').' . $options->{'_newline_str'};
    }
    return "result.\n";
}

sub serialise_csv_value {
    #
    #   STRING serialise_csv_value($value, $options)
    #
    #   Returns a prolog csvs representation of $value.
    #
    my ($value, $options) = @_;
    if (!defined $value) {
        return '';
    }
    elsif (ref($value) eq 'HASH') {
        return serialise_csv_hash($value, $options);
    }
    elsif (ref($value) eq 'ARRAY') {
        return serialise_csv_array($value, $options);
    }
    elsif ($value ne '') {
        return _atomquote_or_number($value, $options);
    }
    return '';
}

sub serialise_csv_hash {
    my ($hash_ref, $options) = @_;
    my @keys = keys %$hash_ref;
    if ($options->{'canonical'}) {
        @keys = sort @keys;
    }
    $options->{'_nargs' . $options->{'_indent'}} = scalar(@keys);
    my $nl = '';
    my @csvs = ();
    for my $key (@keys) {
        my $value = $hash_ref->{$key};
        $nl = $options->{'_newline_str'};
        my $indent = $options->{'_indent_str'} x $options->{'_indent'};
        if ($value eq '') {
            push(@csvs, $indent . _atomquote($key));
        }
        else {
            $options->{'_indent'}++;
            $options->{'_nargs' . $options->{'_indent'}} = 0;
            my $args = serialise_csv_value($value, $options);
            if ( $options->{'pretty'} &&
                (
                    $options->{'_nargs' . $options->{'_indent'}} > 1 &&
                    $args !~ m/[\]\)]$/    #ie. no indent after end of list or csv body
                ) ||
                $args =~ m/\s$/
               ) {
                $args = $args . $indent;
            }
            push(@csvs, $indent . _atomquote($key) . '(' . $args .')');
            $options->{'_indent'}--;
        }
    }
    return $nl . join($options->{'_separator_str'}, @csvs) . $nl;
}

sub serialise_csv_array {
    my ($array_ref, $options) = @_;
    $options->{'_nargs' . $options->{'_indent'}} = scalar(@$array_ref);
    my @csvs = ();
    my $indent = $options->{'_indent_str'} x $options->{'_indent'};
    for my $value (@$array_ref) {
        if ($value eq '') {
            push(@csvs, $indent . "''");
        }
        else {
            $options->{'_indent'}++;
            $options->{'_nargs' . $options->{'_indent'}} = 0;
            my $args = serialise_csv_value($value, $options);
            if ($options->{'_nargs' . $options->{'_indent'}} > 1 && (ref($value) ne 'ARRAY')) {
                my $head = (ref($value) eq 'HASH') ? 'hash' : 'tuple';
                $args = $head . get_csv_uid() . '(' . $args . $indent . ')';
            }
            push(@csvs, $indent . $args);
            $options->{'_indent'}--;
        }
    }
    $indent = ($options->{'pretty'} && $options->{'_nargs' . $options->{'_indent'}} > 1 && $options->{'_indent'} > 1)
                ?   $options->{'_indent_str'} x ($options->{'_indent'} - 1)
                :   '';
    return '[' . $options->{'_newline_str'} . join($options->{'_separator_str'}, @csvs) . $options->{'_newline_str'} . $indent . ']';
}

sub _atomquote {
    my ($str) = @_;
    if (defined $str) {
        $str =~ s/'/\\'/gsmx;
        if ($str !~ m{^[a-z_][a-zA-Z0-9_]*$}xs) {
            $str = '\'' . $str . '\'';
        } 
    }
    else {
        die 'Undefined string!';
    }
    return $str;
}

sub _atomquote_or_number {
    my ($str) = @_;
    if (defined $str) {
        $str =~ s/'/\\'/gsmx;
                    #FIXME: should restrict length/size of numbers to ensure not illegal in Prolog
        if ($str !~ m{^[a-z_][a-zA-Z0-9_]*$|^[+-]?[0-9]+(?:\.[0-9]*)?(?:e[+-][0-9]+)?$}xs) {
            $str = '\'' . $str . '\'';
        }
    }
    else {
        die 'Undefined string!';
    }
    return $str;
}


use vars qw($_Csv_uid);

sub get_csv_uid {
    return ++$_Csv_uid;
}

sub reset_csv_uid {
    $_Csv_uid = 0;
}



1;