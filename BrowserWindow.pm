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
use Digest::SHA1;
use Version;
use POSIX qw(tmpnam);
use Stage;
use Assignments;
use Roster;
use Score;

BEGIN {
  eval "use ServerDialogs";
  eval "use OnlineGrades";
}

#---------------------------------------------------
# BrowserWindow class
#---------------------------------------------------

=head3 BrowserWindow

Encapsulates the whole GUI window.

=cut

package BrowserWindow;

use Words qw(w get_w);

#------------ Begin public methods --------------

=head4 new()

 BrowserWindow->new($browser_data,$parent_widget);

=cut

sub new {
  my $class = shift;
  my $data = shift;
  my $parent = shift;
  my $self = {};
  bless($self,$class);
  $self->is_modified(0);

  # Create widgets.
  $self->{PARENT} = $parent;
  $self->{DATA} = $data;
  $self->{MENU_BAR} = $self->menu_bar($parent);
  $self->{FOOTER_TEXT} = "";
  $self->{HEADER_TEXT} = "";
  my $footer = $parent->Label(-textvariable=>\($self->{FOOTER_TEXT}),-font=>ExtraGUI::font('plain'));
  my $header = $parent->Label(-textvariable=>\($self->{HEADER_TEXT}),-font=>ExtraGUI::font('plain'));
  $self->{STAGE} = Stage->new($self,$parent,$data);

  # Pack widgets.
  $self->{MENU_BAR}->pack(-side=>'top',-anchor=>'w',-fill=>'x');
  $header->pack(-side=>'top',-anchor=>'w');
  $self->{STAGE}->{FRAME}->pack(-side=>'top',-anchor=>'w');
  $footer->pack(-side=>'bottom',-anchor=>'w');
  $self->refresh_all();
  $parent->protocol("WM_DELETE_WINDOW",[sub{$_[0]->grades_queue(); $_[0]->quit()},$self]);
  return $self;
}

=head4 set_footer_text

Set the text at the bottom of the browser window.

=cut

sub set_footer_text {
  my $self = shift;
  my $message = shift;
  my $old_message = $self->{FOOTER_TEXT};
  # Problem: sometimes we get two messages, one immediately after the other.
  my $new = "$message........$old_message";
  $new = substr($new,0,72);
  $self->{FOOTER_TEXT} = $new; # This variable is tied to the widget.
}

sub set_header_text {
  my $self = shift;
  $self->{HEADER_TEXT} = shift;
}

=head4 is_modified()

Get or set a flag that says whether the file has been modified relative to
the version on disk. Side-effects: (1) Set the text at the footer of the
window. (2) Set the modification time of the GradeBook object. To make
memoization safe, this has to be called after the modification is *complete*.

=cut

sub is_modified {
  local $Words::words_prefix = "b.is_modified";
  my $self = shift;
  my $old = $self->{IS_MODIFIED};
  my $gb = '';
  my $file_open = exists($self->{DATA}) && $self->{DATA}->file_is_open();
  if ($file_open) {
    $gb = $self->{DATA}->{GB};
  }

  # Set whether I've been modified:
  if (@_) {
    $self->{IS_MODIFIED} = shift;
    if ($file_open) {
      if ($self->{IS_MODIFIED}) {
        # $self->set_footer_text(w('modified')); # not really necessary, because we autosave anyway; it also tends to obscure other, more relevant messages
        $gb->mark_modified_now();
               # In the case where IS_MODIFIED was already 1, and is being set to 1 again, we still have to do this. This is because, e.g., when
               # we put a grade on the queue, we call is_modified, but the operation isn't really complete. Then when we flush the queue again,
               # we complete the modification to the GradeBook object. When we flush, we need to set the time of modification again, because otherwise
               # memoization could get messed up.
      }
      else {
        # $self->set_footer_text(w('not_modified')); # not really necessary, because we autosave anyway; it also tends to obscure other, more relevant messages
      }
      $self->refresh_title() if $self->{IS_MODIFIED} != $old;
    }
    else {
      $self->set_footer_text('');
    }
  }

  # Return the result: have I been modified?
  return $self->{IS_MODIFIED};
}

=head4 refresh_all()

Calls refrest_title(), refresh_header(), refresh_roster(), and refresh_assignments().

=cut


sub refresh_all {
  my $self = shift;
  $self->refresh_title();
  $self->refresh_header();
  $self->refresh_roster();
  $self->refresh_assignments();
}

=head4 refresh_header()

Sets header text depending on the file that's open.

=cut

sub refresh_header {
  my $self = shift;
  local $Words::words_prefix = "b.refresh_header";
  my $browser_data = $self->{DATA};
  if ($browser_data->file_is_open()) {
    $self->set_header_text($browser_data->{GB}->title());
  }
  else {
    $self->set_header_text(w("no_file"));
  }
}


=head4 refresh_title()

Put's program name in header.

=cut

sub refresh_title {
  my $self = shift;
  local $Words::words_prefix = "b.refresh_title";
  my $browser_data = $self->{DATA};
  my $title = '';
  if ($browser_data->file_is_open()) {
    $title = w("program_name").": ".UtilOG::filename_with_path_stripped($browser_data->file_name());
    $title = $title . " (modified)" if $self->is_modified();
  }
  else {
    $title = w("program_name");
  }
  Browser::main_window()->title($title);
}


=head4 refresh_roster()

Flushes grades queue and refreshes $self->{ROSTER}.

=cut

sub refresh_roster {
  my $self = shift;
  my $data = $self->{DATA};
  $self->grades_queue();
  $self->{ROSTER}->refresh();
}

=head4 refresh_assignments()

Flushes grades queue and refreshes $self->{ASSIGNMENTS}.

=cut
sub refresh_assignments {
  my $self = shift;
  my $data = $self->{DATA};
  $self->grades_queue();
  $self->{ASSIGNMENTS}->refresh();
}

=head4 grades_queue()

When the user types in a new grade, it's in a fragile state. They could click somewhere
and select a different student or assignment, and then we need to make sure that the
student's precious grade data isn't lost. To make this totally safe, we implement
a special queue, where we save the grade that's being edited, keystroke by keystroke.
Internally, we maintain this as a hash, so when you make your second
keystroke, the score recorded from the first keystroke gets replaced.
It's vital to make sure this info is saved when we save the file, but that's relatively
easy (see save_file).
The other thing is that we want to make sure it gets recorded ASAP so that
the change is visible throughout the application. For that, we just
try to make sure to flush every single time the user does anything! That means
flushing the queue in refresh_roster(), refresh_assignments(),
add_or_drop()

=cut

my %queue; # moved lexical decl out of BEGIN block as a workaround for a bug in Perl 5.8.4
my %has_error_dialog;
my %linked_var;
BEGIN {
  %queue = ();
  %has_error_dialog = (); # Prevent two dialogs in a row from being displayed because of the same error in input.
  %linked_var = (); # For saving a variable that for some reason doesn't seem to get finalized.
  sub grades_queue {
    my $self = shift;
    my %args = (
      ACTION=>'flush',                # 'put', or 'flush'
      KEY=>'',                        # e.g. einstein_al.hw.12
      SCORE=>'',
      ENTRY=>'',
      LINKED_VAR=>'',
      @_,
    );  
    local $Words::words_prefix = "b.grades_queue";
    my $action = $args{ACTION};
    my $key = $args{KEY};
    my $score = $args{SCORE};
    my $linked_var = $args{LINKED_VAR};
    my $entry = $args{ENTRY};
    my $data = $self->{DATA};

    # We flush this queue on any excuse, and we may often do it when no file is
    # open. When that happens, well, we sure hope the queue was empty! In any case,
    # we just get dangling references unless we bail out here.
    # Note that a 'put' causes the modification flag to be set, but a 'flush' doesn't.
    # That's because we do flushes at the drop of a hat, unless there's been a previous
    # put, the flush isn't doing anything.

    if (!$data->file_is_open()) {return}

    my $gb = $data->{GB};

    if ($action eq 'put') {
      $queue{$key} = $score;
      $self->is_modified(1); # This is before the modification is complete, but we also call is_modified after the modification is complete, when the queue is flushed.
    }
    if ($action eq 'flush') {
      foreach my $key(keys %queue) {
        $key =~ m/([^\.]+)\.([^\.]+)\.([^\.]+)/;
        my ($who,$cat,$ass) = ($1,$2,$3);
        my $grade = $queue{$key};
        my $gv = $data->get_a_grade($cat.".".$ass,$who);
        my $change_entry = ($grade=~m/[x\+]$/i);
        my $trailing_x = ($grade =~ m/x\+?$/i);
        $grade =~ s/x//i;
        $grade =~ s/\+/\.5/g;
        $grade =~ s/^0(\d+)/$1/; # strip leading zeroes
        if ($change_entry) {
          if (ref $linked_var) {
            $$linked_var = $grade;
          }
          if (ref $entry) {
            $entry->icursor('end'); # otherwise the cursor gets out of whack because we edited the entry
          }
        }
        my $bogus = '';
        # First, check if they're numeric. There are several cases: numeric (possibly with decimal point), null,
        # only whitespace, erroneous input with bogus characters in it. The following regex checks whether it contains
        # only digits and dots, contains no more than one dot, and contains at least one digit. Can also have the
        # optional x on the end for extra credit, but that's already been stripped off. A minus sign on the front is also OK.
        #                        at least 1 digit       sign, then only digits and dots       not more than one dot
          my $old_was_numeric = ($gv    =~ m/[0-9]/) && ($gv    =~ m/^\-?[0-9\.]+$/)       && !($gv    =~ m/\..*\./);
          my $new_is_numeric  = ($grade =~ m/[0-9]/) && ($grade =~ m/^\-?[0-9\.]+$/)       && !($grade =~ m/\..*\./);
          # Nonnumeric input can be ok, but only in the special case of a blank grade or a nonnumeric type:
          if ((!$new_is_numeric) && $grade ne '' && $gb->category_property2($cat,'type') eq 'numerical') {
            $bogus = 'nonnumeric';
          }
        # If they're numeric, we only make the change if they're numerically different. It might seem kind of bogus to
        # check equality on numbers that might be floating point, but how would it make any difference if there was
        # a rounding error in the 8th decimal place of the student's grade? The point here is to avoid thinking the file
        # has been changed, and needs to be saved, when in fact it hasn't. One commonly occurring case is that the student
        # has a blank and you want to change it to a zero, or vice-versa; to me, this is a significant change, since it
        # indicates the student is at least going through the motions of participating. Another possibility is that you
        # erroneously enter somthing like "20foo", then realize you need to edit out the bogus characters and make it "20".
        if ($grade != $gv   ||  (!$old_was_numeric)  || (!$new_is_numeric)) {
                              # old code had this:  $grade eq '' && $gv eq '0'   or   $grade eq '0' && $gv eq '' ) {
          my $which = "$cat.$ass.$who";
          $linked_var{$which} = $linked_var;
          my $do_it = sub { # callback routine for setting the grade, which can either happen smoothly or after making the user correct an error
            delete($has_error_dialog{$which});
            $linked_var = $linked_var{$which};
            delete($linked_var{$which});
            if (!@_) {return} # Happens if they're asked to fix a too-high score, and they hit cancel.
            $grade = shift;
            $self->{STAGE}->grades_has_set_grade($who,$cat,$ass,$grade);
            if (ref $linked_var) {
              $$linked_var = $grade;
            }
            if (ref $entry) {
              $entry->icursor('end'); # otherwise the cursor gets out of whack because we edited the entry
            }
          };
          my $max = $gb->assignment_property($cat.".".$ass,"max");
          if ($bogus eq '' && $grade>$max && !$trailing_x && $max>0) {
            $bogus = 'too_high';
          }
          if (!exists $has_error_dialog{$which}) {
            if ($bogus ne '') {
              $has_error_dialog{$which} = 1;
              my $ass_name = $gb->assignment_name($cat,$ass);
              my $name = $data->key_to_name(KEY=>$who,ORDER=>'firstlast');
              ExtraGUI::ask(
                 PROMPT=>(sprintf w($bogus),$grade,$name,$ass_name,$max),
                 TITLE=>w("${bogus}_title"),
                 WIDTH=>40,
                 CALLBACK=>$do_it,
                 DEFAULT=>$grade,
                 BEEP=>1,
              );
            } # end if too high
            else {
              &$do_it($grade);
            } # end if not too high
				  } # end if no error dialog already open
        } # end if grade has actually changed
      } # end loop over queue
      %queue = ();
    } # end if flushing
    if ($action eq 'initialize') {
      %queue = ();
    }
  }
}

=head4 delete_assignment()

Delete an assignment.

=cut

sub delete_assignment {
  my $self = shift;
  local $Words::words_prefix = "b.delete_assignment";
  $self->grades_queue();
  my $data = $self->{DATA};
  my $gb = $data->{GB};
  my $cat = "";
  my $ass = "";
  my $key = "";
  if ($data->file_is_open() && exists $self->{STAGE} && exists $self->{STAGE}->{ASSIGNMENTS}) {
    $cat=$self->{STAGE}->{ASSIGNMENTS}->get_active_category();
    $key=$self->{STAGE}->{ASSIGNMENTS}->selected();
    $ass = $key;
    $ass =~ s/\.(.*)//;
    $ass = $1;
  };
  if ($cat eq '' || $ass eq '') {return}

  ExtraGUI::confirm(sprintf(w('confirm'),($gb->assignment_name($cat,$ass))),
    sub {
      if (shift) {
        $gb->delete_assignment($key);
        $self->{STAGE}->{ASSIGNMENTS}->selected($cat);
        $self->is_modified(1);
        $self->{STAGE}->{ROSTER}->refresh();
        $self->{STAGE}->{ASSIGNMENTS}->refresh();
      }
    }
  );
}

=head4 edit_assignment()

Give the user a form for editing information about a particular assignment.

=cut

