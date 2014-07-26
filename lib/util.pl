# util.pl
use strict;
use warnings;
#use diagnostics;

use Cwd qw(realpath);
use File::Basename qw(fileparse);
use Fcntl qw(:flock SEEK_END); # import LOCK_* and SEEK_END constants

# load heavy/occassional modules only on first use
use Class::Autouse;
Class::Autouse->autouse('LWP::RobotUA');
Class::Autouse->autouse('LWP::UserAgent');
Class::Autouse->autouse('URI');

use Encode;
require Encode::Detect;

use Digest::SHA1 qw(sha1_hex);


my $FALSE = 0;
my $TRUE  = 1;



sub http_cache_clear {
    #TODO: delete all(?) files in $settings->{'CACHE_PATH'}
}

sub http_get {
    #
    # HASHREF http_get(
    #    url => STRING,         url (which may include query string)
    #    params => HASHREF,     parameter key=>value pairs
    #    headers => HASHREF,    header key=>value pairs
    #    error => BOOL,         whether to die if an http error result
    #    cache => BOOL,         whether to cache page (if cacheable)
    #    refresh => BOOL,       whether to refresh cached page
    #    delay => REAL,         minutes to pause before performing get
    # )
    #
    # Perform an http GET of url with optional headers and caching, returning:
    #    content => STRING,     response body,
    #    status => INT,         status code (e.g. 200)
    #    message => STRING,     status code and message (e.g. "200 OK")
    #    success => BOOL,       whether status is a success code
    #
    
    # default argument values
    my %args = (
        'headers' => {},
        'error' => $FALSE,
        'cache' => $TRUE,
        'refresh' => $FALSE,
        'delay' => 1/60,        # minutes, i.e. 1/60 = 1 second
    );
    # decode key=>value argument list into %args
    while (my ($key, $value) = splice(@_, 0, 2)) {
        $key = '' unless defined $key;
        $args{$key} = $value;
    }
    # check for mandatory argument
    if (!defined $args{'url'}) {
        die 'Missing url in http_get';
    }

    # default return values
    my %ret = (
        'content' => '',
        'status' => 200,
        'message' => '200 OK',
        'success' => $TRUE,
    );

    # retrieve web framework configuration settings
    my $settings = get_settings();
    
    # generate a cache file name by hashing the original url
    my $cachefile;
    if ($args{'cache'}) {
        $cachefile = File::Spec->catfile($settings->{'CACHE_PATH'}, util_hashedFileName($args{'url'}));
        if (!$args{'refresh'} && util_fileExists($cachefile)) {
            # retrieve locally cached copy of file
            $ret{'content'} = util_readFile($cachefile, 'UTF-8');
            return \%ret;
        }
    }
    
    # construct url with optional query string
    my $url = URI->new( $args{'url'} );
    if (exists $args{'params'}) {
        # merge params key=>value pairs onto any existing query string
        my %query_args = $url->query_form;
        $url->query_form((%query_args, %{$args{'params'}}));
    }
    #my $ua = LWP::RobotUA->new($settings->{'ROBOT_TITLE'}, $settings->{'ROBOT_EMAIL'});
    my $ua = LWP::UserAgent->new();
    $ua->timeout(10);
    $ua->agent('Mozilla/5.0');
    
    #$ua->delay($args{'delay'});    # real no. in minutes
    # get() method requires args list as ($url[, $header_field => $header_value, ...])
    my @headers = %{$args{'headers'}};
    my @agent_args = ($url->as_string, @headers);
    my $response = $ua->get(@agent_args);
    if ($response->is_error) {
        if ($args{'error'}) {
            die 'Error ' . $response->code() . ' ' . $response->message() . ': unable to get url: ' . $url;
        }
        $ret{'status'} = $response->code();
        $ret{'message'} = $response->code() . ' ' . $response->message();
        $ret{'success'} = $FALSE;
        return \%ret;
    }
    my $refresh = $response->header('Refresh');
    if (defined $refresh) {
        # if http header has a "Refresh: 0;url=..." line then refresh automatically
        my $newurl = substr($refresh, index($refresh, ';url=')+length(';url='));
        if ($newurl !~ m{^https?://}) {
            # make url absolute by stripping off document name at end
            my ($urlbase) = ($response->base() =~ m{^(.+/)[^/]*});
            $newurl = $urlbase . $newurl;
        }
        $agent_args[0] = $newurl;
        $response = $ua->get(@agent_args);
        if (!$response->is_success) {
            if ($args{'error'}) {
                die 'Error ' . $response->code() . ' ' . $response->message() . ': unable to get Refresh url: ' . $newurl;
            }
            $ret{'status'} = $response->code();
            $ret{'message'} = $response->code() . ' ' . $response->message();
            $ret{'success'} = $FALSE;
            return \%ret;
        }
    }
    my $location = $response->header('Location');
    if (defined $location && $response->code >= 300 && $response->code <= 400) {
        # if http header has a "Location: ..." line then redirect automatically
        my $newurl = $location;
        $agent_args[0] = $newurl;
        $response = $ua->get(@agent_args);
        if (!$response->is_success) {
            if ($args{'error'}) {
                die 'Error ' . $response->code() . ' ' . $response->message() . ': unable to get Location url: ' . $newurl;
            }
            $ret{'status'} = $response->code();
            $ret{'message'} = $response->code() . ' ' . $response->message();
            $ret{'success'} = $FALSE;
            return \%ret;
        }
    }

    $ret{'content'} = Encode::decode('Detect', $response->content || '');
    $ret{'status'} = $response->code();
    $ret{'message'} = $response->code() . ' ' . $response->message();
    $ret{'success'} = ($response->is_success) ? $TRUE : $FALSE;
    
    if ($response->is_error) {
        if ($args{'error'}) {
            die 'Error ' . $response->code() . ' ' . $response->message() . ': unable to get url: ' . $url;
        }
        return \%ret;
    }
      
    if ($args{'cache'}) {
        # store a copy in local cache
        if (!((defined $response->header('Cache-Control') && $response->header('Cache-Control') =~ /no\-cache/xsmi) ||
              (defined $response->header('Cache-control') && $response->header('Cache-control') =~ /no\-cache/xsmi) ||
              (defined $response->header('Pragma') && $response->header('Pragma') =~ /no\-cache/xsmi))
            ) {
            util_writeFile($cachefile, $ret{'content'}, 'UTF-8');
        }
    }
    
    return \%ret;
}


#FIXME: probably need to either set Content-Length or Transfer-Encoding for posting data in content body
sub http_post {
    #
    # HASHREF http_post(
    #    url => STRING,         url (which may include query string)
    #    params => HASHREF,     parameter key=>value pairs
    #    headers => HASHREF,    header key=>value pairs
    #    error => BOOL,         whether to die if an http error result
    #    delay => REAL,         minutes to pause before performing post
    #    content => STRING,     override key-value usage and supply your own body
    # )
    #
    # Perform an http POST of url with optional headers and caching, returning:
    #    content => STRING,     response body,
    #    status => INT,         status code (e.g. 200)
    #    message => STRING,     status code and message (e.g. "200 OK")
    #    success => BOOL,       whether status is a success code
    #
    
    # default argument values
    my %args = (
        'headers' => {},
        'error' => $FALSE,
        'delay' => 1/60,        # minutes, i.e. 1/60 = 1 second
    );

    # decode key=>value argument list into %args
    while (my ($key, $value) = splice(@_, 0, 2)) {
        $key = '' unless defined $key;
        $args{$key} = $value;
    }
    # check for mandatory argument
    if (!defined $args{'url'}) {
        die 'Missing url in http_post';
    }

    # default return values
    my %ret = (
        'content' => '',
        'status' => 200,
        'message' => '200 OK',
        'success' => $TRUE,
    );

    # retrieve web framework configuration settings
    my $settings = get_settings();
    
    # construct url with optional query string (which will be converted to post params)
    my $url = URI->new( $args{'url'} );
    my $url_stem = $url->as_string;
    $url_stem =~ s/\?.*$//gxsm;

    my $ua = LWP::RobotUA->new($settings->{'ROBOT_TITLE'}, $settings->{'ROBOT_EMAIL'});
    $ua->delay($args{'delay'});    # real no. in minutes

    # create a request object (we do this rather than using "easier" ways to avoid character encoding hell)
    my $req = new HTTP::Request 'POST',$url_stem;
    $req->content_type('application/x-www-form-urlencoded');
    
    # transfer header key=>value pairs to request
    for my $k (keys %{$args{'headers'}}) {
        $req->header($k => $args{'headers'}{$k});
    }
    
    # merge query string and any params hash parameters into single hash
    my %parameters = (exists $args{'params'})
        ? ($url->query_form, %{$args{'params'}})
        : $url->query_form;

    # build up POST content as string rather than passing hash of params (to avoid mixed encoding issues)
    if (!defined $args{'content'}) {
        my $content = '';
        for my $key (keys %parameters) {
            $content .= $key . '=';
            $content .= URI::Escape::uri_escape($parameters{$key}) . '&';
        }
        $content =~ s/\&$//gxsm;
        $req->content($content);
    }
    else {
        $req->content($args{'content'});
    }

    # issue the HTTP POST request and process the result
    my $response = $ua->request($req);
    if ($response->is_error) {
        if ($args{'error'}) {
            die 'Error ' . $response->code() . ' ' . $response->message() . ': unable to post url: ' . $url;
        }
        $ret{'status'} = $response->code();
        $ret{'message'} = $response->code() . ' ' . $response->message();
        $ret{'success'} = $FALSE;
        return \%ret;
    }

    $ret{'content'} = Encode::decode('Detect', $response->content || '');
    $ret{'status'} = $response->code();
    $ret{'message'} = $response->code() . ' ' . $response->message();
    $ret{'success'} = ($response->is_success) ? $TRUE : $FALSE;

    return \%ret;
}



sub util_readFile {
    #
    # STRING util_readFile(STRING $fname, [STRING $encoding])
    #
    # Read as text the entire file from path $fname.
    #
    my ($fname, $encoding) = @_;
    
    # trap empty files early
    if (-z $fname) {
        return '';
    }
    
    open(FH, '<' . $fname) or return '';
#    binmode FH, ':encoding(UTF-8)';
    binmode FH;
    my $content;
    {
      local $/;
      $content = <FH>;
    }
    close(FH);

    if (!defined $content || $content eq '') {
        die 'Error: unable to read (or was an empty) file: ' . $fname;
    }
    
    if (defined $encoding) {
        $content = Encode::decode($encoding, $content);
    }

    return $content;
}

sub util_writeFile {
    #
    # VOID util_writeFile(STRING $fname, STRING $str, [STRING $encoding])
    #
    # Write $str as text to file path $fname.
    #
    my ($fname, $str, $encoding) = @_;

    if (defined $encoding) {
        $str = Encode::encode($encoding, $str);
    }

    open(FH, '>' . $fname) or die "Unable to open $fname: $!";
#    binmode FH, ':encoding(UTF-8)';
    binmode FH;
    print FH $str;
    close(FH);
}

sub util_appendFile {
    #
    # VOID util_appendFile(STRING $fname, STRING $str, [STRING $encoding])
    #
    # Append $str as text to file path $fname.
    # If file does not exist, one is created.
    #
    my ($fname, $str, $encoding) = @_;

    if (defined $encoding) {
        $str = Encode::encode($encoding, $str);
    }
    
    open(FH, '>>' . $fname) or die "Unable to open $fname for append: $!";
    $! = undef;  #suppress 'Inappropriate ioctl for device' due to Perl checking if tty or real file
#    binmode FH, ':encoding(UTF-8)';
    binmode FH;
	flock(FH, LOCK_EX) or die "Cannot lock - $!\n";
	# and, in case someone appended while we were waiting...
	seek(FH, 0, SEEK_END) or die "Cannot seek - $!\n";
    print FH $str;
	flock(FH, LOCK_UN) or die "Cannot unlock - $!\n";
    close(FH);
}


sub util_fileExists {
    #
    # STRING util_fileExists(STRING $fname)
    #
    # Returns 1 (true) if file $fname exists; 0 (false) otherwise.
    # (Syntactic sugar for perl's ugly -e operator)
    #
    my ($fname) = @_;
    return (-e $fname) ? 1 : 0;
}

=head unused

sub util_fileIsNewer {
    #
    # returns 1 if $file1 is newer than $file2 else 0
    #
    my ($file1, $file2) = @_;
    if (!-f $file1) {
        return 0;
    }
    if (!-f $file2) {
        return 1;
    }
    my ($mtime1) = (stat($file1))[9];
    my ($mtime2) = (stat($file2))[9];
    return ($mtime1 > $mtime2) ? 1 : 0;
}

sub util_programPath {
    #
    # returns absolute file path of this program (ends with slash)
    #
    my $path = Cwd::realpath($0);
    my ($filename, $directories, $suffix) = File::Basename::fileparse($path, qr/\.[^.]*/);
    return $directories;
}

sub util_programName {
    #
    # returns file name of this program (without the .pl suffix)
    #
    my $path = Cwd::realpath($0);
    my ($filename, $directories, $suffix) = File::Basename::fileparse($path, qr/\.[^.]*/);
    return $filename;
}

sub util_normalisePath {
    #
    # STRING util_normalisePath(STRING $path)
    #
    # Ensures $path ends with a file path separator
    #
    my ($path) = @_;
    if ($path ne '' && $path !~ m{[\\/\.:]$}gmsx) {
        $path .= '/';
    }
    return $path;
}

sub util_escapeHTML {
    #
    # returns an escaped HTML string
    #
    my ($str) = @_;
    $str = HTML::Entities::decode_entities($str);
    $str = HTML::Entities::encode_entities($str, '<>&');  #NB. only encoding minimal html chars so we don't mess up UTF8 multibyte chars
    return $str;
}

sub util_unescapeHTML {
    #
    # returns an unescaped HTML string
    #
    my ($str) = @_;
    return HTML::Entities::decode_entities($str);
}


=cut



sub util_trim {
    #
    # STRING util_trim(STRING $str)
    #
    # Strip white space off start and end of each line in string.
    #
    my ($str) = @_;
    $str =~ s/^\s+//gxms;
    $str =~ s/\s+$//gxms;
    return $str;
}

sub util_normalise_whitespace {
    #
    # STRING util_normalise_whitespace(STRING $str)
    #
    # Strip out repeated white space.
    #
    my ($str) = @_;
    $str =~ s/\s\s+/ /gxms;
    return $str;
}

=head unused

sub util_ellipsise {
    #
    # STRING util_ellipsise(STRING $str)
    #
    # Truncate a string to at most $MAXLEN characters,
    # appending ellipsis (i.e. three dots) if truncated.
    # Trys to split at word boundaries but will never truncate
    # to less than $MINLEN characters even if no word boundary.
    #
    my ($str) = @_;
    my $MAXLEN = 100;
    my $MINLEN = 40;
    if (length($str) > $MAXLEN) {
        $str = substr($str, 0, $MAXLEN);
        while(length($str) > $MINLEN && substr($str, -1) ne ' ') {
            $str = substr($str, 0, length($str)-1);
        }
        $str .= '...';
    }
    return $str;
}

=cut

sub util_getValidSubName {
    #
    # STRING util_getValidSubName(STRING $str) 
    #
    # Convert filename $str to a valid Perl sub name.
    #
    my ($str) = @_;
    $str =~ tr/A-Z \-\./a-z___/;
    return $str;
}
use vars qw(%DiacriticsMap $DiacriticsPattern);
%DiacriticsMap = (
    '��' => 'a', 
    '��' => 'a', 
    '��' => 'a', 
    '��' => 'a', 
    '��' => 'a', 
    '��' => 'a', 
    '��' => 'c', 
    '��' => 'e', 
    '��' => 'e', 
    '��' => 'e', 
    '��' => 'e', 
    '��' => 'i', 
    '��' => 'i', 
    '��' => 'i', 
    '��' => 'i', 
    '��' => 'dh',
    '��' => 'n', 
    '��' => 'o', 
    '��' => 'o', 
    '��' => 'o', 
    '��' => 'o', 
    '��' => 'o', 
    '��' => 'u', 
    '��' => 'u', 
    '��' => 'u', 
    '��' => 'y', 
    '��' => 'th',
    '��' => 'y', 
    '��' => 'ae',
    '��' => 'oe',
    '��' => 'ue',
    '��' => 'ss',

    '��' => 'A', 
    '��' => 'A', 
    '��' => 'A', 
    '��' => 'A', 
    '��' => 'A', 
    '��' => 'A', 
    '��' => 'C', 
    '��' => 'E', 
    '��' => 'E', 
    '��' => 'E', 
    '��' => 'E', 
    '��' => 'I', 
    '��' => 'I', 
    '��' => 'I', 
    '��' => 'I', 
    '��' => 'Dh',
    '��' => 'N', 
    '��' => 'O', 
    '��' => 'O', 
    '��' => 'O', 
    '��' => 'O', 
    '��' => 'O', 
    '��' => 'U', 
    '��' => 'U', 
    '��' => 'U', 
    '��' => 'Y', 
    '��' => 'Th',
    '��' => 'Y', 
    '��' => 'Ae',
    '��' => 'Oe',
    '��' => 'Ue',
    '��' => 'Ss' 
);
$DiacriticsPattern = join('|', keys %DiacriticsMap);

=head THIS DOESN'T SEEM TO WORK. BUT USING SAME REGEX WHERE A CALL WOULD BE MADE TO THIS SUB *DOES* WORK (fun with Perl encodings!)
sub util_replaceDiacritics {
    #
    # STRING util_replaceDiacritics(STRING $str) 
    #
    # Expands diagritic characters in str to their ascii equivalent(s).
    #
    my ($str) = @_;
    $str =~ s/($DiacriticsPattern)/$DiacriticsMap{$1}/gxms;
    return $str;
}
=cut


sub util_getValidFileName {
    #
    # STRING util_getValidFileName(STRING $str)
    #
    # Returns a valid file name derived from $str.
    # Note that '.' is not permitted in the name.
    #
    my ($str) = @_;

    # swap spaces for underscores
    $str =~ tr/ /_/;

    # limit length to maximum and switch to hash if weird chars found
    my $MAXLEN = 41;
    if (length($str) >= $MAXLEN) {
        # truncate string
        $str = substr($str, 0, $MAXLEN);
    }
#    if ($str =~ m/[^A-Za-z0-9_\-\.]/gxsm) {
    if ($str =~ m/[^A-Za-z0-9_]/gxsm) {
        $str =~ s/($DiacriticsPattern)/$DiacriticsMap{$1}/g;
        # $str =~ util_replaceDiadritics($str);  #THIS DOESN'T SEEM TO WORK. BUT REGEX DIRECTLY *DOES* WORK (fun with Perl encodings!). SEE ABOVE LINE
#        $str =~ s/[\{\[\(\<>)\]\}~\|\/]/-/g;               # {[(<>)]}~|/ to '-'
        $str =~ s/[\{\[\(\<>)\]\}~\|\/]/_/g;               # {[(<>)]}~|/ to '_'
        $str =~ s/[\p{Zs}\t]+/_/g;                         # whitespace to '_'
        $str =~ s/\&+/_and_/g;                             # '&' to "_and_"
        $str =~ s/[^\p{Alphabetic}\p{Nd}\-\._]//g;         # drop not-word chars
#        $str =~ s/\-+/\-/g;                                # collapse sequences of '-'
        $str =~ s/_+/_/g;                                  # collapse sequences of '_'
        $str =~ s/^_//gxms;                                # trim leading underscore
        $str =~ s/_$//gxms;                                # trim trailing underscore
        if (length($str) >= $MAXLEN) {
            # truncate string again if it grew in size
            $str = substr($str, 0, $MAXLEN);
        }
    }
    return $str;
}

sub util_hashedFileName {
    #
    # STRING util_hashedFileName(STRING $str)
    #
    # Returns a (with high probability) unique string associated with $str
    # and that is suitable for using as a filename.
    #
    my ($str) = @_;
    return 'E' . Digest::SHA1::sha1_hex($str);
}


=head unused

# private globals used exclusively by util_ensureUnique()
use vars qw(%_original_of);
%_original_of = ();

sub util_ensureUnique {
    #
    # STRING util_ensureUnique(STRING $original, INT $maxlen)
    #
    # Returns a unique string based on $original and length limited to $maxlen
    # NB. maxlen must be > 5
    #
    my ($original, $maxlen) = @_;

    if (length($original) < $maxlen) {
        return $original
    }
    
    # generate candidate filestem
    my $s = substr($original, 0, $maxlen);
    
    my $MAXFILESTEMCLASHES = 9999;
    my $base_s = substr($s, 0, $maxlen - 5);  #5 comes from possible "_9999" suffix

    # guarantee a 1:1 mapping from entityid to filestem
    LP:
    for(my $i=1; $i < $MAXFILESTEMCLASHES; $i++) {
        # ensure that this filestem has not already been claimed by another entityid
        my $slot = $_original_of{$s};
        if (!defined $slot || $slot eq '') {
            # unused filestem, so claim it for this entityid
            $_original_of{$s} = $original;
            last LP;
        }
        else {
            # filestem is already claimed
            if ($slot eq $original) {
                # already claimed by this entity, so is okay
                last LP;
            }
            # filestem already claimed by another entityid, so make a new stem and retry
            $s = "${base_s}_${i}";
        }
    }
    
    return $s;
}

sub util_percentage {
    #
    # STRING util_percentage(NUMBER $nominator, NUMBER $denominator, INT $decimalplaces)
    #
    # Return $nominator*100/$denominator as a percentage to $decimalplaces.
    #
    my ($nominator, $denominator, $decimalplaces) = @_;

    my $percentage = 0;
    if ($denominator != 0) {
        $percentage = (100 * $nominator) / $denominator;
    }

    return sprintf("\%.${decimalplaces}f", $percentage);
}

sub util_rescale {
    #
    # STRING util_rescale(NUMBER $nominator, NUMBER $denominator, NUMBER $maxvalue, INT $decimalplaces)
    #
    # Return $nominator*$maxvalue/$denominator to $decimalplaces.
    #
    my ($nominator, $denominator, $maxvalue, $decimalplaces) = @_;
    
    my $rescaled = 0;
    if ($denominator != 0) {
        $rescaled = ($maxvalue * $nominator) / $denominator;
    }

    return sprintf("%.${decimalplaces}f", $rescaled);
}

sub util_nicemax {
    #
    # NUMBER util_nicemax(NUMBER_ARRAYREF $arrayref)
    #
    # Calculate a nice number just larger than the maximum number in array.
    #
    my ($arrayref) = @_;
    my $nmax = $arrayref->[0];
    foreach my $n (@$arrayref) {
        if ($n > $nmax) {
            $nmax = $n;
        }
    }
    my $r = int(0.5 + $nmax + $nmax*0.15);
    return $r;
}


sub util_timestamp {
    #
    # STRING util_timestamp()
    #
    # Returns current time as a timestamp string in "d mmm yyyy hh:mm:ss GMT" format.
    #
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time);
    $year += 1900;
    my @months = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
    return sprintf('%d %s %04d %02d:%02d:%02d GMT', $mday,$months[$mon],$year, $hour,$min,$sec);
}

