# routes.pl
use strict;
use warnings;

my $FALSE = 0;
my $TRUE  = 1;

sub routes {
    #
    #   ARRAYREF routes(HASHREF $settings)
    #
    #   Returns a Ruby on Rails inspired url routing pattern definition.
    #
    #   See lib/routing.pl for details of syntax and semantics.
    #
    my ($settings) = @_;

    # set formats to a string representation of a regular expression (e.g. '/json|rdf|terms|xml|yaml/')
    my $ACCEPTED_FORMATS_STR = $settings->{'SUPPORTED_FORMATS_STR'};
    my $ACCEPTED_FORMATS = '/' . $ACCEPTED_FORMATS_STR . '/';
    
    # set default format from either simple content negotiation or literal default extension (e.g. 'xml')
    my $DEFAULT_FORMAT = $settings->{'CONTENT_FORMATS'}{ $ENV{'HTTP_ACCEPT'} || '' } || $settings->{'DEFAULT_FORMAT'};

    # set recognised and default input formats for item creation from text
    my $ACCEPTED_INPUT_FORMATS_STR = 'text|csv|json|xml|arff';
    my $ACCEPTED_INPUT_FORMATS = '/' . $ACCEPTED_INPUT_FORMATS_STR . '/';
    my $DEFAULT_INPUT_FORMAT = 'text';

    # regex string for ids that are also legal perl sub names and legal file names
    my $ACCEPTED_IDS = '/^\p{Ll}(?:\p{Ll}|[\d_])*$/';

    # more loosely constrained id name (e.g. to allow people's names as ids)
    my $ACCEPTED_NAMES = '/^[^\?\\\/\=]+$/';


    my @routes = (

        #
        # API documentation pages
        #

        [ 'api/:action',
          {
            controller => 'api',
            requirements => { action => '/^\p{Lowercase}[\p{Lowercase}\d_\-]*$/', },
            defaults => { action => 'index', format => 'html' },
          }
        ],


        #
        # DBLP author search utility pages
        #

        [ 'demo/:action.:format',
          {
            controller => 'sift',
            conditions => { method => 'post' },
            format => $ACCEPTED_FORMATS,
            requirements => {
                action => '/search|disambiguate|restrict/',
            },
            defaults => { format => 'html' },
          }
        ],
        [ 'demo/dblp_search_results',
          {
            controller => 'dblp',
            actions => {
                'post'   => 'search_results     names_list refresh',
            },
            requirements => {
                names_list => '/.*/',
            },
            models => {
                'names_list' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>50*1024 },
                'refresh' => { type=>'BOOL' },
            },
            defaults => { format => 'html' },
          }
        ],
        [ 'demo/dblp_search_restrict',
          {
            controller => 'dblp',
            actions => {
                'post'   => 'search_restrict    results_list',
            },
            requirements => {
                results_list => '/.*/',
            },
            models => {
                'results_list' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>100*1024 },
            },
            defaults => { format => 'html' },
          }
        ],
        [ 'demo/dblp_extract',
          {
            controller => 'dblp',
            action => 'extract',
            requirements => {
                uri => '/.*/',
            },
            defaults => { format => 'txt', refresh => 0 },
          }
        ],



        #
        # REST system (inc. workflow and status)
        #

        [ ':user_id/workflow/:workflow_id.:format',
          {
            controller => 'system',
            actions => {
                'delete' => 'workflow_destroy    user_id workflow_id format',
                'head'   => 'workflow_enacting   user_id workflow_id format',
                'post'   => 'workflow_create     user_id workflow_id format commands',
            },
            requirements => {
                user_id => $ACCEPTED_IDS,
                workflow_id => $ACCEPTED_IDS,
                format => $ACCEPTED_FORMATS,
            },
            defaults => { format => $DEFAULT_FORMAT, },
            models => {
                'user_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'workflow_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'format' => { type=>'STR', default=>$DEFAULT_FORMAT, values=>$ACCEPTED_FORMATS_STR },
                'commands' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>5000*1024 },
            },
          }
        ],
        [ 'status/test/:user_id.:format',
          {
            controller => 'system',
            action => 'status_test',
            requirements => {
                user_id => $ACCEPTED_IDS,
                format => $ACCEPTED_FORMATS,
            },
            defaults => { format => $DEFAULT_FORMAT, },
          }
        ],
        [ 'status/test.:format',
          {
            controller => 'system',
            action => 'status_test',
            format => $ACCEPTED_FORMATS,
            defaults => { format => $DEFAULT_FORMAT, },
          }
        ],


        #
        # REST documents
        #

        [ ':user_id/documents.:format',
          {
            controller => 'documents',
            actions => {
                'get'    => 'list           user_id format full',
                'any'    => 'wrong_method   format',
            },
            requirements => {
                user_id => $ACCEPTED_IDS,
                format => $ACCEPTED_FORMATS,
            },
            defaults => { format => $DEFAULT_FORMAT, },
            models => {
                'user_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'format' => { type=>'STR', default=>$DEFAULT_FORMAT, values=>$ACCEPTED_FORMATS_STR },
                'full' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
            },
          }
        ],

        [ ':user_id/documents/:folder_id.:format',
          {
            controller => 'documents',
            actions => {
                'delete' => 'destroy    user_id folder_id format full',
                'get'    => 'show       user_id folder_id format full',
                'head'   => 'exists     user_id folder_id format',
                'post'   => 'create     user_id folder_id format mode description data_type full',
                'put'    => 'update     user_id folder_id format mode description full',
            },
            requirements => {
                user_id => $ACCEPTED_IDS,
                folder_id => $ACCEPTED_IDS,
                format => $ACCEPTED_FORMATS,
            },
            defaults => { format => $DEFAULT_FORMAT, },
            models => {
                'user_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'folder_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'format' => { type=>'STR', default=>$DEFAULT_FORMAT, values=>$ACCEPTED_FORMATS_STR },
                'mode' => { type=>'STR', required=>$FALSE, default=>'public', values=>'public|private' },
                'description' => { type=>'STR', required=>$FALSE, default=>'', maxlength=>1024 },
                'data_type' => { type=>'STR', required=>$FALSE, default=>'', maxlength=>8096 },
                'full' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
            },
          }
        ],


        #
        # REST document_items
        #

        [ ':user_id/documents/:folder_id/import/:bookmarks_id.:format',
          {
            controller => 'document_items',
            actions => {
                'post'  => 'import          user_id folder_id bookmarks_id format same_domain same_stem breadth depth threshold remove_html',
                'head'  => 'importing       user_id folder_id bookmarks_id format',
                'any'   => 'wrong_method    format',
            },
            requirements => {
                user_id => $ACCEPTED_IDS,
                folder_id => $ACCEPTED_IDS,
#                bookmarks_id => $ACCEPTED_IDS,
                format => $ACCEPTED_FORMATS,
            },
            defaults => { bookmarks_id => '', format => $DEFAULT_FORMAT, },
            models => {
                'user_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'folder_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'bookmarks_id' => { type=>'STR', required=>$FALSE, default=>'', minlength=>0, maxlength=>64 },
                'format' => { type=>'STR', default=>$DEFAULT_FORMAT, values=>$ACCEPTED_FORMATS_STR },
                'same_domain' => { type=>'BOOL', required=>$FALSE, default=>$TRUE },
                'same_stem' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
                'breadth' => { type=>'INT2', required=>$FALSE, default=>50, minvalue=>1, maxvalue=>200 },
                'depth' => { type=>'INT2', required=>$FALSE, default=>0, minvalue=>0, maxvalue=>3 },
                'threshold' => { type=>'NUM', required=>$FALSE, default=>0.7, minvalue=>0 },
                'remove_html' =>{ type=>'BOOL', required=>$FALSE, default=>$FALSE },
            },
          }
        ],

        [ ':user_id/documents/:folder_id/creating.:format',
          {
            controller => 'document_items',
            actions => {
                'head'  => 'creating        user_id folder_id format',
                'any'   => 'wrong_method    format',
            },
            requirements => {
                user_id => $ACCEPTED_IDS,
                folder_id => $ACCEPTED_IDS,
                format => $ACCEPTED_FORMATS,
            },
            defaults => { format => $DEFAULT_FORMAT, },
            models => {
                'user_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'folder_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'format' => { type=>'STR', default=>$DEFAULT_FORMAT, values=>$ACCEPTED_FORMATS_STR },
            },
          }
        ],

        [ ':user_id/documents/:folder_id/from/*document_ids.:format',
          {
            controller => 'documents',
            actions => {
                'post'   => 'create_from    user_id folder_id document_ids format generator description mode sort full',
                'head'   => 'creating_from  user_id folder_id format',
                'any'    => 'wrong_method   format',
            },
            requirements => {
                user_id => $ACCEPTED_IDS,
                folder_id => $ACCEPTED_IDS,
                format => $ACCEPTED_FORMATS,
            },
            defaults => { format => $DEFAULT_FORMAT, },
            models => {
                'user_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'folder_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'document_ids' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>640 },
                'format' => { type=>'STR', default=>$DEFAULT_FORMAT, values=>$ACCEPTED_FORMATS_STR },
                'generator' => { type=>'STR', required=>$FALSE, default=>'map', values=>'map|product' },
                'description' => { type=>'STR', required=>$FALSE, default=>'', maxlength=>1024 },
                'mode' => { type=>'STR', required=>$FALSE, default=>'public', values=>'public|private' },
                'sort' => { type=>'INT2', required=>$FALSE, default=>2, minvalue=>0, maxvalue=>2 },
                'full' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
            },
          }
        ],

        [ ':user_id/documents/:folder_id/items.:format',
          {
            controller => 'document_items',
            actions => {
                'post'   => 'create     user_id folder_id format values as is_schema use_schema id_path description_path full',
                'put'    => 'create     user_id folder_id format values as is_schema use_schema id_path description_path full',
            },
            requirements => {
                user_id => $ACCEPTED_IDS,
                folder_id => $ACCEPTED_IDS,
                format => $ACCEPTED_FORMATS,
                values => '/.*/',
            },
            defaults => { format => $DEFAULT_FORMAT, },
            models => {
                'user_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'folder_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'format' => { type=>'STR', default=>$DEFAULT_FORMAT, values=>$ACCEPTED_FORMATS_STR },
                'values' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>5000*1024 },
                'as' => { type=>'STR', required=>$FALSE, default=>$DEFAULT_INPUT_FORMAT, values=>$ACCEPTED_INPUT_FORMATS_STR },
                'is_schema' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
                'use_schema' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
                'id_path' => { type=>'STR', required=>$FALSE, default=>'',  maxlength=>64 },
                'description_path' => { type=>'STR', required=>$FALSE, default=>'',  maxlength=>64 },
                'full' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
            },
          }
        ],
        [ ':user_id/documents/:folder_id/items.:format',
          {
            controller => 'document_items',
            actions => {
                'post'   => 'create     user_id folder_id format items_list as is_schema use_schema full',
                'put'    => 'create     user_id folder_id format items_list as is_schema use_schema full',
            },
            requirements => {
                user_id => $ACCEPTED_IDS,
                folder_id => $ACCEPTED_IDS,
                format => $ACCEPTED_FORMATS,
                items_list => '/.*/',
            },
            defaults => { format => $DEFAULT_FORMAT, },
            models => {
                'user_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'folder_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'format' => { type=>'STR', default=>$DEFAULT_FORMAT, values=>$ACCEPTED_FORMATS_STR },
                'items_list' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>5000*1024 },
                'as' => { type=>'STR', required=>$FALSE, default=>$DEFAULT_INPUT_FORMAT, values=>$ACCEPTED_INPUT_FORMATS_STR },
                'is_schema' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
                'use_schema' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
                'full' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
            },
          }
        ],

        [ ':user_id/documents/:folder_id/items/:item_id.:format',
          {
            controller => 'document_items',
            actions => {
                'delete' => 'destroy    user_id folder_id item_id format full',
                'get'    => 'show       user_id folder_id item_id format full',
                'head'   => 'exists     user_id folder_id item_id format',
                'post'   => 'create     user_id folder_id item_id format text value as description full',
                'put'    => 'update     user_id folder_id item_id format text value as description full',
            },
            requirements => {
                user_id => $ACCEPTED_IDS,
                folder_id => $ACCEPTED_IDS,
                item_id => $ACCEPTED_NAMES,
                format => $ACCEPTED_FORMATS,
            },
            defaults => { format => $DEFAULT_FORMAT, },
            models => {
                'user_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'folder_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'item_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'format' => { type=>'STR', default=>$DEFAULT_FORMAT, values=>$ACCEPTED_FORMATS_STR },
                'text' => { type=>'STR', required=>$FALSE, default=>'', maxlength=>5000*1024 },
                'value' => { type=>'STR', required=>$FALSE, default=>'', maxlength=>5000*1024 },
                'as' => { type=>'STR', required=>$FALSE, default=>$DEFAULT_INPUT_FORMAT, values=>$ACCEPTED_INPUT_FORMATS_STR },
                'description' => { type=>'STR', required=>$FALSE, default=>'', maxlength=>1024 },
                'full' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
            },
          }
        ],

        [ ':user_id/documents/:folder_id/items.:format',
          {
            controller => 'document_items',
            actions => {
                'get'    => 'list           user_id folder_id format page count full',
                'delete' => 'destroy_all    user_id folder_id format',
                'any'    => 'wrong_method   format',
            },
            requirements => {
                user_id => $ACCEPTED_IDS,
                folder_id => $ACCEPTED_IDS,
                format => $ACCEPTED_FORMATS,
            },
            defaults => { format => $DEFAULT_FORMAT, },
            models => {
                'user_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'folder_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'format' => { type=>'STR', default=>$DEFAULT_FORMAT, values=>$ACCEPTED_FORMATS_STR },
                'page' => { type=>'INT2', required=>$FALSE, default=>1, minvalue=>1 },
                'count' => { type=>'INT2', required=>$FALSE, default=>10, minvalue=>1, maxvalue=>1000 },
                'full' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
            },
          }
        ],


        #
        # REST profiles
        #

        [ ':user_id/profiles.:format',
          {
            controller => 'profiles',
            actions => {
                'get'    => 'list           user_id format full items',
                'any'    => 'wrong_method   format',
            },
            requirements => {
                user_id => $ACCEPTED_IDS,
                format => $ACCEPTED_FORMATS,
            },
            defaults => { format => $DEFAULT_FORMAT, },
            models => {
                'user_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'format' => { type=>'STR', default=>$DEFAULT_FORMAT, values=>$ACCEPTED_FORMATS_STR },
                'full' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
                'items' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
            },
          }
        ],

        [ ':user_id/profiles/:folder_id/recalculate.:format',
          {
            controller => 'profiles',
            actions => {
                'post'   => 'recalculate    user_id folder_id format sort full',
                'any'    => 'wrong_method   format',
            },
            requirements => {
                user_id => $ACCEPTED_IDS,
                folder_id => $ACCEPTED_IDS,
                format => $ACCEPTED_FORMATS,
            },
            defaults => { format => $DEFAULT_FORMAT, },
            models => {
                'user_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'folder_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'format' => { type=>'STR', default=>$DEFAULT_FORMAT, values=>$ACCEPTED_FORMATS_STR },
                'sort' => { type=>'INT2', required=>$FALSE, default=>2, minvalue=>0, maxvalue=>2 },
                'full' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
            },
          }
        ],

        [ ':user_id/profiles/:folder_id/from/:document_id.:format',
          {
            controller => 'profiles',
            actions => {
                'post'   => 'create         user_id folder_id document_id format description mode ignore_case remove_html remove_stopwords stopwords stem ngrams restrict_vocabulary vocabulary limit length term_weights term_weight_default threshold sort full',
                'put'    => 'update         user_id folder_id document_id format description mode ignore_case remove_html remove_stopwords stopwords stem ngrams restrict_vocabulary vocabulary limit length term_weights term_weight_default threshold recalculate sort full',
                'any'    => 'wrong_method   format',
            },
            requirements => {
                user_id => $ACCEPTED_IDS,
                folder_id => $ACCEPTED_IDS,
                document_id => $ACCEPTED_IDS,
                format => $ACCEPTED_FORMATS,
            },
            defaults => { format => $DEFAULT_FORMAT, },
            models => {
                'user_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'folder_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'document_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'format' => { type=>'STR', default=>$DEFAULT_FORMAT, values=>$ACCEPTED_FORMATS_STR },
                'description' => { type=>'STR', required=>$FALSE, default=>'', maxlength=>1024 },
                'mode' => { type=>'STR', required=>$FALSE, default=>'public', values=>'public|private' },
                'ignore_case' => { type=>'BOOL', required=>$FALSE, default=>$TRUE },
                'remove_html' =>{ type=>'BOOL', required=>$FALSE, default=>$TRUE },
                'remove_stopwords' => { type=>'BOOL', required=>$FALSE, default=>$TRUE },
                'stopwords' => { type=>'STR', required=>$FALSE, default=>'', maxlength=>500*1024 },
                'stem' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
                'ngrams' => { type=>'STR', required=>$FALSE, default=>'1,2', maxlength=>30 },
                'restrict_vocabulary' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
                'vocabulary' => { type=>'STR', required=>$FALSE, default=>'', maxlength=>500*1024 },
                'limit' => { type=>'INT2', required=>$FALSE, default=>1000, minvalue=>1, maxvalue=>100000 },
                'length' => { type=>'INT2', required=>$FALSE, default=>2, minvalue=>1, maxvalue=>100 },
                'term_weights' => { type=>'STR', required=>$FALSE, default=>'', maxlength=>500*1024 },
                'term_weight_default' => { type=>'NUM', required=>$FALSE, default=>1, minvalue=>0, maxvalue=>1 },
                'threshold' => { type=>'NUM', required=>$FALSE, default=>0, minvalue=>0 },
                'recalculate' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
                'sort' => { type=>'INT2', required=>$FALSE, default=>2, minvalue=>0, maxvalue=>2 },
                'full' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
            },
          }
        ],
        # MALLET topic modelling from documents -> profiles
        # Author: Brian Liu
        [ ':user_id/tprofiles/:folder_id/from/:document_id.:format',
          {
            controller => 'profiles',
            actions => {
                'post'   => 'create_topics         output_model num_topics num_threads num_iterations random_seed num_top_words use_ngram '.
                			'use_pam alpha beta gamma delta delta1 delta2 user_id folder_id document_id format description '.
                			'mode ignore_case remove_html remove_stopwords stopwords stem ngrams restrict_vocabulary vocabulary '.
                			'limit length term_weights term_weight_default threshold sort full',
                'put'    => 'update_topics         num_topics user_id folder_id document_id format description mode ignore_case remove_html remove_stopwords stopwords stem ngrams restrict_vocabulary vocabulary limit length term_weights term_weight_default threshold recalculate sort full',
                'any'    => 'wrong_method   format',
            },
            requirements => {
                user_id => $ACCEPTED_IDS,
                folder_id => $ACCEPTED_IDS,
                document_id => $ACCEPTED_IDS,
                format => $ACCEPTED_FORMATS,
            },
            defaults => { format => $DEFAULT_FORMAT, },
            models => {
            	'output_model' => { type=>'BOOL', required=>$FALSE, default=>$TRUE },
            	'num_topics' => { type=>'NUM', required=>$FALSE, default=>10, minvalue=>10 },
            	'num_threads' => { type=>'NUM', required=>$FALSE, default=>1, minvalue=>1 },
            	'num_iterations' => { type=>'NUM', required=>$FALSE, default=>1000, minvalue=>1000 },
            	'random_seed' => { type=>'NUM', required=>$FALSE, default=>0, minvalue=>0 },
            	'num_top_words' => { type=>'NUM', required=>$FALSE, default=>20, minvalue=>0 },
            	'use_ngram' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
            	'use_pam' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
            	'alpha' => { type=>'NUM', required=>$FALSE, default=>50.0, minvalue=>0 },
            	'beta' => { type=>'NUM', required=>$FALSE, default=>0.01, minvalue=>0 },
            	'gamma' => { type=>'NUM', required=>$FALSE, default=>0.01, minvalue=>0 },
            	'delta' => { type=>'NUM', required=>$FALSE, default=>0.03, minvalue=>0 },
            	'delta1' => { type=>'NUM', required=>$FALSE, default=>0.2, minvalue=>0 },
            	'delta2' => { type=>'NUM', required=>$FALSE, default=>1000.0, minvalue=>0 },
                'user_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'folder_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'document_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'format' => { type=>'STR', default=>$DEFAULT_FORMAT, values=>$ACCEPTED_FORMATS_STR },
                'description' => { type=>'STR', required=>$FALSE, default=>'', maxlength=>1024 },
                'mode' => { type=>'STR', required=>$FALSE, default=>'public', values=>'public|private' },
                'ignore_case' => { type=>'BOOL', required=>$FALSE, default=>$TRUE },
                'remove_html' =>{ type=>'BOOL', required=>$FALSE, default=>$TRUE },
                'remove_stopwords' => { type=>'BOOL', required=>$FALSE, default=>$TRUE },
                'stopwords' => { type=>'STR', required=>$FALSE, default=>'', maxlength=>500*1024 },
                'stem' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
                'ngrams' => { type=>'STR', required=>$FALSE, default=>'1,2', maxlength=>30 },
                'restrict_vocabulary' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
                'vocabulary' => { type=>'STR', required=>$FALSE, default=>'', maxlength=>500*1024 },
                'limit' => { type=>'INT2', required=>$FALSE, default=>1000, minvalue=>1, maxvalue=>100000 },
                'length' => { type=>'INT2', required=>$FALSE, default=>2, minvalue=>1, maxvalue=>100 },
                'term_weights' => { type=>'STR', required=>$FALSE, default=>'', maxlength=>500*1024 },
                'term_weight_default' => { type=>'NUM', required=>$FALSE, default=>1, minvalue=>0, maxvalue=>1 },
                'threshold' => { type=>'NUM', required=>$FALSE, default=>0, minvalue=>0 },
                'recalculate' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
                'sort' => { type=>'INT2', required=>$FALSE, default=>2, minvalue=>0, maxvalue=>2 },
                'full' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
            },
          }
        ],

        [ ':user_id/profiles/:folder_id.:format',
          {
            controller => 'profiles',
            actions => {
                'delete' => 'destroy        user_id folder_id format sort full',
                'get'    => 'show           user_id folder_id format sort full',
                'head'   => 'exists         user_id folder_id format',
                'post'   => 'create         user_id folder_id document_id format description mode ignore_case remove_html remove_stopwords stopwords stem ngrams restrict_vocabulary vocabulary limit length term_weights term_weight_default threshold sort full',
                'put'    => 'update         user_id folder_id format document_id description mode ignore_case remove_html remove_stopwords stopwords stem ngrams restrict_vocabulary vocabulary limit length term_weights term_weight_default threshold sort full',
            },
            requirements => {
                user_id => $ACCEPTED_IDS,
                folder_id => $ACCEPTED_IDS,
                format => $ACCEPTED_FORMATS,
            },
            defaults => { format => $DEFAULT_FORMAT, },
            models => {
                'user_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'folder_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'document_id' => { type=>'STR', required=>$FALSE, default=>'', maxlength=>64 },
                'format' => { type=>'STR', default=>$DEFAULT_FORMAT, values=>$ACCEPTED_FORMATS_STR },
                'description' => { type=>'STR', required=>$FALSE, default=>'', maxlength=>1024 },
                'mode' => { type=>'STR', required=>$FALSE, default=>'public', values=>'public|private' },
                'ignore_case' => { type=>'BOOL', required=>$FALSE, default=>$TRUE },
                'remove_html' =>{ type=>'BOOL', required=>$FALSE, default=>$TRUE },
                'remove_stopwords' => { type=>'BOOL', required=>$FALSE, default=>$TRUE },
                'stopwords' => { type=>'STR', required=>$FALSE, default=>'', maxlength=>500*1024 },
                'stem' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
                'ngrams' => { type=>'STR', required=>$FALSE, default=>'1,2', maxlength=>30 },
                'restrict_vocabulary' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
                'vocabulary' => { type=>'STR', required=>$FALSE, default=>'', maxlength=>500*1024 },
                'limit' => { type=>'INT2', required=>$FALSE, default=>1000, minvalue=>1, maxvalue=>100000 },
                'length' => { type=>'INT2', required=>$FALSE, default=>2, minvalue=>1, maxvalue=>100 },
                'term_weights' => { type=>'STR', required=>$FALSE, default=>'', maxlength=>500*1024 },
                'term_weight_default' => { type=>'NUM', required=>$FALSE, default=>1, minvalue=>0, maxvalue=>1 },
                'threshold' => { type=>'NUM', required=>$FALSE, default=>0, minvalue=>0 },
                'sort' => { type=>'INT2', required=>$FALSE, default=>2, minvalue=>0, maxvalue=>2 },
                'full' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
            },
          }
        ],


        #
        # REST profile_items
        #

        [ ':user_id/profiles/:folder_id/items/:item_id.:format',
          {
            controller => 'profile_items',
            actions => {
                'get'    => 'show           user_id folder_id item_id format sort full',
                'head'   => 'exists         user_id folder_id item_id format',
                'any'    => 'wrong_method   format',
            },
            requirements => {
                user_id => $ACCEPTED_IDS,
                folder_id => $ACCEPTED_IDS,
                item_id => $ACCEPTED_NAMES,
                format => $ACCEPTED_FORMATS,
            },
            defaults => { format => $DEFAULT_FORMAT, },
            models => {
                'user_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'folder_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'item_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'format' => { type=>'STR', default=>$DEFAULT_FORMAT, values=>$ACCEPTED_FORMATS_STR },
                'sort' => { type=>'INT2', required=>$FALSE, default=>7, minvalue=>0, maxvalue=>7 },
                'full' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
            },
          }
        ],

        [ ':user_id/profiles/:folder_id/items.:format',
          {
            controller => 'profile_items',
            actions => {
                'get'    => 'list           user_id folder_id format sort full',
                'any'    => 'wrong_method   format',
            },
            requirements => {
                user_id => $ACCEPTED_IDS,
                folder_id => $ACCEPTED_IDS,
                format => $ACCEPTED_FORMATS,
            },
            defaults => { format => $DEFAULT_FORMAT, },
            models => {
                'user_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'folder_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'format' => { type=>'STR', default=>$DEFAULT_FORMAT, values=>$ACCEPTED_FORMATS_STR },
                'sort' => { type=>'INT2', required=>$FALSE, default=>7, minvalue=>0, maxvalue=>7 },
                'full' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
            },
          }
        ],


        #
        # REST matches
        #

        [ ':user_id/matches.:format',
          {
            controller => 'matches',
            actions => {
                'get'    => 'list           user_id format full',
                'any'    => 'wrong_method   format',
            },
            requirements => {
                user_id => $ACCEPTED_IDS,
                format => $ACCEPTED_FORMATS,
            },
            defaults => { format => $DEFAULT_FORMAT, },
            models => {
                'user_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'format' => { type=>'STR', default=>$DEFAULT_FORMAT, values=>$ACCEPTED_FORMATS_STR },
                'full' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
            },
          }
        ],

        [ ':user_id/matches/:folder_id/recalculate.:format',
          {
            controller => 'matches',
            actions => {
                'post'   => 'recalculate    user_id folder_id format sort full',
                'any'    => 'wrong_method   format',
            },
            requirements => {
                user_id => $ACCEPTED_IDS,
                folder_id => $ACCEPTED_IDS,
                format => $ACCEPTED_FORMATS,
            },
            defaults => { format => $DEFAULT_FORMAT, },
            models => {
                'user_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'folder_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'format' => { type=>'STR', default=>$DEFAULT_FORMAT, values=>$ACCEPTED_FORMATS_STR },
                'sort' => { type=>'INT2', required=>$FALSE, default=>2, minvalue=>0, maxvalue=>2 },
                'full' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
            },
          }
        ],
        # MALLET topic modelling matching
        # Author: Brian Liu
		[ ':user_id/matches/:folder_id/tprofiles/:profiles_id1/:with/:profiles_id2.:format',
          {
            controller => 'matches',
            actions => {
                'post'   => 'create_topics         user_id folder_id profiles_id1 profiles_id2 format description mode limit threshold sort full',
                'put'    => 'update_topics         user_id folder_id profiles_id1 profiles_id2 format description mode limit threshold sort full',
                'any'    => 'wrong_method   format',
            },
            requirements => {
                user_id => $ACCEPTED_IDS,
                folder_id => $ACCEPTED_IDS,
                profiles_id1 => $ACCEPTED_IDS,
                format => $ACCEPTED_FORMATS,
            },
            defaults => { with => 'with', profiles_id2 => '', format => $DEFAULT_FORMAT, },
            models => {
                'user_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'folder_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'profiles_id1' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'profiles_id2' => { type=>'STR', required=>$FALSE, default=>'', maxlength=>64 },
                'format' => { type=>'STR', default=>$DEFAULT_FORMAT, values=>$ACCEPTED_FORMATS_STR },
                'description' => { type=>'STR', required=>$FALSE, default=>'', maxlength=>1024 },
                'mode' => { type=>'STR', required=>$FALSE, default=>'public', values=>'public|private' },
                'limit' => { type=>'INT2', required=>$FALSE, default=>1000, minvalue=>1, maxvalue=>100000 },
                'threshold' => { type=>'NUM', required=>$FALSE, default=>0, minvalue=>0 },
                'sort' => { type=>'INT2', required=>$FALSE, default=>2, minvalue=>0, maxvalue=>2 },
                'full' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
                'with' => { type=>'STR', required=>$FALSE, default=>'with', values=>'with' },
            },
          }
        ],
        [ ':user_id/matches/:folder_id/profiles/:profiles_id1/:with/:profiles_id2.:format',
          {
            controller => 'matches',
            actions => {
                'post'   => 'create         user_id folder_id profiles_id1 profiles_id2 format description mode limit threshold sort full',
                'put'    => 'update         user_id folder_id profiles_id1 profiles_id2 format description mode limit threshold sort full',
                'any'    => 'wrong_method   format',
            },
            requirements => {
                user_id => $ACCEPTED_IDS,
                folder_id => $ACCEPTED_IDS,
                profiles_id1 => $ACCEPTED_IDS,
                format => $ACCEPTED_FORMATS,
            },
            defaults => { with => 'with', profiles_id2 => '', format => $DEFAULT_FORMAT, },
            models => {
                'user_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'folder_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'profiles_id1' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'profiles_id2' => { type=>'STR', required=>$FALSE, default=>'', maxlength=>64 },
                'format' => { type=>'STR', default=>$DEFAULT_FORMAT, values=>$ACCEPTED_FORMATS_STR },
                'description' => { type=>'STR', required=>$FALSE, default=>'', maxlength=>1024 },
                'mode' => { type=>'STR', required=>$FALSE, default=>'public', values=>'public|private' },
                'limit' => { type=>'INT2', required=>$FALSE, default=>1000, minvalue=>1, maxvalue=>100000 },
                'threshold' => { type=>'NUM', required=>$FALSE, default=>0, minvalue=>0 },
                'sort' => { type=>'INT2', required=>$FALSE, default=>2, minvalue=>0, maxvalue=>2 },
                'full' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
                'with' => { type=>'STR', required=>$FALSE, default=>'with', values=>'with' },
            },
          }
        ],

        [ ':user_id/matches/:folder_id.:format',
          {
            controller => 'matches',
            actions => {
                'delete' => 'destroy        user_id folder_id format sort full',
                'get'    => 'show           user_id folder_id format sort full',
                'head'   => 'exists         user_id folder_id format',
                'post'   => 'create         user_id folder_id format profiles_id1 profiles_id2 description mode limit threshold sort full',
                'put'    => 'update         user_id folder_id format profiles_id1 profiles_id2 description mode limit threshold sort full',
            },
            requirements => {
                user_id => $ACCEPTED_IDS,
                folder_id => $ACCEPTED_IDS,
                format => $ACCEPTED_FORMATS,
            },
            defaults => { profiles_id1 => '', profiles_id2 => '', format => $DEFAULT_FORMAT, },
            models => {
                'user_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'folder_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'profiles_id1' => { type=>'STR', required=>$FALSE, default=>'', maxlength=>64 },
                'profiles_id2' => { type=>'STR', required=>$FALSE, default=>'', maxlength=>64 },
                'format' => { type=>'STR', default=>$DEFAULT_FORMAT, values=>$ACCEPTED_FORMATS_STR },
                'description' => { type=>'STR', required=>$FALSE, default=>'', maxlength=>1024 },
                'mode' => { type=>'STR', required=>$FALSE, default=>'public', values=>'public|private' },
                'limit' => { type=>'INT2', required=>$FALSE, default=>1000, minvalue=>1, maxvalue=>100000 },
                'threshold' => { type=>'NUM', required=>$FALSE, default=>0, minvalue=>0 },
                'sort' => { type=>'INT2', required=>$FALSE, default=>2, minvalue=>0, maxvalue=>2 },
                'full' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
            },
          }
        ],


        #
        # REST match_matrix
        #

        [ ':user_id/matches/:folder_id/pairs.:format',
          {
            controller => 'match_matrix',
            actions => {
                'get'    => 'show_pairs     user_id folder_id format profiles_id',
                'any'    => 'wrong_method   format',
            },
            requirements => {
                user_id => $ACCEPTED_IDS,
                folder_id => $ACCEPTED_IDS,
                format => $ACCEPTED_FORMATS,
            },
            defaults => { format => $DEFAULT_FORMAT, },
            models => {
                'user_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'folder_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'format' => { type=>'STR', default=>$DEFAULT_FORMAT, values=>$ACCEPTED_FORMATS_STR },
                'profiles_id' => { type=>'STR', required=>$FALSE, default=>'', maxlength=>64 },
            },
          }
        ],


        [ ':user_id/matches/:folder_id/matrix/:type.:format',
          {
            controller => 'match_matrix',
            actions => {
                'get'    => 'show           user_id folder_id type separator format',
                'any'    => 'wrong_method   format',
            },
            requirements => {
                user_id => $ACCEPTED_IDS,
                folder_id => $ACCEPTED_IDS,
                format => $ACCEPTED_FORMATS,
            },
            defaults => { type => 'all', separator=>'comma', format =>'csv' },
            models => {
                'user_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'folder_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'type' => { type=>'STR', required=>$FALSE, default=>'all', values=>'all|rows|columns|values' },
                'separator' => { type=>'STR', required=>$FALSE, default=>'comma', values=>'comma|colon|line|space|tab' },
                'format' => { type=>'STR', default=>'csv', values=>$ACCEPTED_FORMATS_STR },
            },
          }
        ],


        #
        # REST match_items
        #

        [ ':user_id/matches/:folder_id/items.:format',
          {
            controller => 'match_items',
            actions => {
                'get'    => 'list           user_id folder_id format profiles_id sort threshold3 threshold2 threshold1 full',
                'any'    => 'wrong_method   format',
            },
            requirements => {
                user_id => $ACCEPTED_IDS,
                folder_id => $ACCEPTED_IDS,
                format => $ACCEPTED_FORMATS,
            },
            defaults => { format => $DEFAULT_FORMAT, },
            models => {
                'user_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'folder_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'format' => { type=>'STR', default=>$DEFAULT_FORMAT, values=>$ACCEPTED_FORMATS_STR },
                'profiles_id' => { type=>'STR', required=>$FALSE, default=>'', maxlength=>64 },
                'sort' => { type=>'INT2', required=>$FALSE, default=>7, minvalue=>0, maxvalue=>7 },
                'threshold3' => { type=>'NUM', required=>$FALSE, default=>0, minvalue=>0, maxvalue=>1000 },
                'threshold2' => { type=>'NUM', required=>$FALSE, default=>0, minvalue=>0, maxvalue=>1000 },
                'threshold1' => { type=>'NUM', required=>$FALSE, default=>0, minvalue=>0, maxvalue=>1000 },
                'full' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
            },
          }
        ],

        [ ':user_id/matches/:folder_id/items/:item_id.:format',
          {
            controller => 'match_items',
            actions => {
                'get'    => 'show           user_id folder_id item_id format profiles_id sort threshold3 threshold2 threshold1 full',
                'head'   => 'exists         user_id folder_id item_id format profiles_id',
                'any'    => 'wrong_method   format',
            },
            requirements => {
                user_id => $ACCEPTED_IDS,
                folder_id => $ACCEPTED_IDS,
                item_id => $ACCEPTED_NAMES,
                format => $ACCEPTED_FORMATS,
            },
            defaults => { format => $DEFAULT_FORMAT, },
            models => {
                'user_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'folder_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'item_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'format' => { type=>'STR', default=>$DEFAULT_FORMAT, values=>$ACCEPTED_FORMATS_STR },
                'profiles_id' => { type=>'STR', required=>$FALSE, default=>'', maxlength=>64 },
                'sort' => { type=>'INT2', required=>$FALSE, default=>7, minvalue=>0, maxvalue=>7 },
                'threshold3' => { type=>'NUM', required=>$FALSE, default=>0, minvalue=>0, maxvalue=>1000 },
                'threshold2' => { type=>'NUM', required=>$FALSE, default=>0, minvalue=>0, maxvalue=>1000 },
                'threshold1' => { type=>'NUM', required=>$FALSE, default=>0, minvalue=>0, maxvalue=>1000 },
                'full' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
            },
          }
        ],


        #
        # REST match_pairs
        #

        [ ':user_id/matches/:folder_id/pairs.:format',
          {
            controller => 'match_pairs',
            actions => {
                'get'    => 'list           user_id folder_id format full',
                'any'    => 'wrong_method   format',
            },
            requirements => {
                user_id => $ACCEPTED_IDS,
                folder_id => $ACCEPTED_IDS,
                format => $ACCEPTED_FORMATS,
            },
            defaults => { format => $DEFAULT_FORMAT, },
            models => {
                'user_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'folder_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'format' => { type=>'STR', default=>$DEFAULT_FORMAT, values=>$ACCEPTED_FORMATS_STR },
                'full' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
            },
          }
        ],

        [ ':user_id/matches/:folder_id/pairs/:pair_id.:format',
          {
            controller => 'match_pairs',
            actions => {
                'get'    => 'show           user_id folder_id pair_id format full',
                'head'   => 'exists         user_id folder_id pair_id format',
                'any'    => 'wrong_method   format',
            },
            requirements => {
                user_id => $ACCEPTED_IDS,
                folder_id => $ACCEPTED_IDS,
                pair_id => $ACCEPTED_NAMES,
                format => $ACCEPTED_FORMATS,
            },
            defaults => { format => $DEFAULT_FORMAT, },
            models => {
                'user_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'folder_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'pair_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'format' => { type=>'STR', default=>$DEFAULT_FORMAT, values=>$ACCEPTED_FORMATS_STR },
                'full' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
            },
          }
        ],

        #
        # REST bookmarks
        #

        [ ':user_id/bookmarks.:format',
          {
            controller => 'bookmarks',
            actions => {
                'get'    => 'list           user_id format',
                'any'    => 'wrong_method   format',
            },
            requirements => {
                user_id => $ACCEPTED_IDS,
                format => $ACCEPTED_FORMATS,
            },
            defaults => { format => $DEFAULT_FORMAT, },
            models => {
                'user_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'format' => { type=>'STR', default=>$DEFAULT_FORMAT, values=>$ACCEPTED_FORMATS_STR },
            },
          }
        ],

        [ ':user_id/bookmarks/:folder_id.:format',
          {
            controller => 'bookmarks',
            actions => {
                'delete' => 'destroy    user_id folder_id format',
                'get'    => 'show       user_id folder_id format',
                'head'   => 'exists     user_id folder_id format',
                'post'   => 'create     user_id folder_id format mode description',
                'put'    => 'update     user_id folder_id format mode description',
            },
            requirements => {
                user_id => $ACCEPTED_IDS,
                folder_id => $ACCEPTED_IDS,
                format => $ACCEPTED_FORMATS,
            },
            defaults => { format => $DEFAULT_FORMAT, },
            models => {
                'user_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'folder_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'format' => { type=>'STR', default=>$DEFAULT_FORMAT, values=>$ACCEPTED_FORMATS_STR },
                'mode' => { type=>'STR', required=>$FALSE, default=>'public', values=>'public|private' },
                'description' => { type=>'STR', required=>$FALSE, default=>'', maxlength=>1024 },
            },
          }
        ],


        #
        # REST bookmark_items
        #

        [ ':user_id/bookmarks/:folder_id/items.:format',
          {
            controller => 'bookmark_items',
            actions => {
                'post'   => 'create     user_id folder_id format items_list',
                'put'    => 'create     user_id folder_id format items_list',
            },
            requirements => {
                user_id => $ACCEPTED_IDS,
                folder_id => $ACCEPTED_IDS,
                format => $ACCEPTED_FORMATS,
                items_list => '/.*/',
            },
            defaults => { format => $DEFAULT_FORMAT, },
            models => {
                'user_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'folder_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'format' => { type=>'STR', default=>$DEFAULT_FORMAT, values=>$ACCEPTED_FORMATS_STR },
                'items_list' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>500*1024 },
            },
          }
        ],

        [ ':user_id/bookmarks/:folder_id/items/:item_id.:format',
          {
            controller => 'bookmark_items',
            actions => {
                'delete' => 'destroy    user_id folder_id item_id format',
                'get'    => 'show       user_id folder_id item_id format',
                'head'   => 'exists     user_id folder_id item_id format',
                'post'   => 'create     user_id folder_id item_id format item_url description',
                'put'    => 'update     user_id folder_id item_id format item_url description',
            },
            requirements => {
                user_id => $ACCEPTED_IDS,
                folder_id => $ACCEPTED_IDS,
                item_id => $ACCEPTED_NAMES,
                format => $ACCEPTED_FORMATS,
            },
            defaults => { format => $DEFAULT_FORMAT, },
            models => {
                'user_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'folder_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'item_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'format' => { type=>'STR', default=>$DEFAULT_FORMAT, values=>$ACCEPTED_FORMATS_STR },
                'item_url' => { type=>'STR', required=>$FALSE, default=>'', maxlength=>1024 },
                'description' => { type=>'STR', required=>$FALSE, default=>'', maxlength=>1024 },
            },
          }
        ],

        [ ':user_id/bookmarks/:folder_id/items.:format',
          {
            controller => 'bookmark_items',
            actions => {
                'get'    => 'list           user_id folder_id format',
                'delete' => 'destroy_all    user_id folder_id format',
                'any'    => 'wrong_method   format',
            },
            requirements => {
                user_id => $ACCEPTED_IDS,
                folder_id => $ACCEPTED_IDS,
                format => $ACCEPTED_FORMATS,
            },
            defaults => { format => $DEFAULT_FORMAT, },
            models => {
                'user_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'folder_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'format' => { type=>'STR', default=>$DEFAULT_FORMAT, values=>$ACCEPTED_FORMATS_STR },
            },
          }
        ],


        #
        # REST reports
        #

        [ ':user_id/reports.:format',
          {
            controller => 'reports',
            actions => {
                'get'    => 'list           user_id format',
                'any'    => 'wrong_method   format',
            },
            requirements => {
                user_id => $ACCEPTED_IDS,
                format => $ACCEPTED_FORMATS,
            },
            defaults => { format => $DEFAULT_FORMAT, },
            models => {
                'user_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'format' => { type=>'STR', default=>$DEFAULT_FORMAT, values=>$ACCEPTED_FORMATS_STR },
            },
          }
        ],
		# Add a new parament, topic, to identify report style (tf-idf/topics)
		# Author: Brian Liu
        [ ':user_id/reports/:folder_id/profiles/:profiles_id.:format',
          {
            controller => 'reports',
            actions => {
                'post'   => 'create_profiles    topic user_id folder_id format mode description type profiles_id',
                'put'    => 'update             topic user_id folder_id format mode description type profiles_id',
            },
            requirements => {
                user_id => $ACCEPTED_IDS,
                folder_id => $ACCEPTED_IDS,
                format => $ACCEPTED_FORMATS,
            },
            defaults => { topic => $FALSE, profiles_id => '', format => $DEFAULT_FORMAT, },
            models => {
                'user_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'folder_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'format' => { type=>'STR', default=>$DEFAULT_FORMAT, values=>$ACCEPTED_FORMATS_STR },
                'mode' => { type=>'STR', required=>$FALSE, default=>'public', values=>'public|private' },
                'description' => { type=>'STR', required=>$FALSE, default=>'', maxlength=>1024 },
                'type' => { type=>'STR', required=>$FALSE, default=>'html', values=>'html|graphviz' },
                'profiles_id' => { type=>'STR', required=>$FALSE, default=>'', maxlength=>64 },
                # default TF-IDF report, True => Topics report
                'topic' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
            },
          }
        ],
        # Add a new parament, topic, to identify report style (tf-idf/topics)
		# Author: Brian Liu
        [ ':user_id/reports/:folder_id/matches/:matches_id.:format',
          {
            controller => 'reports',
            actions => {
                'post'   => 'create_matches     topic user_id folder_id format mode description type matches_id strength',
                'put'    => 'update             topic user_id folder_id format mode description type matches_id',
            },
            requirements => {
                user_id => $ACCEPTED_IDS,
                folder_id => $ACCEPTED_IDS,
                format => $ACCEPTED_FORMATS,
            },
            defaults => { topic => $FALSE, matches_id => '', format => $DEFAULT_FORMAT, },
            models => {
                'user_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'folder_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'format' => { type=>'STR', default=>$DEFAULT_FORMAT, values=>$ACCEPTED_FORMATS_STR },
                'mode' => { type=>'STR', required=>$FALSE, default=>'public', values=>'public|private' },
                'description' => { type=>'STR', required=>$FALSE, default=>'', maxlength=>1024 },
                'type' => { type=>'STR', required=>$FALSE, default=>'html', values=>'html|graphviz' },
                'matches_id' => { type=>'STR', required=>$FALSE, default=>'', maxlength=>64 },
                'strength' => { type=>'NUM', required=>$FALSE, default=>95, minvalue=>1, maxvalue=>100 },
                # default TF-IDF report, True => Topics report
                'topic' => { type=>'BOOL', required=>$FALSE, default=>$FALSE },
            },
          }
        ],
        
        # serve pre-generated static files from reports folder under folder's access control
        [ ':user_id/reports/:folder_id/*file.:format',
          {
            controller => 'reports',
            actions => {
                'get'    => 'view       user_id folder_id file format',
            },
            requirements => {
                user_id => $ACCEPTED_IDS,
                folder_id => $ACCEPTED_IDS,
                format => '/html|zip|png|pdf|jpg|svg|dot/',     #lets xml,json,etc. non-statics be handled by a later route below
            },
            defaults => { format => 'html', },
            models => {
                'user_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'folder_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'file' => { type=>'STR', required=>$FALSE, default=>'index', maxlength=>250 },
                'format' => { type=>'STR', required=>$FALSE, default=>'html', values=>'html|zip|png|pdf|jpg|svg|dot' },
            },
          }
        ],

        [ ':user_id/reports/:folder_id.:format',
          {
            controller => 'reports',
            actions => {
                'delete' => 'destroy    user_id folder_id format',
                'get'    => 'show       user_id folder_id format',
                'head'   => 'exists     user_id folder_id format',
            },
            requirements => {
                user_id => $ACCEPTED_IDS,
                folder_id => $ACCEPTED_IDS,
                format => $ACCEPTED_FORMATS,
            },
            defaults => { format => $DEFAULT_FORMAT, },
            models => {
                'user_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'folder_id' => { type=>'STR', required=>$TRUE, minlength=>1, maxlength=>64 },
                'format' => { type=>'STR', default=>$DEFAULT_FORMAT, values=>$ACCEPTED_FORMATS_STR },
                'mode' => { type=>'STR', required=>$FALSE, default=>'public', values=>'public|private' },
                'description' => { type=>'STR', required=>$FALSE, default=>'', maxlength=>1024 },
            },
          }
        ],


        #
        # Default routes
        #

        [ ':controller/:action',
          {
            controller => 'default',
            defaults => { action => 'index', },
          }
        ],

        # Catch-all
        # NB. will only match if no physical index.html (or similar) file
        [ '/',
          {
            controller => 'default',
            action => 'index',
          }
        ],

    # Example usage:
    #  [ ':controller/:action/:id.:format',
    #    {
    #      conditions => { method => 'any' },
    #      controller => '/users|accounts|groups/',
    #      language => 'en_uk',
    #      requirements => {
    #           action => $ACCEPTED_IDS,
    #           page => '/^[\d]{1,3}/',
    #           id => $ACCEPTED_IDS,
    #      },
    #      defaults => { action => 'index', id => 'nil', },
    #    }
    #  ],
    );
    return \@routes;
}

1;