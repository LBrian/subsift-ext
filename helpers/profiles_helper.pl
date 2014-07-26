# profiles_helper.pl
use strict;
use warnings;

use Encode;
use HTML::Entities();
use URI::Escape;
# Porter stemming
use Text::English;
use Data::Dumper;
## Named Entity Recognition
#use Lingua::EN::NamedEntity;


require 'csv.pl';


my $FALSE = 0;
my $TRUE  = 1;

my $DOCUMENTS_TYPE = 'documents';

my $ALL_DOCUMENTS_ID = '_ALL_';

my $TERM_FILE_EXTENSION = '.js';
my $DOCUMENT_FILE_EXTENSION = '.js';
my $MALLET_FILE_EXTENSION = '.mallet';


sub helper_topics_from_documents_folder{
	# Include MALLET topic modelling
	# Author: Brian Liu
	my ($profiles_type, $settings, $params, 
        $profiles_info, $profiles_data, $documents_info, $documents_data) = @_;

    my $user_id = $params->{'user_id'};
    # profiles folder_id
    my $profiles_id = $profiles_info->{'id'};
    # documents folder being profiled
    my $documents_id        = $profiles_info->{'document_id'};
    
    my $mallet_bin = $settings->{'BIN_PATH'} . '/' . 'mallet';
    
    # TODO
    # text processing and computational parameters
    # new parameters for topic modelling
    my $output_model        = $profiles_info->{'output_model'};		#Default is false
    my $num_topics          = $profiles_info->{'num_topics'};		#Default is 10
    my $num_threads			= $profiles_info->{'num_threads'};		#Default is 1
    my $num_iterations		= $profiles_info->{'num_iterations'};	#iterations of Gibbs sampling, default is 1000
    my $random_seed			= $profiles_info->{'random_seed'};		#for the Gibbs sampler, default is 0
    my $num_top_words		= $profiles_info->{'num_top_words'};	#most probable words for each topic, default is 20
    my $use_ngram			= $profiles_info->{'use_ngram'};		#Defaul is LDA, use Toical-N-Grams
    my $use_pam				= $profiles_info->{'use_pam'};			#Defaul is LDA, use Pachinko Allocation Model, conflict with use_ngram
    my $alpha				= $profiles_info->{'alpha'};			#smoothing over topic distribution, default is 50.0
    my $beta				= $profiles_info->{'beta'};				#smoothing over unigram distribution, default is 0.01
    my $gamma				= $profiles_info->{'gamma'};			#smoothing over bigram distribution, default is 0.01
    my $delta1				= $profiles_info->{'delta1'};			#Topic N-gram smoothing parameter, default is 0.2
    my $delta2				= $profiles_info->{'delta2'};			#Topic N-gram smoothing parameter, default is 1000.0

    my $ignore_case         = $profiles_info->{'ignore_case'};
    my $remove_html         = $profiles_info->{'remove_html'};
    my $remove_stopwords    = $profiles_info->{'remove_stopwords'};
    my $stopwords           = $profiles_info->{'stopwords'};
    my $stem                = $profiles_info->{'stem'};
    my $ngrams              = $profiles_info->{'ngrams'};
    my $restrict_vocabulary = $profiles_info->{'restrict_vocabulary'};
    my $vocabulary          = $profiles_info->{'vocabulary'};
    my $limit               = $profiles_info->{'limit'};
    my $length              = $profiles_info->{'length'};
    my $term_weight_default = $profiles_info->{'term_weight_default'};
    my $threshold           = $profiles_info->{'threshold'};
    
    # for speed, we directly access the storage layer (without using helper_[load|save]_file)
    my $profiles_path = helper_folders_path($profiles_type, $settings, $params, $profiles_id);
    if (performed_render()) {
        return;
    }
    my $documents_path = helper_folders_path($DOCUMENTS_TYPE, $settings, $params, $documents_id);
    if (performed_render()) {
        return;
    }
    
#    # get hash of unwanted words (from a comma separated string of words)
#    my @stopwords = grep( /.+/, split(/,/, Encode::decode('Detect', $stopwords)) );
#    my %stopwords = map { $_, 1 } @stopwords;
#
#    # get hash of restricted words (from a comma separated string of words)
#    my @vocabulary = grep( /.+/, split(/,/, Encode::decode('Detect', $vocabulary)) );
#    my %vocabulary = map { $_, 1 } @vocabulary;
    
    # initialise corpus term statistics
    my %corpus_n = ();      # no. occurrences of term across all documents
    my %corpus_dt = ();     # no. documents in which term occurs
    
    # clear out any earlier profiles data
    {
        my $profiles_array = array_from_hash($profiles_data);
        for my $profile_data (@$profiles_array) {
            # delete profile item terms file
            my $old_file = File::Spec->catfile($profiles_path, $profile_data->{'id'} . $TERM_FILE_EXTENSION);
            if (-f $old_file) {
                unlink $old_file;
            }
        }
    }
    %$profiles_data = ();
    
    # construct uri for the resources being created
    my $uri_stem = $settings->{'SITE_URI_BASE'} . '/' . $user_id . '/' . $profiles_type . '/' . $profiles_id . '/items';

    my $timestamp = $profiles_info->{'modified'};

    my $documents_array = array_from_hash($documents_data);
    for my $document_data (@$documents_array) {
        
        my $item_id = $document_data->{'id'};   #document item_id is guaranteed to be legal for filenames and uris

        # get document file
        my $document_file = File::Spec->catfile($documents_path, $item_id . $DOCUMENT_FILE_EXTENSION);
        if (!-f $document_file) {
            render({
                'status' => '404 Not Found',
                'text'   => serialise_error_message("No document text for: $item_id"),
            });
            return;
        }
        
        my $text = util_readFile($document_file, 'UTF-8');       
        #
        # pre-process the document text and save it back to original document file
        #
        if ($remove_html) {
            $text = remove_html($text);
        }
        
        if ($ignore_case) {
            # convert whole string to lower case
            $text = lc($text);
        }
        $text =~ s/\\n//gxsm;   #remove newlines
        util_writeFile($document_file, $text, 'UTF-8');
        
        my $mallet_file = File::Spec->catfile($profiles_path, $item_id . $MALLET_FILE_EXTENSION);
        my $topics_file = File::Spec->catfile($profiles_path, $item_id . ".topics");
        my $word_topic_conut = File::Spec->catfile($profiles_path, $item_id . "_word_topic_count");
        my $word_topic_weights = File::Spec->catfile($profiles_path, $item_id . "_word_topic_weights");
        my $topics_model = File::Spec->catfile($profiles_path, $item_id . ".model");

		my $import_data_options = "--keep-sequence";
		if ($remove_stopwords) {
			$import_data_options = $import_data_options . " --remove-stopwords";
		}
	    # Import documents to MALLET data format
	    system($mallet_bin, "import-file", "--input", $document_file, "--output", $mallet_file, $import_data_options);
	    
	    # Train topics from MALLET data format
	    my $train_tp_options = 	"--num-topics ${num_topics} ".
	    					"--output-topic-keys ${topics_file} ".
	    					"--word-topic-counts-file ${word_topic_conut} ".
	    					"--topic-word-weights-file ${word_topic_weights}";
	    if($output_model) {
	    	$train_tp_options = $train_tp_options . " --output-model ${topics_model}";
	    }elsif(-f $topics_model) {
	    	$train_tp_options = $train_tp_options . " --input-model ${topics_model} --output-model ${topics_model}";
	    }
	    
	    if($num_threads) {
	    	$train_tp_options = $train_tp_options ." --num-threads $num_threads";
	    }
	    if($num_iterations) {
	    	$train_tp_options = $train_tp_options ." --num-iterations $num_iterations";
	    }
	    if($random_seed) {
	    	$train_tp_options = $train_tp_options ." --random-seed $random_seed";
	    }
	    if($num_top_words) {
	    	$train_tp_options = $train_tp_options ." --num-top-words $num_top_words";
	    }
	    
	    if($use_ngram) {
	    	$train_tp_options = $train_tp_options ." --use-ngrams";
	    }
	    elsif($use_pam) {
	    	$train_tp_options = $train_tp_options ." --use-pam";
	    }
	    
	    if($alpha) {
	    	$train_tp_options = $train_tp_options ." --alpha $alpha";
	    }
	    if($beta) {
	    	$train_tp_options = $train_tp_options ." --beta $beta";
	    }
	    if($gamma) {
	    	$train_tp_options = $train_tp_options ." --gamma $gamma";
	    }
	    if($delta1) {
	    	$train_tp_options = $train_tp_options ." --delta1 $delta1";
	    }
	    if($delta2) {
	    	$train_tp_options = $train_tp_options ." --delta2 $delta2";
	    }
	  	my $stderr_train_topics = `${mallet_bin} train-topics --input ${mallet_file} ${train_tp_options} 2>&1 1>/dev/null`;
	    
#        # split string into words
#        my @words = split( /[^\p{L}_]+/, $text );
# 	    @words = grep( /.{$length,}/, @words );     #strip out words only 0 characters long (or below min length)
#        if ($remove_stopwords) {
#            # filter out any unwanted (by default these are common English) words
#            if ($ignore_case) {
#                @words = grep { !$stopwords{$_} } @words;
#            }
#            else {
#                @words = grep { !$stopwords{lc($_)} } @words;
#            }
#        }
#        
#        if ($stem) {
#            # apply Porter Stemming to words
#            @words = Text::English::stem( @words );
#        }
#        
#        if (scalar @nvalues > 0) {
#            # construct n-grams and append to list of words
#            my @grams = ();
#            for my $n (@nvalues) {
#                if ($n == 1) {
#                    # no need to construct 1-grams, so just append them
#                    @grams = (@grams, @words);
#                }
#                elsif (scalar(@words) >= $n) {
#                    # construct n-grams
#                    my $nm1 = $n - 1;
#                    my $ilim = scalar(@words) - $nm1;
#                    for (my $i=0; $i < $ilim; $i++) {
#                        push(@grams, join(' ', @words[$i..$i+$nm1]));
#                    }
#                }
#            }
#            @words = @grams;
#        }
#        if ($restrict_vocabulary) {
#            # filter out words not in predefined vocabulary
#            if ($ignore_case) {
#                @words = grep { $vocabulary{$_} } @words;
#            }
#            else {
#                @words = grep { $vocabulary{lc($_)} } @words;
#            }
#        }
#        
#        # count number of occurrences of each term in this document
#        my %term_n = ();
#    	foreach my $term (@words){
#		    $term_n{$term}++;
#	    }
#	    
        # create a new profile item in the profiles metadata
        $profiles_data->{$item_id} = {
            'type'          => $profiles_type,
            'id'            => $item_id,
            'description'   => $document_data->{'description'},
            'source'        => $document_data->{'source'},
            'document'      => $document_data->{'uri'},
            'created'       => $timestamp,
            'modified'      => $timestamp,
#            'document_n'    => scalar(@words),
#            'term_n'        => \%term_n,
            'uri'           => $uri_stem . '/' . $item_id,
        };
#
#        # update corpus statistics
#        foreach my $term (keys %term_n) {
#            $corpus_n{$term} += $term_n{$term};
#            $corpus_dt{$term}++;
#        }

    }
}

