#----------------------------------------------------------------
# Copyright (c) 2002 Benjamin Crowell, all rights reserved.
#
# This software is available under version 2 of the GPL license.
# The software is copyrighted, and you must agree to the
# license in order to have permission to copy it. The full
# text of the license is given in the file titled Copying.
#
#----------------------------------------------------------------

=head2 ExtraGUI.pm

This module contains a bunch of miscellaneous GUI code for making
windows other than the main Browser.pm window, e.g. dialog boxes.
For the most part, Browser.pm calls routines in ExtraGUI.pm,
not the other way around.
The only exceptions are (1) we do calls to
 Browser::empty_toplevel_window(); (2) we make use
of $Browser::words.

=cut

use strict;

use Cwd;
use Tk;
use Browser;
use MyWords;
use Input;
use Preferences;

package ExtraGUI;

use Words qw(w get_w);

BEGIN {
  my %fonts = ();
  my %size    = ('plain' => 11,          'bold' => 11,          'small_plain' => 10,         'fixed_width'=>14);
  my %family  = ('plain' => 'helvetica', 'bold' => 'helvetica', 'small_plain' => 'helvetica','fixed_width'=>'courier');
  my %weight  = ('plain' => 'normal',    'bold' => 'bold',      'small_plain' => 'normal',   'fixed_width'=>'normal');
  my %slant   = ('plain' => 'roman',     'bold' => 'roman',     'small_plain' => 'roman',    'fixed_width'=>'roman');
  my $widget; # Gets initialized by calling fonts_init. We just need to have some widget
              # that we can call the fontCreate() method on.
  sub fonts_init {
    $widget = shift;
  }
  sub font {
    my $style = shift;
    if (!exists($fonts{$style})) {
      $fonts{$style} = $widget->fontCreate(-size=>$size{$style},-family=>$family{$style},-weight=>$weight{$style},-slant=>$slant{$style});
    }
    return $fonts{$style};
  }
}

=head3 preferred_location

Returns a geometry string describing where dialog boxes should be placed: in front of the main window,
and just a little lower at the top, like ``sheets'' in MacOS X.

=cut

sub preferred_location {
  my ($x,$y) = preferred_location_coords();
  # For some reason, the main window's geometry is returned as the coordinates of the /interior/
  # of the window. Therefore, we don't really need to add anything to $y.
  return coords_to_geometry_string($x,$y);
}

sub offset_location {
  my $xoffset = shift; my $yoffset = shift;
  my ($x,$y) = preferred_location_coords();
  return coords_to_geometry_string($x+$xoffset,$y+$yoffset);
}

sub coords_to_geometry_string {
  my $x = shift; my $y = shift;
  if (! ($y =~ m/^[\+\-]/)) {$y='+'.$y}
  if (! ($x =~ m/^[\+\-]/)) {$x='+'.$x}
  return $x.$y;
}

sub preferred_location_coords {
  Browser::main_window()->geometry() =~ m/^=?(\d+)x(\d+)([+-]\d+)([+-]\d+)$/;
  return ($3,$4);
}

=head3 choose_file()

Displays a file dialog box.

=cut

sub choose_file {
  my %args = (
    CALLBACK=>sub{},
    TITLE=>'',
    CREATE=>0,
    PATH=>Cwd::getcwd(),
    INITIALFILE=>'',
    FILETYPES=>[['OpenGrade Files','.gb'],['JSON Files','.json'],['All Files','*']],
    DEFAULT_EXTENSION=>'.gb',
    WHAT=>'input', # can also be 'output'
    @_,
  );
  my $callback = $args{CALLBACK};
  my $filetypes = $args{FILETYPES};
  my $title = $args{TITLE};
  my $default_extension = $args{DEFAULT_EXTENSION};
  my $path = $args{PATH};
  my $initialfile = $args{INITIALFILE};
  $path =~ s|/$||;

  # man 3 Tk::getOpenFile

  my $file_name;
  if ($args{WHAT} eq 'input') {
    # choosing file to open:
    $file_name = Browser::main_window()->getOpenFile(-initialdir=>$path,-title=>$title,-filetypes=>$filetypes);
  }
  if ($args{WHAT} eq 'output') {
    # choosing file to save as:
    $file_name = Browser::main_window()->getSaveFile(-initialdir=>$path,-initialfile=>$initialfile,-title=>$title,-defaultextension=>$default_extension);
  }
  &$callback($file_name);
}


