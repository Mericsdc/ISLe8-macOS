#!/usr/bin/perl
# Loads ISLe8's MediaRemote bridge (libisle8mr.dylib) into the system Perl and runs it.
# The system Perl carries an Apple identity, which MediaRemote requires since macOS 15.4.
use strict;
use warnings;
use DynaLoader;

my $library = shift or die "usage: isle8-media.pl <path to libisle8mr.dylib>\n";
my $handle = DynaLoader::dl_load_file($library, 0) or die DynaLoader::dl_error() . "\n";
my $symbol = DynaLoader::dl_find_symbol($handle, "isle8_mr_run") or die DynaLoader::dl_error() . "\n";
DynaLoader::dl_install_xsub("main::isle8_mr_run", $symbol)->();
