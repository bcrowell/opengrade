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

package TermUI;

use Term::ReadKey;

use GradeBook;
use Crunch;
use Report;
use Words qw(w get_w);
use MyWords;
use UtilOG;
use DateOG;

our $up_arrow_seq = chr(27).chr(91)."A";
our $down_arrow_seq = chr(27).chr(91)."B";

# See the Words and MyWords modules for info on the following.
our $words;                        # initialized in main_loop()
our $words_prefix;                # initialized in each routine

sub main_loop {
    my $command_line_file_argument = shift;

    local $Words::words = Words->new(FORMAT=>"terminal",LANGUAGE=>"en",WIDTH=>"80");
    local $Words::words_prefix = "main_loop";

    my $file_open = 0;
    my $gb;

    print_startup_info();

    if ($command_line_file_argument ne "") {
      $gb = open_gb($command_line_file_argument);
      if (ref $gb) {
        ogr::add_to_list_of_open_files($gb);
        $file_open = 1;
      }
      else {
        print "$gb\n";
      }
    }


    my $who = UtilOG::guess_username();

    MAIN_LOOP: while (1) {



        my $mod = ($file_open && $gb->modified);
        if ($mod) {$gb->auto_save_if_they_want_it()}
        print "-----------------------------------------------------------\n";
        print w("user").": $who     ".w("date").": ".DateOG::current_date_human()."\n";
        if ($file_open) {
            print $gb->file_name().": ".$gb->title();
            if ($mod) {print " (modified)"} else {print " (not modified)"}
            print "\n";
        }
        print w("main_menu_header\n");
        if ($file_open) {
          print "  a ".w("enter_grades_alpha\n");
          print "  1 ".w("enter_grades_1\n");
          print "  e ".w("edit\n");
          print "  r ".w("reports\n");
          print "  u ".w("upload_grades\n");
          print "  c ";
          if ($mod) {
              print w("save_and_close");
          }
          else {
              print w("close");
          }
          print "\n";
          print "  s ".w("save");
          if (!$mod) {
              print " ".w("save_not_necessary");
          }
          print ",\n";
          if ($mod) {
              print "  revert ".w("revert\n");
          }
        }
        else {
          print "  n ".w("new\n");
          print "  o ".w("open\n");
        }
        print "  q ";
        if ($mod) {
          print w("save_and_quit");
        }
        else {
          print w("quit");
        }
        print "\n";
        my $choice = lc(ask());
        if ($file_open) {
          if ($choice eq "a") {grade_an_assignment($gb,"a")}
          if ($choice eq "1") {grade_an_assignment($gb,"1")}
          if ($choice eq "r") {view_a_report($gb)}
          if ($choice eq "e") {edit($gb)}
          if ($choice eq "u") {upload_grades($gb)}
          if ($choice eq "c") {
              if ($mod) {print w("writing_file\n"); print $gb->write()}; 
              $file_open = 0;
              ogr::remove_from_list_of_open_files($gb);
              $gb->close();
              $gb = "";
          }
          if ($choice eq "revert") {
              $file_open = 0;
              $gb = "";
          }
          if ($choice eq "s") {
              print w("writing_file\n");
              print $gb->write();
              $gb->modified(0);
          }
          if ($choice eq "q") {
              if ($mod) {print w("writing_file\n"); print $gb->write()}; 
              last MAIN_LOOP
          }
        }
        if (!$file_open) {
          if ($choice eq "n") {
              $gb = new_file();
              $file_open = 1;
              ogr::add_to_list_of_open_files($gb);
          }
          if ($choice eq "o") {
              print w("enter_filename_to_open\n");
              my $file_name = TermUI::ask("");
              $gb = open_gb($file_name);
              if (ref $gb) {
                $file_open = 1;
                ogr::add_to_list_of_open_files($gb);
              }
              else {
                  print "$gb\n";
              }
          }
          if ($choice eq "q") {last MAIN_LOOP}
        }
    }
    print w("done\n");
}


sub open_gb {
  my $filename = shift;
  local $Words::words_prefix = "open_gb";
  my $password = ask(PROMPT=>w("password"),PASSWORD=>1);
  my $gb = GradeBook->read($filename,$password);
  if (!ref $gb) {
    print "Error opening file $filename: $gb\n";
    return "";
  }
  my $auth = $gb->{AUTHENTICITY};
  if ($auth ne "" && $auth ne "bad header") {
    print "Incorrect password.\n";
    return "";
  }
  if ($auth eq "bad header") {
    print "This file appears not to have authentication codes. Codes will be added.\n";
  }

  return $gb;
}

