# reports_helper.pl
use strict;
use warnings;
use Data::Dumper;

use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
 
require '_folders_helper.pl';
require 'profiles_helper.pl';
require 'matches_helper.pl';

my $FALSE = 0;
my $TRUE  = 1;

my $DOCUMENTS_TYPE = 'documents';
my $PROFILES_TYPE  = 'profiles';
my $MATCHES_TYPE   = 'matches';

my $HTML_FILE_EXTENSION = '.html';

# Author: Brian Liu
sub helper_topic_reports_profiles {
    my ($folder_type, $settings, $params,
        $info,
        $profiles_info, $profiles_data) = @_;

    my $user_id = $params->{'user_id'};
    my $format = $params->{'format'};
    my $folder_id = $params->{'folder_id'};

    my $folder_path = helper_folders_path($folder_type, $settings, $params, $folder_id);
    if (performed_render()) {
        return;
    }

    my $profile_array = array_from_hash($profiles_data);

        for my $item_data (@$profile_array) {
            my $terms = helper_load_topics_for($PROFILES_TYPE, $settings, $params, $profiles_info->{'id'}, $item_data->{'id'});
            if (performed_render()) {
                return;
            }
            $item_data->{'term'} = helper_unpack_topics($params, $terms);
        }
        
    my $template_cache_path = File::Spec->catdir($settings->{'CACHE_PATH'}, 'tcc');
    for my $profile (@$profile_array) {
        my $item_id = $profile->{'id'};
        my $filename = util_getValidFileName($item_id) . $HTML_FILE_EXTENSION;
        $profile->{'filename'} = $filename;
        $profile->{'url'} = $settings->{'SITE_URL'} . '/' . $user_id . '/' . $folder_type . '/' . $info->{'id'} . '/' . $filename;
    }
    for my $profile (@$profile_array) {
        my $filepath = File::Spec->catfile($folder_path, $profile->{'filename'});
        util_writeFile($filepath,
            render({
                'COMPILE_EXT' => '.ttc',
                'COMPILE_DIR' => $template_cache_path,
                'to_string' => $TRUE,
                'locals'    => {
                    'report'        => $info, 
                    'profiles'      => $profiles_info, 
                    'profile'       => $profile,
                },
                'template'  => '_reports/profiles_topic_detail.phtml',
                'layout' => 'report',
            })
        );
    }

    my $item_id = 'index';
    my $filename = util_getValidFileName($item_id) . $HTML_FILE_EXTENSION;
    my $filepath = File::Spec->catfile($folder_path, $filename);
    util_writeFile($filepath,
        render({
            'COMPILE_EXT' => '.ttc',
            'COMPILE_DIR' => $template_cache_path,
            'to_string' => $TRUE,
            'locals'    => {
                'report'        => $info, 
                'profiles'      => $profiles_info, 
                'profile_items' => $profile_array,
            },
            'template'  => '_reports/profiles_index.phtml',
            'layout' => 'report',
        })
    );

    _create_zip($folder_path, $profiles_info->{'id'});
}

