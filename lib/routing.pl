# routing.pl
use strict;
use warnings;

require 'logging.pl';

my $FALSE = 0;
my $TRUE  = 1;


sub parse_routes {
    #
    #   STRING_HASHREF $params parse_routes(
    #       STRING $path_info,
    #       STRING_HASHREF $cgi_params_hashref, 
    #       STRING $request_method,
    #       ARRAYREF $routes_arrayref,
    #       STRING $file_extensions
    #   )
    #
    # $path_info is the part of the url after the root or script name.
    # $cgi_params_hashref is a copy of a cgi params hash.
    # $request_method is one of: 'get', 'post', 'put', 'delete', 'any'.
    # $routes_arrayref is a Rails-inspired routing table (see Ruby on Rails 2
    # docs: http://api.rubyonrails.org/classes/ActionController/Routing.html
    # and user guide at: http://guides.rubyonrails.org/routing.html).
    # In Rails 3 see, http://api.rubyonrails.org/classes/ActionDispatch/Routing.html
    # Old Rails 2 docs at http://apidock.com/rails/v2.3.8/ActionController/Routing
    #
    # Returns a hash containing key-value pairs from $cgi_params augmented 
    # with key-value pairs extracted from the first matching route pattern.
    #
    my ($path_info, $cgi_params_hashref, $request_method, $routes_arrayref, $file_extensions) = @_;

    if (defined $file_extensions && $file_extensions !~ m{^(?:[a-z]+\|)*[a-z]+$}xms) {
        die 'parse_routes: invalid file_extension string. A valid example is: "rss|xml|yaml"';
    }

    # strip off leading slash if there is one
    if (substr($path_info,0,1) eq '/') {
        $path_info = substr($path_info,1);
    }

    my ($url_parts, $url_extension_ix) = _split_route($path_info, $file_extensions);
    my $noof_url_parts = scalar @$url_parts;

    my $mismatch;
    my %params = ();

    LP_CHECK_PATTERNS:
    foreach my $route_arrayref (@$routes_arrayref) {
        my $pattern          = $route_arrayref->[0];
        my $pattern_args     = $route_arrayref->[1];

        my $instantiated_pattern = '';

        my ($pattern_parts, $pattern_extension_ix) = _split_route($pattern, $file_extensions);

        # %$actions is not part of rails. It is a hash mapping from request_method to action name (to more elegantly support REST)
        # Actions are http_method=>action pairs, where http_method is one of 'get', 'post', 'put', 'delete', 'any'.
        # These also act as conditions for the pattern - i.e. the pattern will only match iff the method matches or 'any' is used.
        my $actions       = (exists $pattern_args->{'actions'}) 
                            ?   $pattern_args->{'actions'}
                            :   {};
                            
        my $conditions    = (exists $pattern_args->{'conditions'}) 
                            ?   $pattern_args->{'conditions'}
                            :   {};
        my $defaults      = (exists $pattern_args->{'defaults'}) 
                            ?   $pattern_args->{'defaults'}
                            :   {};
        my $requirements  = (exists $pattern_args->{'requirements'}) 
                            ?   $pattern_args->{'requirements'}
                            :   {};
        #FIXME: requirements does not report error if string does not start+end with slash
        #FIXME: requirements should just be a standard Perl regex, not a string. Will be more efficient.

        $mismatch = 0;  #false

        # if a request method is specified then must match (default is 'any') 
        if ( exists $conditions->{'method'} && $conditions->{'method'} ne 'any' 
             && $conditions->{'method'} ne $request_method) {
            # failed to match request method
            $mismatch = 1;
        }

        # if actions mapping is specified then only match if request_method matches (or if 'any' allowed)
        if ( exists $pattern_args->{'actions'} &&
             !exists $actions->{'any'} &&
             !exists $actions->{$request_method}
           ) {
            # failed to match request methods for which actions are specified
            $mismatch = 2;
        }

        my $noof_pattern_parts = scalar @$pattern_parts;
        LP_CHECK_PARTS:
        for(my $i=0; !$mismatch && $i < $noof_pattern_parts; $i++) {
            my $pattern_part = $pattern_parts->[$i];
            if (!$pattern_part) {
                die "ROUTING ERROR: Illegal route pattern (in part $i): $pattern\n";
            }
            my $partname;
            if ($pattern_part =~ m/^:([A-Za-z][A-Za-z\d_\-]*)$/xms) {
                # :partname
                $partname = $1;
                # while still any url parts left, use those and then fall back on cgi params

                my $regex;
                if (exists $pattern_args->{$partname} && $pattern_args->{$partname} =~ m{^/([^/]+)/$}xms) {
                    $regex = $1;
                }
                elsif (exists $requirements->{$partname} && $requirements->{$partname} =~ m{^/([^/]+)/$}xms) {
                    $regex = $1;
                }
                
                my $candidate;

                # if url part is the terminal .ext extension, stop its consumption by a non-terminal pattern variable
                if ($i == $url_extension_ix && $i < ($noof_pattern_parts - 1)) {
                    # reached url .ext extension so any non-terminal variable match must now come from cgi params
                    if (exists $cgi_params_hashref->{$partname}) {
                        $candidate = $cgi_params_hashref->{$partname};
                        # allow consumption of .ext but transfer its value to a 'format' cgi parameter (or is lost)
                        # so that .ext can be used even when rest of params supplied as cgi
                        $cgi_params_hashref->{'format'} = $url_parts->[$i];
                    }
                    else {
                        $mismatch = 3;
                        last LP_CHECK_PARTS;
                    }
                }
                
                if (!defined $candidate) {
                    $candidate = ($i < $noof_url_parts)
                        ? $url_parts->[$i] 
                        : ((exists $cgi_params_hashref->{$partname}) ? $cgi_params_hashref->{$partname} : undef);
                }
                if (defined $candidate) {
                    #
                    # found corresponding part of url for this part of pattern
                    #
                    if (defined $regex) {
                        # check constraining regex requirements on this part
                        if ($candidate !~ m/^($regex)$/xms) {
                            # url part failed to match against regex
                            $mismatch = 4;
                            last LP_CHECK_PARTS;
                        }
                    }
                    if ( ($partname eq 'controller' || $partname eq 'action')
                         && $candidate !~ m{^[A-Za-z][A-Za-z\d_\-]*$}xms          #FIXME: controllers in Rails support '/' in their names to support subdirs
                            #FIXME: "-" isn't a valid perl subroutine name character, so we need to remap it somewhere (possibly here)
                       ) {
                        # url part failed to meet our requirements for a valid Perl sub name
                        $mismatch = 5;
                        last LP_CHECK_PARTS;
                    }
                    $params{$partname} = $candidate;
                }
                else {
                    #
                    # no corresponding part of url for this part of pattern
                    #
                    
                    # ensure .ext values not lost and replaced by default and ensure requirements checked later
                    if ($partname eq 'format' && $url_extension_ix >= 0) {
                        # ensure .ext is not replaced by default
                        $cgi_params_hashref->{$partname} = $url_parts->[$url_extension_ix];
                    }
                    
                    my $default;
                    if (exists $pattern_args->{$partname} && $pattern_args->{$partname} !~ m{^/[^/]+/$}xms) {
                        $default = $pattern_args->{$partname};
                    }
                    elsif (exists $cgi_params_hashref->{$partname}) {
                        $default = $cgi_params_hashref->{$partname};
                        # check constraining regex requirements on this cgi param
                        if ($default !~ m/^($regex)$/xms) {
                            # url part failed to match against regex
                            $mismatch = 6;
                            last LP_CHECK_PARTS;
                        }
                    }
                    elsif (exists $defaults->{$partname} && $defaults->{$partname} !~ m{^/[^/]+/$}xms) {
                        $default = $defaults->{$partname};
                    }

                    if (defined $default) {
                        if ($default eq 'nil') {
                            # do not set a value for this part if not provided by url (ie. do nothing)
                        }
                        else {
                            # use default value specified for this part
                            $params{$partname} = $default;
                        }
                    }
                    else {
                        # auto defaults (NB. to stop these, you must add an explicit default of nil)
                        if ($partname eq 'action') {
                            $params{$partname} = 'index';
                        }
                        elsif ($partname eq 'id') {
                            $params{$partname} = 'nil';
                        }
                        elsif (exists $requirements->{$partname}) {
                            # no corresponding url part so required partname can not match regex
                            $mismatch = 7;
                            last LP_CHECK_PARTS;
                        }
                        else {
                            die "FIXME: not sure if should throw bad url error here because we have a partname that has no corresponding default?";
                        }
                    }
                }

            }
            elsif ($pattern_part =~ m/^\*([A-Za-z][A-Za-z\d_\-]+)$/xms) {
                # *name
                $partname = $1;
#FIXME: decide whether to use \0 or stick with simpler / separator (the latter requires no changes to params.pl for model validation)
#                # consume rest of url parts (returning multiple values as "\0" delimited string)
#                $params{$partname} = join("\0", @$url_parts[$i..$noof_url_parts-1]);
#                last LP_CHECK_PARTS;
                # consume rest of url parts up to file extension (returning multiple values as "/" delimited string)
                my $maxpart = ($url_extension_ix < 0) ? $noof_url_parts : $url_extension_ix;
                if ($i > ($maxpart-1)) {
                    # empty value, so leave for default to supply later if one is defined
                    next LP_CHECK_PARTS;
                }
                $params{$partname} = join('/', @$url_parts[$i..$maxpart-1]);
                # replace all url parts up to, but excluding, the extension with concatenated value
                my @lis = ($params{$partname}, );
                if ($url_extension_ix >= 0) {
                    push(@lis, $url_parts->[$url_extension_ix]);
                }
                splice(@$url_parts, $i, $maxpart-1, @lis);
                $noof_url_parts = scalar @$url_parts;
            }
            elsif ($i < $noof_url_parts && $pattern_part eq $url_parts->[$i]) {
                # matched literal part of pattern
                $instantiated_pattern .= '/' . $pattern_part;
                # continue loop (ie. do nothing)
                next LP_CHECK_PARTS;
            }
            else {
                # failed to match against whole pattern
                $mismatch = 8;
                last LP_CHECK_PARTS;
            }
            if ($partname ne 'format') {
                $instantiated_pattern .= '/' . $params{$partname};
            }
        } #for LP_CHECK_PARTS

        # did this pattern match the url?
        if (!$mismatch) {
            # matched, so check and merge in other values and if ok, quit loop
            
            # merge in any remaining defaults (or if requirement, check met by a cgi param)
            LP_DEFAULTS:
            foreach my $partname (keys %{$pattern_args}) {
                if ( $partname ne 'actions' &&
                     $partname ne 'conditions' &&
                     $partname ne 'defaults' &&
                     $partname ne 'requirements' && 
                     !(exists $params{$partname})
                   ) {
                    # if regex then must check if cgi param meets requirement
                    if ($pattern_args->{$partname} =~ m{^/([^/]+)/$}xms) {
                        my $value = $cgi_params_hashref->{$partname};
                        if (!defined $value) {
                            die "Cannot check values of ':$partname' because it does not occur in routing pattern: '$pattern'";
                        }
                        if ($value !~ m/^($1)$/xms) {
                            # url part failed to match against regex
                            $mismatch = 9;
                            last LP_DEFAULTS;
                        }
                    }
                    else {
                        # not a regex, so treat as default value
                        $params{$partname} = $pattern_args->{$partname};
                    }
                }
            }
            if (!$mismatch) {
                # check requirements are all met, including checking for missing cgi-params
                LP_REQUIREMENTS:
                foreach my $key (keys %$requirements) {
                    if (!exists $params{$key}) {
                        my $value = $cgi_params_hashref->{$key};
                        my ($regex) = ($requirements->{$key} =~ m{^/([^/]*)/$});
                        if (defined $regex && (!defined $value || $value !~ m/^($regex)$/xms)) {
                            # url part failed to match against regex
                            $mismatch = 10;
                            last LP_REQUIREMENTS;
                        }
                    }
                }
                if (!$mismatch) {
                    # merge in any cgi params that do not clash with already assigned keys
                    foreach my $key (keys %$cgi_params_hashref) {
                        if (!exists $params{$key}) {
                            $params{$key} = $cgi_params_hashref->{$key};
                        }
                    }
                }
            }
        }
        
        if ($mismatch) {
            debug_message("routing mismatch $mismatch: $pattern");

            # clear out partly-completed hash
            %params = ();
        }
        else {
            #
            # matched pattern
            #
            debug_message("routing match $pattern");
            $params{'route'} = $pattern;
            $params{'path'}  = $instantiated_pattern;
            
            # apply actions mapping from request_method to action name if defined  (this is not part of Rails)
            if (exists $actions->{$request_method}) {
                $params{'action'} = $actions->{$request_method};
            }
            elsif (exists $actions->{'any'}) {
                $params{'action'} = $actions->{'any'};
            }
            elsif (!defined $params{'action'}) {
                $params{'action'} = 'nil';
            }
            
            # optional, additional validation of parameters against model  (this is not part of Rails)
            set_params_error(undef);
            if (exists $pattern_args->{'models'} && $params{'action'} ne 'nil') {
                my $models = $pattern_args->{'models'};
                # unpack action prototype as action and its list of argument ids
                my @ids = split(/\W/, $params{'action'});
                $params{'action'} = shift @ids;
                # delete any params not listed in prototype list of argument ids (or a reserved id)
                my %allowed = map { ($_, 1) } (@ids, 'controller', 'action', 'id', 'format', 'route', 'path', 'pretty', 'callback', 'jsoncallback', 'suppress_response_codes');
                foreach my $key (keys %params) {
                    if (!exists $allowed{$key}) {
                        delete $params{$key};
                    }
                }
                # validate each param against model
                LP_VALIDATE:
                for my $key (@ids) {
                    if (exists $models->{$key}) {
                        # pre-process BOOL types to map html web form checkbox missing|STR to 0|1
                        if ($models->{$key}{'type'} eq 'BOOL') {
                            if (exists $params{$key}) {
                                # value present => possibly a checkbox that is checked, in which case an 'on' string is sent by the form
                                if ($params{$key} ne "$FALSE") {
                                    # replace the string with true value
                                    $params{$key} = "$TRUE";
                                }
                            }
                            else {
                                # value missing => possibly a checkbox that is unchecked (no value would be sent by the form)
                                if (!exists $models->{$key}{'required'} || $models->{$key}{'required'} eq "$FALSE") {
                                    # model did not explicitly require a parameter, so now check if a default
                                    if (!exists $models->{$key}{'default'} || $models->{$key}{'default'} eq "$FALSE") {
                                        # create the missing param value
                                        $params{$key} = "$FALSE";
                                    }
                                }
                            }
                        }
                        #
                        # check each value against model
                        #
                        $models->{$key}{'severity'} = 'IGNORE';
                        $params{$key} = params_model(\%params, $key, $models->{$key});
                        my $error = get_params_error();
                        if (defined $error) {
                            # model violation detected and an error message rendered
                            last LP_VALIDATE;
                        }
                    }
                }
            }
            
            last LP_CHECK_PATTERNS;
        }

    } #for all patterns
    
    return \%params;
}


