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

package Crunch;

# If the second argument is the name of a category,
# calculate the class's statistics in a category and its assignments.
# Result is returned as a ref to a hash like {"."=>...,"1"=>...,...},
# where "." is the whole category, and "1",... are assignments.
# If the second argument is omitted or is "all", we calculate statistics for
# students' overall scores, giving a hash like {"."=>...,"exams"=>...,...},
# where "." is overall.
# Each set of statistics is a comma-delimited list
# that looks like "mean:...","sd:...",... 
# The results are returned as raw scores, not percentages.
#
# Right now, I'm only implementing "all": <<<<<-----------
#
sub class_stats {
    my $gb = shift;
    my $cat = "all";
    if (@_) {$cat = shift}
    my %data = ();
    my @my_keys = ();
    my @student_keys = $gb->student_keys();
    foreach my $student (@student_keys) {
      my $totals = totals($gb,$student,$cat);
      if ($#my_keys == -1) {@my_keys = keys(%$totals)}
      foreach my $k(@my_keys) {
        my $frac = $totals->{$k};
        my ($x,$y) = split("/",$frac);
        if (!exists($data{$k})) {
                $data{$k} = [$x];
        }
        else {
          my $r = $data{$k};
          push @$r,$x;
        }
      }
    }
    my %result = ();
    foreach my $k(@my_keys) {
      my ($n,$mean,$sd) = stats($data{$k});
      $result{$k} = "\"n:$n\",\"mean:$mean\",\"sd:$sd\"";
    }
    return \%result;
}


sub stats {
    my $xr = shift; # ref to array
    my @x = @$xr;
    my @moments = (0,0,0); # for calculating N, mean and variance
    foreach my $x(@x) {
        $moments[0] = $moments[0]+1;
        $moments[1] = $moments[1]+$x;
        $moments[2] = $moments[2]+$x*$x;
    }
    my $n = $moments[0];
    my $mean = $moments[1]/$n;
    my $sd = sqrt($moments[2]/$n-$mean*$mean);
    my @m = ($n,$mean,$sd);
    return @m;
}

# Returns a hash like {all=>"1000",hw=>...} giving the number
# of points possible in each category. The optional $c argument,
# if not set to "all", results in only that category being calculated.
sub possible {
    my $gb = shift;
    my $c = "all";
    if (@_) {$c = shift}
    my $t = totals($gb,"",$c);
    while (my ($c,$v) = each (%$t)) {
        $v =~ s|^\d*/||;
        $t->{$c} = $v;
    }
    return $t;
}

# Find a particular student's point totals in each category.
# Returns a ref to a hash like {all=>"370/1000",hw=>...}
# The category argument, if present and not "all", gives the name of a category,
# and we do calculations only for that category.
# For efficiency, can supply an extra argument on the end, from
# array_of_assignments_in_category.
# The student string can be blank, in which case we give the
# total possible in each category, but the point totals are zero.
#   totals(gb,student)
#   totals(gb,student,cat)
#   totals(gb,student,cat,assignments_list) ... more efficient
#   totals(gb,student,cat,assignments_list,mp) ... more efficient
#   totals(gb,student,'all')
#   totals(gb,student,'all',mp)
# If supplied, the marking period mp should be the name of the marking period.
sub totals {
    my $gb = shift;
    my $student = shift;
    my @c;
    my $assignments_in_this_cat = undef;
    my $use_wts = $gb->weights_enabled();
    my $mp;
    if (@_ && $_[0] ne "all") { # cat
      @c = (shift,);
      if (@_) { # They supplied assignments list for efficiency.
        $assignments_in_this_cat = shift;
        if (@_) {$mp = shift}
      }
      else {
        $assignments_in_this_cat = $gb->array_of_assignments_in_category($c[0]);
      }
    }
    else { # no cat
      @c = split(",",$gb->category_list());
      shift; # get rid of 'all'
      if (@_) {$mp = shift}
    }
    my %results = ();
    my $total = 0;
    my $possible = 0;
    foreach my $c(@c) {
      my $r;
      $r = total_one_cat($gb,$student,$c,$assignments_in_this_cat,0,$mp);
      $results{$c} = $r;
      my ($t,$p) = split("/",$r);
      if (!$use_wts) {
        $total = $total + $t;
        $possible = $possible + $p;
      }
      else {
        # If we're using weighted grading, and no points are possible
        # in this category, then it wouldn't make sense to try to count
        # it, and we'd get a division by zero as well.
        if ($p!=0) { 
          my $w = $gb->category_weight($c)/$p;
          $total = $total + $t*$w;
          $possible = $possible + $p*$w;
        }
      }
          
    }
    $results{"all"} = "$total/$possible";
    return \%results;
}

# Like totals(), but the category argument is mandatory, and the
# result is a single string, not a hash ref.
# If there are no assignments in the category at all except for
# extra-credit ones, then we return a string like "xxx/0", where
# xxx is the extra credit points.
# The same occurs if the number of assignments in the category is less than or
# equal to the number of assignments we're supposed to drop.
# The student key can be a null string, in which case we calculate possible
# points, but give results as 0/possible; rather than using this
# directly, we'd normally call the possible() subroutine.
# Note that it's not necessary to check whether the category is ignored, because
# if it is, that's just a default setting that's inherited by the assignments.
# For efficiency, can supply an extra argument on the end, from
# array_of_assignments_in_category. This can be undef.
# Can also have marking period on end.
# summary:
#    total_one_cat(who,cat)
#    total_one_cat(who,cat,assignments_for_efficiency)
#    total_one_cat(who,cat,assignments_for_efficiency,override_ignored)
#    total_one_cat(who,cat,assignments_for_efficiency,override_ignored,mp)
# Considerations for memoization:
#   The memoized results have to be stored in the gb object, not here, because we might have more than one gb open.
#   Correctness of memoization depends on how careful the UI code is about calling mark_modified_now() at appropriate times.
#   The number of possible memoization keys has to be fairly small, or else we'll have what amounts to a memory leak.
sub total_one_cat {        
    my $gb = shift;
    my $student = shift;
    my $cat = shift;
    my $aa;
    my $gave_assignments;
    if (@_) {
      $gave_assignments = shift;
    }
    if ($gave_assignments) {$aa=$gave_assignments} else { $aa = $gb->array_of_assignments_in_category($cat)}
    my $override_ignored = 0;
    if (@_) {
      $override_ignored = shift;
    }
    my $mp;
    if (@_) {
      $mp = shift;
    }
    my $enable_memoization = 1;
    my $memoization_key = 'crunch_total_one_cat'.join(',',$student,$cat,$override_ignored,$mp);
    if (exists $gb->{MEMOIZE}->{$memoization_key}) {
      my $r = $gb->{MEMOIZE}->{$memoization_key};
      my ($result,$when) = ($r->[0],$r->[1]);
      my $last_mod = $gb->when_last_modified(); # may be undef if never modified
      if (!defined $last_mod || $r->[1] > $last_mod) { # The last calculation was at least one second later than the last modification.
        if ($enable_memoization) {
          return $result;
        }
      }
    }
    my $result = total_one_cat_without_memoization($gb,$student,$cat,$override_ignored,$mp,$aa);
    $gb->{MEMOIZE}->{$memoization_key} = [$result,time];
    return $result;
}

sub total_one_cat_without_memoization {
    my ($gb,$student,$cat,$override_ignored,$mp,$aa) = @_;
    my $extra_credit = 0;
    my @grades = ();
    my @maxes = ();
    my @a = @$aa;
    my $cat_properties = $gb->category_properties($cat);
    my $normalize_grades = ($cat_properties->{"normalize"} eq "true");
    foreach my $ass(@a) {
      my $a = "$cat.$ass";
      my $ass_properties = $gb->assignment_properties($a);
      my $ignore = ($ass_properties->{"ignore"} eq "true") && !$override_ignored;
      if (!$ignore) {
        my $due_date = $ass_properties->{"due"};
        my $due = ($due_date eq "") || (DateOG::is_past(DateOG::disambiguate_year($due_date,$gb->term())));
        if ($due && (!$mp || $ass_properties->{'mp'} eq $mp)) { 
          my $grade = 0;
          if ($student) {$grade = $gb->get_current_grade_as_number($student,$cat,$ass)};
          my $max = $ass_properties->{"max"};
          if ($max==0) {
                  $extra_credit = $extra_credit + $grade;
                } # end if extra credit
                else {
                  if ($normalize_grades){
                  	$grade = $grade*100/$max;
                  	$max = 100;
                  }
                  push @grades,$grade;
            push @maxes,$max;
          } # end if not extra credit
        } # end if it's due
      } # end if it's not to be ignored
   } # end loop over assignments

   my $n_drop = $gb->category_property($cat,"drop");
   if ($#grades+1<$n_drop) {return "$extra_credit/0"}

   for(my $i=0; $i<=$#grades; $i++) {
     if ($grades[$i]>$maxes[$i]) {
             my $excess = $grades[$i]-$maxes[$i];
             $extra_credit = $extra_credit + $excess;
             $grades[$i] = $grades[$i] - $excess;
     }
   }

   my $it = compute_total_with_dropped_assignments(\@grades,\@maxes,$n_drop);
   if ($it ne "") {
     my ($x,$y) = split("/",$it);
     $x = $x + $extra_credit;
     return "$x/$y";
   }
   else {
     return "0/0";
   }
}

# When dropping low scores, we choose them so as to maximize the
# student's points, not the student's average. The maximum number
# of possible points is calculated by leaving out the assignments
# that have the lowest number of points possible. The result is
# that the number of possible points is the same for all students.
# This might give surprising results in cases where there are some
# assignments worth a lot more points than others, or where students
# have more than the maximum number of points on an assignment.
# A consequence of this definition is that it doesn't matter which
# elements of @maxes correspond to which elements of @grades.
# If the number of assignments to drop is greater the the number
# of assignments there are, we return a null string.
# Note that extra-credit assignments should not be passed to this
# routine, and assignments with scores over the maximum should have
# already been chopped down, with the excess credited to extra credit.
# Returns a string of the form "x/y".
sub compute_total_with_dropped_assignments {
    my $grades_ref = shift;
    my $maxes_ref = shift;
    my $n_drop = shift;

    my @grades = @$grades_ref;
    if ($n_drop>$#grades+1) {return ""}
    my @maxes = @$maxes_ref;

    # In theory, the following is probably not the optimal algorithm,
    # since it takes k log k time, where k is the number of assignments.
    # With a custom-tailored algorithm, it should be possible to do it in
    # k time. But I suspect that for reasonable values of k, the following
    # is actually /more/ efficient than anything one could write in Perl.

    if ($n_drop>0) { # If possible, skip the sorting for greater efficiency.
      @grades = sort {$a <=> $b} @grades; # The <=> stuff makes it numerical, not string.
      @maxes = sort {$a <=> $b} @maxes; # The <=> stuff makes it numerical, not string.
    }
    my $g = 0;
    my $m = 0;
    #print "  n_drop=$n_drop\n";
    for (my $i=$n_drop; $i<=$#grades; $i++) {
        $g = $g + $grades[$i];
        $m = $m + $maxes[$i];
    }

    #print "  $g/$m\n";
    return "$g/$m";
}

1;
