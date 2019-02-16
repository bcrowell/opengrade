#----------------------------------------------------------------
# Copyright (c) 2002-2008 Benjamin Crowell, all rights reserved.
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
use Stage;
use Assignments;
use Score;

BEGIN {
  eval "use ServerDialogs";
  eval "use OnlineGrades";
}

#---------------------------------------------------
# Roster class
#---------------------------------------------------

=head3 Roster class

This class encapsulates all the data about the roster
displayed on the screen.

=cut

package Roster;

use Words qw(w get_w);

sub new {
  my $class = shift;
  my $stage = shift;
  my $parent = shift;
  my $data = shift;
  my $self = {};
  bless($self,$class);

  $self->{KEYS} = [];                # ref to an array, which is stored in the order shown on the screen
  $self->{NAMES} = [];                # in the same order as KEYS, but shows the names in human-readable form
  $self->{KBSEL} = '';
  $self->{KBCTRL} = 0;                # is the control key currently being held down?
  $self->{SELECTED_STUDENT} = '';
  $self->{ASSIGNMENT} = '';
  $self->{OPTION_VAR} = '1-overall';
  $self->{SCROLL_LOCATION} = 0.;

  $self->{STAGE} = $stage;
  $self->{PARENT} = $parent;
  $self->{DATA} = $data;
  my $f = $parent->Frame()->pack(-side=>'left',-expand=>1,-fill=>'y',-padx=>10);
  my $f2 = $f->Frame()->pack(-side=>'top',-anchor=>'w');
  my $f3 = $f2->Frame()->grid(-row=>0,-column=>0);
  $f3->Label(-text=>'keyboard',-font=>ExtraGUI::font('plain'))->pack(-side=>'left');
  $f3->Label(-textvariable=>\$self->{KBSEL},-font=>ExtraGUI::font('plain'),-relief=>'groove',-width=>8,-anchor=>'w')->pack(-side=>'left');
  $self->{OPTIONS_FRAME} = $f2->Frame()->grid(-row=>0,-column=>1);
  $self->make_options_menu('1-overall','','');
  my $height = $f->screenheight - 200;
  $self->{SPREADSHEET} = $f2->Scrolled(
      "Canvas",
      -scrollbars=>"e",
      -width=>320,
      -height=>$height,
  )->grid(-row=>1,-column=>0,-columnspan=>2);
  $self->{SPREADSHEET}->Subwidget('yscrollbar')->configure(-takefocus=>0);
  $self->{SPREADSHEET}->Subwidget('canvas')->configure(-takefocus=>0);
  return $self;
}