sub helper_tfidf_from_documents_folder {
    #
    # Calculate the tfidf for all terms in each document of the specified documents folder.
    # Stores terms and values in a simple (fast) custom serialisation of a hash.
    #
    # NB. Populates $profiles_info and profiles_data with one item per document
    #
    my ($profiles_type, $settings, $params, 
        $profiles_info, $profiles_data, $documents_info, $documents_data, $weights) = @_;

    my $user_id = $params->{'user_id'};

    # profiles folder_id
    my $profiles_id = $profiles_info->{'id'};
    # documents folder being profiled
    my $documents_id        = $profiles_info->{'document_id'};

    # text processing and computational parameters
    my $ignore_case         = $profiles_info->{'ignore_case'};
    my $remove_html         = $profiles_info->{'remove_html'};
    my $remove_stopwords    = $profiles_info->{'remove_stopwords'};
    my $stopwords           = $profiles_info->{'stopwords'};
    my $stem                = $profiles_info->{'stem'};
    my $ngrams              = $profiles_info->{'ngrams'};
    my $restrict_vocabulary = $profiles_info->{'restrict_vocabulary'};
    my $vocabulary          = $profiles_info->{'vocabulary'};
    my $limit               = $profiles_info->{'limit'};
    my $length              = $profiles_info->{'length'};
#$term_weights is not required as weights are pre-parsed and passed in as $weights hashref
#    my $term_weights        = $profiles_info->{'term_weights'};
    my $term_weight_default = $profiles_info->{'term_weight_default'};
    my $threshold           = $profiles_info->{'threshold'};

    # for speed, we directly access the storage layer (without using helper_[load|save]_file)
    my $profiles_path = helper_folders_path($profiles_type, $settings, $params, $profiles_id);
    if (performed_render()) {
        return;
    }
    my $documents_path = helper_folders_path($DOCUMENTS_TYPE, $settings, $params, $documents_id);
    if (performed_render()) {
        return;
    }
    
    if ($ngrams !~ m/^\s*[12345](\s*,\s*[12345])*\s*$/gxsm) {
        render({
            'status' => '400 Bad Request',
            'text'   => serialise_error_message('ngrams is not a comma separated list of n (n in range 1..5)'),
        });
        return;
    }
    # convert comma separated list string to an array of numbers
    $ngrams =~ s/\s+//gxsm;
    my @nvalues = ();
    if ($ngrams ne '') {
        @nvalues = split(',', $ngrams);
        @nvalues = map { 1.0 * $_ } @nvalues;
    }
 
    # get hash of unwanted words (from a comma separated string of words)
    my @stopwords = grep( /.+/, split(/,/, Encode::decode('Detect', $stopwords)) );
    my %stopwords = map { $_, 1 } @stopwords;

    # get hash of restricted words (from a comma separated string of words)
    my @vocabulary = grep( /.+/, split(/,/, Encode::decode('Detect', $vocabulary)) );
    my %vocabulary = map { $_, 1 } @vocabulary;
    
    # initialise corpus term statistics
    my %corpus_n = ();      # no. occurrences of term across all documents
    my %corpus_dt = ();     # no. documents in which term occurs
    
    # clear out any earlier profiles data
    {
        my $profiles_array = array_from_hash($profiles_data);
        for my $profile_data (@$profiles_array) {
            # delete profile item terms file
            my $old_file = File::Spec->catfile($profiles_path, $profile_data->{'id'} . $TERM_FILE_EXTENSION);
            if (-f $old_file) {
                unlink $old_file;
            }
        }
    }
    %$profiles_data = ();
    
    # construct uri for the resources being created
    my $uri_stem = $settings->{'SITE_URI_BASE'} . '/' . $user_id . '/' . $profiles_type . '/' . $profiles_id . '/items';

    my $timestamp = $profiles_info->{'modified'};

    my $documents_array = array_from_hash($documents_data);

    for my $document_data (@$documents_array) {
        
        my $item_id = $document_data->{'id'};   #document item_id is guaranteed to be legal for filenames and uris

        #
        # load document text from the document [NOTE: for speed, do not use helper_load_file]
        #
        
        my $document_file = File::Spec->catfile($documents_path, $item_id . $DOCUMENT_FILE_EXTENSION);
        
        if (!-f $document_file) {
            render({
                'status' => '404 Not Found',
                'text'   => serialise_error_message("No document text for: $item_id"),
            });
            return;
        }
        my $text = util_readFile($document_file, 'UTF-8');

        #
        # process the document text to produce term counts and statistics
        #
        
        if ($remove_html) {
            $text = remove_html($text);
        }
        
        if ($ignore_case) {
            # convert whole string to lower case
            $text = lc($text);
        }

        # split string into words
        my @words = split( /[^\p{L}_]+/, $text );
 	    @words = grep( /.{$length,}/, @words );     #strip out words only 0 characters long (or below min length)
        if ($remove_stopwords) {
            # filter out any unwanted (by default these are common English) words
            if ($ignore_case) {
                @words = grep { !$stopwords{$_} } @words;
            }
            else {
                @words = grep { !$stopwords{lc($_)} } @words;
            }
        }
        
        if ($stem) {
            # apply Porter Stemming to words
            @words = Text::English::stem( @words );
        }
        
        if (scalar @nvalues > 0) {
            # construct n-grams and append to list of words
            my @grams = ();
            for my $n (@nvalues) {
                if ($n == 1) {
                    # no need to construct 1-grams, so just append them
                    @grams = (@grams, @words);
                }
                elsif (scalar(@words) >= $n) {
                    # construct n-grams
                    my $nm1 = $n - 1;
                    my $ilim = scalar(@words) - $nm1;
                    for (my $i=0; $i < $ilim; $i++) {
                        push(@grams, join(' ', @words[$i..$i+$nm1]));
                    }
                }
            }
            @words = @grams;
        }
        if ($restrict_vocabulary) {
            # filter out words not in predefined vocabulary
            if ($ignore_case) {
                @words = grep { $vocabulary{$_} } @words;
            }
            else {
                @words = grep { $vocabulary{lc($_)} } @words;
            }
        }
        
        # count number of occurrences of each term in this document
        my %term_n = ();
    	foreach my $term (@words){
		    $term_n{$term}++;
	    }
	    
        # create a new profile item in the profiles metadata
        $profiles_data->{$item_id} = {
            'type'          => $profiles_type,
            'id'            => $item_id,
            'description'   => $document_data->{'description'},
            'source'        => $document_data->{'source'},
            'document'      => $document_data->{'uri'},
            'created'       => $timestamp,
            'modified'      => $timestamp,
            'document_n'    => scalar(@words),
            'term_n'        => \%term_n,
            'uri'           => $uri_stem . '/' . $item_id,
        };

        # update corpus statistics
        foreach my $term (keys %term_n) {
            $corpus_n{$term} += $term_n{$term};
            $corpus_dt{$term}++;
        }

    }
    
    # dereference global weights
    my $weights_global = $weights->{$ALL_DOCUMENTS_ID};
    
    # if only keep top $limit terms for each profile, then we can discard 
    # terms that do not appear in the top $limit of any profile
    my %corpus_include = ();

    # calculate tfidf vector for document
    my $noofdocs = scalar(@$documents_array);
    # if only one document in corpus then treat noofdocs as 2 to avoid getting log(1/1)=0 for idf
    my $adjusted_noofdocs = ($noofdocs == 1) ? 2 : $noofdocs;
    my $log_2 = log(2.0);
    for my $document_data (@$documents_array) {
        
        my $item_id = $document_data->{'id'};

        my $document_n = $profiles_data->{$item_id}{'document_n'};
        my $term_n = $profiles_data->{$item_id}{'term_n'};
        my $weights_local = $weights->{$item_id};
        my @ranklist = ();
        while (my ($term, $n) = each(%$term_n)) {
            my $tf = $n / $document_n;
            my $idf = log( $adjusted_noofdocs / $corpus_dt{$term} ) / $log_2;
            my $tfidf = $tf * $idf;
            my $term_weight_global = $weights_global->{$term}; 
            if (!defined $term_weight_global) { $term_weight_global = $term_weight_default; }
            my $term_weight_local  = $weights_local->{$term};
            if (!defined $term_weight_local) { $term_weight_local = $term_weight_default; }
            my $weighted_tfidf = $tfidf * $term_weight_global * $term_weight_local;
            push(@ranklist, [ 
                $weighted_tfidf, 
                $term, 
                [$n, $tf, $idf, $tfidf, $term_weight_global, $term_weight_local, $weighted_tfidf]
            ]);
        }

        # apply limit to the number of terms retained
        if ($limit < scalar(@ranklist)) {
            # only keep the top $limit tfidf scoring terms
            @ranklist = sort { $b->[0] <=> $a->[0] } @ranklist;
            @ranklist = @ranklist[0..$limit-1];
        }

        # enforce a score threshold if there is one
        if ($threshold > 0) {
            # only keep terms with tfidf scores greater than or equal to threshold
            @ranklist = grep($_->[0] > $threshold, @ranklist);
        }
        
        # reconstruct the terms hash
        my %terms = map( ($_->[1], $_->[2]), @ranklist );

        # record which terms in the corpus appear in the top $limit terms of some profile
        foreach my $tuple (@ranklist) {
            $corpus_include{$tuple->[1]} = 1;
        }

        # save the document statistics [NOTE: for speed, do not use helper_save_file]
        my $document_n_file = File::Spec->catfile($profiles_path, $item_id . $TERM_FILE_EXTENSION);
#        util_writeFile($document_n_file, join("\n", %terms), 'UTF-8');
        util_writeFile($document_n_file, JSON->new->canonical->pretty->encode(\%terms));

        # remove the term_n hash from the stored metadata [NOTE: to keep file size manageable]
        delete $profiles_data->{$item_id}{'term_n'};
    }
    
    # filter out all terms which do not appear in the top $limit terms of any profile
    my %included_corpus_n = ();
    my %included_corpus_dt = ();
    foreach my $term (keys %corpus_include) {
        $included_corpus_n{$term} = $corpus_n{$term};
        $included_corpus_dt{$term} = $corpus_dt{$term};
    }

##BACKGROUND KNOWLEDGE
    # save the corpus statistics
    my $corpus_n_file = File::Spec->catfile($profiles_path, helper_document_n_file_id() . $TERM_FILE_EXTENSION);
#    util_writeFile($corpus_n_file, join("\n", %included_corpus_n), 'UTF-8');
    util_writeFile($corpus_n_file, JSON->new->canonical->pretty->encode(\%included_corpus_n));
    my $corpus_dt_file = File::Spec->catfile($profiles_path, helper_document_dt_file_id() . $TERM_FILE_EXTENSION);
#    util_writeFile($corpus_dt_file, join("\n", %included_corpus_dt), 'UTF-8');
    util_writeFile($corpus_dt_file, JSON->new->canonical->pretty->encode(\%included_corpus_dt));

}

