#!/usr/bin/perl -w
#
#   harvest.pl
#
use strict;
use warnings;
use diagnostics;

my $start_time = time;

# only harvest for a maximum of N seconds (because running via cron)
##FIXME: move out to config so can adjust on per platform basis to suit cron interval
my $EXECUTION_TIMEOUT = 180;

use FindBin qw($RealDir);
my $home_path = $RealDir;
# optionally, if in a *nix /bin folder, assume home is parent
$home_path =~ s{/bin$}{};

use File::Path qw(mkpath rmtree);  #warning: newer version of File::Path renames these as qw(make_path remove_tree)
use File::Basename qw(dirname);
use File::Spec;

use File::Glob ':glob';

#use Encode;
#require Encode::Detect;

# module for pretty printing perl variables [for debugging]
use Data::Dumper;   #usage:  print Dumper($anyvariable, @another, %andanother);

# add local lib folder to perl library include search path
push(@INC, File::Spec->catdir($home_path, 'lib'));
push(@INC, $home_path);

require 'util.pl';
require 'logging.pl';

use JSON;

my $FALSE = 0;
my $TRUE  = 1;

my $INFO_FILENAME = '_info.js';
my $DATA_FILENAME = '_data.js';

my $DOCUMENT_FILE_EXTENSION = '.js';

my $settings;
{
    #
    # read application configuration
    #
    my $config_path = $ENV{'SUBSIFT_CONFIG'} || File::Spec->catdir($home_path, 'config');
    $settings = _load_and_run(File::Spec->catfile($config_path, 'settings.pl'), 'settings', $home_path, $config_path);
}
# make available to lib/*.pl files
set_settings($settings);


