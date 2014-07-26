# documents_helper.pl
use strict;
use warnings;

require JSON::Path;

require 'csv.pl';

require '_items_helper.pl';
require '_items_index_helper.pl';
require 'fn_helper.pl';

my $FALSE = 0;
my $TRUE  = 1;

my $TRANSFORM_MANIFEST_FILE = '_transform.js';


##use vars qw(%hash);

sub helper_import_bookmarks {
    #
    # Queue a list of bookmark urls for fetching into this document.
    # This simply requires copying the bookmarks data file into the document's folder
    # where it will be discovered and processed automatically by harvest.pl (on cron)
    #
    my ($folder_type, $settings, $params, $bookmarks_id, $bookmarks_data) = @_;
    
    my $folder_path = helper_folders_path($folder_type, $settings, $params);
    if (performed_render()) {
        return;
    }
    
    # construct harvest manifest
    my $bookmarks_array = array_from_hash($bookmarks_data);
    for my $item (@$bookmarks_array) {
        my @queue = ( $item->{'url'}, );
        my @child = ();
        my @history = ();
        $item->{'queue'}   = \@queue,
        $item->{'child'}   = \@child,
        $item->{'history'} = \@history,
    }
    my %harvest_manifest = (
        'breadth' => 0 + $params->{'breadth'},
        'depth' => 0 + $params->{'depth'},
        'same_domain' => 0 + $params->{'same_domain'},
        'same_stem' => 0 + $params->{'same_stem'},
        'threshold' => 0 + $params->{'threshold'},
        'remove_html' => 0 + $params->{'remove_html'},
        'current_depth' => 0,
        'bookmark' => $bookmarks_array,
    );

    my $harvest_file = File::Spec->catfile($folder_path, '__' . $bookmarks_id . '.js' );
    helper_folders_put_info_file($harvest_file, \%harvest_manifest);

}


sub helper_importing_bookmarks {
    #
    # Tests whether the bookmarks data file is still in the document's folder.
    # This is a reliable way of testing whether harvester.pl (on cron) is still processing
    # the bookmark items in that file. Once completed the harvester.pl deletes the file.
    #
    # Returns $TRUE if still importing; $FALSE otherwise.
    #
    my ($folder_type, $settings, $params, $bookmarks_id, $bookmarks_data) = @_;
    
    my $folder_path = helper_folders_path($folder_type, $settings, $params);
    if (performed_render()) {
        return($FALSE);
    }
    
    my $harvest_file = File::Spec->catfile($folder_path, '__' . $bookmarks_id . '.js' );
    return (-e $harvest_file);
}


sub helper_parse_items_list {
    #
    #   ARRAYREF helper_parse_items_list(STRING $items_list)
    #
    #   Parse string of text lines where each line is one of the formats:
    #       text
    #       id, text
    #       id, description, text
    #
    #   Returns an array of [id, description, text] arrays. If description or id are missing then
    #   unique ids (and/or descriptions) are generated automatically.
    #
    my ($items_list) = @_;

    my @items_list = ();
    if (!defined $items_list) {
        return \@items_list;
    }

    my $err;
    eval{
        @items_list = @{csv_parse_string($items_list)};
    };
    if ($@) {
        $err = $@;
    } elsif ($!) {
        $err = $!;
    }
    if (defined $err && $err ne 'No such file or directory') {      #FIXME: HACK WORKAROUND because 'open'ing from a string gives this error in csv_parse_string
        warn_message('csv parse error: ' . $err);
        render({
            'status' => '400 Bad Request',
            'text'   => serialise_error_message('Invalid items_list'),
        });
        return \@items_list;
    }

    my %used_names = ();
    my $i = 0;
    foreach my $item (@items_list) {
        $i++;
        # accept one, two or three fields per line
        my $n = scalar(@$item);
        if ($n > 3) {
            # collapse text of rightmost fields to a single text field
            $item->[2] = join(', ', @$item[2..(scalar(@$item)-1)]);
            # truncate to first three fields
            @$item = @$item[0..2];
        }
        elsif ($n == 2) {
            # treat first field as both id and description shifting the text to third
            $item->[2] = $item->[1];
            $item->[1] = $item->[0];
        }
        elsif ($n == 1) {
            # treat single field as the text and invent a unique id, description
            $item->[2] = $item->[0];
            $item->[1] = "item$i";
            $item->[0] = $item->[1];
        }
        if (!(defined $item->[0] && $item->[0] ne '' &&
              defined $item->[1] && $item->[1] ne '' &&
              defined $item->[2] && $item->[2] ne '')
           ) {
            render({
                'status' => '400 Bad Request',
                'text'   => serialise_error_message("Invalid items_list at line $i"),
            });
            return;
        }

        # map id string to an acceptable valid id
        $item->[0] = util_getValidFileName($item->[0]);
        
        if (exists $used_names{$item->[0]}) {
            render({
                'status' => '400 Bad Request',
                'text'   => serialise_error_message("Invalid items_list, id '$item->[0]' is not unique at line $i"),
            });
            return;
        }
        $used_names{$item->[0]} = $TRUE;
    }

    return \@items_list;
}