sub helper_document_n_file_id { return 'COLLECTION_n'; }
sub helper_document_dt_file_id { return 'COLLECTION_dt'; }


sub helper_load_terms_for {
    my ($folder_type, $settings, $params, $folder_id, $item_id) = @_;

    my $folder_path = helper_folders_path($folder_type, $settings, $params, $folder_id);
    if (performed_render()) {
        return;
    }

    my $terms_file = File::Spec->catfile($folder_path, $item_id . $TERM_FILE_EXTENSION);
    my %terms = ();
    if (!-f $terms_file) {
        return \%terms;
    }
#    %terms = split("\n", util_readFile($terms_file, 'UTF-8'));
    my $terms_hashref = JSON->new->decode( util_readFile($terms_file) );

    return $terms_hashref;
}


sub helper_profiles_addin_full {
    #
    # Augment $profiles_info hash with extra data retrieved from associated external file
    #
    my ($folder_type, $settings, $params, $profiles_info) = @_;

    my $folder_id = $params->{'folder_id'} || $profiles_info->{'id'};
    my $sort_ix = $params->{'sort'};

    my $folder_path = helper_folders_path($folder_type, $settings, $params, $folder_id);
    if (performed_render()) {
        return;
    }

    my $terms_n_file = File::Spec->catfile($folder_path, helper_document_n_file_id() . $TERM_FILE_EXTENSION);
#    my %terms_n  = split("\n", util_readFile($terms_n_file, 'UTF-8'));
    my $terms_n_hashref  = JSON->new->decode( util_readFile($terms_n_file) );

    my $terms_dt_file = File::Spec->catfile($folder_path, helper_document_dt_file_id() . $TERM_FILE_EXTENSION);
#    my %terms_dt = split("\n", util_readFile($terms_dt_file, 'UTF-8'));
    my $terms_dt_hashref  = JSON->new->decode( util_readFile($terms_dt_file) );

    # reconstruct values as arrays
    my @rank = ();
#    while( my ($term, $n) = each(%terms_n) ) {
    while( my ($term, $n) = each(%$terms_n_hashref) ) {
#        # construct 3-tuples name,n,dt (forcing type of numbers by adding zero)
#        my @stats = ($term, 0 + $n, 0 + $terms_dt_hashref->{$term});
        # construct 3-tuples name,n,dt
        my @stats = ($term, $n, $terms_dt_hashref->{$term});
        push(@rank, \@stats);
    }
    if (scalar(@rank) > 0) {
        # order by rightmost stat
        my $ix = (defined $sort_ix) ? $sort_ix : scalar(@{$rank[0]}) - 1;
        if ($ix == 0) {
            @rank = sort { $a->[$ix] cmp $b->[$ix] } @rank;
        }
        else {
            @rank = sort { $b->[$ix] <=> $a->[$ix] } @rank;
        }
    }

    # convert arrays to hashes
    for(my $i=0; $i<scalar(@rank); $i++) {
        $rank[$i] = {
            'name'  => Encode::encode('UTF-8', $rank[$i][0]),
            'n'     => $rank[$i][1],
            'dt'    => $rank[$i][2],
        };
    }

    $profiles_info->{'term'} = \@rank;

    return;
}

