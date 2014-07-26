# fn_helper.pl
use strict;
use warnings;

use Encode;
use HTML::Entities();
use URI::Escape;

# Porter stemming
use Text::English;

# Named Entity Recognition
use Lingua::EN::NamedEntity;


require 'csv.pl';


my $FALSE = 0;
my $TRUE  = 1;

#
# functions on STRING
#

sub helper_fn_concat {
    #
    # STRING concat(ARRAYREF_STRING $str)
    #
    return join("\n", @_);
}

sub helper_fn_length {
    #
    # STRING length(STRING $str)
    #
    return length(shift);
}

sub helper_fn_downcase {
    #
    # STRING downcase(STRING $str)
    #
    return lc(shift);
}

sub helper_fn_remove_html {
    #
    #   STRING remove_html(STRING $str)
    #
    #   Nieve implementation of xml/html tag removal (+ removes xml/html comments)
    #   FIXME: ought to use a parser to do this!
    #
    my ($str) = @_;
    # unescape
    $str = HTML::Entities::decode_entities($str);
    # remove comments
    $str =~ s/<!--.+?-->//gxsm;
    # remove elements
    $str =~ s/<[^>]+>/\ /gxsm;
    return $str;
}

sub helper_fn_named_entities {
    #
    #   ARRAY_REF named_entities(STRING $str)
    #
    #   Return list of entities extracted from $str
    #
    my ($str) = @_;
    my @entities = extract_entities($str);
    my @words = ();
    for my $entity (@entities) {
        #FIXME: just taking top ranking match, but could do something smarter with confidence scores (we are ignoring them for now)
=head
$VAR1 = {
          'scores' => {
                        'organisation' => 3,
                        'person' => 4,
                        'place' => 1
                      },
          'count' => 1,
          'entity' => 'Red Guards',
          'class' => 'person'
        };
$VAR2 = {
          'scores' => {
                        'organisation' => 4,
                        'person' => 1,
                        'place' => 1
                      },
          'count' => 1,
          'entity' => 'Old Photographs Fever',
          'class' => 'organisation'
        };
=cut


    }
    return \@words;
}

sub helper_fn_to_words {
    #
    #   ARRAY_REF to_words(STRING $str, INT $length)
    #
    #   split string into a list of words
    #   removing any words below minimum length
    #
    my ($text, $length) = @_;
    if (!defined $text) {
        return [];
    }
    if (!defined $length) { 
        $length = 1;
    }
#    my @words = split( /[^\p{L}_]+/o, $text );
    my @words = split( /[^\p{L}\d_]+/o, $text );
    my @filtered_words = ();
    for my $word (@words) {
        if (length($word) >= $length) {
            push(@filtered_words, $word);
        }
    }
    return \@filtered_words;
}

#
# functions on ARRAYS
#
=head
sub helper_fn_array_length {
    #
    #   INT array_length(ARRAY_REF $array)
    #
    my ($array) = @_;
    if (!defined $array || ref($array) ne 'ARRAY') {
        return 0;
    }
    return scalar(@$array);
}
=cut

sub helper_fn_sort {
    #
    #   ARRAY_REF sort(ARRAY_REF $array[, HASH_REF $options])
    #
    #   options:
    #       index:      column index to use in sort compare (default 1)
    #       numeric:    0=FALSE|1=TRUE, whether to use numeric compare (default infers from column value on first row)
    #       ascending:  0=FALSE|1=TRUE, sort direction (default 0 for numerics or 1 for non-numerics)
    #
    my ($array, $options) = @_;

    if (!defined $array || 
         ref($array) ne 'ARRAY' || scalar(@$array) == 0 || 
         ref($array->[0]) ne 'ARRAY' || scalar(@{$array->[0]}) == 0) {
        return [];
    }

    $options = $options || {};
    my $index = $options->{'index'} || 1;
    my $numeric = (defined $options->{'numeric'} && "$options->{'numeric'}" eq '0') ? $FALSE : $TRUE;
    #FIXME: the following safeguard may be a waste of time if speed is critical (we could just wrap sort in eval and catch the "not a number" error of a duff sort)
    my $sample_value = $array->[0][$index];
    if ($numeric && $sample_value !~ /^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]\d+)?$/) {
        # ignore numeric flag if column contains non-numeric data
        $numeric = $FALSE;
    }

    my @sorted_array;
    if ($numeric) {
        my $ascending = (defined $options->{'ascending'} && "$options->{'ascending'}" eq '1') ? $TRUE : $FALSE;
        if ($ascending) {
            @sorted_array = sort { $a->[$index] <=> $b->[$index] } @$array;
        }
        else {
            @sorted_array = sort { $b->[$index] <=> $a->[$index] } @$array;
        }
    }
    else {
        my $ascending = (defined $options->{'ascending'} && "$options->{'ascending'}" eq '0') ? $FALSE : $TRUE;
        if ($ascending) {
            @sorted_array = sort { $a->[$index] cmp $b->[$index] } @$array;
        }
        else {
            @sorted_array = sort { $b->[$index] cmp $a->[$index] } @$array;
        }
    }
    return \@sorted_array;
}

