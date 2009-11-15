#----------------------------------------------------------------
# Copyright (c) 2008 Benjamin Crowell, all rights reserved.
#
# This software is available under version 2 of the GPL license.
# The software is copyrighted, and you must agree to the
# license in order to have permission to copy it. The full
# text of the license is given in the file titled Copying.
#
#----------------------------------------------------------------

# This package is for UI-related functions that satisfy the following criteria:
#  - Purely functional (no side-effects).
#  - May read GradeBook objects, but don't modify them.
#  - Totally independent of the particular GUI library (Perl/Tk,...).
# Exceptions:
#  - may take strings out of MyWords
#  - may make generic GUI stuff, Input objects
#  - may get current date, etc.

use strict;
use Digest::SHA1;

package Fun;
use MyWords;
use DateOG;
use IPC::Open2;

# turn a string like "a=6&b=4" to a hash ref like {a=>6,b=>4}
sub html_query_to_hash {
  my $x = shift;
  my $y={};
  foreach my $a(split(/\&/,$x)) {
    if ($a=~/(.*)=(.*)/) {
      $y->{$1}=$2;
    }
  }
  return $y;
}

# turn a string like "book=6&chapter=4&problem=37" to a string like "6,4,37"
sub html_query_to_bcp {
  my $x = shift;
  my $y={};
  foreach my $a(split(/\&/,$x)) {
    if ($a=~/(book|chapter|problem)=(.*)/) {
      $y->{$1}=$2;
    }
  }
  return "$y->{book},$y->{chapter},$y->{problem}";
}

sub hash_usable_in_filename {
  my $x = shift;
  my $hash = Digest::SHA1::sha1_base64($x);
  $hash =~ m/^(....)/; # get 1st 4 chars
  $hash = $1;
  $hash =~ s@/@_@g; # Unix filenames shouldn't have slashes in them.
  $hash =~ s@\+@_@g; # Plus signs also seem to cause problems.
  return $hash;
}

sub server_send_email_construct_inputs {
    my ($default_recipient,$class_description) = @_;
    my @inputs = ();
    push @inputs,Input->new(KEY=>'to',PROMPT=>Browser::w('to'),TYPE=>'string',BLANK_ALLOWED=>0,
                DEFAULT=>$default_recipient);
    push @inputs,Input->new(KEY=>'do_email',PROMPT=>Browser::w('do_email'),
                TYPE=>'string',WIDGET_TYPE=>'radio_buttons',BLANK_ALLOWED=>0,DEFAULT=>0);
    push @inputs,Input->new(KEY=>'subject',PROMPT=>Browser::w('subject'),TYPE=>'string',BLANK_ALLOWED=>0,
                DEFAULT=>$class_description);
    push @inputs,Input->new(KEY=>'body',PROMPT=>Browser::w('body'),TYPE=>'string',BLANK_ALLOWED=>0,WIDGET_TYPE=>'text');
    return @inputs;
}

sub server_list_work_add_time_slop {
    my ($due,$time,$clock_slop) = @_;
    if ($time ne '') {
      my $clock_slop = 1;
      # add $clock_slop minutes to time in case clocks aren't quite precisely in sync:
      $time =~ m/(\d\d):(\d\d)/;
      my ($hh,$mm) = ($1,$2);
      $mm += $clock_slop;
      if ($mm>59) {
        $mm -= 60;
        $hh += 1;
      }
      if ($hh>23) {
        $due = DateOG::day_after($due);
        $hh -= 24;
      }
      $time = sprintf "%02d:%02d",$hh,$mm;
    }
    else {
      # time is blank, set to default, just before midnight
      $time = '23:59';
    }
    return ($due,$time);
}

{
    my %roman = (1=>'i',2=>'ii',3=>'iii',4=>'iv',5=>'v',6=>'vi',7=>'vii',8=>'viii',9=>'ix');
    my %arabic;
    my $made_arabic = 0;
    sub arabic_to_roman {
      my $arabic = shift;
      if (exists $roman{$arabic}) {
        return $roman{$arabic};
      }
      else {
        return $arabic;
      }
    }
    sub roman_to_arabic {
      my $roman = shift;
      if (!$made_arabic) {
        %arabic = reverse %roman; # inverts the hash, by using its equivalence to a list
        $made_arabic = 1;
      }
      if (exists $arabic{$roman}) {
        return $arabic{$roman};
      }
      else {
        return $roman;
      }
    };
}