sub helper_load_topics_for {
    my ($folder_type, $settings, $params, $folder_id, $item_id) = @_;

    my $folder_path = helper_folders_path($folder_type, $settings, $params, $folder_id);
    if (performed_render()) {
        return;
    }

	my $terms_file = File::Spec->catfile($folder_path, $item_id . $TERM_FILE_EXTENSION);
    my $topics_file = File::Spec->catfile($folder_path, $item_id . ".topics");
    my $wtw = File::Spec->catfile($folder_path, $item_id . "_word_topic_weights");
    my $wtc = File::Spec->catfile($folder_path, $item_id . "_word_topic_count");
    my %terms = ();
    my $terms_json = "{";
    if (!-f $terms_file) {
    	# transform .topics, weigths and counts into terms JSON format
    	my $wtc = util_readFile($wtc);
    	my $wtw = util_readFile($wtw);
    	my $topics = util_readFile($topics_file);
    	my @topics = split(/\n/, $topics);
    	# read topics from file
    	foreach my $topic (@topics) {
    		my @tp_terms = split(/\t/,$topic);
    		my %words = ();
    		foreach my $wd (split(/ /, $tp_terms[2])){
    			$words{$wd} = [];
    		}
    		$terms{$tp_terms[0]} = \%words;
    	}
    	# read word's counts of each topic from files
    	foreach my $count(split(/\n/, $wtc)){
    		my @wtc_info = split(/ /, $count);
    		for(my $i=2; $i<scalar(@wtc_info); $i++){
    			my($topic_no, $word_cnt) = split(/:/, $wtc_info[$i]);
    			$terms{$topic_no}{$wtc_info[1]}[0] = $word_cnt;
    		}
    	}
    	# read word's weight of each topic from files
    	foreach my $weigth(split(/\n/, $wtw)){
    		my @wtw_info = split(/\t/, $weigth);
    		if(defined $terms{$wtw_info[0]}{$wtw_info[1]}) {
    			$terms{$wtw_info[0]}{$wtw_info[1]}[1] = $wtw_info[2];
    		}
    	}
    	util_writeFile($terms_file, JSON->new->canonical->pretty->encode(\%terms), 'UTF-8');
        return \%terms;
    }
    my $terms_hashref = JSON->new->decode( util_readFile($terms_file) );
    return $terms_hashref;
}