sub edit_assignment {
  my $self = shift;
  local $Words::words_prefix = "b.edit_assignment";
  $self->grades_queue();
  my $data = $self->{DATA};
  my $gb = $data->{GB};
  my $roster = $self->{STAGE}->{ROSTER};
  my $cat = "";
  my $ass = "";
  my $key = "";
  if ($data->file_is_open() && exists $self->{STAGE} && exists $self->{STAGE}->{ASSIGNMENTS}) {
    $cat=$self->{STAGE}->{ASSIGNMENTS}->get_active_category();
    $key=$self->{STAGE}->{ASSIGNMENTS}->selected();
    $ass = $key;
    $ass =~ s/\.(.*)//;
    $ass = $1;
  };
  if ($cat eq '' || $ass eq '') {return}

  my %old = (
    'name'=>$gb->assignment_name($cat,$ass),
    'due'=>$gb->assignment_property($key,'due'),
    'max'=>$gb->assignment_property($key,'max'),
    'ignore'=>$gb->assignment_property($key,'ignore'),
    'key'=>$ass,
    'mp'=>$gb->assignment_property($key,'mp'),
  );
  if ($old{'ignore'} eq '') {$old{'ignore'} = 'false'}

  my $callback = sub {
    my $new = shift;
    my $did_something = 0;
    foreach my $what(keys %old) {
      if (!(exists $old{$what} && $old{$what} eq $new->{$what})) {
        $did_something = 1;
      }
    }
    if ($did_something) {
      if ($new->{'due'} eq '') {delete $new->{'due'}}
      if ($new->{'ignore'} eq 'false') {delete $new->{'ignore'}}

      if ($new->{'key'} ne $old{'key'}) {
        my $result = $gb->rekey_assignment($cat,$old{'key'},$new->{'key'});
        if ($result ne "") {
                ExtraGUI::error_message($result); # bug: always in English
        }
        $ass = $new->{'key'};
        $key = "$cat.$ass";
      }
      delete $new->{'key'};


      # The basic idea is that we don't want to store "name" parameters when the name of the assignment
      # can be correctly inferred from its category and key. The reason we need to set the assignment
      # properties twice is that if we don't do it the first time, the test against the default
      # assignment name won't work. Note that this has to work if they change the key, the name,
      # both, or neither.
      my $new_name = $new->{'name'};
      $new_name =~ s/\"/\'/g; # Otherwise we can't embed it in quotes in the gradebook file.
      delete $new->{'name'};
      $gb->assignment_properties($key,$new);
      if ($new_name ne $gb->default_assignment_name($cat,$ass)) {
        $new->{'name'} = $new_name;
      }
      $gb->assignment_properties($key,$new);

      $self->is_modified(1);
      $roster->refresh();
      $self->{STAGE}->{ASSIGNMENTS}->refresh(); # necesary if assignment was renamed
    };
  };

  my @inputs = (
          Input->new(KEY=>"name",PROMPT=>w("name"),TYPE=>'string',DEFAULT=>$old{'name'}),
          Input->new(KEY=>"key",PROMPT=>w("key"),TYPE=>'string',DEFAULT=>$old{'key'}),
          Input->new(KEY=>"max",PROMPT=>w("max"),TYPE=>'numeric',DEFAULT=>$old{'max'}),
          Input->new(KEY=>"due",PROMPT=>w("due"),TYPE=>'date',WIDGET_TYPE=>'date',TERM=>$gb->term(),DEFAULT=>$old{'due'}),
          Input->new(KEY=>"ignore",PROMPT=>w("ignore"),TYPE=>'string',DEFAULT=>$old{'ignore'},
                           WIDGET_TYPE=>'radio_buttons',
                           ITEM_MAP=>{'false'=>'no','true'=>'yes'},
                           ITEM_KEYS=>['true','false']),
  );
  if ($gb->marking_periods()) {
    my @rbo = $gb->marking_periods_in_order();
    my $rb = {};
    foreach my $mp(@rbo) {$rb->{$mp} = $mp}
    my $default = $gb->assignment_property($key,'mp') || $rbo[-1];
    push @inputs,(Input->new(KEY=>"mp",PROMPT=>w("mp"),TYPE=>'string',DEFAULT=>$default,WIDGET_TYPE=>'menu',ITEM_KEYS=>\@rbo,ITEM_MAP=>$rb));
  }
  ExtraGUI::fill_in_form(
    TITLE=>(sprintf w("title"),ucfirst($gb->assignment_name($cat,$ass))),
    CALLBACK=>$callback,
    COLUMNS=>2,
    INPUTS=>\@inputs,
  );

}

=head4 new_assignment()

Creates a new assignment. Calls refresh_assignments(), clicked_on_category(),
and clicked_on_assignment().

=cut

sub new_assignment {
  my $self = shift;
  local $Words::words_prefix = "b.new_assignment";

  my $data = $self->{DATA};
  my $gb = $data->{GB};
  my $cat = $self->{ASSIGNMENTS}->get_active_category();
  my $insert_before = ""; # This should be set by the menu item they select.
  my $assignment_exists_message = w('assignment_exists');

  my $callback = sub {
    my $results = shift; # a hash ref
    my $name;
    if ($gb->category_property_boolean($cat,'single')) {
      $name = '1';
    }
    else {
      $name = $results->{"name"};
    }
    my $max = $results->{"max"} || '';
    my $due = $results->{"due"};
    $name =~ s/\"/\'/g; # can't quote it if it contains quotes
    my $raw_name = $name;
    $name =~ s/[^\w]/_/g; # make a valid database key
    if ($due ne "") {$due = DateOG::disambiguate_year($due,$gb->term())}
    my $props = "\"max:$max\"";
    if ($due ne "") {$props = $props .",\"due:$due\""}
    my $mp = $results->{"mp"};
    if ($mp) {$props = $props . ",\"mp:$mp\""}
    if ($name ne $raw_name) {$props = $props .",\"name:$raw_name\""}
    if ($gb->assignment_exists("$cat.$name")) {
      ExtraGUI::error_message(sprintf $assignment_exists_message,$name,$cat);
    }
    else {
      my $result = $gb->add_assignment(CATEGORY=>$cat,ASS=>$name,COMES_BEFORE=>$insert_before,PROPERTIES=>$props);
      $self->is_modified(1);
      if ($result) {ExtraGUI::error_message($result); return 1}
      $gb->use_defaults_for_assignments();
      $self->{ASSIGNMENTS}->refresh_assignments();
      $self->{ASSIGNMENTS}->clicked_on_category($cat);
      $self->{ASSIGNMENTS}->clicked_on_assignment($name);
    }
  };

  if ($cat eq "") {print "no category\n";return} # Shouldn't happen, since menu item should be dimmed.
  my $cat_props = $gb->category_properties_comma_delimited($cat);

  my $whoops = '';
  my @inputs = ();
  if ($gb->category_property_boolean($cat,'single')) {
    if ($gb->category_contains_assignments($cat)) {$whoops = w('single_assignment_cat_already_has_one')}
  }
  else {
    push @inputs,Input->new(KEY=>"name",PROMPT=>w("name"),TYPE=>'string',BLANK_ALLOWED=>0);
  }
  my $max = $gb->category_max($cat);
  push @inputs,Input->new(KEY=>"max",PROMPT=>w("max_score"),TYPE=>'numeric',MIN=>0,DEFAULT=>$max);
  push @inputs,(Input->new(KEY=>"due",PROMPT=>w("due"),TYPE=>'date',WIDGET_TYPE=>'date',TERM=>$gb->term(),BLANK_ALLOWED=>1));
  if ($gb->marking_periods()) {
    my @rbo = $gb->marking_periods_in_order();
    my $h = $gb->marking_periods();
    my $rb = {};
    foreach my $mp(@rbo) {$rb->{$mp} = $mp}
    my $default_mp = $rbo[0];
    foreach my $mp(@rbo) {my $start=$h->{$mp}; if (DateOG::are_in_chronological_order($start,DateOG::current_date_sortable())) {$default_mp=$mp}}
    push @inputs,(Input->new(KEY=>"mp",PROMPT=>w("mp"),TYPE=>'string',DEFAULT=>$default_mp,WIDGET_TYPE=>'radio_buttons',ITEM_MAP=>$rb,ITEM_KEYS=>\@rbo));
  }
  if ($whoops eq '') {
    ExtraGUI::fill_in_form(
      TITLE=>(sprintf w("new_assignment_title"),$gb->category_name_singular($cat)),
      CALLBACK=>$callback,
      COLUMNS=>2,
      INPUTS=>\@inputs,
    );
  }
  else {
    ExtraGUI::error_message($whoops);
  }

}

sub new_file {
  my $self = shift;
  local $Words::words_prefix = "new_file"; # shared with TermUI.pm

  $self->close_file();

  my $file_name = "";

  my $results = {}; # inputs from the form

  # Due to Perl's lack of a real way of nesting subroutines, the
  # callback routines have to be in reverse order.

  my $callback2 = sub {
    local $Words::words_prefix = "new_file"; # shared with TermUI.pm
    $results = shift;
    my $title = $results->{"title"};
    my $staff = $results->{"staff"};
    my $days_of_week = $results->{"days_of_week"};
    my $time = $results->{"time"};
    my $year = $results->{"year"};
    my $month = $results->{"month"};
    my $term = $year."-".$month;
    my $password = $results->{"password"};
    $title =~ s/\"/\\\"/g;
    my $gb = GradeBook->new(TITLE=>$title,STAFF=>$staff,DAYS=>$days_of_week,TIME=>$time,
                            TERM=>$term,FILE_NAME=>$file_name,PASSWORD=>$password);
    my $result = $gb->write();
    if ($result ne '') {
      ExtraGUI::error_message($result)
    }
    else {
      $self->open_file($file_name,$password);
      ExtraGUI::message(w('file_created'));
    }
  };

  my $callback1 = sub {
  $file_name = shift;
  if (!$file_name) {return}
  if (-e $file_name) {ExtraGUI::error_message(sprintf w('file_exists'),$file_name); return}
  ExtraGUI::fill_in_form(
    TITLE=>$file_name,
    CALLBACK=>$callback2,
    COLUMNS=>1,
    INPUTS=>[
      Input->new(KEY=>"title",PROMPT=>w("title"),TYPE=>'string',BLANK_ALLOWED=>0),
      Input->new(KEY=>"staff",PROMPT=>w("staff_gui"),
                              DEFAULT=>UtilOG::guess_username(),TYPE=>'string',BLANK_ALLOWED=>1),
      Input->new(KEY=>"days_of_week",PROMPT=>w("days_of_week"),
                              DEFAULT=>"MTWRF",TYPE=>'string',BLANK_ALLOWED=>1),
      Input->new(KEY=>"time",PROMPT=>w("time"),
                              DEFAULT=>"",TYPE=>'time',BLANK_ALLOWED=>1),
      Input->new(KEY=>"year",PROMPT=>w("year"),
                              DEFAULT=>DateOG::current_date("year"),TYPE=>'numeric',MIN=>1900),
      Input->new(KEY=>"month",PROMPT=>w("month"),DEFAULT=>DateOG::current_date("month"),
                  TYPE=>'numeric',MIN=>1,MAX=>12),
      Input->new(KEY=>"password",PROMPT=>w("password"),DEFAULT=>"",TYPE=>'string'),
    ]
  );
  };


  ExtraGUI::choose_file(
    CALLBACK=>$callback1,
    TITLE=>w('file_dlog_title'),
    CREATE=>1,
    PATH=>Preferences->new()->get('recent_directory'),
    WHAT=>'output',
  );
  
}

sub list_of_recent_files_is_frozen {
  my $self = shift;
  my $prefs = Preferences->new(); # Can't use the one associated with the gradebook, because may not have one open.
  return ($prefs->get('freeze_recent') eq '1');
}

=head4 prepare_list_of_recent_files_for_menu