sub make_options_menu {
  my $self = shift;
  my $what = shift;
  my $cat = shift;
  my $ass = shift;
  local $Words::words_prefix = "b.roster_options_menu";
  #print "in make_options_menu\n";
  if (exists $self->{OPTIONS_MENU}) {$self->{OPTIONS_MENU}->destroy()}
  my $gb = $self->{DATA}->{GB};
  my $file_is_open;
  if (ref $gb) {$file_is_open=1} else {$file_is_open=0}
  my @options = ();
  $self->{OPTION_VAR} = '';
  if ($file_is_open) {
    $self->{OPTION_VAR} = $options[0] = w('overall');
  }
  if ($cat ne '') {
    $self->{OPTION_VAR} = $options[1] = $gb->category_name_plural($cat);
  }
  if ($ass ne '') {
    my $assignment_menu_item = $gb->assignment_name($cat,$ass);
    if ($gb->category_property_boolean($cat,'single')) {
      $assignment_menu_item = $assignment_menu_item." ".w('grade'); # Has to be different from text of menu item for category.
    }
    $self->{OPTION_VAR} = $options[2] = $assignment_menu_item;
  }

  #print "in make_options_menu, cat=$cat= ass=$ass=\n";
  #print "  ".$self->{OPTION_VAR}."\n";

  @options = reverse @options;
  # Reverse order as a workaround for bug in some Perl/Tk implementations of Optionmenu. In some implementations of Perl/Tk,
  # setting the variable linked to the Optionmenu doesn't allow you to select the item on the menu. In these implementations,
  # the Optionmenu always starts out with the first item selected. As a workaround for this bug, I've reversed the order
  # of the menu, so that the first item is the one that /should/ be selected when the Optionmenu is rebuilt. 
  # This workaround required one other change in the code, which is also marked with a comment containing the text
  # "Reverse order as a workaround..."
  # Jan 09: See more notes in Perl/Tk book, p. 275, and implementation of Optionmenu in ExtraGUI; possibly I could simplify this.

  # Avoid annoying redrawing of window when an assignment with a very long name is picked.
  # It's still easy to tell which one you actually have selected, because it's highlighted on the left.
  my $max_len = 10;
  for (my $i=0; $i<@options; $i++) {
    my $o = $options[$i];
    if (length($o)>$max_len+3) {
      $options[$i] = substr($o,0,$max_len).'...';
    }
  }

  # This has to come /before/ the statement that creates the optionmenu, because the callback to make_scores gets triggered
  # when the optionmenu is first created.
  $self->{OPTIONS} = \@options; 

  # This is a flag that the optionmenu's callback routine checks (see below). Before I made this flag, it was
  # recalculating category totals twice whenever a new category was selected.
  $self->{DO_NOT_MAKE_SCORES} = 1;

  $self->{OPTIONS_MENU} = 
    $self->{OPTIONS_FRAME}->Optionmenu(
         -takefocus=>0,
         -font=>ExtraGUI::font('plain'),
         -options=>\@options,
         -variable=>\$self->{OPTION_VAR},
         -command=>sub{$self->{STAGE}->{BROWSER_WINDOW}->grades_queue(); if (!$self->{DO_NOT_MAKE_SCORES}) {$self->make_scores()}}
    )->pack();

  $self->{DO_NOT_MAKE_SCORES} = 0;

  #$self->{OPTIONS_MENU}->setOption($self->{OPTION_VAR}) if $self->{OPTION_VAR}; #...seems to have no effect; see note above, Jan 09
}

sub get_assignment_selection_info {
  my $self = shift;
  my $what = $self->type_of_assignment();
  my $cat = '';
  if ($what >= '2-category') {
    $cat = $self->{ASSIGNMENT};
    $cat =~ s/\..*//; # strip everything after the category, e.g. e.2 => e
  }
  my $ass = '';
  if ($what eq '3-assignment') {
    $ass = $self->{ASSIGNMENT};
    $ass =~ m/[^\.]*\.(.*)/;
    $ass = $1;
  }
  return ($what,$cat,$ass);
}

sub set_assignment {
  my $self = shift;
  my $key = shift;
  if ($key eq $self->{ASSIGNMENT}) {return}
  $self->{ASSIGNMENT} = $key;
  my $keys_ref = $self->{KEYS};
  my $n = @$keys_ref;
  my ($cat,$ass) = ('','');
  my $what;
  if ($key eq '') {
    $what = '1-overall';
  }
  else {
    if ($key =~ m/([^\.]*)\.(.*)/) {
      $what = '3-assignment';
      ($cat,$ass) = ($1,$2);
    }
    else {
      $what = '2-category';
      ($cat,$ass) = ($key,'');
    }
  }
  $self->make_options_menu($what,$cat,$ass);
  $self->make_scores($cat,$ass);
}

