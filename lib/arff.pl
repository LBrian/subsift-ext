# arff.pl
#
# 	Adapted from ARFF::Util on CPAN by simon.price@bristol.ac.uk
# 	- Accepts string instead of file argument.
# 	- Can specify whether result records (rows) are hashes or arrays.
#	- Converts numeric values to Perl numbers rather than strings (was bug in ARFF::Util)
#	- TODO: add error reporting and more checking
#
use strict;
use warnings;

my $STATUS_NORMAL 			= 0;
my $STATUS_RELATION_NAME 	= 1;
my $STATUS_COMMENT 			= 2;
my $STATUS_DATA 			= 3;

sub arff_parse_string {
	#
	#	HASHREF $relation arff_parse_string(STRING $arff_str[, BOOL $use_schema])
	#
	#	args:
	# 		$arff_str = text of an ARFF file
	# 		$use_schema = if 1 returns records as hash of {attribute_name=>value) pairs
	#				      otherwise returns records as arrays (default if arg not supplied)
	#
	my ($arff_str, $use_schema) = @_;

	my $status = $STATUS_NORMAL;

	my $line_counter = 1;
	my $relation = {};

	while($arff_str =~ /([^\n\r]+)[\n\r]?/g) {
		my $line = util_trim($1);

		if ($line eq '') {
			# ignore blank lines
		}
		elsif ($line =~ /^\s*%/i) {
			$status = $STATUS_COMMENT;
		}
		elsif ($line =~ /^\s*\@RELATION\s+(\S*)/i ) {
			$relation->{'relation_name'} = $1;
		}
		elsif ($line =~ /^\s*\@ATTRIBUTE\s+(\S*)\s+(\S*)/i ) {
			if (!$relation->{'attributes'}) {
				$relation->{'attributes'} = [];
			}
			my $v = lc($2);
			my $attribute = { 'attribute_name' => $1, 'attribute_type' => $v,
							  'attribute_is_numeric' => (($2 eq 'numeric' || $2 eq 'integer' || $2 eq 'real') ? 1 : 0) };
			my $attributes = $relation->{'attributes'};

			push(@$attributes , $attribute);
		}
		elsif ($line =~ /^\s*\@DATA(\.*)/i ) {
			$status = $STATUS_DATA;
		}
		elsif ($status == $STATUS_DATA) {
			if (!$relation->{'records'}) {
				$relation->{'records'} = [];
			}
			my @data_parts = split(/,/, $line);

			my $attributes = $relation->{'attributes'};
 			my $records = $relation->{'records'};

 			my $data_size = scalar(@data_parts);
			if ($data_size != scalar(@$attributes)) {
				# ignore errors!
			}
			else {
	 			if (defined $use_schema && $use_schema eq '1') {
	 				# create a record as a hash of attribute_name=>value pairs
					my $cur_record = {};
					for(my $i=0; $i<$data_size; $i++) {
						my $value = util_trim($data_parts[$i]);
						$cur_record->{$attributes->[$i]->{'attribute_name'}} = ($attributes->[$i]->{'attribute_is_numeric'} ? 0+$value : $value);
					}
					push(@$records , $cur_record);
	 			}
	 			else {
	 				# create a record as an array
					my $cur_record = [];
					for(my $i=0; $i<$data_size; $i++) {
						my $value = util_trim($data_parts[$i]);
						$cur_record->[$i] = ($attributes->[$i]->{'attribute_is_numeric'} ? 0+$value : $value);
					}
					push(@$records , $cur_record);
				}
			}
			
		}
		$line_counter++;
	}
	
#	$relation->{'data_record_count'} = $record_count; 	 redundant!
# 	$relation->{'attribute_count'} = $attribute_count; 	 redundant!

#	$self->relation($relation);
	return $relation;
}

1;
