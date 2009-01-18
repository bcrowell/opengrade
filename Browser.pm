#----------------------------------------------------------------
# Copyright (c) 2002 Benjamin Crowell, all rights reserved.
#
# This software is available under version 2 of the GPL license.
# The software is copyrighted, and you must agree to the
# license in order to have permission to copy it. The full
# text of the license is given in the file titled Copying.
#
#----------------------------------------------------------------

=head2 Browser.pm

Browser.pm is the main module containing the GUI (so named because
I originally envisioned it having an interface sort of like a web
browser.)

The following is the hierarchy of who creates and destroys whom:

 Browser::main_loop()
   BrowserData
   BrowserWindow
     Stage
       Roster
       Grades

=cut

use strict;
use English;

use Tk;
use Tk ':variables';
require Tk::ErrorDialog; # show errors in dialog boxes, rather than printing to console
use BrowserData;
use BrowserWindow;
use ExtraGUI;
use GradeBook;
use Crunch;
use Report;
use MyWords;
use UtilOG;
use DateOG;
use Input;
use NetOG;
use Fun;
use Digest::SHA1;
use Version;
use POSIX qw(tmpnam);

package Browser;

use Words qw(w get_w);


our $mw; # main window

sub main_loop {
  my $file_name = shift;
  my $death = '';
  if (@_) {$death = shift} # if 2nd arg isn't a null string, it's a fatal error to show the user before dying

  local $Words::words_prefix = "b.main_loop";
  local $Words::words = Words->new(FORMAT=>"terminal",LANGUAGE=>"en");

  $mw = MainWindow->new;
  $mw->geometry("+90+30");
  $mw->maxsize(($mw->screenwidth)-50,($mw->screenheight)-50);
  $mw->minsize(580,600);
    # ... When you run opengrade from the command line, with a file as an argument, it pops up the password dialog before the main window is really
    #     done being drawn. This minsize setting makes sure that the main window isn't ridiculously short. Once the file is opened, the main window gets bigger.
  ExtraGUI::fonts_init($mw);
  my $browser_data = BrowserData->new($file_name);
  my $browser_window = BrowserWindow->new($browser_data,$mw);
  if (ref $browser_data->{GB}) {
    $browser_data->{GB}->undo_callback(sub{$browser_window->adjust_after_undo(@_)});
  }
  $browser_window->set_footer_text(w("startup_info"));
  $mw->repeat(5000,\&periodic_actions); # every 5000 milliseconds, i.e., once every 5 seconds

  my $gtk_version = Version::gtk_version();
  if ($gtk_version) {
    $gtk_version =~ m/(.*)\.(.*)\.(.*)/;
    my ($a,$b,$c) = ($1,$2,$3);
    my $tk_version = $Tk::VERSION;
    if (($a*10000+$b*100+$c)>=20801 && $tk_version<=804.001) {
      my $message = 
<<TK_BUG;
Sorry, but you're running GTK2 version $gtk_version, which is incompatible with Perl/Tk $tk_version.
Due to a known bug in Perl/Tk, this version of Perl/Tk is not compatible with versions of the GTK+
libraries later than 2.8.0. You will find that whenever you run a GTK+ application alongside of
OpenGrade, it will cause OpenGrade to crash. You should upgrade to Perl/Tk 804.
Because this is a serious problem that could cause students' grades to
be lost, opengrade will not run on your system. After you click on OK or Cancel, opengrade
will exit.
TK_BUG
      ExtraGUI::confirm($message,sub{exit});
    }
  }

  if ($death) {
    ExtraGUI::confirm($death,sub{exit});
  }

  Tk::MainLoop();
}

sub periodic_actions {
  foreach my $gb(@ogr::open_files) {
    $gb->auto_save_if_they_want_it();
  }
}


=head3 empty_toplevel_window()

Takes one argument, which is the title. Returns
a Toplevel, which it has set to transient.

=cut

sub empty_toplevel_window {
  my $title = shift;
  my $it = $mw->Toplevel();
  $it->transient($mw);
  $it->title($title);
  return $it;
}

=head3 main_window()

I'd prefer not to use this, since empty_toplevel_window()
keeps Browser's data safer, but Tk::FileDialog requires this.

=cut

sub main_window {
  return $mw;
}

#---------------------------------------------------
# Prefs class
#---------------------------------------------------

=head3 Prefs

Preferences for how the GUI is displayed.

=cut

package Prefs;

sub get_focus_highlight_thickness {return 2}
sub get_focus_highlight_color     {return 'blue'}
sub get_roster_hover_color        {return '#e8f0ff'}
sub get_roster_bg_color_1         {return '#e0ffe0'}
sub get_roster_bg_color_2         {return '#fcfffc'}


1;