=head3 error_message()

Takes one parameter, which is the error message.

=cut

sub error_message {
  my $message = shift;
  local $Words::words_prefix = "b.error_message";
  my $box = Browser::empty_toplevel_window(w('error'));
  $box->Label(-text=>$message,-justify=>'left',-font=>font('plain'))->pack();
  $box->Button(-text=>w("ok"),-command=>sub{$box->destroy()})->pack();
  $box->geometry(preferred_location());
  beep_if_allowed($box);
}


=head3 message()

Takes one parameter, which is the message. Cf. error_message().


=cut

sub message {
  my $message = shift;
  local $Words::words_prefix = "b.error_message";
  my $box = Browser::empty_toplevel_window('');
  $box->geometry(preferred_location());
  $box->Label(-text=>$message,-justify=>'left',-font=>font('plain'))->pack();
  $box->Button(-text=>w("ok"),-command=>sub{$box->destroy()})->pack();
}

=head3 confirm()

First argument is a question, e.g., "Drop Al Einstein?"
Second argument is a callback, which gets
1 if they hit ok, 0 if they cancel.
This can also be used for other kinds of two-choice dialog boxes:
the third and fourth arguments, if present, are text to use
instead of OK and Cancel. The optional fifth argument says whether to
beep. (When using the fifth argument, can set third and fourth to undef
if you want their defaults.)

=cut

sub confirm {
  my $question = shift;
  my $callback = shift;
  local $Words::words_prefix = "b.dialog";
  my ($ok_text,$cancel_text);
  if (@_) {$ok_text = shift}
  if (@_) {$cancel_text = shift}
  $ok_text = w('ok') unless defined $ok_text;
  $cancel_text = w('cancel') unless defined $cancel_text;
  my $beep = 0;
  if (@_) {$beep = shift}
  if ($beep) {beep_if_allowed(Browser::main_window())}
  choices($question,[$ok_text,$cancel_text],[sub{&$callback(1)},sub{&$callback(0)}]);
}

=head3 choices()

Present the user with a set of choices, in the form of a question with some buttons below it.
First argument is the question. Second argument is an array ref of strings for the choices.
Third argument is an array ref of callbacks.

=cut

sub choices {
  my $question = shift;
  my $choices = shift; # array ref
  my $callbacks = shift; # array ref
  local $Words::words_prefix = "b.dialog";
  my $box = Browser::empty_toplevel_window(w('confirm'));
  $box->geometry(preferred_location());
  if (length($question)>90) {
    my ($width,$height) = (100,int(length($question)/90)+1);
    my $n_lines = 1;
    while ($question=~m/\n/g) {++$n_lines}
    $height = $n_lines if $n_lines>$height;
    my $t = $box->Scrolled("Text",
        -scrollbars=>'e',
        -width=>$width,
        -height=>$height,
    )->pack();
    my $text_without_newline_at_end = $question;
    $text_without_newline_at_end =~ s/\n$//; # newline at the end is shown as an extraneous blank line
    $t->insert('end',$text_without_newline_at_end);
  }
  else {
    $box->Label(-text=>$question,-justify=>'left',-font=>font('plain'))->pack();
  }
  my @callback_array;
  my $i = 0;
  foreach my $choice(@$choices) {
    my $callback = $callbacks->[$i];
    $box->Button(-text=>$choice,-command=>sub{$box->destroy();&$callback()})->pack();
    $i++;
  }
}

=head3 ask()

