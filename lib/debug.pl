# debug.pl
# 
# important: this file must not dependencies on rest of framework
#
use strict;
use warnings;

use Syntax::Highlight::Perl;

use FindBin qw($RealDir);
my $home_path = $RealDir;
# optionally, if in a *nix /cgi-bin folder, assume home is parent
$home_path =~ s{/cgi\-bin$}{};


=head test...
# test out error capture and perl code listing with error line highlighted...
eval {
 my $num=0;
 my $cal = 123;
 my $x = $cal / $num;
 print $x;
}; #end of eval
if ($@) {
    debug_handle_error($@);
} elsif ($!) {
    debug_handle_error($!);
}
=cut

sub debug_handle_error {
    my ($error_message) = @_;
    
    #
    # display debug information to browser
    #
    print "Content-type: text/html\n\n";

    my $css = _debug_code_css();
    my $body = $error_message;

    my ($error_file, $error_line) = ($error_message =~ /\s+(\S+)\s+line\s+(\d+)/);
    if (defined $error_file && defined $error_line) {
        my $sanitised_message = $error_message;
        $sanitised_message =~ s/$home_path//gxsm;
        $body = _debug_code_listing($error_file, $error_line, $sanitised_message);   
    }
    print <<"__";
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en" dir="ltr">
<head>
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
    <title>PERL Error</title>
$css
</head>
<body>
$body
</body>
</html>
__
    die "PERL Error: $error_message\n";
}



sub _debug_code_listing {
    #
    # return an html formatted code listing of perl source file $error_file
    # and highlight error line $error_line
    #
    my ($error_file, $error_line, $error_message) = @_;

    if (!-e $error_file) {
        return '';
    }
    my $str = _debug_util_readFile($error_file, 'UTF-8');
    $str =~ s/\r//gsxm;

    if (defined $error_line) {
        $error_line *= 1;
    }
    else {
        $error_line = -1;
    }
    

    my $color_table = {
        'Variable_Scalar'   => 'color:#080;',
        'Variable_Array'    => 'color:#f70;',
        'Variable_Hash'     => 'color:#80f;',
        'Variable_Typeglob' => 'color:#f03;',
        'Subroutine'        => 'color:#980;',
        'Quote'             => 'color:#00a;',
        'String'            => 'color:#007e3b;',
        'Comment_Normal'    => 'color:#315500;font-style:italic;',
        'Comment_POD'       => 'color:#014;font-family:' .
                                   'garamond,serif;font-size:11pt;',
        'Bareword'          => 'color:#3A3;',
        'Package'           => 'color:#900;',
        'Number'            => 'color:#0066ff;',
        'Operator'          => 'color:#000;',
        'Symbol'            => 'color:#000;',
        'Keyword'           => 'color:#00f;',
        'Builtin_Operator'  => 'color:#300;',
        'Builtin_Function'  => 'color:#001;',
        'Character'         => 'color:#800;',
        'Directive'         => 'color:#399;font-style:italic;',
        'Label'             => 'color:#939;font-style:italic;',
        'Line'              => 'color:#000;',
    };
    my $formatter = new Syntax::Highlight::Perl;
    # install the formats set up above
    while ( my ($type, $style) = each %{$color_table} ) {
        $formatter->set_format($type, [ qq|<span style="$style">|, '</span>' ] );
    }
    $formatter->define_substitution('<' => '&lt;', 
                                    '>' => '&gt;', 
                                    '&' => '&amp;'); # HTML escapes
    $str = $formatter->format_string($str);

    my $err_html = $error_message;
    $err_html =~ s/(line\s\d+)/<a href="#errorline">$1<\/a>/;
    my $ret = '<pre class="error"><strong>PERL Error:</strong> ' . $err_html . '</pre><pre class="listing">';
    my $linenum = 0;
    for my $line ( split(/[\r\n]/, $str) ) {
        $linenum++;
        my $class = ($linenum == $error_line) ? 'error-line-no' : 'line-no';
        if ($linenum == $error_line) {
            $ret .= '<a name="errorline"></a>';
            $line = "<span class=\"error-line\">$line</span>";
        }
        my $numstr = sprintf('%4u',$linenum);
        $ret .= "<span class=\"$class\">$numstr</span>$line\n";
    }
    $ret .= '</pre>';
    return $ret;
}


sub _debug_code_css {
    #
    # css fragment required to provide styles for code_listing()
    #
    return <<'__';
<style type="text/css">

p.error
{
  font-family: monospace,courier;
  font-size: 0.8em;
}

pre.listing
{ margin-top: 0;
  margin-bottom: 0;
}

span.line-no
{ font-weight: normal;
  color: #505050;
  background-color: white;
  border: 1px inset;
  margin-right: 1em;
}

span.error-line-no
{ font-weight: bold;
  color: white;
  background-color: red;
  border: 1px inset;
  margin-right: 1em;
}

span.error-line
{ background-color: #d8d8d8;
}

</style>
__
}


sub _debug_util_readFile {
    #
    # local copy of generic file read util
    # (included here to ensure always available even if crash in i/o module)
    #
    my $fname = shift;
    
    open(FH, '<' . $fname) or return '';
    my $str;
    {
      local $/;
      $str = <FH>;
    }
    close(FH);
    
    return $str;
}


1;
