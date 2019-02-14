#----------------------------------------------------------------
# Copyright (c) 2002 Benjamin Crowell, all rights reserved.
#
# This software is available under version 2 of the GPL license.
# The software is copyrighted, and you must agree to the
# license in order to have permission to copy it. The full
# text of the license is given in the file titled Copying.
#
#----------------------------------------------------------------

# This package encapsulates a bunch of calendar-related stuff
# used in OpenGrade. By using this wrapper, we:
#  - avoid problems with Perl 6 versus Perl 5 compatibility
#  - make it easier to change to some other package besides Date::Calc
#  - avoid conversions to and from string formats
# When these routines accept dates as arguments, they expect them
# as strings of the form y-m-d, where all three fields are numeric.
# They generally return strings in this format as well.


use strict;
use Date::Calc;

package DateOG;

# This is a greater-than-or-equal thing, i.e. today is already considered past.
sub is_past {
    my $when = shift;
    #print "-=-= is_past, when=$when\n";
    return are_in_chronological_order($when,current_date_human());
}

sub how_many_days_ago {
    my $when = shift;
    return Date::Calc::Delta_Days(split("-",$when),split("-",current_date_human()));
}

sub day_of_week_number {
    my $when = shift;
    return (Date::Calc::Delta_Days(split("-","2004-11-07"),split("-",$when)))%7; # 2004-11-07 is a Sunday
}

sub day_of_week_letter_to_number {
  my $letter = shift;
  return {'u'=>0,'m'=>1,'t'=>2,'w'=>3,'r'=>4,'f'=>5,'s'=>6}->{lc($letter)};
}

sub day_before {
  my $when = shift;
  my @when = split '-',$when;
  @when = Date::Calc::Add_Delta_Days(@when,-1);
  return sprintf "%04d-%02d-%02d", @when;
}

sub day_after {
  my $when = shift;
  my @when = split '-',$when;
  @when = Date::Calc::Add_Delta_Days(@when,1);
  return sprintf "%04d-%02d-%02d", @when;
}


sub day_of_week_number_to_letter {
  my $number = shift;
  return ['U','M','T','W','R','F','S']->[$number];
}

sub are_in_chronological_order {
    my $d1 = shift;
    my $d2 = shift;
    my $d = Date::Calc::Delta_Days(split("-",$d1),split("-",$d2));
    return $d>=0;
}

sub order {
    my $d1 = shift;
    my $d2 = shift;
    #print "d1=$d1, d2=$d2\n";
    my $d = Date::Calc::Delta_Days(split("-",$d1),split("-",$d2));
    if ($d>0) {return -1}
    if ($d<0) {return 1}
    return 0;
}

sub disambiguate_year {
    my $when = shift; # y-m-d or m-d
    my $term = shift; # y-m or y-m-d (date the term began)
    if ($when =~ m/\d+\-\d+\-\d+/) {return $when} # unambiguous
    if ($term eq '') {return current_date("year")."-".$when}
    if ($term =~ m/\d+\-\d+/) {$term = $term . "-1"}
    my $last_year = current_date("year")-1;
    if (are_in_chronological_order($term,$last_year."-".$when)) {return $last_year."-".$when}
    return current_date("year")."-".$when;
}

# Automatically adds one to month, so Jan=1, and, if year is less than
# 1900, adds 1900 to it. This should ensure that it works in both Perl 5
# and Perl 6.
sub current_date {
    my $what = shift; #=day, month, year, ...
    my @tm = localtime;
    if ($what eq "day") {return $tm[3]}
    if ($what eq "year") {my $y = $tm[5]; if ($y<1900) {$y=$y+1900} return $y}
    if ($what eq "month") {return ($tm[4])+1}
    if ($what eq "hour") {return $tm[2]}
    if ($what eq "minutes") {return $tm[1]}
    if ($what eq "seconds") {return $tm[0]}
}

# Optimized for readability on the screen.
sub current_date_human() {
    return current_date("year")."-".current_date("month")."-".current_date("day");
}

# Optimized for readability on the screen.
sub current_date_sortable_with_hm() {
    return sprintf "%04d-%02d-%02d %02d:%02d", current_date("year"), current_date("month") ,
    current_date("day"),current_date("hour"),current_date("minutes");
}


# This form can be sorted as a string.
sub current_date_sortable() {
    return sprintf "%04d-%02d-%02d", current_date("year"), current_date("month") ,
    current_date("day");
}

# This form can be sorted as a string.
sub current_date_for_message_key() {
    return sprintf "%04d-%02d-%02d-%02d%02d%02d", current_date("year"), current_date("month") ,
    current_date("day"),current_date("hour"),current_date("minutes"),current_date("seconds");
}

sub is_legal {
  my $date = shift;
  my $term = shift;
  return 0 if $date eq '';
  my ($y,$m,$d) = split("-",disambiguate_year($date,$term));
  return ($m>=1 && $m<=12 && $d>=1 && $d<=Date::Calc::Days_in_Month($y,$m));
}

1;
