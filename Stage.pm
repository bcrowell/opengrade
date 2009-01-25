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
use Assignments;
use Roster;
use Score;

BEGIN {
  eval "use ServerDialogs";
  eval "use OnlineGrades";
}

#---------------------------------------------------
# Stage class
#---------------------------------------------------

=head3 Stage class

This is the ``center-stage'' area of the window, where the user
selects students and edits their grades on assignments.
The object's basic job is just to pass messages
among its parts.
Its children, Roster, Grades, and Assignments,
let it know when they change the state of the GUI. For instance,
when the Roster object sees that the user has selected a
certain student, it calls Stage::roster_has_set_student(),
which then gives the relevant information to Grades.
We avoid endless loops, because Stage knows that when it
gets a call to this method, the call came from Roster, and
therefore it doesn't need to call Roster to let it know about
the change.

=cut

package Stage;

sub new {
  my $class = shift;
  my $browser_window = shift;
  my $parent = shift;
  my $data = shift;
  my $self = {};
  bless($self,$class);
  $self->{BROWSER_WINDOW} = $browser_window;
  $self->{PARENT} = $parent;
  $self->{DATA} = $data;
  $self->{FRAME} = $parent->Frame();
  $browser_window->{ASSIGNMENTS} = Assignments->new($self,$self->{FRAME},$data);
  $browser_window->{ROSTER} = Roster->new($self,$self->{FRAME},$data);
  $self->{ROSTER} = $browser_window->{ROSTER};
  $self->{ASSIGNMENTS} = $browser_window->{ASSIGNMENTS};
  $self->{ASSIGNMENT} = "";
  $self->{STUDENT} = "";
  return $self;
}


sub roster_has_set_student {
  my $self = shift;
  my $k = shift; # key of student
  if (!$self->{DATA}->file_is_open()) {return}
  $self->{BROWSER_WINDOW}->grades_queue(); # flush
  $self->{STUDENT} = $k;
  $self->{BROWSER_WINDOW}->enable_and_disable_menu_items();
}

=head4 assignments_has_set_assignment()

Enables and disables menu items, then calls set_assignment().
Optional second arg may be {'no_enable_and_disable_menu_items'=>1}, for efficiency.

=cut

sub assignments_has_set_assignment {
  my $self = shift;
  my $k = shift; # key of assignment
  my $options = shift;
  if (!$self->{DATA}->file_is_open()) {return}
  $self->{BROWSER_WINDOW}->grades_queue(); # flush
  $self->{BROWSER_WINDOW}->enable_and_disable_menu_items() unless exists $options->{'no_enable_and_disable_menu_items'};
  $self->{ROSTER}->set_assignment($k);
  $self->{ASSIGNMENT} = $k;
}

=head4 grades_has_set_grade()

Simply passes the message to the BrowserData object via its
set_a_grade() method.

=cut

sub grades_has_set_grade {
  my $self = shift;
  my $s_key = shift;
  my $c_key = shift;
  my $a_key = shift;
  my $grade = shift;
  #print "setting $a_key,$s_key,$grade in grades_has_set_grade\n";
  $self->{DATA}->set_a_grade($c_key.".".$a_key,$s_key,$grade);
}



1;