sub helper_unpack_topics {
    #
    # unpack topic modelling data from MALLET tool
    #
    my ($params, $terms) = @_;

    my $sort_ix = $params->{'sort'};

    # reconstruct values as arrays
    my @rank = ();
    while (my ($term, $stats_arrayref) = each(%$terms)) {
        my @stats = ($term, @$stats_arrayref);
        push(@rank, \@stats);
    }

    if (scalar(@rank) > 0) {
        # order by rightmost stat
        my $ix = (defined $sort_ix) ? $sort_ix : scalar(@{$rank[0]}) - 1;
        if ($ix == 0) {
            @rank = sort { $a->[$ix] cmp $b->[$ix] } @rank;
        }
        else {
            @rank = sort { $b->[$ix] <=> $a->[$ix] } @rank;
        }
    }

    # replace each array with a hash
    for(my $i=0; $i<scalar(@rank); $i++) {
        my $r = $rank[$i];
        $rank[$i] = {
            'name'  => Encode::encode('UTF-8', $r->[0]),
            'n'     => $r->[1],
            'tf'    => $r->[2],
            'idf'   => $r->[3],
            'tfidf' => $r->[4],
            'wg'     => $r->[5],
            'wl'     => $r->[6],
            'wtfidf' => $r->[7],
        };
    }

    return \@rank;
}


