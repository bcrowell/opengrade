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
use Stage;
use Assignments;
use Roster;

BEGIN {
  eval "use ServerDialogs";
  eval "use OnlineGrades";
}

#---------------------------------------------------
# Score class
#---------------------------------------------------

=head3 Score class

This represents an Entry for a score, or a piece of
text describing the student's overall score in a certain
category, or in the whole course.

=cut

package Score;

sub new {
  my $class = shift;
  my $frame = shift;       # the frame it goes into; it's the sole occupant
  my $who = shift;         # student key
  my $what = shift;        # ='1-overall', '2-category', or '3-assignment'; numbers are so comparisons work
  my $textvar_ref = shift; # the text variable tied to the Entry
  my $roster = shift;
  my $j = shift;           # index into the roster
  my $n = shift;           # number of students in the roster
  my $self = {};
  return undef if !defined $frame;
  bless($self,$class);
  $self->{FRAME} = $frame;
  $self->{WHO} = $who;
  $self->{WHAT} = $what;
  $self->{ROSTER} = $roster;
  my $relief = 'flat';
  if ($what eq '3-assignment') {$relief='sunken'}
  my $gb = $roster->{DATA}->{GB};
  my $prefs = $gb->preferences();
  if (!defined $prefs) {$prefs = Preferences->new()}
  my $default_justification = 'right';
  my $justify = {0=>'left',1=>'right',''=>$default_justification,'left'=>'left','right'=>'right'}->{$prefs->get('justify')};
  $self->{WIDGET} = $frame->Entry(
        -width=>9,
        -takefocus=>0,
#        -state=>'disabled',
            # ...Removed this 2004 jan 25 because in the latest version of Perl/Tk, it was causing the scores to dim out and become hard
            # to read. Not sure why I did this in the first place. Similar change at one other place in the code, marked with same date.
        -textvariable=>$textvar_ref,
#        -font=>ExtraGUI::font('fixed_width'), # on older versions of Perl/Tk, hurt performance a lot for some reason; looks bad anyway
        -relief=>$relief,
        -justify=>$justify,
      )->pack();
  my $w = $self->{WIDGET};
  $w->bind('<ButtonRelease-1>',sub{       # $who and $name are closure-ized in this subroutine
           $roster->clicked_on_student($who);
           $roster->{KBSEL}='';
           $roster->{SELECTED_STUDENT} = $who;
           $self->focus();
           $roster->{COLUMN_FOCUS} = 1;
         }
        );
  $w->bind('<Key>',sub{Roster::key_pressed_in_scores($roster,$who,$j,$n)});
  $w->bind('<Control-Key>',sub{}); # This overrides the <Key> binding in the special case of Control-Key, so we don't call key_pressed_in_scores on that key.
  $w->bind('<FocusIn>',
    sub{
      $roster->{COLUMN_FOCUS}=1;
      $w->selectionClear(); # This is extremely important, because otherwise you hit tab to go to a preexisting score, it selects the whole score, and then if you
                            # hit space, it clears the score!
      $w->icursor('end');
    }
  );
  $w->bind('<FocusOut>',sub{$self->tidy_when_leaving()});

  return $self;
}

sub widget {
  my $self = shift;
  return $self->{WIDGET};
}

sub frame {
  my $self = shift;
  return $self->{FRAME};
}

sub tidy_when_leaving {
  my $self = shift;
  $self->{WIDGET}->selectionClear();
}

sub focus {
  my $self = shift;
  $self->{WIDGET}->focus();
}

sub highlighted {
  my $self = shift;
  my $want_highlighted = shift;
  if ($want_highlighted) {
    $self->{WIDGET}->configure(-font=>ExtraGUI::font('bold'));
  }
  else {
    $self->{WIDGET}->configure(-font=>ExtraGUI::font('plain'));
  }
}

=head4 is_editable()

Tells whether this is a specific assignment that we can edit the score on.
Doesn't know or care whether it's actually enabled (e.g., whether it actually
has the focus).

=cut

sub is_editable {
  my $self = shift;
  return $self->{WHAT} eq '3-assignment';
}

=head4 enabled()

Set whether it's enabled for editing and can take the focus.
Ignored if not editable.

=cut

sub enabled {
  my $self = shift;
  my $want_enabled = shift;
  if ($want_enabled && $self->is_editable()) {
    $self->{WIDGET}->configure(-takefocus=>1,-state=>'normal');
  }
  else {
    #$self->{WIDGET}->configure(-takefocus=>0,-state=>'disabled');
        # ... Commented out 2004 jan 25. See comment above with same date.
  }
}

sub destroy_widget {
  my $self = shift;
  $self->{WIDGET}->destroy();
}


1;
