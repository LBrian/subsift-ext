# render.pl
use strict;
use warnings;

my $FALSE = 0;
my $TRUE  = 1;



use vars qw($_Performed_render);

sub performed_render {
    return $_Performed_render;
}

sub set_performed_render {
    my ($value) = @_;
    $_Performed_render = $value;
}


use vars qw($_Global_headers);

sub get_global_headers {
    return $_Global_headers;
}

sub set_global_headers {
    my ($value) = @_;
    $_Global_headers = $value;
}


sub render {
    #
    #   STRING render(HASHREF $options)
    #
    #   Options:
    #       action:             invoke action on current controller
    #       callback:           wrap json in function call
    #       content_type:       text/html, application/xml, etc.
    #       file:               renders file (without layout by default)
    #       format:             override file type otherwise derived from template (e.g. .p[html|xml|json])
    #       headers:            hash of http response header pairs (added to defaults)
    #       locals:             hash of local variables for template
    #       layout:             TRUE/FALSE embed content in current view. Or specify specific <layout>[.p<format>]
    #       partial:            render as a document fragment
    #       status:             http status code, either number or whole string (default='200 OK')
    #       suppress_response_codes: if TRUE, always returns '200 OK' irrespective of errors
    #       template:           file to use as template
    #       text:               print text without template
    #       to_string:          returns value as string instead of printing to output
    #
    #   Returns '' or, if 'to_string' then returns http response body as string
    #
    #   Note: assumes existence:
    #           - global getters for params and settings hash_refs
    #           - global boolean accessors to a performed_render flag
    #           - global string getter for request_method
    #
    #   Inspired by Ruby on Rails rendering, but with a healthy dose of simplification
    #   for ease of use. See http://api.rubyonrails.org/classes/ActionController/Base.html
    #
    my ($options) = @_;
    
    if (performed_render()) {
        die "Double render error!";
    }
    my $settings = get_settings();
    my $params = get_params();

    # deduce format from file extension of template
    my $template = $options->{'template'} || '__NONE__';
    my ($format) = ($template =~ /\.p([^.]+)$/);
    if (!defined $format) {
        $format = $options->{'format'} || $params->{'format'} || 'html';
        # validate format (ensuring we always support 'html' format)
        if ($format !~ m/^(?:html|$settings->{'SUPPORTED_FORMATS_STR'})$/xms) {
            # unrecognised/unsupported format, so convert render to an error message in default format
            $options->{'status'} = '400 Bad Request';
            $options->{'text'} = serialise_error_message("Unsupported format: $format");
            $format = $settings->{'DEFAULT_FORMAT'};
        }
        $template .= ".p${format}";
    }
 
    my $initial_status = $options->{'status'} || '200 OK';
    my $content_type = $options->{'content_type'} || $settings->{'CONTENT_TYPES'}{$format};
    if ($content_type !~ m/\;\s*charset=/i) {
        # default to utf-8 (FIXME: not tested for non-utf-8)
        $content_type .= '; charset=utf-8';
    }
    my $expires_time = expires_now_string('http');

    my $callback = $options->{'callback'} || $params->{'callback'} || $params->{'jsoncallback'} || undef;
    if ($format eq 'json' && defined $callback) {
        # override mime type to standard for jsonp (i.e. application/javascript) or get browser mimetype interpretation error
        $content_type = $options->{'content_type'} || $settings->{'CONTENT_TYPES'}{'js'};
    }

    my %response_header = (
        'Status' => $initial_status,
        'Content-Type' => $content_type,
        'Pragma' => 'no-cache',
        'Cache-Control' => 'no-cache, no-store, must-revalidate, pre-check=0, post-check=0',
        'Expires' => $expires_time,  # construct current time string
        'Date' => $expires_time,     # tell browser to use our clock so that Expires works as expected
    );
    my $global_headers = get_global_headers();
    if (defined $global_headers) {
        # merge in global response header pairs (e.g. Set-Cookie)
        while (my ($k,$v) = each(%$global_headers)) {
            $response_header{$k} = $v;
        }
    }
    if (defined $options->{'headers'}) {
        # merge in additional response header pairs
        while (my ($k,$v) = each(%{$options->{'headers'}})) {
            $response_header{$k} = $v;
        }
    }
    my $response_body = '';

    my $template_file = File::Spec->catfile($settings->{'VIEWS_PATH'}, $template);
    debug_message('looking for', $template_file);
    if (!-f $template_file) {
        my $controller = $params->{'controller'} || 'default';
        # if controller is not a folder in views then it may be a file
        if ( $controller ne 'default' && 
             !-d File::Spec->catdir($settings->{'VIEWS_PATH'}, $controller)) {
            # if controller folder does not exist then look for template of that name
            # so that default route ":controller/:action" finds templates in view root if no (or default) controller
            $template = "$controller.p$format";
            $controller = 'default';
        }
        $template_file = ($controller eq 'default')
            ? File::Spec->catfile($settings->{'VIEWS_PATH'}, $template)
            : File::Spec->catfile($settings->{'VIEWS_PATH'}, $controller, $template);
            debug_message('looking for', $template_file);
        if (!-f $template_file) {
            my $action = $options->{'action'} || $params->{'action'} || 'index';
            $template_file = ($controller eq 'default')
                ? File::Spec->catfile($settings->{'VIEWS_PATH'}, "${action}.p${format}")
                : File::Spec->catfile($settings->{'VIEWS_PATH'}, $controller, "${action}.p${format}");
            debug_message('looking for', $template_file);
            if (!-f $template_file) {
                # no template
                $template = undef;
                $template_file = undef;
                #FIXME: maybe throw an error or check if need to report problem
            }
        }
        if (defined $template_file) {
            # reconstruct a relative path suitable for template toolkit
            $template = File::Spec->abs2rel($template_file, $settings->{'VIEWS_PATH'});
            info_message("using template: $template");
        }
    }
    my %vars = (defined $options->{'locals'}) ? %{$options->{'locals'}} : ();
    
    # look for a layout
    my $layout = $params->{'controller'};
    if (defined $options->{'layout'}) {
        if ($options->{'layout'} eq '0') {      #layout = FALSE
            $layout = undef;
        }
        elsif ($options->{'layout'} eq '1') {   #layout = TRUE
            # accept default layout
        }
        else {
            # a specific layout template is given
            $layout = $options->{'layout'};
        }
    }
    else {
        # only templates automatically try to apply a layout
        if (!defined $template) {
            $layout = undef;
        }
    }
    if (defined $layout) {
        # look for a layout file
        if ($layout !~ /\.p([^.]+)$/) {
            $layout .= ".p${format}";
        }
        my $layout_file = File::Spec->catfile($settings->{'LAYOUTS_PATH'}, $layout);
        debug_message('looking for', $layout_file);
        if (!-f $layout_file) {
            debug_message('failed to find', $layout_file);
            $layout = "application.p${format}";
            $layout_file = File::Spec->catfile($settings->{'LAYOUTS_PATH'}, $layout);
            debug_message('looking for', $layout_file);
            if (!-f $layout_file) {
                debug_message('failed to find', $layout_file);
                $layout = undef;
                $layout_file = undef;
            }
        }
    }

#TODO: not implemented these three (not sure needed with Perl Template Toolkit):
#    if ($options->{'action'}) {
#       We're currently invoking actions on the current controller BEFORE calling render (which isn't what rails does)
#       See http://api.rubyonrails.org/classes/ActionController/Base.html
#    }
#    elsif ($options->{'partial'}) {
#       See http://api.rubyonrails.org/classes/ActionView/Partials.html
#    }
#    elsif ($options->{'file'}) {
#    }

    # initialise template parameters
    $vars{'site'} = {
        'name'      => $settings->{'SITE_NAME'},
        'url'       => $settings->{'SITE_URL'},
        'user_id'   => $params->{'user_id'},
        'media'     => $settings->{'SITE_MEDIA'},
    };

    # render main content
    if (defined $options->{'text'}) {
        if (defined $layout) {
            #FIXME: test if [% and %] in $options->{'text'} get evaluated (we don't want them to be)
            my $text = "[% WRAPPER $layout %]" . $options->{'text'} . "[% END %]";
            $response_body = template_to_string(\$text, \%vars);
        }
        else {
            $response_body = $options->{'text'};
        }
    }
    elsif (defined $template) {
        if (defined $layout) {
            my $text = "[% WRAPPER $layout %][% PROCESS '$template' %][% END %]";
            $response_body = template_to_string(\$text, \%vars);
        }
        else {
            $response_body = template_to_string($template, \%vars);
        }
    }
    
    # optionally, wrap content in a layout template (or, for json, a callback)
    if ($format eq 'json' && defined $callback) {
        $callback =~ s/[^A-Za-z\d_]//gxsm;  #protect against nasty CGI params
        $response_body = $callback . '(' . $response_body . ');';
    }
   
    if ($options->{'to_string'}) {
        # return a string instead of printing to STDOUT (and throw header away)
        return $response_body;
    }
    
    # support Flash and JavaScript applications running in browsers that intercept all non-200 responses
    if (exists $options->{'suppress_response_codes'} || exists $params->{'suppress_response_codes'}) {
        # always return 200 even if errors
        $response_header{'Status'} = '200 OK';
    }
    # expand numeric status code to full message (or validate if already a full message)
    $response_header{'Status'} = http_status_message($response_header{'Status'});
    
    $response_header{'Content-Length'} = length($response_body);

    # render http header followed by body
    foreach my $key (keys %response_header) {
        print "${key}: $response_header{$key}\n";
    }
    print "\n";
    print $response_body;

    # set global flag to inhibit further rendering calls
    set_performed_render($TRUE);

    return undef;
}


sub expires_now_string {
    #
    #   Returns current time as either a http header 
    #   Arg: $format   'http' for http headers or 'cookie' for cookies
    #
    my ($format) = @_;

    my @mons = qw/Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec/;
    my @wdays = qw/Sun Mon Tue Wed Thu Fri Sat/;

    my ($sec,$min,$hour,$mday,$mon,$year,$wday) = gmtime;
    $year += 1900;
    my $sc = ($format eq 'cookie') ? ' ' : '-';
    return 
        sprintf(
            "%s, %02d${sc}%s${sc}%04d %02d:%02d:%02d GMT",
            $wdays[$wday],$mday,$mons[$mon],$year,$hour,$min,$sec
        );
}


1;