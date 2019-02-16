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

use GradeBook;
use Crunch;
use Text;
use NetOG;
use POSIX;
use POSIX ":sys_wait_h";

package Report;

sub stats {
    my %args = (
                GB=>"",
                FORMAT=>"plain",
                @_,
                );
    my $gb = $args{GB};
    my $format = $args{FORMAT};
    my $t = Text->new($format);

    my $n_enrolled = $gb->student_keys();
    $t->put(TEXT=>"students enrolled: $n_enrolled\n");

    my $h = Crunch::class_stats($gb,"all");
    my $possible = Crunch::possible($gb,"all");
    my %h = %$h;
    foreach my $c(keys(%h)) {
      my $stats = $h{$c};
      my ($n,$mean,$sd) = (
        GradeBook::get_property($stats,"n"),
        GradeBook::get_property($stats,"mean"),
        GradeBook::get_property($stats,"sd"),
      );
      #print "$c possible = ".$possible->{$c}."\n";
      my $p = $possible->{$c};
      my $stuff = "";
      if ($p > 0.) {
        $stuff = (sprintf "n=%3d   mean=%7.2f%s   sd=%7.2f%s",
                        $n,$mean/$p*100.0,"%",$sd/$p*100.0,"%"
                  );
      }
      else {
        $stuff = "";
      }
      $t->put(TEXT=>(sprintf "%10s   %s\n",$c,$stuff));
    }

    return $t;
}

sub statistics_ass {
    my $gb = shift;
    my $format = shift;
    my $cat = shift;
    my $ass = shift;
    my @student_keys = $gb->student_keys();
    my $t = Text->new($format);
    my @scores = ();
    my $title;
    $title=$gb->assignment_name($cat,$ass);
    foreach my $student (@student_keys) {
      my $score;
      $score = $gb->get_current_grade($student,$cat,$ass);
      push @scores,$score;
    }
    my ($n,$mean,$sd) = Crunch::stats(\@scores);
    my $p = $gb->assignment_property("$cat.$ass",'max');
    my $sd_of_mean_percent = undef;
    if ($n>0 && $p>0) {$sd_of_mean_percent = $sd*100.0/(sqrt($n)*$p)}
    $t->put(P=>1,TEXT=>$title);
    my $stuff = '';
    if ($p > 0.) {
      $stuff = (sprintf "   n = %5d\nmean = %7.1f = %7.2f%s +- %7.2f%s\n  sd = %7.1f = %7.2f%s",
                        $n,$mean,$mean/$p*100.0,"%",$sd_of_mean_percent,"%",$sd,$sd/$p*100.0,"%"
                  );
	  }
    $t->put(BR=>1,TEXT=>$stuff);
    return $t;
}

