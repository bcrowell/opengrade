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
use Portable;
use JSON 2.0;

package Preferences;

sub new {
  my $class = shift;
  my %args = (
                GB=>{},
                @_
                );
  my $self = {};
  bless($self,$class);

  my %dir = (
    'traditional_unix'=>'~',
    'macos_x'=>'~/Library/Preferences',
    'windows'=>'MY_DOCUMENTS_DRIVE:/My Documents'
  );

  my %name = (
    'traditional_unix'=>'.OpenGrade_prefs',
    'macos_x'=>'OpenGrade_prefs',
    'windows'=>'ogr.prf'
  );


  my $os = Portable::os_type();
  if (!exists $dir{$os}) {$os = 'traditional_unix'}

  my $dir = $dir{$os};
  # On a Windows machine, the My Documents folder may be on C, or D, or God knows what. Try to find it:
  if ($os eq 'windows') {
    my $dir_for_my_documents;
    my @drives = ('C','D','E'); # Avoid A and B, because then it makes the floppy drive grind. This should work for most users.
    foreach my $drive(@drives) {
      my $try = $dir;
      $try =~ s/MY_DOCUMENTS_DRIVE/$drive/;
      if (-e $try && -d $try) {$dir_for_my_documents = $try}
    }
    $dir = $dir_for_my_documents;
  }

  my ($err,$file) = Portable::do_glob_one($dir);
  $file = $file."/".$name{$os};

  if (!-e $file) {
    open F,">$file" or return $self;
    if (Portable::os_has_unix_shell()) {
      print F <<DEFAULTS;
editor_command="gedit"
spreadsheet_command="soffice -calc"
print_command="lpr -o page-left=36 -o page-right=36 -o page-top=100 -o page-bottom=36"
DEFAULTS
    }
    close F;
  }

  open F,"<$file" or return $self;
  close F or return $self;
  $self->{FILE} = $file;

  return $self;
}

# If called in list context and the result is an array, returns it as a list.
sub get {
  my $self = shift;
  my $what = shift;
  my $hash = $self->get_hash();
  my $r = $hash->{$what};
  if (defined $r) {
    if (ref($r) eq "ARRAY" && wantarray()) {return @$r} else {return $r}
  }
  else {
    return '';
  }
}

# Value can be a string, hash ref, array ref.
sub set {
  my $self = shift;
  my $what = shift;
  my $value = shift;
  my $hash = $self->get_hash();
  $hash->{$what} = $value;
  return $self->write($hash);
  return 1;
}


sub write {
  my $self = shift;
  my $hash = shift;
  my $json = (new JSON);
  $json->canonical([1]);
  $json->pretty([1]);
  open F,">".$self->{FILE} or return '';
  print F $json->encode($hash);
  close F;
  return 1;
}

# returns hash ref or undef
sub get_hash {
  my $self = shift;
  local $/; # slurp whole file
  open F,"<".$self->{FILE} or return '';
  my $stuff = <F>;
  close F;
  if ($stuff=~/^{/) { # new JSON format
    my $hash;
    eval{$hash = JSON::parse_json($stuff)};
    if (!defined $hash) {eval{$hash = JSON::from_json($stuff)}}
    if (! defined $hash) {die "Preferences file ".$self->{FILE}." is not in valid JSON syntax."}
    return undef if !ref $hash;
    return $hash;
  }
  else { # old format -- convert to new
    my $hash = {};
    while ($stuff=~/(\w+)=\"([^\"]+)\"/g) {
      $hash->{$1} = $2;
    }
    foreach my $list("recent_files","files_to_delete") {
      if (exists $hash->{$list}) {
        my $text = $hash->{$list};
        my @l = get_comma_separated_list($text);
        $hash->{$list} = \@l;
      }
    }
    $self->write($hash); # convert to JSON format
    return $hash;
  }
}

# no longer used except when converting from old format
sub get_comma_separated_list {
  my $x = shift;
  return (map undo_backslash_commas($_),split(/(?<!\\),/,$x));
  # We store the string with all the commas backslashed, so any actual commas occurring in filenames are guaranteed
  # to have backslashes in front of them.
}

sub delete_from_list {
  my $self = shift;
  my $key = shift;
  my $x = shift;
  my @list = $self->get($key);
  @list = grep {$_ ne $x} @list;
  $self->set($key,\@list);
}

sub add_to_list_without_duplication {
  my $self = shift;
  my $key = shift;
  my $x = shift;
  my @list = $self->get($key);
  @list = eliminate_duplicates(@list,$x);
  $self->set($key,\@list);
}

sub eliminate_duplicates {
  my @x = @_;
  my %h = map {$_ => 1} @x;
  return keys %h;
}

sub backslash_commas {
  my $x = shift;
  $x =~ s/\\/BACKSLASH_IN_FILENAME_MAGIC/g;
  $x =~ s/,/\\,/g;
  return $x;
}

sub undo_backslash_commas {
  my $x = shift;
  $x =~ s/\\,/,/g;
  $x =~ s/BACKSLASH_IN_FILENAME_MAGIC/\\/g;
  return $x;
}



1;