sub util_datepath {
    #
    # STRING util_datepath()
    #
    # Returns current time as a file path string in "yyyy/mm/dd/" format.
    #
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time);
    $year += 1900;
    return sprintf('%04d/%02d/%02d/', $year,$mon+1,$mday);
}

sub util_humandate {
    #
    # STRING util_humandate()
    #
    # Returns current time as a human readable date string in "day d month yyyy" format.
    #
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time);
    $year += 1900;
    my @months = qw(January February March April May June July August September October November December);
    my @dayofweek = qw(Sunday Monday Tuesday Wednesday Thursday Friday Saturday);
    return sprintf('%s %d %s %04d', $dayofweek[$wday], $mday, $months[$mon], $year);
}

=cut

=head unused
sub util_sleep {
    #
    # VOID util_sleep(DOUBLE seconds)
    #
    # Pauses for specified number of seconds before returning.
    #
    my ($seconds) = @_;
    select(undef, undef, undef, $seconds);
    return;
}
=cut


sub util_invert_hash {
    #
    # HASH_REF util_invert_hash(HASH_REF hash_ref)
    #
    # Returns a value-key hash from original key-value hash
    #
    my ($hash_ref) = @_;
    my %inv = ();
    foreach my $key (keys %$hash_ref) {
        $inv{ $hash_ref->{$key} } = $key;
    }
    return \%inv;
}


1;