sub upload_grades {
    my $gb = shift;
    my $done = 0;
    my $error = Report::upload_grades(GB=>$gb,
          PROGRESS_BAR_CALLBACK=>sub{
            print ".\n";
          },
          FINAL_CALLBACK=>sub{
            $done = 1;
          }
    );
    for (;;) {
      sleep 1;
      last if $done;
    }
}

sub edit {
    my $gb = shift;

    local $Words::words_prefix = "edit";

    while (1) {                
        print w("menu_header\n");
        print "    c ".w("edit_categories\n");
        print "    s ".w("edit_students\n");
        print "    ".w("main_menu\n");
        my $choice = ask();
        my $result = "";
        if ($choice eq "-" or $choice eq "m") {return}
        if ($choice eq "c") {$result = edit_categories($gb)}
        if ($choice eq "s") {$result = edit_students($gb)}
        if ($result eq "m") {return}
    }
}

sub edit_categories {
    my $gb = shift;

    local $Words::words_prefix = "edit_categories";

    while (1) {
        print "Categories --- enter\n";
        print "      a ".w("add\n");
        print "      - ".w("edit_menu\n");
        print "      m ".w("main_menu\n");
        my $choice = ask();
        if ($choice eq "a") {
            my $key = "";
            while ($key eq "" || $gb->category_exists($key)) {
              print w("enter_short_name\n");
              $key = ask(NULL_ALLOWED=>0);
              $key =~ s/[^a-z]//g;
              if ($gb->category_exists($key)) {print w('category_exists').'\n'}
            }
            print w("enter_singular_noun\n");
            my $sing = ask(NULL_ALLOWED=>0);
            print w("enter_plural_noun\n");
            my $pl = Words::pluralize($sing);
            $pl = ask(DEFAULT=>$pl,PROMPT=>"($pl)");
            print w("enter_number_to_drop\n");
            my $drop = ask(DEFAULT=>0,PROMPT=>"(0)");
            print w("will_it_count\n");
            my $ignored = (ask() eq ".");
            print w("enter_max\n");
            my $max = ask();

            my $w = "";
            if ($gb->weights_enabled()!=0) {
                if ($gb->weights_enabled()==2) {
                    print w("enter_weight\n");
                }
                $w = ask(PROMPT=>w("weight"));
            }

            print w("confirm_add\n");
            my $do_it = "";
            while ($do_it ne "y" && $do_it ne "n") {
              $do_it = lc(ask(PROMPT=>"y or n"));
            }
            if ($do_it eq "y") {
                my $stuff = "\"catname:$sing,$pl\"";
                if ($max) {$stuff = $stuff . ",\"max:$max\""}
                if ($drop>=1) {$stuff = $stuff . ",\"drop:$drop\""}
                if ($ignored) {$stuff = $stuff . ",\"ignore:true\""}
                if ($w ne "") {$stuff = $stuff . ",\"weight:$w\""}
                $gb->add_category($key,$stuff);        # already checked above that it doesn't already exist
                $gb->modified(1);
            }
        }
        if ($choice eq "-") {return ""}
        if ($choice eq "m") {return "m"}
    }
}

# Returns "m" if they want to go back to the main menu.
sub edit_students {
    my $gb = shift;

    local $Words::words_prefix = "edit_students";

    while (1) {                
        print "Edit menu --- enter\n";
        print "      a ".w("add\n");
        print "      d ".w("drop\n");
        print "      r ".w("reinstate\n");
        print "      - ".w("exit\n");
        print "      m ".w("main\n");
        my $choice = lc(ask());
        if ($choice eq "-" || $choice eq "m") {return $choice}
        if ($choice eq "a") {
            while (1) {
              my $last = ask(PROMPT=>w("last_name"));
              if ($last eq "") {last}
              my $first = ask(PROMPT=>w("first_name"),NULL_ALLOWED=>0);
              my $id = ask(PROMPT=>w("student_id"));
              my $pwd = ask(PROMPT=>w("password"));
              $gb->add_student(LAST=>$last,FIRST=>$first,ID=>$id,PWD=>$pwd);
              printf w("added\n"),$first,$last;
              $gb->modified(1);
            }
        }
        if ($choice eq "d") {
            my $student = choose_student($gb);
            if ($student ne "") {
                $gb->drop_student($student);
                printf w("dropped\n"),$student;
                $gb->modified(1);
            }
        }
        if ($choice eq "r") {
            my $student = choose_student($gb,"dropped");
            if ($student ne "") {
                $gb->reinstate_student($student);
                printf w("reinstated\n"),$student;
                $gb->modified(1);
            }
        }
    }
    return "";
}

