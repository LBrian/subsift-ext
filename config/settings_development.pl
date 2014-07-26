# settings_development.pl
use strict;
use warnings;

sub settings_development {
    my ($home_path) = @_;

    # optionally, change $work to keep work dir out of workspace
    my $work = $home_path;
    
    my %settings = (
        'LOG_LEVEL'             => 'INFO',  # Ranging from NONE < ERROR < WARN < INFO < DEBUG
                                            # Note: it is insecure to use DEBUG on the Web

        # dynamic user data
        'WORK_PATH'             => File::Spec->catdir($work),
        'USERS_PATH'            => File::Spec->catdir($work, 'users'),
        'CACHE_PATH'            => File::Spec->catdir($work, 'cache'),
        'SOFT_DELETE'           => 0,  # 0=FALSE, 1=TRUE
        'ACCESS_LOG'            => File::Spec->catfile($work, 'log', 'access_log'),
        'ROBOT_LOG'             => File::Spec->catfile($work, 'log', 'robot_log'),
        'WORKFLOW_LOG'          => File::Spec->catfile($work, 'log', 'workflow_log'),

        'CONTROLLERS_PATH'      => File::Spec->catdir($home_path, 'controllers'),
        'HELPERS_PATH'          => File::Spec->catdir($home_path, 'helpers'),

        # Template Toolkit templates folder
        'TEMPLATES_PATH'        => File::Spec->catdir($home_path, 'templates'),
        'VIEWS_PATH'            => File::Spec->catdir($home_path, 'views'),
        'LAYOUTS_PATH'          => File::Spec->catdir($home_path, 'views', 'layouts'),

        # Site details
        'SITE_NAME'             => 'SubSift',
        'SITE_URL'              => 'http://localhost',
        'SITE_MEDIA'            => 'http://localhost',
        'SITE_URI_BASE'         => 'sift:',
    
        'ROBOT_TITLE'           => 'SubSift-Harvester/1.3',
        'ROBOT_EMAIL'           => 'your@email.goes.here',
        
        # helper applications
        'GRAPHVIZ_PATH'         => '/usr/local/bin',

        # Serialisable formats
        #FIXME: should distinguish here (and in rest of code) between serialisable formats and servable formats.
        'DEFAULT_FORMAT'        => 'xml',
        'SUPPORTED_FORMATS_STR' => 'csv|dot|html|jpg|jpeg|js|json|pdf|png|rdf|svg|terms|txt|xml|yaml|zip',
        'CONTENT_TYPES'         => {
                                        'csv'   =>  'text/csv',
                                        'dot'   =>  'text/x-graphviz',
                                        'html'  =>  'text/html',
                                        'jpg'   =>  'image/jpeg',
                                        'jpeg'  =>  'image/jpeg',
                                        'js'    =>  'application/javascript',
                                        'json'  =>  'application/json',
                                        'pdf'   =>  'application/pdf',
                                        'png'   =>  'image/png',
                                        'rdf'   =>  'application/rdf',
                                        'svg'   =>  'image/svg+xml',
                                        'terms' =>  'application/prolog',
                                        'txt'   =>  'text/plain',
                                        'xml'   =>  'application/xml',
                                        'yaml'  =>  'application/yaml',
                                        'zip'   =>  'application/zip',
                                   },
 
    );
    $settings{'CONTENT_FORMATS'} = util_invert_hash($settings{'CONTENT_TYPES'});

    return \%settings;
}

1;