sub helper_fn_limit {
    #
    #   ARRAY_REF limit(ARRAY_REF $array, INT $limit)
    #
    #   only keep the top $limit items
    #
    my ($array_ref, $limit) = @_;

    if ($limit >= scalar(@$array_ref)) {
        return $array_ref;
    }
    my @array = @$array_ref[0..$limit-1];
    return \@array;
}

sub helper_fn_threshold {
    #
    #   ARRAY_REF threshold(ARRAY_REF $array, INT $threshold[, $index])
    #
    #   only retain items with value greater than $threshold
    #   where $index (default 1) is the index into the item's sort value
    #
    my ($array_ref, $threshold, $index) = @_;

    if (!defined $index) {
        $index = 1;
    }
    my @array = ();
    for my $item (@$array_ref) {
        if ($item->[$index] >= $threshold) {
            push(@array, $item);
        }
    }
    return \@array;
}


#
# functions on WORDS (multisets)
#

sub helper_fn_min_length {
    #
    #   ARRAY_REF min_length(ARRAY_REF $words, INT $length)
    #
    #   filter out words shorten than $length
    #
    my ($words, $length) = @_;
    if (!defined $length) { 
        $length = 1;
    }
    my @filtered_words = ();
    for my $word (@$words) {
        if (length($word) >= $length) {
            push(@filtered_words, $word);
        }
    }
    return \@filtered_words;
}

sub helper_fn_exclude_words {
    #
    #   ARRAY_REF text_to_words(ARRAY_REF $words, HASH_REF $unwanted_words, BOOL $ignore_case)
    #
    #   filter out excluded words from a list of words
    #
    my ($words_ref, $unwanted_words, $ignore_case) = @_;
    my @words;
    $ignore_case = (defined $ignore_case && $ignore_case eq '1') ? $TRUE : $FALSE;
    if ($ignore_case) {
        @words = grep { !$unwanted_words->{$_} } @$words_ref;
    }
    else {
        @words = grep { !$unwanted_words->{lc($_)} } @$words_ref;
    }
    return \@words;
}

sub helper_fn_include_words {
    #
    #   ARRAY_REF text_to_words(ARRAY_REF $words, HASH_REF $wanted_words, BOOL $ignore_case)
    #
    #   filter out words not in a list of wanted words from a list of words
    #   Special case for empty $wanted_words returns $words unchanged
    #
    my ($words_ref, $wanted_words, $ignore_case) = @_;
    if (scalar keys %$wanted_words == 0) {
        return $words_ref;
    }
    my @words;
    $ignore_case = (defined $ignore_case && $ignore_case eq '1') ? $TRUE : $FALSE;
    if ($ignore_case) {
        @words = grep { $wanted_words->{$_} } @$words_ref;
    }
    else {
        @words = grep { $wanted_words->{lc($_)} } @$words_ref;
    }
    return \@words;
}

sub helper_fn_stem {
    #
    #   ARRAY_REF stem(ARRAY_REF $words)
    #
    #   apply Porter Stemming to a list of words
    #
    my ($words) = @_;
    my @words = Text::English::stem( @$words );
    return \@words;
}

sub helper_fn_ngrams {
    #
    #   ARRAY_REF ngrams(ARRAY_REF $words, ARRAY_REF $nvalues)
    #
    #   construct n-grams and append to list of words
    #   for each INT $n in an array of $nvalues
    #
    my ($words, $nvalues) = @_;
    my @grams = ();
    my $noofwords = scalar(@$words);
    for my $n (@$nvalues) {
        if ($n == 1) {
            # no need to construct 1-grams, so just append them
            @grams = (@grams, @$words);
        }
        elsif ($noofwords >= $n) {
            # construct n-grams
            my $nm1 = $n - 1;
            my $ilim = $noofwords - $nm1;
            for (my $i=0; $i < $ilim; $i++) {
                push(@grams, join(' ', @{$words}[$i..$i+$nm1]));
            }
        }
    }
    return \@grams;
}

