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
use Roster;
use Score;

BEGIN {
  eval "use ServerDialogs";
  eval "use OnlineGrades";
}

#---------------------------------------------------
# Assignments class
#---------------------------------------------------

=head3 Assignments class

This class encapsulates all the data about the assignments
displayed on the screen.

=cut

package Assignments;

sub new {
  my $class = shift;
  my $stage = shift;
  my $parent = shift;
  my $data = shift;
  my $self = {};
  bless($self,$class);
  $self->{STAGE} = $stage;
  $self->{PARENT} = $parent;
  $self->{DATA} = $data;
  $self->{FRAME} = $parent->Frame()->pack(-side=>'left',-expand=>1,-padx=>10);
  $self->{CATEGORIES_TEXTVARIABLE} = '';
  $self->{CATEGORIES_MENU} = $self->{FRAME}->Optionmenu(
         -takefocus=>0,
         -font=>ExtraGUI::font('plain'),
         -textvariable=>\($self->{CATEGORIES_TEXTVARIABLE}),
  )->pack(-side=>'top',-expand=>1);
  $self->{ASSIGNMENTS_LISTBOX} = $self->{FRAME}->Scrolled(
         "Listbox",
         -scrollbars=>"e",
         -takefocus=>0,
         -font=>ExtraGUI::font('plain'),
         -height=>25
  )->pack(-side=>'top',-expand=>1);
  $self->{ASSIGNMENTS_LISTBOX}->Subwidget('yscrollbar')->configure(-takefocus=>0);
  $self->{KEYS} = [];                # ref to an array, which is stored in the order shown on the screen
  $self->{NAMES} = [];                # in the same order as KEYS, but shows the assmts in human-readable form
  $self->{CAT_INTENTIONALLY_SELECTED} = ''; # as opposed to {SELECTED}, which may be set to a default because the user hasn't selected a category yet
  $self->{LEAVE_CAT_SELECTION_ALONE} = 0; # if set to 1, prevents selection of wrong cat when menu is rebuilt
  $self->{INFINITE_LOOP_PROTECTION} = 0; # see clicked_on_category()
  return $self;
}

sub refresh {
  my $self = shift;
  $self->clear();
  my $data = $self->{DATA};
  # If a file is open, fill it back up:
  if ($data->file_is_open()) {
    $self->refresh_categories();
    $self->refresh_assignments();
  }
}

=head4 refresh_categories()

Rebuild the popup menu of categories from scratch. If nothing is selected, we
select the first category. Sets up a callback from the menu to decode_cats_option_menu().

=cut

sub refresh_categories {
    my $self = shift;
    my $data = $self->{DATA};
    my $gb = $data->{GB};
    my $menu = $self->{CATEGORIES_MENU}; # a Tk::Optionmenu object
    my @c = ();
    my @names = ();
    if ($gb) {
      my $aa = $gb->category_array();
      @c = @$aa;
      $self->{CAT_KEYS} = \@c;
      foreach my $cat(@c) {
        push @names,$gb->category_name_plural($cat);
      }
      my $save_intent = $self->{CAT_INTENTIONALLY_SELECTED};
      $self->{LEAVE_CAT_SELECTION_ALONE} = ($save_intent ne '');
      $menu->configure(-options=>\@names,-command=>sub{decode_cats_option_menu($self,\@_,\@names,\@c)});
         # The arrays @names and @c are closure-ized at this point.
         # This step is somewhat inefficient, takes about .14 seconds.
      $self->{CAT_INTENTIONALLY_SELECTED} = $save_intent;
      $self->{LEAVE_CAT_SELECTION_ALONE} = 0;
      if (@c) {
        my $active = $self->get_active_category();
        if ($active ne '') {
          $self->clicked_on_category($active);
        }
        else {
          my $cat = $self->{CAT_INTENTIONALLY_SELECTED};
          if ($cat eq '') {
            # An Optionmenu always has something selected, so we have to say the first item is selected:
            $cat = $c[0];
          }
          $self->clicked_on_category($cat);
        }
        $menu->configure(-state=>'normal');
      }
    }
    else {
      $menu->configure(-state=>'disabled'); # doesn't seem to work
      $menu->configure(-options=>[]); # doesn't seem to work
    }
}

=head4 decode_cats_option_menu()

This is the callback that gets called when the user selects a category from the categories
menu. Since all we get back from Tk is the actual text of the menu item, it takes some work
to figure out the corresponding database key. Calls clicked_on_category() with the result.

=cut

sub decode_cats_option_menu {
  my $self = shift;
  my ($args_ref,$names_ref,$keys_ref) = @_;
  my @args = @$args_ref;
  my @names = @$names_ref;
  my @keys = @$keys_ref;
  my $name = pop @args;
  if (!($self->{LEAVE_CAT_SELECTION_ALONE})) {
    for (my $j=0; $j<=$#names; $j++) {
      if ($names[$j] eq $name) {
        $self->clicked_on_category($keys[$j]);
      }
    }
  }
  else {
    my $cat = $self->{CAT_INTENTIONALLY_SELECTED};
    $self->clicked_on_category($cat);
  }
}


=head4 refresh_assignments()

