#!/usr/bin/env perl
use strict;
use warnings;

# dmidecode_json: Reads dmidecode output and maps it back to a data structure.
# Author: Tony Malkowski <tony@txstate.edu>
# Also see meminfo.pl, which uses the structured data to show a nicely formatted list of memory modules.

BEGIN {
	for my $module (qw( JSON::XS JSON::PP JSON )) {
		next if defined &encode_json;
		eval {
			(my $file = $module) =~ s{::}{/}g; # Convert module name to file path
			require "$file.pm";                # Attempt to load the module
			$module->import('encode_json');    # Import 'encode_json'
		};
	}

	die "No JSON libraries found" unless defined &encode_json;
}

print encode_json(dmidecode(@ARGV)) . "\n";

sub dmidecode {
	my $trim = sub { my $t = shift; $t =~ s/\s*$//; $t; };

	my @text = split(/\n/, `dmidecode @_`);
	die "Permission denied" if $text[1] =~ m/Permission denied/ && @text < 10;

	my $records = {};
	my $record = { handle => undef };
	my $out = {
		dmidecode_version => undef,
		smbios_version => undef, 
		count => 0, 
		total_bytes => 0, 
		table_at => undef, 
		records => $records,
	};
	my $entry = [];
	for (my $n=0; $n<@text; $n++) {
		$_ = $text[$n];
	
		next if m/^$/;

		if (m/^# dmidecode (.*)/) {
			$out->{dmidecode_version} = $1;
		}
		elsif ($_ eq "Getting SMBIOS data from sysfs.") {
			# crickets
		}
		elsif (m/^SMBIOS ([^ ]+) present\.$/) {
			$out->{smbios_version} = $1;
		}
		elsif (m/^Handle (.*), DMI type (.*), (.*) bytes$/) {
			$record = {
				handle => $1,
				dmi_type => $2,
				bytes => $3,
				record_type => $text[$n+1],
				entries => {},
			};
			die "Duplicate handle ID found on line $n" if $records->{$1};
			$records->{$1} = $record;
			$n++; # skip the next line which is record type
		}
		elsif (m/^\t([^\t]+):$/) {
			$entry = [];
			$record->{entries}->{$1} = $entry;
		}
		elsif (m/^\t([^\t:]+): (.+)$/) {
			$record->{entries}->{$1} = $trim->($2);
		}
		elsif (m/^\t\t(.*)$/) {
			push @$entry, $trim->($1);
		}
		elsif (m/^(.+) structures occupying (.+) bytes\.$/) {
			$out->{count} = $1;
			$out->{total_bytes} = $2;
		}
		elsif (m/^Table at (.*)\.$/) {
			$out->{table_at} = $1;
		}
		elsif ($_ eq "Scanning /dev/mem for entry point.") {
			die "Failed reading DMI data" if $out->{count} == 0 && $n<10;
		}
		else {
			warn "Failed processing line $n ($_)";
		}
	
	}
	$out;
}

