# upload.pl
use strict;
use warnings;
use diagnostics;

use CGI qw(param);

sub upload_file {
    #
    #   STRING $error upload_file(STRING $cgi_param_name, STRING $destination_filename,
    #                             BOOL $allow_overwrite, STRING $maximum_file_size)
    #
    #   Receive a cgi uploaded file with client filename in the cgi param $cgi_param_name, 
    #   but first checking that file size is under $maximum_file_size before storing the file
    #   in the absolute $destination_filename (which must be webserver user writable).
    #   If $allow_overwrite is 1, then destination file will be replaced if it already exists.
    #
    #   Returns $error, an error message string (will be '' if no errors).
    #
    my ($cgi_param_name, $destination_filename, $allow_overwrite, $maximum_file_size) = @_;
    
    # check that a filename has been submitted and that the file is not too large
    if ($ENV{'CONTENT_LENGTH'} > $maximum_file_size) {
        return "File rejected because it is larger than $maximum_file_size bytes.";
    }

    # check that a client filename was submitted
    if (!defined CGI::param($cgi_param_name) || CGI::param($cgi_param_name) eq '') {
        return 'You did not enter a filename.';
    }

    # check whether there is an existing file that will be overwritten and do we mind
    if ($allow_overwrite ne '1' && -e $destination_filename) {
        return 'File rejected because of lack of permission to replace.';
    }

    # read and store the file
    {
        my $cgi = new CGI;
        my $upload_filehandle = $cgi->upload($cgi_param_name);
        open DESTFILE, ">$destination_filename";
        binmode DESTFILE;
        while (<$upload_filehandle>) {
            print DESTFILE;
        }
        close DESTFILE;
    }
    
    # check file now exists
    if (!-e $destination_filename) {
        return 'Problem encountered uploading the file.';
    }

    # check not empty file
    if (-z $destination_filename) {
        # attempt to delete the file
        unlink($destination_filename);
        return 'Problem encountered uploading the file (or the file was empty in the first place).';
    }

    # success, so return empty error message
    return '';
}

1;