sub helper_fn_count_words {
    #
    #   HASH_REF count_words(ARRAY_REF $words)
    #
    #   count number of occurrences of each term in this document
    #   returns multiset <STRING term, INT count>
    #
    my ($words) = @_;
    my %term_n = ();
    foreach my $term (@$words){
        $term_n{$term}++;
    }
    return \%term_n;
}

sub helper_fn_multiset_union {
    #
    #   HASH_REF multiset_union(HASH_REF $multiset,...)
    #
    #   merges a list of multisets into a single multiset
    #   returns multiset <STRING term, INT multiplicity>
    #
    #   note: accepts hash and array (in sift:Bag format) representations of multisets
    #
    # dodgy type wrangling: unwrap a singleton array argument and treat its elements as @_
    # as a convenience to allow json path queries that return multiple results to act as n-ary arguments
    # FIXME: this wrangling will probably stop working if I switch to using btrees for large hash variables
    my $arglist = \@_;
    if (scalar(@$arglist) == 1 && ref($arglist->[0]) eq 'ARRAY') {
        $arglist = $arglist->[0];
    }
    # start of sub proper...
    my %hash = ();
    LP_ARGS:
    foreach my $multiset (@$arglist) {
        # skip null arguments
        if (!defined $multiset || !ref($multiset)) {
            next LP_ARGS;
        }
        # determine whether hash or array representation of multiset
        if (ref($multiset) eq 'HASH') {
            # merge in hash representation of multiset
            while( my ($key, $value) = each(%$multiset) ) {
                if (!exists $hash{$key}) {
                    $hash{$key} = $value;
                }
                else {
                    $hash{$key} += $value;
                }
            }
        }
        else {
            # merge in array representation of multiset
            # assume sift:Bag representation, i.e. [[key1,value1],[key2,value2],...]
            foreach my $pair (@$multiset) {
                if (!exists $hash{$pair->[0]}) {
                    $hash{$pair->[0]} = $pair->[1];
                }
                else {
                    $hash{$pair->[0]} += $pair->[1];
                }
            }
        }
    }
    return \%hash;
}

sub helper_fn_multiset_increment {
    #
    #   HASH_REF multiset_increment(HASH_REF $multiset_count, HASH_REF $multiset,...)
    #
    #   increments corresponding $multiset_count term by 1 for each term key in $multiset
    #   returns multiset_count <STRING term, INT count>
    #
    #   note: accepts hash and array (in sift:Bag format) representations of multisets
    #
    my $multiset_count = shift;
    foreach my $multiset (@_) {
        if (ref($multiset) eq 'HASH') {
            while( my ($key, $_value) = each(%$multiset) ) {
                if (!exists $multiset_count->{$key}) {
                    $multiset_count->{$key} = 1;
                }
                else {
                    $multiset_count->{$key}++;
                }
            }
        }
        else {
            # assume sift:Bag representation, i.e. [[key1,value1],[key2,value2],...]
            foreach my $pair (@$multiset) {
                if (!exists $multiset_count->{$pair->[0]}) {
                    $multiset_count->{$pair->[0]} = 1;
                }
                else {
                    $multiset_count->{$pair->[0]}++;
                }
            }
        }
    }
    return $multiset_count;
}

sub helper_fn_multiset_cardinality {
    #
    #   INT multiset_cardinality(HASH_REF $multiset)
    #
    my ($hashref) = @_;
    my $count = 0;
    foreach my $value (values %$hashref) {
        $count += $value;
    }
    return $count;
}

=head
sub helper_fn_project {
    #
    #   HASH_REF project(INT $index, HASH_REF <STRING term, ARRAY_REF row> table)
    #
    #   returns multiset <STRING term, ANY value> where value is the projection of index onto table
    #
    my ($index, $hashref) = @_;
    my %hash = ();
    while( my ($key, $array_ref) = each(%$hashref) ) {
        $hash{$key} = $array_ref->[$index];
    }
    return \%hash;
}
=cut