Get a string as input in a dialog box.

    PROMPT=>"?",
    TITLE=>"",
    WIDTH=>40,
    CALLBACK=>sub{},
    ACTION_BUTTON=>w("ok"),
    DEFAULT=>'',
    PASSWORD=>0

The callback routine gets the result, or gets no argument if the
user hit cancel.

=cut

sub ask {
  local $Words::words_prefix = "b.dialog";
  my %args = (
    PROMPT=>"?",
    TITLE=>"",
    WIDTH=>40,
    CALLBACK=>sub{},
    ACTION_BUTTON=>w("ok"),
    DEFAULT=>'',
    PASSWORD=>0,
    BEEP=>0, # If set to 1, /and/ if user's prefs allow it, beep.
    @_
  );
  my $callback = $args{CALLBACK};
  my $result = $args{DEFAULT};
  my $pwd = $args{PASSWORD};
  my $beep = $args{BEEP};
  my @pwd_option = ();
  if ($pwd) {@pwd_option=(-show=>'*')}
  my $box = Browser::empty_toplevel_window($args{TITLE});
  $box->geometry(preferred_location());
  $box->Label(-anchor=>'w',-justify=>'left',-text=>$args{PROMPT})->pack();
  my $f = $box->Frame->pack(-side => 'right');
  my $e = $box->Entry(
              -takefocus=>1,
              -width=>$args{WIDTH},
              -textvariable=>\$result,
              @pwd_option,
  )->pack(-side=>'left');
  $e->focus();
  $e->icursor('end');
  $f->Button(-text=>w("cancel"),-command=>sub{$box->destroy();&$callback()})->pack(-side=>'right');

  # In the following, it actually makes a big difference whether we do KeyRelease or KeyPress. When it
  # was KeyPress, I could type in a bogus grade (too high) and hit return, and the KeyRelease would
  # happen after the error dialog had already popped up, causing it to go away instantly!
  #$e->bind('<KeyRelease-Return>'=>sub{$box->destroy();&$callback($result)});
  $e->bind('<KeyPress-Return>'=>sub{$box->destroy();&$callback($result)});

  $f->Button(-text=>w("ok"),-command=>sub{$box->destroy();&$callback($result)})->pack(-side=>'right');
  if ($beep) {beep_if_allowed($box)}
}

sub open_file_in_editor {
  my $text = shift;
  local $Words::words_prefix = "b.dialog";
  my $command = Preferences->new()->get('editor_command');
  if (@_) {$command = shift}
  if (Portable::os_has_unix_shell()) {
    if (!($command=~/\w/)) {error_message(w('no_open_command')); return}
    my $temp_file = save_text_in_temporary_file($text);
    system("$command $temp_file")==0 or ExtraGUI::error_message("Error executing Unix shell command $command, $?");;
  }
}

sub print_file {
  my $text = shift;
  local $Words::words_prefix = "b.dialog";
  if (Portable::os_has_unix_shell()) {
    my $command = Preferences->new()->get('print_command');
    if (!($command=~/\w/)) {error_message(w('no_print_command')); return}
    my $temp_file = save_text_in_temporary_file($text);
    system("$command $temp_file");
  }
}

sub save_text_in_temporary_file {
  my $text = shift;
  my $temp_file = POSIX::tmpnam();
  END {unlink($temp_file)}
  open(FILE,">$temp_file");
  print FILE $text;
  close FILE;
  return $temp_file;
}

