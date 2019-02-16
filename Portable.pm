#----------------------------------------------------------------
# Copyright (c) 2002 Benjamin Crowell, all rights reserved.
#
# This software is available under version 2 of the GPL license.
# The software is copyrighted, and you must agree to the
# license in order to have permission to copy it. The full
# text of the license is given in the file titled Copying.
#
#----------------------------------------------------------------


use strict;
use File::Glob;

package Portable;

# The following wrapper is intended to make it easier to deal with
# portability problems relating to filename globbing. In particular,
# I was having problems on Windows with filenames containing whitespace;
# bsd_glob() handles that correctly (not trying to interpret it as
# two patterns). A wildcard like *x will not match a file .x, because
# the . makes it invisible. However, .x matches .x. To get a listing of
# all files in a directory, do this:
#    do_glob_many("dir/{*,.*}")
# Matching is case-sensitive, which is not normal behavior on Windows or
# Classic MacOS. AFAICT, the GLOB_NOCHECK option referred to in the Camel
# book doesn't work, so I've emulated its behavior from scratch.
sub do_glob_many {
  my $spec = shift;
  my $flags =   File::Glob::GLOB_TILDE       # allow stuff like ~ and ~jones
              | File::Glob::GLOB_BRACE       # allow stuff like {*.c,*.h}
  ;
  my $err = '';
  my @result = File::Glob::bsd_glob($spec,$flags);
  if (File::Glob::GLOB_ERROR) {$err = $!}
  if (!@result) {$err='no such file'; push @result,$spec} # like GLOB_NOCHECK
  return ($err,\@result);
}

sub do_glob_one {
  my $spec = shift;
  my ($err,$result) = do_glob_many($spec);
  return ($err,$result->[0]);
}

sub do_glob_easy {
  my $spec = shift;
  my ($err,$result) = do_glob_one($spec);
  return $result;
}

# returns windows, macos_x, or traditional_unix, or, if not one of these, just returns $^O
sub os_type {
  my %detect_os = (
    'linux'=>'traditional_unix',
    'bsd'=>'traditional_unix',
    'darwin'=>'macos_x',
    'windows'=>'windows',
  );

  my $os_name = lc($^O);
  if ($os_name =~ m/win/) {$os_name = 'windows'}  # any version of Windows returns "MSWin32"
  if ($os_name =~ m/bsd/) {$os_name = 'bsd'} # FreeBSD actually returns 'freebsd', but this should also accomodate netbsd, etc.
  if (exists $detect_os{$os_name}) {$os_name = $detect_os{$os_name}}
  return $os_name;
}

sub os_has_unix_shell {
  return os_type() =~ /(traditional_unix|macos_x)/;
}

return 1;
