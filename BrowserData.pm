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
use English;

use Tk;
use Tk ':variables';
use BrowserWindow;
use ExtraGUI;
use GradeBook;
use Crunch;
use Report;
use Words qw(w get_w);
use MyWords;
use UtilOG;
use DateOG;
use Input;
use NetOG;
use Fun;
use Digest::SHA;
use Version;
use POSIX qw(tmpnam);

#---------------------------------------------------
# BrowserData class
#---------------------------------------------------

=head3 BrowserData

This contains all the in-memory information about the state of
an open gradebook file. Almost all of this information is in
a GradeBook file, but there are a few more pieces of data maintained
here, such as a flag that tells whether it has a file open.
the name of the file, etc.

This module does not contain any GUI stuff at all (oops, now it does,
unfortunately...), so for instance
if the GUI was going to be rewritten using a different library,
this parts wouldn't change. To keep GUI stuff out of here, we make
sure that BrowserData code never has to call any methods of any of
the GUI objects. The GUI objects know about the BrowserData, and
they call its methods as needed.

=cut

package BrowserData;

use Words qw(w get_w);

sub new {
  my $class = shift;
  my $file_name = shift;
  my $self = {};
  local $Words::words_prefix = "b.browser_data.new";
  bless($self,$class);
  $self->{FILE_OPEN} = 0;
  $self->{GB} = "";
  my ($success,$mark_modified);

  if ($file_name ne "") {
    my $yep_go_ahead = 0;
    my $sub = sub {
      my $password = shift;
      ($success,$mark_modified) = $self->open($file_name,$password);
      $yep_go_ahead = 1;
    };
    ExtraGUI::ask(PROMPT=>w('password'),CALLBACK=>$sub,PASSWORD=>1);
    # The three lines that are commented out below improve the program cosmetically, but make it significantly
    # slower to open a file.
    #Browser::main_window->withdraw(); # Otherwise it's there when we give a filename on the cmd line.
    my $mw = Browser::main_window();
    $mw->waitVariable(\$yep_go_ahead);
    #Browser::main_window->waitVariable(\$yep_go_ahead);
    #Browser::main_window->deiconify();
    #Browser::main_window->raise();
  }
  return $self;
}

=head4 file_is_open

Tells whether file is open (read-only).

=cut

sub file_is_open {
  my $self = shift;
  return $self->{FILE_OPEN};
}

sub file_name {
  my $self = shift;
  return $self->{FILE_NAME};
}

=head4 open()

  open($file_name,$password);

Calls GradeBook->read() and stores the newly created
GradeBook object in $self->{GB}. Returns a list consisting
of a boolean success value and a boolean telling whether the
file should be marked as modified (because sometimes the mere
act of opening a file can cause it to be modified, e.g., if it
needs a watermark added).

=cut

sub open {
  my $self = shift;
  my $file_name = shift;
  my $password = shift;
  local $Words::words_prefix = "b.authentication";
  my $mark_modified = 0;

  my $gb;
  $gb = GradeBook->read($file_name,$password);
  if (!ref $gb) {
    ExtraGUI::error_message("$gb");
    return (0,$mark_modified);
  }

  my $auth = $gb->{AUTHENTICITY};
  if ($auth ne "" && $gb->{HAS_WATERMARK}) {
    ExtraGUI::confirm(w("inauthentic"),
          sub {
            if (!shift) {
              my $report = '';
              if ($gb->{FORMAT} eq 'old') {
                my $mac = LineByLine->new(KEY=>$password,INPUT=>$file_name);
                $report = $mac->report_tampering();
              }
              else {
                $report = "The digital watermark is not consistent with the password you entered.";
              }
              ExtraGUI::show_text(TEXT=>$report,WIDTH=>81,PATH=>Preferences->new()->get('recent_directory'));
            }
          }
          ,w('ok'),w('view_report'));
    return (0,$mark_modified);
  }
  if (!$gb->{HAS_WATERMARK}) {
    ExtraGUI::error_message("This file appears not to have authentication codes. Codes will be added.");
    $gb->mark_modified_now();
    $mark_modified = 1;
  }

  my $confirm_result = 2;
  if ($gb->auto_save_file_exists()) {
    # First test if the autosave file is identical to the regular one:
    my $identical = 1;
    my $autosave = GradeBook->read($gb->autosave_filename(),$password); # assume same password
    if (!ref $autosave) {
      $identical=0;
      ExtraGUI::error_message("The file $file_name has an autosave file, ".($gb->autosave_filename()).", which could not be opened due to this error: $!");
    }
    else {
      $autosave->close();
    }
    if ($identical) {
      if($autosave->{AUTHENTICITY} ne "") {
        $identical=0;
        ExtraGUI::error_message("The file $file_name has an autosave file, ".($gb->autosave_filename()).". The autosave file's watermark was invalid. This could mean it ".
                               "had a different password, or it could mean that it's been tampered with."); 
      }
		}
    if ($identical) {
      my $log = $gb->union($autosave);
      $identical = ($log eq '');
    }
    if ($identical) {
      ExtraGUI::error_message("The file $file_name has an autosave file, ".($gb->autosave_filename()).", but the two files were identical. The autosave file is being deleted.");
      unlink($gb->autosave_filename())==1 || ExtraGUI::error_message("Error $! attempting to delete ".($gb->autosave_filename()));
    }
    
    # If they're not identical, warn the user:
    if (!$identical) {
      ExtraGUI::confirm((sprintf w('autosave_check'),$gb->autosave_filename()),sub{$confirm_result=shift});
      Browser::main_window()->waitVariable(\$confirm_result); # When they make their decision, the var changes to 0 or 1.
		}
  }
  if ($confirm_result==0) {return (0,$mark_modified)}

  ogr::add_to_list_of_open_files($gb);
  $self->{GB} = $gb;
  $self->{FILE_NAME} = $file_name;
  $self->{FILE_OPEN} = 1;
  return (1,$mark_modified);
}