sub helper_unpack_terms {
    #
    # unpack a hash of strings (where the string is a comma separated list of numbers)
    # returning an array of hashes ordered by the rightmost number in the list
    #
    my ($params, $terms) = @_;

    my $sort_ix = $params->{'sort'};

    # reconstruct values as arrays
    my @rank = ();
    while (my ($term, $stats_arrayref) = each(%$terms)) {
#    while (my ($term, $str) = each(%$terms)) {
#        # unpack into n-tuples name,numbers... (forcing type of numbers by adding zero)
#        my @stats = ($term, map {0 + $_} split(',', $str));
        my @stats = ($term, @$stats_arrayref);
        push(@rank, \@stats);
    }

    if (scalar(@rank) > 0) {
        # order by rightmost stat
        my $ix = (defined $sort_ix) ? $sort_ix : scalar(@{$rank[0]}) - 1;
        if ($ix == 0) {
            @rank = sort { $a->[$ix] cmp $b->[$ix] } @rank;
        }
        else {
            @rank = sort { $b->[$ix] <=> $a->[$ix] } @rank;
        }
    }

    # replace each array with a hash
    for(my $i=0; $i<scalar(@rank); $i++) {
        my $r = $rank[$i];
        $rank[$i] = {
            'name'  => Encode::encode('UTF-8', $r->[0]),
            'n'     => $r->[1],
            'tf'    => $r->[2],
            'idf'   => $r->[3],
            'tfidf' => $r->[4],
            'wg'     => $r->[5],
            'wl'     => $r->[6],
            'wtfidf' => $r->[7],
        };
    }

    return \@rank;
}