Prepares a list of array references containing info about the list of recently used files, for use
in the file menu. If a file doesn't exist, this has the side-effect of permanently deleting
it from the list (assuming the list isn't frozen).

=cut

sub prepare_list_of_recent_files_for_menu {
  my $self = shift;
  my $prefs = Preferences->new(); # Can't use the one associated with the gradebook, because may not have one open.
  my @names = $prefs->get('recent_files');
  my @list = ();
  my @rebuilt = (); # eliminate files that don't exist anymore
  if (@names) {
    my $n=0;
    foreach my $recent_file(@names) {
      if (-e Portable::do_glob_easy($recent_file)) {
        push @rebuilt,$recent_file;
        my $tail_of_filename = UtilOG::filename_with_path_stripped($recent_file);
        if ($tail_of_filename ne '') {
          $n++;
          my $label = "$n. $tail_of_filename";
          push @list,["recent_file$n",$label,$recent_file,sub{my $safe=$self->{SAFE}; &$safe(); $self->open_file($recent_file)}];
        }
      }
    }
  }
  if (!($self->list_of_recent_files_is_frozen())) {$prefs->set('recent_files',\@rebuilt);}
  return @list;
}

sub adjust_after_undo {
  my $self = shift;
  my $gb = shift;
  my $operation = shift;
  my $gui_stuff = shift; # hash ref like, e.g., {'roster_refresh'=>1}
  my $direction = shift; # save, undo, or revert
  $self->enable_and_disable_menu_items();
  #print "gui stuff = ".join(',',(keys %$gui_stuff))."=, operation=$operation, direction=$direction qwe\n";
  if (exists $gui_stuff->{'roster_refresh'}) {$self->{STAGE}->{ROSTER}->refresh()}
  if (exists $gui_stuff->{'assignments_refresh'}) {$self->{STAGE}->{ASSIGNMENTS}->refresh()}
  if ($operation eq 'set_grades_on_assignment' && $direction eq 'undo') {$self->{STAGE}->{ROSTER}->refresh()}
}

=head4 open_file()

Normally, we call this routine with no arguments, and it offers the
user a dialog box and opens a file they select. You can also call it
with the filename and password as an argument, in which case there is no interaction
with the user.

=cut

sub open_file {
  my $self = shift;
  my $file_name = "";
  if (@_) {$file_name = shift}
  my $password = "---no password---";
  if (@_) {$password = shift}

  local $Words::words_prefix = "b.open_file";
  my $data = $self->{DATA};
  if ($data->file_is_open()) {$self->close_file()}
  my $sub2 = sub{
      if (!@_) {return} # user hit cancel instead of entering password
      $password = shift;
      if ($file_name eq "") {return}
      my $prefs = Preferences->new();
      my @recent_files = $prefs->get('recent_files');
      my $full_path = UtilOG::absolute_pathname($file_name);
      #print "full_path=$full_path\n";
      my $this_directory = UtilOG::directory_containing_filename($full_path);
      #print "setting recent dir, --$full_path,$this_directory\n";
      $prefs->set('recent_directory',$this_directory);
      my ($result,$mark_modified) = $data->open($file_name,$password); # actually reads in the file
      if ($result) {
        $self->is_modified($mark_modified);
      }
      my $gb = $data->{GB}; # may be undef if there was an error, e.g., bogus password
      if (ref $gb) {
        $prefs = $gb->preferences(); # otherwise hang on to the prefs object we already have
        $gb->undo_callback(sub{$self->adjust_after_undo(@_)});
      }
      $self->refresh_all();
      $self->enable_and_disable_menu_items();
      my @rebuilt = ($full_path);
      foreach my $recent_file(@recent_files) {
        my $already_there = 0;
        foreach my $already(@rebuilt) {
          if ($already eq $recent_file) {$already_there = 1}
        }
        if (@rebuilt<5 && !$already_there) {
          push @rebuilt,$recent_file;
        }
      }
      if (!($self->list_of_recent_files_is_frozen())) {$prefs->set('recent_files',\@rebuilt);}

      # Rebuild the list of recent files in the file menu:
      if (!($self->list_of_recent_files_is_frozen())) {
        $self->clear_recent_files_from_menu();
        my $menu = $self->{FILE_MENUB}->menu();
        my $l = $self->{RECENT_FILE_LABELS};
        my @prepared_list = $self->prepare_list_of_recent_files_for_menu();
        foreach my $stuff(@prepared_list) {
          my ($foo,$label,$recent_file,$sub) = @$stuff; # $foo is something like "recent_file3" for the third file -- do I ever even use this?
          $menu->insert($menu->index($self->{LABEL_OF_CLEAR_RECENT}),'command',-label=>$label,-command=>$sub);
          push @$l,$label;
        }
        $self->enable_or_disable_specific_menu_item('FILE','clear_recent'); # did all the menus above, but now need to recheck this item on this menu
      }

  };
  my $sub1 = sub {
      $file_name = shift;
      if ($file_name eq "") {return}
      if ($password eq "---no password---") {
        ExtraGUI::ask(PROMPT=>w('password'),CALLBACK=>$sub2,PASSWORD=>1);
      }
      else {
        &$sub2($password);
      }
  };
  if ($file_name eq "") {
    my @args = (CALLBACK=>$sub1,TITLE=>w('dlog_title'));
    my $prefs = Preferences->new(); # Can't use the one associated with the gradebook, because may not have one open.
    my $recent_directory = $prefs->get('recent_directory');
    #print "recent directory = $recent_directory\n";
    if ($recent_directory ne '') {
      push @args,'PATH';
      push @args,$recent_directory;
    }
    ExtraGUI::choose_file(@args);
  }
  else {
    &$sub1($file_name);
  }
  $self->enable_and_disable_menu_items();
}

sub rekey_file {
  my $self = shift;
  local $Words::words_prefix = "b.rekey_file";
  my $file_name;
  my $prefs = Preferences->new(); # Can't use the one associated with the gradebook, because they don't have one open.
  my $sub2 = sub {
      my $password = shift;
      my $gb = GradeBook->read($file_name);
      if (!ref $gb) {ExtraGUI::error_message($gb)}
      $gb->close();
      $gb->password($password);
      my $err = $gb->write_to_named_file($file_name);
      ExtraGUI::error_message($err) if $err;
  };
  my $sub1 = sub {
      $file_name = shift;
      if ($file_name eq "") {return}
      ExtraGUI::ask(PROMPT=>w('password'),CALLBACK=>$sub2,PASSWORD=>1);
  };
  my @args = (CALLBACK=>$sub1,TITLE=>w('dlog_title'));
  my $recent_directory = $prefs->get('recent_directory');
  if ($recent_directory ne '') {
    push @args,'PATH';
    push @args,$recent_directory;
  }
  ExtraGUI::choose_file(@args);
}

sub reconcile {
  my $self = shift;
  local $Words::words_prefix = "b.reconcile";
  my ($file_a,$file_b,$recent_directory,$password,$a);
  my $sub4 = sub {
    local $Words::words_prefix = "b.reconcile";
    my $ass = shift;
    my $who = shift;
    my $a_grade = shift;
    my $b_grade = shift;
    my $message_form = w('pick');
    my $message = sprintf $message_form,$who,$ass,$a_grade,$b_grade;
    my $decision;
    ExtraGUI::confirm($message,sub {$decision = shift},w('yes'),w('no'));
    Browser::main_window()->waitVariable(\$decision);
    return $decision;
  };
  my $sub3 = sub {
      local $Words::words_prefix = "b.reconcile";
                  my $file_b = shift;
      my $b = GradeBook->read($file_b,$password); # assume same password
      if (!ref $b) {ExtraGUI::error_message($b); return}
      $b->close();
      my $log = $a->union($b,$sub4);
      if ($log eq '') {
        $log="No changes.\n";
        my $a_clone = GradeBook->read($file_a,$password);
        my $b_clone = GradeBook->read($file_b,$password);
        $a_clone->close();
        $b_clone->close();
        if ('' ne $b_clone->union($a_clone)) {
          $log = "File $file_a\ncontained more data than file\n$file_b,\n".
                 "but the two files agreed on all the data they had in common, so\n".
                 "no changes were made to the first file. The second file is incomplete,\n".
                 "and should probably be discarded. If you want the details on how the files\n".
                 "differed, you can copy both files, and repeat this operation with the roles\n".
                 "reversed. Do not do this with the original copies of the files, however, unless\n".
                 "you think you should actually be deleting the additional data in the first file.\n";
        }
      }
      $log = "Changing file $file_a,\n"."folding in file $file_b\n".$log;
      my $result = $a->write_to_named_file($file_a);
      if ($result) {ExtraGUI::error_message($result); return}
                        ExtraGUI::show_text(TITLE=>w('summary'),TEXT=>$log,WIDTH=>80);
  };
  my $sub2 = sub {
      local $Words::words_prefix = "b.reconcile";
      $password = shift;
      $a = GradeBook->read($file_a,$password);
      if (!ref $a) {ExtraGUI::error_message($a); return}
      $a->close();
      my @args2 = (CALLBACK=>$sub3,TITLE=>w('file_to_fold_in'));
      if ($recent_directory ne '') {
        push @args2,'PATH';
        push @args2,$recent_directory;
                  }
      ExtraGUI::choose_file(@args2);
                };
  my $sub1 = sub {
      local $Words::words_prefix = "b.reconcile";
      $file_a = shift;
      if ($file_a eq "") {return}
      ExtraGUI::ask(PROMPT=>w('password'),CALLBACK=>$sub2,PASSWORD=>1);
  };
  my @args = (CALLBACK=>$sub1,TITLE=>w('file_to_change'));
  my $prefs = Preferences->new(); # Can't use the one associated with the gradebook, because they don't have one open.
  $recent_directory = $prefs->get('recent_directory');
  if ($recent_directory ne '') {
    push @args,'PATH';
    push @args,$recent_directory;
  }
  ExtraGUI::choose_file(@args);
}

sub strip_watermark {
  my $self = shift;
  local $Words::words_prefix = "b.strip_watermark";
  my $file_name;
  my $sub = sub {
    $file_name = shift;
    my $err = GradeBook::strip_watermark_from_file($file_name);
    if ($err ne '') {ExtraGUI::error_message($err)}
  };
  my @args = (CALLBACK=>$sub,TITLE=>w('dlog_title'));
  my $prefs = Preferences->new(); # Can't use the one associated with the gradebook, because they don't have one open.
  my $recent_directory = $prefs->get('recent_directory');
  if ($recent_directory ne '') {
    push @args,'PATH';
    push @args,$recent_directory;
  }
  ExtraGUI::choose_file(@args);
}

=head4 close_file()

Calls close() on the BrowserData object. Rebuilds the menu above the roster, and disables items in all menus
that you can't do when there's no file open.

=cut

sub close_file {
  my $self = shift;
  my $file_name = shift;
  my $data = $self->{DATA};
  if (!$data->file_is_open()) {return}
  my $result = $data->close($file_name,$self->is_modified());
  $self->enable_and_disable_menu_items();
  $self->{STAGE}->{ASSIGNMENTS}->refresh_categories();
  $self->{STAGE}->{ASSIGNMENTS}->{CAT_INTENTIONALLY_SELECTED} = '';
  $self->{STAGE}->{ROSTER}->selected('');
  $self->{STAGE}->{ROSTER}->make_options_menu();
  $self->refresh_all();
  if ($result) {
    ExtraGUI::error_message($result)
  }
  else {
    $self->is_modified(0);
  }
  $self->check_for_files_to_delete();
}

sub properties {
  my $self = shift;
  local $Words::words_prefix = "b.properties";
  my $gb = $self->{DATA}->{GB};
  my $t = '';
  my $w = $gb->weights_enabled(); #0 unweighted 1 weighted 2 no categories
  if ($w==0) {$t = $t . w('weighting_mode') . ': ' . w('straight_points') . "\n"}
  if ($w==1) {$t = $t . w('weighting_mode') . ': ' . w('weighted') . "\n"}
  if ($w==2) {$t = $t . w('weighting_mode') . ': ' . w('no_cats') . "\n"}
  my $r = $gb->marking_periods();
  if (defined $r) {
    $t = $t . w('marking_periods') . ': ' . join(',',$gb->marking_periods_in_order())  . "\n";
  }
  else {
    $t = $t . w('marking_periods') . ': ' . w('none')  . "\n";
  }
  ExtraGUI::show_text(TEXT=>$t,TITLE=>w('properties'));
}

sub revert {
    my $self = shift;
    ExtraGUI::confirm(w("confirm_revert"),
      sub { 
        my $ok = shift; 
        if ($ok) {
          my $gb = $self->{DATA}->{GB};
          $gb->revert() if ref $gb;
        }
      },
      undef,undef,1);
}

sub check_for_files_to_delete {
  my $self = shift;
  my $data = $self->{DATA};
  my $gb = $data->{GB};
  my $prefs;
  if ($gb) {$prefs = $gb->preferences()} else {$prefs = Preferences->new()}
  my @files = $prefs->get('files_to_delete');
  if (@files) {
    foreach my $file(@files) {
      if (-e $file) {
        ExtraGUI::choices(
          "Delete $file? Keeping Online Grades' xml files around on your disk is a security risk, because they contain your password.",
          [ "Delete" , "Not now, but remind me later" , "Delete automatically in 10 minutes." , "Don't delete"         ],
          [
          # delete
          sub {
            unlink($file)==1 or ExtraGUI::error_message("Error deleting $file, $!");
            if (!-e $file) {$prefs->delete_from_list('files_to_delete',$file)} # if deletion succeeded
           },
          # later
          sub {
            # Don't need to do anything. It'll still be on the list the next time we check.
          },
          # automatically, later
          sub {
            if (Portable::os_has_unix_shell()) {
              system("sleep 60 && rm $file &"); # list of files to delete won't get cleaned up until the next time we're in this routine
            }
            else {
              ExtraGUI::error_message("Sorry, this feature only works on Unix.");
            }
          },
          # don't delete
          sub {
            $prefs->delete_from_list('files_to_delete',$file);
          },
          ]
        );
      }
      else {
        $prefs->delete_from_list('files_to_delete',$file);
      }
    }
  }
}

=head4 save_file()

Flush the grades queue, save the file, enable and disable menu items,
and refresh all.

=cut

sub save_file {
  my $self = shift;
  my $file_name = shift;
  my $data = $self->{DATA};
  $self->grades_queue(); # flush the queue
  if (!$data->file_is_open()) {return}
  my $result = $data->save();
  $self->enable_and_disable_menu_items();
  if ($result) {ExtraGUI::error_message($result)}
  $self->is_modified(0);
}

=head4 export()

Exports the file to another format.

=cut

sub export {
  my $self = shift;
  local $Words::words_prefix = "b.export";
  my $gb = $self->{DATA}->{GB};
  my $prefs;
  if ($gb) {$prefs = $gb->preferences()} else {$prefs = Preferences->new()}
  my $recent_dir = $prefs->get('recent_directory');
  my $filename = $gb->file_name();
  my $do_it = sub {
    my $selection = shift;
    my $format = $selection->{'format'};
    my $extension = {'json'=>'gb','gdl'=>'gdl','old'=>'gb','online_grades'=>'xml'}->{$format};
    my $result;
    my $already_saved = 0;
    my $exported_filename = $filename;
    $exported_filename =~ s/\.\w+$/\.$extension/;
    if ($format eq 'gdl') {
      $result = $gb->export_gradel();
    }
    if ($format eq 'json' || $format eq 'old') {
      # Write to a temp file and then slurp the contents back out, so we can use ExtraGUI::save_plain_text_to_file on the resulting string.
      my $err;
      my $temp_file = POSIX::tmpnam();
      $err = $gb->write_to_named_file($temp_file,$format);
      if ($err) {
        ExtraGUI::error_message($err);
      }
      else {
        local $/; # slurp whole file;
        open(F,"<$temp_file");
        $result = <F>;
        close F;
        unlink($temp_file);
      }
    }
    if ($format eq 'online_grades') {
      my $err;
      $self->OnlineGrades::upload(); # handles setting permissions, marking for deletion, etc., for security, since file contains password
      $already_saved = 1;
    }
    if (!$already_saved && $result) {
      ExtraGUI::save_plain_text_to_file($result,$recent_dir,$exported_filename,{'on_top_ok'=>1});
    }
  };
  my $rb = {'json'=>'OpenGrade 3 (.gb)','old'=>'OpenGrade 2 (.gb)','gdl'=>'GradeL'}; # labels for radio buttons
  my $rbo = ['json','old','gdl']; # defines order
  if (eval{OnlineGrades::available()}) {
    $rb->{'online_grades'} = 'Online Grades';
    push @$rbo,'online_grades';
  }
  ExtraGUI::fill_in_form(
    TITLE=>w('export_to'),
    CALLBACK=>$do_it,
    COLUMNS=>1,
    INPUTS=>[
          Input->new(KEY=>"format",PROMPT=>w('prompt'),TYPE=>'string',DEFAULT=>'json',
                           WIDGET_TYPE=>'menu',
                           ITEM_MAP=>$rb,
                           ITEM_KEYS=>$rbo),
  ],
  );
}

=head4 clone()

Clones the file. Clears the list of assignments and the roster, but leaves categories and grading standards intact.

=cut

sub clone {
  my $self = shift;
  local $Words::words_prefix = "b.clone";
  my $gb = $self->{DATA}->{GB};
  $gb->clear_assignment_list();
  $gb->clear_roster();
  $gb->clear_grades();
  my $staff = $gb->staff();
  my $standards = GradeBook::hash_to_comma_delimited($gb->standards());
  my $marking_periods;
  if ($gb->marking_periods()) {
    $marking_periods = GradeBook::hash_to_comma_delimited($gb->marking_periods());
  }
  my $callback1 = sub {
    my $file_name = shift;
    $gb->file_name($file_name);
    $gb->write_to_named_file($file_name);
  };
  my $callback2 = sub {
    my $inputs = shift;
    my $term = $inputs->{'year'}.'-'.$inputs->{'month'};
    $gb->set_class_data({'title'=>$inputs->{'title'},'staff'=>$staff,'days'=>$inputs->{'days_of_week'},
                         'time'=>$inputs->{'time'},'term'=>$term,'dir'=>$inputs->{'dir'},'standards'=>$standards,'marking_periods'=>$marking_periods});
    $gb->password($inputs->{'password'});
    ExtraGUI::choose_file(TITLE=>w('save_as'),WHAT=>'output',CREATE=>1,CALLBACK=>$callback1);
  };
  ExtraGUI::fill_in_form(
      TITLE=>w('what'),
      CALLBACK=>$callback2,
      COLUMNS=>1,
      INPUTS=>[
        Input->new(KEY=>"title",PROMPT=>w("title"),TYPE=>'string',BLANK_ALLOWED=>0,DEFAULT=>$gb->title()),
        Input->new(KEY=>"days_of_week",PROMPT=>w("days_of_week"),
                              DEFAULT=>"MTWRF",TYPE=>'string',BLANK_ALLOWED=>1),
        Input->new(KEY=>"time",PROMPT=>w("time"),
                              DEFAULT=>"",TYPE=>'time',BLANK_ALLOWED=>1),
        Input->new(KEY=>"year",PROMPT=>w("year"),
                              DEFAULT=>DateOG::current_date("year"),TYPE=>'numeric',MIN=>1900),
        Input->new(KEY=>"month",PROMPT=>w("month"),DEFAULT=>DateOG::current_date("month"),
                  TYPE=>'numeric',MIN=>1,MAX=>12),
        Input->new(KEY=>"password",PROMPT=>w("password"),DEFAULT=>"",TYPE=>'string'),
        Input->new(KEY=>"dir",PROMPT=>w("dir"),TYPE=>'string',DEFAULT=>$gb->dir()),
      ]
    );
}


=head4 options()

Set options. The argument tells what kind: 'beep', etc. Server options are handled
in ServerDialogs.pm, not here. Some of these options are in the preferences file,
some (grading standards) in the gradebook.

=cut
sub options {
  my $self = shift;
  my $what = shift;
  local $Words::words_prefix = "b.options";
  my $data = $self->{DATA};
  my $gb = $data->{GB};

  if ($what eq 'beep') {
    $self->set_a_preference_item($what,1);
  }
  if ($what eq 'justify') {
    $self->set_a_preference_item($what,'left'); # default to left because at one time right caused problem with Perl/Tk bug
  }
  if ($what eq 'editor_command' || $what eq 'spreadsheet_command' || $what eq 'print_command') {
    $self->set_a_preference_item($what,'');
  }
  if ($what eq 'hash_function') {
    $self->set_a_preference_item($what,Version::default_hash_function());
  }
  if ($what eq 'marking_periods' && $gb) {
    my $callback = sub {
      my $r = shift;
      my $p = {
        $r->{'n1'} => $r->{'d1'},
        $r->{'n2'} => $r->{'d2'},
        $r->{'n3'} => $r->{'d3'},
        $r->{'n4'} => $r->{'d4'},
      };
      delete $p->{''};
      $gb->set_marking_periods(GradeBook::hash_to_comma_delimited($p));
      $self->is_modified(1);
      $self->enable_and_disable_menu_items();
      if (keys %$p) {
        # Could be adding marking periods to a gradebook that previously didn't have them.
        # Typically we want to set them all to the first one on the list.
        my @mp = $gb->marking_periods_in_order();
        my $default = $mp[-1];
        my @ass = split(",",$gb->assignment_list());
        my @oops = ();
        foreach my $key(@ass) {
          if (! $gb->assignment_property($key,'mp') || !exists $p->{$gb->assignment_property($key,'mp')}) { push @oops,$key }
        }
        if (@oops) {
          my @rbo = $gb->marking_periods_in_order();
          my $rb = {};
          foreach my $mp(@rbo) {$rb->{$mp} = $mp}
          my $default = $rbo[0];
          ExtraGUI::fill_in_form(
              TITLE=>w('oops'),
              INFO=>"Some preexisting assignments did not have marking periods set. Set them to:",
              CALLBACK=>sub {
                my $r = shift;
                $self->is_modified(1);
                foreach my $key(@oops) {
                   my $h = $gb->assignment_properties($key);
                   $h->{'mp'} = $r->{'mp'};
                   $gb->assignment_properties($key,$h);
                }
              },
              COLUMNS=>2,
              INPUTS=>          [Input->new(KEY=>"mp",
                        TYPE=>'string',DEFAULT=>$default,WIDGET_TYPE=>'radio_buttons',ITEM_MAP=>$rb,ITEM_KEYS=>\@rbo)],
          );
        }
      }
    };

    my $mp = $gb->marking_periods();
    my @mp = $gb->marking_periods_in_order();
    my @inputs = ();
    for (my $i=1; $i<=4; $i++) {
      my $p = $mp[$i-1];
      push @inputs,Input->new(KEY=>"n$i",PROMPT=>sprintf(w('marking_periods.name'),$i),TYPE=>'string',DEFAULT=>($p || ''));
      push @inputs,Input->new(KEY=>"d$i",PROMPT=>sprintf(w('marking_periods.start'),$i),WIDGET_TYPE=>'date',TYPE=>'date',TERM=>$gb->term(),DEFAULT=>($mp->{$p} || ''));
    }
    ExtraGUI::fill_in_form(
        TITLE=>w('mp_title'),
        CALLBACK=>$callback,
        COLUMNS=>2,
        INPUTS=>\@inputs,
    );
  }
  if ($what eq 'standards' && $gb) {
    my ($box,$f);
    my $grade_symbols = 'A B C D F';
    my @symbols = ();
    my %standards = ();

    # The following have to be in reverse order because perl doesn't really have nested subroutines.

    my $standards_callback2 = sub {
      my $results = shift;
      $standards{$symbols[$#symbols]} = 0;
      for (my $i=0; $i<=$#symbols-1; $i++) {
        my $symbol = $symbols[$i];
        $standards{$symbol} = $results->{$symbol};
        if ($i>=1 && $standards{$symbol}>=$standards{$symbols[$i-1]}) {
          ExtraGUI::error_message(w('standards.not_in_order'));
        }
      }
      my $standards_comma_delimited = "";
      for (my $i=0; $i<=$#symbols; $i++) {
        $standards_comma_delimited = $standards_comma_delimited 
            . ',"'.$symbols[$i].':'.$standards{$symbols[$i]}.'"';
      }
      $standards_comma_delimited =~ s/^\,//; # remove leading comma
      $gb->set_standards($standards_comma_delimited);
      $self->is_modified(1);
    };

    my $standards_callback1 = sub {
      local $Words::words_prefix = "b.options";
      my $preexisting_standards = $gb->standards();
      @symbols = split /\s+/,$grade_symbols;
      if (@symbols<2) {ExtraGUI::error_message(w('standards.at_least_two')); return}
      if (@symbols>100) {ExtraGUI::error_message(w('standards.too_many')); return}
      # Check for duplicates:
      for (my $i=0; $i<=$#symbols; $i++) {
        for (my $j=0; $j<=$#symbols; $j++) {
          if ($i!=$j && $symbols[$i] eq $symbols[$j]) {ExtraGUI::error_message(w('standards.not_unique')); return}
        }
      }
      my @inputs = ();
      # The last symbol has to have a minimum of zero, so it doesn't even have a space in the form.
      for (my $i=0; $i<=$#symbols-1; $i++) {
        my $symbol = $symbols[$i];
        my $default = "";
        if (exists $preexisting_standards->{$symbol}) {$default=$preexisting_standards->{$symbol}}
        push @inputs, Input->new(KEY=>$symbol,PROMPT=>$symbol,TYPE=>'numeric',MIN=>0,MAX=>100,DEFAULT=>$default);
      }
      ExtraGUI::fill_in_form(
        TITLE=>w('standards.pct_title'),
        CALLBACK=>$standards_callback2,
        COLUMNS=>2,
        INPUTS=>\@inputs
      );
    };

    my $previous_standards = $gb->standards(); # hash ref like {"A"=>90,...}
    my @previous_symbols = keys(%$previous_standards);
    @previous_symbols = sort {$previous_standards->{$b} <=> $previous_standards->{$a}} @previous_symbols;
    $box = Browser::empty_toplevel_window(w('standards.symbols_title'));
    $f = $box->Frame->pack(-side => 'bottom');
    $f->Button(-text=>w("ok"),-command=>sub{$box->destroy(); &$standards_callback1(); }
    )->pack(-side=>'left');
    $f->Button(-text=>w("cancel"),-command=> sub{$box->destroy(); }
    )->pack(-side=>'left');
    my $e = $box->Entry(-textvariable=>\$grade_symbols,-width=>60)->pack(-side=>'top');
    my $type;
    if (@previous_symbols) {
      $type = 3;
      $grade_symbols = '';
      foreach my $symbol(@previous_symbols) {$grade_symbols = $grade_symbols . ' '.$symbol}
    }
    else {
      $type = 1;
      $grade_symbols = 'A B C D F';
    }
    $grade_symbols =~ s/^ //; # strip leading blank
    $box->Radiobutton(-text=>'ABCDF',-justify=>'left',-value=>1,-variable=>\$type,
               -command=>sub{$grade_symbols='A B C D F'})
         ->pack(-side=>'top',-anchor=>'w');
    $box->Radiobutton(-text=>'ABCDF+-',-justify=>'left',-value=>2,-variable=>\$type,
               -command=>sub{$grade_symbols='A+ A A- B+ B B- C+ C C- D+ D D- F'})
         ->pack(-side=>'top',-anchor=>'w');
    $box->Radiobutton(-text=>w('standards.custom'),-justify=>'left',-value=>3,-variable=>\$type,
              -command=>sub{$grade_symbols=''; $e->focus()})
         ->pack(-side=>'top',-anchor=>'w');
  }
}

sub set_a_preference_item {
  my $self = shift;
  my $what = shift;
  my $default = shift; # default if there's no item in the preferences file yet; if this is a radio button, this  has to be the symbolic value, not the index
  local $Words::words_prefix = "b.options";
  my $data = $self->{DATA};
  my $gb = $data->{GB};
  my $prefs;
  if ($gb) {$prefs = $gb->preferences()} else {$prefs = Preferences->new()}
  my $button_map = {
    'hash_function' => {0=>'SHA1',1=>'Whirlpool'},
    'justify'       => {0=>'left',1=>'right'},
  }->{$what};
  my %reverse_button_map;
  %reverse_button_map = reverse %$button_map if defined $button_map;
  my $do_pref = sub {
    my $stuff = shift; # array ref
    my ($pref_name,$type,$widget_type,$dialog_options,$do_after) = @$stuff;
    my @merge = %$dialog_options;
    my $default;
    if ($prefs->get($pref_name)) {
      $default = $prefs->get($pref_name);
    }
    $default = $reverse_button_map{$default} if defined $button_map;
    my @inputs = (
       Input->new(KEY=>'pref',
                   PROMPT=>w("preferences.$what"),
                   DEFAULT=>$default,
                   TYPE=>$type,
                   WIDGET_TYPE=>$widget_type,
                   @merge
                         ),
    );
    ExtraGUI::fill_in_form(
      INPUTS => \@inputs,
      COLUMNS=>1,
      CALLBACK=>sub{
        my $results = shift;
        my $value = $results->{'pref'};
        $value = $button_map->{$value} if defined $button_map;
        $prefs->set($what, $value);
        &$do_after();
      }
    );
  };
  &$do_pref(
    {
      'beep'    =>['beep'    ,'string','radio_buttons',{},sub{}],
      'justify' =>['justify' ,'string','radio_buttons',{ITEM_MAP=>$button_map,ITEM_KEYS=>[0,1]},sub{$self->refresh_roster()}],
      'editor_command' => ['editor_command','string','entry',{},sub{}],
      'spreadsheet_command' => ['spreadsheet_command','string','entry',{},sub{}],
      'print_command' => ['print_command','string','entry',{},sub{}],
      'hash_function' =>['hash_function' ,'string','radio_buttons',{ITEM_MAP=>$button_map,ITEM_KEYS=>[0,1]},sub{}],
    }
    ->{$what}
  );
}

=head4 report()

Display a report. The argument tells what kind: 'class_totals', etc.

=cut

sub report {
  my $self = shift;
  my $what = shift;
  my $data = $self->{DATA};
  my $gb = $data->{GB};
  my $prefs = $gb->preferences();
  my $recent_dir = $prefs->get('recent_directory');
  my $filename = $gb->file_name();
  local $Words::words_prefix = "b.report";
  if ($what eq "stats_ass") {
    my $format = "plain";
    my $title = w("$what.title");
    my $cat=$self->{ASSIGNMENTS}->get_active_category();
    my $ass=$self->{ASSIGNMENTS}->selected();
    $ass =~ s/^[^.]*\.//;
    ExtraGUI::show_text(TITLE=>$title,TEXT=>Report::statistics_ass($gb,$format,$cat,$ass)->text(),PATH=>$recent_dir);
  }
  if ($what eq "sort_by_overall" || $what eq "sort_by_category" || $what eq "sort_by_assignment") {
    # These are all the ones that require the user to decide what to sort by.
    my $format = "plain";
    my $mp;
    my $title = w("$what.title");
    my $sort_type = -1;
    my @inputs;
    my @rbo = ('all',$gb->marking_periods_in_order());
    my $rb = {};
    foreach my $mp(@rbo) {$rb->{$mp} = $mp}
    $rb->{'all'} = w('all_marking_periods');
    my $default = $rbo[0];
    push @inputs,Input->new(KEY=>"sort_type",TYPE=>'string',DEFAULT=>0,WIDGET_TYPE=>'radio_buttons',ITEM_MAP=>{0=>w('sort_by_score'),1=>w('sort_by_name')},ITEM_KEYS=>[0,1]);
    if ($gb->marking_periods() && $what ne "sort_by_assignment") {
      push @inputs,Input->new(KEY=>"mp",TYPE=>'string',DEFAULT=>$default,WIDGET_TYPE=>'menu',ITEM_MAP=>$rb,ITEM_KEYS=>\@rbo);
    }
    ExtraGUI::fill_in_form(
              TITLE=>w("$what.title"),
              CALLBACK=>sub {
                my $r = shift;
                $mp = $r->{'mp'}; # will be undef if no MPs in this gradebook
                if ($mp eq 'all') {$mp=undef} # user picked all
                $sort_type = $r->{'sort_type'};
                if ($sort_type == 1) {$format=$format.'*'}
                if ($what eq "sort_by_overall") {
                  ExtraGUI::show_text(TITLE=>$title,TEXT=>Report::sort($gb,$format,$mp)->text(),PATH=>$recent_dir);
                }
                if ($what eq "sort_by_category") {
                  my $cat=$self->{ASSIGNMENTS}->get_active_category();
                  ExtraGUI::show_text(TITLE=>$title,TEXT=>Report::sort($gb,$format,$mp,$cat)->text(),PATH=>$recent_dir);
                }
                if ($what eq "sort_by_assignment") {
                  my $cat=$self->{ASSIGNMENTS}->get_active_category();
                  my $ass=$self->{ASSIGNMENTS}->selected();
                  $ass =~ s/^[^.]*\.//;
                  ExtraGUI::show_text(TITLE=>$title,TEXT=>Report::sort($gb,$format,$mp,$cat,$ass)->text(),PATH=>$recent_dir);
                }
              },
              COLUMNS=>1,
              WIDTH=>40,
              INPUTS=>\@inputs,
    );
  }
  if ($what eq "student") {
    my $r = $self->{ROSTER};
    my $key = $r->selected();
    my $name = $data->key_to_name(KEY=>$key,ORDER=>"firstlast");
    my $t= Report::student(GB=>$gb,STUDENT=>$key,FORMAT=>"plain");
    ExtraGUI::show_text(TITLE=>$name,TEXT=>$t->text(),PATH=>$recent_dir);
  }
  if ($what eq "table") {
    my $r = $self->{ROSTER};
    my ($t,$width)= Report::table(GB=>$gb,FORMAT=>"plain");
    ExtraGUI::show_text(TITLE=>'',TEXT=>$t->text(),WIDTH=>$width,PATH=>$recent_dir);
  }
  if ($what eq "roster") {
    my @roster = $gb->student_keys();
    @roster = sort {$gb->compare_names($a,$b)} @roster;
    my @r = ();
    foreach my $who(@roster) {
      my ($first,$last) = $gb->name($who);
      push @r,"$first $last";
    }
    my $t = join("\n",@r);
    my $roster_filename = $filename;
    $roster_filename =~ s/\.gb/\.roster/;
    my $extra_buttons = {};
    if (Portable::os_has_unix_shell()) {
      $extra_buttons = {
        w('graphical_roster')=>sub {
           my $f = POSIX::tmpnam().".svg"; # without the SVG, inkscape prints a warning to the console
           unless (open(F,">$f")) {ExtraGUI::error_message("Error opening file $f for output, $!"); exit}
           print F Report::roster_to_svg(\@r,$gb->title());
           close F;
           my $c = "inkscape --print=\"| lpr\" $f && rm $f"; 
           system($c)==0 or ExtraGUI::error_message("Error executing Unix shell command $c, $?");
         }
      }
    }
    ExtraGUI::show_text(TITLE=>'',TEXT=>$t,PATH=>$recent_dir,FILENAME=>$roster_filename,
         EXTRA_BUTTONS=>$extra_buttons);
  }
  if ($what eq "spreadsheet") {
    my $command = $prefs->get('spreadsheet_command');
    my $spreadsheet_filename = $filename;
    $spreadsheet_filename =~ s/\.gb/\.csv/;
    my $box = Browser::empty_toplevel_window('Spreadsheet');
    my $f = $box->Frame->pack(-side => 'bottom');
    my $r = $gb->category_array();
    my @cats = @$r;
    my @scores = ();
    my @selected = ();
    my $i = 0;
    push @scores,['overall',\($selected[$i]),''];
    if ($command eq '') {
      $f->Label(-text=>'You may want to use the Preferences menu to set a command used to open a spreadsheet.')->pack(-anchor=>'w');
    }
    #my $g = $f->Frame()->pack();
    my $g = $f->Scrolled("Frame",-scrollbars=>'e',-width=>500,-height=>500)->pack();
    $g->Checkbutton(-text=>"overall",-variable=>\($selected[$i]))->pack(-anchor=>'w');
    ++$i;
    foreach my $cat(@cats) {
      push @scores,['category',\($selected[$i]),$cat];
      $g->Checkbutton(-text=>$gb->category_name_plural($cat),-variable=>\($selected[$i]))->pack(-anchor=>'w');
      ++$i;
      my $a = $gb->array_of_assignments_in_category($cat);
      foreach my $ass(@$a) {
        push @scores,['assignment',\($selected[$i]),"$cat.$ass"];
        $g->Checkbutton(-text=>'- '.$gb->assignment_name("$cat.$ass"),-variable=>\($selected[$i]))->pack(-anchor=>'w');
        ++$i;
      }
    }
    $f->Button(-text=>"ok",
       -command=>
         sub{
           $box->destroy();
           my $text = '';
           my @roster =  sort {$gb->compare_names($a,$b)} $gb->student_keys();
           my  @row = ('"name"                    ');
           foreach my $score(@scores) {
             my ($type,$selected,$what) = @$score;
             $selected = $$selected;
             if ($selected) {
               my $name;
               $name = 'overall' if $type eq 'overall';
               $name = $gb->category_name_plural($what) if $type eq 'category';
               $name = $gb->assignment_name($what) if $type eq 'assignment';
               push @row,"\"$name\"";
             }
             $text = join(",",@row) . "\n";
           }
           foreach my $who(@roster) {
             my ($first,$last) = $gb->name($who);
             @row = (sprintf('%-26s',"\"$first $last\""));
             foreach my $score(@scores) {
               my ($type,$selected,$what) = @$score;
               $selected = $$selected;
               if ($selected) {
                 my $points;
                 if ($type eq 'overall') {
                   Crunch::totals($gb,$who)->{'all'}  =~ m@(.*)/@;
                   $points = $1;
                 }
                 if ($type eq 'category') {
                   Crunch::total_one_cat($gb,$who,$what,$gb->array_of_assignments_in_category($what),1)  =~ m@(.*)/@;
                   $points = $1;
                 }
                 if ($type eq 'assignment') {
                   my ($cat,$ass) = $gb->split_cat_dot_ass($what);
                   $points = $gb->get_current_grade($who,$cat,$ass);
                 }
                 if ($points eq '') {$points = 0}
                 push @row,$points;
               }
             }
             #$text = $text . join(",\t",@row) . "\n";
             $text = $text . join(",",@row) . "\n";
           }
           ExtraGUI::show_text(TITLE=>'',TEXT=>$text,PATH=>$recent_dir,FILENAME=>$spreadsheet_filename,OPEN_WITH=>$command,DESCRIBE_OPEN_WITH=>'Open in OpenOffice Calc');
         }
    )->pack();
  }
  if ($what eq "stats") {
    ExtraGUI::show_text(TITLE=>w('stats_title'),TEXT=>Report::stats(GB=>$gb,FORMAT=>"plain")->text(),PATH=>$recent_dir);
  }
}

=head4 quit()

Takes no arguments. Closes the file this Browser object has open, and any other files; exits.

=cut

sub quit {
  my $self = shift;
  $self->close_file();
  ogr::clean_up_before_exiting();
  if (ref Browser::main_window()) {Browser::main_window()->destroy}
}

=head4 edit_student()

Takes no arguments.

=cut

sub edit_student {
  my $self = shift;
  local $Words::words_prefix = "b.edit_student";
  $self->grades_queue();
  my $data = $self->{DATA};
  my $gb = $data->{GB};
  my $roster = $self->{STAGE}->{ROSTER};
  my $student=$roster->selected();
  my $name = $data->key_to_name(KEY=>$student,ORDER=>'firstlast');


  if ($student eq "" || !($name =~ m/\w+/)) {return}
         # ...See comments on the similar test in add_or_drop().

  my ($first,$last) = $gb->name($student);
  my %old = (
    'last'=>$last,
    'first'=>$first,
    'id'=>$gb->get_student_property($student,'id'),
  );

  my $callback = sub {
    my $new = shift;
    my $did_something = 0;
    foreach my $what(keys %old) {
      if (!(exists $old{$what} && $old{$what} eq $new->{$what})) {
        $gb->set_student_property($student,$what,$new->{$what});
        $did_something = 1;
      }
    }
    if ($did_something) {
      $self->is_modified(1);
      $roster->refresh();
    };
  };

  ExtraGUI::fill_in_form(
    TITLE=>(sprintf w("title"),$name),
    CALLBACK=>$callback,
    COLUMNS=>2,
    INPUTS=>[
          Input->new(KEY=>"last",PROMPT=>w("last"),TYPE=>'string',DEFAULT=>$old{'last'}),
          Input->new(KEY=>"first",PROMPT=>w("first"),TYPE=>'string',DEFAULT=>$old{'first'}),
          Input->new(KEY=>"id",PROMPT=>w("id"),TYPE=>'string',DEFAULT=>$old{'id'}),
    ]
  );
}

=head4 add_or_drop()

Takes one argument, 'add', 'drop', or 'reinstate'.

=cut

sub add_or_drop {
  my $self = shift;
  my $action = shift;
  local $Words::words_prefix = "b.add_or_drop";
  $self->grades_queue();
  my $data = $self->{DATA};
  my $gb = $data->{GB};
  my $roster = $self->{STAGE}->{ROSTER};
  my $student=$roster->selected();
  my $name = $data->key_to_name(KEY=>$student,ORDER=>'firstlast');

  my $did_something = sub {
      $self->is_modified(1);
      $roster->refresh();
  };

  if ($action eq 'drop') {
    if ($student eq "" || !($name =~ m/\w+/)) {return}
         # ...The $name clause shouldn't be necessary, but one time
         # I somehow got this dialog box to come up with null string for the
         # name. Wish I could figure out how to reproduce that, but anyway
         # this check keeps anything bogus from happening.
    ExtraGUI::confirm(
                     sprintf(w('confirm'),$name),
                     sub {
                       if (shift) {
                         $gb->drop_student($student);
                         $roster->selected("");
                         &$did_something();
                       }
                     }
    );
  }
  if ($action eq 'add') {
    my $continue_looping = 1;
    while ($continue_looping) {
      $continue_looping = 0;
      my $did_form = 0;
      ExtraGUI::fill_in_form(
        INPUTS => [
          Input->new(KEY=>'last',PROMPT=>w('last'),TYPE=>'string',BLANK_ALLOWED=>0),
          Input->new(KEY=>'first',PROMPT=>w('first'),TYPE=>'string',BLANK_ALLOWED=>0),
          Input->new(KEY=>'id',PROMPT=>w('id'),TYPE=>'string'),
        ],
        TITLE=>w('add_title'),
        INFO=>w('add_students_info'),
        CANCEL_CALLBACK=>sub{$did_form=1},
        CALLBACK=>sub {
                       my $results = shift; # hash ref
                       my ($key,$err) = $gb->add_student(
                         LAST=>$results->{'last'},
                         FIRST=>$results->{'first'},
                         ID=>$results->{'id'});
                       if ($err ne '') {ExtraGUI::error_message(sprintf w($err),($results->{'first'}.' '.$results->{'last'}))}
                       &$did_something();
                       $continue_looping = 1;
                       $did_form = 1;
                     },
        OK_TEXT=>w('add'),
        CANCEL_TEXT=>w('done'),
        XOFFSET=>300,
        YOFFSET=>30,
      );
      Browser::main_window()->waitVariable(\$did_form);
    }
  }
  if ($action eq 'reinstate') {

    # Currently, there's no way to select a dropped student from the regular menu, but
    # I may add that in the future. So right here, I should check if the selected student
    # is a dropped student, and if she is, select her automatically in the dialog box I make.

    my $who = '';

    my $box = Browser::empty_toplevel_window(w('reinstate_title'));
    my $lb = $box->Scrolled("Listbox",-scrollbars=>"e")
                       ->pack(-side=>'top',-expand=>1,-fill=>'y');

    my @k = $gb->student_keys("dropped");
    my @names = ();
    my %name_to_key;
    foreach my $key(@k) {
      my $name = $data->key_to_name(KEY=>$key);
      push @names,$name;
      $name_to_key{$name} = $key;
    }
    $lb->insert('end',@names);
    $lb->bind('<Button-1>',
      sub {
        # $who = $k[$lb->curselection()];
        #    ... used to work, but no longer does
        $who = $name_to_key{$lb->get($lb->curselection())};
      }
    );
    $box->Button(-text=>w("ok"),-command=>sub{
      $box->destroy();
      $gb->reinstate_student($who);
      &$did_something();
    })->pack();
    $box->Button(-text=>w("cancel"),-command=>sub{$box->destroy()})->pack();

  }

}

sub delete_category {
  my $self = shift;
  local $Words::words_prefix = "b.delete_category";
  $self->grades_queue();
  my $data = $self->{DATA};
  my $gb = $data->{GB};
  my $assignments = $self->{STAGE}->{ASSIGNMENTS};
  my $cat = "";
  if ($data->file_is_open() && exists $self->{STAGE} && exists $self->{STAGE}->{ASSIGNMENTS}) {
    $cat=$self->{STAGE}->{ASSIGNMENTS}->get_active_category();
  };
  if ($cat eq '') {return}
  my $r = $gb->array_of_assignments_in_category($cat);
  my $n = @$r;
  ExtraGUI::confirm(
    sprintf(
      w('confirm'),
      $gb->category_name_singular($cat),
      $n,
      $gb->category_name_plural($cat),
    ),
    sub {
      if (shift) {
        $gb->delete_category($cat);
        $self->{STAGE}->{ASSIGNMENTS}->selected($gb->array_of_assignments_in_category($cat)->[0]);
        $self->is_modified(1);
        $self->{STAGE}->{ROSTER}->refresh();
        $self->{STAGE}->{ASSIGNMENTS}->refresh();
      }
    },
    undef,
    undef,
    1 # beep
  );
}

sub edit_category_weights {
  my $self = shift;
  local $Words::words_prefix = "b.edit_category_weights";
  $self->grades_queue();
  my $data = $self->{DATA};
  my $gb = $data->{GB};
  my $assignments = $self->{STAGE}->{ASSIGNMENTS};

  if (!$gb->has_categories()) {
    ExtraGUI::error_message(w('no_categories'));
    return;
  }

  if (!$gb->weights_enabled()) {
    ExtraGUI::error_message(w('not_weighted'));
    return;
  }

  my $did_something = sub {
      $self->is_modified(1);
      $assignments->refresh();
  };

  my $categories_ref = $gb->category_array();
  my @categories = @$categories_ref;

  my @inputs = ();
  foreach my $cat(@categories) {
    push @inputs,Input->new(KEY=>$cat,PROMPT=>(sprintf w('weight_for'),$gb->category_name_plural($cat)),
                            TYPE=>'numeric',MIN=>0,DEFAULT=>$gb->category_property($cat,'weight'));
  }

    ExtraGUI::fill_in_form(
      INPUTS => \@inputs,
      COLUMNS=>2,
      TITLE=>w('title'),
      CALLBACK=>sub {
                       local $Words::words_prefix = "edit_category_weights";
                       my $results = shift; # hash ref

                       foreach my $cat(keys %$results) {
                         $gb->category_property($cat,'weight',$results->{$cat});
                       }
                       &$did_something();
                     }
    );

}

sub new_category {
  my $self = shift;
  local $Words::words_prefix = "edit_categories"; # shared with TermUI
  $self->grades_queue();
  my $data = $self->{DATA};
  my $gb = $data->{GB};
  my $assignments = $self->{STAGE}->{ASSIGNMENTS};

  my $did_something = sub {
      $self->is_modified(1);
      $assignments->refresh();
  };

  my $types = $gb->types();
  my $type_map = {};
  my $type_order = $types->{'order'};
  foreach my $type(@$type_order) {
    $type_map->{$type} = w($types->{'data'}->{$type}->{'description'});
  }
  my @inputs = (
        Input->new(KEY=>'key',PROMPT=>w('enter_short_name'),TYPE=>'string',BLANK_ALLOWED=>0),
        Input->new(KEY=>'sing',PROMPT=>w('enter_singular_noun'),TYPE=>'string',BLANK_ALLOWED=>0),
        Input->new(KEY=>'pl',PROMPT=>w('enter_plural_noun'),TYPE=>'string'),
        Input->new(KEY=>'n_drop',PROMPT=>w('enter_number_to_drop'),DEFAULT=>0,TYPE=>'numeric',MIN=>0),
        Input->new(KEY=>'count',PROMPT=>w('b.will_it_count'),DEFAULT=>1,TYPE=>'string',
                   WIDGET_TYPE=>'radio_buttons'),
        Input->new(KEY=>'single',PROMPT=>w('b.is_it_single'),DEFAULT=>0,TYPE=>'string',
                   WIDGET_TYPE=>'radio_buttons'),
        Input->new(KEY=>'max',PROMPT=>w('enter_max'),TYPE=>'numeric',MIN=>0),
        Input->new(KEY=>'type',PROMPT=>w('type'),TYPE=>'string',WIDGET_TYPE=>'menu',ITEM_KEYS=>$type_order,ITEM_MAP=>$type_map,DEFAULT=>'numerical'),
      );
    if ($gb->weights_enabled()!=0) {
      my $blank_allowed = 1;
      my $prompt = w('gimme_weight');
      if ($gb->weights_enabled()==1) {$blank_allowed=0; $prompt=w('gimme_weight_required')}
      push @inputs,Input->new(KEY=>'weight',PROMPT=>$prompt,TYPE=>'numeric',MIN=>0,BLANK_ALLOWED=>$blank_allowed);
    }

    ExtraGUI::fill_in_form(
      INPUTS => \@inputs,
      COLUMNS=>1,
      TITLE=>w('add_title'),
      MAX_HEIGHT=>40,
      CALLBACK=>sub {
                       local $Words::words_prefix = "edit_categories"; # shared with TermUI
                       my $results = shift; # hash ref
                       my $key = $results->{'key'};
                       # The following only affects the key, not the name the user sees:
                         $key = lc($key);
                         $key =~ s/[^\w]//g;
                       my $sing = $results->{'sing'};
                       my $pl  = $results->{'pl'};
                       my $drop =   $results->{'n_drop'};
                       my $ignored =  !($results->{'count'});
                       my $single = $results->{'single'};
                       my $max =  $results->{'max'};
                       my $w =  $results->{'weight'};
                       my $type =  $type_map->{$results->{'type'}};
                       my $stuff = "\"catname:$sing,$pl\"";
                       if ($max) {$stuff = $stuff . ",\"max:$max\""}
                       if ($drop>=1) {$stuff = $stuff . ",\"drop:$drop\""}
                       if ($ignored) {$stuff = $stuff . ",\"ignore:true\""}
                       if ($single) {$stuff = $stuff . ",\"single:true\""}
                       if ($w ne "") {$stuff = $stuff . ",\"weight:$w\""}
                       if ($type ne "" && $type ne 'numerical') {$stuff = $stuff . ",\"type:$type\""}
                       if ($gb->category_exists($key)) {ExtraGUI::error_message(w('category_exists')); return}
                       $gb->add_category($key,$stuff);
                       &$did_something();
                     }
    );

}


sub negate_binary {
  my $x = shift;
  if ($x) {return 0} else {return 1}
}

=head4 edit_category()

This lets you edit anything about the category except for the weights,
which is what edit_category_weights() is for. The "ignore" and "max"
parameters of a category are the defaults for its assignments. If the
user changes these, she'll be prompted as to whether to propagate the
new value down to all the assignments in the category.

=cut

sub edit_category {
  my $self = shift;
  local $Words::words_prefix = "edit_categories"; # shared with TermUI
  $self->grades_queue();
  my $data = $self->{DATA};
  my $gb = $data->{GB};
  my $assignments = $self->{STAGE}->{ASSIGNMENTS};
  my $roster = $self->{STAGE}->{ROSTER};
  my $cat = "";
  if ($data->file_is_open() && exists $self->{STAGE} && exists $self->{STAGE}->{ASSIGNMENTS}) {
    $cat=$self->{STAGE}->{ASSIGNMENTS}->get_active_category();
  };
  if ($cat eq '') {return}


  my %old = (
    'sing'=>$gb->category_name_singular($cat),
    'pl'=>$gb->category_name_plural($cat),
    'drop'=>$gb->category_property($cat,'drop'),
    'max'=>$gb->category_property($cat,'max'),
    'ignore'=>$gb->category_property_boolean($cat,'ignore'),
    'single'=>$gb->category_property_boolean($cat,'single'),
    'type'=>$gb->category_property2($cat,'type'), # guaranteed to return numerical rather than undef
  );
  if ($old{'drop'} eq '') {$old{'drop'} = 0}
  if ($old{'ignore'} eq '') {$old{'ignore'} = 0}
  if ($old{'single'} eq '') {$old{'single'} = 0}

  my $callback = sub {
    local $Words::words_prefix = "edit_categories"; # shared with TermUI
    my $new = shift;
    my $did_something = 0;
    my %changed;
    my $changed_heritable = 0;
    foreach my $what(keys %old) {
      if (!(exists $old{$what} && $old{$what} eq $new->{$what})) {
        $did_something = 1;
        $changed{$what} = 1;
        if ($what eq 'ignore' || $what eq 'max') {$changed_heritable=1}
      }
    }
    if ($did_something) {
      my $sing = $new->{'sing'};
      my $pl  = $new->{'pl'};
      my $drop =   $new->{'drop'};
      my $ignore =   $new->{'ignore'};
      my $max =  $new->{'max'};
      my $type = $new->{'type'};

      my $single = $old{'single'};
      if (exists $new->{'single'}) {$single = $new->{'single'}}

      $sing =~ s/\"/\'/g; # Otherwise we can't embed it in quotes in the gradebook file.
      $pl =~ s/\"/\'/g;   # ditto.

      my $stuff = "\"catname:$sing,$pl\"";
      if ($max ne '') {$stuff = $stuff . ",\"max:$max\""}
      if ($drop>=1) {$stuff = $stuff . ",\"drop:$drop\""}
      if ($ignore) {$stuff = $stuff . ",\"ignore:true\""}
      if ($single) {$stuff = $stuff . ",\"single:true\""}
      my $w = $gb->category_property($cat,'weight');
      if ($w ne "") {$stuff = $stuff . ",\"weight:$w\""}
      if ($type ne "numerical") {$stuff = $stuff . ",\"type:$type\""}
      $gb->set_all_category_properties($cat,$stuff);
      $self->is_modified(1);
      $roster->refresh();
      $self->{STAGE}->{ASSIGNMENTS}->refresh(); # necesary if this caused names of assmts to change

      if ($changed_heritable && $gb->number_of_assignments_in_category($cat)>0) {
        my @inputs = ();
        if ($changed{'ignore'}) {
          my $ignore_prompt = w('propagate_ignore');
          if (!$ignore) {$ignore_prompt=w('propagate_not_ignore')}
          push @inputs,Input->new(KEY=>'ignore',PROMPT=>$ignore_prompt,TYPE=>'string',DEFAULT=>1,
                   WIDGET_TYPE=>'radio_buttons');
        }
        if ($changed{'max'}) {
          push @inputs,Input->new(KEY=>'max',PROMPT=>w('propagate_max'),TYPE=>'string',DEFAULT=>1,
                   WIDGET_TYPE=>'radio_buttons');
        }
        ExtraGUI::fill_in_form(
          INPUTS => \@inputs,
          COLUMNS=>1,
          CALLBACK=>sub {
                      local $Words::words_prefix = "edit_categories"; # shared with TermUI
                      my $results = shift;
                      my $assignments = $gb->array_of_assignments_in_category($cat);
                      my @things = ('ignore','max');
                      foreach my $ass(@$assignments) {
                        foreach my $thing(@things) {
                          if ($results->{$thing}) {
                            my $props = $gb->assignment_properties("$cat.$ass");
                            my $change_to = $new->{$thing};
                            if ($thing eq 'ignore') {$change_to = ('false','true')[$change_to]}
                            $props->{$thing} = $change_to;
                            $gb->assignment_properties("$cat.$ass",$props);
                          }
                        }
                      }
                    }
        );
      }
    };
  };


  my $types = $gb->types();
  my $type_map = {};
  my $type_order = $types->{'order'};
  foreach my $type(@$type_order) {
    $type_map->{$type} = w($types->{'data'}->{$type}->{'description'});
  }
  my @inputs = (
        Input->new(KEY=>'sing',PROMPT=>w('enter_singular_noun'),TYPE=>'string',BLANK_ALLOWED=>0,
                        DEFAULT=>$gb->category_name_singular($cat)),
        Input->new(KEY=>'pl',PROMPT=>w('enter_plural_noun'),TYPE=>'string',
                        DEFAULT=>$gb->category_name_plural($cat)),
        Input->new(KEY=>'drop',PROMPT=>w('enter_number_to_drop'),DEFAULT=>$old{'drop'},
                                           TYPE=>'numeric',MIN=>0),
        Input->new(KEY=>'max',PROMPT=>w('enter_max'),DEFAULT=>$old{'max'},
                                           TYPE=>'numeric',MIN=>0,BLANK_ALLOWED=>1),
        Input->new(KEY=>'ignore',PROMPT=>w('b.is_it_ignored'),DEFAULT=>$old{'ignore'},
                   TYPE=>'string',WIDGET_TYPE=>'radio_buttons'),
        Input->new(KEY=>'type',PROMPT=>w('type'),TYPE=>'string',WIDGET_TYPE=>'menu',ITEM_KEYS=>$type_order,ITEM_MAP=>$type_map,DEFAULT=>$old{'type'}),
      );

    if ($gb->number_of_assignments_in_category($cat)<2) {
      push @inputs,
        Input->new(KEY=>'single',PROMPT=>w('b.is_it_single'),DEFAULT=>$old{'single'},TYPE=>'string',
                   WIDGET_TYPE=>'radio_buttons'),
    }

    ExtraGUI::fill_in_form(
      INPUTS => \@inputs,
      COLUMNS=>1,
      TITLE=>w('edit_category_dialog_title'),
      CALLBACK=>$callback
    );

}





#------------ End public methods --------------

=head4 menu_bar()

This private method adds the menu bar to the parent window.

=cut

sub menu_bar {
  my $self = shift;
  my $parent = shift;
  local $Words::words_prefix = "b.menus";

  $self->{MENU_ITEM_DIRECTORY} = {};

  # Flush the grades queue whenever the user selects a menu item:
  my $safe = sub {$self->grades_queue()};
  $self->{SAFE} = $safe;

  my $add_item = sub {
    my $menu = shift;
    my $items = shift;
    my $key = shift;
    my $text = shift;
    my $cmd = shift; # sub ref
    my $acc = '';
    my $type = 'command';
    my $variable_ref = undef; # reference to a variable, for $type being 'checkbutton'
    if ($key eq '-') {
      my @stuff = (Separator=>'');
      push @$items,\@stuff;
    }
    else {
      if ($text eq "") {$text = w($key)}
      if (@_) {$acc=shift}
      if (@_) {$type = shift}
      if (@_) {$variable_ref = shift}
      my $whatcha_do = sub {
        my $gb = $self->{DATA}->{GB};
        $gb->{PREVENT_UNDO} = 0 if ref $gb;
        &$safe();
        &$cmd;
      };
      my @stuff = ($type=>$text,-command=>$whatcha_do); #see Mastering Perl/Tk p. 262; command tells what type (command, not radiobutton,...)
      if ($acc) {push @stuff,(-accelerator=>$acc)}
      if (ref $variable_ref) {push @stuff,(-variable=>$variable_ref)}
      push @$items,\@stuff;
      $self->{MENU_ITEM_DIRECTORY}->{$menu."*".$key} = $#$items;
    }
  };

  my $bind_accel = sub {
    $parent->bind('<Control-Key-'.lc(accel($_[0])).'>'=>$_[1]);
    $parent->bind('<Control-Key-'.uc(accel($_[0])).'>'=>$_[1]);
  };

  my $bar = $parent->Frame(-relief=>'raised',-borderwidth=>'2');

  my @items = ();


  &$add_item("FILE_MENUB",\@items,'new',  '',sub{$self->new_file()},  'Ctrl+'.accel('fn'));
  &$add_item("FILE_MENUB",\@items,'open', '',sub{$self->open_file()}, 'Ctrl+'.accel('fo'));
  &$add_item("FILE_MENUB",\@items,'save', '',sub{$self->save_file()}, 'Ctrl+'.accel('fs'));
  &$add_item("FILE_MENUB",\@items,'close','',sub{$self->close_file()},'Ctrl+'.accel('fw'));
  &$add_item("FILE_MENUB",\@items,'quit', '',sub{$self->quit()},      'Ctrl+'.accel('fq'));
  &$add_item("FILE_MENUB",\@items,'-');
  &$add_item("FILE_MENUB",\@items,'about','',sub{$self->about()});
  &$add_item("FILE_MENUB",\@items,'-');
  &$add_item("FILE_MENUB",\@items,'properties','',sub{$self->properties()});
  &$add_item("FILE_MENUB",\@items,'revert','',sub{$self->revert()});
  &$add_item("FILE_MENUB",\@items,'rekey','',sub{$self->rekey_file()});
  &$add_item("FILE_MENUB",\@items,'strip_watermark','',sub{$self->strip_watermark()});
  &$add_item("FILE_MENUB",\@items,'reconcile','',sub{$self->reconcile()});
  &$add_item("FILE_MENUB",\@items,'clone','',sub{$self->clone()});
  &$add_item("FILE_MENUB",\@items,'export','',sub{$self->export()});
  &$add_item("FILE_MENUB",\@items,'-');
  my $prefs = Preferences->new(); # Can't use the one associated with the gradebook, because may not have one open.
  #my $recent_files = $prefs->get('recent_files');
  $self->{RECENT_FILE_LABELS} = [];
  my @prepared_list = $self->prepare_list_of_recent_files_for_menu();
  my $l = $self->{RECENT_FILE_LABELS};
  foreach my $stuff(@prepared_list) {
    my ($foo,$label,$recent_file,$sub) = @$stuff; # $foo is something like "recent_file3" for the third file -- do I ever even use this?
    &$add_item("FILE_MENUB",\@items,$foo,$label,$sub);
    push @$l,$label;
  }
  $self->{LABEL_OF_CLEAR_RECENT} = w('clear_recent');
  &$add_item("FILE_MENUB",\@items,'clear_recent','',
             sub {
               my $prefs = Preferences->new();
               $prefs->set('recent_files','');
               $self->clear_recent_files_from_menu();
               $self->enable_and_disable_menu_items();
             }
  );
  $self->{LABEL_OF_FREEZE_RECENT} = w('freeze_recent');
  my $freeze_recent = $prefs->get('freeze_recent');
  &$add_item("FILE_MENUB",\@items,'freeze_recent','',
             sub {
               my $prefs = Preferences->new();
               $prefs->set('freeze_recent',$freeze_recent);
             },
             '','checkbutton',\$freeze_recent);
  $self->{FILE_MENUB}
   = $bar->Menubutton(-text=>w("file"),-menuitems=>\@items,-tearoff=>0)->pack(-side=>'left');

  &$bind_accel('fn',sub{&$safe; $self->new_file()});
  &$bind_accel('fo',sub{&$safe; $self->open_file()});
  &$bind_accel('fs',sub{&$safe; $self->save_file()});
  &$bind_accel('fw',sub{&$safe; $self->close_file()});
  &$bind_accel('fq',sub{&$safe; $self->quit()});

  @items = ();
  &$add_item("EDIT_MENUB",\@items,'undo','',sub{my $gb = $self->{DATA}->{GB}; $gb->undo() if ref $gb },'Ctrl+'.accel('fz')); # also see bind_accel below
  #...redo
  &$add_item("EDIT_MENUB",\@items,'-');
  &$add_item("EDIT_MENUB",\@items,'standards','',sub{$self->options('standards')});
  &$add_item("EDIT_MENUB",\@items,'marking_periods','',sub{$self->options('marking_periods')});
  $self->{EDIT_MENUB}
   = $bar->Menubutton(-text=>w("edit_menu"),-menuitems=>\@items,-tearoff=>0)->pack(-side=>'left');
  &$bind_accel('fz',sub{$self->grades_queue(); my $gb = $self->{DATA}->{GB}; $gb->undo() if ref $gb });

  @items = ();
  &$add_item("PREFERENCES_MENUB",\@items,'beep','',sub{$self->options('beep')});
  &$add_item("PREFERENCES_MENUB",\@items,'justify','',sub{$self->options('justify')});
  if (Portable::os_has_unix_shell()) {
    &$add_item("PREFERENCES_MENUB",\@items,'editor_command','',sub{$self->options('editor_command')});
    &$add_item("PREFERENCES_MENUB",\@items,'print_command','',sub{$self->options('print_command')});
    &$add_item("PREFERENCES_MENUB",\@items,'spreadsheet_command','',sub{$self->options('spreadsheet_command')});
  }
  &$add_item("PREFERENCES_MENUB",\@items,'hash_function','',sub{$self->options('hash_function')});
  my $prefs = Preferences->new();
  my $restart_to_change_menus = w('restart_to_change_menus');
  if (eval{OnlineGrades::available()}) {
    my $p = $prefs->get('activate_online_grades_plugin');
    my $activate_online_grades = ($p || !defined $p || $p eq '');
    &$add_item("FILE_MENUB",\@items,'activate_online_grades_plugin','',
             sub {
               my $prefs = Preferences->new();
               $prefs->set('activate_online_grades_plugin',$activate_online_grades);
               ExtraGUI::message($restart_to_change_menus);
             },
             '','checkbutton',\$activate_online_grades);
  }
  if (eval{ServerDialogs::available()}) {
    my $p = $prefs->get('activate_spotter_plugin');
    my $activate_spotter = ($p || !defined $p || $p eq '');
    &$add_item("FILE_MENUB",\@items,'activate_spotter_plugin','',
             sub {
               my $prefs = Preferences->new();
               $prefs->set('activate_spotter_plugin',$activate_spotter);
               ExtraGUI::message($restart_to_change_menus);
             },
             '','checkbutton',\$activate_spotter);
  }
  $self->{PREFERENCES_MENUB}
   = $bar->Menubutton(-text=>w("preferences"),-menuitems=>\@items,-tearoff=>0)->pack(-side=>'left');


  @items = ();
  &$add_item("STUDENTS_MENUB",\@items,'add','',sub{$self->add_or_drop('add')});
  &$add_item("STUDENTS_MENUB",\@items,'reinstate','',sub{$self->add_or_drop('reinstate')});
  &$add_item("STUDENTS_MENUB",\@items,'edit',w('edit_disabled'),sub{$self->edit_student()});
  &$add_item("STUDENTS_MENUB",\@items,'drop',(sprintf w('drop'),''),sub{$self->add_or_drop('drop')});
  $self->{STUDENTS_MENUB}
   = $bar->Menubutton(-text=>w("students"),-menuitems=>\@items,-tearoff=>0)->pack(-side=>'left');

  @items = ();
  &$add_item("ASSIGNMENTS_MENUB",\@items,'new_category','',sub{$self->new_category()});
  &$add_item("ASSIGNMENTS_MENUB",\@items,
             'edit_category',w('edit_category_blank'),sub{$self->edit_category()});
  &$add_item("ASSIGNMENTS_MENUB",\@items,'category_weights','',sub{$self->edit_category_weights()});
  &$add_item("ASSIGNMENTS_MENUB",\@items,'delete_category',w('delete_category_blank'),sub{$self->delete_category()});
  &$add_item("ASSIGNMENTS_MENUB",\@items,'-');
  &$add_item("ASSIGNMENTS_MENUB",\@items,
             'new_assignment',w('new_assignment_blank'),sub{$self->new_assignment()});
  &$add_item("ASSIGNMENTS_MENUB",\@items,
             'edit_assignment',w('edit_assignment_blank'),sub{$self->edit_assignment()});
  &$add_item("ASSIGNMENTS_MENUB",\@items,
             'delete_assignment',w('delete_assignment_blank'),sub{$self->delete_assignment()});
  $self->{ASSIGNMENTS_MENUB}
   = $bar->Menubutton(-text=>w("assignments"),-menuitems=>\@items,-tearoff=>0)->pack(-side=>'left');

  @items = ();
  &$add_item("REPORT_MENUB",\@items,'statistics','',sub{$self->report('stats')});
  &$add_item("REPORT_MENUB",\@items,'statistics_ass',w('statistics_ass_blank'),sub{$self->report('stats_ass')});
  &$add_item("REPORT_MENUB",\@items,'student','',sub{$self->report('student')});
  &$add_item("REPORT_MENUB",\@items,'sort_by_overall','',sub{$self->report('sort_by_overall')});
  &$add_item("REPORT_MENUB",\@items,'sort_by_category',w('sort_by_category_blank'),sub{$self->report('sort_by_category')});
  &$add_item("REPORT_MENUB",\@items,'sort_by_assignment',w('sort_by_assignment_blank'),sub{$self->report('sort_by_assignment')});
  &$add_item("REPORT_MENUB",\@items,'table',w('table'),sub{$self->report('table')});
  &$add_item("REPORT_MENUB",\@items,'roster',w('roster'),sub{$self->report('roster')});
  &$add_item("REPORT_MENUB",\@items,'spreadsheet',w('spreadsheet'),sub{$self->report('spreadsheet')});
  $self->{REPORT_MENUB}
   = $bar->Menubutton(-text=>w("report"),-menuitems=>\@items,-tearoff=>0)->pack(-side=>'left');

  eval {
    my $p = $prefs->get('activate_spotter_plugin');
    if ($p || !defined $p || $p eq '') {
      $self->{SERVER_MENUB}
        = $bar->Menubutton(-text=>w("server"),-menuitems=>ServerDialogs::create_server_menu($self,$add_item),-tearoff=>0)->pack(-side=>'left');
    }
  };
  eval {
    my $p = $prefs->get('activate_online_grades_plugin');
    if ($p || !defined $p || $p eq '') {
      $self->{ONLINE_GRADES_MENUB}
        = $bar->Menubutton(-text=>w("online_grades"),-menuitems=>OnlineGrades::create_server_menu($self,$add_item),-tearoff=>0)->pack(-side=>'left');
    }
  };

  $self->enable_and_disable_menu_items();
  return $bar;
}

sub clear_recent_files_from_menu {
  my $self = shift;
  my $menu = $self->{FILE_MENUB}->menu();
  my $l = $self->{RECENT_FILE_LABELS};
  foreach my $label(@$l) {
    $menu->delete($label);
  }
  @$l = ();
}

sub about {
  local $Words::words_prefix = "b.about";
  my $text = w('about_og');
  my $version = Version::version();
  my $tk_version = $Tk::VERSION;
  my $perl_version = sprintf "%vd",$^V;
  my $gtk_version = Version::gtk_version();
  $gtk_version = '?' if !$gtk_version;
  $text = sprintf $text,$version,$tk_version,$perl_version,$gtk_version;
  ExtraGUI::show_text(TITLE=>w('about_og_title'),TEXT=>$text,WIDTH=>100);
}

# Set the accelerator buttons for the menus:
sub accel {
  my $what = shift; # fs for file menu/save, etc.
  return {
    'fs'=>'S',    'fo'=>'O',    'fn'=>'N',    'fw'=>'W',    'fq'=>'Q',   'fz'=>'Z',
  }
  ->{$what};
}

=head4 enable_and_disable_menu_items()

Looks at whether a file is open, whether a student is selected, etc., and enables and
disables the menu items appropriately. This doesn't have any effect on things like
control-O for open, but that's ok, because, e.g., open_file() automatically closes
the file anyway before opening a new one.

=cut

sub enable_and_disable_menu_items {
  my $self = shift;
  my $data = $self->{DATA};
  local $Words::words_prefix = "b.menus";
  my $dir = $self->{MENU_ITEM_DIRECTORY};


  my $assignments_menub = $self->{ASSIGNMENTS_MENUB};
  my $cat = "";
  my $ass = "";
  if ($data->file_is_open() && exists $self->{STAGE} && exists $self->{STAGE}->{ASSIGNMENTS}) {
    $cat=$self->{STAGE}->{ASSIGNMENTS}->get_active_category();
    $ass=$self->{STAGE}->{ASSIGNMENTS}->selected();
    $ass =~ s/\.(.*)//;
    $ass = $1;
  };

  my $gb = $data->{GB};

  # File menu.
  my $file_menub = $self->{FILE_MENUB};
  if ($data->file_is_open()) {
    $file_menub->entryconfigure($dir->{'FILE_MENUB*new'},-state=>'disabled');
    $file_menub->entryconfigure($dir->{'FILE_MENUB*open'},-state=>'disabled');
    $file_menub->entryconfigure($dir->{'FILE_MENUB*close'},-state=>'normal');
    $file_menub->entryconfigure($dir->{'FILE_MENUB*save'},-state=>'normal');
    $file_menub->entryconfigure($dir->{'FILE_MENUB*rekey'},-state=>'disabled');
    $file_menub->entryconfigure($dir->{'FILE_MENUB*strip_watermark'},-state=>'disabled');
    $file_menub->entryconfigure($dir->{'FILE_MENUB*reconcile'},-state=>'disabled');
    $file_menub->entryconfigure($dir->{'FILE_MENUB*clone'},-state=>'normal');
    $file_menub->entryconfigure($dir->{'FILE_MENUB*export'},-state=>'normal');
    $file_menub->entryconfigure($dir->{'FILE_MENUB*properties'},-state=>'normal');
    $file_menub->entryconfigure($dir->{'EDIT_MENUB*standards'},-state=>'normal');
  }
  else { # no file open
    $file_menub->entryconfigure($dir->{'FILE_MENUB*new'},-state=>'normal');
    $file_menub->entryconfigure($dir->{'FILE_MENUB*open'},-state=>'normal');
    $file_menub->entryconfigure($dir->{'FILE_MENUB*close'},-state=>'disabled');
    $file_menub->entryconfigure($dir->{'FILE_MENUB*save'},-state=>'disabled');
    $file_menub->entryconfigure($dir->{'FILE_MENUB*rekey'},-state=>'normal');
    $file_menub->entryconfigure($dir->{'FILE_MENUB*strip_watermark'},-state=>'normal');
    $file_menub->entryconfigure($dir->{'FILE_MENUB*reconcile'},-state=>'normal');
    $file_menub->entryconfigure($dir->{'FILE_MENUB*clone'},-state=>'disabled');
    $file_menub->entryconfigure($dir->{'FILE_MENUB*export'},-state=>'disabled');
    $file_menub->entryconfigure($dir->{'FILE_MENUB*properties'},-state=>'disabled');
    $file_menub->entryconfigure($dir->{'EDIT_MENUB*standards'},-state=>'disabled');
  }
  $self->enable_or_disable_specific_menu_item('FILE','clear_recent');
  my $can_revert = 0;
  my $r;
  if (ref $gb) {
    $r = $gb->{UNDO_STACK};
    if (@$r >= 2) {$can_revert = 1} # if it only has 1 item, it's still in its original state
  }
  if ($can_revert) {
    $file_menub->entryconfigure($dir->{'FILE_MENUB*revert'},-state=>'normal');
  }
  else {
    $file_menub->entryconfigure($dir->{'FILE_MENUB*revert'},-state=>'disabled');
  }

  # Edit menu.
  my $edit_menub = $self->{EDIT_MENUB};
  my $can_undo = 0;
  my $r;
  if (ref $gb) {
    $r = $gb->{UNDO_STACK};
    if (@$r >= 2) {$can_undo = 1} # We always put the initial state in the stack. Having a second item means it got changed.
  }
  if ($can_undo) {
    $edit_menub->entryconfigure($dir->{'EDIT_MENUB*undo'},-state=>'normal',
         -label=>(sprintf w('undo_operation'),$gb->{UNDO_STACK}->[-1]->{'describe'}));
  }
  else {
    $edit_menub->entryconfigure($dir->{'EDIT_MENUB*undo'},-state=>'disabled',-label=>w('undo'));
  }

  # Students menu:
  my $students_menub = $self->{STUDENTS_MENUB};
  my $student = "";
  if ($data->file_is_open() && exists $self->{STAGE} && exists $self->{STAGE}->{ROSTER}) {
    $student=$self->{STAGE}->{ROSTER}->selected();
  };
  if ($student ne "" && $data->file_is_open()) {
    $students_menub->entryconfigure($dir->{'STUDENTS_MENUB*drop'},
                       -state=>'normal',
                       -label=>(sprintf w('drop'),$data->key_to_name(KEY=>$student,ORDER=>'firstlast')));
    $students_menub->entryconfigure($dir->{'STUDENTS_MENUB*edit'},
                       -state=>'normal',
                       -label=>(sprintf w('edit'),$data->key_to_name(KEY=>$student,ORDER=>'firstlast')));
  }  
  else { # no student selected
    $students_menub->entryconfigure($dir->{'STUDENTS_MENUB*drop'},-state=>'disabled');
    $students_menub->entryconfigure($dir->{'STUDENTS_MENUB*edit'},-state=>'disabled',-label=>w('edit_disabled'));
  }  
  if ($data->file_is_open()) {
    $students_menub->entryconfigure($dir->{'STUDENTS_MENUB*add'},-state=>'normal');
    $students_menub->entryconfigure($dir->{'STUDENTS_MENUB*reinstate'},-state=>'normal');
  }
  else {
    $students_menub->entryconfigure($dir->{'STUDENTS_MENUB*add'},-state=>'disabled');
    $students_menub->entryconfigure($dir->{'STUDENTS_MENUB*reinstate'},-state=>'disabled');
  }

  # Assignments menu:
  my $cat_selected = $cat ne "" && $data->file_is_open(); # 2nd clause is for when we're in the process of quitting
  my $ass_selected = $cat_selected && $ass ne "";
  if ($cat_selected) {
    $assignments_menub->entryconfigure($dir->{'ASSIGNMENTS_MENUB*new_assignment'},
                       -state=>'normal',
                       -label=>(sprintf w('new_assignment'),
                                ucfirst($data->{GB}->category_name_singular($cat))));
    $assignments_menub->entryconfigure($dir->{'ASSIGNMENTS_MENUB*edit_category'},
                       -state=>'normal',
                       -label=>(sprintf w('edit_category'),
                                ucfirst($data->{GB}->category_name_plural($cat))));
    $assignments_menub->entryconfigure($dir->{'ASSIGNMENTS_MENUB*delete_category'},
                       -state=>'normal',
                       -label=>(sprintf w('delete_category'),
                                ucfirst($data->{GB}->category_name_plural($cat))));
  }
  else { # no category selected
    $assignments_menub->entryconfigure($dir->{'ASSIGNMENTS_MENUB*new_assignment'},-state=>'disabled');
    $assignments_menub->entryconfigure($dir->{'ASSIGNMENTS_MENUB*edit_category'},
                       -state=>'disabled',-label=>w('edit_category_blank'));
    $assignments_menub->entryconfigure($dir->{'ASSIGNMENTS_MENUB*delete_category'},
                       -state=>'disabled',-label=>w('delete_category_blank'));
  }
  if ($ass_selected) {
    $assignments_menub->entryconfigure($dir->{'ASSIGNMENTS_MENUB*edit_assignment'},
                       -state=>'normal',
                       -label=>(sprintf w('edit_assignment'),
                                ucfirst($data->{GB}->assignment_name($cat,$ass))));
    $assignments_menub->entryconfigure($dir->{'ASSIGNMENTS_MENUB*delete_assignment'},
                       -state=>'normal',
                       -label=>(sprintf w('delete_assignment'),
                                ucfirst($data->{GB}->assignment_name($cat,$ass))));
  }
  else { # no assignment selected
    $assignments_menub->entryconfigure($dir->{'ASSIGNMENTS_MENUB*edit_assignment'},-state=>'disabled',-label=>w('edit_assignment_blank'));
    $assignments_menub->entryconfigure($dir->{'ASSIGNMENTS_MENUB*delete_assignment'},-state=>'disabled',-label=>w('delete_assignment_blank'));
  }
  if ($data->file_is_open() && $data->{GB}->weights_enabled() && $data->{GB}->has_categories()) {
    $assignments_menub->entryconfigure($dir->{'ASSIGNMENTS_MENUB*category_weights'},-state=>'normal')
  }
  else {
    $assignments_menub->entryconfigure($dir->{'ASSIGNMENTS_MENUB*category_weights'},-state=>'disabled')
  }
  if ($data->file_is_open()) {
    $assignments_menub->entryconfigure($dir->{'ASSIGNMENTS_MENUB*new_category'},-state=>'normal')
  }
  else {
    $assignments_menub->entryconfigure($dir->{'ASSIGNMENTS_MENUB*new_category'},-state=>'disabled')
  }

  # Reports menu.
  my $report_menub = $self->{REPORT_MENUB};
  if ($cat ne "" && $data->file_is_open()) { # 2nd clause is for when we're in the process of quitting
    $report_menub->entryconfigure($dir->{'REPORT_MENUB*sort_by_category'},
                       -state=>'normal',
                       -label=>(sprintf w('sort_by_category'),
                                ucfirst($data->{GB}->category_name_plural($cat))));
  }  
  else { # no category selected
    $report_menub->entryconfigure($dir->{'REPORT_MENUB*sort_by_category'},
                                            -label=>w('sort_by_category_blank'),
                                             -state=>'disabled');
  }  
  if ($cat ne "" && $ass ne "" && $data->file_is_open()) { # 2nd clause is for when we're in the process of quitting
    $report_menub->entryconfigure($dir->{'REPORT_MENUB*sort_by_assignment'},
                       -state=>'normal',
                       -label=>(sprintf w('sort_by_assignment'),
                                ucfirst($data->{GB}->assignment_name($cat,$ass))));
    $report_menub->entryconfigure($dir->{'REPORT_MENUB*statistics_ass'},
                       -state=>'normal',
                       -label=>(sprintf w('statistics_ass'),
                                ucfirst($data->{GB}->assignment_name($cat,$ass))));
  }  
  else { # no assignment selected
    $report_menub->entryconfigure($dir->{'REPORT_MENUB*sort_by_assignment'},
                     -label=>w('sort_by_assignment_blank'),
                     -state=>'disabled');
    $report_menub->entryconfigure($dir->{'REPORT_MENUB*statistics_ass'},
                     -label=>w('statistics_ass_blank'),
                     -state=>'disabled');
  }  
  if ($data->file_is_open()) {
    $assignments_menub->entryconfigure($dir->{'ASSIGNMENTS_MENUB*new_category'},-state=>'normal')
  }
  else {
    $assignments_menub->entryconfigure($dir->{'ASSIGNMENTS_MENUB*new_category'},-state=>'disabled')
  }

  if ($student ne "") {
    $report_menub->entryconfigure($dir->{'REPORT_MENUB*student'},-state=>'normal');
  }  
  else { # no student selected
    $report_menub->entryconfigure($dir->{'REPORT_MENUB*student'},-state=>'disabled');
  }  
  if ($data->file_is_open()) {
    $report_menub->entryconfigure($dir->{'REPORT_MENUB*statistics'},-state=>'normal');
    $report_menub->entryconfigure($dir->{'REPORT_MENUB*sort_by_overall'},-state=>'normal');
    $report_menub->entryconfigure($dir->{'REPORT_MENUB*table'},-state=>'normal');
    $report_menub->entryconfigure($dir->{'REPORT_MENUB*roster'},-state=>'normal');
  }
  else {
    $report_menub->entryconfigure($dir->{'REPORT_MENUB*statistics'},-state=>'disabled');
    $report_menub->entryconfigure($dir->{'REPORT_MENUB*sort_by_overall'},-state=>'disabled');
    $report_menub->entryconfigure($dir->{'REPORT_MENUB*table'},-state=>'disabled');
    $report_menub->entryconfigure($dir->{'REPORT_MENUB*roster'},-state=>'disabled');
  }

  eval { ServerDialogs::enable_and_disable_menu_items($self,$data,$dir,$student) };
  eval { OnlineGrades::enable_and_disable_menu_items($self,$data,$dir,$student) };
}

=head4 enable_or_disable_specific_menu_item()

Call with name of menu (e.g., FILE) and item (e.g. clear_recent). This is not implemented for every
combination of inputs. The idea is that sometimes we just want to tweak one item, and for efficiency,
we don't want to call enable_and_disable_menu_items(), which does every single menu. In cases like that,
enable_and_disable_menu_items() is coded so that it actually calls this routine.

=cut

sub enable_or_disable_specific_menu_item {
  my $self = shift;
  my $menu = shift;
  my $item = shift;
  my $dir = $self->{MENU_ITEM_DIRECTORY};
  if ($menu eq 'FILE') {
    my $file_menub = $self->{FILE_MENUB};
    if ($item eq 'clear_recent') {
      my $index = $self->{FILE_MENUB}->menu()->index($self->{LABEL_OF_CLEAR_RECENT});
      if (split(',',Preferences->new()->get('recent_files'))) { # We have a list of recent files.
        $file_menub->entryconfigure($index,-state=>'normal');
      }
      else {
        $file_menub->entryconfigure($index,-state=>'disabled');
      }
    }
  }
}



1;
