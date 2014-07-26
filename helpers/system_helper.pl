# system_helper.pl
use strict;
use warnings;

use URI::Escape;

require 'csv.pl';

my $FALSE = 0;
my $TRUE  = 1;


sub helper_parse_commands {
    #
    #   ARRAYREF helper_parse_commands(STRING $commands)
    #
    #   Parse string of text lines where each line is:
    #       flow, method, url[, parameters]
    #
    #   Returns an array of [flow, method, url, parameters] arrays.
    #
    my ($commands) = @_;
    my @commands = ();
    if (!defined $commands) {
        return \@commands;
    }

    my $err;
    eval{
        @commands = @{csv_parse_string($commands)};
    };
    if ($@) {
        $err = $@;
    } elsif ($!) {
        $err = $!;
    }
    if (defined $err) {
        warn_message('csv parse error: ' . $err);
        render({
            'status' => '400 Bad Request',
            'text'   => serialise_error_message('Invalid commands'),
        });
        return \@commands;
    }

    # verify that all rows parsed okay and that fields are as expected
    my $i = 0;
    foreach my $command (@commands) {
        $i++;
        # validate first three fields per line and treat rest as pairs of key=value parameters
        my $n = scalar(@$command);
        if ($n < 3) {
            render({
                'status' => '400 Bad Request',
                'text'   => serialise_error_message("Missing fields at line $i"),
            });
            return \@commands;
        }
        elsif ($n == 3) {
            # create a default parameters string
            $command->[3] = '';
        }

        if (!(defined $command->[0] && $command->[0] ne '' &&
              defined $command->[1] && $command->[1] ne '' &&
              defined $command->[2] && $command->[2] ne '' &&
              defined $command->[3])
           ) {
            render({
                'status' => '400 Bad Request',
                'text'   => serialise_error_message("Invalid command at line $i"),
            });
            return \@commands;
        }

        if ($command->[0] !~ m{^[\+\-\?\*]$}xsm) {
            render({
                'status' => '400 Bad Request',
                'text'   => serialise_error_message("Invalid flow symbol at line $i. Must be one of: +,-,?,*"),
            });
            return \@commands;
        }

        $command->[1] = lc($command->[1]);
        if ($command->[1] !~ m{^(get|delete|head|post|put)$}xsm) {
            render({
                'status' => '400 Bad Request',
                'text'   => serialise_error_message("Invalid HTTP method at line $i. Must be one of: get, delete, head, post, put"),
            });
            return \@commands;
        }
        
        # security: remove up-path ".." strings from path and then check not an absolute url
        $command->[2] =~ s{\.\.}{}gxsm;
        # strip off leading slashes
        $command->[2] =~ s{^/+}{}gxsm;
        if ($command->[2] =~ m{^\s*(http|ftp|mailto)}xsm) {
            render({
                'status' => '400 Bad Request',
                'text'   => serialise_error_message("Invalid SubSift API relative url at line $i."),
            });
            return \@commands;
        }
        
        #parse parameters into a hash of key=>value pairs
        my %parameters = ();
        LP_PAIRS:
        for(my $i=3; $i < scalar(@$command); $i++) {
#            my $pair = URI::Escape::uri_unescape($command->[$i]);
            my $pair = $command->[$i];
            $pair = util_trim($pair);
            if ($pair eq '') {
                next LP_PAIRS;
            }
            my ($key, $value) = ($pair =~ m/^\s*([A-Za-z0-9_]+)\s*=\s*(.+)\s*/xsm);
            if (!defined $key || !defined $value) {
                render({
                    'status' => '400 Bad Request',
                    'text'   => serialise_error_message("Invalid parameter key=value pair at line $i: $pair"),
                });
                return \@commands;
            }
            $parameters{$key} = $value;
        }
        
        # convert to a hash
        $command = {
            'flow'       => $command->[0],
            'method'     => $command->[1],
            'url'        => $command->[2],
            'parameters' => \%parameters,
            'index'      => $i,
        };
    }

    return \@commands;
}



1;