sub server_list_work_massage_list_of_problems {
    my $list = shift;
    my @list = ();
    my @stuff = ();
    while ($list=~m/^([^\n]+)$/mg) {
      push @list,$1;
    }
    # get rid of irrelevant data, and remove duplicates:
    for (my $i=0; $i<@list; $i++) {
      $list[$i] =~ s/(class|username|correct)=[\w\d\/]+\&//g;
      $list[$i] =~ s/\&(class|username|correct)=[\w\d\/]+//g;
    }
    my %unique = ();
    foreach my $l(@list) {
      $unique{$l} = 1;
    }
    @list = keys %unique;
    # sort them:
    @list = sort {
      my $aa = $a . '&';
      my $bb = $b . '&';
      $aa =~ s/\=(\d{1,3})\&/'='.(sprintf '%04d',$1).'&'/ge;
      $bb =~ s/\=(\d{1,3})\&/'='.(sprintf '%04d',$1).'&'/ge;
      $aa cmp $bb;
    } @list;
    my @raw_and_cooked = ();
    foreach my $problem(@list) {
      push @stuff,$problem;
      my $text = $problem;
      $text =~ s/find\=/wugganugga\=/;
      $text =~ s/(\w+)\=(\w+)\&?/$1 $2   /g;
      my $arabic = $2;
      my $roman = arabic_to_roman($arabic);
      $text =~ s/wugganugga(\s+)(\d)/$1.'wugga-'.$roman/e;
      $text =~ s/^file //;
      push @raw_and_cooked,{'raw'=>$problem,'cooked'=>$text};
    }
    my $n = 0;
    foreach my $rc(@raw_and_cooked) {
      my $raw = $rc->{'raw'};
      my $cooked = $rc->{'cooked'};
      if ($cooked=~m/wugga\-(\w+)\s*$/) {
        my $roman = $1;
        my $arabic = roman_to_arabic($roman);
        my $next_roman = arabic_to_roman($arabic+1);
        if ($arabic==1 and $n==$#raw_and_cooked || !($raw_and_cooked[$n+1]->{'cooked'}=~m/wugga\-$next_roman\s*$/)) {
          # only one part to this problem, so no need to display roman numeral
          $cooked=~s/\s*wugga\-(\w+)\s*$//;
        }
        else {
          $cooked=~s/wugga\-(\w+)\s*$/$roman/;
        }
  		}
      else {
        $cooked =~ s/\s+$//; # strip trailing whitespace
      }
      $cooked=~s/^lm\s+book\s+(\d+)/{1=>'NP',2=>'CL',3=>'VW',4=>'EM',5=>'Op',6=>'MR'}->{$1}/e; 
      $raw_and_cooked[$n]->{'cooked'}=$cooked;
			$n++;
    }
    return (\@list,\@raw_and_cooked,\@stuff);
}

sub server_list_work_handle_response {
                 my ($roster_ref,
                     $r,         # server's response string
                     $gb,
                     $stuff,     # list of raw problems, in this format: file=lm&book=1&chapter=0&problem=5&find=1 , including ones the use didn't select in GUI
                     $filter,    # See ServerDialogs::list_work() for comments explaining filter.
                     ) = @_; 
                 my @roster = @$roster_ref;
                 my %scores;
                 my $t = '';
                 $r =~ m/\n=key,([^\n]*)\n/; # Extract the key that tells us what problems these are the scores on.
                 my @key = split /,/ , $1;
                 $t = $t . sprintf "%25s ",'';
                 my $count = 0;
                 foreach my $key(@key) {
                   my $char = chr(ord('a')+$count); # These are labels for entire problems in plain-text table, not parts (a), (b), etc. of one problem.
                   $count++;
                   $t = "$t$char";
                 }
                 $t = "$t\n";
                 my %possible = (); # check that everyone has the same number of points possible, even if it's individualized hw
                 foreach my $who(@roster) {
                   my ($first,$last) = $gb->name($who);
                   $t = $t . sprintf "%25s","$first $last";
                   if ($r =~ m/$who\=([^\n]*)/m) {
                     #print "response:\n$r\n";
                     my $scores = $1; # comes back in the server's response as a string of binary bits
                     $possible{length $scores}++; # increment number of students who had this many points possible
                     $scores = server_list_work_filter_bit_string($scores,$who,$filter,\@key); # pass key, not stuff; only want the ones that were actually assigned
                     $t = $t . " $scores";
                     my $total = $scores;
                     $total =~ s/[0 ]//g;
                     $scores{$who} = length $total;
                   }
                   $t = $t . "\n";
                 }
                 if (length(keys %possible)>1) {ExtraGUI::error_message("Fun::server_list_work_handle_response: not all students had same number of possible pts")}
                 $t = $t . "\nkey:\n";
                 $count = 0;
                 foreach my $key(@key) {
                   my $char = chr(ord('a')+$count);
                   $count++;
                   $t = $t."  $char $key\n";
                 }
                 return ($t,\%scores);
}