# use:
#     sort(gb,format,mp)
#     sort(gb,format,mp,cat)
#     sort(gb,format,mp,cat,ass)
# trailing * on format means sort by name
# For a gradebook without marking periods, mp is ignored.
# For a gb with mps, mp can be specified, or set to undef for overall grade.
sub sort {
    my $gb = shift;
    my $format = shift;
    my $mp = shift;
    my $cat = '';
    if (@_) {$cat=shift}
    my $ass = '';
    if (@_) {$ass=shift}
    my $sort_by = 'score';
    if ($format=~m/\*$/) {$sort_by='name'; $format=~s/\*$//} # kludge: trailing * means sort by name
    my @student_keys = $gb->student_keys();
    my $t = Text->new($format);
    my @stuff = ();
    my $title;
    if ($cat eq '') {$title=''}
    if ($cat ne '' && $ass eq '') {$title=$gb->category_name_plural($cat)}
    if ($ass ne '') {$title=$gb->assignment_name($cat,$ass)}
    foreach my $student (@student_keys) {
      my $score;
      if ($cat eq '') {$score = Crunch::totals($gb,$student,'all',$mp)->{'all'}; $title=''}
      if ($cat ne '' && $ass eq '') {$score = Crunch::total_one_cat($gb,$student,$cat,$gb->array_of_assignments_in_category($cat),1,$mp)}
      if ($ass ne '') {$score = $gb->get_current_grade($student,$cat,$ass)."/".$gb->assignment_property("$cat.$ass","max")}
      $score =~ m@^([^/]*)@.*@;
      my $points = $1;
      push @stuff,[$student,$points,$score];
    }
    if ($sort_by eq 'score') {
      @stuff = sort {$b->[1] <=> $a->[1]} @stuff;
    }
    else { # sort by name
      @stuff = sort {$gb->compare_names($a->[0],$b->[0])} @stuff;
    }
    $t->put(P=>1,TEXT=>$title);
    foreach my $thing (@stuff) {
      my $student = $thing->[0];
      my $score = $thing->[2];
      my ($first,$last) = $gb->name($student);
      my $display_name = "$first $last";
      if (length($display_name)>20) {$display_name = substr($display_name,0,17).'...'}
      my $display = fraction_to_display($gb,$score);
      $display='--' if $score=~m@^/@;
      $t->put(BR=>1,TEXT=>(sprintf "%-20s %10s   (%s)" , $display_name, $display,format_fraction($score)));
    }
    return $t;
}

# Returns a Text object
sub class_totals {
    my $gb = shift;
    my $format = shift;
    my @student_keys = $gb->student_keys();
    my $t = Text->new($format);
    foreach my $student (@student_keys) {
        my ($first,$last) = $gb->name($student);
        my $full_name = $first." ".$last;
        my $totals = Crunch::totals($gb,$student);
        my $all = $totals->{"all"};
        $t->put(TEXT=>(sprintf "%20s %s\n",$full_name,
                       fraction_to_display($gb,$all)." ($all)"));
    }
    $t->put(BR=>1,TEXT=>(sprintf "%20s %d students","",1+$#student_keys));
    return $t;
}

# Returns a Text object
sub class_totals_one_mp {
    my $gb = shift;
    my $format = shift;
    my $mp = shift;
    my @student_keys = $gb->student_keys();
    my $t = Text->new($format);
    foreach my $student (@student_keys) {
        my ($first,$last) = $gb->name($student);
        my $full_name = $first." ".$last;
        my $totals = Crunch::totals($gb,$student,'all',$mp);
        my $all = $totals->{"all"};
        $t->put(TEXT=>(sprintf "%20s %s\n",$full_name,
                       fraction_to_display($gb,$all)." ($all)"));
    }
    $t->put(BR=>1,TEXT=>(sprintf "%20s %d students","",1+$#student_keys));
    return $t;
}


sub make_student_report {
  my $gb = shift;
  my $who = shift;
  my ($first,$last) = $gb->name($who);
  my $t = student(GB=>$gb,STUDENT=>$who,FORMAT=>"html");
  return "<html><head><title>Grades for $first $last</title></head><body>\n"
               . $t->text()
               . "</body></html>\n";
}

=head3 upload_grades()

  GB=>'',
  PWD=>'',
  PROGRESS_BAR_CALLBACK=>sub{},
  FINAL_CALLBACK=>sub{},
  PROTOCOL=>'og',

This is meant to be something we can call from either the GUI or the text-based
interface, without duplicating any code. No other protocols are supported besides the default one.

=cut

sub upload_grades {
      my %args = (
        GB=>'',
        PWD=>'',
        PROGRESS_BAR_CALLBACK=>sub{},
        FINAL_CALLBACK=>sub{},
        PROTOCOL=>'og',
        @_
      );
      my $gb = $args{GB};
      my $password = $args{PWD};
      my $progress_bar = $args{PROGRESS_BAR_CALLBACK};
      my $protocol = $args{PROTOCOL};
      my $dir = $gb->dir(); # e.g. bcrowell/s2002/205 ; relative to cgi-bin
      my $final_callback = $args{FINAL_CALLBACK};
      my $result = '';
      my $backup = 1;
      if ($protocol ne 'og') {
        return 'og is the only supported protocol';
      }
      my $request = NetOG->new();
      my $prefs = $gb->preferences();
      my $server_domain = $prefs->get('server_domain');
      my $server_user = $prefs->get('server_user');
      my $server_account = $prefs->get('server_account');
      my $server_key = $prefs->get('server_key');
      my $server_class = $gb->dir();
      my $ndone = 0;
      my @student_keys = $gb->student_keys();
      my $err = '';
      my %reports = ();
      foreach my $student(@student_keys) {
        $reports{$student} = make_student_report($gb,$student);
      }
      # The following code for uploading reports is designed to be robust when used over a slow
      # or unreliable connection. It used to be just a simple loop with a be_client() call inside,
      # but sometimes the server would fail to respond for an indefinite period, and it would hang.
      # This new version forks a child process to do each upload, and if the child doesn't exit
      # within a certain amount of time, it waits a little longer out of politeness to the
      # server (which may be overloaded) and then goes on to the next report. After going down the
      # roster, it then repeats the process for any students whose reports it failed to upload the
      # first time. With each iteration, it sets longer time limits. If this doesn't succeed after
      # a certain number of iterations, it gives up and returns an error. The tunable parameters
      # are the times, in units of seconds, given in $max_tries, $politeness_delay, and $tmax.
      my $n_tries = 0;
      my $max_tries = 5; # if changing this, change the arrays used to set tmax and politeness_delay below
      my $debug = 0;
      while (keys %reports) {
  			++$n_tries;
	  		if ($n_tries>=2) {print "retrying\n" if $debug}
        if ($n_tries>=$max_tries) {$err= "giving up after $n_tries tries\n"; last}
        my $politeness_delay = [1,5,10,20,30]->[$n_tries-1]; # seconds
        my $tmax = [10,15,20,30,40]->[$n_tries-1]; # seconds
        print "politeness_delay=$politeness_delay\n" if $debug;
		  	my @to_do = sort keys %reports;
        foreach my $student(@to_do) {
          my $kid = fork;
          if ($kid==0) { # I'm the child
            $request->be_client(GB=>$gb,
              HOST=>$server_domain,SERVER_KEY=>$server_key,
              PARS=>{'account'=>$server_account,'user'=>$server_user,'class'=>$server_class,
                     'what'=>'upload_grade_report','who'=>$student,'report'=>$reports{$student}}
            );
            POSIX::_exit(0); # no cleanup, closing files, etc.
				  }
          else {
            my $t = 0;
            my $dt = 1;
            print "$student\n" if $debug;
            for (;;) {
              sleep $dt;
              my $dead = ($kid==waitpid($kid,&POSIX::WNOHANG));
              if ($dead) {
                delete($reports{$student});
                ++$ndone;
                last;
              }
              $t += $dt;
              if ($t>$tmax) {
                print "Error uploading grade report for $student, timed out after $tmax sec.\n" if $debug;
                kill 9,$kid;
                sleep $politeness_delay; # be polite to server, maybe it's overloaded
                last;
              }
            }
          }
          $result = $request->{RESPONSE_DATA};
          if ($result=~m/^error/) {$err=$result; last}
          if (ref $progress_bar) {&$progress_bar($ndone/($#student_keys+1))}
        } # end loop over students
      }
      &$final_callback($err);
      return $err;
}

sub format_percent_letter_and_fraction {
        my $gb = shift;
        my $frac = shift;
        my $relative = fraction_to_display($gb,$frac);
        my $absolute = format_fraction($frac);
        if ($relative ne '') {
          return "$relative ($absolute)";
        }
        else {
          return $absolute;
        }
}

sub format_fraction {
        my $frac = shift;
        if ($frac eq '' || $frac eq '--') {return $frac}
        my ($total,$possible) = split("/",$frac);
        if ($possible<10 && (int($total)<$total || int($possible)<$possible)) {
          # unusual case, very small numbers like 0.2/0.3
          # Don't change formatting or do any rounding.
        }
        else {
          # normal case
          $possible = sprintf "%d",int($possible);
          $total = sprintf "%".length(int($possible))."d",int($total);
        }
        return sprintf "$total/$possible";
}

sub fraction_to_display {
        my $gb = shift;
        my $frac = shift;
        my ($percentage,$letter) = fraction_to_pct_and_letter($gb,$frac);
        if ($percentage eq "" && $letter eq "") {return ""}
        if ($letter eq "") {return sprintf "%4.1f",$percentage}
        if (length $letter<2) {$letter = "$letter "}
        return sprintf "%4.1f%s %s",$percentage,'%',$letter;
}


sub fraction_to_pct_and_letter {
        my $gb = shift;
        my $frac = shift;
        if ($frac eq '' || $frac eq '--') {return $frac}
        my ($total,$possible) = split("/",$frac);
        my $percentage = 0.0;
        my $letter = "";
        if ($possible>0) {
            $percentage = 100.*$total/$possible;
            $letter = $gb->percentage_to_letter_grade($percentage);
        }
        else {
            $percentage = "";
            $letter = "";
        }
        return ($percentage,$letter);
}

sub table {
    my %args = (
                GB=>"",
                FORMAT=>"plain",
                @_,
               );
    my $gb = $args{GB};
    my $format = $args{FORMAT};
    my @student_keys = $gb->student_keys();
    my $t = Text->new($format);

    my @a = split(",",$gb->assignment_list()); # list of cat.ass
    my @c = (); # cat only
    my @n = (); # ass only
    foreach my $a(@a) {
      my ($cat,$ass) = (GradeBook::first_part_of_label($a),
                              GradeBook::second_part_of_label($a));
      push @c,$cat;
      push @n,$ass;
    }
    my $n_assignments = @a;
    my $assignments_per_page = 12;
    my $width = 5;
    my $name_width = 15;
    my $full_width = $name_width+$assignments_per_page*$width;
    my $n_pages = int($n_assignments/$assignments_per_page);
    if ($n_pages * $assignments_per_page < $n_assignments) {$n_pages++}

    # Helper routine to trim or pad a string to a desired width:
    my $trim = sub {
      my $string = shift;
      my $width = shift;
      my $result = sprintf "%${width}s",$string;
      if (length $result>$width) {$result = substr($result,0,$width)}
      return $result;
    };

    for (my $page=0; $page<$n_pages; $page++) {
      my $offset = $page*$assignments_per_page;
      my $n_cols = $assignments_per_page;
      if ($offset+$n_cols>$n_assignments) {$n_cols = $n_assignments-$offset}

      $t->put(TEXT=>(' ' x $name_width));
      for (my $col=0; $col<$n_cols; $col++) {
        $t->put(TEXT=>&$trim($c[$offset+$col]." ",$width));
      }
      $t->put(BR=>1);

      $t->put(TEXT=>(' ' x $name_width));
      for (my $col=0; $col<$n_cols; $col++) {
        $t->put(TEXT=>&$trim($n[$offset+$col]." ",$width));
      }
      $t->put(BR=>1);

      $t->put(TEXT=>(' ' x $name_width));
      for (my $col=0; $col<$n_cols; $col++) {
        $t->put(TEXT=>&$trim("(".$gb->assignment_property($a[$offset+$col],"max").")",$width));
      }
      $t->put(BR=>1);

      foreach my $student (@student_keys) {
        my ($first,$last) = $gb->name($student);
        my $full_name = "$last, $first";
        if (length $full_name>$name_width-1) {$full_name=substr($full_name,0,$name_width-1)}
        $t->put(TEXT=>&$trim($full_name." ",$name_width));
        for (my $col=0; $col<$n_cols; $col++) {
          my $j = $offset+$col;
          my $grade = $gb->get_current_grade($student,$c[$j],$n[$j]);
          if ($grade eq '') {$grade='--'}
          $t->put(TEXT=>(sprintf "%${width}s",$grade." "));
        }
        $t->put(BR=>1);
      }

      $t->put(P=>1);

    }


    return ($t,$full_width);
}

sub student {
  my %args = (
                GB=>"",
                STUDENT=>"",
                FORMAT=>"plain",
                @_,
               );
  my $gb = $args{GB};
  my $format = $args{FORMAT};
  my $student = $args{STUDENT};
  my ($first,$last) = $gb->name($student);
  my $full_name = $first." ".$last;
  my $t = Text->new($format);
  $t->put(P=>1,TEXT=>"$first $last, ".$gb->title());
  my @c = split(",",$gb->category_list());

  my @mps = (undef,);
  if ($gb->marking_periods()) {@mps =  $gb->marking_periods_in_order()}
  foreach my $mp (@mps) {
    my $period_total = Crunch::totals($gb,$student,'all',$mp);
    if ($mp) {  $t->put(BR=>1,TEXT=>"================ $mp =============="); }
    my $all = $period_total->{"all"};
    $t->put(P=>1,TEXT=>"overall grade: ".format_percent_letter_and_fraction($gb,$all));
    foreach my $c(@c) {
      my $totals = Crunch::totals($gb,$student,$c,$gb->array_of_assignments_in_category($c),$mp);
      my $single_assignment_category = $gb->category_property_boolean($c,'single');
      my $category_total = format_percent_letter_and_fraction($gb,$totals->{$c});
      my $show_category_total;
      my @a = split(",",$gb->assignment_list()); # for all categories
      #my @a = $gb->array_of_assignments_in_category($c);
      if (   !empty_array_ref($gb->array_of_assignments_in_category($c)) # There really are one or more assignments in
                                                                         # it, not zero.
          && $gb->assignment_properties($c.'.'.(($gb->array_of_assignments_in_category($c))->[0]))->{'ignore'} eq 'true'
         ) {

        # This is a category that's ignored for purposes of computing students'
        # grades. This requires special handling. Normally for an ignored
        # category, we'd just put 0/0 for the category total, and the report
        # would show the individual (ignored) grades on the assignments below
        # the category heading. But we have to do something different for the
        # case of a single-assignment category, because then it would always
        # show 0/0, and you could never tell from the report what the (ignored)
        # score was. We do this in categories that aren't single-assignment as
        # well, just to avoid confusion. 

        if ($single_assignment_category) {
          my $a = (($gb->array_of_assignments_in_category($c))->[0]);
          my $grade = $gb->get_current_grade($student,$c,$a);
          if ($grade eq '') {$grade='no credit recorded'}
          $show_category_total = "($grade) (not counted in computing grades)" if (!$mp || $gb->assignment_properties("$c.$a")->{'mp'} eq $mp);
          # Since this is a single-assignment category, this is the only way they'll see their (ignored) points.
        }
        else {
          my $ignored_cat_total = Crunch::total_one_cat($gb,$student,$c,$gb->array_of_assignments_in_category($c),1);
          $show_category_total = "($ignored_cat_total, not counted in computing grades)"; 
          # $category_total is just 0/0, so no point in showing it -- it just confuses them
        }
      } # end if ignored category
      else { # not an ignored category
        $show_category_total = $category_total; # if not during this mp, this will be 0/0
        # Check the special case where it's a single-assignment category, and the assignment isn't due yet:
        my $a = $gb->array_of_assignments_in_category($c);
        if ($single_assignment_category && @a) {
          my $ass =  $a->[0];
          my $due_date = $gb->assignment_properties("$c.$ass")->{"due"};
          my $due = ($due_date eq "") || (DateOG::is_past(DateOG::disambiguate_year($due_date,$gb->term())));
          if (!$due && (!$mp ||  $gb->assignment_properties("$c.$ass")->{'mp'} eq $mp)) {
            my $g = report_one_grade($c,$ass,$gb,$student,0);
            $show_category_total = "$g (not counted because it isn't due until $due_date)";
          }          
        }
      }
      $t->put(BR=>1,TEXT=>$gb->category_name_plural($c).": ".$show_category_total);
      my $sing = $gb->category_name_singular($c);
      if (!$single_assignment_category) {
        foreach my $a(@a) {
          my ($cat,$ass) = (GradeBook::first_part_of_label($a),
                            GradeBook::second_part_of_label($a));
          if ($cat eq $c) {report_one_assignment($t,$cat,$ass,$gb,$student,$mp)}
        } # end foreach assignment
      } # end if not single-assignment cat
    } # end loop over cats
  } # end loop over marking periods
  return $t;
}

sub report_one_assignment {
            my ($t,$cat,$ass,$gb,$student,$mp) = @_;
            my $a = "$cat.$ass";
            my $ass_properties = $gb->assignment_properties($a);
            my $due_date = $ass_properties->{"due"};
            my $ignore = ($ass_properties->{"ignore"} eq "true");
            my $fraction = report_one_grade($cat,$ass,$gb,$student,$ignore);
            my $due = ($due_date eq "") || (DateOG::is_past(DateOG::disambiguate_year($due_date,$gb->term())));
            my $ass_name = $gb->assignment_name($cat,$ass);
            my $explain_whether_due = '';
            $explain_whether_due=" (not counted for computing grades, because it isn't due until $due_date)" if !$due; # $due_date guaranteed not null, because then $due is true
            my $result = '';
            $result = "$ass_name: $fraction$explain_whether_due" if (!$mp || $ass_properties->{'mp'} eq $mp);
            $t->put(TEXT=>$result,INDENTATION=>1,BR=>1) if ref $t;
            return $result;
}

sub report_one_grade {
            my ($cat,$ass,$gb,$student,$ignore) = @_;
            my $type = $gb->category_property2($cat,'type');
            my $grade = $gb->get_current_grade($student,$cat,$ass);
            if ($grade eq "") {$grade="--"}
            my $max = $gb->assignment_property("$cat.$ass","max");
            my $fraction = "$grade/$max";
            if ($type ne 'numerical') {$fraction = $gb->types()->{'data'}->{$type}->{'descriptions'}->{$grade}}
            $fraction = $grade if ($ignore && $max==0);
            $fraction = "$grade (extra credit)" if (!$ignore && $max==0 && $grade>=0);
            return $fraction;
}

sub dbg {
  my $mess = shift;
  print STDERR "$mess\n";
}

sub empty_array_ref {
  my $ref = shift;
  return !(@$ref);
}

sub roster_to_svg {

my $n = shift; # ref to list of names
my $title = shift;
my @names = @$n;

my $svg_head = <<'SVG';
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<svg
   xmlns:svg="http://www.w3.org/2000/svg"
   xmlns="http://www.w3.org/2000/svg"
   width="744.09448819"
   height="1052.3622047"
>
SVG
my $svg_tail = <<'SVG';
</svg>
SVG

my $count = @names;

my $svg_body = '';
my $y_offset = 125;
my $x_text = 51;
my $y_text = 56;
my $line_spacing = 22.5;

# fiddle with format for large class, try to fit everyone on one page:
my $nominal_max_count = 33; # the number that normally would fit on the page
if ($count>$nominal_max_count) {
  my $excess = $count-$nominal_max_count;
  if ($excess>15) {$excess=15}
  # reduce line spacing and scoot everything up:
  $line_spacing = $line_spacing * $nominal_max_count / ($nominal_max_count+$excess);
  $y_offset = $y_offset - 30;
}
my $shaded_rectangle_height = 3*$line_spacing;


my $y_title = $y_offset;
my $x_title = $x_text+250;
$svg_body = $svg_body . <<SVG;
    <text
       xml:space="preserve"
       style="font-size:18px;font-style:normal;font-weight:normal;fill:#000000;fill-opacity:1;stroke:none;stroke-width:1px;stroke-linecap:butt;stroke-linejoin:miter;stroke-opacity:1;font-family:Bitstream Vera Sans"
       x="50"
       y="$y_title">
    <tspan x='$x_title' y='$y_title'>$title</tspan>
    </text>
SVG
# make shaded rectangles:
for (my $i=0; $i<=@names-1; $i+=6) {
  my $y_rect = 56 + $i*$line_spacing + $y_offset;
  $svg_body = $svg_body . <<SVG;
    <rect
       style="fill:#dedede;fill-opacity:1;stroke:none;"
       width="632"
       height="$shaded_rectangle_height"
       x="49"
       y="$y_rect" />
SVG
}
# The first rectangle below is to force portrait orientation and margin when printing from evince.
# The tiny black circle is because the invisible rectangle doesn't seem to convince some printer drivers,
# so they scale the page up. The dot doesn't actually show up on the paper, because it's outside the
# printable area.
$svg_body = $svg_body . <<'SVG';
    <rect
       style="fill:#ffffff;fill-opacity:1;stroke:none;"
       width="1"
       height="880"
       x="-10"
       y="40" />
    <circle style="color:#000000" cx="762.0" cy="1000.0" r="0.1" />
    <text
       xml:space="preserve"
       style="font-size:14px;font-style:normal;font-weight:normal;fill:#000000;fill-opacity:1;stroke:none;stroke-width:1px;stroke-linecap:butt;stroke-linejoin:miter;stroke-opacity:1;font-family:Bitstream Vera Sans"
       x="51"
       y="$y_text">
SVG
for (my $i=0; $i<=@names-1; $i++) {
  my $y =  71.9 + $line_spacing *$i + $y_offset;
  $svg_body = $svg_body . "<tspan x='$x_text' y='$y'>$names[$i]</tspan>\n";
}
$svg_body = $svg_body . "</text>\n";

return $svg_head,$svg_body,$svg_tail;

}


1;
