# profiles_controller.pl
use strict;
use warnings;
use Data::Dumper;

# for access to raw params
require 'params.pl';

require '_folders_helper.pl';
require 'profiles_helper.pl';

my $FALSE = 0;
my $TRUE  = 1;

my $FOLDER_TYPE    = 'profiles';
my $DOCUMENTS_TYPE = 'documents';


sub controller_profiles {
    my ($settings, $params) = @_;

	# changes made by Brian Liu
	# action start with /create/ for supporting both tf-idf and topics modelling
    if (defined $params->{'folder_id'} && $params->{'action'} !~ /create/) {
        my $info = helper_folders_get_info($FOLDER_TYPE, $settings, $params);
        if (defined $info && $info->{'mode'} eq 'private') {
            # insist that request is authenticated
            error_unless_authenticated($settings, $params);
        }
    }
}


sub action_profiles_list {
    my ($settings, $params) = @_;

    my $profiles_arrayref = helper_list_folders($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }
    my $full = $params->{'full'};
    my $items = $params->{'items'};

	
    if ($full) {
        for my $profiles_info (@$profiles_arrayref) {
            helper_profiles_addin_full($FOLDER_TYPE, $settings, $params, $profiles_info);
            if (performed_render()) {
                return;
            }
        }
    }

    if ($items) {
        for my $profiles_info (@$profiles_arrayref) {
            $params->{'folder_id'} = $profiles_info->{'id'};  #inject folder_id into params hash
            my (
              $profiles_info_file, $_profiles_info, 
              $profiles_data_file, $profiles_data
            ) = helper_load_folder($FOLDER_TYPE, $settings, $params);
            if (performed_render()) {
                return;
            }
            $profiles_info->{'item'} = array_from_hash($profiles_data);
        }
    }

    my $text = serialise({'folder' => $profiles_arrayref});
    render({ 'text' => $text });
}