This is the same as the name of another routine in another package.
Optional argument is {'no_enable_and_disable_menu_items'=>1}, for efficiency.

=cut 

sub refresh_assignments {
  my $self = shift;
  my $options = shift;
  my $data = $self->{DATA};
  my $gb = $data->{GB};
  my $ass_lb = $self->{ASSIGNMENTS_LISTBOX};
  my @names = ();
  my $active_cat = $self->get_active_category();
  #print "in refresh_assignments, =$active_cat=\n";
  $self->clear_assignments($options);
  if (ref $gb && $active_cat ne "") {
      my $aa = $gb->array_of_assignments_in_category($active_cat);
      my @assignments_in_cat = @$aa;
      my %name_to_key = ();
      $self->{ASS_KEYS} = \@assignments_in_cat;
      my $k = 0;
      foreach my $ass(@assignments_in_cat) {
        my $name = $gb->assignment_name($active_cat,$ass);
        push @names,$name;
        $name_to_key{$name} = $k++;
      }
      $ass_lb->insert('end',@names);
      $ass_lb->bind(
          '<Button-1>',
          # sub{$self->clicked_on_assignment($self->{ASS_KEYS}->[$ass_lb->curselection()])}
          # ... used to work, but no longer does
          sub{$self->clicked_on_assignment($self->{ASS_KEYS}->[$name_to_key{$ass_lb->get($ass_lb->curselection())}])}
      );
  }
}


=head4 clear()

This gets called by refresh(). Don't call it directly and expect the GUI
to get redrawn.

=cut

sub clear {
  my $self = shift;
  $self->{KEYS} = [];
  $self->{NAMES} = [];

  # Clear categories.
  $self->{CAT_KEYS} = [];
  $self->{NAMES} = [];
  $self->selected("");
  $self->{CATEGORIES_MENU}->configure(-options=>[''],-state=>'disabled');

  # Clear assignments.
  my $ass_lb = $self->{ASSIGNMENTS_LISTBOX};
  $ass_lb->delete(0,'end'); # Delete all of them.
}


sub clear_assignments {
  my $self = shift;
  my $options = shift;
  $self->{ASS_KEYS} = [];
  $self->{NAMES} = [];
  $self->selected($self->get_active_category(),$options);
  my $ass_lb = $self->{ASSIGNMENTS_LISTBOX};
  $ass_lb->delete(0,'end'); # Delete all of them.
}



=head4 get_active_category()

Get the key of the category that is currently selected. Calls
selected() and returns the category portion of the key.

=cut

sub get_active_category {
  my $self = shift;
  my $key = $self->selected();
  #print "in get_active_category, =$key=\n";
  if ($key eq "") {return ""}
  if ($key =~ m/^[^\.]+$/) {return $key}
  return GradeBook::first_part_of_label($key);
}

=head4 selected()

Get or set the key of the category or assignment that is currently selected.
Optional second arg may be {'no_enable_and_disable_menu_items'=>1}, for efficiency.

=cut

sub selected {
  my $self = shift;
  if (@_) {
    my $what = shift;
    $self->{SELECTED}=$what;
    if ($what eq '') {
      $what = $self->{CAT_INTENTIONALLY_SELECTED};
    }
    $self->{STAGE}->assignments_has_set_assignment($self->{SELECTED},@_);
  }
  return $self->{SELECTED};
}

=head4 specific_assignment_selected()

Has a specific assignment been selected?

=cut

sub specific_assignment_selected {
  my $self = shift;
  my $key = $self->selected();
  if ($key eq "") {return ""}
  return GradeBook::second_part_of_label($key);
}

=head4 clicked_on_assignment()

Takes one argument, which is the assignment part of the key. Calls selected().

=cut

sub clicked_on_assignment {
  my $self = shift;
  my $key = shift;
  #print "clicked_on_assignment, =$key=\n";
  $self->selected($self->get_active_category().".".$key);
}

=head4 clicked_on_category()

Call selected() and refresh_assignments().

=cut 

sub clicked_on_category {
  my $self = shift;
  my $key = shift;
  $self->selected($key,{'no_enable_and_disable_menu_items'=>1}); # enable_and_disable_menu_items is called explicitly below, and it's slow, so don't call it repeatedly
  $self->refresh_assignments({'no_enable_and_disable_menu_items'=>1}); # calls clear_assignments, which calls selected
  $self->{STAGE}->{BROWSER_WINDOW}->enable_and_disable_menu_items();
  $self->{CAT_INTENTIONALLY_SELECTED} = $key;

  my $cats_menu = $self->{CATEGORIES_MENU};
  my $gb = $self->{DATA}->{GB};
  my $cat_plural = $gb->category_name_plural($key);
  if ($self->{CATEGORIES_TEXTVARIABLE} ne $cat_plural) {
    # We get into this state when rebuilding the categories menu. Tk selects the first category by default, but that's no what we want.
    if (!($self->{INFINITE_LOOP_PROTECTION})) {
      $self->{INFINITE_LOOP_PROTECTION} = 1; # Avoid infinite recursion
      $cats_menu->setOption($key); # This could cause infinite recursion
    }
  }
  $self->{INFINITE_LOOP_PROTECTION} = 0;
}



1;
