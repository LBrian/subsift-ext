# matches_helper.pl
use strict;
use warnings;

use URI::Escape;

#require '_folders_helper.pl';
require 'profiles_helper.pl';

my $FALSE = 0;
my $TRUE  = 1;

my $MATCHES_TYPE  = 'matches';
my $PROFILES_TYPE = 'profiles';

my $TERM_FILE_EXTENSION = '.js';

sub similarity_matrix_filename { return 'sim.csv'; }
sub similarity_pairs_filename { return 'pair.csv'; }

sub helper_match_topic_profiles {
	#
    # Calculate a similarity score between the paired topics of a pair of profiles.
    # Stores the results in a simple (fast) custom serialisation of a hash.
    #
    my ($matches_name, $settings, $params, 
        $matches_info, $matches_data, 
        $profiles1_info, $profiles_data1, $profiles2_info, $profiles_data2
    ) = @_;


    my $timestamp           = $matches_info->{'modified'};

    # computational parameters
    my $limit               = $matches_info->{'limit'};
    my $threshold           = $matches_info->{'threshold'};

    # for speed, we directly access the storage layer (without using helper_[load|save]_file)
    my $matches_id = $params->{'folder_id'};
    my $matches_path = helper_folders_path($matches_name, $settings, $params, $matches_id);
    if (performed_render()) {
        return;
    }
    
    
    my $profiles_id1 = $matches_info->{'profiles_id1'};
    my $profiles_path1 = helper_folders_path($PROFILES_TYPE, $settings, $params, $profiles_id1);
    if (performed_render()) {
        return;
    }    
    my $profiles_id2 = $matches_info->{'profiles_id2'};
    my $profiles_path2 = helper_folders_path($PROFILES_TYPE, $settings, $params, $profiles_id2);
    if (performed_render()) {
        return;
    }
    
    for my $key (keys %$matches_data) {
        delete $matches_data->{$key};
    }

    # get canonically ordered arrays of profile data
    my $profiles_array1 = array_from_hash($profiles_data1);
    my $profiles_array2 = array_from_hash($profiles_data2);
    
    my $matches_uri_stem = $matches_info->{'uri'} . '/items/';
    
    # load topics for every item in profiles1 folder
#    my $log_2 = log(2.0);
    for my $profile_data (@$profiles_array1) {
        my $item_id = $profile_data->{'id'};
        my %topicsNmeans = ();
        my $terms = helper_load_topics_for($PROFILES_TYPE, $settings, $params, $profiles_id1, $item_id);
        while (my ($topic_id, $words) = each(%$terms)) {
        	my $sum = 0;
        	# $stats->[1] : weights
            # $stats->[2] : P(t)
        	while (my ($term, $stats) = each($words->[2])) {
        		$sum = $sum + $stats->[2];
        	}
        	# Mean value P(t) of each topic, i.e weights
        	$words->[3]= $sum / keys $words->[2];
        	$topicsNmeans{$topic_id} = $words;
        }
        $profile_data->{'topics'} = \%topicsNmeans;
        # save the new document statistics [NOTE: for speed, do not use helper_save_file]
        my $composite_id = $profiles_id1 . '-' . $item_id;
        my $terms_file = File::Spec->catfile($matches_path, $composite_id . $TERM_FILE_EXTENSION);
        util_writeFile($terms_file, JSON->new->canonical->pretty->encode(\%topicsNmeans));
        
         $matches_data->{$composite_id} = {
            'type'          => $MATCHES_TYPE,
            'profiles_id'   => $profiles_id1,
            'id'            => $composite_id,
            'description'   => $profile_data->{'description'},
            'document'      => $profile_data->{'document'},
            'document_n'    => $profile_data->{'document_n'},
            'source'        => $profile_data->{'source'},
            'created'       => $timestamp,
            'modified'      => $timestamp,
            'uri'           => $matches_uri_stem . $item_id,
        };
        
    }
    # load topics for every item in profiles2 folder
    for my $profile_data (@$profiles_array2) {
        my $item_id = $profile_data->{'id'};
        my %topicsNmeans = ();
        my $terms = helper_load_topics_for($PROFILES_TYPE, $settings, $params, $profiles_id2, $item_id);
        while (my ($topic_id, $words) = each(%$terms)) {
        	my $sum = 0;
        	# $stats->[1] : weights
            # $stats->[2] : P(t)
        	while (my ($term, $stats) = each($words->[2])) {
        		$sum = $sum + $stats->[2];
        	}
        	# Mean value P(t) of each topic, i.e weights
        	$words->[3]= $sum / keys $words->[2];
        	$topicsNmeans{$topic_id} = $words;
        }
        $profile_data->{'topics'} = \%topicsNmeans;
         # save the new document statistics [NOTE: for speed, do not use helper_save_file]
        my $composite_id = $profiles_id2 . '-' . $item_id;
        my $terms_file = File::Spec->catfile($matches_path, $composite_id . $TERM_FILE_EXTENSION);
        util_writeFile($terms_file, JSON->new->canonical->pretty->encode(\%topicsNmeans));
        
         $matches_data->{$composite_id} = {
            'type'          => $MATCHES_TYPE,
            'profiles_id'   => $profiles_id1,
            'id'            => $composite_id,
            'description'   => $profile_data->{'description'},
            'document'      => $profile_data->{'document'},
            'document_n'    => $profile_data->{'document_n'},
            'source'        => $profile_data->{'source'},
            'created'       => $timestamp,
            'modified'      => $timestamp,
            'uri'           => $matches_uri_stem . $item_id,
        };
    }
    
    #
    # Calculate pairwise topics Pearson product-moment correlation coefficient into Rxy matrix
    #
    my @rows = ();
    my %details = ();
    for my $profile1_data (@$profiles_array1) {  
             
        my $item1_id = $profile1_data->{'id'};
        my $terms1 = $profile1_data->{'topics'};
        
        my @row= ();      
        for my $profile2_data (@$profiles_array2) {
            
            my $item2_id = $profile2_data->{'id'};
            my $terms2 = $profile2_data->{'topics'};
                      
    		my $r = 0; 
    		my $xy_sum = 0;
    		my $x_pow_sum = 0;
    		my $y_pow_sum = 0;
    		my $x_mean = 0;
    		my $y_mean = 0;
    		my $cnt = 0;
    		my @PCCs= ();
    		my $max_pcc = 0;
    		my $pcc_sum = 0;
		    while (my ($x_topic_id, $x_words) = each(%$terms1)) {
#		    	$x_mean = $x_words->[3];
				$max_pcc = 0;
                while (my ($y_topic_id, $y_words) = each(%$terms2)) {
#                	$y_mean = $y_words->[3];
					$x_mean =0 ;
					$y_mean = 0;
					$cnt = 0;
                	$r = 0;
                	$xy_sum = 0;
                	$x_pow_sum = 0;
                	$y_pow_sum = 0;
                	my @x_weights=();
                	my @y_weights=();
                	# $stats->[1] : weights
                	# $stats->[2] : P(t)
                	while (my ($term, $stats) = each($x_words->[2])) {
                		if(exists $y_words->[2]->{$term}) {
           					$cnt++;
           					$x_mean += $stats->[2];
           					$y_mean += $y_words->[2]->{$term}->[2];
		        			push(@x_weights, $stats->[2]);
		        			push(@y_weights, $y_words->[2]->{$term}->[2]);
                		}
		        	}
		        	if($cnt > 1) {
			        	$x_mean = $x_mean/$cnt;
			        	$y_mean = $y_mean/$cnt;
#		        	while (my ($term, $stats) = each($y_words->[2])) {
#		        		push(@y_weights, $stats->[2]);
#		        	}
	                	for (my $x=0; $x<scalar(@x_weights); $x++) {
	                		$xy_sum += ($x_weights[$x] - $x_mean) * ($y_weights[$x] - $y_mean);
	                		$x_pow_sum += ($x_weights[$x] - $x_mean)**2;
	                		$y_pow_sum += ($y_weights[$x] - $y_mean)**2;
	                	}
	                	if($x_pow_sum > 0 and $y_pow_sum > 0) {
	                		$r = $xy_sum / sqrt($x_pow_sum) * sqrt($y_pow_sum);
		        		}
		        	}
					$PCCs[$x_topic_id][$y_topic_id] = $r;
					$max_pcc = ($r > $max_pcc) ? $r : $max_pcc;
                }
                $pcc_sum += $max_pcc;
		    }
		    $details{$item1_id}{$item2_id} = [ $pcc_sum, \@PCCs ];
		    push(@row, $pcc_sum);
        }
        push(@rows, \@row);
    }
    #
    # serialise the similarity matrix to a csv file
    #
    my @row_headings = map {$_->{'id'}} @$profiles_array1;
    my @column_headings = map {$_->{'id'}} @$profiles_array2;
    my @lines = ( '"Similarity","' . join('","', @column_headings) . '"', );
    foreach my $row_arrayref (@rows) {
    	push(@lines, '"' . shift(@row_headings) . '",' . join(',', @$row_arrayref));
    }
    my $sim_file = File::Spec->catfile($matches_path, similarity_matrix_filename());
    util_writeFile($sim_file, join("\n", @lines));  #no UTF-8 conversion needs (no wide characters in ids or numbers)
    
    #
    # serialise the details of each pairwise comparison grouped by item
    #
    # first: the items of profile1
    for my $profile1_data (@$profiles_array1) {        
        my $item1_id = $profile1_data->{'id'};
        my $composite_id = $profiles_id1 . '-' . $item1_id;
        my $item_file = File::Spec->catfile($matches_path, 'TERMS-' . $composite_id . $TERM_FILE_EXTENSION);
        util_writeFile($item_file, JSON->new->canonical->pretty->encode( $details{$item1_id} ));
    }
     if ($profiles_id1 ne $profiles_id2) {
        for my $profile2_data (@$profiles_array2) {
            my $item2_id = $profile2_data->{'id'};
            my $composite_id = $profiles_id2 . '-' . $item2_id;
            my %pivot_details = ();
            for my $profile1_data (@$profiles_array1) {        
                my $item1_id = $profile1_data->{'id'};
                $pivot_details{$item1_id} = $details{$item1_id}{$item2_id};
            }
            my $item_file = File::Spec->catfile($matches_path, 'TERMS-' . $composite_id . $TERM_FILE_EXTENSION);
            util_writeFile($item_file, JSON->new->canonical->pretty->encode( \%pivot_details ));
        }
    }
}