sub helper_fn_project {
    #
    #   ARRAY_REF project(INT $index, ARRAY_REF <STRING key, ANY value1, value2, ...> table)
    #   ARRAY_REF project(ARRAY_REF INT $indices, ARRAY_REF <STRING key, ANY value1, value2, ...> table)
    #
    #   returns array <STRING key, ANY value1, value2, ...> where value is the projection of index onto table
    #
    my ($index, $arrayref) = @_;
    my @relation = ();
    if (ref $index eq 'ARRAY') {
        foreach my $row (@$arrayref) {
            my @values = ();
            foreach (@$index) {
                push(@values, $row->[$_]);
            }
            push(@relation, \@values);
        }
    }
    else {
        foreach my $row (@$arrayref) {
            push(@relation, [$row->[0], $row->[$index]]);
        }
    }
    return \@relation;
}

sub helper_fn_hash {
    #
    #   converts an array of pairs to a hash
    #
    my ($array_ref) = @_;
    my %hash = ();
    foreach my $pair (@$array_ref) {
        $hash{$pair->[0]} = $pair->[1];
    }
    return \%hash;
}


sub helper_fn_tfidf {
    #
    #   ARRAY_REF tfidf(
    #       HASH_REF <STRING term => INT n> $term_n,
    #       INT $document_n,
    #       HASH_REF <STRING term => INT dt> $corpus_dt,
    #       INT $noofdocs
    #   )
    #
    #   returns array <STRING key, ARRAY_REF tuple> where tuple is [tfidf, n, tf, idf]
    #
    my ($term_n, $document_n, $corpus_dt, $noofdocs) = @_;

    my $adjusted_noofdocs = ($noofdocs == 1) ? 2 : $noofdocs;
    my $log_2 = log(2.0);

    my @result = ();
    while (my ($term, $n) = each(%$term_n)) {

        my $tf = $n / $document_n;
        my $idf = log( $adjusted_noofdocs / $corpus_dt->{$term} ) / $log_2;
        my $tfidf = $tf * $idf;
#        my $term_weight_global = $weights_global->{$term}; 
#        if (!defined $term_weight_global) { $term_weight_global = $term_weight_default; }
#        my $term_weight_local  = $weights_local->{$term};
#        if (!defined $term_weight_local) { $term_weight_local = $term_weight_default; }
#        my $weighted_tfidf = $tfidf * $term_weight_global * $term_weight_local;
        push(@result, [ 
#            $weighted_tfidf, 
#            $tfidf, 
            $term, 
#            [$n, $tf, $idf, $tfidf, $term_weight_global, $term_weight_local, $weighted_tfidf]
            $tfidf, $n, $tf, $idf
        ]);
    }
    return \@result;
}


sub helper_fn_cosine {
    #
    #   ARRAY_REF cosine(
    #       ARRAY_REF terms1,
    #       ARRAY_REF terms2
    #   )
    #
    my ($terms1, $terms2) = @_;

    my $lookupterms = (scalar(@$terms1) > scalar(@$terms2)) ? $terms2 : $terms1;
    my $serialterms = (scalar(@$terms1) > scalar(@$terms2)) ? $terms1 : $terms2;

    # convert array to hash keyed on term
    my %keyedterms = ();
    my $norm_a = 0;
    for my $elem (@$lookupterms) {
        $keyedterms{$elem->[0]} = $elem;
        $norm_a += $elem->[2] * $elem->[2];
    }
    $norm_a = sqrt($norm_a);

    my $norm_b = 0;
    for my $elem (@$serialterms) {
        $norm_b += $elem->[2] * $elem->[2];
    }
    $norm_b = sqrt($norm_b);

    # compute dot product of term vectors (iterating over shortest key set)
    my $dotproduct = 0;
    my @shared_terms = ();
    for my $stats (@$serialterms) {
        my $term = $stats->[0];
        if (exists $keyedterms{$term}) {
            my $contribution = $stats->[2] * $keyedterms{$term}[2];
            # ignore terms with non-zero tf but zero tfidf (ie. ones which are significant in a single doc but which occur in all docs)
            if ($contribution > 0) {
                $dotproduct += $contribution;
                push(@shared_terms, [$term, $contribution]);
            }
        }
    }
    my $denom = $norm_a * $norm_b;
    my $cosine = ($denom) ? $dotproduct / $denom : 0;
    @shared_terms = sort { $b->[1] <=> $a->[1] } @shared_terms;

    return [$cosine, \@shared_terms];
}

1;