sub _split_route {
    #
    #   (STRING_ARRAYREF, INT) _split_route(STRING $route, STRING $file_extensions)
    #
    #   Splits string on '/' or '.' but will only split on '.' if followed by either
    #       - a colon (eg. for .:format)
    #       - a file extension from $file_extensions (eg. 'csv|xml|yaml')
    #
    #   These exceptions allow the inclusion of '.' in url parts without ambiguity
    #
    my ($route, $file_extensions) = @_;

#    my $mysteryPerlQuirkDummyAssignment = $route; #FIXME: perl quirk requires a copy taking of passed in string. Unless this is done (or the variable instantiated in some other way, such as printing it!) then subsequent route matches fail when format is passed in as a cgi string. I suspect that this issue is only a secondary side effect of some other bug but its hard to track down if printing a variable to STDERR affects the behaviour of the program. However, it could be that I'm misunderstanding the reference. Note that this dummy assignment can instead be put after the call to _split_route as:  my $foo = $route_arrayref->[0];  which suggests that there is something unexpected happening with the scope/memory/reference for this array item (which is a literal string from routes.pl).
#Fixed now?: could have been related to character encoding issues (now fixed), as it doesn't seem to happen any more!?

    # split off any trailing file extension
    my $extension;
    if (defined $file_extensions && $file_extensions =~ m{^(?:[a-z]+\|)*[a-z]+$}xms) {
        my ($route2, $extension2) = ($route =~ m{^(.*)\.($file_extensions)$}xms);
        if (defined $route2 && defined $extension2) {
            $route = $route2;
            $extension = $extension2;
        }
    }

    # split everything up on '/' or '.' provided dot is followed by colon
    my @route_parts = split(m{/|(?:[.](?=[:]))}, $route);
    if (scalar(@route_parts) == 0) {
        push(@route_parts, $route);
    }

    # restore the file extension if there was one
    my $extension_ix = -1;
    if (defined $extension) {
        $extension_ix = scalar(@route_parts);
        push(@route_parts, $extension);
    }


    return (\@route_parts, $extension_ix);
}

1;