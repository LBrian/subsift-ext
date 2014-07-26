#!/usr/bin/perl -w
#
#   index.cgi
#
use strict;
use warnings;
#use diagnostics;

use Time::HiRes qw(gettimeofday tv_interval);
my $benchmark_t0 = [gettimeofday];

use FindBin qw($RealDir);
my $home_path = $RealDir;
# optionally, if in a *nix /cgi-bin folder, assume home is parent
$home_path =~ s{/cgi\-bin$}{};

# for internal metadata
use JSON;

use File::Path qw(mkpath rmtree);  #warning: newer version of File::Path renames these as qw(make_path remove_tree)
use File::Spec;

use Carp;

# module for pretty printing perl variables [for debugging]
use Data::Dumper;   #usage:  print Dumper($anyvariable, @another, %andanother);

# add local lib folder to perl library include search path
push(@INC, File::Spec->catdir($home_path, 'lib'));


# wrap rest of code in eval so we can trap and report errors nicely
$@ = undef;
$! = undef;
eval {

    require 'routing.pl';
    require 'params.pl';
    require 'util.pl';
    require 'template.pl';
    require 'http_status.pl';

    require 'logging.pl';
    require 'render.pl';
    require 'auth.pl';

    require 'serialise.pl';


    my $FALSE = 0;
    my $TRUE  = 1;


    #
    #   Application Configuration
    #

    # look for the required config file
    my $config_path = $ENV{'SUBSIFT_CONFIG'} || File::Spec->catdir($home_path, 'config');

    # disable logging until loaded settings and routes
    set_current_log_level('NONE');

    # create the settings hash_ref
    my $settings = _load_and_run(File::Spec->catfile($config_path, 'settings.pl'), 'settings', $home_path, $config_path);
    # make available to controllers/views and our own lib/*.pl files
    set_settings($settings);

    # create Rails-inspired url routing table array_ref
    my $routes = _load_and_run(File::Spec->catfile($config_path, 'routes.pl'), 'routes', $settings, $config_path);


    # make *_helper.pl files available for 'require' inclusion by controllers
    push(@INC, $settings->{'HELPERS_PATH'});

    # Template Toolkit input folders
    my @SETTING_TEMPLATE_PATHS = (
        $settings->{'VIEWS_PATH'},
        $settings->{'LAYOUTS_PATH'},
        $settings->{'TEMPLATES_PATH'},
    );
    template_config(\@SETTING_TEMPLATE_PATHS, $settings->{'OUTPUT_PATH'});  #OUTPUT_PATH is no longer defined/used

    # Control verbosity of messages sent to STDERR
    set_current_log_level($settings->{'LOG_LEVEL'} || 'INFO');


    #
    #   URL path + CGI parameter decoding and routing
    #

    my $remote_addr     = $ENV{'REMOTE_ADDR'} || '';
    my $http_user_agent = $ENV{'HTTP_USER_AGENT'} || '';

    my $path_info       = $ENV{'PATH_INFO'} || '';

    # fetch a copy of the cgi parameters
    my $raw_params = get_cgi_params();
    set_raw_params($raw_params);

    my $request_method = $ENV{'REQUEST_METHOD'} || 'get';
    # we adopt convention of request methods always being lower case
    $request_method = lc($request_method);
    # allow override of HTTP request method for clients that do not support (PUT, DELETE, HEAD)
    if (defined $raw_params->{'_method'}) {
        my $_method = lc( $raw_params->{'_method'} );
        # allow cgi override of get to head, or of post to put or delete
        if (($request_method eq 'get' && $_method eq 'head') ||
            ($request_method eq 'post' && ($_method eq 'put' || $_method eq 'delete')) ) {
            $request_method = $_method;
        }
    }
    # make effective method available to controllers
    set_request_method($request_method);

    info_message(uc($request_method) . ' ' . $path_info);

    # set flag so that we can detect if rendering has occurred in subsequent controllers/views
    set_performed_render($FALSE);

    # allow an xslt stylesheet url to be specified to go in the XML Decl of any xml serialisation
    if (defined $raw_params->{'xslt'}) {
        my $xslt_url = $settings->{'SITE_MEDIA'} . '/xslt/' . $raw_params->{'xslt'} . '.xsl';
        set_serialise_xslt($xslt_url);
    }

    # match url path and cgi parameters against route patterns, returning an augmented
    # hash_ref of params that usually includes keys for 'controller', 'action' and 'format'.
    my $params = parse_routes($path_info, $raw_params, $request_method, $routes, $settings->{'SUPPORTED_FORMATS_STR'});
    # make the params hash available via a global accessor (required for render())
    set_params($params);

    # set default serialisation options to reduce need to specify format & pretty for each call
    set_default_serialise_options({
        'format' => $params->{'format'}, 
        'pretty' => $params->{'pretty'},
    });

    # optionally, log params returned from the parse+match process
    if (get_current_log_level() >= log_level('INFO')) {
        my @msg = ();
        foreach my $k (sort keys %$params) {
            push(@msg, $k . '=' . $params->{$k});
        }
        if (scalar(@msg) > 0) {
            info_message('Params: ' . join(', ', @msg));
        }
    }

    # check whether the params validated okay against model of matching route
    my $error_message = get_params_error();
    if (defined $error_message) {
        # route match was found but parameters failed to validate against model
        info_message('params error: ' . $error_message);
        render({
            'status' => '404 Not Found',
            'text'   => serialise_error_message($error_message),
        });
        exit;
    }

    # if no controller specified, default to a catch-all controller
    if (!defined $params->{'controller'}) {
        $params->{'controller'} = 'default';
    }

    dispatch($settings, $params);

    # log execution time (includes our compilation time in this figure)
    my $benchmark_t1 = [gettimeofday];
    info_message(tv_interval($benchmark_t0, $benchmark_t1) . ' seconds');

    exit;



    sub dispatch {
        #
        #   Render following Rails-inspired controller, action, view scheme
        #
        my ($settings, $params) = @_;
    
        my $controller_subname = util_getValidSubName($params->{'controller'} || '');
        my $action_subname     = util_getValidSubName($params->{'action'} || '');

        # look for a controller shared by whole application (optional)
        _load_and_run(File::Spec->catfile($settings->{'CONTROLLERS_PATH'}, 'application_controller.pl'), 
                      'controller_application', $settings, $params);
        if (performed_render()) {return;}

        # look for a controller file of this name and call controller_<controller>
        _load_and_run(File::Spec->catfile($settings->{'CONTROLLERS_PATH'}, $params->{'controller'} . '_controller.pl'), 
                      'controller_' . $controller_subname, $settings, $params);
        if (performed_render()) {return;}

        # look for a controller file of this name and call action_<controller>_<action>
        debug_message("looking for 'action_${controller_subname}_$action_subname'");
        if (defined &{'action_' . $controller_subname . '_' . $action_subname} ) {

            # invoke action on this controller
            _load_and_run(File::Spec->catfile($settings->{'CONTROLLERS_PATH'}, $params->{'controller'} . '_controller.pl'), 
                          'action_' . $controller_subname . '_' . $action_subname, $settings, $params);
        }
        else {
            # look for a controller shared by whole application and call action_application_<action>
            debug_message("looking for 'action_application_$action_subname'");
            if (defined &{'action_application_' . $action_subname} ) {

                # invoke action on this controller
                _load_and_run(File::Spec->catfile($settings->{'CONTROLLERS_PATH'}, 'application_controller.pl'), 
                              'action_application_' . $action_subname, $settings, $params);
            }
            else {
                # look for a catch-all action: action_<controller>_unknown
                debug_message("looking for 'action_${controller_subname}_unknown'");
                if (defined &{'action_' . $controller_subname . '_unknown'} ) {
    
                    # invoke catch-all action: action_<controller>_unknown
                    _load_and_run(File::Spec->catfile($settings->{'CONTROLLERS_PATH'}, $params->{'controller'} . '_controller.pl'), 
                                  'action_' . $controller_subname . '_unknown', $settings, $params);
                }
                else {
                    # look for a catch-all action: action_application_unknown
                    debug_message("looking for 'action_application_unknown'");
                    if (defined &{'action_application_unknown'} ) {

                        # invoke catch-all action: action_application_unknown
                        _load_and_run(File::Spec->catfile($settings->{'CONTROLLERS_PATH'}, 'application_controller.pl'), 
                                      'action_application_unknown', $settings, $params);
                    }
                    else {
                        debug_message("no action '$action_subname'");
                    }
                }
            }
        }

        if (!performed_render()) {
            # render default document as default
            render({});
        }
    }#end dispatch


    sub _load_and_run {
        #
        # loads a perl file arg1 and calls a function arg2
        #
        my ($fname, $subname) = @_;
        shift; shift;  #consume first two args but keep rest
        my $ret = undef;
        # for logging we remove the site url stem to create relative urls
        my $relative_fname = substr($fname, length($home_path)+1);
        debug_message("looking for $relative_fname");
        if (-f $fname) {
            debug_message("found $relative_fname");
            require $fname;
            info_message("calling '$subname' in $relative_fname");
            no strict 'refs';
            $ret = &$subname(@_);
            use strict 'refs';
        }
        return $ret;
    }


    use vars qw($_Request_method);

    sub get_request_method {
        return $_Request_method;
    }

    sub set_request_method {
        my ($value) = @_;
        $_Request_method = $value;
    }

};#end of eval
if ($@) {
    handle_error($@);
} elsif ($!) {
    handle_error($!);
}


sub handle_error {
    my ($error_message) = @_;

    if ($ENV{'SERVER_NAME'} eq 'localhost') {
        # display debug information to browser
        #require 'debug.pl';
        #debug_handle_error($error_message);
    }
    # not running locally, so throw error 500
    die $error_message;
}