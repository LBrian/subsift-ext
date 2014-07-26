#!/usr/bin/perl -w

# test for subsift pre-requisite modules

use strict;
use warnings;
use diagnostics;
use Module::Load;

my @Modules = (
  'Archive::Zip',
  'BerkeleyDB',
	'Carp',
	'CGI',
	'Class::Autouse',
	'Data::Dumper',
	'DBD::SQLite',
	'DBI',
	'Digest::SHA1',
  'Encode',
	'Encode::Detect',
	'Fcntl',
	'File::Basename',
	'File::Glob',
	'File::Path',
	'File::Spec',
	'FindBin',
	'HTML::Entities',
	'HTTP::Request',
	'HTTP::Response',
	'JSON',
	'JSON::Path',
	'Lingua::EN::NamedEntity',
	'LWP::UserAgent',
	'Syntax::Highlight::Perl',
	'Template',
	'Text::CSV',
	'Text::English',
	'Time::HiRes',
	'URI',
	'XML::FeedPP',
	'XML::Simple',
	'YAML',
	# legacy from original subsift but not required in REST API
	#'Text::Document',
	#'Text::DocumentCollection',
	#'DB_File',
	#'Cwd',  #may not need any more
);

foreach my $Mod ( @Modules ) {
	eval { load $Mod; 1 } or print "Could not load module " . $Mod . "\n";
};