sub action_profiles_create_topics{
	#
	# Create profile by using MALLET topic modelling
	#
	
	my ($settings, $params) = @_;
    my $mode = $params->{'mode'};
    my $description = $params->{'description'};
    my $full = $params->{'full'};

    # text processing and computational parameters
    # new parameters for topic modelling
    my $output_model        = $params->{'output_model'};	#Default is false
	my $num_topics          = $params->{'num_topics'};		#Default is 10
    my $num_threads			= $params->{'num_threads'};		#Default is 1
    my $num_iterations		= $params->{'num_iterations'};	#iterations of Gibbs sampling, default is 1000
    my $random_seed			= $params->{'random_seed'};		#for the Gibbs sampler, default is 0
    my $num_top_words		= $params->{'num_top_words'};	#most probable words for each topic, default is 20
    my $use_ngram			= $params->{'use_ngram'};		#Defaul is LDA, use Toical-N-Grams
    my $use_pam				= $params->{'use_pam'};			#Defaul is LDA, use Pachinko Allocation Model, conflict with use_ngram
    my $alpha				= $params->{'alpha'};			#smoothing over topic distribution, default is 50.0
    my $beta				= $params->{'beta'};				#smoothing over unigram distribution, default is 0.01
    my $gamma				= $params->{'gamma'};			#smoothing over bigram distribution, default is 0.01
    my $delta1				= $params->{'delta1'};			#Topic N-gram smoothing parameter, default is 0.2
    my $delta2				= $params->{'delta2'};			#Topic N-gram smoothing parameter, default is 1000.0
    
    my $ignore_case = $params->{'ignore_case'};
    my $remove_html = $params->{'remove_html'};
    my $remove_stopwords = $params->{'remove_stopwords'};
    my $stopwords = helper_normalise_wordlist(
        (($params->{'stopwords'} eq '') ? helper_default_stopwords() : $params->{'stopwords'})
    );
    my $stem = $params->{'stem'};
    my $ngrams = $params->{'ngrams'};
    my $restrict_vocabulary = $params->{'restrict_vocabulary'};
    my $vocabulary = helper_normalise_wordlist($params->{'vocabulary'});
    my $limit = $params->{'limit'};
    my $length = $params->{'length'};
    my $term_weights = $params->{'term_weights'};
    my $term_weight_default = $params->{'term_weight_default'} + 0.0;
    my $threshold = $params->{'threshold'};

    # because there are multiple route patterns that lead to here, document_id may be null
    my $document_id = $params->{'document_id'};
    if (!defined $document_id || $document_id eq '') {
        # default to documents folder ID being same as the profiles folder ID
        $document_id = $params->{'folder_id'};
    }


    # parse and validate term weights (both global and document-specific)
    #my $weights = helper_parse_term_weights($term_weights);

    # get the metadata of the document we are profiling
    # (also validates and gives us access to document id param)
    my (
        $__document_info_file, $document_info, 
        $__document_data_file, $document_data
       ) = helper_load_folder_for($DOCUMENTS_TYPE, $settings, $params, $document_id);
    if (performed_render()) {
        return;
    }

    # create profile info hash which will be serialised to a file in the created folder
    my %info = (
          # generic "thing" parameters
        'type'                  => undef,
        'id'                    => undef,
        'mode'                  => $mode,
        'description'           => $description,
        'created'               => undef,
        'modified'              => undef,
        'uri'                   => undef,
          # id of document to profile        
        'document_id'           => $document_info->{'id'},
          # computational parameters
        'output_model'			=> $output_model,
        'num_topics'			=> $num_topics,
        'num_threads'			=> $num_threads,
        'num_iterations'		=> $num_iterations,
        'random_seed'			=> $random_seed,
        'num_top_words'			=> $num_top_words,
        'use_ngram'				=> $use_ngram,
        'use_pam'				=> $use_pam,
        'alpha'					=> $alpha,
        'beta'					=> $beta,
        'gamma'					=> $gamma,
        'delta1'				=> $delta1,
        'delta2'				=> $delta2,
        'ignore_case'           => $ignore_case,
        'remove_html'           => $remove_html,
        'remove_stopwords'      => $remove_stopwords,
        'stopwords'             => helper_normalise_wordlist($stopwords),
        'stem'                  => $stem,
        'ngrams'                => $ngrams,
        'restrict_vocabulary'   => $restrict_vocabulary,
        'vocabulary'            => helper_normalise_wordlist($vocabulary),
        'limit'                 => $limit,
        'length'                => $length,
        'term_weights'          => $term_weights,
        'term_weight_default'   => $term_weight_default,
        'threshold'             => $threshold,
    );
    helper_folders_create($FOLDER_TYPE, $settings, $params, \%info);
    if (performed_render()) {
        return;
    }
    
    # get the metadata and file details of the profile just created
    my (
        $profiles_info_file, $profiles_info, 
        $profiles_data_file, $profiles_data
       ) = helper_load_folder($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    # compute a profile for each document from the document
    helper_topics_from_documents_folder($FOLDER_TYPE, $settings, $params, 
        $profiles_info, $profiles_data, $document_info, $document_data
    );
    if (performed_render()) {
        return;
    }

    my $profile_array = helper_save_things_data($profiles_data_file, $profiles_data);
    if (performed_render()) {
        return;
    }
    helper_folders_put_info_file($profiles_info_file, $profiles_info);
    if (performed_render()) {
        return;
    }

    if ($full) {
        helper_profiles_addin_full($FOLDER_TYPE, $settings, $params, $profiles_info);
        if (performed_render()) {
            return;
        }
    }

    my $text = serialise({'folder' => $profiles_info});
    render({
        'status'    => '201 Created',
        'headers'   => { 'Location' => $info{'uri'} },
        'text'      => $text,
    });
}

sub action_profiles_update_topics{
	#
	# Update profile by using MALLET topic modelling
	#
	
	my ($settings, $params) = @_;
    
    my (
        $profiles_info_file, $profiles_info, 
        $profiles_data_file, $profiles_data
       ) = helper_load_folder($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $mode = $params->{'mode'};
    my $description = $params->{'description'};
    my $full = $params->{'full'};
    
    my $mallet_bin = 'bin/mallet';
    
    #
    # TODO
	#
}

sub action_profiles_create {
    my ($settings, $params) = @_;
    
    my $mode = $params->{'mode'};
    my $description = $params->{'description'};
    my $full = $params->{'full'};

    # text processing and computational parameters

    my $ignore_case = $params->{'ignore_case'};
    my $remove_html = $params->{'remove_html'};
    my $remove_stopwords = $params->{'remove_stopwords'};
    my $stopwords = helper_normalise_wordlist(
        (($params->{'stopwords'} eq '') ? helper_default_stopwords() : $params->{'stopwords'})
    );
    my $stem = $params->{'stem'};
    my $ngrams = $params->{'ngrams'};
    my $restrict_vocabulary = $params->{'restrict_vocabulary'};
    my $vocabulary = helper_normalise_wordlist($params->{'vocabulary'});
    my $limit = $params->{'limit'};
    my $length = $params->{'length'};
    my $term_weights = $params->{'term_weights'};
    my $term_weight_default = $params->{'term_weight_default'} + 0.0;
    my $threshold = $params->{'threshold'};

    # because there are multiple route patterns that lead to here, document_id may be null
    my $document_id = $params->{'document_id'};
    if (!defined $document_id || $document_id eq '') {
        # default to documents folder ID being same as the profiles folder ID
        $document_id = $params->{'folder_id'};
    }


    # parse and validate term weights (both global and document-specific)
    my $weights = helper_parse_term_weights($term_weights);

    # get the metadata of the document we are profiling
    # (also validates and gives us access to document id param)
    my (
        $__document_info_file, $document_info, 
        $__document_data_file, $document_data
       ) = helper_load_folder_for($DOCUMENTS_TYPE, $settings, $params, $document_id);
    if (performed_render()) {
        return;
    }

    # create profile info hash which will be serialised to a file in the created folder
    my %info = (
          # generic "thing" parameters
        'type'                  => undef,
        'id'                    => undef,
        'mode'                  => $mode,
        'description'           => $description,
        'created'               => undef,
        'modified'              => undef,
        'uri'                   => undef,
          # id of document to profile        
        'document_id'           => $document_info->{'id'},
          # computational parameters
        'ignore_case'           => $ignore_case,
        'remove_html'           => $remove_html,
        'remove_stopwords'      => $remove_stopwords,
        'stopwords'             => helper_normalise_wordlist($stopwords),
        'stem'                  => $stem,
        'ngrams'                => $ngrams,
        'restrict_vocabulary'   => $restrict_vocabulary,
        'vocabulary'            => helper_normalise_wordlist($vocabulary),
        'limit'                 => $limit,
        'length'                => $length,
        'term_weights'          => $term_weights,
        'term_weight_default'   => $term_weight_default,
        'threshold'             => $threshold,
    );
    helper_folders_create($FOLDER_TYPE, $settings, $params, \%info);
    if (performed_render()) {
        return;
    }
    
    # get the metadata and file details of the profile just created
    my (
        $profiles_info_file, $profiles_info, 
        $profiles_data_file, $profiles_data
       ) = helper_load_folder($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }
    # compute a profile for each document from the document
    helper_tfidf_from_documents_folder($FOLDER_TYPE, $settings, $params, 
        $profiles_info, $profiles_data, $document_info, $document_data, $weights
    );
    if (performed_render()) {
        return;
    }

    my $profile_array = helper_save_things_data($profiles_data_file, $profiles_data);
    if (performed_render()) {
        return;
    }
    helper_folders_put_info_file($profiles_info_file, $profiles_info);
    if (performed_render()) {
        return;
    }

    if ($full) {
        helper_profiles_addin_full($FOLDER_TYPE, $settings, $params, $profiles_info);
        if (performed_render()) {
            return;
        }
    }

    my $text = serialise({'folder' => $profiles_info});
    render({
        'status'    => '201 Created',
        'headers'   => { 'Location' => $info{'uri'} },
        'text'      => $text,
    });
}


sub action_profiles_destroy {
    my ($settings, $params) = @_;

    my (
        $profiles_info_file, $profiles_info, 
        $profiles_data_file, $profiles_data
       ) = helper_load_folder($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $full = $params->{'full'};

    if ($full) {
        helper_profiles_addin_full($FOLDER_TYPE, $settings, $params, $profiles_info);
        if (performed_render()) {
            return;
        }
    }

    helper_folders_destroy($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $text = serialise({'folder' => $profiles_info});
    render({ 'text' => $text });
}


sub action_profiles_exists {
    my ($settings, $params) = @_;

    my $exists = helper_folders_exists($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    render({
        'text' => '',
        'status' => ($exists) ? '200 OK' : '404 Not Found',
    });
}


sub action_profiles_show {
    my ($settings, $params) = @_;

    my (
        $profiles_info_file, $profiles_info, 
        $profiles_data_file, $profiles_data
       ) = helper_load_folder($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $full = $params->{'full'};

    if ($full) {
        helper_profiles_addin_full($FOLDER_TYPE, $settings, $params, $profiles_info);
        if (performed_render()) {
            return;
        }
    }

    my $text = serialise({'folder' => $profiles_info});
    render({ 'text' => $text });
}


sub action_profiles_update {
    my ($settings, $params) = @_;
    
    my (
        $profiles_info_file, $profiles_info, 
        $profiles_data_file, $profiles_data
       ) = helper_load_folder($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $mode = $params->{'mode'};
    my $description = $params->{'description'};
    my $full = $params->{'full'};

    # text processing and computational parameters
    
    my $ignore_case = $params->{'ignore_case'};
    my $remove_html = $params->{'remove_html'};
    my $remove_stopwords = $params->{'remove_stopwords'};
    my $raw_params = get_raw_params();
    my $stopwords = helper_normalise_wordlist(
        (defined $raw_params->{'stopwords'})
        ?   (($params->{'stopwords'} eq '') ? helper_default_stopwords() : $params->{'stopwords'})
        :   (($profiles_info->{'stopwords'} eq '') ? helper_default_stopwords() : $profiles_info->{'stopwords'})
    );
    my $stem = $params->{'stem'};
    my $ngrams = $params->{'ngrams'};
    my $restrict_vocabulary = $params->{'restrict_vocabulary'};
    my $vocabulary = helper_normalise_wordlist(
        (defined $raw_params->{'vocabulary'}) ? $params->{'vocabulary'} : $profiles_info->{'vocabulary'}
    );
    my $limit = $params->{'limit'};
    my $length = $params->{'length'};
    my $term_weights = $params->{'term_weights'};
    my $term_weight_default = $params->{'term_weight_default'} + 0.0;
    my $threshold = $params->{'threshold'};
    my $force_recalculate = $params->{'recalculate'};

    # document being profiled
    my $document_id = $profiles_info->{'document_id'};
    if (exists $params->{'document_id'} && $params->{'document_id'} ne '') {
        $document_id = $params->{'document_id'};
    }


    # determine whether computational parameters have changed and invalidated the current stats
    my $recalculate = (
        $force_recalculate ||
        !defined $profiles_info->{'document_id'} || $document_id ne $profiles_info->{'document_id'} ||
        !defined $profiles_info->{'ignore_case'} || $ignore_case ne $profiles_info->{'ignore_case'} ||
        !defined $profiles_info->{'remove_html'} || $remove_html ne $profiles_info->{'remove_html'} ||
        !defined $profiles_info->{'remove_stopwords'} || $remove_stopwords ne $profiles_info->{'remove_stopwords'} ||
        !defined $profiles_info->{'stopwords'} || $stopwords ne $profiles_info->{'stopwords'} ||
        !defined $profiles_info->{'stem'} || $ngrams ne $profiles_info->{'stem'} ||
        !defined $profiles_info->{'ngrams'} || $ngrams ne $profiles_info->{'ngrams'} ||
        !defined $profiles_info->{'restrict_vocabulary'} || $restrict_vocabulary ne $profiles_info->{'restrict_vocabulary'} ||
        !defined $profiles_info->{'vocabulary'} || $vocabulary ne $profiles_info->{'vocabulary'} ||
        !defined $profiles_info->{'limit'} || $limit ne $profiles_info->{'limit'} ||
        !defined $profiles_info->{'length'} || $length ne $profiles_info->{'length'} ||
        !defined $profiles_info->{'term_weights'} || $term_weights ne $profiles_info->{'term_weights'} ||
        !defined $profiles_info->{'term_weight_default'} || $term_weight_default ne $profiles_info->{'term_weight_default'} ||
        !defined $profiles_info->{'threshold'} || $threshold ne $profiles_info->{'threshold'}
    ) ? $TRUE : $FALSE;

    # update info hash which will be serialised to a file in the profiles folder
    my $changed = $FALSE;
    my @properties = (
        ['document_id',         'document_id',          $document_id], 
        ['mode',                'mode',                 $mode], 
        ['description',         'description',          $description], 
        ['ignore_case',         'ignore_case',          $ignore_case], 
        ['remove_html',         'remove_html',          $remove_html], 
        ['remove_stopwords',    'remove_stopwords',     $remove_stopwords], 
        ['stopwords',           'stopwords',            $stopwords], 
        ['stem',                'stem',                 $stem], 
        ['ngrams',              'ngrams',               $ngrams], 
        ['restrict_vocabulary', 'restrict_vocabulary',  $restrict_vocabulary], 
        ['vocabulary',          'vocabulary',           $vocabulary], 
        ['limit',               'limit',                $limit], 
        ['length',              'length',               $length], 
        ['term_weights',        'term_weights',         $term_weights], 
        ['term_weight_default', 'term_weight_default',  $term_weight_default], 
        ['threshold',           'threshold',            $threshold], 
    );
    foreach (@properties) {
        my ($key, $cgi_key, $value) = @$_;
        if (exists $params->{$cgi_key} && (!defined $profiles_info->{$key} || $profiles_info->{$key} ne $value)) {
            $profiles_info->{$key} = $value;
            $changed = $TRUE;
        }
    }

    if ($changed) {
        $profiles_info->{'modified'} = time;

        # if changed any of the computational parameters then must recalculate entire profile
        if ($recalculate) {

            # parse and validate term weights (both global and document-specific)
            my $weights = helper_parse_term_weights($term_weights);

            # get the metadata of the document we are profiling
            my (
                $__document_info_file, $document_info, 
                $__document_data_file, $document_data, 
               ) = helper_load_folder_for($DOCUMENTS_TYPE, $settings, $params, $document_id);
            if (performed_render()) {
                return;
            }
    
            # compute a profile for each document from the document
            helper_tfidf_from_documents_folder($FOLDER_TYPE, $settings, $params, 
                $profiles_info, $profiles_data, $document_info, $document_data, $weights
            );
            if (performed_render()) {
                return;
            }

            my $profile_array = helper_save_things_data($profiles_data_file, $profiles_data);
            if (performed_render()) {
                return;
            }
        }
        
        # save the profiles folder metadata
        helper_folders_put_info_file($profiles_info_file, $profiles_info);
        if (performed_render()) {
            return;
        }
    }

    if ($full) {
        helper_profiles_addin_full($FOLDER_TYPE, $settings, $params, $profiles_info);
        if (performed_render()) {
            return;
        }
    }

    my $text = serialise({'folder' => $profiles_info});
    render({ 'text' => $text });
}


sub action_profiles_recalculate {
    my ($settings, $params) = @_;
    
    my (
        $profiles_info_file, $profiles_info, 
        $profiles_data_file, $profiles_data
       ) = helper_load_folder($FOLDER_TYPE, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $full = $params->{'full'};

    $profiles_info->{'modified'} = time;

    # parse and validate term weights (both global and document-specific)
    my $weights = helper_parse_term_weights($profiles_info->{'term_weights'});


    # recalculate entire profile

    # get the metadata of the documents folder we are profiling
    my $document_id = $profiles_info->{'document_id'};
    my (
        $__document_info_file, $document_info, 
        $__document_data_file, $document_data, 
       ) = helper_load_folder_for($DOCUMENTS_TYPE, $settings, $params, $document_id);
    if (performed_render()) {
        return;
    }

    # compute a profile for each document from the documents folder
    helper_tfidf_from_documents_folder($FOLDER_TYPE, $settings, $params, 
        $profiles_info, $profiles_data, $document_info, $document_data, $weights
    );
    if (performed_render()) {
        return;
    }

    my $profile_array = helper_save_things_data($profiles_data_file, $profiles_data);
    if (performed_render()) {
        return;
    }
        
    # save the profiles folder metadata
    helper_folders_put_info_file($profiles_info_file, $profiles_info);
    if (performed_render()) {
        return;
    }

    if ($full) {
        helper_profiles_addin_full($FOLDER_TYPE, $settings, $params, $profiles_info);
        if (performed_render()) {
            return;
        }
    }

    my $text = serialise({'folder' => $profiles_info});
    render({ 'text' => $text });
}


1;