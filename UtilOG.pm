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

package UtilOG;

use File::Basename;
use Cwd 'abs_path';
use Portable;

sub absolute_pathname {
  my $relative = shift;
  my ($err,$globbed) = Portable::do_glob_one($relative);
  my $dir = directory_containing_filename($globbed);
  my $file = filename_with_path_stripped($globbed);
  return Cwd::abs_path($dir)."/".$file; # I think this is portable, because Perl translates these when opening and closing files.
}

sub directory_containing_filename {
  my $file = shift;
  my ($err,$globbed) = Portable::do_glob_one($file);
  my @split_up = split_up_path_name($globbed);
  if ($split_up[0] ne '') {return $split_up[0]}
  return ".";
}

sub filename_with_path_stripped {
  my $file = shift;
  my ($err,$globbed) = Portable::do_glob_one($file);
  my @split_up = split_up_path_name($globbed);
  return $split_up[1];
}

sub split_up_path_name {
  my $path_name = shift;
  my ($name,$path,$suffix) = fileparse($path_name);
  #$path_name =~ m@^(.*)/([^/]*)$@;
  return ($path,$name.$suffix);
}

sub guess_username {
    return getlogin() || (getpwuid($<))[0] || "staff"; 
    #... Programming Perl, p. 722; 2nd clause is in case getlogin doesn't work
    # 3rd is for systems like Windows that might not even require users to log in.
}


1;