sub save_plain_text_to_file {
  my $text = shift;
  my $path = '.';
  if (@_) {$path = shift}
  my $initialfile = ''; # just the tail of the filename
  if (@_) {$initialfile = shift}
  my $options = {};
  if (@_) {$options = shift}
  local $Words::words_prefix = "b.dialog";
  my $filename = $path;
  if ($path eq '.') {
    $filename = '';
  }
  if ($filename ne '' && !($filename =~ m@/$@)) {$filename="$filename/"} # put a slash on the end if it doesn't already have one

  my $do_it = sub {
              local $Words::words_prefix = "b.dialog";
              my $really_do_it = shift;
              if ($really_do_it == 1) {
                my $err = '';
                if ($err eq '') {
                  if (open(FILE,">$filename")) {
                    print FILE $text;
                    close(FILE);
                  }
                  else {
                    $err = sprintf w('error_opening_for_output'),$filename;
                  }
                }
                if ($err ne '') {error_message($err)}
              }
  };
  my $callback = sub {
              local $Words::words_prefix = "b.dialog";
              $filename = shift;
              if ($filename eq '') {return} # user canceled
              my $err = '';
              my $prefs = Preferences->new();
              $prefs->set('recent_directory',UtilOG::directory_containing_filename(UtilOG::absolute_pathname($filename)));
              if ($filename =~ m/\.gb$/ && !exists $options->{'on_top_ok'}) {$err = w('save_on_top_of_gb')}
              # If we're overwriting a preexisting file, getOpenFile will already have asked for confirmation.
              if ($err eq '') {
                                                                &$do_it(1);
              }
              else {
                error_message($err);
              }
  };

  ExtraGUI::choose_file(TITLE=>w('save_as'),WHAT=>'output',CREATE=>1,DEFAULT_EXTENSION=>'',CALLBACK=>$callback,PATH=>$filename,INITIALFILE=>$initialfile);

}


=head3 show_text()

Show some text, and give the user the option of saving it in a file.
    TITLE=>"",
    TEXT=>"",
    WIDTH=>60,
    MIN_HEIGHT=>3,
    MAX_HEIGHT=>40,
    BGCOLOR=>"white",
    PATH=>'.', # default directory for saving
    OPEN_WITH=>'',
    DESCRIBE_OPEN_WITH=>'',
    EXTRA_BUTTONS=>{}, # hash whose keys are text for buttons, and whose contents are subs to execute

=cut

sub show_text {
  local $Words::words_prefix = "b.dialog";
  my %args = (
    TITLE=>"",
    TEXT=>"",
    WIDTH=>60,
    MIN_HEIGHT=>3,
    MAX_HEIGHT=>40,
    BGCOLOR=>"white",
    PATH=>'.', # default directory for saving
    FILENAME=>'', # default filename for saving
    OPEN_WITH=>'',
    DESCRIBE_OPEN_WITH=>'',
    EXTRA_BUTTONS=>{},
    @_,
  );
  my $text = $args{TEXT};
  my $width = $args{WIDTH};
  my $nlines = 0;
  my @lines = split /\n/,$text; # in scalar context, we get the number of elements in the array
  foreach my $line(@lines) {
    $nlines = $nlines + int(length($line)/$width) + 1;
  }
  my $height = $nlines;
  if ($height>$args{MAX_HEIGHT}) {$height=$args{MAX_HEIGHT}}
  if ($height<$args{MIN_HEIGHT}) {$height=$args{MIN_HEIGHT}}
  my $box = Browser::empty_toplevel_window($args{TITLE});
  $box->geometry(preferred_location());
  my $t = $box->Scrolled("Text",
        -scrollbars=>'e',
        -width=>$width,
        -height=>$height,
        -background=>$args{BGCOLOR},
        -font=>ExtraGUI::font('fixed_width'),
#        -font=>ExtraGUI::font('plain'),
  )->pack();
  my $text_without_newline_at_end = $text;
  $text_without_newline_at_end =~ s/\n$//; # newline at the end is shown as an extraneous blank line
  $t->insert('end',$text_without_newline_at_end);
  # Note: The following is commented out because even though this routine is meant to be used
  # with immutable text, if you disable the Text object, they can't copy it to the clipboard.
  #  $t->configure(-state => 'disabled'); # so they can't type in it
  my $f = $box->Frame();
  $f->Button(-text=>w('ok'),-command=>sub{$box->destroy()})->pack(-side=>'left');
  $f->Button(-text=>w('save'),-command=>sub{save_plain_text_to_file($args{TEXT},$args{PATH},$args{FILENAME}); $box->destroy()})->pack(-side=>'left');
  if (Portable::os_has_unix_shell()) {
    $f->Button(-text=>w('open'),-command=>sub{open_file_in_editor($args{TEXT}); $box->destroy()})->pack(-side=>'left');
    if ($args{OPEN_WITH}) {
      $f->Button(-text=>$args{DESCRIBE_OPEN_WITH},-command=>sub{open_file_in_editor($args{TEXT},$args{OPEN_WITH}); $box->destroy()})->pack(-side=>'left');
    }
    $f->Button(-text=>w('print'),-command=>sub{print_file($args{TEXT}); $box->destroy()})->pack(-side=>'left');
  }
  my $extra_buttons = $args{EXTRA_BUTTONS};
  foreach my $button(keys %$extra_buttons) {
    my $sub = $extra_buttons->{$button};
    $f->Button(-text=>$button,-command=>sub{&$sub(); $box->destroy()})->pack(-side=>'left');
  }
  $f->pack();
}