############################################################################################


sub helper_create_transform_task {
    #
    #   create manifest listing folders (and their items) to transform
    #
    my ($folder_type, $settings, $params) = @_;

    my $folder_info = helper_folders_get_info($folder_type, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $folder_path = helper_folders_path($folder_type, $settings, $params);
    if (performed_render()) {
        return;
    }

    # construct transform manifest
    my $transform_manifest = {
        'transformation' => '',
    };


    # get the length of each argument folder
    my @argument_size = ();
    my @argument_index = ();
    for my $argument_folder_id (@{$folder_info->{'document_ids'}}) {
        my $argument_path = helper_folders_path($folder_type, $settings, $params, $argument_folder_id);
        if (performed_render()) {
            return;
        }
        my $size = helper_items_index_size($argument_path);
        push(@argument_size, $size);
        push(@argument_index, 0);
        if ($folder_info->{'generator'} eq 'map') {
            # all arguments must have same number of items
            if ($size != $argument_size[0]) {
                render({
                    'status' => '400 Bad Request',
                    'text'   => serialise_error_message("Document folders must have the same number of items."),
                });
                return;
            }
        }
    }
    $transform_manifest->{'size'} = \@argument_size;
    $transform_manifest->{'index'} = ($folder_info->{'generator'} eq 'map') ? [0] : \@argument_index;

    # save manifest into the results folder
    my $transform_file = File::Spec->catfile($folder_path, $TRANSFORM_MANIFEST_FILE);
    util_writeFile($transform_file, JSON->new->canonical->pretty->encode($transform_manifest) );   

}


sub helper_transform_next {
    #
    #   helper_transform_next($folder_type, $settings, $params[, $folder_info])
    #
    #   Incrementally copy-transform items from source to destination folder
    #

    my ($folder_type, $settings, $params, $folder_info) = @_;

    my $start_time = time;

    # only enact for a maximum of N seconds (because running via cron)
    ##FIXME: move out to config so can adjust on per platform basis to suit cron interval
    my $TRANSFORM_TIMEOUT = 10;

    # get the metadata of the results folder
    if (!defined $folder_info) {
        $folder_info = helper_folders_get_info($folder_type, $settings, $params);
        if (performed_render()) {
            return;
        }
    }

    my $folder_path = helper_folders_path($folder_type, $settings, $params);
    if (performed_render()) {
        return;
    }

    my $transform_file = File::Spec->catfile($folder_path, $TRANSFORM_MANIFEST_FILE);
    my $transform_manifest = JSON->new->decode( util_readFile($transform_file) );

    my @argument_folders_info = ();
    my @argument_folders_path = ();
    for my $argument_folder_id (@{$folder_info->{'document_ids'}}) {

        my $argument_folder_info = helper_folders_get_info($folder_type, $settings, $params, $argument_folder_id);
        if (performed_render()) {
            return;
        }
        push(@argument_folders_info, $argument_folder_info);

        my $argument_folder_path = helper_folders_path($folder_type, $settings, $params, $argument_folder_id);
        if (performed_render()) {
            return;
        }
        push(@argument_folders_path, $argument_folder_path);
    }

    my $size = $transform_manifest->{'size'};

    my $timestamp = $folder_info->{'created'};

=head declarative kernels

    -- this is a comment
    data Class = East | West ;

    --eastbound :: Train -> Bool ;

    type Individual = Car -> Bool with modifier gaussian 0.1 ;
    type Car = (Shape, Length, NumWheels, Kind, Roof, Load) ;
    data Shape = Rectangular | DoubleRectangular | UShaped | BucketShaped | Hexagonal | Ellipsoidal ;
    data Length = Long | Short ;
    type NumWheels = Int with kernel discreteKernel ;
    data Kind = Closed | Open ;
    data Roof = Flat | Jagged | Peaked | Curved | None with kernel roofK ;
    type Load = (Object, NumObjects) ;
    data Object = Circle | Hexagon | Square | Rectangle | LongRectangle | Triangle | UTriangle | Diamond | Null ;
    type NumObjects = Int ;

=cut

    my $prototypes1 = <<'__';
/*
 * text -> pre-profile
 *
 */
{
    "folder":
        {
            "corpus_n": {}, //bag of term=>n pairs where n is term count in this corpus
            "corpus_dt": {}, //bag of term=>n pairs where n is no. documents in which term occurs
            "corpus_N": "$.arguments_size.[0]"  //no. documents in corpus
        },
    "item":
        ["sift:Bag",
            ["text", ["sift:concat", "$.items.text"]], //"items" allows text for same item_id from multiple document folders to be merged (although normally just use one folder)
            ["len",  ["sift:length", "$.self.text"]], //length of this text string
            ["term_n",  //bag of term=>n pairs where n is term count in this document
                ["sift:count_words",
                    ["sift:include_words",
                        ["sift:ngrams",
                            ["sift:exclude_words",
                                ["sift:to_words", 
                                    ["sift:remove_html",
                                        ["sift:downcase", "$.self.text"]
                                    ]
                                    ,
                                    3
                                ]
                                ,
                                {"a":1, "the":1, "to":1, "blah":1}
                                ,
                                1
                            ]
                            ,
                            [1,2,3]
                        ]
                        ,
                        {}
                        ,
                        1
                    ]
                ]
            ],
            // document_n is no. terms in this document
            ["document_n", ["sift:multiset_cardinality", "$.self.term_n"]]
        ],
    "folder_each_item":
        {
            \\ update folder-level counter variables
            "corpus_n": ["sift:multiset_union", "$.folder.corpus_n", "$.item.term_n"],
            "corpus_dt": ["sift:multiset_increment", "$.folder.corpus_dt", "$.item.term_n"]
        }
}
__

    my $prototypes2 = <<'__';
/*
 * pre-profile -> profile
 *
 */
{
    "folder":
        {
            "corpus_n": {},
            "corpus_dt": {},
            "corpus_N": "$.folders[0].value.corpus_N",
            "value_type": ["term", "tfidf", "n", "tf", "idf"]
        },
    "item":
        ["sift:Bag",
            ["document_n", "$.items.document_n"],
            ["term",
                ["sift:threshold",
                    ["sift:limit",
                        ["sift:sort",
                            ["sift:tfidf", 
                                "$.items.term_n", 
                                "$.items.document_n",
                                "$.folders[0].value.corpus_dt", 
                                "$.folders[0].value.corpus_N"
                            ]
                        ]
                        ,
                        3
                    ]
                    ,
                    0.09,
                    1
                ]
            ]
        ],
    "folder_each_item":
        {
            "corpus_n": ["sift:multiset_union", "$.folder.corpus_n", ["sift:project", 2, "$.item.term"]],
            "corpus_dt": ["sift:multiset_increment", "$.folder.corpus_dt", "$.item.term"]
        }
}
__

    my $prototypes = <<'__';
/*
 * Profiles x Profiles -> Matches
 *
 */
{
    "folder":
        {
            "corpus_n": ["sift:multiset_union", "$.folders.corpus_n"],
            "corpus_dt": ["sift:multiset_union", "$.folders.corpus_dt"]
        },
    "item":
        ["sift:Bag",
            ["items", "$.items.term"],
            ["_terms1", ["sift:tfidf",
                    ["sift:hash", ["sift:project", [0,2], "$.items[0].value.term"]],
                    "$.items[0].value.document_n",
                    "$.folder.corpus_dt",
                    "$.folder.corpus_n"
                ]
            ],
            ["_terms2", ["sift:tfidf",
                    ["sift:hash", ["sift:project", [0,2], "$.items[1].value.term"]],
                    "$.items[1].value.document_n",
                    "$.folder.corpus_dt",
                    "$.folder.corpus_n"
                ]
            ],
            ["matches", ["sift:cosine", "$.self._terms1", "$.self._terms2"]]
        ]
}
__

    my $prototypes_hash = helper_parse_json($prototypes);
    if (performed_render()) {
        return;
    }
    my $compiled_prototypes = compile_prototype($prototypes_hash);
    if (performed_render()) {
        return;
    }

    my $context = {
        'folder'    => $folder_info,
#        'item'      => {},
        'folders'   => \@argument_folders_info,
#??? is there such a concept for map/generator?        'current_folder' => undef,
#        'items'     => [],
#        'self'      => undef,
         'arguments_size' => $transform_manifest->{'size'},
    };
    # if target value already has data in it, merge new values into existing ones
    $folder_info->{'value'} = helper_fn_multiset_union(
        $folder_info->{'value'}, 
        evaluate_prototype_value($compiled_prototypes->{'folder'}, $context)
    );
    $folder_info->{'prototypes'} = $prototypes_hash;

    #
    # process folder item transformations until finished or timeout
    #
    
    my $finished = $FALSE;
    LP_MANIFEST:
    for (;;) {
        # only execute for a maximum of N seconds (+ time of one iteration)
        if ((time - $start_time) > $TRANSFORM_TIMEOUT) {
            last LP_MANIFEST;
        }

        # load arguments at current index
        my $index = $transform_manifest->{'index'};
        my $argument_values = ();
        #FIXME: optimisation to batch load, say, 1000 ids at a time rather than single id queries (at least for innermost index)
        #FIXME: optimisation for reflexive comparisons (no need to reload the same data multiple times)
        #FIXME: optimisation for symmetrical operators in a 'product' relationship where only need calc half of matrix
        my @item_ids = ();
        my @item_values = ();
        for(my $i=0; $i < scalar(@argument_folders_path); $i++) {
            my $ix = ($folder_info->{'generator'} eq 'map') ? $index->[0] : $index->[$i];
            my $item_ids = helper_items_index_get($argument_folders_path[$i], 1+$ix, 1);
            my $value = helper_items_get($folder_type, $settings, $params, @$item_ids[0], $folder_info->{'document_ids'}[$i]);
            push(@item_ids, @$item_ids[0]);
            push(@item_values, $value);
        }

        # apply function to arguments and store value as a new item

        my $item_id = ($folder_info->{'generator'} eq 'map')
            ?   $item_ids[0]
            :   join('_x_', @item_ids);

        my %item_info = (
            'id'            => $item_id,
#            'uri'           => undef,
        );

        $context->{'item'}  = \%item_info;   #IMPORTANT: does not contain 'value' during evaluation of JSONPaths.
        $context->{'self'}  = undef;         #Dynamically assigned during prototype evaluation (only for sift:Bag and ARRAY(?); not for HASH though as no control over key order)
        $context->{'items'} = \@item_values;

        my $err;
        $@ = undef;
        $! = undef;
        eval {
            $item_info{'value'} = evaluate_prototype_value(
                $compiled_prototypes->{'item'},
                $context
            );
            if ($compiled_prototypes->{'folder_each_item'}) {
                $context->{'item'} = $item_info{'value'};
                $folder_info->{'value'} = evaluate_prototype_value(
                    $compiled_prototypes->{'folder_each_item'}, 
                    $context,
                    $folder_info->{'value'}
                );
            }
        };
        if ($@) {
            $err = $@;
        } elsif ($!) {
            $err = $!;
        }
        if (defined $err) {
            render({
                'status' => '400 Bad Request',
                'text'   => serialise_error_message('Invalid function: ' . $err),
            });
            # abort transformation to avoid thousands of errors
            unlink($transform_file);
            return;
        }

        # create one or more persistent items
        helper_items_create($folder_type, $settings, $params, [\%item_info]);
        if (performed_render()) {
            return;
        }

        # increment rightmost index
        LP_INCREMENT_INDICES:
        for(my $i=scalar(@$index)-1; $i >= 0; $i--) {
            $index->[$i]++;
            if ($index->[$i] < $size->[$i]) {
                last LP_INCREMENT_INDICES;
            }
            else {
                if ($i == 0) {
                    $finished = $TRUE;
                    last LP_MANIFEST;
                }
                $index->[$i] = 0;
            }
        }
    }

    $folder_info->{'modified'} = time;
    helper_folders_put_info($folder_type, $settings, $params, $folder_info);
    if (performed_render()) {
        return;
    }
    if ($finished) {
        #
        # finished all tranformations, so delete the transform file
        #
        unlink($transform_file);
    }
    else {
        #
        # preserve state for subsequent continuation
        #
        util_writeFile($transform_file, JSON->new->canonical->pretty->encode($transform_manifest) );
    }

}


sub helper_creating {
    #
    # Tests whether the create_from manifest file is still in the document's folder.
    # This is a reliable way of testing whether transformer.pl (on cron) is still copying
    # and transforming items into the folder. Once completed the transformer.pl deletes the file.
    #
    # Returns $TRUE if creating items; $FALSE otherwise.
    #
    my ($folder_type, $settings, $params) = @_;
    
    my $folder_path = helper_folders_path($folder_type, $settings, $params);
    if (performed_render()) {
        return($FALSE);
    }

    my $create_from_file = File::Spec->catfile($folder_path, $TRANSFORM_MANIFEST_FILE);
    
    return (-e $create_from_file);
}


#####################################


sub helper_parse_json {
    #
    # parse JSON string to a Perl hash or array
    # NB. Allows comments encoded in JavaScript syntax
    #
    my ($json_str) = @_;

    # strip out /*...*/ comments
    $json_str =~ s{/\*.*?\*/}{}gxsm;
    # strip out //... trailing comments
    $json_str =~ s{//[^\n\r]*}{}gxsm;

    my $hash_or_array;
    my $err;
    eval{
         $hash_or_array = JSON->new->decode($json_str);
    };
    if ($@) {
        $err = $@;
    } elsif ($!) {
        $err = $!;
    }
    if (defined $err) {
        render({
            'status' => '400 Bad Request',
            'text'   => serialise_error_message('Invalid JSON: ' . $err . "\n" . $json_str),
        });
        return;
    }
    return $hash_or_array;
}

sub helper_parse_json_path {
    #
    # parse JSONPath string to a JSON::Path object
    #
    my ($path_str) = @_;
    my $path_obj;
    my $err;
    eval{
         $path_obj = JSON::Path->new($path_str);
    };
    if ($@) {
        $err = $@;
    } elsif ($!) {
        $err = $!;
    } elsif (!defined $path_obj) {
        $err = 'syntax error';
    }
    if (defined $err) {
        render({
            'status' => '400 Bad Request',
            'text'   => serialise_error_message('Invalid JSONPath: ' . $err . "\n" . $path_str),
        });
        return;
    }
    return $path_obj;
}

sub helper_apply_json_path {
    #
    # apply JSON::Path object to a variable, returning an array of results
    #
    my ($path_obj, $object) = @_;
    my @v;
    my $err;
    eval{
        @v = $path_obj->values($object);    #NOTE: values() returns a LIST
    };
    if ($@) {
        $err = $@;
    } elsif ($!) {
        $err = $!;
    } elsif (scalar(@v) == 0) {
        $err = '';
    }
    if (defined $err) {
        my $obj = Dumper($object);
        $obj =~ s/\$VAR1\s=\s//xsm;
        $obj =~ s/;$//xsm;
        render({
            'status' => '400 Bad Request',
            'text'   => serialise_error_message('Invalid JSONPath application: JSONPath expression=\'' . $path_obj . "'\nJSON value=" . $obj),
        });
        return;
    }
    return \@v;
}


sub compile_prototype {
    #
    #   Compile JSONPath strings inside a JSON structure to JSON::Path objects
    #   (Assumes strings starting "'$." are a JSONPath)
    #
    my ($value) = @_;
    if (!defined $value) {
        return '';
    }
    elsif (ref($value) eq 'HASH') {
        my @keys = keys %$value;
        my %compiled_hash = ();
        for my $key (@keys) {
            $compiled_hash{$key} = compile_prototype($value->{$key});
        }
        return \%compiled_hash;
    }
    elsif (ref($value) eq 'ARRAY') {
        my @compiled_array = ();
        for my $element (@$value) {
            push(@compiled_array, compile_prototype($element));
        }
        return \@compiled_array;
    }
    else {
        my $value_copy = $value;  #copy to avoid changing numerics to strings as side-effect of substr
        if (substr($value_copy, 0, 2) eq '$.') {
            $value =~ s/^\$\.folder\./\$\.folder\.value\./xsmo;
            $value =~ s/^\$\.items\./\$\.items\[\*\]\.value\./xsmo;
            $value =~ s/^\$\.folders\./\$\.folders\[\*\]\.value\./xsmo;
            # compile literal
            my $path_obj = helper_parse_json_path($value);
            if (performed_render()) {
                return;
            }
            return $path_obj;
        }
    }
    return $value;
}

sub evaluate_prototype_value {
    #
    #   Copy of compiled prototype $value with JSON Path expressions evaluated against $object.
    #   Optionally, merge the result into the supplied initial value (a reference to a hash or array).
    #
    my ($value, $object, $initial_value) = @_;
    if (!defined $value) {
        return '';
    }
    my $type = ref($value);
    if ($type eq 'HASH') {
        # construct a hash
        my @keys = keys %$value;
        my $evaluated_hash = $initial_value || {};
        for my $key (@keys) {
            $evaluated_hash->{$key} = evaluate_prototype_value($value->{$key}, $object);
        }
        return $evaluated_hash;
    }
    elsif ($type eq 'ARRAY') {
        if (substr($value->[0], 0, 8) eq 'sift:Bag') {
            # construct hash from (car cdr) key, value arrays rather than from a hash prototype
            # (allows user to create a hash but have keys evaluated in declared key order, rather than randon order)
            my $evaluated_hash = $initial_value || {};
            my $old = $object->{'self'};
            $object->{'self'} = $evaluated_hash;
            my $first = $TRUE;
            for my $array_ref (@$value) {
                if ($first) { $first = $FALSE; next; }  #skip "sift:Bag"
                $evaluated_hash->{$array_ref->[0]} = evaluate_prototype_value($array_ref->[1], $object);
            }
            $object->{'self'} = $old;
            return $evaluated_hash;
        }
=head
        if (substr($value->[0], 0, 8) eq 'sift:map') {
            # construct an array from an array and a prototype element - i.e. map(array, element_prototype)
            # (allows user to process each element in the supplied array)
            my $evaluated_array = $initial_value || [];
            my $array_ref = evaluate_prototype_value($value->[1], $object);
            if (ref($array_ref) eq 'ARRAY') {
                my $element_prototype = $value->[2];
                my $old = $object->{'element'};
                for my $element (@$array_ref) {
                    $object->{'element'} = $element;
                    push(@$evaluated_array, evaluate_prototype_value($element_prototype, $object));
                }
                $object->{'element'} = $old;
            }
            return [];
            return $evaluated_array;
        }
=cut

        else {
            # construct an array or apply function (car) to arguments (cdr)
            my $evaluated_array = $initial_value || [];
#            my $old = $object->{'self'};
#            $object->{'self'} = \@evaluated_array;
            for my $element (@$value) {
                push(@$evaluated_array, evaluate_prototype_value($element, $object));
            }
#            $object->{'self'} = $old;
            if (substr($value->[0], 0, 5) eq 'sift:') {
                # apply function (car) to arguments (cdr)
                my $fn = 'helper_fn_' . substr(shift @$evaluated_array, 5);
                # evaluate of function, from fn_helpers.pl
                no strict 'refs';
                my $ret = &$fn(@$evaluated_array);
                use strict 'refs';
                return $ret;
            }
            else {
                # construct an array
                return $evaluated_array;
            }
        }
    }
    elsif ($type eq 'JSON::Path') {
        # replace compiled JSON Path with result of its application to $object
        my $v = helper_apply_json_path($value, $object);
        if (performed_render()) {
            return;
        }
        if (scalar(@$v) == 0) {
            return undef;
        }
        if (scalar(@$v) == 1) {
            return $v->[0];
        }
        return $v;
#        my @v = $value->values($object);    #NOTE: values() returns a LIST
#        if (scalar(@v) == 0) {
#            return undef;
#        }
#        if (scalar(@v) == 1) {
#            return $v[0];
#        }
#        return \@v;
##        return \@v || '';
        #FIXME: the above default of '' (instead of undef) could actually be typed to s_0 or somesuch dependant upon the expected result type
    }
    return $value;
}


1;