# poll all user documents looking for specially named files requesting an http get of a url
my $filespec = File::Spec->catdir($settings->{'USERS_PATH'}, '*', 'documents', '*', '__*.js');
my @files = bsd_glob($filespec);
LP_MANIFEST:
for my $manifest_file (@files) {


    my $relative_manifest_file = substr($manifest_file, length($settings->{'USERS_PATH'})+1);
    my $manifest = _load_manifest($manifest_file);
    if (!defined $manifest) {
        # as a failsafe, remove any empty manifest files so we don't keep reparsing them
        unlink $manifest_file;
        next LP_MANIFEST;
    }
    my ($user_id, $folder_id) = ($relative_manifest_file =~ m{^([^/]+)/documents/([^/]+)/}xsm);

    # breadth-first search parameters
    my $breadth = $manifest->{'breadth'};
    my $depth = $manifest->{'depth'};
    my $current_depth = $manifest->{'current_depth'};
    my $same_domain = $manifest->{'same_domain'};
    my $same_stem = $manifest->{'same_stem'};
    # threshold for choosing which links to crawl (links are ranked by their idf against peer links at same depth)
    my $threshold = $manifest->{'threshold'};
    my $remove_html = $manifest->{'remove_html'};

    # list of starting urls (each with its own queue of urls to fetch and list of child links)
    my $bookmarks = $manifest->{'bookmark'};
    if (!(defined $bookmarks) || scalar(@$bookmarks) == 0) {
        # as a failsafe, remove any empty manifest files so we don't keep reparsing them
        unlink $manifest_file;
        next LP_MANIFEST;
    }

    #
    # scan over all bookmarks to see if any queued urls left
    #
    my $all_queues_empty = $TRUE;
    LP_SCAN:
    foreach my $bookmark (@$bookmarks) {
        if (scalar(@{$bookmark->{'queue'}}) > 0) {
            $all_queues_empty = $FALSE;
            last LP_SCAN;
        }
    }
    if ($all_queues_empty) {
        #
        # completed harvesting the current level, so decide whether to quit or descend
        #
        if ($current_depth >= $depth) {
            # finished, so delete this manifest file and go onto next manifest file
            unlink $manifest_file;
            next LP_MANIFEST;
        }
        # descend to the next level
        $manifest->{'current_depth'} = ++$current_depth;
        #FIXME: refine candidate links for next level according to idf and threshold
        
        # calculate idf of each child and history link (same idea as idf used in tf-idf)
        my %df = ();
        {
            # count number of bookmarks each child url occurs in (equivalent to corpus df)
            foreach my $bookmark (@$bookmarks) {
                foreach my $url ( (@{$bookmark->{'child'}}, @{$bookmark->{'history'}}) ) {
                    if (exists $df{$url}) {
                        $df{$url}++;
                    }
                    else {
                        $df{$url} = 1;
                    }
                }
            }
            # normalise df to value in linear scale [0=not discriminating .. 1.0=totally discriminating]
            my $noofdocs = scalar(@$bookmarks);
            for my $key (keys %df) {
                $df{$key} = ($noofdocs - $df{$key}) / $noofdocs;
            }
        }

        # move suitable children to their respective bookmark's queue of urls
        my $new_urls_queued = $FALSE;
        foreach my $bookmark (@$bookmarks) {        
            foreach my $url (@{$bookmark->{'child'}}) {
                if ($df{$url} >= $threshold) {
                    $new_urls_queued = $TRUE;
                    push(@{$bookmark->{'queue'}}, $url);
                    _robot_log("QUEUE($df{$url}>=$threshold)", $relative_manifest_file, $bookmark->{'id'}, $url);
                }
                else {
                    _robot_log("IGNORE($df{$url}<$threshold)", $relative_manifest_file, $bookmark->{'id'}, $url);
                }
            }
            my @empty_list = ();
            $bookmark->{'child'} = \@empty_list;
        }
        if ($new_urls_queued) {
            # save the updated manifest
            _save_manifest($manifest_file, $manifest);
        }
        else {
            # finished, so delete this manifest file and go onto next manifest file
            unlink $manifest_file;
            next LP_MANIFEST;
        }
    }
    
    #
    # attempt to harvest each bookmark's current queue of urls
    #
    foreach my $bookmark (@$bookmarks) {

        while(scalar(@{$bookmark->{'queue'}}) > 0) {

            # only harvest for a maximum of N seconds (because running via cron)
            if ((time - $start_time) > $EXECUTION_TIMEOUT) {
                last LP_MANIFEST;
            }
        
            # pull first item from the head of this bookmark's queue of urls to be fetched
            my $url = shift @{$bookmark->{'queue'}};
            
            # record this url in the bookmark's crawl history
            push(@{$bookmark->{'history'}}, $url);
            
            # save new manifest info (i.e. without this url)
            _save_manifest($manifest_file, $manifest);

            # log the attempt to fetch a url
            _robot_log('GET', $relative_manifest_file, $bookmark->{'id'}, $url);

            # attempt to fetch this bookmark
            my $res = http_get(
                'url' => $url,
                'cache' => $FALSE,
                'headers' => {
                    'Accept' => 'text/html,application/xhtml+xml,application/xml',
                },
            );
            if (!$res->{'success'}) {
                # failed to fetch page, so log problem with url
                _robot_log('FAIL', $relative_manifest_file, $bookmark->{'id'}, $res->{'message'}, $url);
            }
            else {
                # url fetched successfully, so add file to document
                my $document_folder = File::Basename::dirname($manifest_file);
                my $item_id = util_getValidFileName($bookmark->{'id'});
                my $document_file = File::Spec->catdir($document_folder, $item_id . $DOCUMENT_FILE_EXTENSION);
                
                my $content = $res->{'content'};
                if ($remove_html) {
                    # remove html tags
                    $content = remove_html($content);
                    # compress whitespace (but leave lines intact for ease of reading)
                    $content =~ s/\r+/\n/gxsm;
                    $content =~ s/[\ \t]+/\ /gxsm;
                    $content =~ s/\n+[\ ]+/\n/gxsm;
                    $content =~ s/[\ ]+\n+/\n/gxsm;
                    $content =~ s/\n+/\n/gxsm;
                }

                if ($current_depth == 0) {
#                    util_writeFile($document_file, $content, 'UTF-8');
                    my %data_value = (
                        'text' =>  Encode::decode('Detect', $content),
                    );
                    util_writeFile($document_file, JSON->new->canonical->pretty->encode(\%data_value) );    
                }
                else {
                    die "TODO: harvest.pl - read json of old value and append content to 'text' value in hash.";
                    util_appendFile($document_file, $content, 'UTF-8');
                }

                # update document metadata to insert/replace the document entry
                my ($documents_info_file, $documents_info, $documents_data_file, $documents_data)
                    = _load_documents_meta($document_folder);
                my $timestamp = time;
                $documents_data->{$item_id} = {
                    'type'          => 'documents',
                    'id'            => $item_id,
                    'description'   => $bookmark->{'description'},
                    'created'       => $timestamp,
                    'modified'      => $timestamp,
                    'bookmark'      => $bookmark->{'uri'},
                    'source'        => $bookmark->{'url'},
                    'uri'           => $settings->{'SITE_URI_BASE'} . '/' . $user_id . '/documents/' . $folder_id . '/items/' . $item_id,
                };            
                $documents_info->{'modified'} = $timestamp;
                _save_documents_meta($documents_info_file, $documents_info, $documents_data_file, $documents_data);
                        
                # log success and record filename and length
                my $relative_document_file = substr($document_file, length($settings->{'USERS_PATH'})+1);
                _robot_log('OK', $relative_manifest_file, $bookmark->{'id'}, $relative_document_file, length($res->{'content'}));

                # if depth not exceeded, add child links to bookmark's queue
                if ($current_depth < $depth && scalar(@{$bookmark->{'child'}}) < $breadth) {

                    # get base for the current url (used to make relative urls absolute)
                    my $url_stem = $url;
                    {
                        # strip off query string if one exists
                        my $ix = index($url_stem, '?');
                        if ($ix >=0) {
                            $url_stem = substr($url_stem, 0, $ix);
                        }
                    }
                    # normalise trailing slash
                    $url_stem =~ s|[/\\]$||gxsm;
                    $url_stem .= '/';

                    # get root for the current url (used to make relative urls absolute)
                    my ($url_root) = ($url_stem =~ m|^(https?://[^/\\\?]+)|xmsi);

                    # build a hash of urls already added or considering
                    my $covered = \%{{ 
                        map { $_ => $TRUE } 
                        (@{$bookmark->{'child'}}, @{$bookmark->{'history'}}, @{$bookmark->{'queue'}}) 
                    }};

                    # ignore commented out text (and links)
                    my $content = $res->{'content'};
                    $content =~ s/<!--.+?-->//gxsm;
                    # iterate over all links in content (with relaxed syntax to cope with bad html)
                    my @links = $content =~ /<a\s[^>]*?href\s*=\s*["']?([^"'\s>]+)/gis;
                    if (scalar @links > 0) {
                        LP_LINKS:
                        for my $link (@links) {
                            # make a copy of link without any trailing slash
                            my $link_noslash = $link;
                            $link_noslash =~ s|[/\\]$||gxsm;
                            # ignore empty, local, non-http protocols, and already covered urls
                            if ( 
                                 exists $covered->{$link} || 
                                 exists $covered->{$link_noslash} ||
                                 $link eq '' || 
                                 substr($link, 0, 1) eq '#' || 
                                 $link =~ /^(?:mailto|ftp|sftp)\:/xmsi
                               ) {
                                next LP_LINKS;
                            }

                            # avoid later retesting this same link
                            $covered->{$link} = $TRUE;

                            # ensure url is absolute
                            if ($link !~ m|^https?\://|) {
                                $link = (($link =~ m|^[/\\]|) ? $url_root : $url_stem) . $link;
                            }

                            # constrain url to have the same domain
                            if ($same_domain && 
                                $url_root ne substr($link, 0, length($url_root))) {
                                next LP_LINKS;
                            }
                            # constrain url to have the same stem
                            if ($same_stem && 
                                $url_stem ne substr($link, 0, length($url_stem))) {
                                next LP_LINKS;
                            }

                            # record this link as a "child" of current page
                            push(@{$bookmark->{'child'}}, $link);

                            # constrain number of children followed
                            if (scalar(@{$bookmark->{'child'}}) >= $breadth) {
                                last LP_LINKS;
                            }
                        }#for @links

                        # save new manifest info (i.e. with new children urls)
                        _save_manifest($manifest_file, $manifest);
                    }
                }

            }
        }#foreach bookmark's queued urls
    }#foreach bookmark
}#foreach manifest file

exit;

sub _robot_log {
    my $str = join("\t", @_);
    util_appendFile($settings->{'ROBOT_LOG'}, gmtime(time) . "\t" . $str . "\n");
}

sub _load_and_run {
    #
    # loads a perl file arg1 and calls a function arg2
    #
    my ($fname, $subname) = @_;
    shift; shift;  #consume first two args but keep rest
    my $ret = undef;
    if (-f $fname) {
        require $fname;
        no strict 'refs';
        $ret = &$subname(@_);
        use strict 'refs';
    }
    return $ret;
}

sub array_from_hash {
    my ($hash_ref) = @_;
    my @array = map($hash_ref->{$_}, sort keys %{$hash_ref});
    return \@array;
}

sub remove_html {
    #
    #   STRING remove_html(STRING $str)
    #
    #   Nieve implementation of xml/html tag removal (+ removes xml/html comments)
    #   FIXME: ought to use a parser to do this!
    #
    my ($str) = @_;
    # unescape
    $str = HTML::Entities::decode_entities($str);
    # remove comments
    $str =~ s/<!--.+?-->//gxsm;
    # remove elements
    $str =~ s/<[^>]+>/\ /gxsm;
    return $str;
}


sub _load_manifest {
    my ($manifest_file) = @_;    
    # deserialise a json hash
    return JSON->new->decode( util_readFile($manifest_file) );
}

sub _save_manifest {
    my ($manifest_file, $manifest) = @_;
    # serialise a json hash
    util_writeFile($manifest_file, JSON->new->canonical->pretty->encode($manifest));
    return $manifest;
}



sub _load_documents_meta {
    my ($documents_path) = @_;

    my $documents_info_file = File::Spec->catfile($documents_path, $INFO_FILENAME);
    my $documents_info = JSON->new->decode(util_readFile($documents_info_file));

    # add to or create this documents folder's data file (if it exists)
    my $documents_data_file = File::Spec->catfile($documents_path, $DATA_FILENAME);
    my $documents_data;
    if (!-e $documents_data_file) {
        $documents_data = {};
    }
    else {
        # deserialise an array of thing hashes
        my $array_ref = JSON->new->decode( util_readFile($documents_data_file) );
        my %hash = map(($_->{'id'}, $_), @$array_ref);
        $documents_data = \%hash;
    }

    return ($documents_info_file, $documents_info, $documents_data_file, $documents_data);
}

sub _save_documents_meta {
    my ($documents_info_file, $documents_info, $documents_data_file, $documents_data) = @_;
    
    util_writeFile($documents_info_file, JSON->new->canonical->pretty->encode($documents_info) );  

    my $documents_array = array_from_hash($documents_data);
    util_writeFile($documents_data_file, JSON->new->canonical->pretty->encode($documents_array) );
}