=head3 fill_in_form

Arguments:

      INPUTS=>[], # ref to an array of Input objects
      TITLE=>"",
      INFO=>'',   # information displayed at the top
      CALLBACK=>sub{},
      CANCEL_CALLBACK=>sub{},
      COLUMNS=>2, # 2=prompts side by side with blanks, 1=vertical arrangement
      WIDTH=>80,

This routine creates a dialog box and asks for the inputs referred to in the INPUTS array.
Then it calls the callback routine, giving it a
reference to a hash containing the strings given by the
user. The hash keys are defined by the {KEY} instance variables of the Input objects.

=cut

sub fill_in_form {
  local $Words::words_prefix = "b.dialog";
  my %args = (
        INPUTS=>[], # ref to an array of Input objects
        TITLE=>"",
        INFO=>'',   # information displayed at the top
        CALLBACK=>sub{},
        CANCEL_CALLBACK=>sub{},
        COLUMNS=>2, # 2=prompts side by side with blanks, 1=vertical arrangement
        WIDTH=>80,
        HEIGHT=>'',
        MAX_HEIGHT=>35,
        XOFFSET=>0,
        YOFFSET=>0,
        OK_TEXT=>w('ok'),
        CANCEL_TEXT=>w('cancel'),
        @_,
  );
  my $callback = $args{CALLBACK};
  my $cancel_callback = $args{CANCEL_CALLBACK};
  my $inputs = $args{INPUTS};
  my $info = $args{INFO};
  my $xoffset = $args{XOFFSET};
  my $yoffset = $args{YOFFSET};
  my $n_inputs = @$inputs;
  my $max_height = $args{MAX_HEIGHT};
  my $height;
  if ($args{HEIGHT} ne '') {
    $height=$args{HEIGHT}
  }
  else {
    # They get a scrollbar if it's too small, but too big can be a pain, because the OK button is hidden.
    $height = 10+6*$n_inputs;
    if ($height>$max_height) {
      $height = $max_height;
    }
  }
  my %results = ();
  my $box = Browser::empty_toplevel_window($args{TITLE});
  $box->geometry(offset_location($xoffset,$yoffset));

  if ($info ne '') {
    $box->Label(-anchor=>'w',-justify=>'left',-text=>$info,-width=>$args{WIDTH})->pack(-side=>'top');
  }

  my $f = $box->Frame->pack(-side => 'bottom');
  $f->Button(-text=>$args{OK_TEXT},
     -command=>
       sub{
         my $has_errors = 0;
         my $error_text = '';
         foreach my $input(@$inputs) {
           my $key = $input->{KEY};
           my $retrieve = $input->{RETRIEVE};
           my $value = &$retrieve;
           my @err_stuff = $input->check($value);
           if ($input->{TYPE} eq 'date' && !exists $input->{TERM}) {push @err_stuff,"programming error, no TERM supplied for input with TYPE=>'date'"}
           my $is_an_error = @err_stuff;
           $has_errors = $has_errors || $is_an_error;
           if ($is_an_error) {
             my $fmt = shift @err_stuff;
             my $this_error = (sprintf $fmt,(@err_stuff));
             $error_text = $error_text . $key.": ".$this_error."\n";
           }
           else {
             if ($input->{TYPE} eq 'date' && $value ne '') {
               $value = DateOG::disambiguate_year($value,$input->{TERM});
             }
           }
           $results{$key} = $value;
         }
         if (!$has_errors) {
                 $box->destroy();
                 &$callback(\%results)
         }
               else {
                 error_message($error_text);
         }
       }
  )->pack(-side=>'left'); 
  $f->Button(-text=>$args{CANCEL_TEXT},
     -command=>[
       sub{
         my $box = shift;
         my $callback = shift;
         my $results = shift;
         $box->destroy();
         &$cancel_callback()
       }
       ,$box,$cancel_callback
     ]
  )->pack(-side=>'left');

  my $ncols = $args{COLUMNS};
  my $t;
  if ($ncols==2) {
    $t = $box->Scrolled("Text",
         -scrollbars=>'oe',
         -width=>$args{WIDTH},
         -height=>$height,
    )->pack();
  }
  else { # one column
    $t = $box->Scrolled("Text",
        -scrollbars=>'oe',
        -width=>$args{WIDTH},
        -height=>$height,
    )->pack();

  }
  my $first_one = 1;
  foreach my $input(@$inputs) {
    my $which = $input->{KEY};
    my $w = $t->Label(-anchor=>'w',-justify=>'left',-text=>$input->{PROMPT},-width=>$args{WIDTH}/$ncols);

    $t->windowCreate('end',-window=>$w);
    if ($args{COLUMNS}==1) {$t->insert('end',"\n");}
    $results{$which} = $input->{DEFAULT};
    if ($input->{WIDGET_TYPE} eq 'entry') {
      $w = $t->Entry(
                   -textvariable=>\$results{$which},
       -width=>$args{WIDTH}/$ncols,
      );
      $input->{RETRIEVE} = sub{return $results{$which}}
    }
    if ($input->{WIDGET_TYPE} eq 'menu') {
      $w = $t->Frame;
      my $map = $input->{ITEM_MAP};
      my %reverse_map = reverse %$map;
      my $keys = $input->{ITEM_KEYS};
      die if ! defined $keys;
      my $rr = $map->{$input->{DEFAULT}};
      my $om = $w->Optionmenu(-variable=>\$results{$which},-textvariable=>\$rr)->pack(-side=>'left');
      $om->addOptions(map {[$map->{$_},$_]} @$keys);
      $results{$which} = $input->{DEFAULT};
      $input->{RETRIEVE} = sub{return $results{$which}};
    }
    if ($input->{WIDGET_TYPE} eq 'date') {
      $w = $t->Frame;
      my $d = $input->{DEFAULT}; # guaranteed to have been disambiguated already by Input::new, but may be null
      my ($dy,$dm,$dd);
      $input->{TERM} =~ /^(\d+)\-(\d+)/; # y-m or y-m-d ... extract ym; Input makes sure TERM already exists
      my ($ty,$tm) = ($1,$2);
      my ($year,$month,$day);
      if ($d) {
        ($dy,$dm,$dd)=split('-',$d);
      } else {
        if ($input->{BLANK_ALLOWED}) {
          ($dm,$dd)=(0,'');
        }
        else {
          ($dm,$dd)=($tm,1);
        }
      }
      my $map = {1=>w('january'),2=>w('february'),3=>w('march'),4=>w('april'),5=>w('may'),6=>w('june'),7=>w('july'),8=>w('august'),9=>w('september'),
                    10=>w('october'),11=>w('november'),12=>w('december'),};
      my $low_m = 1;
      if ($input->{BLANK_ALLOWED}) {$map->{0}=w('none'); $low_m=0}
      my %reverse_map = reverse %$map;
      my $rr = $map->{$dm+0};
      my $om = $w->Optionmenu(-variable=>\$month,-textvariable=>\$rr)->pack(-side=>'left');
      $om->addOptions(map {[$map->{$_},$_]} ($low_m..12));
      my $e = $w->Entry(-textvariable=>\$day,-width=>2)->pack(-side=>'left');
      if ($d) {$month = $dm}
      if ($d) {$day = $dd}
      $results{$which} = $input->{DEFAULT};
      my $today = $w->Button(-text=>'Today',-command=>sub{
        ($year,$month,$day)=split('-',DateOG::current_date_sortable());
        my $mm = $month;
        $om->setOption($map->{$month+0});
        $month = $mm;
      })->pack(-side=>'left');   
      my $yesterday = $w->Button(-text=>'Yesterday',-command=>sub{
        ($year,$month,$day)=split('-',DateOG::day_before(DateOG::current_date_sortable()));
        my $mm = $month;
        $om->setOption($map->{$month+0});
        $month = $mm;
      })->pack(-side=>'left');   
      $input->{RETRIEVE} = sub{
        if ($month==0) {return ''}
        $results{$which} = "$month-$day"; $results{$which}=DateOG::disambiguate_year($results{$which},$input->{TERM}); return $results{$which}
      };
    }
    if ($input->{WIDGET_TYPE} eq 'radio_buttons') {
      $w = $t->Frame;
      my $radio_buttons = $input->{ITEM_MAP};
      my $order = $input->{ITEM_KEYS};
      foreach my $value(@$order) {
        $w->Radiobutton(-text=>$radio_buttons->{$value},-value=>$value,-variable=>\$results{$which})
                        ->pack(-side=>'left');
      }
      $results{$which} = $input->{DEFAULT};
      $input->{RETRIEVE} = sub{return $results{$which}};
    }
    if ($input->{WIDGET_TYPE} eq 'text') {
      $w = $t->Scrolled('Text',
        -scrollbars=>'e',
        -width=>$args{WIDTH}/$ncols,
        -height=>200);
      $input->{RETRIEVE} = sub{return $w->get('1.0','end');}
    }
    $t->windowCreate('end',-window=>$w);
    if ($first_one) {$w->focus}
    $first_one = 0;
    $t->insert('end',"\n");
  }
  $t->configure(-state => 'disabled'); # so they can't type in it
}