sub make_scores {
  my $self = shift;
  my ($what,$cat,$ass);
  if (@_) {
    $cat = shift;
    $ass = shift;
    $what =  $self->type_of_assignment();
  }
  else {
    ($what,$cat,$ass) = $self->get_assignment_selection_info();
  }

  my $gb = $self->{DATA}->{GB};
  if (!ref $gb) {return}
  my @k = $gb->student_keys("");
  my $n = @k;
  my $keys_ref = $self->{KEYS};

  my $assignments_in_this_cat;
  if ($what eq '2-category') {
    # For efficiency, compute this now, not once per student:
    $assignments_in_this_cat = $gb->array_of_assignments_in_category($cat);
  }

  for (my $j=0; $j<$n; $j++) { # loop over students
    my $who = $keys_ref->[$j];
    my $f;
    if (exists $self->{SCORE_ENTRIES}->[$j]) {
      $self->{SCORE_ENTRIES}->[$j]->destroy_widget();
      $f = $self->{SCORE_ENTRIES}->[$j]->frame();
    }
    else {
      $f = $self->{SCORE_FRAMES}->[$j];
    }
    my $score_info;
    my $gb = $self->{DATA}->{GB};
    if ($what eq '') {
      $score_info = ''; # shouldn't happen unless we're in an inconsistent state; see comment at bottom of type_of_assignment()
    }
    if ($what eq '1-overall') {
      my $total = Crunch::totals($gb,$who);
      $score_info = Report::fraction_to_display($gb,$total->{'all'});
    }
    if ($what eq '2-category') {
      my $total = Crunch::total_one_cat($gb,$who,$cat,$assignments_in_this_cat,1);
      $score_info = Report::fraction_to_display($gb,$total);
      # my $total = Crunch::totals($gb,$who,$cat,$assignments_in_this_cat);
      # $score_info = Report::fraction_to_display($gb,$total->{$cat});
    }
    if ($what eq '3-assignment') {
      $score_info = $self->{DATA}->get_a_grade($cat.".".$ass,$who);
    }
    $self->{SCORE_VARIABLES}->[$j] = $score_info;
    $self->{SCORE_ENTRIES}->[$j] = Score->new($f,$who,$what,\$self->{SCORE_VARIABLES}->[$j],$self,$j,$n);
  }

  return;

}


=head4 refresh()

Empties the roster and fills it up again.
This currently assumes only one student can be selected at once.

=cut

sub refresh {
  my $self = shift;
  $self->clear();
  my $data = $self->{DATA};
  my $spread = $self->{SPREADSHEET};
  my $canvas = $spread->Subwidget('canvas');
  if (exists $self->{FRAME_IN_CANVAS}) {  $self->{FRAME_IN_CANVAS}->destroy()}
  $self->{CANVAS} = $canvas;
  my $f = $canvas->Frame();
  return if !defined $f;
  $self->{FRAME_IN_CANVAS} = $f;
  $f->configure(-takefocus=>0);
  # If a file is open, fill it back up:
  if ($data->file_is_open()) {
    my $gb = $data->{GB};
    my @k = $gb->student_keys("");
    @k = sort {$gb->compare_names($a,$b)} @k;
    $self->{KEYS} = \@k;
    my @name_buttons = ();
    my @name_button_colors = ();
    my @score_frames = ();
    my $n = @k;
    for (my $j=0; $j<$n; $j++) {
      my $who = $k[$j];
      my $name = $f->Button(
        -relief=>'flat',
        -text=>$data->key_to_name(KEY=>$who)
      )->grid(-sticky=>'w',-row=>$j,-column=>0);
      push @score_frames,$f->Frame()->grid(-sticky=>'w',-row=>$j,-column=>1);
      push @name_buttons,$name;
      my $hover_color = Prefs::get_roster_hover_color();
      my $bg_color = Prefs::get_roster_bg_color_1();
      if (($j/3)%2 == 1) {$bg_color = Prefs::get_roster_bg_color_2()}
      push @name_button_colors,$bg_color;
      $name->configure(-activebackground=>$hover_color,
                       -takefocus=>0,
                       -anchor=>'w',
                       -background=>$bg_color,
                       -width=>16,
                       -height=>1,
                       -font=>ExtraGUI::font('plain'),
                       -pady=>-3);
      my $jj= $j; # Need this for closure, although it doesn't seem like we should!
      $name->bind('<ButtonRelease-1>',sub{       # $who and $name are closure-ized in this subroutine
           $self->clicked_on_student($who);
           $self->{KBSEL}='';
           $self->{SELECTED_STUDENT} = $who;
           $name->focus();
           $self->{COLUMN_FOCUS} = 0;
         }
        );
      $name->bind('<Key>',sub{key_pressed_in_roster($self,$who,$jj,$n)});
      $name->bind('<KeyRelease>',sub{key_released_in_roster($self,$who,$jj,$n)});
      $name->bind('<FocusIn>',sub{$self->{COLUMN_FOCUS}=0});
      # Note: bindings for the Score object are handled inside its constructor.
    }
    $self->{COLUMN_FOCUS} = 1;
    $self->{NAME_BUTTONS} = \@name_buttons;
    $self->{NAME_BUTTON_COLORS} = \@name_button_colors;
    $self->{SCORE_FRAMES} = \@score_frames;
    $self->make_scores();
  }
  $canvas->createWindow(0,0,-anchor=>'nw',-window=>$f);
  Browser::main_window()->update;
  $canvas->configure(-scrollregion=>[$canvas->bbox('all')]);
}

