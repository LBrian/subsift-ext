# settings_production.pl
use strict;
use warnings;

sub settings_production {
    my ($home_path) = @_;

    my %settings = (
        'LOG_LEVEL'             => 'DEBUG',  # Ranging from NONE < ERROR < WARN < INFO < DEBUG
                                            # Note: it is insecure to use DEBUG on the Web

        # dynamic user data
        'BIN_PATH'              => File::Spec->catdir($home_path, 'bin'),
        'WORK_PATH'             => File::Spec->catdir($home_path, 'work'),
        'USERS_PATH'            => File::Spec->catdir($home_path, 'work', 'users'),
        'CACHE_PATH'            => File::Spec->catdir($home_path, 'work', 'cache'),
        'SOFT_DELETE'           => 1,  # 0=FALSE, 1=TRUE
        'ACCESS_LOG'            => File::Spec->catfile($home_path, 'work', 'log', 'access_log'),
        'ROBOT_LOG'             => File::Spec->catfile($home_path, 'work', 'log', 'robot_log'),
        'WORKFLOW_LOG'          => File::Spec->catfile($home_path, 'work', 'log', 'workflow_log'),

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
    
        'ROBOT_TITLE'           => 'ILRT-SubSift-Harvester/1.0',
        'ROBOT_EMAIL'           => 'simon.price@bristol.ac.uk',
    
        # helper applications
#        'GRAPHVIZ_PATH'         => '/usr/local/bin',
        'GRAPHVIZ_PATH'         => '/usr/bin',

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