###########################################################################

sub helper_default_stopwords {
    return <<'__';
a,about,above,across,after,afterwards,again,against,all,almost,alone,along,
already,also,although,always,am,among,amongst,amount,an,and,another,
any,anyhow,anyone,anything,anyway,anywhere,are,around,as,at,back,be,became,
because,become,becomes,becoming,been,before,beforehand,behind,being,below,
beside,besides,between,beyond,bill,both,bottom,but,by,call,can,cannot,cant,
co,computer,con,could,couldnt,cry,de,describe,detail,do,done,down,due,during,
each,eg,eight,either,eleven,else,elsewhere,empty,enough,etc,even,ever,every,
everyone,everything,everywhere,except,few,fifteen,fifty,fill,find,fire,first,
five,for,former,formerly,forty,found,four,from,front,full,further,get,give,
go,had,has,hasnt,have,he,hence,her,here,hereafter,hereby,herein,hereupon,
hers,herself,him,himself,his,how,however,hundred,i,ie,if,in,inc,indeed,
interest,into,is,it,its,itself,keep,last,latter,latterly,least,less,ltd,made,
many,may,me,meanwhile,might,mill,mine,more,moreover,most,mostly,move,much,
must,my,myself,name,namely,neither,never,nevertheless,next,nine,no,nobody,
none,noone,nor,not,nothing,now,nowhere,of,off,often,on,once,one,only,onto,or,
other,others,otherwise,our,ours,ourselves,out,over,own,part,per,perhaps,
please,put,rather,re,same,see,seem,seemed,seeming,seems,serious,several,she,
should,show,side,since,sincere,six,sixty,so,some,somehow,someone,something,
sometime,sometimes,somewhere,still,such,system,take,ten,than,that,the,their,
them,themselves,then,thence,there,thereafter,thereby,therefore,therein,
thereupon,these,they,thick,thin,third,this,those,though,three,through,
throughout,thru,thus,to,together,too,top,toward,towards,twelve,twenty,two,un,
under,until,up,upon,us,very,via,was,we,well,were,what,whatever,when,whence,
whenever,where,whereafter,whereas,whereby,wherein,whereupon,wherever,whether,
which,while,whilst,whither,who,whoever,whole,whom,whose,why,will,with,within,
without,would,yet,you,your,yours,yourself,yourselves
__
}