# In some exceptional situations, we may return a null
# string. Calling routines are responsible for not freaking out if we do that.
sub type_of_assignment {
  my $self = shift;
  # The following line gets executed when the file is first opened:
  if (!(exists $self->{OPTIONS} && exists $self->{OPTION_VAR})) {return ''}
  my $ops = $self->{OPTIONS};
  my $o = $self->{OPTION_VAR};
  my $what;
  my $most_specific_possibility = '0';
  for (my $j=0; $j<@$ops; $j++) {
    my $jj = (@$ops-1)-$j; # see the comment elsewhere in the code that reads "Reverse order as a workaround..."
    if ($jj==0) {$what='1-overall'}
    if ($jj==1) {$what='2-category'}
    if ($jj==2) {$what='3-assignment'}
    if ($what>$most_specific_possibility) {$most_specific_possibility=$what}
    if ($o eq $ops->[$j]) {
      return $what;
    }
  }
  # The following should really never happen. It used to happen before I fixed a
  # bug that left the Optionmenu in a temporarily inconsistent state. It still doesn't
  # hurt to have it here just in case.
  return ''; # make_scores() knows what this means
}

sub sel_color {
  return '#b0d0ff';
}

=head4 key_pressed_in_scores()

Handle a key pressed in the scores.

=cut