=head3 beep_if_allowed

Called with one argument, just beeps (if allowed). Use this only when the actual error is being displayed in
its own dialogbox.

Normally you call it with three arguments. The second argument is the BrowserWinudow, 
 and the third is a key of a message to display at the
bottom of the window, e.g., 'luser' for 'b.beep.luser'.

You can call it with four arguments, in which case the fourth is used as a %s argument to sprinf.

=cut

sub beep_if_allowed {
  my $widget = shift; # Browser::main_window()
  my $browser_window = undef;
  if (@_) {$browser_window = shift}
  my $message_code = '';
  if (@_) {$message_code = shift}
  my $message_info = '';
  if (@_) {$message_info = shift}
  local $Words::words_prefix = 'b.beep';
  if (want_beeps()) {$widget->bell}
  if ($message_code ne '') {
    my $message = w($message_code);
    if ($message_info ne '') {$message = sprintf $message,$message_info}
    $browser_window->set_footer_text($message);
  }
}

sub want_beeps {
  return Preferences->new()->get('beep');
}

sub audio_feedback {
  my $what = shift;
  return if ! want_beeps();
  my $sound_file = {"ch"=>"ch.wav","ambiguous"=>"ambiguous.wav","duh"=>"chopsticks.wav"}->{$what};
  return if !defined $sound_file;
  my $sound_dir = "/usr/share/apps/opengrade/sounds/";
  my $cmd = "aplay $sound_dir$sound_file"; # aplay is part of alsa-utils; use instead of sox's play, which no longer works
  system($cmd);
}

1;