=head4 close()

Saves and closes the file that's currently open. Removes it from the list of files
that are currently open (which are the ones we're supposed to save in case we get
a signal killing us).

=cut

sub close {
  my $self = shift;
  my $file_name = shift;
  my $modified = shift;
  local $Words::words_prefix = "b.data.close";
  my $gb = $self->{GB};
  my $result = "";
  if ($self->file_is_open()) { 
    if ($modified) {
      #print "is modified, saving\n";
      $self->save();
    }
    else {
      #print "isn't modified, not saving\n";
    }
    if ($gb->auto_save_file_exists()) {
      # After closing the file, the autosave file still exists. Test whether it's effectively identical to the file, so that we can safely delete it.
      my $autosave = GradeBook->read($gb->autosave_filename(),$gb->password()); # assume same password
      my $log = $gb->union($autosave);
      $autosave->close();
      my $identical = ($log eq '');
      if ($identical) {
        unlink($gb->autosave_filename())==1
             || ExtraGUI::error_message("Error $! attempting to delete ".($gb->autosave_filename()));
      }
      else {
        ExtraGUI::error_message("Warning: after closing the file $file_name in BrowserData::close(), the autosave file ".($gb->autosave_filename())." still exists".
                                ", and is NOT identical to the file.\n");
      }
    }
    $self->{FILE_OPEN} = 0;
    ogr::remove_from_list_of_open_files($gb);
    $self->{GB}->close();
    $self->{GB} = "";
  }
  return $result;
}

=head4 save()

Saves the file.

=cut

sub save {
  my $self = shift;
  my $file_name = shift;
  local $Words::words_prefix = "b.data.close";
  my $gb = $self->{GB};
  my $result = "";
  if ($self->file_is_open()) { 
    if (ref $gb) {
      $result = $gb->write(); # This also results in deleting the autosave file, unless there's an error.
      if ($result ne "") {return $result}
    }
  }
  return $result;
}

=head4 key_to_name()

              KEY=>"",
              ORDER=>"lastfirst", # can be firstlast

=cut

sub key_to_name {
  my $self = shift;
  my %args = (
              KEY=>"",
              ORDER=>"lastfirst", # can be firstlast
              @_,
             );
  if (!$self->file_is_open()) {return}
  my $gb = $self->{GB};
  my $key = $args{KEY};
  my ($first,$last) = $gb->name($key);
  if ($args{ORDER} eq "lastfirst") {
    return "$last, $first";
  }
  else {
    return "$first $last";
  }
}

=head4 get_a_grade()

Arguments are category, assignment, and student key.

=cut

sub get_a_grade {
  my $self = shift;
  my $a_key = shift;
  my $s_key = shift;
  if (!$self->file_is_open()) {return}
  my $gb = $self->{GB};
  my ($cat,$ass) = (GradeBook::first_part_of_label($a_key),
                              GradeBook::second_part_of_label($a_key));
  #print "get_a_grade: $s_key, $cat, $ass, ref=".ref($gb)."=\n";
  return $gb->get_current_grade($s_key,$cat,$ass);
}

=head4 set_a_grade()

Arguments are category, assignment, student key, and grade.

=cut

sub set_a_grade {
  my $self = shift;
  my $a_key = shift;
  my $s_key = shift;
  my $grade = shift;
  if (!$self->file_is_open()) {return}
  my $gb = $self->{GB};
  my ($cat,$ass) = (GradeBook::first_part_of_label($a_key),
                              GradeBook::second_part_of_label($a_key));
  #print "in set_a_grade, $a_key,$cat,$ass\n";
  my %grades = ($s_key=>$grade);
  $gb->set_grades_on_assignment(CATEGORY=>$cat,ASS=>$ass,GRADES=>\%grades);
}

1;