sub helper_reports_profiles {
    my ($folder_type, $settings, $params,
        $info,
        $profiles_info, $profiles_data) = @_;

    my $user_id = $params->{'user_id'};
    my $format = $params->{'format'};
    my $folder_id = $params->{'folder_id'};

    my $folder_path = helper_folders_path($folder_type, $settings, $params, $folder_id);
    if (performed_render()) {
        return;
    }

    my $profile_array = array_from_hash($profiles_data);

##was a pointless loop!
##    for my $profile (@$profile_array) {
        # augment with extra data retrieved from associated external file
        for my $item_data (@$profile_array) {
            my $terms = helper_load_terms_for($PROFILES_TYPE, $settings, $params, $profiles_info->{'id'}, $item_data->{'id'});
            if (performed_render()) {
                return;
            }

            $item_data->{'term'} = helper_unpack_terms($params, $terms);
        }
##    }

    my $template_cache_path = File::Spec->catdir($settings->{'CACHE_PATH'}, 'tcc');
    for my $profile (@$profile_array) {
        my $item_id = $profile->{'id'};
        my $filename = util_getValidFileName($item_id) . $HTML_FILE_EXTENSION;
        $profile->{'filename'} = $filename;
        $profile->{'url'} = $settings->{'SITE_URL'} . '/' . $user_id . '/' . $folder_type . '/' . $info->{'id'} . '/' . $filename;
    }
    for my $profile (@$profile_array) {
        my $filepath = File::Spec->catfile($folder_path, $profile->{'filename'});
        util_writeFile($filepath,
            render({
                'COMPILE_EXT' => '.ttc',
                'COMPILE_DIR' => $template_cache_path,
                'to_string' => $TRUE,
                'locals'    => {
                    'report'        => $info, 
                    'profiles'      => $profiles_info, 
                    'profile'       => $profile,
                },
                'template'  => '_reports/profiles_detail.phtml',
                'layout' => 'report',
            })
        );
    }

    my $item_id = 'index';
    my $filename = util_getValidFileName($item_id) . $HTML_FILE_EXTENSION;
    my $filepath = File::Spec->catfile($folder_path, $filename);
    util_writeFile($filepath,
        render({
            'COMPILE_EXT' => '.ttc',
            'COMPILE_DIR' => $template_cache_path,
            'to_string' => $TRUE,
            'locals'    => {
                'report'        => $info, 
                'profiles'      => $profiles_info, 
                'profile_items' => $profile_array,
            },
            'template'  => '_reports/profiles_index.phtml',
            'layout' => 'report',
        })
    );

    _create_zip($folder_path, $profiles_info->{'id'});
}


sub helper_reports_matches_html {
    my ($folder_type, $settings, $params,
        $info,
        $matches_info, $matches_data) = @_;

    my $user_id = $params->{'user_id'};
    my $format = $params->{'format'};
    my $folder_id = $params->{'folder_id'};

    my $folder_path = helper_folders_path($folder_type, $settings, $params, $folder_id);
    if (performed_render()) {
        return;
    }

    my $match_array = array_from_hash($matches_data);

##was a pointless loop!
##    for my $match (@$match_array) {
        # augment with extra data retrieved from associated external file
        for my $item_data (@$match_array) {
            my $terms = helper_load_terms_for($MATCHES_TYPE, $settings, $params, $matches_info->{'id'}, $item_data->{'id'});
            if (performed_render()) {
                return;
            }
            $item_data->{'term'} = helper_unpack_terms($params, $terms);
        }
##    }

    # load similarity matrix
    my ($item_ids1, $item_ids2, $sims, $all) = helper_load_sim(
        $MATCHES_TYPE, 'matches_id', $settings, $params, 
        similarity_matrix_filename()
    );
    if (performed_render()) {
        return;
    }            
    # augment metadata with list of items ranked by similarity score
    for my $item_data (@$match_array) {
        my ($profiles_id, $item_id) = ($item_data->{'id'} =~ m/^([^-]+)-(.*)$/gxsm);
        $params->{'full'} = $TRUE;
        $item_data->{'item'} = helper_get_sim_vector(
            $matches_info, $profiles_id, $item_id, $settings, $params,
            $item_ids1, $item_ids2, $sims
        );
        if (performed_render()) {
            return;
        }
    }

    my $template_cache_path = File::Spec->catdir($settings->{'CACHE_PATH'}, 'tcc');

    for my $match (@$match_array) {
        my ($profiles_id, $item_id) = ($match->{'id'} =~ m/^([^-]+)-(.*)$/gxsm);
        $match->{'profiles_id'} = $profiles_id;
        my $filename = util_getValidFileName($match->{'id'}) . $HTML_FILE_EXTENSION;
        $match->{'filename'} = $filename;
        $match->{'url'} = $settings->{'SITE_URL'} . '/' . $user_id . '/' . $folder_type . '/' . $info->{'id'} . '/' . $filename;
    }
    for my $match (@$match_array) {
        my $filepath = File::Spec->catfile($folder_path, $match->{'filename'});
        util_writeFile($filepath,
            render({
                'COMPILE_EXT' => '.ttc',
                'COMPILE_DIR' => $template_cache_path,
                'to_string' => $TRUE,
                'locals'    => {
                    'report'    => $info, 
                    'matches'   => $matches_info, 
                    'match'     => $match,
                },
                'template'  => '_reports/matches_detail.phtml',
                'layout' => 'report',
            })
        );       
    }

    my $item_id = 'index';
    my $filename = util_getValidFileName($item_id) . $HTML_FILE_EXTENSION;
    my $filepath = File::Spec->catfile($folder_path, $filename);
    util_writeFile($filepath,
        render({
            'COMPILE_EXT' => '.ttc',
            'COMPILE_DIR' => $template_cache_path,
            'to_string' => $TRUE,
            'locals'    => {
                
                'report'        => $info, 
                'matches'       => $matches_info, 
                'match_items'   => $match_array,
            },
            'template'  => '_reports/matches_index.phtml',
            'layout' => 'report',
        })
    );

    _create_zip($folder_path, $matches_info->{'id'});
}