sub new_file {
    local $Words::words_prefix = "new_file";

    print w("title\n");
    my $title = ask();
    $title =~ s/\"/\\\"/g;
    print w("staff\n");
    my $staff = UtilOG::guess_username();
    if ($staff eq "staff") {
        print w("lame_system\n");
    }
    else {
        print w("cool_system\n");
    }
    my $staff = ask(DEFAULT=>$staff,PROMPT=>"($staff)");
    print w("days_of_week\n");
    my $days = "";
    while ($days eq "" || ! ($days =~ m/^[MTWRFSU]+$/)) {
      $days = uc(ask(DEFAULT=>"MTWRF"));
      if (! ($days =~ m/^[MTWRFSU]+$/)) {
          print w("illegal_day_of_week\n");
      }
    }
    print w("year\n");
    my $year = DateOG::current_date("year");
    $year = ask(DEFAULT=>$year,PROMPT=>"($year)");
    if ($year<1900) {$year = $year + 1900}
    print w("month\n");
    my $month = DateOG::current_date("month");
    $month = ask(DEFAULT=>$month,PROMPT=>"($month)");
    my $term = $year."-".$month;

    print w("standards_header\n");
    my %standards = ();
    while (1) {
        print w("letter_grade\n");
        my $symbol = ask();
        if ($symbol eq "") {last}
        while (1) {
          print w("min_percentage\n");
          my $pct = ask();
          if ($pct =~ m/\d+(\.\d*)?/ && $pct<=100) {
              $standards{$symbol} = $pct;
              last;
          }
          print w("illegal_percentage\n");
        }
    }
    my $standards_comma_delimited = GradeBook::hash_to_comma_delimited(\%standards);

    print w("web_reports_header\n");
    print w("ftp_username\n");        # username for FTP when uploading reports
    my $username = UtilOG::guess_username();
    my $username = ask(DEFAULT=>$username,PROMPT=>"($username)");
    print w("ftp_server\n");        # name of FTP server
    my $server = ask();
    print w("cgi\n");                # location of cgi-bin
    my $cgi_bin = ask(DEFAULT=>"www/cgi-bin",PROMPT=>"(www/cgi-bin)");
    $cgi_bin =~ s|^\/||;
    $cgi_bin =~ s|\/$||;
    my $ftp = $username."@".$server."/".$cgi_bin;
    print w("subdir\n");        # subdir for web reports, relative to cgi-bin
    my $dir = ask(DEFAULT=>"grade_reports",PROMPT=>"(grade_reports)");
    my $done = 0;
    my $file_name;
    while (!$done) {
      print w("file_name\n");
      $file_name = ask(NULL_ALLOWED=>0);
      $done = 1;
      if (-e $file_name) {
        printf w("already_exists\n"),$file_name;
        my $overwrite = lc(ask(PROMPT=>"y or n"));
        if ($overwrite ne "y") {$done = 0}
      }
    }
    my $gb = GradeBook->new(TITLE=>$title,STAFF=>$staff,DAYS=>$days,
                            TERM=>$term,DIR=>$dir,FTP=>$ftp,FILE_NAME=>$file_name,
                            STANDARDS=>$standards_comma_delimited);
    print w("created\n");
    return $gb;
}

sub view_a_report {
    my $gb = shift;

    local $Words::words_prefix = "view_a_report";

    print w("menu_header\n");
    print "      c ".w("totals\n");
    print "      1 ".w("one_student\n");
    print "      a ".w("one_assignment\n");
    print "      s ".w("stats\n");
    my $choice = lc(ask());
    if ($choice eq "c") {my $t= Report::class_totals($gb,"plain"); print $t->text()}
    if ($choice eq "1") {my $t= Report::student(GB=>$gb,STUDENT=>choose_student($gb),
                                                FORMAT=>"plain"); print $t->text()}
    if ($choice eq "a") {
      my $cat = choose_category($gb);
      my $ass = choose_assignment($gb,$cat);
      my $t = Report::sort($gb,"plain*",undef,$cat,$ass);
      print $t->text();
    }
    if ($choice eq "s") {my $t= Report::stats(GB=>$gb,FORMAT=>"plain"); print $t->text()}
}