sub helper_match_profiles {
    #
    # Calculate a similarity score between the term vectors of a pair of profiles.
    # Stores the results in a simple (fast) custom serialisation of a hash.
    #
    my ($matches_name, $settings, $params, 
        $matches_info, $matches_data, 
        $profiles1_info, $profiles_data1, $profiles2_info, $profiles_data2
    ) = @_;


    my $timestamp           = $matches_info->{'modified'};

    # computational parameters
    my $limit               = $matches_info->{'limit'};
    my $threshold           = $matches_info->{'threshold'};

    # for speed, we directly access the storage layer (without using helper_[load|save]_file)
    my $matches_id = $params->{'folder_id'};
    my $matches_path = helper_folders_path($matches_name, $settings, $params, $matches_id);
    if (performed_render()) {
        return;
    }
    
    
    my $profiles_id1 = $matches_info->{'profiles_id1'};
    my $profiles_path1 = helper_folders_path($PROFILES_TYPE, $settings, $params, $profiles_id1);
    if (performed_render()) {
        return;
    }    
    my $profiles_id2 = $matches_info->{'profiles_id2'};
    my $profiles_path2 = helper_folders_path($PROFILES_TYPE, $settings, $params, $profiles_id2);
    if (performed_render()) {
        return;
    }    

    #
    # calculate combined (i.e. summed) corpus term statistics
    #

    # combined number of documents
    my $corpus_noofdocs = scalar(keys %$profiles_data1) + scalar(keys %$profiles_data2);

    # no. occurrences of term across all documents
    my $corpus_n = helper_load_terms_for($PROFILES_TYPE, $settings, $params, $profiles_id1, helper_document_n_file_id());
   
    if (performed_render()) {
        return;
    }
    {
        my $corpus_n2 = helper_load_terms_for($PROFILES_TYPE, $settings, $params, $profiles_id2, helper_document_n_file_id());
        if (performed_render()) {
            return;
        }
        helper_merge_term_hashes($corpus_n, $corpus_n2);
    }

    # no. documents in which term occurs
    my $corpus_dt = helper_load_terms_for($PROFILES_TYPE, $settings, $params, $profiles_id1, helper_document_dt_file_id());
    if (performed_render()) {
        return;
    }
    {
        my $corpus_dt2 = helper_load_terms_for($PROFILES_TYPE, $settings, $params, $profiles_id2, helper_document_dt_file_id());
        if (performed_render()) {
            return;
        }
        helper_merge_term_hashes($corpus_dt, $corpus_dt2);
    }

    #
    # load term counts for use in pairwise comparison of profiles
    #

    # start new metadata for folder data items
#FIXME: why do we do this? would be simpler to recreate from an empty hash!
    for my $key (keys %$matches_data) {
        delete $matches_data->{$key};
    }

    # get canonically ordered arrays of profile data
    my $profiles_array1 = array_from_hash($profiles_data1);
    my $profiles_array2 = array_from_hash($profiles_data2);
    
    my $matches_uri_stem = $matches_info->{'uri'} . '/items/';
    
    # load terms for every item in profiles1 folder
    my $log_2 = log(2.0);
    for my $profile_data (@$profiles_array1) {
        my $item_id = $profile_data->{'id'};
        my $terms = helper_load_terms_for($PROFILES_TYPE, $settings, $params, $profiles_id1, $item_id);
        # deserialise stats from string "n,tf,idf,tfidf,wg,wl,wtfidf" to 7-tuple (array)
        # and recompute idf and tfidf relative to combined corpus (n and tf do not change)
        my %terms_n_tf_idf_tfidf_wg_wl_wtfidf = ();
        my $norm = 0;
        my $noofterms = 0;
#        while (my ($term, $str) = each(%$terms)) {
        while (my ($term, $stats) = each(%$terms)) {
#            my @stats = split(',', $str);
#            $stats[2] = log( $corpus_noofdocs / $corpus_dt->{$term} ) / $log_2;
#            $stats[3] = $stats[1] * $stats[2];
#            $stats[6] = $stats[3] * $stats[4] * $stats[5];
#            $norm += $stats[6] * $stats[6];
#            $terms->{$term} = \@stats;
#            $terms_n_tf_idf_tfidf_wg_wl_wtfidf{$term} = join(',', @stats);
            $stats->[2] = log( $corpus_noofdocs / $corpus_dt->{$term} ) / $log_2;
            $stats->[3] = $stats->[1] * $stats->[2];
            $stats->[6] = $stats->[3] * $stats->[4] * $stats->[5];
            $norm += $stats->[6] * $stats->[6];
            $terms->{$term} = $stats;
            $terms_n_tf_idf_tfidf_wg_wl_wtfidf{$term} = $stats;
            $noofterms++;
        }

        # save the new document statistics [NOTE: for speed, do not use helper_save_file]
        my $composite_id = $profiles_id1 . '-' . $item_id;
        my $terms_file = File::Spec->catfile($matches_path, $composite_id . $TERM_FILE_EXTENSION);
#        util_writeFile($terms_file, join("\n", %terms_n_tf_idf_tfidf_wg_wl_wtfidf), 'UTF-8');
        util_writeFile($terms_file, JSON->new->canonical->pretty->encode(\%terms_n_tf_idf_tfidf_wg_wl_wtfidf));

#        $matches_data->{$item_id} = {
        $matches_data->{$composite_id} = {
            'type'          => $MATCHES_TYPE,
            'profiles_id'   => $profiles_id1,
            'id'            => $composite_id,
            'description'   => $profile_data->{'description'},
            'document'      => $profile_data->{'document'},
            'document_n'    => $profile_data->{'document_n'},
            'source'        => $profile_data->{'source'},
            'created'       => $timestamp,
            'modified'      => $timestamp,
            'uri'           => $matches_uri_stem . $item_id,
        };

        $profile_data->{'terms'} = $terms;
        $profile_data->{'norm'} = sqrt($norm);
        $profile_data->{'noofterms'} = $noofterms;
    }
    # load terms for every item in profiles2 folder
    for my $profile_data (@$profiles_array2) {
        my $item_id = $profile_data->{'id'};
        my $terms = helper_load_terms_for($PROFILES_TYPE, $settings, $params, $profiles_id2, $item_id);
        # deserialise stats from string "n,tf,idf,tfidf,wg,wl,wtfidf" to 7-tuple (array)
        # and recompute idf and tfidf relative to combined corpus (n and tf do not change)
        my %terms_n_tf_idf_tfidf_wg_wl_wtfidf = ();
        my $norm = 0;
        my $noofterms = 0;
#        while (my ($term, $str) = each(%$terms)) {
        while (my ($term, $stats) = each(%$terms)) {
#            my @stats = split(',', $str);
#            $stats[2] = log( $corpus_noofdocs / $corpus_dt->{$term} ) / $log_2;
#            $stats[3] = $stats[1] * $stats[2];
#            $stats[6] = $stats[3] * $stats[4] * $stats[5];
#            $norm += $stats[6] * $stats[6];
#            $terms->{$term} = \@stats;
#            $terms_n_tf_idf_tfidf_wg_wl_wtfidf{$term} = join(',', @stats);
            $stats->[2] = log( $corpus_noofdocs / $corpus_dt->{$term} ) / $log_2;
            $stats->[3] = $stats->[1] * $stats->[2];
            $stats->[6] = $stats->[3] * $stats->[4] * $stats->[5];
            $norm += $stats->[6] * $stats->[6];
            $terms->{$term} = $stats;
            $terms_n_tf_idf_tfidf_wg_wl_wtfidf{$term} = $stats;
            $noofterms++;
        }

        # save the new document statistics [NOTE: for speed, do not use helper_save_file]
        my $composite_id = $profiles_id2 . '-' . $item_id;
        my $terms_file = File::Spec->catfile($matches_path, $composite_id . $TERM_FILE_EXTENSION);
#        util_writeFile($terms_file, join("\n", %terms_n_tf_idf_tfidf_wg_wl_wtfidf), 'UTF-8');
        util_writeFile($terms_file, JSON->new->canonical->pretty->encode(\%terms_n_tf_idf_tfidf_wg_wl_wtfidf));

        $matches_data->{$composite_id} = {
            'type'          => $MATCHES_TYPE,
            'profiles_id'   => $profiles_id2,
            'id'            => $composite_id,
            'description'   => $profile_data->{'description'},
            'document'      => $profile_data->{'document'},
            'document_n'    => $profile_data->{'document_n'},
            'source'        => $profile_data->{'source'},
            'created'       => $timestamp,
            'modified'      => $timestamp,
            'uri'           => $matches_uri_stem . $item_id,
        };

        $profile_data->{'terms'} = $terms;
        $profile_data->{'norm'} = sqrt($norm);
        $profile_data->{'noofterms'} = $noofterms;
    }

    #
    # pairwise compare all term vectors from profiles1 and profiles2 folders
    #

    my @rows = ();
    my %details = ();
    for my $profile1_data (@$profiles_array1) {  
             
        my $item1_id = $profile1_data->{'id'};
        my $terms1 = $profile1_data->{'terms'};
        
        my @row = ();      
        for my $profile2_data (@$profiles_array2) {
            
            my $item2_id = $profile2_data->{'id'};
            my $terms2 = $profile2_data->{'terms'};
                      
            # compute dot product of term vectors (iterating over shortest key set)
            my $dotproduct = 0;
            my @shared_terms = ();
            if ($profile1_data->{'noofterms'} <= $profile2_data->{'noofterms'}) {
                while (my ($term, $stats) = each(%$terms1)) {
                    if (exists $terms2->{$term}) {
                        my $contribution = $stats->[6] * $terms2->{$term}[6];
                        # ignore terms with non-zero tf but zero tfidf (ie. ones which are significant in a single doc but which occur in all docs)
                        if ($contribution > 0) {
                            $dotproduct += $contribution;
                            push(@shared_terms, [$term, $contribution]);
                        }
                    }
                }
            }
            else {
                while (my ($term, $stats) = each(%$terms2)) {
                    if (exists $terms1->{$term}) {
                        my $contribution = $stats->[6] * $terms1->{$term}[6];
                        # ignore terms with non-zero tf but zero tfidf (ie. ones which are significant in a single doc but which occur in all docs)
                        if ($contribution > 0) {
                            $dotproduct += $contribution;
                            push(@shared_terms, [$term, $contribution]);
                        }
                    }
                }
            }
            my $denom = $profile1_data->{'norm'} * $profile2_data->{'norm'};
            my $cosine = ($denom) ? $dotproduct / $denom : 0;
            push(@row, $cosine);
            @shared_terms = sort { $b->[1] <=> $a->[1] } @shared_terms;
#            my @packed_shared_terms = ();
#            foreach my $array_ref (@shared_terms) {
#                push(@packed_shared_terms, $array_ref->[0] . ' ' . $array_ref->[1]);
#            }
#            # serialise the details of the pairwise comparisons for this row (e.g. for one person or for one paper)
#            $details{$item1_id}{$item2_id} = "$cosine,\"". join(',', @packed_shared_terms) . '"';
            # serialise the details of the pairwise comparisons for this row (e.g. for one person or for one paper)
            $details{$item1_id}{$item2_id} = [ $cosine, \@shared_terms ];
        }
        # build up the similarity matrix
        push(@rows, \@row);
    }

    #
    # serialise the similarity matrix to a csv file
    #
    my @row_headings = map {$_->{'id'}} @$profiles_array1;
    my @column_headings = map {$_->{'id'}} @$profiles_array2;
    my @lines = ( '"Similarity","' . join('","', @column_headings) . '"', );
    foreach my $row_arrayref (@rows) {
    	push(@lines, '"' . shift(@row_headings) . '",' . join(',', @$row_arrayref));
    }
    my $sim_file = File::Spec->catfile($matches_path, similarity_matrix_filename());
    util_writeFile($sim_file, join("\n", @lines));  #no UTF-8 conversion needs (no wide characters in ids or numbers)
    #
    # serialise the details of each pairwise comparison grouped by item
    #
    # first: the items of profile1
    for my $profile1_data (@$profiles_array1) {        
        my $item1_id = $profile1_data->{'id'};
        my $composite_id = $profiles_id1 . '-' . $item1_id;
#        my @lines = ();
#        for my $profile2_data (@$profiles_array2) {
#            my $item2_id = $profile2_data->{'id'};
#            push(@lines, "\"$item1_id\",\"$item2_id\"," . $details{$item1_id}{$item2_id});
#        }
        my $item_file = File::Spec->catfile($matches_path, 'TERMS-' . $composite_id . $TERM_FILE_EXTENSION);
#        util_writeFile($item_file, join("\n", @lines), 'UTF-8');
        util_writeFile($item_file, JSON->new->canonical->pretty->encode( $details{$item1_id} ));
    }
    # second: the items of profile2 (skip if this is a reflexive comparison)
    if ($profiles_id1 ne $profiles_id2) {
        for my $profile2_data (@$profiles_array2) {
            my $item2_id = $profile2_data->{'id'};
            my $composite_id = $profiles_id2 . '-' . $item2_id;
#            my @lines = ();
            my %pivot_details = ();
            for my $profile1_data (@$profiles_array1) {        
                my $item1_id = $profile1_data->{'id'};
#                push(@lines, "\"$item2_id\",\"$item1_id\"," . $details{$item1_id}{$item2_id});
                $pivot_details{$item1_id} = $details{$item1_id}{$item2_id};
            }
            my $item_file = File::Spec->catfile($matches_path, 'TERMS-' . $composite_id . $TERM_FILE_EXTENSION);
#            util_writeFile($item_file, join("\n", @lines), 'UTF-8');
            util_writeFile($item_file, JSON->new->canonical->pretty->encode( \%pivot_details ));
        }
    }
#    my $pairs_file = File::Spec->catfile($matches_path, similarity_pairs_filename());
#    util_writeFile($pairs_file, join("\n", @details));  #no UTF-8 conversion needed (due to string ops maybe?!)

=head
    
    # if only keep top $limit terms for each match, then we can discard 
    # terms that do not appear in the top $limit of any match
    my %corpus_include = ();

    # calculate tfidf vector for document
    my $noofdocs = scalar(@$profile_array);
    my $log_2 = log(2.0);
    for my $document_data (@$profile_array) {
        
        my $item_id = $document_data->{'id'};

#        my $document_n = $matches_data->{$item_id}{'document_n'};
        my $document_n = $matches_data->{$composite_id}{'document_n'};
#        my $term_n = $matches_data->{$item_id}{'term_n'};
        my $term_n = $matches_data->{$composite_id}{'term_n'};
        my @ranklist = ();
        while (my ($term, $n) = each(%$term_n)) {
            my $tf = $n / $document_n;
            my $idf = log( $noofdocs / $corpus_dt{$term} ) / $log_2;
            my $tfidf = $tf * $idf;
#            $term_n->{$term} = $n . ',' . $tf . ',' . $idf . ',' . $tfidf;
            push(@ranklist, [ $tfidf, $term, $n . ',' . $tf . ',' . $idf . ',' . $tfidf ]);
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

        # record which terms in the corpus appear in the top $limit terms of some matche
        foreach my $tuple (@ranklist) {
            $corpus_include{$tuple->[1]} = 1;
        }

        # save the document statistics [NOTE: for speed, do not use helper_save_file]
        my $file_id = util_getValidFileName($item_id);
        my $document_n_file = File::Spec->catfile($matches_path, $file_id . $TERM_FILE_EXTENSION);
#        util_writeFile($document_n_file, join("\n", %$term_n), 'UTF-8');
        util_writeFile($document_n_file, join("\n", %terms), 'UTF-8');
        
        # remove the term_n hash from the stored metadata [NOTE: to keep file size manageable]
#        delete $matches_data->{$item_id}{'term_n'};
        delete $matches_data->{$composite_id}{'term_n'};
    }
=cut

=head
    # filter out all terms which do not appear in the top $limit terms of any matches
    my %included_corpus_n = ();
    my %included_corpus_dt = ();
    foreach my $term (keys %corpus_include) {
        $included_corpus_n{$term} = $corpus_n{$term};
        $included_corpus_dt{$term} = $corpus_dt{$term};
    }
=cut

    # save the corpus statistics
    my $corpus_n_file = File::Spec->catfile($matches_path, helper_document_n_file_id() . $TERM_FILE_EXTENSION);
#    util_writeFile($corpus_n_file, join("\n", %$corpus_n), 'UTF-8');
    util_writeFile($corpus_n_file, JSON->new->canonical->pretty->encode($corpus_n));
    my $corpus_dt_file = File::Spec->catfile($matches_path, helper_document_dt_file_id() . $TERM_FILE_EXTENSION);
#    util_writeFile($corpus_dt_file, join("\n", %$corpus_dt), 'UTF-8');
    util_writeFile($corpus_dt_file, JSON->new->canonical->pretty->encode($corpus_dt));

=head
    # for compactness of info metadata we join corpus term stats into comma separated "n,dt" strings
    my %corpus_n_dt = ();
    while( my ($term, $n) = each(%$corpus_n) ) {
        $corpus_n_dt{$term} = $n . ',' . $corpus_dt->{$term};
    }
    $matches_info->{'terms_n_dt'} = \%corpus_n_dt;
=cut

}



sub helper_matches_addin_full {
    #
    # Augment $matches_info hash with extra data retrieved from associated external file
    #
#    my ($folder_type, $settings, $params, $matches_info) = @_;
    
    # matches corpus summary uses exactly the same serialisation as profiles uses
    return helper_profiles_addin_full(@_);
}


sub helper_merge_term_hashes {
    #
    #   void merge_term_hashes(HASHREF terms1, HASHREF terms2)
    #
    #   Merges terms2 into terms1, summing their values
    #
    my ($terms1, $terms2) = @_;
    while( my ($term, $value) = each(%$terms2) ) {
        if (!exists $terms1->{$term}) {
            $terms1->{$term} = $value;
        }
        else {
            $terms1->{$term} += $value;
        }
    }
}


sub helper_deserialise_sim {
    #
    # (STRING_ARRAYREF docids1, 
    #  STRING_ARRAYREF docids2,
    #  ARRAY_ARRAYREF_NUMBER_ARRAYREF sims,
    #  STRING_REF csv) deserialise_sim(STRING $sim_file)
    # 
    # Deserialise similarity matrix, returning docids1 (row headings),
    # docsids2 (column headings), similarity matrix, csv.
    #
    my ($sim_file) = @_;
    
    my $str = util_readFile($sim_file);
    # extract docids column/row headings and sim matrix body
    my @lines = split("\n", $str);
    my @docids1 = ();
    
    my $line = shift @lines;
    my @docids2 = ();
    pos $line = 0;
    while (pos $line < length $line) {
        if ($line =~ m{ \G \"([^\"]*)\",? }gcxms) {
            push(@docids2, $1);
        }
    }
    shift(@docids2); #scrap top left corner label (it is not a docid)

    # extract sim matrix and build @docids1 by stripping off column 0
    my @sims = ();
    foreach my $line (@lines) {
        my ($docid1, $data) = ($line =~ m{^\"([^\"]*)\",(.*)}xms);
        my @row = split(",", $data);
        push(@docids1, $docid1);
        push(@sims, \@row);
    }

    return (\@docids1, \@docids2, \@sims, \$str);
}


sub helper_load_sim {
    my ($folder_type, $folder_id_param_name, $settings, $params, $filename) = @_;

    my $folder_id = $params->{$folder_id_param_name};

    my $folder_path = helper_folders_path($folder_type, $settings, $params, $folder_id);
    if (performed_render()) {
        return;
    }

    my $sim_file = File::Spec->catfile($folder_path, $filename);
    if (!-f $sim_file) {
        render({
            'status' => '404 Not Found',
            'text'   => serialise_error_message("No similarity data"),
        });
        return;
    }

    return helper_deserialise_sim($sim_file);
}


sub helper_get_sim_vector {
    # retrieve either a row or column from similarity matrix return as a sorted list
    my ($matches_info, $profiles_id, $item_id, $settings, $params,
        $item_ids1, $item_ids2, $sims) = @_;

    # optional thresholds for partitioning up papers into bids based on scores
    my $DEFAULT_THRESHOLD = 1.0;
    my $threshold3 = $DEFAULT_THRESHOLD;
    my $threshold2 = $DEFAULT_THRESHOLD;
    my $threshold1 = $DEFAULT_THRESHOLD;
    # bids are only included if any thresholds were supplied
    my $include_bids = $FALSE;
    if (exists $params->{'threshold3'} && $params->{'threshold3'} > 0) {
        $threshold3 = $params->{'threshold3'};
        $threshold3 *= 1.0;
        $include_bids = $TRUE;
    }
    if (exists $params->{'threshold2'} && $params->{'threshold2'} > 0) {
        $threshold2 = $params->{'threshold2'};
        $threshold2 *= 1.0;
        $include_bids = $TRUE;
    }
    if (exists $params->{'threshold1'} && $params->{'threshold1'} > 0) {
        $threshold1 = $params->{'threshold1'};
        $threshold1 *= 1.0;
        $include_bids = $TRUE;
    }
    my $bid_by_rank = ($threshold1 > $DEFAULT_THRESHOLD) ? 1 : 0;
    if ($bid_by_rank) {
        # convert to cumulative thresholds
        $threshold3 += 0;
        $threshold2 += $threshold3;
        $threshold1 += $threshold2;
    }


    my $ids;
    my $scores;
    if ($profiles_id eq $matches_info->{'profiles_id1'}) {
        # retrieve a row from matrix
        for(my $i=0; $i<scalar(@$item_ids1); $i++) {
            if ($item_ids1->[$i] eq $item_id) {
                $ids = $item_ids2;
                $scores = $sims->[$i];
                last;
            }
        }
    }
    else {
        # retrieve a column from matrix
        for(my $i=0; $i<scalar(@$item_ids2); $i++) {
            if ($item_ids2->[$i] eq $item_id) {
                my @scores = ();
                $ids = $item_ids1;
                $scores = \@scores;
                for(my $j=0; $j<scalar(@$item_ids1); $j++) {
                    $scores[$j] = $sims->[$j][$i];
                }
                last;
            }
        }
    }
 
    # merge two arrays into a single array
    my @rank = ();
    for(my $i=0; $i<scalar(@$ids); $i++) {
        push(@rank, [ $ids->[$i], 0 + $scores->[$i] ]);
    }
    # rank array on similarity scores
    @rank = sort { $b->[1] <=> $a->[1] } @rank;
    # convert array to hash and add in other requested metadata
    for(my $i=0; $i<scalar(@rank); $i++) {

        $rank[$i] = {
            'id' => $rank[$i][0],
            'score' => $rank[$i][1],
        };

        if ($include_bids) {
            if ($bid_by_rank) {
                # assign bids based on rank positions (held in threshold variables)
                $rank[$i]->{'bid'} = assign_bid_rank($i, $threshold3, $threshold2, $threshold1);
            }
            else {
                # assign bids based on thresholding similarity scores
                $rank[$i]->{'bid'} = assign_bid_score($rank[$i]->{'score'}, $threshold3, $threshold2, $threshold1);
            }
        }

    }

    #FIXME: perhaps make this augmentation optional (parts of it already are)...
    # augment each item with full metadata
    my $full = $params->{'full'};
    if (1) {
        my $folder_id = (($profiles_id eq $matches_info->{'profiles_id1'}))
            ? $matches_info->{'profiles_id2'} 
            : $matches_info->{'profiles_id1'};
        my (
            $__profiles_info_file, $__profiles_info, 
            $__profiles_data_file, $profiles_data, 
           ) = helper_load_folder_for(
                $PROFILES_TYPE, 
                $settings, $params,
                $folder_id
               );
        if (performed_render()) {
            return;
        }
   
        my ($pairs_hashref, $csv_strref);
        if ($full) {
            my $matches_path = helper_folders_path($MATCHES_TYPE, $settings, $params, $matches_info->{'id'});
            if (performed_render()) {
                return;
            }
            ($pairs_hashref, $csv_strref) = helper_load_pairs_item(
                $matches_path, $profiles_id, $item_id,
                $settings, $params
            );
        }
        for(my $i=0; $i<scalar(@rank); $i++) {
            my $info = $profiles_data->{$rank[$i]->{'id'}};
            $rank[$i]->{'description'} = $info->{'description'};
            $rank[$i]->{'document'} = $info->{'document'};
            $rank[$i]->{'source'} = $info->{'source'};
            $rank[$i]->{'profile'} = $info->{'uri'};
            # augment with common terms and their contribution to similarity score
            if ($full) {
                $rank[$i]->{'term'} = $pairs_hashref->{ Encode::decode('UTF-8', $rank[$i]->{'id'}) };
            }
        }
    }
    return \@rank;
}


sub assign_bid_score {
    my ($score, $threshold3, $threshold2, $threshold1) = @_;
    return 3 if ($score > $threshold3);
    return 2 if ($score > $threshold2);
    return 1 if ($score > $threshold1);
    return 0;
}
sub assign_bid_rank {
    my ($rank, $threshold3, $threshold2, $threshold1) = @_;
    return 3 if ($rank < $threshold3);
    return 2 if ($rank < $threshold2);
    return 1 if ($rank < $threshold1);
    return 0;
}

sub helper_deserialise_topic_pairs {
	my ($pairs_file) = @_;
	my $details = JSON->new->decode( util_readFile($pairs_file) );
	my %pairs = ();
    for my $item_id (keys %$details) {
        my $topics= $details->{$item_id}[1];
        my @topics_list = ();
        my $topic_x = 0;
        for my $topic (@$topics) {
        	my $topic_y=0;
        	my $y_cnt=0;
        	my $max_pcc=0;
        	for my $pcc (@$topic) {
        		if($pcc > $max_pcc) {
        			$topic_y = $y_cnt;
        			$max_pcc = $pcc;
        		}
	            $y_cnt++;
        	}
        	push(@topics_list, {
	                'name' => 'topic' . $topic_x . '/topic' . $topic_y,
	                'contribution' => $max_pcc,
	            });
            $topic_x++;
        }
        $pairs{$item_id} = \@topics_list;
    }
    return (\%pairs, 'foobar');
}

sub helper_deserialise_pairs {
    #
    # (HASHREF pairs, STRING_REF csv) deserialise_sim(STRING $pairs_file)
    # 
    # Deserialise similarity pairs file, returning similarity pairs, csv.
    #
    my ($pairs_file) = @_;
    
#    my $str = util_readFile($pairs_file);
    my $details = JSON->new->decode( util_readFile($pairs_file) );
    
    # extract docids column/row headings and sim matrix body
#    my @lines = split("\n", $str);
#    my %pairs = ();
#    foreach my $line (@lines) {
#        my ($_id1, $id2, $_score, $packed_termslist) = ($line =~ /^\"([^\"]+)\",\"([^\"]+)\",([^,]+),\"([^\"]*)\"$/);
#        my @terms = split(/,/, $packed_termslist);
#        my @termlist = ();
#        for my $term (@terms) {
#            my ($term, $contribution) = ($term =~ /^(.+)\ (\S+)$/);
#            push(@termlist, {
#                    'name' => Encode::encode('UTF-8', $term),
#                    'contribution' => $contribution,
#            });
#        }
#        $pairs{$id2} = \@termlist;
    my %pairs = ();
    for my $item_id (keys %$details) {
        my $terms = $details->{$item_id}[1];
        my @termlist = ();
        for my $term (@$terms) {
            push(@termlist, {
                'name' => $term->[0],
                'contribution' => $term->[1],
            });
        }
        $pairs{$item_id} = \@termlist;
    }
#    return (\%pairs, \$str);
    return (\%pairs, 'foobar');
}


sub helper_load_pairs_item {
    my ($matches_path, $profiles_id, $item_id, $settings, $params) = @_;
    my $composite_id = $profiles_id . '-' . $item_id;
    my $item_file = File::Spec->catfile($matches_path, 'TERMS-' . $composite_id . $TERM_FILE_EXTENSION);
    if($params->{'topic'}) {
    	return helper_deserialise_topic_pairs($item_file);
    }else{
    	return helper_deserialise_pairs($item_file);
	}
}


#FIXME: this is now broken because it assumes a single csv file exists already but we now use a separate csv for each item
#       and so must load and concat all csv files of profile1 (or of profile2 for the pivoted version) to get the lot
sub helper_load_pairs_all {
    my ($folder_type, $settings, $params, $filename, $matches_info, $matches_data) = @_;

    my $folder_id = $params->{'folder_id'};

    my $folder_path = helper_folders_path($folder_type, $settings, $params, $folder_id);
    if (performed_render()) {
        return;
    }

=head
    my $pairs_file = File::Spec->catfile($folder_path, $filename);
    if (!-f $pairs_file) {
        render({
            'status' => '404 Not Found',
            'text'   => serialise_error_message("No similarity pairwise data"),
        });
        return;
    }
=cut

    my $profiles_id = $params->{'profiles_id'};     #note: will be '' if none supplied

    # if no specific profiles supplied, try both
    if ($profiles_id eq '') {
        $profiles_id = $matches_info->{'profiles_id1'};
    }

    # concatenate pair csv data from either profiles1 or profiles2 items
    my $matches_array = array_from_hash($matches_data);
    my $str = '';
    for my $match_data (@$matches_array) {
        if ($match_data->{'profiles_id'} eq $profiles_id) {
            my $item_id = $match_data->{'id'};
            my $item_file = File::Spec->catfile($folder_path, 'TERMS-' . $item_id . $TERM_FILE_EXTENSION);
            $str .= util_readFile($item_file) . "\n";
        }
    }
    my %pairs = ();
    return (\%pairs, \$str);
#    return helper_deserialise_pairs($pairs_file);
}


1;