# for individualized hw
# Takes a binary bit string and replaces any 0 or 1 characters with blanks if the problem wasn't assigned to this student.
sub server_list_work_filter_bit_string {
  my (
    $scores,   # binary string
    $who,      # student key
    $filter,   # See ServerDialogs::list_work() for comments explaining filter.
    $stuff,    # list of raw problems, in this format: file=lm&book=1&chapter=0&problem=5
  ) = @_;

  # Construct a list of raw html query keys, eliminating duplications.
  # I used to start this off with my @x = sort @$stuff;, because I thought WorkFile.pm used raw string sort order, so it was necessary to duplicate that.
  # That definitely caused a bug, where, e.g., if problem 3 and problem 11 were both assigned, students got scored on the wrong problems
  # because 11 came before 3 in string sort order. Eliminating the sort seems to have fixed the bug, but I'm still a little unsure of whether that
  # could cause a bug somewhere else.
  my @x = @$stuff;
  my %y = ();
  my @order = ();
  foreach my $x(@x) {
    if (! exists $y{$x}) {
      push @order,$x;
      $y{$x} = 1;
    }
  }
  if (scalar(@order)!=length($scores)) {die "in Fun::server_list_work_filter_bit_string, length mismatch between order, ".scalar(@order).", and scores, \"$scores\",".length($scores)."\n"  }
 
  my $filtered = '';
  for (my $i=0; $i<length($scores); $i++) {
    my $which = html_query_to_bcp($order[$i]); # "book,chapter,problem"
    #print "i=$i, order=$order[$i], which=$which\n";
    my $f = $filter->{$which}->{who};
    my $counted = (! defined $f) || (&$f($who));
    $filtered = $filtered . ($counted ? substr($scores,$i,1) : ' ');
  }
  #print "filtered $scores => $filtered for $who\n";
  return $filtered;
}



# returns the local time zone in units of hours; result may be a non-integer;
# west of Greenwich is negative
sub my_time_zone {
  my $t = time();
  my @local = localtime($t);
  my @gmt = gmtime($t);
  my $secs = ($local[0]-$gmt[0])+($local[1]-$gmt[1])*60+($local[2]-$gmt[2])*3600;
  if ($local[3]!=$gmt[3] || $local[4]!=$gmt[4] || $local[5]!=$gmt[5]) {
    if ($local[5]>$gmt[5] || ($local[5]==$gmt[5] && $local[4]>$gmt[4]) || ($local[5]==$gmt[5] && $local[4]==$gmt[4] && $local[3]>$gmt[3])) {
      $secs = $secs + 3600*24;
    }
    else {
      $secs = $secs - 3600*24;
    }
  }
  return $secs/3600.;
}


# returns undef if they don't have either Digest::Whirlpool or whirlpooldeep installed
sub do_whirlpool {
  my $x = shift;
  if (eval("require Digest::Whirlpool;") ) { # faster
    my $whirlpool = Digest::Whirlpool->new();
    $whirlpool->add($x);
    return pad_base64($whirlpool->base64digest());
  }
  else { # slow, but easier to satisfy dependency, using whirlpooldeep, which is packaged in debian md5deep package
    return cheesy_whirlpool($x);
  }
}

# It's a standard thing in base64 to pad with = signs to make the length be a multiple of 4.
# However, different versions of Digest::Whirlpool are inconsistent about this. Ensure the
# standard behavior:
sub pad_base64 {
  my $x = shift;
  while (length($x)%4!=0) {$x = $x . '='} 
  return $x;
}

# The following is an alternative to Digest::Whirlpool, used to avoid the dependency,
# which isn't available in a debian package. The whirlpooldeep program is available
# as part of the debian md5deep package. Returns undef if they don't have it installed.
sub cheesy_whirlpool {
  my $x = shift;

  # Camel book, p. 900, has an example of open2 with a bunch of mistakes in it.
  # See http://www.cs.wmich.edu/~hrvogel/perl/prog/ch16_03.htm for what looks like a correct example.
  local(*OUT,*IN);
  my $child_pid = open2(*OUT,*IN,'whirlpooldeep') or return undef;
  print IN $x;
  close IN;
  my $y = <OUT>;
  close OUT;
  waitpid($child_pid,0);

  # At this point, we have $y, the hash, in hex.

  $y =~ s/ *\n*$//; # eliminate trailing whitespace
  $y = pack "H*",$y; # convert hex to a string
  $y = encode_base64($y);
  $y =~ s/\n//g;
  return $y;
}


#----------------------------------------------------------------

1;
