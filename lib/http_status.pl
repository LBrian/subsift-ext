# http_status.pl 
# Note: we use this in preference to HTTP::Status because of variablility of constant naming between versions
use strict;
use warnings;

# following HTTP status messages are from HTTP::Status
my %StatusCode = (
    100 => 'Continue',
    101 => 'Switching Protocols',
    102 => 'Processing',                      # RFC 2518 (WebDAV)
    200 => 'OK',
    201 => 'Created',
    202 => 'Accepted',
    203 => 'Non-Authoritative Information',
    204 => 'No Content',
    205 => 'Reset Content',
    206 => 'Partial Content',
    207 => 'Multi-Status',                    # RFC 2518 (WebDAV)
    300 => 'Multiple Choices',
    301 => 'Moved Permanently',
    302 => 'Found',
    303 => 'See Other',
    304 => 'Not Modified',
    305 => 'Use Proxy',
    307 => 'Temporary Redirect',
    400 => 'Bad Request',
    401 => 'Unauthorized',
    402 => 'Payment Required',
    403 => 'Forbidden',
    404 => 'Not Found',
    405 => 'Method Not Allowed',
    406 => 'Not Acceptable',
    407 => 'Proxy Authentication Required',
    408 => 'Request Timeout',
    409 => 'Conflict',
    410 => 'Gone',
    411 => 'Length Required',
    412 => 'Precondition Failed',
    413 => 'Request Entity Too Large',
    414 => 'Request-URI Too Large',
    415 => 'Unsupported Media Type',
    416 => 'Request Range Not Satisfiable',
    417 => 'Expectation Failed',
    422 => 'Unprocessable Entity',            # RFC 2518 (WebDAV)
    423 => 'Locked',                          # RFC 2518 (WebDAV)
    424 => 'Failed Dependency',               # RFC 2518 (WebDAV)
    425 => 'No code',                         # WebDAV Advanced Collections
    426 => 'Upgrade Required',                # RFC 2817
    449 => 'Retry with',                      # unofficial Microsoft
    500 => 'Internal Server Error',
    501 => 'Not Implemented',
    502 => 'Bad Gateway',
    503 => 'Service Unavailable',
    504 => 'Gateway Timeout',
    505 => 'HTTP Version Not Supported',
    506 => 'Variant Also Negotiates',         # RFC 2295
    507 => 'Insufficient Storage',            # RFC 2518 (WebDAV)
    509 => 'Bandwidth Limit Exceeded',        # unofficial
    510 => 'Not Extended',                    # RFC 2774
);

sub http_status_message {
    #
    #   STRING http_status_message(STRING $str)
    #
    #   $str is either an HTTP status code (e.g. 200) or a full status message (e.g. '200 OK').
    #   Returns: full error message (e.g. '200 OK').
    #
    #   If a full status message is passed in it will be checked for validity.
    #
    my ($str) = @_;
    if (exists $StatusCode{$str}) {
        # expand to full HTTP return message
        $str .= ' ' . $StatusCode{$str}
    }
    else {
        # accept already expanded messages so long as valid
        my ($code, $message) = ($str =~ m{^(\d\d\d)\ (.+)}xms);
        if (defined $code && defined $message && $StatusCode{$code} eq $message) {
            # we have a valid status message, so safe to allow its return
        }
        else {
            die "Invalid status code/message: $str";
        }
    }
    return $str;
}


1;


=head not using following at moment...