sub remove_html {
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

sub helper_normalise_wordlist {
    #
    #   STRING helper_normalise_wordlist(STRING $terms)
    #
    #   Normalise whitespace (and commas) to csv
    #
    my ($terms) = @_;
    $terms = util_trim($terms);
    if (index($terms, ',') < 0) {
        # no commas, so assume whitespace separated
        if ($terms =~ m/[\r\n\t]+/xms) {
            # convert newlines or tabs to commas
            $terms =~ s/[\r\n\t]+/,/gxms;
        }
        else {
            # convert all whitespace to commas (i.e. 1-grams only)
            $terms =~ s/\s+/,/gxms;
        }
    }
    # normalise whitespace
    $terms =~ s/\s+/\ /gxms;
    # normalise commas and remove their surrounding whitespace
    $terms =~ s/(?:\s*,\s*)+/,/gxms;
    # remove leading comma
    $terms =~ s/^,//gxms;
    # remove trailing comma
    $terms =~ s/,$//gxms;
    return $terms;
}


sub helper_parse_term_weights {
    #
    #   HASHREF helper_parse_term_weights(STRING $weights)
    #
    #   Parse string of text lines where each line is:
    #       [document item id], term, weight[, term,weight[, ..., term,weight]]
    #
    #   Returns HASHREF keyed on document_item_id of HASHREF weights keyed on term.
    #
    my ($term_weights) = @_;
    my %weights = ();
    if (!defined $term_weights || $term_weights eq '') {
        return \%weights;
    }

    my $err;
    my @lines = ();
    eval{
        @lines = @{csv_parse_string($term_weights)};
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
            'text'   => serialise_error_message('Invalid term_weights'),
        });
        return \%weights;
    }

    # verify that all rows parsed okay and that fields are as expected
    my $line_number = 0;
    foreach my $fields (@lines) {
        $line_number++;
        # if an even number of fields on line then assume all <term, weight> pairs
        # otherwise assume <document_item_id> followed by <term, weight> pairs
        my $n = scalar(@$fields);
        my $document_item_id = $ALL_DOCUMENTS_ID;
        if ($n & 1) {
            $document_item_id = shift @$fields;
            $n--;
        }

        # add all <term, weight> pairs to document's hash
        for (my $i=0; $i<$n; $i+=2) {
            my $term   = $fields->[$i];
            my $weight = $fields->[$i+1];
            if (!(defined $term && $term ne '' &&
                  defined $weight && $weight =~ m{^(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]\d+)?$}xsm &&
                  (0.0 + $weight) <= 1.0)
               ) {
                render({
                    'status' => '400 Bad Request',
                    'text'   => serialise_error_message("Invalid term, weight pairs at line $line_number"),
                });
                return \%weights;
            }
            $weights{$document_item_id}{ Encode::decode('UTF-8', $term) } = 0.0 + $weight;
        }
    }
    return \%weights;
}


1;