sub key_pressed_in_scores {
  my $self = shift;
  my $who = shift; # student's database key
  my $j = shift;   # index into the array of students
  my $n = shift;   # number of students
  my $key = $Tk::event->K;
  my $them = $self->{KEYS};
  if (!@$them) {return}        # no file open, or the roster is empty

  my $score = $self->{SCORE_VARIABLES}->[$j];

  # The logic for handling control characters is now partly obsolete, because this routine is no longer bound to those. Num_lock also doesn't seem to get passed here (?).
  # We do get an event when the control key is pressed, but, e.g., no W when control-W is pressed.

  # We want to beep if they type bogus characters. 
  # It's important not to use this list for anything other than beeping -- if I add a new feature, there
  # may be new keys that are valid.
  # This does not help with recognizing when the keypad is being used but the NumLock is off, because everything gets passed in
  # here the same way regardless of the state of the NumLock key.

  my $gb = $self->{STAGE}->{BROWSER_WINDOW}->{DATA}->{GB};
  $gb->{PREVENT_UNDO} = 0;
  my $assignment = $self->{STAGE}->{ASSIGNMENTS}->selected(); # cat.ass
  my ($cat,$ass) = $gb->split_cat_dot_ass($assignment);
  my $type = $gb->category_property2($cat,'type'); # guaranteed to return numerical by default, not undef
  #print "type=$type\n";
  my $allowed_pat = '[0-9]';
  my $allowed_values = [0,1,2,3,4,5,6,7,8,9];
  if ($type ne 'numerical') {
    $allowed_values = $gb->types()->{'data'}->{$type}->{'order'};
    $allowed_pat = '('.join('|',@$allowed_values).')';
  }
  #print "allowed_pat=$allowed_pat\n";

  my $generically_ok_key = ($key=~m/(\-|\.|x|space|Tab|plus|minus|period|Caps_Lock|Shift_(L|R)|Return|Control_(L|R)|KP_(Left|Begin|Right|Prior|Home|End|Subtract|Add|Delete|Insert|Enter)|Down|Up|Num_Lock)/i);
  my $beep_because_key_is_goofy = !($generically_ok_key || $key=~/$allowed_pat/);

  # Also, try to detect cases where NumLock is off, and they're trying to type keys on the keypad. This is actually really hard to do in general, but
  # I just look for cass where they hit a keypad key, but the grade is still null. That catches the most common situation, where you start
  # typing in a bunch of grades on the keypad without realizing the num lock is off.

  my $beep_because_of_num_lock = ($key=~m/^KP_/) && ($score eq '');

  if ($beep_because_key_is_goofy) {
    ExtraGUI::beep_if_allowed(Browser::main_window(),$self->{STAGE}->{BROWSER_WINDOW},'goofy_key',$key);
    if ($type ne 'numerical') {
      my $descr = $gb->types()->{'data'}->{$type}->{'descriptions'};
      my %h = reverse %$descr;
      ExtraGUI::error_message("Allowed keys are: ".join(',',sort @$allowed_values)." for ".join(',',sort keys(%h)));
    }
  }
  if ($beep_because_of_num_lock) {
    ExtraGUI::beep_if_allowed(Browser::main_window(),$self->{STAGE}->{BROWSER_WINDOW},'num_lock');
  }


  my %not_part_of_scores = ('space'=>' ');


  # Pressing the space bar gets you from the grades column to the names column.
  if ($key eq 'space') {
    $self->{COLUMN_FOCUS}=0;
    $self->clicked_on_student($who);
  }

  if ($key ne 'Tab' && !($key =~ m/^Control/)) {
    my $entry = $self->{SCORE_ENTRIES}->[$j]->{WIDGET};
    my $linked_var = \($self->{SCORE_VARIABLES}->[$j]);
    if (exists $not_part_of_scores{$key}) {my $remove=$not_part_of_scores{$key}; $score=~s/$remove$//}
    $self->{SCORE_VARIABLES}->[$j] = $score;

    # Queue up the latest version of the input string, including this keystroke:
    if ($self->{STAGE}->{ASSIGNMENTS}->specific_assignment_selected()) {
      # The following code is to deal with a nasty bug resulting from how Perl/Tk implements control key equivalents for menu items.
      # If the keyboard focus is in a grade space and you then hit control-W to close the file, Tk apparently does this:
      #          1. temporarily sets the widget's string to a null string (why!?!?!?)
      #          2. sends the keystroke to the widget, which results in a call to this routine
      #          3. calls the hook I gave for the File>Close menu item
      #          4. sets the entry widget's string back to what it should be
      # This results in the loss of that student's grade!
      # The following code detects that bug. The idea is that there's no way that hitting the W key (or any alphanumeric key)
      # can result in a null string in the entry widget, so if we get that combo, we should /not/ put the null string on the grade queue.
      # Note added 2004 Feb. 7: This is no longer an issue, because I figured out how to keep Control-Key events from being bound to this routine.
      my $menu_control_key_bug = ($score eq '') && ($key=~m/^[a-zA-Z0-9]$/);

      if (!$menu_control_key_bug) {
        $self->{STAGE}->{BROWSER_WINDOW}->grades_queue(
          ACTION=>'put',  KEY=>$who.".".$assignment,  SCORE=>$score, 
                  ENTRY=>$entry,  LINKED_VAR=>$linked_var,
        );
      }
    }

    # If appropriate, flush the queue, and select a different student.
    my %enter_it = ('Return'=>1,'KP_Enter'=>1,'Down'=>1,'Up'=>-1,'space'=>0);
    if (exists $enter_it{$key}) {
      $self->{STAGE}->{BROWSER_WINDOW}->grades_queue(ENTRY=>$entry,  LINKED_VAR=>$linked_var); # flush grades queue
      if ($enter_it{$key}!=0) {
        $j = $j+$enter_it{$key};
        if ($j<0) {$j=0}
        if ($j>$n-1) {$j=$n-1}
        $self->change_student($them->[$j]);
      }
    }
  }
}

=head4 key_pressed_in_roster()

Handle a key pressed in the roster.

=cut

sub key_pressed_in_roster {
  my $self = shift;
  my $who = shift; # student's database key
  my $j = shift;   # index into the array of students
  my $n = shift;   # number of students
  my $key = $Tk::event->K;
  my $sel = $self->{KBSEL};
  my $them = $self->{KEYS};
  #print "key=$key=\n"; #-----debugging
  my $gb = $self->{DATA}->{GB};
  if (!@$them) { # no file open, or the roster is empty
    ExtraGUI::beep_if_allowed(Browser::main_window(),$self->{STAGE}->{BROWSER_WINDOW},'empty_roster');
    return;
  }
  if ($key =~ m/\d/) { # Trying to enter grade when focus is on names column. Warn them it's going in the bit bucket.
    ExtraGUI::beep_if_allowed(Browser::main_window(),$self->{STAGE}->{BROWSER_WINDOW},'grade_in_name_column');
    return;
  }
  if ($key eq 'Up' || $key eq 'Down') {    # e.g., typed J to select Jones, then down-arrow to get Josephson
    $sel='';
  }                    
  if ($key eq 'apostrophe') {$key="'"}            
  if ($key =~ m/^(\w|\')$/ && $key ne '_' && !$self->{KBCTRL}) { # not Tab, control sequence, or underbar; could be a-z, A-Z, ', Chinese character,...
    $sel=$sel.lc($key); # Matches are case-insensitive, and we may as well impress that fact on them so they don't think they have to enter initial caps.
  } else {                        # not a normal alphabetic character
    my $recognized = 0;
    if ($key eq 'Delete' || $key eq 'BackSpace') {
      $recognized = 1;
      if (length($sel)>0) {
        $sel = substr($sel,0,length($sel)-1)
                        }
      else {
        ExtraGUI::beep_if_allowed(Browser::main_window(),$self->{STAGE}->{BROWSER_WINDOW},'nothing_left_to_delete'); # nothing left to delete
      }
    } # end if delete or backspace
    if ($key =~ m/^Control/) {        # Actual strings are Control-L and Control-R
      $recognized = 1;
      $self->{KBCTRL} = 1;
    }
    if ($key eq 'Shift' || $key eq 'Up' || $key eq 'Down' || $key eq 'Tab' || $key =~ m/^Shift/ || $key eq 'Num_Lock' 
         || $key eq 'Caps_Lock') {
      $recognized = 1;
    }
    if (!$recognized  && !$self->{KBCTRL}) { # They hit _, Escape, or some other key that doesn't make sense here.
      ExtraGUI::beep_if_allowed(Browser::main_window(),$self->{STAGE}->{BROWSER_WINDOW},'key_not_recognized',$key);
    }
  }

  # The following cases are handled below:
  # 1. They've typed in a string that doesn't match anybody. $match is null.
  # 2. They've typed in a string that matches someone. $match is their key
  # 3. They've hit an arrow key. $match is set appropriately.
  # 4. They've hit a key that doesn't affect anything. $match is the currently selected student.
  my $n_matches = 0;
  my @matches;
  my $match = '';                # ---- case 1 ----
  if ($sel ne "") {
    my $j=0;
    foreach my $w (@$them) { # $w is a database key
      my $who = join('_',reverse $gb->name($w)); # If a student, e.g., gets married, may need to change name, so last name doesn't match database key.
                                                 # Also, name may have punctuation (') that's not present in key.
      if ($who =~ m/^$sel/i) {
        $match = $w;                # ---- case 2 ----
        ++$n_matches;
        push @matches,[$w,$j];
      }
      $j++;
    }
  } else {
    if ($key eq 'Up' || $key eq 'Down') {
      # ---- case 3 ---- 
      if ($key eq 'Up') {$j--} else {$j++}
      if ($j<0) {$j=0}
      if ($j>$n-1) {$j=$n-1}
      $match = $them->[$j];
    } else {
      $match = $self->{SELECTED_STUDENT}; # ---- case 4 ----
    }
  }

  my $is_tab = ($key eq 'Tab');

  # If it's ambiguous, make our most reasonable guess as to which student to pick. The user will get audible feedback that there's an ambiguity,
  # but we want to minimize the chances that the user will have to do anything to correct the ambiguity.
  if ($n_matches>1) {
    my $j = 0; # index into @match; default to first match in alphabetical order
    # If some students who match have scores already, and others don't, go to the earliest blank one in alphabetical order.
    for (my $k=0; $k<$n_matches; $k++) {
      if ($self->{SCORE_VARIABLES}->[$matches[$k]->[1]] eq '') {
        $j = $k;
        last;
      }
    }
    # Make the final decision:
    $match = $matches[$j]->[0];
  }

  if (!$self->{KBTRL}) {
    my ($audio_feedback,$message);
    if ($n_matches==1 && $is_tab) {
      $audio_feedback = "ch"; # confirm that they got a unique match
    }
    if ($n_matches>1 && $is_tab) {
      $audio_feedback = "ambiguous"; # warn them they might have selected the wrong student
      $message = "ambiguous"; # FIXME -- not internationalized
    }
    if ($match eq '' && $key=~m/^\w$/) { # no such student
      $audio_feedback = "duh";
      $message = "no such student"; # FIXME -- not internationalized
    }
    if ($audio_feedback) {
      ExtraGUI::audio_feedback($audio_feedback); 
      $self->{STAGE}->{BROWSER_WINDOW}->set_footer_text($message) if $message;
    }
  }

  if ($key eq 'Tab') {                 # about to switch to the grades column; forget keyboard input
    $sel='';
  }                                
  $self->{KBSEL} = $sel;

  $self->change_student($match); # null string is ok
}

# The point of the following is to keep track of whether the control key is being held down. If it
# is, we don't want to select students based on the alphabetic key they hit.
sub key_released_in_roster {
  my $self = shift;
  my $who = shift; # student's database key
  my $j = shift;   # index into the array of students
  my $n = shift;   # number of students
  my $key = $Tk::event->K;
  if ($key =~ m/^Control/) {        # Actual strings are Control-L and Control-R for left and right control keys
    $self->{KBCTRL} = 0;
  }
}

# This gets called by refresh(). Don't call it directly and expect the GUI
# to get redrawn.
sub clear {
  my $self = shift;
  $self->{KEYS} = [];
  $self->{NAMES} = [];

  my $buttons = $self->{NAME_BUTTONS};
  foreach my $button(@$buttons) {
    $button->destroy();
  }
  $self->{NAME_BUTTONS} = [];

  my $scores = $self->{SCORE_ENTRIES};
  foreach my $score(@$scores) {
    $score->destroy_widget();
  }
  $self->{SCORE_ENTRIES} = [];

}

# null string is ok
sub change_student {
  my $self = shift;
  my $new = shift;
  $self->{SELECTED_STUDENT} = $new;
  $self->clicked_on_student($new); # ok if null
}

sub select_next_student {
  my $self = shift;
  my $what = shift; # 1 or -1
  if ($what==0) {return}
  my $foo = $self->{KEYS};
  my $n = @$foo;
  my $old;
  for (my $j=0; $j<=$n-1; $j++) {
    if ($self->{KEYS}->[$j] eq $self->{SELECTED_STUDENT}) {$old=$j}
  }
  if ($old eq '') {return}
  my $new = $old+$what;
  if ($new>=0 && $new<=$n-1) {
    $self->{SELECTED_STUDENT} = $self->{KEYS}->[$new];
    $self->clicked_on_student($self->{SELECTED_STUDENT});
  }
}


=head4 selected()

Get or set the key of the student who is currently selected.

=cut

sub selected {
  my $self = shift;
  if (@_) {
    $self->{SELECTED}=shift;
    $self->{STAGE}->roster_has_set_student($self->{SELECTED});
  }
  return $self->{SELECTED};
}



sub clicked_on_student {
  my $self = shift; # Roster
  my $key = shift;

  $self->selected($key);

  my $index;

  # Fiddle with colors, and only let the selected one have the focus:
  my $r = $self->{KEYS};
  my @keys = @$r;
  for (my $j=0; $j<@keys; $j++) {
    if ($keys[$j] eq $key) {
      $index = $j;
      $self->{NAME_BUTTONS}->[$j]->configure(-font=>ExtraGUI::font('bold'),-takefocus=>1);
      $self->{SCORE_ENTRIES}->[$j]->highlighted(1);
      if ($self->{STAGE}->{ASSIGNMENTS}->specific_assignment_selected()) {
        $self->{SCORE_ENTRIES}->[$j]->enabled(1);
        if ($self->{COLUMN_FOCUS}==0) {
          $self->{NAME_BUTTONS}->[$j]->focus();
        }
        else {
          $self->{SCORE_ENTRIES}->[$j]->focus();
        }
      }
    }
    else {
      $self->{NAME_BUTTONS}->[$j]->configure(-font=>ExtraGUI::font('plain'),-takefocus=>0);
      $self->{SCORE_ENTRIES}->[$j]->highlighted(0);
      $self->{SCORE_ENTRIES}->[$j]->enabled(0);
    }
  }

  # If they select a student using the keyboard, automatically scroll so that the student is visible:
  my $n = @keys+0.; # total students
  my ($first,$last) = $self->{SPREADSHEET}->Subwidget('yscrollbar')->get(); # first and last positions in the roster that are actually visible, expressed as numbers 0-1
  my $frac_vis = $last-$first;
  if ($key && defined $index && $n>0) { # check on n is both for efficiency and to avoid div by 0 below
    my $f = ($index+0.)/$n; # fraction of the way through the list at which this student is located; guaranteed no divide by 0 because $n has been tested
    my $current = $self->{SCROLL_LOCATION};
    if (! defined $current) {$current = 0.}
    my $moveto = $current;
    my $margin_relative_to_visible = .15;
    my $margin = $margin_relative_to_visible*$frac_vis;
          # ... Extra margin of error to make sure the desired student is not off the end.
          # Multiply by frac_vis because $margin_relative_to_visible the is thought of as a fraction of the *visible* area; e.g., in a huge class with 500 students,
          # the margin will correspond to a small fraction of the entire roster. $margin is relative to the whole scrolling canvas widget.
          # The choice of $margin_relative_to_visible is a compromise. If it's too small, we'll type 'a,' but the result may be that we don't see all the
          # students whose names begin with 'a.' If it's too big, we'll get a lot of unnecessary scrolling back and forth.
    # It's not possible for both of the following ifs to be satisfied, because margin is guaranteed to be small compared to frac_vis.
    if ($current+$frac_vis < $f+$margin) {$moveto=$f+$margin-$frac_vis}
          # ... too high, move down so selected student is visible
    if ($current>$f-$margin) {$moveto=$f-$margin}
          # ... too low, move up so selected student is visible
    if ($moveto<0) {$moveto=0}
    if ($moveto>1-$frac_vis+$margin) {$moveto=1-$frac_vis+$margin}
    if ($moveto>1) {$moveto=1}
    if ($moveto!=$current) {
      $self->{SPREADSHEET}->Subwidget('canvas')->yview('moveto',$moveto);
      $self->{SCROLL_LOCATION} = $moveto;
    }
  }

}



1;