my %_HTTP_StatusCode = (
    'CONTINUE'                      => '100 Continue',
    'SWITCHING_PROTOCOLS'           => '101 Switching Protocols',
    'PROCESSING'                    => '102 Processing',                      # RFC 2518 (WebDAV)
    'OK'                            => '200 OK',
    'CREATED'                       => '201 Created',
    'ACCEPTED'                      => '202 Accepted',
    'NON_AUTHORITATIVE_INFORMATION' => '203 Non-Authoritative Information',
    'NO_CONTENT'                    => '204 No Content',
    'RESET_CONTENT'                 => '205 Reset Content',
    'PARTIAL_CONTENT'               => '206 Partial Content',
    'MULTI_STATUS'                  => '207 Multi-Status',                    # RFC 2518 (WebDAV)
    'MULTIPLE_CHOICES'              => '300 Multiple Choices',
    'MOVED_PERMANENTLY'             => '301 Moved Permanently',
    'FOUND'                         => '302 Found',
    'SEE_OTHER'                     => '303 See Other',
    'NOT_MODIFIED'                  => '304 Not Modified',
    'USE_PROXY'                     => '305 Use Proxy',
    'TEMPORARY_REDIRECT'            => '307 Temporary Redirect',
    'BAD_REQUEST'                   => '400 Bad Request',
    'UNAUTHORIZED'                  => '401 Unauthorized',
    'PAYMENT_REQUIRED'              => '402 Payment Required',
    'FORBIDDEN'                     => '403 Forbidden',
    'NOT_FOUND'                     => '404 Not Found',
    'METHOD_NOT ALLOWED'            => '405 Method Not Allowed',
    'NOT_ACCEPTABLE'                => '406 Not Acceptable',
    'PROXY_AUTHENTICATION REQUIRED' => '407 Proxy Authentication Required',
    'REQUEST_TIMEOUT'               => '408 Request Timeout',
    'CONFLICT'                      => '409 Conflict',
    'GONE'                          => '410 Gone',
    'LENGTH_REQUIRED'               => '411 Length Required',
    'PRECONDITION_FAILED'           => '412 Precondition Failed',
    'REQUEST_ENTITY TOO LARGE'      => '413 Request Entity Too Large',
    'REQUEST_URI_TOO LARGE'         => '414 Request-URI Too Large',
    'UNSUPPORTED_MEDIA TYPE'        => '415 Unsupported Media Type',
    'REQUEST_RANGE NOT SATISFIABLE' => '416 Request Range Not Satisfiable',
    'EXPECTATION_FAILED'            => '417 Expectation Failed',
    'UNPROCESSABLE_ENTITY'          => '422 Unprocessable Entity',            # RFC 2518 (WebDAV)
    'LOCKED'                        => '423 Locked',                          # RFC 2518 (WebDAV)
    'FAILED_DEPENDENCY'             => '424 Failed Dependency',               # RFC 2518 (WebDAV)
    'NO_CODE'                       => '425 No code',                         # WebDAV Advanced Collections
    'UPGRADE_REQUIRED'              => '426 Upgrade Required',                # RFC 2817
    'RETRY_WITH'                    => '449 Retry with',                      # unofficial Microsoft
    'INTERNAL_SERVER ERROR'         => '500 Internal Server Error',
    'NOT_IMPLEMENTED'               => '501 Not Implemented',
    'BAD_GATEWAY'                   => '502 Bad Gateway',
    'SERVICE_UNAVAILABLE'           => '503 Service Unavailable',
    'GATEWAY_TIMEOUT'               => '504 Gateway Timeout',
    'HTTP_VERSION NOT SUPPORTED'    => '505 HTTP Version Not Supported',
    'VARIANT_ALSO NEGOTIATES'       => '506 Variant Also Negotiates',         # RFC 2295
    'INSUFFICIENT_STORAGE'          => '507 Insufficient Storage',            # RFC 2518 (WebDAV)
    'BANDWIDTH_LIMIT EXCEEDED'      => '509 Bandwidth Limit Exceeded',        # unofficial
    'NOT_EXTENDED'                  => '510 Not Extended',                    # RFC 2774
);

sub http_status_message {
    my ($id) = @_;
    if (!exists $_HTTP_StatusCode{$id}) {
        die "Invalid status code id: $id";
    }
    return $_HTTP_StatusCode{$id};
}
=cut