# Optional second argument:
#   ""          only return active students (default)
#   "all"       return all students
#   "dropped"   return a list of dropped students
sub choose_student {
    my $gb = shift;
    my $criteria = "";
    if (@_) {$criteria = shift}
    local $Words::words_prefix = "choose_student";
    my @student_keys = $gb->student_keys($criteria);
    return choose_one(w("prompt"),
                      w("none_begin_with"),
                      \@student_keys,0,3,0);
}

sub choose_assignment {
    my $gb = shift;
    my $cat = shift;
    local $Words::words_prefix = "choose_assignment";
    my $c = $gb->array_of_assignments_in_category($cat);
    return choose_one(w("prompt"),
                      w("create_new"),
                      $gb->array_of_assignments_in_category($cat),1,16,1);
}

sub choose_category {
    my $gb = shift;
    local $Words::words_prefix = "choose_category";
    return choose_one(w("prompt"),
                      w("none_begin_with"),
                      $gb->category_array(),1,16,0);
}

# One slightly tricky thing here is the handling of null inputs.
# When choosing a student, $allow_unrecognized is turned off, so
# a null input would only be allowed if the number of students in
# the class equals one!
# When adding a new assignment, we ask them to name an assignment
# that they want to place it before, but they can enter a null input
# if they want to put it at the end. In this situation, we want to
# return a null string, even if there is only one assignment in the
# category, which would provide a unique match to the null string.
# So when $allow_unrecognized is turned on, we always return a null
# string as a null string.
sub choose_one {
    my $prompt = shift;
    my $message_none_found = shift;
    my $list_ref = shift;
    my $list_if_null = shift;
    my $max_to_show = shift;
    my $allow_unrecognized = shift;
    print "$prompt\n";
    Term::ReadKey::ReadMode("cbreak");
    my $input = "";
    my @matches;
    KEY_LOOP: while (1) {
        @matches = ();
        foreach my $k(@$list_ref) {
            if ($input eq "" || $k =~ m/^$input/) {push @matches,$k}
        }
        my $show = "$input   ";
        if ($input ne "" || $list_if_null) {
            if ($#matches== -1 && $input ne "") {$show = $show . "$message_none_found $input"}
            if (@matches) {
                for (my $j=0; $j<=$max_to_show-1 && $j<=$#matches; $j++) {
                    $show = $show . $matches[$j]." ";
                }
                if ($#matches>$max_to_show-1) {$show = $show . " ..."}
            }
        }
        if (length($show)<75) {$show = $show . " "x(75-length($show))}
        print "$show\r$input"; # rewrite input on top of itself, position cursor after it
        my $c = lc(Term::ReadKey::ReadKey(0));
        my $del = (ord($c)==127 || ord($c)==8);
        my $tab = (ord($c)==9);
        my $hit_return = ($c eq "\r" || $c eq "\n");
        my $printable = !($del || $tab || $hit_return);
        if ($printable) {$input = $input . $c}
        if ($tab) {$input = longest_common_leading_string(@matches)} 
              # emacs-style cmd completion
        if ($del && length($input)>0) {
            $input = substr($input,0,length($input)-1)
        }
        if ($hit_return  and  $#matches!=0 || $input eq ""  and  $allow_unrecognized) {
                   # ... see note at top of subroutine
            @matches=($input); last KEY_LOOP
        }
          if ($#matches==0 && $hit_return) {last KEY_LOOP}
        if ($input eq "" && $hit_return) {@matches=(""); last KEY_LOOP}
        if ($#matches!=0 && $hit_return) {
            # Check if they selected a string that is the same as the beginning
            # of another string. Otherwise, this is an error.
            my $ok = "";
            foreach my $m(@matches) {
                if ($m eq $input) {$ok = 1}
            }
            if ($ok) {
                @matches = ($input);
                last KEY_LOOP;
            }
            else {
                print "\a"
            }
        }
    }
    Term::ReadKey::ReadMode("normal");
    my $result = $matches[0];
    print "\r". " "x80 . "\r$result\n";
    return $result;
}

sub longest_common_leading_string {
    my @a = @_;
    if ($#a == -1) {return ""}
    my $result = $a[0];
    for (my $j=1; $j<=$#a; $j++) {
        my $x = $a[$j];
        if ($result eq "" || $x eq "") {
            return "";
        }
        while (!($x=~m/^$result/)) {
            $result = substr($result,0,length($result)-1); # chop one char off end
            if ($result eq "") {return ""}
        }
    }
    return $result;
}

sub print_startup_info {
    print w("startup_info\n");
}


sub grade_an_assignment {
    my $gb = shift;
    my $mode = shift; # "a"=alphabetical, "1"=one at a time

    local $Words::words_prefix = "grade_an_assignment";
    
    if (!$gb->has_categories()) {print w("no_cats\n"); return "no categories"}
    print w("header\n");
    my $cat = choose_category($gb);
    if (!$gb->category_exists($cat)) {print w("no_such_cat\n"); return 1}
    my $ass = choose_assignment($gb,$cat);
    $ass =~ s/[ \.]/_/g;
    my $big_ass = $cat.".".$ass;
    my $max;
    if (!$gb->assignment_exists($big_ass)) {
        print w("where_to_put_it\n"); # return=at end, .=cancel, number=before that number
        my $insert_before = choose_one("","",
                      $gb->array_of_assignments_in_category($cat),1,16,1);

        if ($insert_before eq ".") {print w("action_canceled.\n"); return 1}
        my $cat_props = $gb->category_properties_comma_delimited($cat);

        $max = GradeBook::get_property($cat_props,"max");
        my $prompt = w("maximum_score");
        if ($max ne "") {$prompt = "$prompt ($max)"}
        $max = ask(PROMPT=>$prompt,DEFAULT=>$max,
            HELP=>w("max_help"));

        my $due = "";
        while (1) {
          $due = ask(PROMPT=>w("due_date"),NULL_ALLOWED=>1,
                     HELP=>w("due_date_help\n"));
          if ($due eq "" || $due =~ m/^\d+\-\d+(\-\d+)?/) {last}
        }
        if ($due ne "") {$due = DateOG::disambiguate_year($due,$gb->term())}

        my $props = "\"max:$max\"";
        if ($due ne "") {$props = $props .",\"due:$due\""}
        my $result = $gb->add_assignment(CATEGORY=>$cat,ASS=>$ass,
                COMES_BEFORE=>$insert_before,PROPERTIES=>$props);
        $gb->use_defaults_for_assignments();
        if ($result) {print $result; return 1}
    }
    else { # preexisting assmt
        $max = $gb->assignment_property($cat.".".$ass,"max");
        printf w("max_is\n"),$max;
    }
    my @students = $gb->student_keys();
    my %grades = ();
    if ($mode eq "a") {
        print w("how_to_enter_scores\n");
        my $result = "";
        # The only thing funky about the following loop is the handling of the
        # arrow keys. If they hit down arrow, it's just a synonym for return, and
        # that's handled inside enter_one_grade(). If they hit up arrow, we handle it.
        STUDENT_LOOP: for (my $j=0; $j<=$#students; ) {
          my $student = $students[$j];
          $result = enter_one_grade($gb,$student,$cat,$ass,$max,\%grades,
                                    make_leader($#students+1,$j+1));
          if ($result eq "q") {last STUDENT_LOOP}
          if ($result eq "c") {return}
          if ($result ne $up_arrow_seq) {
              $j++;
          }
          else {
              $j-- unless $j==0;
          }
        }
    }
    else {
        while (1) {
          print w("how_to_enter_one\n");
          my $student = choose_student($gb);
          if ($student eq "") {last}
          my $result = enter_one_grade($gb,$student,$cat,$ass,$max,\%grades);
      }
    }
    $gb->set_grades_on_assignment(CATEGORY=>$cat,ASS=>$ass,GRADES=>\%grades);
    $gb->modified(1);
    return "";

  # When entering grades for the entire class, this leader is meant to make
  # it easier to keep track of where you are compared to a printout of the
  # roster. The dashes on every third line are because that's how I chunk my
  # roster printouts.
  sub make_leader {
    my $class_size = shift;
    my $who = shift;
    my $ndig = 2;
    if ($class_size>=100) {$ndig=3}
    if ($class_size>=1000) {$ndig=4}
    my $leader = " ";
    if ($who % 3 == 1) {$leader="-"}
    $leader = $leader . sprintf (("%".$ndig."d "),$who);
    return $leader;
  }

}


sub enter_one_grade {
        local $Words::words_prefix = "enter_one_grade";
        my $gb = shift;
        my $student = shift;
        my $cat = shift;
        my $ass = shift;
        my $max = shift;
        my $grades_hash_ref = shift;
        my $leader = shift;
        my ($first,$last) = $gb->name($student);
        my $current_grade = $gb->get_current_grade($student,$cat,$ass);
        my $full_name = $first." ".$last;
        my $prompt = $leader . $full_name;
        if ($current_grade ne "") {$prompt = $prompt . " (".$current_grade.")"}
        my $ok = "";
        while (!$ok) {
          my $score = ask(PROMPT=>$prompt,ARROW_KEYS=>1);
          if ($score eq "q" || $score eq "c" || $score eq $up_arrow_seq) {return $score}
          if ($score eq $down_arrow_seq) {$score=""}
          $score = lc($score);
          $score =~ s/\+$/.5/;
          $ok = ($score eq "b") || ($score eq "") || ($score eq "x") || ($score =~ m/^\d+$/) || ($score =~ m/^\d*\.5$/);
          if ($score ne "") {
            if ($score>$max && $max>0) { # The second condition is for extra-credit assmts.
                print w("too_high\n"); # return to confirm, or redo, or x to cancel
                print "\a"; # ring the bell
                $score = ask(PROMPT=>"($score)",DEFAULT=>$score);
            }
            if ($ok) {
              if ($score eq "b") {$score = ""}
              if ($score ne "x") {$grades_hash_ref->{$student}=$score} 
            }
            else {
                print "\a"; # ring the bell
                print w("invalid_input\n");
            }
          }
        }
        return "";
}

sub ask {
    my %args = (
                PROMPT=>"",
                HELP=>"",
                NULL_ALLOWED=>1,
                PASSWORD=>"",
                ARROW_KEYS=>"",
                @_,
                );
    my $prompt = $args{PROMPT};
    my $help = $args{HELP};
    my $null_allowed = $args{NULL_ALLOWED};
    my $has_default = exists($args{DEFAULT});
    my $password = $args{PASSWORD}; # inputting a password, so don't echo to screen
    my $arrow_keys = $args{ARROW_KEYS};
       # If the first key they hit as an arrow key, return the character immediately.
    my $default;
    if ($has_default) {
        $default = $args{DEFAULT};
    }
    my $l = 40;
    if (length($prompt)<$l) {
        $prompt = $prompt . " " x ($l-length($prompt));
    }
    my $done = 0;
    my $input;
    while (!$done) {
      print "$prompt:";
      if (!$password) { # The following is complicated to allow for arrow keys.
        $input = "";
        Term::ReadKey::ReadMode("cbreak");
        my $last_c = "";
        while (1) {
          my $c = Term::ReadKey::ReadKey(0);

          my $del = (ord($c)==127 || ord($c)==8);
          my $hit_return = ($c eq "\r" || $c eq "\n");

          if ($hit_return) {print "\n";last}

          if (!$del) {
            $input = $input . $c;
          }
          else {
              print chr(8) x length($input) . " " x length($input) . chr(8) x length($input);
              if ($input ne "") {  $input = substr($input,0,length($input)-1)}
              print $input;
          }

          if ($input eq $up_arrow_seq || $input eq $down_arrow_seq) {
            print "\n";
            last
          }

          my $printable = ($input ne $up_arrow_seq && $input ne $down_arrow_seq && !$del
                           && $c ne chr(91) && $last_c ne chr(91) 
                           && (ord($c)>=32 || $hit_return));
          $last_c = $c;
          if ($printable) {print $c}

          #print "\n";
          #if (length($input)>0) {print "-".ord(substr($input,0,1))."-"}
          #if (length($input)>1) {print ord(substr($input,1,1))."-"}
          #print "\n";

       }
       Term::ReadKey::ReadMode("normal");
      }
      else {
          Term::ReadKey::ReadMode('noecho');
          $input = Term::ReadKey::ReadLine(0);
          Term::ReadKey::ReadMode('normal');
          print "\n";
      }
      chomp $input;
      if ($input eq "?") {
          if ($help ne "") {
              chomp $help;
              print $help . "\n";
          }
          else {
              print "Sorry, no help available.\n";
          }
      }
      else {
          if (!($input eq "" && !$null_allowed)) {$done = 1;}
      }
      if ($input eq "" && !$null_allowed) {print "\a"}
    }
    if ($input eq "" && $has_default) {$input=$default}
    return $input;
}

sub progress_bar {
    my $progress = shift; # floating point number between 0 and 1
    my $chars = 40;
    my $done = $chars*$progress;
    my $undone = $chars-$done;
    my $save_autoflush_state = $|;
    $| = 1;
    print "=" x $done . "-" x $undone . "\r";
    $| = $save_autoflush_state;
}

1;
