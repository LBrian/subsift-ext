# settings.pl
use strict;
use warnings;


use vars qw($_Settings);

sub get_settings {
    return $_Settings;
}

sub set_settings {
    my ($value) = @_;
    $_Settings = $value;
}

sub get_setting {
    my ($key) = @_;
    return $_Settings->{$key};
}

sub settings {
    my ($home_path, $config_path) = @_;

    #
    # Allow override of settings() according to environment variable:
    #
    #    $ENV{'SUBSIFT_ENV'}     = 'development' | 'test' | 'production';
    #
    my $subsift_env = 'settings_' . ($ENV{'SUBSIFT_ENV'} ? $ENV{'SUBSIFT_ENV'} : 'production');
    my $settings_hashref = _load_and_run(
        File::Spec->catfile(
            $config_path, 
            $subsift_env . '.pl'
        ),
        $subsift_env, $home_path, $config_path
    );

    $settings_hashref->{'HOME_PATH'} = $home_path;
    $settings_hashref->{'CONFIG_PATH'} = $config_path;

    return $settings_hashref;
}

1;