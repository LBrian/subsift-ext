use strict;

# this controller is shared by the whole application

sub controller_application {
    my ($settings, $params) = @_;

    # compare request credentials against those for user namespace (if user_id is specified)
    authenticate($settings, $params);

    # for user namespaces must be authenticated to do any write operations or if private
    if (exists $params->{'user_id'} && defined $params->{'user_id'}) {
        my $method = get_request_method();
        if ($method eq 'post' || $method eq 'put' || $method eq 'delete') {
            # insist that request is authenticated
            error_unless_authenticated($settings, $params);
        }
        else {
            # method is get/head/location
            my $user_info = get_user_info();
            if (defined $user_info && $user_info->{'mode'} eq 'private') {
                # insist that request is authenticated
                error_unless_authenticated($settings, $params);
            }
        }
        # NB. Other controllers can insist on authentication even though passed this test.
        #     That allows them to perform fine grained control over resource access.
    }
}


#EXAMPLE...
#sub action_application_index {
#    my ($settings, $params) = @_;
#
#    render({ 'template' => 'index' });    
#}


sub action_application_wrong_method {
    #
    # routes assign this action if wrong http method is used for the matched route
    #
    my ($settings, $params) = @_;

    render({
        'status' => '400 Bad Request',
        'text'   => serialise_error_message('Wrong http method for this action: ' . get_request_method()),
    });
}


#EXAMPLE...
#NOTE: not using in SubSift because would need to check not a non-action template page - eg. one of the /api/... urls
#sub action_application_unknown {
#    #
#    # this action is invoked if the expected action does not exist
#    #
#    my ($settings, $params) = @_;
#
#    my $action_unescaped = $params->{'action'} || 'undef';
#    
#    render({
#        'status' => '400 Bad Request',
#        'text'   => serialise_error_message("Unknown action: $action_unescaped"),
#    });
#}


1;