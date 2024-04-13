#!/usr/bin/env perl
use strict;
use warnings;

# meminfo: Nicely formatted output showing info about physical memory modules, using dmidecode output.
# Author: Tony Malkowski <tony@txstate.edu>
# Also see dmidecode_json.pl, which this is based on.

die "Must run as root" unless $ENV{USER} eq "root";

# check for vmware devices
die "This tool does not run on VMs (yet)" if `lspci -d 15ad: | wc -l` > 0;

my $dmi = dmidecode("-t", "memory");
my $records = $dmi->{records};

foreach my $id (sort keys %$records) {
	my $record_type = $records->{$id}->{record_type};
	my $entries     = $records->{$id}->{entries};
	if ($record_type eq "Physical Memory Array") {
		foreach my $t ("Number Of Devices", "Error Correction Type") {
			printf "%s: %s\n", $t, $entries->{$t} if $entries->{$t};
		}
		print "\n";
	}
}

my %len = (
	"Locator" => 0,
	"Form Factor" => 0,
	"Size" => 0,
	"Configured Memory Speed" => 0,
	"Part Number" => 0,
);
my %sets;
foreach my $id (sort keys %$records) {
	my $record_type = $records->{$id}->{record_type};
	my $entries     = $records->{$id}->{entries};

	if ($record_type eq "Memory Device") {
		foreach (keys %len) {
			if (defined($entries->{$_}) && ($entries->{Size} ne "No Module Installed" || $_ eq "Locator")) {
				$len{$_} = length($entries->{$_}) if length($entries->{$_}) > $len{$_};
			}
		}
		$sets{ $entries->{Set} // 0 } //= [];
		push @{ $sets{ $entries->{Set} // 0 } }, $entries;
	}
	elsif ($record_type eq "Physical Memory Array") {
	}
	else {
		warn "unknown record type '$record_type'";
	}
}

$len{"Part Number"} += 3;

sub print_slot {
	printf("  Slot %s ", sprintf("%-".($len{"Locator"}+1)."s", $_[0].":"));
}

foreach (sort keys %sets) {
	if (m/^[0-9]+$/) {
		printf("Set %d:\n", $_);
	}
	elsif ($_ eq "None") {
		if (length(keys %sets) > 1) {
			print "No set defined:\n";
		}
	}
	else {
		warn "Unexpected value '$_' in set";
	}

	my $set = $sets{$_};
	foreach my $entries (@$set) {
		print_slot($entries->{Locator});
		if ($entries->{Size} eq "No Module Installed") {
			print "(empty)\n";
		}
		else {
			foreach ("Form Factor", "Size", "Configured Memory Speed", "Part Number") {
				printf("%-".($len{$_}+2)."s", ($_ eq "Part Number" ? "PN:" : "") . $entries->{$_} . ", ");
			}
			printf "SN:%s\n", $entries->{"Serial Number"};
		}
	}
	print "\n";
}






###############################################################################################################
################################## dmidecode function from dmidecode_json.pl ##################################
###############################################################################################################
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