sub helper_reports_matches_graphviz {
    my ($folder_type, $settings, $params,
        $info,
        $matches_info, $matches_data) = @_;

    my $user_id = $params->{'user_id'};
    my $format = $params->{'format'};
    my $folder_id = $params->{'folder_id'};
    my $strength = 0.0 + $params->{'strength'};   # [1..100, default=95]

    my $folder_path = helper_folders_path($folder_type, $settings, $params, $folder_id);
    if (performed_render()) {
        return;
    }

    my $match_array = array_from_hash($matches_data);

    # load similarity matrix
    my ($item_ids1, $item_ids2, $sims, $all) = helper_load_sim(
        $MATCHES_TYPE, 'matches_id', $settings, $params, 
        similarity_matrix_filename()
    );
    if (performed_render()) {
        return;
    }            

    my $reflexive = ($matches_info->{'profiles_id1'} eq $matches_info->{'profiles_id2'}) ? $TRUE : $FALSE;

    # first pass over data to establish top N% scores
    
    my @scores =();
    for my $item_data (@$match_array) {
        my ($profiles_id, $item_id) = ($item_data->{'id'} =~ m/^([^-]+)-(.*)$/gxsm);
        $item_data->{'item'} = helper_get_sim_vector(
            $matches_info, $profiles_id, $item_id, $settings, $params,
            $item_ids1, $item_ids2, $sims
        );
        if (performed_render()) {
            return;
        }
        for my $item (@{$item_data->{'item'}}) {
            push(@scores, 0+$item->{'score'});
        }
    }
    # sort descending
    @scores = sort { $b <=> $a } @scores;
    my $noofscores = scalar @scores;
    my $sum_size = ($reflexive) 
        ? scalar(@$item_ids1) + scalar(@$item_ids1) 
        : scalar(@$item_ids1) + scalar(@$item_ids2);
    my $maxlinks = sqrt($noofscores); 
    if ($maxlinks < 50) { $maxlinks = 50; }
    my $topn = int(sqrt($sum_size) + ($maxlinks * (100 - $strength)/$maxlinks));
    my $noofreflexives = ($reflexive) ? scalar(@$item_ids1) : 0;
    $topn += $noofreflexives;
    if ($topn >= $noofscores) {
        $topn = $noofscores - 1;
    }
    # use the topn-th value as the minimum score threshold
    my $threshold = $scores[$topn];
    
    # assign rank to each score
    @scores = @scores[0..$topn];
    my @ranks = ();
    my %rank = ();
    my $r = 1;
    for (my $i=0; $i < scalar(@scores); $i++) {
        $ranks[$i] = $r;
        $rank{$scores[$i]} = $r;
        # increment rank iff next value is less than current one (i.e. allow ties)
        if (($i+1) < scalar(@scores) && $scores[$i] > $scores[$i+1]) {
            $r++;
        }
    }
    # create a mapping from score to inverse rank
    my %inverse_rank = ();
    $r++;
    for (my $i=0; $i < scalar(@scores); $i++) {
        $inverse_rank{$scores[$i]} = $r - $ranks[$i];
    }

    # augment metadata with list of items ranked by similarity score
    my %pairs = ();
    my %required_item = ();
    for my $item_data (@$match_array) {
        # process one person

        my ($profiles_id, $item_id) = ($item_data->{'id'} =~ m/^([^-]+)-(.*)$/gxsm);

        $params->{'full'} = 1;  #force inclusion of term contributions
        $item_data->{'item'} = helper_get_sim_vector(
            $matches_info, $profiles_id, $item_id, $settings, $params,
            $item_ids1, $item_ids2, $sims
        );
        if (performed_render()) {
            return;
        }
   
        # augment $item with profile term data retrieved from associated external file
        my $terms = helper_load_terms_for($MATCHES_TYPE, $settings, $params, $matches_info->{'id'}, $item_data->{'id'});
        if (performed_render()) {
            return;
        }
        $item_data->{'term'} = helper_unpack_terms($params, $terms);

        # construct a tooltip listing the first few terms of person's profile
        my @terms = ();
        for my $term (@{$item_data->{'term'}}) {
            push(@terms, $term->{'name'});
            if (scalar @terms >= 3) {
                push(@terms, '...');
                last;
            }
        }
        $item_data->{'terms'} = join(", ", @terms);

        # create arcs for each pair above similarity threshold
        my @items = ();
        LP_THRESHOLD:
        for my $item (@{$item_data->{'item'}}) {
            if ((0+$item->{'score'}) < $threshold) {
                last LP_THRESHOLD;
            }
            
            # avoid tiny similarities relying on exponents (avoids dot file syntax errors)
            if (index($item->{'score'}, 'e') >= 0) {
                last LP_THRESHOLD;
            }
 
            # construct a tooltip listing the first few contributing terms
            my @terms = ();
            for my $term (@{$item->{'term'}}) {
                push(@terms, $term->{'name'});
                if (scalar @terms >= 3) {
                    push(@terms, '...');
                    last;
                }
            }
            $item->{'terms'} = Encode::decode('UTF-8', join(", ", @terms));
            
            # add in the inverse rank (for use as a weight in diagram)
            $item->{'rank'} = $rank{$item->{'score'}};
            $item->{'inverse_rank'} = $inverse_rank{$item->{'score'}};
            
            if ($reflexive) {
                # suppress reverse link if already added from other direction
                my $key = ($item_id lt $item->{'id'})
                          ?  ($item_id . ':' . $item->{'id'})
                          :  ($item->{'id'} . ':' . $item_id);
                if (!defined $pairs{$key}) {
                    # first link between this pair, so keep it
                    $pairs{$key} = $TRUE;
                    push(@items, $item);
                }
                else {
                    # reverse link between pair, so don't output (but do ensure both nodes are kept)
                    $required_item{$profiles_id . '-' . $item_id} = $TRUE;
                    $required_item{$profiles_id . '-' . $item->{'id'}} = $TRUE;
                }
            }
            else {
                push(@items, $item);
            }
        }
        $item_data->{'item'} = \@items;

    }

    # throw away unconnected nodes (ignoring reflexive score=1 match for same folder comparisons)
    my $minlen = ($reflexive) ? 1 : 0;
    my @reduced_array = ();
    my @noitems = ();
    for my $item_data (@$match_array) {
        if (scalar(@{$item_data->{'item'}}) > $minlen) {
            push(@reduced_array, $item_data);
        }
        else {
            # in reflexive case, let linked-to nodes through but remove their links
            if ($reflexive && defined $required_item{$item_data->{'id'}}) {
                push(@reduced_array, $item_data);
            }
        }
    }
    $match_array = \@reduced_array;

    # add in data required by presentation layer
    for my $match (@$match_array) {
        my ($profiles_id, $item_id) = ($match->{'id'} =~ m/^([^-]+)-(.*)$/gxsm);
        $match->{'profiles_id'} = $profiles_id;
        $match->{'id'} = $item_id;
        my $filename = util_getValidFileName($match->{'id'}) . $HTML_FILE_EXTENSION;
        $match->{'filename'} = $filename;
        $match->{'url'} = $settings->{'SITE_URL'} . '/' . $user_id . '/' . $folder_type . '/' . $info->{'id'} . '/' . $filename;
    }

    my $template_cache_path = File::Spec->catdir($settings->{'CACHE_PATH'}, 'tcc');

    my $item_id = $matches_info->{'id'};
    my $filename = util_getValidFileName($item_id) . '.dot';
    my $filepath = File::Spec->catfile($folder_path, $filename);
    util_writeFile($filepath,
        render({
            'COMPILE_EXT' => '.ttc',
            'COMPILE_DIR' => $template_cache_path,
            'to_string' => $TRUE,
            'locals'    => {
                'report'        => $info,
                'matches'       => $matches_info, 
                'match_items'   => $match_array,
                'interactive'   => undef,
                'folder_id'     => $folder_id,
            },
            'template'  => '_reports/matches_graphviz.pdot',
            'layout' => undef,
        })
    );
    my $filename2 = util_getValidFileName($item_id) . '_interactive.dot';
    my $filepath2 = File::Spec->catfile($folder_path, $filename2);
    util_writeFile($filepath2,
        render({
            'COMPILE_EXT' => '.ttc',
            'COMPILE_DIR' => $template_cache_path,
            'to_string' => $TRUE,
            'locals'    => {
                'report'        => $info,
                'matches'       => $matches_info, 
                'match_items'   => $match_array,
                'interactive'   => $TRUE,
                'folder_id'     => $folder_id,
            },
            'template'  => '_reports/matches_graphviz.pdot',
            'layout' => undef,
        })
    );
    
    # generate graph images using Graphviz
    my $outfile_stem = File::Spec->catfile($folder_path, util_getValidFileName($item_id));
    my $dot_path = File::Spec->catfile($settings->{'GRAPHVIZ_PATH'}, 'dot');
#    my $status = system("$dot_path -Tpng -Ksfdp -o \"${outfile_stem}.png\" \"$filepath\"");
#    $status = system("$dot_path -Tpdf -Ksfdp -o \"${outfile_stem}.pdf\" \"$filepath\"");
#    $status = system("$dot_path -Tjpg -Ksfdp -o \"${outfile_stem}.jpg\" \"$filepath\"");
#    $status = system("$dot_path -Tsvg -Ksfdp -o \"${outfile_stem}.svg\" \"$filepath2\"");
    my $status = system("$dot_path -Tpng -Kfdp -o \"${outfile_stem}.png\" \"$filepath\"");
    $status = system("$dot_path -Tpdf -Kfdp -o \"${outfile_stem}.pdf\" \"$filepath\"");
    $status = system("$dot_path -Tjpg -Kfdp -o \"${outfile_stem}.jpg\" \"$filepath\"");
    $status = system("$dot_path -Tsvg -Kfdp -o \"${outfile_stem}.svg\" \"$filepath2\"");

    $item_id = 'index';
    $filename = util_getValidFileName($item_id) . $HTML_FILE_EXTENSION;
    $filepath = File::Spec->catfile($folder_path, $filename);
    util_writeFile($filepath,
        render({
            'COMPILE_EXT' => '.ttc',
            'COMPILE_DIR' => $template_cache_path,
            'to_string' => $TRUE,
            'locals'    => {
                'report'        => $info, 
                'matches'       => $matches_info, 
                'match_items'   => $match_array,
                'folder_id'     => $folder_id,
            },
            'template'  => '_reports/matches_graphviz.phtml',
            'layout' => 'report',
        })
    );

    _create_zip($folder_path, $matches_info->{'id'});
}


sub _create_zip {
    my ($zip_path, $dest_path) = @_;
    my $zip = Archive::Zip->new();
    # add all files in reports folder apart from those beginning with underscore (e.g. _info.js)
    $zip->addTree($zip_path, util_getValidFileName($dest_path), sub { m{[\\/][^_\.][^\\/]*\.[A-Za-z0-9]+$} });
    my $zip_file = File::Spec->catfile($zip_path, 'index.zip');
    unless ( $zip->writeToFileNamed($zip_file) == AZ_OK ) {
        die "zip write error: $zip_file";
    }
}


1;