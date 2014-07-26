# lib/template.pl
use strict;
use warnings;
use diagnostics;

use Template;

use vars qw(%Template_options);

sub template_config {
    #
    # VOID template_config(STRING_ARRAYREF $template_paths, STRING $output_path)
    #
    # Sets up template file search path from an array of paths. Also sets output path.
    #
    my ($template_paths_arrayref, $output_path) = @_;

    my $template_paths = join(':', @$template_paths_arrayref);
    
    %Template_options = (
        INCLUDE_PATH => $template_paths,
#        OUTPUT_PATH  => $output_path,      not using any more (would need for template_to_file though)
#        INTERPOLATE  => 1,
#        EVAL_PERL   => 1,
    );
}

sub template_to_file {
    #
    # VOID template_to_file(STRING $infilename, HASHREF $vars, STRING $outfilename)
    #
    # Use Template Toolkit to process template file $infilename with parameter hash
    # referenced in $vars and write the result out to file $outfilename.
    #
    my ($infilename, $vars, $outfilename) = @_;

    my $tt = Template->new(
            %Template_options
        )
        || die "$Template::ERROR\n";

    $tt->process(
        $infilename, $vars, $outfilename,
        {
            binmode => ':utf8',
        }
    )
    || die $tt->error(), "\n";
}

sub template_to_string {
    #
    # STRING template_to_string(STRING $infilename, HASHREF $vars)
    # STRING template_to_string(STRING_REF $text, HASHREF $vars)
    #
    # Use Template Toolkit to process template file $infilename with parameter hash
    # referenced in $vars and return the result as a string. Or if the first argument
    # is a string reference template_to_string(\$text, ...) then the text itself is used
    # as the template instead of treating it as a filename.
    #
    my ($infilename_or_textref, $vars) = @_;

    my $ret = '';

    my $tt = Template->new(
            %Template_options
        )
        || die "$Template::ERROR\n";

    $tt->process(
        $infilename_or_textref, $vars, \$ret,
        {
            binmode => ':utf8',
        }
    )
    || die $tt->error(), "\n";
    
    return $ret;
}


1;
