#----------------------------------------------------------------
# Copyright (c) 2002 Benjamin Crowell, all rights reserved.
#
# This software is available under version 2 of the GPL license.
# The software is copyrighted, and you must agree to the
# license in order to have permission to copy it. The full
# text of the license is given in the file titled Copying.
#
#----------------------------------------------------------------

=head2 GradeBook.pm

This package defines the GradeBook class, which is essentially just
some hashes and arrays that implement the gradebook file format in memory.
Nearly all the data are in the hashes. The only thing the arrays are used
for is to keep track of the order of some of the keys in the hashes.

Internally, the structure of the hashes is maintained in a slightly different
way than in the gradebook file. This is a hold-over from the old file format.
Basically the internal structure is flatter than the file structure, and some
things that are really hashes are maintained as strings of the form "key:value","key:value",...
See comments above hashify() for more details, and for thoughts on neatening this up.

Undo:

A subset of this package's write methods is designated as the "user-write" API. Criteria for inclusion in the user-write API:
Should be user-initiated at least sometimes; should modify the gb; should modify it in a way that can be reflected with hashify();
should be something the user does directly, not an indirect consequence; shouldn't be a private method; should be a method, i.e., invoked as $gb->method().
The operations in the user API are the ones for which the GUI's "undo" feature can be applied,
and these are also the ones that are exposed to the scripting interface via --modify. See global variable
@user_write_api_functions and subs set_up_undo() and user_api().

There is no "user-read" API. Instead, the scripting interface just allows us to index into the hash
defined by hashify().

To add new data to the GradeBook structure:

=over

=item *

Add a method to GradeBook that sets and gets it.

=item *

Add it to hashify().

=item *

In read_json(), modify the list that specifies what order the top-level members of
the hash are processed.

=item *

Add it to flush_children_json().

=item *

Add appropriate initialization code to misc_initialization() and/or new(), read_json(), read_old() ....
New() is only for new gradebooks created from scratch. Misc_initialization()
gets called on all gradebook objects: newly created ones or ones read in from
a file.

=item *

If you care what order it's written to json files in, modify the invisible_sort array in jsonify().

=item *

Verify via opengrade --copy that it can be read and written correctly.

=back

=cut

use strict;
no strict "refs"; # see set_up_undo()

package GradeBook;

use POSIX;
use File::Copy;
# use LineByLine; # loaded only if specifically needed
use Preferences;
use Words qw(w get_w);
use MyWords;
use Fcntl qw/:flock/; # brings in LOCK_EX, etc.
use Version;
use JSON 2.0;
use Storable; # is distributed as part of the perl package on ubuntu; we use Storable::dclone in jsonify_ugly
use Clone;
push @Gradebook::ISA, 'Clone';
use Memoize;
use Fun;
memoize 'get_property2_slow'; # memoizing get_property2(), which calls get_property2_slow() on hard cases, actually seemed to hurt performance rather than helping

use Digest::SHA1;
# Digest::Whirlpool is loaded on the fly below, if possible and if necessary.
use MIME::Base64; # standard module
use IPC::Open2; # standard module

our @user_write_api_functions = qw(
                          clear_grades clear_assignment_list clear_roster union preferences set_grades_on_assignment drop_student reinstate_student set_student_property 
                          category_properties add_assignment delete_category delete_assignment rekey_assignment assignment_properties add_student set_standards set_marking_periods
                          dir assignment_array assignment_list set_all_category_properties add_category category_list class_data set_class_data types
);

# See the Words and MyWords modules for info on the following.
our $words;                        # initialized in main_loop()
our $words_prefix;                # initialized in each routine
sub w {
    my $key = shift;
    my $newline = "";
    if ($key =~ m/\n$/) {$newline="\n"}
    chomp $key;
    return $words->get($words_prefix.".".$key).$newline;
}


sub auto_save_if_they_want_it {
    my $self = shift;
    return if exists $self->{NO_AUTOSAVE};
    my $s = $self->when_last_autosaved();
    my $m = $self->when_last_modified();
    if ($self->want_auto_save() && (defined $m) && ((!(defined $s)) || ($s<=$m)) && time>$m) {
        # Testing for $s<=$m, as opposed to $s<$m, is necessary for safety, since the clock has a granularity of one
        # second, and the check for the autosave could happen in the same second as the modification.
        # It does raise the possibility of saving twice in a row, which is the reason for the final condition on time>$m.
        # This may have the effect of delaying the autosave for one cycle, which is preferable to double-saving or not saving at all.
        $self->auto_save();
    }
}

sub auto_save {
    my $self = shift;
    return if exists $self->{NO_AUTOSAVE};
    $self->write_to_named_file($self->autosave_filename());
    $self->mark_autosaved_now();
}

sub auto_save_file_exists {
    my $self = shift;
    return -e ($self->autosave_filename());
}

sub want_auto_save {
    my $self = shift;
    #return $self->boolean_pref("auto_save");
    return 1;
}

sub want_auto_backup {
    my $self = shift;
    #return $self->boolean_pref("auto_backup");
    return 1;
}

=head3 when_last_modified()

Get or set the time when the gradebook object was last modified. Returns
undef if never modified. This is used for deciding when to autosave,
and also for memoization in Crunch::total_one_cat().

=cut

sub when_last_modified {
    my $self = shift;
    if (@_) {
      $self->{WHEN_LAST_MODIFIED} = shift;
    }
    return $self->{WHEN_LAST_MODIFIED};
}

=head3 mark_modified_now()

Mark the gradebook as having been modified now.
The UI should call this whenever the gb is modified.
See when_last_modified() for general remarks.  To make memoization
safe, we need to make sure that we call this routine after the
modification is *complete*.

=cut

sub mark_modified_now {
    my $self = shift;
    $self->when_last_modified(time);
}

=head3 when_last_autosaved()

Get or set the time when the gradebook object was last auto-saved.
Returns undef if never autosaved.

=cut

sub when_last_autosaved {
    my $self = shift;
    if (@_) {
      $self->{WHEN_LAST_AUTOSAVED} = shift;
    }
    return $self->{WHEN_LAST_AUTOSAVED};
}

=head3 mark_autosaved_now()

Mark the gradebook as having been autosaved now.

=cut

sub mark_autosaved_now {
    my $self = shift;
    $self->when_last_autosaved(time);
}

# This is not an object method. Returns null string or error message.
sub strip_watermark_from_file {
      my $file_name = shift;
      my $gb = GradeBook->read($file_name);
      if (!ref $gb) {
        return $gb;
      }
      else {
        $gb->close();
      }
      my $err;
      if ($gb->{FORMAT} eq 'old')  {
        eval("require LineByLine;");
        my $mac = LineByLine->new();
        $err = $mac->strip(INFILE=>$file_name,OUTFILE=>$file_name);
        return $err;
      }
      else {
        my $json = $gb->jsonify(0); # 0 means no watermark
        open(FILE,">$file_name") or return "error opening file $file_name for output, $!";
        print FILE $json;
        close FILE;
        return '';
      }
}

=head3 write()

Returns a null string normally, or an error message otherwise.
Writes to the remembered filename, and does an emacs-style auto-backup
with a tilde on the end, if the auto_backup preference is set.
At this point, the file is presumably locked, but that's OK; it was
locked, it stays locked, and we still have it open for purposes of
locking. Deletes the autosave file, if any.
If the file ends in .json, it will be written in JSON format.
The format can also be specified explicitly with an optional argument:
old, json, or default(=either old or json, whatever is the default these days).

=cut

sub write {
    my $self = shift;
    my $format;
    if (@_) {$format = shift}
    my $auto_backup = $self->want_auto_backup();
    my $file_name = $self->file_name();
    $self->close();
    my $temp_file_name = "ogr_tmp_$$";
    if (!defined $format || $format eq 'default') {$format=$self->default_output_format()}
    if ($format ne 'old' && $format ne 'json') {return "illegal format $format specified at GradeBook::write()"}
    my $result = $self->write_to_named_file($temp_file_name,$format);
    if ($result ne "") {return $result} # if there's an error, return
    if ($auto_backup && !$self->{WROTE_TILDE_FILE}) {
      File::Copy::copy($file_name,"$file_name~");
      $self->{WROTE_TILDE_FILE} = 1;
    }
    unlink $file_name; # ignore errors, which just mean file is being created
    File::Copy::move($temp_file_name, $file_name) or return $!;
    unlink $self->autosave_filename(); # ignore errors, since it may not exist
    return "";
}

sub autosave_filename {
  my $self = shift;
  my $name = $self->file_name();
  $name =~ s|([^/]*)$|\#$1\#|;
  return $name;
}

sub hash_function {
  my $self = shift;
  my $prefs = $self->preferences();
  if (defined $prefs && ref($prefs) eq 'Preferences' && $prefs->get('hash_function')) {
    return $prefs->get('hash_function');
  }
  else {
    return Version::default_hash_function();
  }
}

sub jsonify {
  my $self = shift;
  my $do_watermark = 1;
  if (@_) {$do_watermark = shift}
  my $h = $self->hashify();
  $h->{'invisible_sort'} = ['class','preferences','types','category_order','categories','roster','assignment_order','assignments','grades'];
  my $pretty_json =  jsonify_readable($h,2,0,{'grades'=>1,'assignments'=>1},1);
  delete $h->{'invisible_sort'};
  my $ugly_json = jsonify_ugly($h);
  if (0) { 
    # For debugging, see if it can go through another round trip and be the same as it would have been if we hadn't prettified it.
    # This only works if $no_quotes_on_ints is set to zero above.
    my $raw_json = (new JSON)->canonical([1])->encode($h);
    my $round_trip = (new JSON)->canonical([1])->encode(JSON::from_json($pretty_json));
    if ($raw_json ne $round_trip) {die "error, pretty json doesn't canonicalize properly"}
  }
  my $json= (new JSON);
  $json->canonical([1]);
  if ($do_watermark) {
    my $watermark = $json->encode([$self->hash_function(),$self->do_watermark_hash_function($self->password().$ugly_json)]);
    return "{\n\"watermark\":$watermark,\n\"data\":\n$pretty_json}\n";
  }
  else {
    return $pretty_json;
  }
}

# This one's only function in life is to be canonical -- so canonical that we can use it for watermarks.
# The canonical() option on the JSON object makes it output all hashes with keys in alphabetical order.
# We also want to make sure that numbers that can be represented without quotes get represented without quotes.
# Note that although Object::Signature does sort of the same thing, it doesn't address the strings-versus-numbers issue.
# This is not a method, and shouldn't be invoked as such. It's simply a function that takes a hash and returns a string.
# Typically you would do something like jsonify_ugly($b->hashify()).
sub jsonify_ugly {
  my $h = shift;
  my $json= (new JSON);
  $json->canonical([1]);
  return $json->encode(strings_to_numbers(Storable::dclone($h))); # clone it, so we can mess with it without risking damage to the original
}

sub strings_to_numbers {
  my $x = shift;
  my $r = ref $x;
  if ($r eq "ARRAY") { my @y = map {strings_to_numbers($_)} @$x; return \@y }
  if ($r eq "HASH") {
    foreach my $key(keys %$x) {
      $x->{$key} = strings_to_numbers($x->{$key});
    }
    return $x;
  }
  if ($r) {
    die "illegal reference of type $r in GradeBook::strings_to_numbers";
  }
  if ($x=~/^[1-9]\d*$/) { # E.g., if a student ID has leading zeroes, don't make it into a number. JSON integers also can't have leading zeroes.
    return $x+0;
  }
  else {
    return $x;
  }
}

sub jsonify_readable {
  my $x = shift;
  my $pretty_depth = shift; # this many outer layers are indented
  my $depth = shift;
  my $add_depth = shift; # hash ref
  my $no_quotes_on_ints = shift; # if this is set, it won't pass the round-trip test
  my $json= (new JSON);
  $json->canonical([1]); # not available on older versions of JSON 1.x; this is needed if, e.g., differ() and watermarks are going to work correctly
  if (!ref $x) {
    if ($no_quotes_on_ints && ($x eq '0' || $x =~ /^[1-9]\d*$/)) { # JSON int doesn't need to be quoted; can't be a string beginning with 0, unless it's only 0
      return $x;
    }
    else {
      return $json->allow_nonref->encode($x); # surround with quotes, escape " and \
    }
  }
  my $indent = '';
  my $indent_more = '';
  my $newline = '';
  if ($depth<$pretty_depth) {
    $indent = '  ' x ($depth+1);
    $indent_more = $indent . '  ';
    $newline = "\n";
  }
  if (ref($x) eq 'HASH') {
    my @r;
    my $sort = sub{my ($a,$b)=@_; return $a cmp $b};
    if (exists $x->{'invisible_sort'}) {
      $sort = sub {
        my ($a,$b)=@_;
        my $r = $x->{'invisible_sort'};
        my $i = 0;
        my $n = @$r;
        my ($oa,$ob) = ($n,$n);
        foreach my $o(@$r) {
          if ($o eq $a) {$oa=$i}
          if ($o eq $b) {$ob=$i}
          ++$i;
        }
        return $oa <=> $ob;
      };
    }
    foreach my $k(sort {&$sort($a,$b)} keys %$x) {
      if ($k ne 'invisible_sort') {
        my $v = $x->{$k};
        my $pd = ((exists $add_depth->{$k}) ? $pretty_depth+1 : $pretty_depth);
        my $ad = ((exists $add_depth->{$k}) ? {} : $add_depth);
        push @r,"$indent_more\"$k\":".jsonify_readable($v,$pd,$depth+1,$ad,$no_quotes_on_ints);
      }
    }
    return $indent."{$newline".join(",$newline",@r).$newline.$indent."}";
  }
  if (ref($x) eq 'ARRAY') {return $json->encode($x)}
  die "reference of type ".ref($x)." encountered in GradeBook::jsonify_readable" if ref($x);
}

=head3 hashify()

Turn the entire gradebook structure into a data structure made of nested hashes. This
is what determines what gets written to disk when we write a file in the new json format.
It also determines what gets digitally watermarked.

Current internal representation:

$gb->{CATEGORIES}->{$cat}->/property/  --- see categories_private_method

$gb->{ASSIGNMENTS}->{"$cat.$ass"}->/property/ --- see assignments_private_method()

$gb->{GRADES}->{"$who.cat"}->/ass/      --- see grades_private_method()

In the above, ->/.../ means a situation where I mocked up a hash as a comma-separated list.

Representation in output of hashify():

->{categories}->{$cat}->{$property}

->{assignments}->{$cat}->{$ass}->{$property}

->{grades}->{$cat}->{$who}->{$ass}

Thoughts on neatening this up:

One reason it would be helpful to neaten this up would be that it would make hashify() a
more efficient operation. We're currently spending a lot of time in hashify() because of
undo functionality, and it's caused a noticeable degradation in performance when entering
grades.

I made an attempt to neaten in Jan '09, and it was disastrous. I think the problem was
that calling code was being handed references to hashes, and then treating those hashes
as scratch copies that could safely be modified. That's okay in the present implementation,
but isn't okay in an implementation where the hash refs being returned are just references
to the internally maintained data structures. Tie::SecureHash could be helpful here.
It's not packaged for debian, but it's pure perl, so I could just include it with OpenGrade,
or only use it on an interim basis for debugging. However, it will only protect against
munging by other packages, and I could have the same issue with methods inside GradeBook.

It's not as simple as just changing the internal representations of $gb->{GRADES}, etc.
That would be trivial to do, but then every call to grades_private_method() would have
to convert the new-style hash back into an old-style representation. This would probably
be less efficient than the current setup, until I got around to rewriting the calling
code.

=cut

sub hashify {
  my $self = shift;
  my @ao = split(",",$self->assignment_list());
  my @co = split(",",$self->category_list());
  my $h = {
    'class'=>{
      'title'=>$self->title(),
      'staff'=>$self->staff(),
      'days' =>$self->days(),
      'time' =>$self->time(),
      'term' =>$self->term(),
      'dir'  =>$self->dir(),
      'standards' =>$self->standards(), # hash ref
      'online_grades' => {
        'cltext'         =>$self->class_data('online_grades_cltext'),
        'course_code'    =>$self->class_data('online_grades_course_code'),
        'section_number' =>$self->class_data('online_grades_section_number'),
        'term'           =>$self->class_data('online_grades_term'),
      }
    },
    'types'=>        $self->types(),
    'categories'=>   $self->crufty_string_to_hash($self->categories_private_method()),
    'roster'=>       $self->crufty_string_to_hash($self->roster_private_method()),
    'assignments'=>  deepen_crufty_hash($self->crufty_string_to_hash($self->assignments_private_method()),1),
    'grades'=>       deepen_crufty_hash($self->crufty_string_to_hash($self->grades_private_method()),2),
    'assignment_order' =>  \@ao,
    'category_order'   =>  \@co,
  };
  if ($self->marking_periods()) {$h->{'class'}->{'marking_periods'} = $self->marking_periods()}
  return $h;
}

# Example of input (jsonified):
#      "e.midterm" : "1/8",
#      "e.practice_exam_1" : "1/8",
#      "hw.1" : "2/8",
#      "hw.14" : "1/8",
sub deepen_crufty_hash {
  my $h = shift;
  my $outer = shift; # in the above example, $outer=1 would make the keys of the outermost hash be e, hw, ...; $outer=2 would make them midterm, practice_exam_1, etc.
  my $r = {};
  foreach my $k(keys %$h) {
    $k =~ /(.*)\.(.*)/;
    my ($o,$i); # outer and inner key
    ($o,$i) = $outer==1 ? ($1,$2) : ($2,$1);
    $r->{$o} = {} unless exists $r->{$o};
    $r->{$o}->{$i} = $h->{$k};
  }
  return $r;
}

sub shallowfy_crufty_hash {
  my $h = shift;
  my $outer = shift;
  my $r = {};
  foreach my $o(keys %$h) {
    my $g = $h->{$o};
    foreach my $i(keys %$g) {
      $r->{$outer==1 ? "$o.$i" : "$i.$o"} = $g->{$i};
    }
  }
  return $r;
}

sub crufty_string_to_hash {
  my $self = shift;
  my $h = shift; # hash ref
  my $r = {};
  while (my ($k,$v) = each(%$h)) {
    my %x = comma_delimited_to_hash($v);
    $r->{$k} = \%x;
  }
  return $r;
}

=head3 write_to_named_file()

Returns a null string normally, or an error message otherwise.
Shouldn't normally call this directly, because it doesn't do
any of the safety features. Call write() instead.
Optional second argument is format, can be 'default', 'old', or 'json',
defaults according to default_output_format().

=cut

sub write_to_named_file {
    my $self = shift;
    my $file_name = shift;
    my $format = 'default';
    if (@_) {$format = shift}
    if ($format eq 'default') {$format = $self->default_output_format()}
    if ($format eq 'old') {
      return $self->write_to_named_file_native_format($file_name);
    }
    if ($format eq 'json') {
      return $self->write_to_named_file_json_format($file_name);
    }
    die "illegal format $format at GradeBook::write_to_named_file";
}

# can be 'old' or 'json'
sub default_output_format {
  my $self = shift;
  return 'json';
}

sub write_to_named_file_json_format {
    my $self = shift;
    my $file_name = shift;

    open(OUTFILE,">$file_name") or return "Error opening $file_name file for output";
    print OUTFILE $self->jsonify();
    close(OUTFILE) or return "Error closing output file";
    return "";
}

sub write_to_named_file_native_format {
    my $self = shift;
    my $file_name = shift;
    eval("require LineByLine;");

    open(OUTFILE,">$file_name") or return "Error opening $file_name file for output";

    my $mac = LineByLine->new(KEY=>$self->password(),ITERATIONS=>iterations_for_line_by_line(),HASH_FUNCTION=>$self->hash_function());
    print OUTFILE $mac->head();

    print OUTFILE $mac->line("class");
    print OUTFILE $mac->line("  .title \"".$self->title()."\"");
    print OUTFILE $mac->line("  .staff \"".$self->staff()."\"");
    print OUTFILE $mac->line("  .days  \"".$self->days()."\"");
    print OUTFILE $mac->line("  .time  \"".$self->time()."\"");
    print OUTFILE $mac->line("  .term  \"".$self->term()."\"");
    print OUTFILE $mac->line("  .dir   \"".$self->dir()."\"");
    print OUTFILE $mac->line("  .standards   ".hash_to_comma_delimited($self->standards()));
    print OUTFILE $mac->line("  .marking_periods   ".hash_to_comma_delimited($self->marking_periods())) if $self->marking_periods();
    print OUTFILE $mac->line("  .online_grades_cltext   \"".$self->class_data('online_grades_cltext')."\"") if $self->class_data('online_grades_cltext');
    print OUTFILE $mac->line("  .online_grades_course_code   \"".$self->class_data('online_grades_course_code')."\"") if $self->class_data('online_grades_course_code');
    print OUTFILE $mac->line("  .online_grades_section_number   \"".$self->class_data('online_grades_section_number')."\"") if $self->class_data('online_grades_section_number');
    print OUTFILE $mac->line("  .online_grades_term   \"".$self->class_data('online_grades_term')."\"") if $self->class_data('online_grades_term');
    print OUTFILE $mac->line("");
    print OUTFILE $mac->line("preferences");
    my $h = $self->preferences_private_method();
    foreach my $p(keys(%$h)) {
        print OUTFILE $mac->line("  .".lc($p)." \"".$h->{$p}."\"");
    }
    print OUTFILE $mac->line("");
    print OUTFILE $mac->line("categories");
    my @cl = split(",",$self->category_list());
    foreach my $c(@cl) {
        print OUTFILE $mac->line("  .".$c." ".$self->category_properties_comma_delimited($c));
    }
    print OUTFILE $mac->line("");

    print OUTFILE $mac->line("roster");
    my @student_keys = $self->student_keys("all");
    $h = $self->roster_private_method();
    foreach my $k (@student_keys) {
        my $v = $h->{$k};
        $v =~ s/^,//; # strip leading comma
        $v =~ s/,$//; # strip trailing comma
        print OUTFILE $mac->line("  .$k $v");

    }
    print OUTFILE $mac->line("");

    print OUTFILE $mac->line("assignments");
    my @a = split(",",$self->assignment_list());
    my $ass = $self->assignments_private_method();
    foreach my $a(@a) {
        print OUTFILE $mac->line("  .$a ".$self->strip_redundant_properties($a,$ass->{$a}));
    }
    print OUTFILE $mac->line("");

    print OUTFILE $mac->line("grades");
    my $g = $self->grades_private_method();
    my $z = $self->roster_private_method();
    my @r = sort keys %$z;

    # The hard-coded 1000 in the following may be ugly, but I doubt it will
    # ever be an issue, and this /is/ an efficient way to do the sort.
    my @grades_to_sort = ();
    while (my ($k,$v) = each (%$g)) {
      $k =~ m/([^\.]+)\.([^ ]+)/;
      my $who = $1;
      my $cat = $2;
      push @grades_to_sort, (sprintf "%-1000s%-1000s%s",$cat,$who,$v);
    }
    @grades_to_sort = sort @grades_to_sort;
    foreach my $line(@grades_to_sort) {
        my $cat = substr($line,0,1000);
        my $who = substr($line,1000,1000);
        my $v   = substr($line,2000);
        $cat =~ s/ +$//; # delete trailing blanks
        $who =~ s/ +$//; # delete trailing blanks
        #print "$cat,$who,$v\n";
        print OUTFILE $mac->line("  .$who.$cat $v");
    }

    if (my $stuff = $self->stuff_unable_to_parse()) {
      print OUTFILE $mac->line("");
      while ($stuff =~ m/([^\n]*)\n/g) {
        my $line = $1;
        print OUTFILE $mac->line($line);
      }
    }

    print OUTFILE $mac->tail();

    close(OUTFILE) or return "Error closing output file";
    return "";
}

=head3 new()

GradeBook->new() creates a new GradeBook object.

=cut

sub new {
    my $class = shift;
    my %args = (
                TITLE=>"",
                STAFF=>"staff",
                DAYS=>"MTWRF",
                TIME=>"",
                TERM=>"",
                DIR=>"web_reports",
                #FTP=>"",
                FILE_NAME=>"",
                STANDARDS=>"",
                MARKING_PERIODS=>undef,
                PASSWORD=>"",
                @_
                );
    my $self = {};
    bless($self,$class);
    $self->{PREVENT_UNDO} = 1;
    $self->class_private_method({
        "title"=>$args{TITLE},
        "staff"=>$args{STAFF},
        "days"=>$args{DAYS},
        "time"=>$args{TIME},
        "term"=>$args{TERM},
        "dir"=>$args{DIR},
        "standards"=>$args{STANDARDS},
        "marking_periods"=>$args{MARKING_PERIODS},
    });
    $self->preferences_private_method({"backups_on_server"=>'"true"',
                                   "auto_save"=>'"true"',
                                   "auto_backup"=>'"true"'});
    $self->modified(1);
    $self->file_name($args{FILE_NAME});
    $self->password($args{PASSWORD});
    $self->category_list("");
    $self->clear_assignment_list;
    $self->misc_initialization();
    return $self;
}

sub clear_grades {
  my $self = shift;
  $self->grades_private_method({});
}

sub clear_assignment_list {
  my $self = shift;
  $self->assignment_list("");
  $self->assignments_private_method({});
}

sub clear_roster {
  my $self = shift;
  $self->roster_private_method({});
}


=head3 differ

Tests whether two gradebook objects contain identical data. Doesn't care about format, e.g., a file
in JSON format could be judged identical to one in the old format.
Tests somewhat more thoroughly than union(). Returns null string if they're identical,
or a log of hypothetical changes that would have to be made to reconcile them.

=cut

sub differ {
  my ($a,$b) = @_;
  # Try to detect changes, e.g., to prefs or standards, that union() wouldn't have detected.
  my $ja = jsonify_ugly($a->hashify());
  my $jb = jsonify_ugly($b->hashify());
  if ($ja eq $jb) {return 0}
  # jsonify() uses canonical option, so these won't differ trivially
  my $log = $a->union($b);
  if ($log) {return $log}
  return "The files differ when serialized in json format, but not in terms of categories,\nassignments, scores, or students. Perhaps the standards or class data differ.";
}

=head3 union()

$a->union($b,$ask) adds scores and students from gradebook $b into gradebook $a. Nothing is done
with the preferences or grading standards; these are left as they were (in $a).

Returns text describing everything that was done.

Method differ() is meant for the case where you want to find out whether and how $a and $b
differ, but don't necessarily want to reconcile them. Differ() calls union(), but only for
the purpose of reading the textual summary of differences. Union() will not catch or try to
reconcile all possible differences, but differ() will catch all differences, even if union()
is unable to give a textual summary of some of them.

When a student exists in both gradebooks, but the student's properties are different in $a and $b,
an appropriate log message will be generated, but the properties will be left as they are in $a.
A message will also be generated if the student exists in one gradebook but not the other.

Category and assignment properties are handled the same way as student properties.

When a grade is present in both gradebooks, and the grades
are unequal, call the subroutine $ask to decide which to use. This subroutine can interact with the
user, or work according to some predefined rule. If no second argument is provided, the default $ask
routine is one that just returns 1, causing grades from $a to be replaced with those in $b in all cases.
(Note that it's important that this default is this way, because we use this method noninteractively,
e.g., when opening a file that turns out to have an autosave file, which we want to test to see if
it's identical to the one we opened. If the $ask routine returns 0, then the result is always a null
string for the log of changes, which is the wrong result.)

=cut

sub union {
  my $a = shift;
  my $b = shift;
  my $ask = sub {return 1};
  if (@_) {$ask = shift}
  my $log = '';

  # Compare category properties, but don't try to reconcile them:
  my $ac = $a->categories_private_method(); # hash ref
  my $bc = $b->categories_private_method(); # hash ref
  my %combined_cats = (%$ac,%$bc);
  my %deleted_or_added_cats;
  foreach my $cat(sort keys %combined_cats) {
    if (exists $ac->{$cat} xor exists $bc->{$cat}) {
      $deleted_or_added_cats{$cat} = 1;
      if (! exists $ac->{$cat} ) {
        $log = $log . "Category $cat was added.\n";
      }
      else {
        $log = $log . "Category $cat was deleted.\n";
      }
    }
    else {
      my $d = diff_comma_delimited($ac->{$cat},$bc->{$cat});
      if (ref $d) {
        my ($keys,$ah,$bh) = ($d->{'keys'},$d->{'a'},$d->{'b'});
        foreach my $property(@$keys) {
          my $name = $a->category_name_plural($cat);
          $log = $log . "Category $name had property $property changed from '$ah->{$property}' to '$bh->{$property}'\n";
        }
      }
    }
  }
  
  # Compare assignment properties, but don't try to reconcile them:
  my $aa = $a->assignments_private_method(); # hash ref
  my $ba = $b->assignments_private_method(); # hash ref
  my %combined_ass = (%$aa,%$ba);
  foreach my $ass(sort keys %combined_ass) {
    my ($cat,$foo) = $a->split_cat_dot_ass($ass);
    next if exists $deleted_or_added_cats{$cat};
    if (exists $aa->{$ass} xor exists $ba->{$ass}) {
      if (! exists $aa->{$ass} ) {
        $log = $log . "Assignment $ass was added.\n";
      }
      else {
        $log = $log . "Assignment $ass was deleted.\n";
      }
    }
    else {
      my $d = diff_comma_delimited($aa->{$ass},$ba->{$ass});
      if (ref $d) {
        my ($keys,$ah,$bh) = ($d->{'keys'},$d->{'a'},$d->{'b'});
        foreach my $property(@$keys) {
          my $name = $a->assignment_name($ass);
          $log = $log . "Assignment $name had property $property changed from '$ah->{$property}' to '$bh->{$property}'\n";
        }
      }
    }
  }
  
  # Compare student properties, but don't try to reconcile them:
  my $ar = $a->roster_private_method(); # hash ref
  my $br = $b->roster_private_method(); # hash ref
  my %combined_roster = (%$ar,%$br);
  foreach my $student(sort keys %combined_roster) {
    if (exists $ar->{$student} xor exists $br->{$student}) {
      if (! exists $ar->{student} ) {
        $log = $log . "Student $student was added.\n";
      }
      else {
        $log = $log . "Student $student was deleted (not just dropped).\n";
      }
    }
    else {
      my $d = diff_comma_delimited($ar->{$student},$br->{$student});
      if (ref $d) {
        my ($keys,$ah,$bh) = ($d->{'keys'},$d->{'a'},$d->{'b'});
        foreach my $property(@$keys) {
          my ($first,$last) = $a->name($student);
          if ($property eq 'dropped') {
            if ($ah->{$property} eq 'true') {
              $log = $log . "Student $last, $first was reinstated.\n";
            }
            else {
              $log = $log . "Student $last, $first was dropped.\n";
            }
          }
          else {
            $log = $log . "Student $last, $first had property $property changed from '$ah->{$property}' to '$bh->{$property}'\n";
          }
        }
      }
    }
  }
  
  # Copy students:
  foreach my $b_student(sort ($b->student_keys('all'))) {
    if (!(exists($a->roster_private_method->{$b_student}))) {
      $a->roster_private_method->{$b_student} = $b->roster_private_method->{$b_student};
      my ($first,$last) = $a->name($b_student);
      $log = $log . "Added student $last, $first.\n";
    }
  }

  # Copy categories:
  my $b_cats = $b->category_array();
  foreach my $b_cat(@$b_cats) {
    if (!($a->category_exists($b_cat))) {
      $a->add_category($b_cat);
      $a->categories_private_method->{$b_cat} = $b->categories_private_method->{$b_cat}; # copy properties
      $log = $log . "Added category ".$a->category_name_plural($b_cat).".\n";
    }
  }

  # Copy assignments:
  my $cats = $a->category_array();
  foreach my $cat(@$cats) {
    if ($b->category_exists($cat)) {
      my $a_assignments = $a->array_of_assignments_in_category($cat); # array ref
      my $b_assignments = $b->array_of_assignments_in_category($cat);
      foreach my $b_ass(@$b_assignments) {
        if (!($a->assignment_exists("$cat.$b_ass"))) {
          $a->add_assignment(CATEGORY=>$cat,ASS=>$b_ass,PROPERTIES=>($b->assignments_private_method->{".$cat.$b_ass"}));
          $log = $log . "Added assignment ".$a->assignment_name($cat,$b_ass).".\n";
        }
      }
    }
  }

  # Copy scores:
  foreach my $cat(@$cats) {
    my $assignments = $a->array_of_assignments_in_category($cat); # array ref
    foreach my $ass(@$assignments) {
      foreach my $student(sort ($a->student_keys('all'))) {
        my $key = "$cat.$ass";
        if ($b->category_exists($cat) && $b->assignment_exists($key)) {
          my $a_grade = $a->get_current_grade($student,$cat,$ass);
          my $b_grade = $b->get_current_grade($student,$cat,$ass);
          my $ass_name = $a->assignment_name($cat,$ass);
          my ($first,$last) = $a->name($student);
          my $copy = 0;
          if ($a_grade eq '' && $b_grade ne '') {
            $log = $log . "Added grade $b_grade on assignment $ass_name for $last, $first.\n";
            $copy = 1;
          }
          if ($a_grade ne '' && $b_grade ne '' && $a_grade!=$b_grade) {
            if (&$ask($ass_name,"$last, $first",$a_grade,$b_grade)) {$copy = 1}
            if ($copy) {$log = $log . "Changed grade from $a_grade to $b_grade on assignment $ass_name for $last, $first.\n"}
          }
          if ($copy) {
            $a->set_grades_on_assignment(CATEGORY=>$cat,ASS=>$ass,GRADES=>{$student=>$b_grade});
          }
        }
      }
    }
  }

  $log =~ s/\n$//;  
  return $log;

}

=head3 clone()

Make an identical copy of the GradeBook object, but sets its filehandle and file_name to undef. The
list of assignments and student roster are copied.

=cut

sub clone {
  my $self = shift;
  my $clone = GradeBook->Clone();
  $clone->filehandle(undef);
  $clone->file_name(undef);
}

=head3 filehandle()

Sets or gets a reference to the filehandle being used to access the file. Returns undef if there
is no filehandle associated with the file. The only purpose of maintaining this filehandle is
so we can keep a lock on the file.

=cut
sub filehandle {
  my $self = shift;
  if (@_) {$self->{FILEHANDLE} = shift}
  return $self->{FILEHANDLE};
}

=head3 close()

Close the file associated with this GradeBook's filehandle. This also releases the lock.
This does NOT save the file or anything like that. The only real reason you want to call
this routine is to release the lock on the file, or to make sure Windows will not be upset
because it's been left open.

=cut

sub close {
  my $self = shift;
  if (ref $self->{FILEHANDLE}) {
    close($self->filehandle()); # releases lock
  }
}

=head3 lock()

Try to lock the file associated with this GradeBook's filehandle. Pass back the return value.
The unlocking happens automatically when the file is closed.

=cut
sub lock {
  my $self = shift;
  if (Portable::os_type() ne 'windows') {
    return flock($self->filehandle(),(2 | 4));
           # ... 2=exclusive, 4=non-breaking.
           # Can't use symbolic names because of use strict. 
  }
  else {
    return 1;
    # If we're on Windows, don't try to do file locking. I don't understand how Perl implements
    # file locking on Windows, but it seemed to keep me from being able to
    # read files. This may be related to the fact that Perl on Windows is pickier than Unix
    # about opening a file again without closing it.
  }
}

# When I use OpenGrade with howdy, /foo/bar.gb has a corresponding
# directory /foo/bar.sets, which contains some csv files.
# Since howdy isn't a publicly released program, this isn't relevant to anyone but me.

sub sets_directory {
  my $self = shift;
  my $me = $self->file_name();
  my $sets = $me;
  return undef unless $sets =~ /\.gb$/;
  $sets =~ s/\.gb$/\.sets/;
  return undef unless -d $sets;
  return $sets;
}

=head3 read()

GradeBook->read("foo.gb") creates a new GradeBook object by reading a file.
Optional second argument is password (defaults to null string).
Optional third argument is a hash ref containing options.
In case of an error, returns a string containing an error message.
Should call it like this: $gb=GradeBook->read(...); if (!ref $gb) {..error..}
This also sets filehandle() and locks the file.
Attempts to autodetect old format versus new json format, will read either one.

Sets $self->{AUTHENTICITY} to null string if authentic.
Sets $self->{HAS_WATERMARK}.

By default, OpenGrade autosaves your file a few
seconds after any modification. This is not the right behavior for, e.g., scripts
or automated testing. To prevent autosaves, set NO_AUTOSAVE=>1 in the options hashref.

=cut

sub read {
    my $class = shift;
    my $file_name = shift;
    my $password = "";
    if (@_) {$password = shift}
    my $options = {};
    if (@_) {$options = shift}
    open(FILE,"<$file_name") or return "Cannot open $file_name";
    my $first_line = <FILE>;
    close FILE;
    my $gb;
    if ($first_line =~ /^\s*[\{\[]/) { # If it starts with { or [, that's consistent with JSON, not with old format.
      $gb = GradeBook->read_json($file_name,$password);
      if (!ref $gb) {return $gb}
      $gb->{FORMAT} = 'json';
    }
    else {
      $gb = GradeBook->read_old($file_name,$password);
      if (!ref $gb) {return $gb}
      $gb->{FORMAT} = 'old';
    }
    if (exists $options->{NO_AUTOSAVE}) {$gb->{NO_AUTOSAVE}=1}
    $gb->repair_problems();
    return $gb;
}

sub repair_problems {
  my $self = shift;
  # Versions 3.1.6 and earlier would let you give an assignment a name containing uppercase characters, which would cause errors. Repair damage of
  # this type. In this condition, the only place where the uppercase version appears is in the students' recorded grades.
  # We don't want to do a normal renaming of the assignment, because in this condition, the name appears in inconsistent forms in different places.
  my $grades = $self->grades_private_method(); # hash ref like {"Newton_Isaac.hw"=>"1:12",...}
  my $repaired = 0;
  while (my ($key,$val) = each(%$grades)) {
    if ($val ne lc($val)) { # for efficiency, test this way first
      $val =~ /(.*):(.*)/;
      my $new = lc($1) . ":" . $2;
      if ($new ne $val) {
        $grades->{$key} = $new;
        $repaired = 1;
      }
    }
  }
  if ($repaired) {$self->grades_private_method($grades); $self->mark_modified_now()}
}

=head3 read_json()

Call it the same way as read(). Generally this should not be called directly; should call
read(), which will autodetect file format and call read_json() or read_old() as appropriate.

=cut

sub read_json {
    my $class = shift;
    my $file_name = shift;
    my $password = "";
    if (@_) {$password = shift}
    my $self = {};
    bless($self,$class);
    $self->{PREVENT_UNDO} = 1;
    $self->password($password);
    $self->modified(0);
    $self->file_name($file_name);
    my $buff = "";
    my @names; # for use in roster mode
    my $children={};
    open (INFILE,"<$file_name") or return "Cannot open $file_name";
    $self->filehandle(\*INFILE); # Perl idiom for getting a reference to a filehandle, see camel book, p. 249
    $self->lock() or return "Unable to obtain a lock on file $file_name. This can happen if you are running two copies of OpenGrade at once.";
    local $/; # slurp whole file
    my $json = <INFILE>;
    my $envelope = eval {JSON::from_json($json)};
    return "syntax error in input file $file_name" unless defined $envelope;
    my ($h,$watermark,$hash_function);
    if (exists $envelope->{'data'} && exists $envelope->{'watermark'}) {
      $h = $envelope->{'data'};
      $hash_function = $envelope->{'watermark'}->[0];
      $watermark = $envelope->{'watermark'}->[1];
    }
    else {
      $h = $envelope;
    }
    if ($watermark) {
      $self->{HAS_WATERMARK} = 1;
      my $redo_watermark = $self->do_watermark_hash_function($password.jsonify_ugly($h),$hash_function);
      if ($watermark eq $redo_watermark) {
        $self->{AUTHENTICITY}=''; # null string means authentic
      }
      else {
        $self->{AUTHENTICITY}="not authentic, $watermark ne $redo_watermark\n"; # non-null string means not authentic
      }
    }
    else {
      $self->{HAS_WATERMARK} = 0;
    }
    $self->set_from_hash($h);
    #close INFILE; # Used to close after reading. No longer do this, because we want locking.
    my $err = $self->misc_initialization();
    if ($err ne '') {return $err}
    return $self;
}

sub do_watermark_hash_function {
  my $self = shift;
  my $data = shift;
  my $function = $self->hash_function();
  if (@_) {$function = shift}
  if ($function eq 'SHA1') {
    return Digest::SHA1::sha1_base64($data);
  }
  # The following code is duplicated in LineByLine.pm, for legacy support of old format.
  # Returns undef if they requested Whirlpool, but don't have either Digest::Whirlpool or whirlpooldeep installed.
  if ($function eq 'Whirlpool') {
    if (eval("require Digest::Whirlpool;") ) { # faster
      my $whirlpool = Digest::Whirlpool->new();
      $whirlpool->add($data);
      return Fun::pad_base64($whirlpool->base64digest());
    }
    else { # slow, but easier to satisfy dependency, using whirlpooldeep, which is packaged in debian md5deep package
      return Fun::cheesy_whirlpool($data);
    }
  }
  die "unrecognized hash function $function in GradeBook::do_watermark_hash_function";
}

# After calling this, always do $gb->misc_initialization() or $gb->misc_initialization(1)
sub set_from_hash {
  my $self = shift;
  my $h = shift;
  my %recognized_modes = ('class'=>1,'preferences'=>1,'categories'=>1,'roster'=>1,
                            'assignments'=>1,'grades'=>1);
  my $mode_is_recognized; # anything not recognized is just preserved without parsing it
  my @keys = ('class','preferences','types','categories','roster','assignments','grades'); # Want to guarantee that these are done first and in order.
  foreach my $k(keys %$h) { # preserve any keys we don't know about
    unless (exists $recognized_modes{$k}) {push @keys,$k}
  }
  foreach my $k(@keys) {
    $self->flush_children_json($k,$h->{$k});
  }
  $self->use_defaults_for_assignments();
}

sub flush_children_json {
    my $self = shift;
    my $what = shift;
    my $h = shift;
    if ($what eq '' && (keys %$h)==0) {return} # happens if there's nothing to flush yet
    #print "flushing\n";
    my $handler = {
      'class'           => \&class_private_method,
      'preferences'     => \&preferences_private_method,
      'types'           => \&types,
      'categories'      => \&categories_private_method,
      'roster'          => \&roster_private_method,
      'assignments'     => \&assignments_private_method,
      'grades'          => \&grades_private_method,
      'assignment_order'=> sub{my ($self,$h) = @_; $self->assignment_list(join(',',@$h))},
      'category_order'  => sub{my ($self,$h) = @_; $self->category_list(join(',',@$h))},
    }->{$what};
    die "illegal data in file, key=$what, hash keys are ".(join(',',keys %$h)) unless defined $handler;
    if ($what eq 'assignments') {$h = shallowfy_crufty_hash($h,1)}
    if ($what eq 'grades') {$h = shallowfy_crufty_hash($h,2)}
    if (exists {'categories'=>1,'assignments'=>1,'grades'=>1,'roster'=>1}->{$what}) {
      foreach my $k(keys %$h) {
        my $v = $h->{$k};
        $h->{$k} = hash_to_comma_delimited($h->{$k});
      }
    }
    if ($what eq 'class') {
      if (exists $h->{'standards'}) {$h->{'standards'} = hash_to_comma_delimited($h->{'standards'})}
      if (exists $h->{'marking_periods'}) {$h->{'marking_periods'} = hash_to_comma_delimited($h->{'marking_periods'})}
    }
    &$handler($self,$h);
    if ($what eq 'class') {
      if (exists $h->{'online_grades'}) {
        $self->class_data('online_grades_course_code'     ,$h->{'online_grades'}->{'course_code'} || '');
        $self->class_data('online_grades_section_number'  ,$h->{'online_grades'}->{'section_number'} || '');
        $self->class_data('online_grades_term'            ,$h->{'online_grades'}->{'term'} || '');
        $self->class_data('online_grades_cltext'          ,$h->{'online_grades'}->{'cltext'} || '');
      }
    }
}

sub read_old {
    my $class = shift;
    my $file_name = shift;
    my $password = "";
    if (@_) {$password = shift}
    my $self = {};
    bless($self,$class);
    $self->{PREVENT_UNDO} = 1;
    $self->password($password);
    $self->modified(0);
    $self->file_name($file_name);
    my $buff = "";
    my $mode = ""; # e.g. after encountering "grades", we expect some grades
    my %recognized_modes = ('class'=>1,'preferences'=>1,'categories'=>1,'roster'=>1,
                            'assignments'=>1,'grades'=>1);
    my $mode_is_recognized; # anything not recognized is just preserved without parsing it
    my $one_liner = ""; # Some modes are one-liners.
    my @names; # for use in roster mode
    my $children={};
    eval("require LineByLine;");
    my $mac = LineByLine->new(KEY=>$password,INPUT=>$file_name);
    $self->{AUTHENTICITY} = $mac->authenticity(); # This line has to come before the open(), because otherwise we have the file open twice, and that makes
                                                  # it not work on Windows.
    $self->{HAS_WATERMARK} = ($self->{AUTHENTICITY} ne "bad header");
    open (INFILE,"<$file_name") or return "Cannot open $file_name";
    $self->filehandle(\*INFILE); # Perl idiom for getting a reference to a filehandle, see camel book, p. 249
    $self->lock() or return "Unable to obtain a lock on file $file_name. This can happen if you are running two copies of OpenGrade at once.";
    my $got_class_line = 0; # used for format detection
    LINE: while (<INFILE>) {
        next LINE unless $_ = $mac->strip_line($_); # gets rid of MAC part
        tr/\r/\n/;    # Mac newlines must die.
        chomp;        # Get rid of trailing newline.
        s/\#[^\"]*//; # Get rid of comments.
        s/\s+$//;     # Get rid of trailing whitespace.
        s/^\s+//;     # Get rid of leading whitespace.
        next LINE unless $_;
        $buff = $buff . $_;
        if (substr($buff,-1) ne ",") {
          #print "line: $buff\n";
          if ($buff) {
              if (substr($buff,0,1) ne ".") { #mode line
                  flush_children($self,$children);
                  $buff =~ m/^([a-zA-Z_\-]+)\s*(.*)/;
                  $mode = $1;
                  $children={"."=>$mode};
                  my $tail = $2;
                  $mode = lc($mode);
                  $mode_is_recognized = exists $recognized_modes{$mode};
                  if ($mode=~/^class$/i) {$got_class_line = 1}
                  $one_liner = "";
                  my $children = {}; # for later lines under this mode
                  $tail =~ s/\"//g;
              } # end if mode line
              else { #not mode line
                  $buff =~ m/^\.([a-zA-Z_\-\.\d]+)\s*(.*)/;
                  my ($head,$tail) = ($1,$2);
                  if ($mode eq "grades") {$tail =~ s/\"[^\:]+\:\?\",?//g} # MicroGrade uses ?
                  $head = lc($head);
                  $children->{$head}=$tail;
                  if ($mode eq "assignments") {$self->assignment_list($self->assignment_list.",".$head);}
                  if ($mode eq "categories") {$self->category_list($self->category_list.",".$head);}
              }
              if (!$mode_is_recognized) {
                $self->stuff_unable_to_parse($buff);
              }
          } # end if not an empty line
          $buff = "";
        } # end if done with line plus continuation lines
    } # end loop over input lines
    if (!$got_class_line) {return "The file does not appear to be a gradebook file, does not contain a class record."}
    flush_children($self,$children);
    $self->use_defaults_for_assignments();
    #close INFILE; # Used to close after reading. No longer do this, because we want locking.
    my $err = $self->misc_initialization();
    if ($err ne '') {return $err}
    return $self;
}

# This gets called when we create an empty new GradeBook object from scratch, and also after we read
# in a file. Returns a null string, or a string describing any error it found.
# If the optional argument $minimal is set to true, then we only do a minimal amount
# of initialization; this is used the user does an undo operation, and the gradebook is
# reset to a value stored in a JSON string. Doing it with $minimal set to true is completely
# harmless, won't set anything unless it was undefined.
sub misc_initialization {
    my $self = shift;
    my $minimal = 0;
    if (@_) {$minimal = shift}

    if (!defined $self->preferences()) {$self->preferences(Preferences->new(GB=>$self))}
    unless (ref($self->preferences()) eq 'Preferences') {$self->preferences(Preferences->new())} # happens when parsing old format
    if (!defined $self->types()) {$self->set_default_types()}
    if (!defined $self->{WROTE_TILDE_FILE}) {$self->{WROTE_TILDE_FILE}=0}

    unless($minimal) {

      # check for self-consistency:
      my $r = $self->category_array();
      my @c1 = sort @$r;
      my $r = $self->categories_private_method();
      my @c2 = sort keys %$r;
      if (join(',',@c1) ne join(',',@c2)) {return "category_order not consistent with keys of categories"}

      # Set up the undo stack:
      set_up_undo();
      $self->{UNDO_STACK} = [{'state'=>jsonify_ugly($self->hashify())}];
      $self->{IN_UNDO} = 0;
    }


    return '';
}

# The GUI needs to change the Edit : Undo menu item when the undo stack changes. This callback provides for that.
sub undo_callback {
  my $self = shift;
  if (@_) {$self->{UNDO_CALLBACK} = shift}
  return $self->{UNDO_CALLBACK};
}

sub revert {
  my $self = shift;
  my $a = $self->{UNDO_STACK};
  return if @$a<1;
  $self->{UNDO_STACK} = [$a->[0]];
  my $a = $self->{UNDO_STACK};
  my $stuff = $a->[0];
  my $json = $stuff->{'state'};
  return unless $json;
  my $h;
  eval {$h = JSON::from_json($json)};
  if (!defined $h) {print "bad json syntax in GradeBook::revert, didn't revert"; return}
  $self->{PREVENT_UNDO} = 1;
  $self->set_from_hash($h);
  $self->misc_initialization(1);
  $self->{PREVENT_UNDO} = 0;
  if (ref($self->undo_callback()) eq 'CODE') {my $c=$self->undo_callback(); &$c($self,'',{},'revert')}
}

sub undo {
  my $self = shift;
  my $a = $self->{UNDO_STACK};
  return if @$a<2 || (@$a==2 && $self->{UNDO_STACK_OVERFLOWED});
  my $undone = pop @$a;
  my $stuff = $a->[-1];
  my $completed = 0;
  if (exists $stuff->{'set_grades_on_assignment_shortcut'}) {
    my $shortcut = $undone->{'set_grades_on_assignment_shortcut'};
    $self->{PREVENT_UNDO} = 1;
    $self->set_grades_on_assignment(CATEGORY=>$shortcut->{'cat'},ASS=>$shortcut->{'ass'},GRADES=>{$shortcut->{'student'}=>$shortcut->{'old'}});
    $self->{PREVENT_UNDO} = 0;
    $completed = 1;
  }
  if (exists $stuff->{'add_assignment_shortcut'}) {
    my $shortcut = $undone->{'add_assignment_shortcut'};
    $self->{PREVENT_UNDO} = 1;
    #print STDERR "doing shortcut for undo, $shortcut->{'cat'},$shortcut->{'ass'}\n";
    $self->delete_assignment((CATEGORY=>$shortcut->{'cat'}).".".(ASS=>$shortcut->{'ass'}));
    $self->{PREVENT_UNDO} = 0;
    $completed = 1;
  }
  if (!$completed) { # not an undo of a method that has a shortcut
    my $json = $stuff->{'state'};
    return unless $json;
    my $h;
    eval {$h = JSON::from_json($json)};
    if (!defined $h) {print "bad json syntax in GradeBook::undo, didn't undo"; return}
    $self->{PREVENT_UNDO} = 1;
    $self->set_from_hash($h);
    $self->misc_initialization(1);
    $self->{PREVENT_UNDO} = 0;
  }
  if (ref($self->undo_callback()) eq 'CODE') {
    my $sub = $undone->{'sub'};
    my $c=$self->undo_callback();
    &$c($self,$sub,recommend_gui_stuff($sub),'undo');
  }
}

# returns undef normally, error message if there's an error
sub user_write_api {
  my $self = shift;
  my $method = shift; # string; must be one of the ones in @user_api_functions
  my $json_args = shift; # JSON representation of the arguments to the method as an array
  my $valid_user_api_method = 0;
  foreach my $m(@user_write_api_functions) {
    $valid_user_api_method = 1 if $m eq $method;
  }  
  return "method $method is not in the list of valid user-write API methods for the GradeBook class, which consists of: ".join(' ',@user_write_api_functions)
       unless $valid_user_api_method;
  my $args = eval {JSON::from_json($json_args)};
  return "arguments $json_args do not consititute a valid JSON string" unless defined $args;
  return "arguments $json_args do not represent a JSON array, i.e., are not a list surrounded by []" unless ref($args) eq 'ARRAY';
  my $method_ref = *{$method};
  return "method $method is not in the symbol table of GradeBook" unless defined $method_ref;
  &$method_ref($self,@$args);
  return '';
}

{
  # Set up undo functionality.
  my $done = 0;
  my %has_shortcut = ('set_grades_on_assignment'=>1,'add_assignment'=>1);
  sub set_up_undo {
    # We set $gb->{PREVENT_UNDO}=1 initially when we create a gb object, because any calls to write methods are just initializations, not user-initiated edits.
    # We only set $gb->{PREVENT_UNDO}=0 when the user clicks on a menu or types in a score, as detected by BrowserWindow::menu_bar() Roster::key_pressed_in_scores().
    if (!$done) {
      $done = 1;
      # The following is for efficiency. If it's a read-write method, and we're not calling it with enough args to be using it as a write method,
      # don't bother checking whether it was modified.
      my %min_args_if_writing = (
        'preferences'=>1, 'category_properties'=>2, 'assignment_properties'=>2, 'dir'=>1, 'assignment_array'=>1, 'assignment_list'=>1, 'category_list'=>1,
        'class_data'=>2, 'types'=>1
      );
      foreach my $name(@user_write_api_functions) {
        my $c = *{$name}{CODE};
        defined $c or die "Undo functionality can't be set up for nonexistent method $name in GradeBook::set_up_undo().";
        *{$name} = sub{
          my $self = @_[0];
          my $is_writing = ! exists $min_args_if_writing{$name} || @_>=$min_args_if_writing{$name}+1; # 1 extra for $self
          my $could_save = $is_writing && ! $self->{PREVENT_UNDO} && ! $self->{IN_UNDO};
          my $a = $self->{UNDO_STACK};
          my $result;
          my @result;
          if ($could_save ) {
            $self->{IN_UNDO} = 1;
          }
          # special-case set_grades_on_assignment for efficiency
          my $shortcut = 0;
          my %shortcut_data = ();
          # Check whether it's a method on the list of those that we might be able to do a shortcut on. Even if is, that doesn't
          # mean we will actually do the shortcut method. If we actually do, we set the $shortcut flag.
          if ($could_save && exists $has_shortcut{$name}) {
            if ($name eq 'set_grades_on_assignment') {
              # Shortcut for setting exactly one grade (which is what happens when the use is using the GUI).
              my @x = @_;    # $gb,%args
              shift @x;      # gobble $gb
              my %x = (@x,); # args
              my $grades = $x{GRADES};
              if (scalar(keys %$grades)==1) {
                $shortcut = 1;
                my @k = keys (%$grades);
                $shortcut_data{'student'} = $k[0];
                $shortcut_data{'cat'} = $x{CATEGORY};
                $shortcut_data{'ass'} = $x{ASS};
                $shortcut_data{'old'} = $self->get_current_grade($shortcut_data{'student'},$shortcut_data{'cat'},$shortcut_data{'ass'});
              }
            }
            if ($name eq 'add_assignment') {
              my @x = @_;     # $gb, %args
              shift @x;       # gobble $gb
              my %x = (@x,);  # args
              $shortcut = 1;
              $shortcut_data{'cat'} = $x{CATEGORY};
              $shortcut_data{'ass'} = $x{ASS};
            }
          }
          if (wantarray) {@result = &$c(@_)} else {$result = &$c(@_)}
          if ($could_save ) {
            my $changed;
            my $json;
            if ($shortcut) {
              $changed = 1;
            }
            else {
              $json = jsonify_ugly($self->hashify());
              $changed = ($json ne $a->[-1]->{'state'}); # In the case where $a->[-1]->{'state'} is null, we decide it's changed, which is fine.
            }
            if (@$a==0 || $changed) {
              # if changing the structure of the $undo hash below, change it above in misc_initialization() as well
              my $undo = {'state'=>$json,'sub'=>$name,'describe'=>$self->describe_operation($name,@_)}; # $json may be undef if it's set_grades_on_assignment
              if ($shortcut) {
                $undo->{"${name}_shortcut"} = \%shortcut_data;
              }
              push @$a,$undo; 
              if (@$a>100) {splice @$a,1,1; $self->{UNDO_STACK_OVERFLOWED}=1} # prevent undo stack from growing arbitrarily large
              if (ref($self->undo_callback()) eq 'CODE') {my $c=$self->undo_callback(); &$c($self,$name,recommend_gui_stuff($name),'save')}
            }
            $self->{IN_UNDO} = 0;
          }
          if (wantarray) {return @result} else {return $result}
        };
      }
    }
  }
}

sub recommend_gui_stuff {
  my $operation = shift;
  return {
    'add_student'=>{'roster_refresh'=>1},
    'drop_student'=>{'roster_refresh'=>1},
    'reinstate_student'=>{'roster_refresh'=>1},
####    'set_grades_on_assignment'=>{'roster_refresh'=>1}, # special-cased in BrowserWindow
    'delete_assignment'=>{'roster_refresh'=>1,'assignments_refresh'=>1},
    'add_assignment'=>{'roster_refresh'=>1,'assignments_refresh'=>1},
    'delete_category'=>{'roster_refresh'=>1,'assignments_refresh'=>1},
    'set_all_category_properties'=>{'roster_refresh'=>1,'assignments_refresh'=>1},
    'add_category'=>{'roster_refresh'=>1,'assignments_refresh'=>1},
  }->{$operation};
}

sub describe_operation {
  my $self = shift;
  my $sub = shift; # see list in set_up_undo
  my $d = $sub;
  my %args = (
    'add_student'         => ['who'],
    'drop_student'         => ['who'],
    'reinstate_student'    => ['who'],
    'set_student_property' => ['who','property','value'],
  );
  my $r = $args{$sub};
  if (defined $r) {
    my %a;
    my $i=1; # skip 0, which is $gb
    foreach my $a(@$r) {
      $a{$a} = @_[$i++];
    }
    if (exists $a{'property'} && exists $a{'value'}) {$d = $d . "$a{property}=$a{value}"}
    if (exists $a{'who'}) {my $who = $a{'who'};my ($first,$last) = $self->name($who); $d = $d . " for $first $last"}
  }
  $d =~ s/_/ /g;
  return $d;
}

sub preferences {
    my $self = shift;
    if (@_) {$self->{PREFERENCES} = shift}
    return $self->{PREFERENCES};
}

sub file_name {
    my $self = shift;
    if (@_) {
      $self->{FILE_NAME} = shift;
    }
    return $self->{FILE_NAME};
}

sub modified {
    my $self = shift;
    if (@_) {$self->{MODIFIED} = shift}
    return $self->{MODIFIED};
}

sub password {
    my $self = shift;
    if (@_) {$self->{PASSWORD} = shift}
    return $self->{PASSWORD};
}

sub pref {
    my $self = shift;
    my $what = shift;
    my $it = ($self->preferences_private_method())->{$what};
    $it =~ m/^\"([^\"]*)\"$/;
    return $1;
}

sub boolean_pref {
    my $self = shift;
    my $what = shift;
    return ($self->pref($what) eq "true");
}


=head3 stuff_unable_to_parse()

A read-write method. Returns undef if it has never been set. The write method
appends the argument, plus a newline, to what's already there.

The idea here is to ensure forward-compatibility by preserving
any sections in the gradebook file that we were unable to interpret.

=cut

sub stuff_unable_to_parse {
    my $self = shift;
    if (@_) {
      my $new_stuff = shift;
      if (! exists $self->{STUFF_UNABLE_TO_PARSE}) {$self->{STUFF_UNABLE_TO_PARSE} = ''}
      $self->{STUFF_UNABLE_TO_PARSE} = $self->{STUFF_UNABLE_TO_PARSE} . "$new_stuff\n";
    }
    if (! exists $self->{STUFF_UNABLE_TO_PARSE}) {return undef}
    return $self->{STUFF_UNABLE_TO_PARSE};
}

=head3 set_grades_on_assignment()

Add new grades. Any preexisting ones are retained.
      CATEGORY => "",
      ASS => "",
      GRADES => {}, 
The hash reference in GRADES has student keys as its keys, scores as its values.

=cut

sub set_grades_on_assignment {
    my $self = shift;
    my %args = (
      CATEGORY => "",
      ASS => "",
      GRADES => {}, # hash ref
      @_,
    );
    my $category = $args{CATEGORY};
    my $ass = lc($args{ASS});
    my $new_grades = $args{GRADES};
    my $grades = $self->grades_private_method();
    while (my ($student,$score) = each(%$new_grades)) {
        my $c = $student.".".$category;
        my $record = "\"$ass:$score\"";
        $score=~s/x$//i; # get rid of trailing x that just means extra credit
        if (exists($grades->{$c})) {
            $grades->{$c} = set_property($grades->{$c},$ass,$score);
        }
        else {
            $grades->{$c} = $record;
        }
    }
    $self->grades_private_method($grades);
}

=head3 drop_student()

Takes one argument, the key of the student to be dropped.

=cut

sub drop_student {
    my $self = shift;
    my $who = shift; # student's key
   $self->set_student_property($who,"dropped","true");
}

=head3 reinstate_student()

Takes one argument, the key of the student to be reinstated.
If the key is a null string, does nothing.

=cut


sub reinstate_student {
    my $self = shift;
    my $who = shift; # student's key
    $self->set_student_property($who,"dropped","false") unless $who eq "";
}



=head3 set_student_property()

  set_student_property($key,$property,$value)

=cut

sub set_student_property {
    my $self = shift;
    my $who = shift; # student's key
    my $prop = shift;
    my $value = shift;
    my $students = $self->roster_private_method();
    $students->{$who} = set_property($students->{$who},$prop,$value);
    $self->roster_private_method($students);
}


=head3 get_student_property()

  get_student_property($key,$property)

=cut

sub get_student_property {
    my $self = shift;
    my $who = shift; # student's key
    my $prop = shift;
    return get_property($self->roster_private_method()->{$who},$prop);
}

=head3 list_defined_student_properties()

Returns ($a,$h), where $a is a ref to an array containing
all the student properties that have been defined so far,
and $h is a hash whose keys are the elements of $a. As soon as a property has been defined for one student,
it's considered to be defined in general.
The optional argument is a hash ref whose keys are properties that should be not be returned;
if defaults to {"dropped"=>1}.
The order of @$a is guaranteed to be  "last","first","id", and "dropped,"
followed by any others, in alphabetical order.
The second optional argument, is passed to student_keys.

=cut

sub list_defined_student_properties {
  my $self = shift;
  my $ignored = {"dropped"=>1};
  if (@_) {$ignored = shift}
  my $criteria = ''; # defined in student_keys()
  if (@_) {$criteria = shift}
  my @standard = ('last','first','id','dropped');
  my %found = ();
  my @result;
  foreach my $standard(@standard) {
    $found{$standard} = 1;
    push @result,$standard unless exists $ignored->{$standard};
  }
  my @students = $self->student_keys($criteria);
  my $r = $self->roster_private_method();
  foreach my $who(@students) {
    my %k = comma_delimited_to_hash($r->{$who});
    foreach my $k(keys %k) {
      push @result,$k unless exists $ignored->{$k} || exists $found{$k} || !$k; # final test on $!$k is because of possible bug in comma_delimited_to_hash
      $found{$k} = 1;
    }
  }
  my %h = {};
  foreach my $x(@result) {$h{$x}=1}
  return (\@result,\%h);
}

=head3 get_property()

Avoid using this routine, and use get_property2() instead.
Same as get_property2(), but
returns a null string if the parameter doesn't exist.
This was bad design, since it also
returns a null string if the parameter has a null-string value -- yech.
This is only here in order to keep from breaking old code that depends
on this behavior.

=cut

sub get_property {
    my @args = @_;
    my $x = get_property2(@args);
    if (defined $x) {
      return $x;
    }
    else {
      return '';
    }
}


=head3 get_property2()

Given a string like "x:1","y:2", and a param like "x", return 1.
First argument is the string. Second argument is the key, e.g., "x".
Returns undef if the parameter doesn't exist. This is a plain function,
not a GradeBook method.

=cut

sub get_property2 {
    my $x = shift;
    my $key = shift;

    if ($x eq '') {return undef} # for efficiency

    # for efficiency, do the common, simple case first
    my $item_with_no_commas = '("\w+:[^",:]*")';
    if ($x=~/^($item_with_no_commas,)*$item_with_no_commas$/o) {
      if ($x =~ /"$key:([^",:]*)"/) {return $1} else {return undef};
    }
    else {
      return get_property2_slow($x,$key);
    }
}

sub get_property2_slow {
    my $x = shift;
    my $key = shift;

    my @p = split_comma_delimited_values($x);
    foreach my $p(@p) {
        $p =~ m/\"?([^\:]+)\:([^\"]*)\"?/o;
        my ($a,$b) = ($1,$2);
        if ($a eq $key) {return $b}
    }
    return undef;

}

sub get_property2_fast {
}

=head3 delete_property()

Given a string like "x:1","y:2", and a param like "x", delete the part
of the string referring to x.
First argument is the string. Second argument is the key, e.g., "x".
Returns the original string if the parameter doesn't exist. This is a plain function,
not a GradeBook method.

=cut

sub delete_property {
    my $x = shift;
    my $key = shift;
    $x =~ s/\"$key\:([^\"]*)\"\,?//g;
    $x =~ s/\,$//; # If the property was the last one, we need to delete the comma before it.
    return $x;
}

=head3 property_exists()

Given a string like "x:1","y:2", and a param like "x", tells whether
x occurs in the string.

=cut

sub property_exists {
  return defined get_property2(@_);
}

=head3 get_properties()

Given a hash with keys like "x:1","y:2", extract a particular
key, and make it into a hash ref like {x=>1, y=>2}.

=cut

sub get_properties {
    my $self = shift;
    my $which = shift;
    my $c = shift;
    my @p = split_comma_delimited_values($c->{$which});
    my %result = ();
    foreach my $p(@p) {
        $p =~ m/\"?([^\:]+)\:([^\"]*)\"?/;
        my ($a,$b) = ($1,$2);
        $result{$a} = $b;
    }
    return \%result;
}


=head3 set_property()

  set_property($list,$property,$value)

This just returns a modified version of the original list -- doesn't modify it in place.

=cut

sub set_property {
    my $stuff = shift; # .foo "bar:37","glub:92"
    my $prop = shift;
    my $value = shift;
    if ($stuff =~ m/\"$prop\:[^\"]*\"/) {
        $stuff =~ s/\"$prop\:[^\"]*\"/\"$prop\:$value\"/;
    }
    else {
        $stuff = $stuff . ",\"" . $prop . ":" . $value . "\"";
    }
    return $stuff;
}


=head3 heritable_from_cat()

Some properties are inherited by assignments
from the parent category. See use_defaults_for_assignments.
This is a plain old function, not a method for GradeBook objects.
See also list_properties_heritable_from_cat().

=cut

sub heritable_from_cat {
  my $what = shift;
  return ($what eq "max" || $what eq "ignore");
}

sub list_properties_heritable_from_cat {
  return ('max','ignore');
}

=head3 use_defaults_for_assignments()

Goes through the list of assignments, and supplies defaults
from the parent category's properties.

=cut


sub use_defaults_for_assignments {
    my $self = shift;
    my @a = split(",",$self->assignment_list());
    my @c = split(",",$self->category_list());
    foreach my $c(@c) {
        my $cp = $self->category_properties($c);
        foreach my $p(keys(%$cp)) {
            if (!heritable_from_cat($p)) {
                delete($cp->{$p});
            }
        }
        my %cp = %$cp;
        foreach my $a(@a) {
            if (first_part_of_label($a) eq $c) {
                my $ap = $self->assignment_properties($a);
                my %ap = %$ap;
                my %old_ap = %ap;
                %ap = (%cp,%ap); # merge the hashes
                if (hashes_not_equal(\%old_ap,\%ap)) {
                  # Without the test above, this was a huge pig in terms of performance, due to undo functionality.
                  $self->assignment_properties($a,\%ap);
                }
            }
        }
    }
}

# The follownig assumes that all values are scalars, dies if they're not.
sub hashes_not_equal {
  my $h1 = shift; # hash ref
  my $h2 = shift; # hash ref
  my @k1 = keys %$h1;
  my @k2 = keys %$h2;
  if (@k1 != @k2) {return 1} # test equality of number of keys first, since it's efficient
  @k1 = sort @k1;
  @k2 = sort @k2;
  for (my $i=0; $i<@k1; $i++) {
    if ($k1[$i] ne $k2[$i]) {return 1}
    my $v1 = $h1->{$k1[$i]};
    my $v2 = $h2->{$k2[$i]};
    die "non-scalar value in hashes_not_equal" if ((ref $v1) || (ref $v2));
    if ($v1 ne $v2) {return 1} # string comparison works for both numbers and strings
  }
  return 0;
}

=head3 strip_redundant_properties

First argument is the assignment key. Second argument is its list of properties.
This is meant for use only when writing the gradebook file. If an assignment
has properties that are the defaults for its category, we strip those out.
All this does is make the gradebook file a little cleaner and more readable.
When we read the file back in, the defaults are re-applied
by use_defaults_for_assignments().

=cut

sub strip_redundant_properties {
  my $self = shift;
  my $key = shift;
  my $props = shift;
  my ($cat,$ass) = $self->split_cat_dot_ass($key);
  foreach my $prop(list_properties_heritable_from_cat()) {
    my $default = $self->category_property2($cat,$prop);
    my $actual = get_property2($props,$prop);
    if ((defined $actual) && ($actual eq $default)) {
      $props = delete_property($props,$prop);
    }
  }
  return $props;
}

=head3 split_cat_dot_ass()

Takes one argument, of the form "cat.ass", and returns a list
(cat,ass).

=cut

sub split_cat_dot_ass {
  my $self = shift;
  my $x = shift;
  $x =~ m/^([^.]*)\.([^.]*)$/;
  my ($cat,$ass) = ($1,$2);
  return ($cat,$ass);
}

=head3 student_keys()

Returns an array, sorted in alphabetical order. Bug:
probably doesn't work right when one student's name is
the same as the beginning of another's.

 Optional argument:
   ""          only return active students (default)
   "all"       return all students
   "dropped"   return a list of dropped students

=cut

sub student_keys {
    my $self = shift;
    my $criteria = "";
    if (@_) {$criteria = shift}
    my $h = $self->roster_private_method();
    my @raw = sort keys %$h;
    
    my @s = ();
    foreach my $s(@raw) {
        my $is_dropped = "";
        my $info = $h->{$s};
        my $is_dropped = get_property($info,"dropped") eq "true";
        if ($is_dropped && $criteria ne "" or !$is_dropped && $criteria ne "dropped") {
            push @s,$s;
        }
    }

    return @s;
}

sub first_part_of_label {
    my $x = shift;
    $x =~ m/^([^\.]*)\./;
    return $1;
}

sub second_part_of_label {
    my $x = shift;
    $x =~ m/^([^\.]*)\.([^\.]*)/;
    return $2;
}

=head3 get_current_grade()

get_current_grade($student_key,$cat,$ass)

If the category might be nonnumeric, and want to use the result as a number, don't use this,
use get_current_grade_as_number instead.

=cut

# Returns null if no grade recorded.
sub get_current_grade {
    my $self = shift;
    my $student_key = shift;
    my $cat = shift;
    my $ass = shift;
    my $h = $self->grades_private_method();
    if (!exists($h->{$student_key.".".$cat})) {return ""}
    my $list = $h->{$student_key.".".$cat};
    return get_property($list,$ass);
}

=head3 get_current_grade_as_number()

get_current_grade_as_number($student_key,$cat,$ass)

=cut

# Returns null if no grade recorded.
sub get_current_grade_as_number {
  my $self = shift;
  my $student_key = shift;
  my $cat = shift;
  my $ass = shift;
  my $h = $self->grades_private_method();
  if (!exists($h->{$student_key.".".$cat})) {return ""}
  my $list = $h->{$student_key.".".$cat};
  my $type = $self->category_property2($cat,'type');
  my $grade = get_property($list,$ass);
  if ($type ne 'numerical') {
    my $r = $self->types()->{'data'}->{$type}->{'value'}; # hash ref
    if (ref $r && exists $r->{$grade}) {
      $grade = $r->{$grade};
    }
  }
  return $grade;
}

=head3 weights_enabled()

Shouldn't normally be necessary to call this routine, except
when setting up a new category to see if we need to ask them
for a weight. It's inefficient, so avoid calling it.
Return values:
  0 unweighted
  1 weighted
  2 no categories have been put in yet, so could be either

=cut

sub weights_enabled {
    my $self = shift;
    my $h = $self->categories_private_method();
    my $any_cats = 0;
    foreach my $c(keys(%$h)) {
        if (get_property($h->{$c},"weight") ne "") {return 1}
        $any_cats = 1;
    }
    if (!$any_cats) {return 2}
    return 0;
}

# Returns 100 if this weights are not enabled. Otherwise
# returns the weight.
sub category_weight {
    my $self = shift;
    my $which = shift;
    my $h = $self->categories_private_method();
    if (! exists($h->{$which})) {return ""}
    my $w = get_property($h->{$which},"weight");
    if ($w ne "") {return $w}
    return 100;
}

=head3 category_name_singular()

Takes one argument, the category key.

=cut

sub category_name_singular {
    my $self = shift;
    my $which = shift;
    my $h = $self->categories_private_method();
    if (! exists($h->{$which})) {return ""}
    my $n = get_property($h->{$which},"catname");
    $n =~ m/([^\,]+),(.*)/;
    my ($sing,$pl) = ($1,$2);
    return $sing || $which;
}

=head3 category_name_plural()

Takes one argument, the category key.

=cut

sub category_name_plural {
    my $self = shift;
    my $which = shift;
    my $h = $self->categories_private_method();
    if (! exists($h->{$which})) {return ""}
    my $n = get_property($h->{$which},"catname");
    $n =~ m/([^\,]+),(.*)/;
    my ($sing,$pl) = ($1,$2);
    return $pl || $which;
}

=head3 category_exists()

Takes one argument, the category key.

=cut

sub category_exists {
    my $self = shift;
    my $which = shift;
    my $h = $self->categories_private_method();
    return exists($h->{$which});
}

=head3 assignment_exists()

Takes one argument, cat.assmt.

=cut

sub assignment_exists {
    my $self = shift;
    my $which = shift;
    my $h = $self->assignments_private_method();
    return exists($h->{$which});
}

=head3 category_property_boolean()

Arguments are category, property. This is a read-only method.

=cut

sub category_property_boolean {
  my $self = shift;
  my $x = $self->category_property(@_);
  return (lc($x) eq 'true');
}

=head3 category_max()

For nonnumerical ones, gives the highest numerical equivalent.

=cut

sub category_max {
  my $self = shift;
  my $cat = shift;
  my $max = $self->category_property2($cat,'max');
  my $type = $self->category_property2($cat,'type');
  if ($type ne 'numerical') {
    my $r = $self->types()->{'data'}->{$type}->{'value'}; # hash ref
    if (ref $r) {
      my %h = reverse %$r;
      my @l = sort keys %h;
      $max = @l[-1];
    }
  }
  return $max;
}

=head3 category_property2()

To get a property, arguments are category, property; returns undef
if there's no such property.
To set a property, arguments are category, property, value.
For type, returns numerical if type isn't actually specified in gb file.
To find max in a category, use category_max(), which returns the right numerical maximum for nonnumerical types.

=cut

sub category_property2 {
    my $self = shift;
    my $which = shift;
    my $prop = shift;
    my $h = $self->categories_private_method();
    if (!exists($h->{$which})) {return undef}
    if (@_) {
      my $value = shift;
      $h->{$which} = set_property($h->{$which},$prop,$value);
    }
    my $p = get_property2($h->{$which},$prop); 
    if ($prop eq 'type' && !$p) {$p='numerical'}
    return $p;
}

=head3 category_property()

Avoid using this. Use category_property2() instead. This is only
here for the sake of old code that depends on receiving a null
string when the property isn't found.

=cut

sub category_property {
    my $self = shift;
    my $which = shift;
    my $prop = shift;
    my $h = $self->categories_private_method();
    if (!exists($h->{$which})) {return ""}
    if (@_) {
      my $value = shift;
      $h->{$which} = set_property($h->{$which},$prop,$value);
    }
    return get_property($h->{$which},$prop);
}

sub category_properties_comma_delimited {
    my $self = shift;
    my $which = shift;
    my $h = $self->categories_private_method();
    return $h->{$which};
}

# Get or set the properties of the category as a hash reference.
# category must already exist.
sub category_properties {
    my $self = shift;
    my $which = shift;
    if (@_) {
        my $h = shift;
        my $x = hash_to_comma_delimited($h);
        my $c = $self->categories_private_method();
        $c->{$which} = $x;
        $self->categories_private_method($a);
    }
    return $self->get_properties($which,$self->categories_private_method());
}


=head3 add_assignment()

 add_assignment {
        CATEGORY => "",
        ASS => "",          # assmt name only, not category.assmt
        PROPERTIES=>"",     # comma-delimited list
        COMES_BEFORE=>"",   # if null, put it at end of list for this category
        @_,
    );

=cut

sub add_assignment {
    my $self = shift;
    my %args = (
        CATEGORY => "",
        ASS => "",          # assmt name only, not category.assmt
        PROPERTIES=>"",     # comma-delimited list
        COMES_BEFORE=>"",   # if null, put it at end of list for this category
        @_,
    );
    local $Words::words_prefix = "add_assignment";
    my $category = lc($args{CATEGORY});
    my $name = lc($args{ASS});
    my $properties = $args{PROPERTIES};
    my $comes_before = $args{COMES_BEFORE};
    $name =~ s/[ :"]/_/g; # Otherwise you lose data!
    my @a = split(",",$self->assignment_list());
    my $comes_before_index = -999;
    if (!@a) {
      $comes_before_index=0
    }
    else {
    if ($comes_before) {
        for (my $j=0; $j<=$#a; $j++) {
            if ($a[$j] eq $category.".".$comes_before) {$comes_before_index=$j}
        }
    }
    else {
        # Typically this category already has assignments, so we add this one after them:
        for (my $j=0; $j<=$#a; $j++) {
            my $c = $a[$j];
            $c =~ m/([^\.]*)\.([^\.]*)$/;
            if ($1 eq $category) {$comes_before_index=$j+1}
        }
        # This category doesn't have any assignments yet; this will be the first one we add to it:
        if ($comes_before_index == -999) {
            my $cl = $self->category_list();
            $comes_before_index = $#a+1;
               # ...If we can't find any assignments that come after it, it's the last. This happens
               # if it's the last assignment in the last category, or if all the later categories are empty.
            for (my $j=$#a; $j>=0; $j--) {
              my $c = $a[$j];
              $c =~ s/\..*//;
              if ($cl =~ m/$category\,([^,]+\,)*$c/) {$comes_before_index=$j}
            }

        }
    }
    }
    if ($comes_before_index == -999) {return w('where_to_insert')}
    for (my $j=$#a+1; $j>=$comes_before_index+1; $j--) {
        $a[$j] = $a[$j-1];
    }
    my $full_name = $category.".".$name;
    my $h = $self->assignments_private_method();
    if (exists($h->{$full_name})) {return (sprintf w('exists'),$name)}
    $a[$comes_before_index] = $full_name;
    $self->assignment_list(@a);
    $h->{$full_name} = $properties;
    $self->assignments_private_method($h);
    $self->use_defaults_for_assignments();
    return "";
}

sub delete_category {
    my $self = shift;
    my $cat = shift;
    my $r = $self->array_of_assignments_in_category($cat);
    foreach my $ass(@$r) {
      $self->delete_assignment("$cat.$ass");
    }
    my $r = $self->category_array();
    $self->category_list(join(',',(grep {$_ ne $cat} @$r)));
    my $h = $self->categories_private_method();
    delete $h->{$cat};
    $self->categories_private_method($h);
    my $h = $self->hashify();
    delete $h->{'grades'}->{$cat};
    $self->set_from_hash($h);
    $self->misc_initialization(1);
}

=head3 delete_assignment()

 $gb->delete_assignment("exam.1");

Returns null on success.

=cut

sub delete_assignment {
    my $self = shift;
    my $key = shift;

    my $h = $self->assignments_private_method();
    if (!exists($h->{$key})) {return "Assignment $key does not exist."}
    delete $h->{$key};
    $self->assignments_private_method($h);

    my @a = $self->assignment_array();
    my $victim = $#a+999;
    for (my $i=0; $i<=$#a; $i++) {
      if ($a[$i] eq $key) {$victim=$i; last}
    }
    for (my $i=$victim; $i<=$#a-1; $i++) {
      $a[$i] = $a[$i+1];
    }
    $#a = $#a-1; # reduce size by 1
    @a = $self->assignment_array(@a);

    $key =~ m/^([^.]*)\.([^.]*)$/;
    my $category = $1;
    my $which = $2;
    my $g = $self->grades_private_method();
    foreach my $student_and_cat(keys %$g) {
      if ($student_and_cat =~ m/$category$/) {
        $g->{$student_and_cat} =~ s/\"$which\:[^"]*\"\,?//;
        $g->{$student_and_cat} =~ s/\,$//;
      }
    }
    $self->grades_private_method($g);

    return "";
}



=head3 assignment_name()

If given only one argument, it's assumed to be category.assignment.
If given two arguments, they're assumed to be the category and the assignment.

=cut

sub assignment_name {
  my $self = shift;
  my $x = shift;
  my ($cat,$ass);
  if (@_) {
    $cat = $x;
    $ass = shift;
  }
  else {
    $x =~ m/(.*)\.(.*)/;
    ($cat,$ass) = ($1,$2);
  }
  if ($self->assignment_property_exists("$cat.$ass",'name')) {
    return $self->assignment_property("$cat.$ass",'name');
  }
  else {
    return $self->default_assignment_name($cat,$ass);
  }
}


=head3 default_assignment_name()

Arguments are the category and the assignment. This
returns the name the assignment would have simply based on
its category and database key, regardless of whether it has
a "name" property. It would be a bug to call this routine just
to find out a name to display -- that's what assignment_name()
is for.

=cut

sub default_assignment_name {
  my $self = shift;
  my $cat = shift;
  my $ass = shift;
  my $cat_name = $self->category_name_singular($cat);
  if (!$self->category_property_boolean($cat,'single')) {
    return "$cat_name $ass";
  }
  else {
    return $cat_name;
  }
}


=head3 rekey_assignment()

 $gb->rekey_assignment($category,$old,$new);

Returns a null string on success. This only changes the database key.
If the assignment has a "name" tag, then the display name is unaffected.
If the assignment doesn't have a "name" tag, then the display name is
affected.

=cut

sub rekey_assignment {
    my $self = shift;
    my $category = shift;
    my $old = shift;
    my $new = shift;

    my $new_key = $category.".".$new;
    my $old_key = $category.".".$old;
    my $h = $self->assignments_private_method();
    if ($new_key ne $old_key && exists($h->{$new_key})) {return "Assignment $new already exists"}
    my $stuff = $h->{$old_key};
    delete $h->{$old_key};
    $h->{$new_key} = $stuff;
    $self->assignments_private_method($h);

    my @a = $self->assignment_array();
    for (my $i=0; $i<=$#a; $i++) {
      if ($a[$i] eq $old_key) {$a[$i]=$new_key}
    }
    @a = $self->assignment_array(@a);

    my $g = $self->grades_private_method();
    foreach my $key(keys %$g) {
      if ($key =~ m/$category$/) {
        $g->{$key} =~ s/$old\:/$new\:/;
      }
    }
    $self->grades_private_method($g);

    return "";
}

=head3 assignment_property()

First argument is cat.assmt.
Second argument is name of property.
This is a read-only method.
If you're going to extract more than one property, it's
more efficient to call assignment_properties() rather
than this routine.

=cut

sub assignment_property {
    my $self = shift;
    my $which = shift;
    my $prop = shift;
    my $h = $self->assignments_private_method();
    if (!exists($h->{$which})) {return ""}
    return get_property($h->{$which},$prop);
}

=head3 assignment_property_exists()

Like assignment_property(), but tells whether the
property exists.

=cut

sub assignment_property_exists {
    my $self = shift;
    my $which = shift;
    my $prop = shift;
    my $h = $self->assignments_private_method();
    if (!exists($h->{$which})) {return 0}
    return defined get_property2($h->{$which},$prop);
}

=head3 assignment_properties()

Get or set the properties of the assignment as a hash reference.
First argument is cat.assmt. Optional second argument is 
hash ref.

=cut

sub assignment_properties {
    my $self = shift;
    my $which = shift;
    if (@_) {
        my $h = shift;
        my $x = hash_to_comma_delimited($h);
        my $a = $self->assignments_private_method();
        $a->{$which} = $x;
        $self->assignments_private_method($a);
    }
    return $self->get_properties($which,$self->assignments_private_method());
}

=head3 add_student()

                LAST=>"",
                FIRST=>"",
                KEY=>"",
                ID=>"",

Returns ($new_key,$error). You can provide the key,
the last and first names, or both.


=cut


sub add_student {
    my $self = shift;
    my %args = (
                LAST=>"",
                FIRST=>"",
                KEY=>"",
                ID=>"",
                @_,
                );
    my $last = $args{LAST};
    my $first = $args{FIRST};
    my $key = $args{KEY};
    my $id = $args{ID};
    if ($last eq "" && $first eq "" && $key eq "") {return ""}
    if ($key eq "") {$key = $last."_".$first}
    $key = lc($key);
    $key =~ s/[^a-z\-_]//g;
    $key=~m/_(.*)/;
    $first = $1;
    $key=~m/([^_]*)/;
    $last = $1;
    my $stuff = "";
    if (ucfirst($args{FIRST}) ne ucfirst($first)) {
        $stuff = $stuff . ',"first:' . $args{FIRST} . '"';
    }
    if (ucfirst($args{LAST}) ne ucfirst($last)) {
        $stuff = $stuff . ',"last:' . $args{LAST} . '"';
    }
    if ($id ne "") {
        $stuff = $stuff . ',"id:' . $id . '"';
    }
    $stuff =~ s/^,//;
    my $r = $self->roster_private_method();
    if (exists($r->{$key})) {return ('','already_exists')}
    $r->{$key} = $stuff;
    $self->roster_private_method($r);
    return ($key,'');
}

# given a student's key, returns the id
sub id {
    my $self = shift;
    my $key = shift;
    my $h = $self->roster_private_method();
    if (!exists($h->{$key})) {return ()}
    my $info = $h->{$key};
    return get_property($info,"id");
}

=head3 compare_names()

Given two students' keys, returns a cmp-style comparison of their names,
in alphabetical order by last name. Punctuation gets stripped out, and
case is ignored.

=cut

sub compare_names {
    my $self = shift;
    my $key1 = shift;
    my $key2 = shift;
    my ($first1,$last1) = $self->name($key1);
    my ($first2,$last2) = $self->name($key2);
    $last1 = strip_name($last1);
    $last2 = strip_name($last2);
    my $result;
    if ($last1 ne $last2) {
      $result = $last1 cmp $last2;
    }
    else {
      $first1 = strip_name($first1);
      $first2 = strip_name($first2);
      $result = $first1 cmp $first2;
  	}
    return $result;
}

sub strip_name {
    my $name = shift;
    $name = lc($name);
    $name =~ s/[^\w]//g;
    return $name;
}

=head3 name()

Given the student's key, returns an array containing first and last name.

=cut

sub name {
    my $self = shift;
    my $key = shift;
    my $h = $self->roster_private_method();
    if (!exists($h->{$key})) {return ()}
    my $info = $h->{$key};
    my $first = get_property($info,"first");
    if (!$first) {$key=~m/_(.*)/; $first = $1}
    my $last = get_property($info,"last");
    if (!$last) {$key=~m/([^_]*)/; $last = $1}
    $first = capitalize_name($first);
    $last = capitalize_name($last);
    return ($first,$last);
}

sub capitalize_name {
  my $name = shift;
  # Typically we're just returning ucfirst($name). But in a case like Sun-Yat Sen or Eugene O'Neill, we want other stuff capitalized as well.
  $name = join('-',map {ucfirst($_)} split(/\-/,$name));
  return  join("'",map {ucfirst($_)} split(/\'/,$name));
}

sub flush_children {
    my $self = shift;
    my $h = shift;
    my $what = $h->{"."};
    delete($h->{"."});
    while ( my ($k,$v)=each %$h) {
        $v =~ s/,+/,/g;
        $v =~ s/^,//;
        if ($what eq "grades") {
            # Change keys to lc. Otherwise keys may mismatch in grade records, e.g. Exam:97 rather than exam:97.
          # We only do this for grades. It's not appropriate in general because, for instance, it would lead to
          # letter grades being forced to lower case in the standards section.
          my $lcv = $v;
          while ($v =~ m/(\"[A-Za-z]+\:)/g) {
            my $x = $1;
            my $y = lc($x);
            $lcv =~ s/$x/$y/;
          }
          $v = $lcv;
        }
        $h->{$k} = $v;
    }
    #print "flushing\n";
    #show_hash($what,$h);
    if ($what eq "class") {$self->class_private_method($h);}
    if ($what eq "preferences") {$self->preferences_private_method($h);}
    if ($what eq "categories") {$self->categories_private_method($h);}
    if ($what eq "roster") {$self->roster_private_method($h);}
    if ($what eq "assignments") {$self->assignments_private_method($h);}
    if ($what eq "grades") {$self->grades_private_method($h);}
}

# Change "Newton, Isaac" to "newton_isaac",
#        "Isaac Newton" to "newton_isaac",
#        "Franklin D. Roosevelt" to "roosevelt_franklin_d"
sub name_to_label {
    my $x = shift;
    my ($name,$explicit) = split(/:/,$x);
    my $result = "";
    if ($explicit) {$result= $explicit}
    # lastname, firstname:
    if (!$result) {
        if ($name =~ m/^\s*([^,])\s*,\s*(.*)$/) {
            $result = $1."_".$2;
        }
    }
    # firstname lastname
    if (!$result) {
        my $r = $name;
        $r = reverse($r);
        $r =~ m/^\s*([^\s]+)\s*(.*)$/;
        my ($lastrev,$firstrev) = ($1,$2);
        $firstrev =~ s/\s/_/g;
        $firstrev =~ s/_+$//;
        $firstrev =~ s/^_+//;
        $result = reverse($lastrev)."_".reverse($firstrev);
    }
    # Get rid of all whitespace:
    $result =~ tr/[\s",\.]//;
    $result = lc($result);
    return $result;
}

# pass it a hash ref
sub hash_to_comma_delimited {
    my $h = shift;
    my %h = %$h;
    my $result = "";
    my @k = sort keys(%h); # Sorting never hurts, and sometimes helps.
    foreach my $p(@k) {
        $result = $result . "\"" . $p . ":" . $h{$p} . "\",";
    }
    $result =~ s/,$//;
    return $result;
}

=head3 diff_comma_delimited()

Compares two comma-delimited strings representing hashes.
If they're the same, returns 0. If they differ, returns
an a hash ref in the following format:

{'keys'=>[], 'a'=>{}, 'b'=>{}}

where keys gives an array of the keys on which the hashes
differ, and a and b give refs to the hash representations of
the arguments.

 giving the set of keys on which they differ.
Values are judged to be the equal or unequal based on string
comparison, not numerical comparison, except that if one is
undef and the other isn't, they're considered to be unequal.

=cut

sub diff_comma_delimited {
  my ($a,$b) = @_;
  if (defined $a xor defined $b) {return 0}
  if ($a eq $b) {return 0} # for efficiency; they could be identical after canonicalization, just not as raw strings
  my %ah = comma_delimited_to_hash($a);
  my %bh = comma_delimited_to_hash($b);
  if (jsonify_ugly(\%ah) eq jsonify_ugly(\%bh)) {return 0}
  my %combined = (%ah,%bh); # union of hashes
  my @d;
  foreach my $k(keys %combined) {
    push @d,$k if $ah{$k} ne $bh{$k};
  }
  return {'keys'=>\@d,'a'=>\%ah,'b'=>\%bh};
}

# returns a hash (not a hash ref)
# possible bug: if value is null, may return null for key??? noticed this when I set a student's class property to a null string; see workaround in list_defined_student_properties
sub comma_delimited_to_hash {
    my @a = split_comma_delimited_values(shift);
    my %result = ();
    foreach $a(@a) {
        $a =~ m/([^\:]*)\:(.*)/;
        $result{$1} = $2;
    }
    return %result;
}

# The following is nontrivial because there may be delimiters inside quotes.
sub split_comma_delimited_values { # from Perl Cookbook, p. 31
    my $text = shift;
    my @new = ();
    $text =~ s/^,//;
    $text =~ s/,$//;
    push(@new,$+) while $text =~ m{
        "([^\"\\]*(?:\\.[^\"\\]*)*)",?
            | ([^,]+),?
            | ,
            }gxo;
    return @new;
}

sub debug_print {
    my $self = shift;
    print "title: ".$self->title()."\n";
    print "staff: ".$self->staff()."\n";
    print "days:  ".$self->days()."\n";
    print "term:  ".$self->term()."\n";
    print "dir:   ".$self->dir()."\n";
    show_hash("categories",$self->categories_private_method(),$self->category_list());
    show_hash("roster",$self->roster_private_method());
    show_hash("assignments",$self->assignments_private_method(),$self->assignment_list());
    show_hash("grades",$self->grades_private_method());
}

sub show_hash {
    my $title = shift;
    my $h = shift;
    my %h = %$h;
    my @k = keys(%h); 
    if (@_) {
        @k = split(/,/,shift);
    }

    print "$title------------------------------------------\n";
    foreach my $k(@k) {print "  $k => $h{$k}\n";}
    print "-----------\n";
}

sub set_standards {
  my $self = shift;
  my $h = $self->class_private_method();
  $h->{'standards'} = shift;
}

# takes a comma-delimited string
sub set_marking_periods {
  my $self = shift;
  my $h = $self->class_private_method();
  $h->{'marking_periods'} = shift;
}

sub title {
    my $self = shift;
    return $self->class_data("title");
}

sub staff {
    my $self = shift;
    return $self->class_data("staff");
}

sub days {
    my $self = shift;
    return $self->class_data("days");
}

sub time {
    my $self = shift;
    my $time = $self->class_data("time");
    $time=~s/^(\d:\d\d)$/0$1/; # add leading zero if necessary in order to convert from h:mm to hh:mm
    return $time;
}

sub term {
    my $self = shift;
    return $self->class_data("term");
}

=head3 dir()

Get or set the subdirectory for web grades.

=cut

sub dir {
    my $self = shift;
    return $self->class_data("dir",@_);
}

# Returns a hash ref like {"A"=>"90",...}
sub standards {
    my $self = shift;
    my %h = comma_delimited_to_hash($self->class_data("standards"));
    return \%h;
}

# returns a hash ref like {"fall"=>"2009-08-20",...}, or undef if we're not using marking periods.
sub marking_periods {
    my $self = shift;
    my $p = $self->class_data("marking_periods");
    if (!$p) {return undef}
    my %h = comma_delimited_to_hash($p);
    return \%h;
}

sub marking_periods_in_order {
  my $self = shift;
  my $mp = $self->marking_periods();
  if (!$mp) {return undef}
  return sort {DateOG::order($mp->{$a},$mp->{$b})} keys %$mp;
}

sub percentage_to_letter_grade {
    my $self = shift;
    my $pct = shift;
    my $h = $self->standards();
    # Find the highest percentage that this grade meets or exceeds.
    my $highest = -999;
    my $highest_letter = "";
    foreach my $letter(keys(%$h)) {
        my $min = $h->{$letter};
        # The -.05 in the following is so we don't get in a situation where
        # the student's percentage grade rounds up to 90.0% for display, and 90% is supposed
        # to be an A, but the student is shown as having a B.
        if ($pct>=$min-.05 && $min>$highest) {
            $highest = $min;
            $highest_letter = $letter;
        }
    }
    return $highest_letter;
}

# Returns a comma-delimited list, without the category name on the front of the
# assignment names.
sub assignments_in_category {
    my $self = shift;
    my $cat = shift;
    my $a = $self->assignment_list();
    $a = ",".$a; # so first one gets parsed correctly
    $a =~ s/\,$cat\.([^\,]+)/,$1/g; # strip cat names; comma ensures hw doesn't match w
    $a =~ s/[^\.\,]+\.[^\.\,]+\,?//g; # get rid of assmts from other cats
    $a =~ s/,$//;
    $a =~ s/^,//;
    return $a;
}



=head3 category_contains_assignments()

Takes a category key as its argument.

=cut

sub category_contains_assignments {
  my $self = shift;
  my $cat = shift;
  my $assignments = $self->array_of_assignments_in_category($cat);
  if (@$assignments) {
    return 1;
  }
  else {
    return 0;
  }
}

=head3 number_of_assignments_in_category()

Takes a category key as its argument.

=cut

sub number_of_assignments_in_category {
  my $self = shift;
  my $cat = shift;
  my $assignments = $self->array_of_assignments_in_category($cat);
  return scalar @$assignments;
}


=head3 array_of_assignments_in_category()

Takes a category key as its argument.
Returns a reference to an array, like ["1","2",...].

=cut

sub array_of_assignments_in_category {
    my $self = shift;
    my $cat = shift;
    my @a = split(",",$self->assignments_in_category($cat));
    return \@a;
}

=head3 assignment_array()

Get or set the list of assignments. Uses arrays, not array references. Public method.

=cut

sub assignment_array {
  my $self = shift;
  if (@_) {$self->assignment_list(@_)}
  return split_comma_delimited_values($self->assignment_list());
}

=head3 assignment_list()

We keep this comma-delimited list so that we know the correct ordering of the
assignments. Can set it using a comma-delimited string or an array. This
is a private method.

=cut

sub assignment_list {
    my $self = shift;
    if (@_) {
        if ($#_ == 0) {
          $self->{ASSIGNMENT_LIST} = shift;
        }
        else {
            $self->{ASSIGNMENT_LIST} = "";
            foreach my $a(@_) {$self->{ASSIGNMENT_LIST}=$self->{ASSIGNMENT_LIST}.",".$a}
        }
        $self->{ASSIGNMENT_LIST} =~ s/^,//
    }
    return $self->{ASSIGNMENT_LIST};
}

sub set_all_category_properties {
    my $self = shift;
    my $key = shift;
    my $stuff = shift;
    $key = lc($key);
    if (! $self->category_exists($key)) {return 0}
    my $c = $self->categories_private_method();
    $c->{$key} = $stuff;
    $self->categories_private_method($c);
    return 1;
}

=head3 add_category()

Arguments: key, comma-delimited properties string, weight or null

Returns 1 on success, 0 on error.

=cut

sub add_category {
    my $self = shift;
    my $key = shift;
    my $stuff = shift;
    my $w = shift; # null string if not using weights
    $key = lc($key);
    if ($self->category_exists($key)) {return 0}
    $self->category_list($self->category_list().",".$key); # null case checked for inside
    my $c = $self->categories_private_method();
    $c->{$key} = $stuff;
    $self->categories_private_method($c);
    return 1;
}

=head3 category_list()

We keep a comma-delimited list so that we know the correct ordering of the
categories. This routine gets or sets the list. (When setting the list, it
automatically cleans up any leading comma.) This is a private method. To
add a category, use the public method add_category(). To get the list of
categories, use category_array().

=cut
sub category_list {
    my $self = shift;
    if (@_) {$self->{CATEGORY_LIST} = shift; $self->{CATEGORY_LIST} =~ s/^,//}
    return $self->{CATEGORY_LIST};
}

=head3 category_exists()

Only argument is key to check for.

=cut

sub category_exists {
    my $self = shift;
    my $key = shift;
    my $cats = $self->category_array();
    foreach my $cat(@$cats) {
      if ($cat eq $key) {return 1}
    }
    return 0;
}

=head3 category_array()

Returns a reference to an array. Can't be used to set the category list.

=cut

sub category_array {
    my $self = shift;
    my $l = $self->category_list();
    $l =~ s/,$//;
    my @a = split(",",$l);
    return \@a;
}

=head3 has_categories()

Tells whether any categories have been created.

=cut

sub has_categories {
    my $self = shift;
    my $c = $self->category_array();
    my @c = @$c;
    return ($#c >= 0);
}

=head3 most_recent_class_meeting($now)

You pass it an argument, which is a string containing a date in numeric yyyy-mm-dd format;
this is typically DateOG::current_date_sortable().
It tells you the last class meeting that was on or before that date, in the same format.

=cut

sub most_recent_class_meeting {
  my $self = shift;
  my $now = shift;
  #print "now=$now\n";
  my $meeting_days = $self->class_data("days");
  #print "meeting days=$meeting_days\n";
  my $max_tries = 9;
  for (;;) {
    last if $max_tries-- == 0;
    my $day_of_week = lc(DateOG::day_of_week_number_to_letter(DateOG::day_of_week_number($now)));
    #print "bumping, $now, day=$day_of_week\n";
    last if lc($meeting_days)=~/$day_of_week/;
    $now = DateOG::day_before($now);
  }
  
  return $now;
  
}

=head3 class_data()

Get or set a property from the class data. The argument tells which property we want to get.
The property's name is not surrounded with double quotes. To get a property, call with one
argument. To set a property, give a second argument as well.

=cut

sub class_data {
    my $self = shift;
    my $what = shift;
    my $h = $self->class_private_method();
    if (@_) {my $val = shift; $h->{$what}='"'.$val.'"'}
    if (!exists($h->{$what})) {return ""}
    my $result = $h->{$what};
    $result =~ s/^\"([^\"]*)\"$/$1/;
    return $result;
}

=head3 set_class_data()

Set the class's properties using a hash reference. Keys can be
title, staff, days, term, dir, standards, or marking_periods. Any old properties are lost, even
those not specied in the new list.

=cut

sub set_class_data {
    my $self = shift;
    my $stuff = shift;
    if (exists $stuff->{'marking_periods'} && !defined $stuff->{'marking_periods'}) {delete $stuff->{'marking_periods'}}
    $self->class_private_method($stuff);
}

=head3 types()

Get or set the list of enumerated types using a hash reference. 

=cut

sub types {
    my $self = shift;
    if (@_) {$self->{TYPES} = shift}
    my $t = $self->{TYPES};
    if (!ref $t) {return $t}
    return Storable::dclone($t); # clone it, because otherwise when we make a new category, the code in Gradebook mungs it by adding "numerical" to type order, etc.
}

sub set_default_types {
  my $self = shift;
  $self->types(
    {
      'order'       =>['numerical','attendance'],
      'data'=>{
        'numerical'=>{
          'description' =>'numerical',
        },
        'attendance'=>{
          'description' =>'attendance',
          'order'       =>['p','a','e','t'],
          'value'       =>{'p'=>1,'e'=>1,'t'=>1,'a'=>0},
          'descriptions'=>{'p'=>'present','a'=>'absent','e'=>'excused','t'=>'tardy'},
        }
      }
    }
  );
}

=head3 class_private_method()

Get or set the class's properties using a hash reference. 

=cut

sub class_private_method {
    my $self = shift;
    if (@_) {$self->{CLASS} = shift}
    return $self->{CLASS};
}

=head3 categories_private_method()

Currently implemented as a reference to a hash whose values are the
unparsed tails of the category-setup lines.

=cut

sub categories_private_method {
    my $self = shift;
    if (@_) {$self->{CATEGORIES} = shift}
    return $self->{CATEGORIES};
}

=head3 roster_private_method()

A reference to a hash like {".newton_isaac"=>"id:1"',...}

=cut

sub roster_private_method {
    my $self = shift;
    if (@_) {$self->{ROSTER} = shift}
    return $self->{ROSTER};
}

=head3 assignments_private_method()

A reference to a hash like {"hw.1"=>"due:2/28",...}

=cut

sub assignments_private_method {
    my $self = shift;
    if (@_) {$self->{ASSIGNMENTS} = shift}
    return $self->{ASSIGNMENTS};
}

=head3 grades_private_method()

A reference to a hash like {"Newton_Isaac.hw"=>"1:12",...}

=cut

sub grades_private_method {
    my $self = shift;
    if (@_) {$self->{GRADES} = shift}
    return $self->{GRADES};
}

=head3 preferences_private_method()

A reference to a hash like {"backups_on_server"=>"true",...}

=cut

sub preferences_private_method {
    my $self = shift;
    if (@_) {$self->{PREFERENCES} = shift}
    return $self->{PREFERENCES};
}


sub iterations_for_line_by_line {
  return 1;
}


# http://gradel.sourceforge.net/
# http://sourceforge.net/project/showfiles.php?group_id=163450&package_id=184767
# format definition can be found from code in GClass.class in function savegb
# bugs:
#  Worked for me when I exported a file that had no marking periods, but when I used marking periods, gradel choked on it.
#  It complains that the format is too old, which happens when it doesn't encounter a COMMENTS line when it expects it.
sub export_gradel {
  my $self = shift;
  $self->term() =~ /(\d+)\-(\d+)/;
  my ($year,$month) = ($1,$2);
  # For start and end of term, just try to guarantee that they encompass the actual term:
  my $start_term = sprintf("%02d/%02d/%02d",$month,1,$year%100);
  my $end_term = sprintf("%02d/%02d/%02d",$month,1,($year+1)%100);
  my $nmp = 1;
  my @mp_names = ();
  my @start_mp = ($start_term,);
  my @end_mp = ($end_term,);
  if ($self->marking_periods()) {
    my $h = $self->marking_periods();
    @mp_names = $self->marking_periods_in_order();
    $nmp = @mp_names;
    for (my $mp=1; $mp<=$nmp; $mp++) {
      $start_mp[$mp-1] = $h->{$mp_names[$mp-1]};
      if ($mp==$nmp) {$end_mp[$mp-1]=($year+1)."-$month-01"} else {$end_mp[$mp-1]=DateOG::day_before($h->{$mp_names[$mp]})}
    }
  }
  my $t = "[GradeL Gradebook File]\n"
         .$self->title()."\n"
         .$self->staff()."\n"
         ."[Online Grades]\n"
         .$self->class_data('online_grades_course_code')."\n"
         .$self->class_data('online_grades_section_number')."\n"
         .($self->staff() || 'faculty')."\n"
         .$self->password()."\n"
         ."SEMESTERS:1\n"
         ."MP PER SEMESTER:$nmp\n"
         .($self->weights_enabled()==1 ? 101 : 100)."\n" # might not have been set yet, in which case default is 100, unweighted
         ."1\n"; # period
  my @all_ass = split(",",$self->assignment_list());
  for (my $mp=1; $mp<=$nmp; $mp++) {
    $t = $t."[MP $mp Assignments]\n"
           ."MP $mp\n"
           .date_to_gradel_format($start_mp[$mp-1])."\n"
           .date_to_gradel_format($end_mp[$mp-1])."\n";
    my @ass = ();
    foreach my $key(@all_ass) {
      my ($cat,$a) = $self->split_cat_dot_ass($key);
      push @ass,$key if $nmp==1 || $self->assignment_property($key,'mp') eq $mp_names[$mp-1];
    }
    my $nass = @ass;
    $t = $t . $nass ."\n";
    foreach my $key(@ass) {
      my ($cat,$a) = $self->split_cat_dot_ass($key);
      $t = $t . $self->assignment_name($key)."\n".date_to_gradel_format($self->assignment_property($key,'due'))."\n"
              . ( $self->assignment_property($key,'max') || 0)."\n".$self->category_name_singular($cat)."\n";
    }
    $t = $t . "[MP $mp Class Days]\n0\n";
  }
  foreach my $active('','dropped') {
    my @student_keys = $self->student_keys($active);
    $t = $t . ($active eq '' ? '[Students]' : '[Dropped Students]') . "\n";
    my $n = @student_keys;
    $t = $t . "$n\n"; # number of students
    foreach my $who(@student_keys) {
      my ($first,$last) = $self->name($who);
      $t = $t . "$last, $first\n".$self->get_student_property($who,'id')."\n";
      $t = $t . "\n"; # phone number
      # after this comes stuff like EMAIL, FINE, etc., which appears to be optional
      $t = $t . "\n"; # textbook number
      for (my $mp=1; $mp<=$nmp; $mp++) {
        my @grades;
        foreach my $key(@all_ass) {
          my ($cat,$a) = $self->split_cat_dot_ass($key);
          if  ($nmp==1 || $self->assignment_property($key,'mp') eq $mp_names[$mp-1]) {
            my $grade = $self->get_current_grade($who,$cat,$a);
            if (!$grade) {$grade=0}
            push @grades,$grade;
          }
        }      
        $t = $t . join("\t",@grades)."\n" if @grades;
      }
      $t = $t . "COMMENTS:\n" x $nmp;
      # attendance would go here
    }
  }
  my $r = $self->category_array();
  my @cats = @$r;
  my $ncats = @cats;
  $t = $t . "[Categories]\n$ncats\n";
  my $color = 16777215;
  my $normalize = 0;
  foreach my $cat(@cats) {
    $normalize = $normalize + $self->category_weight($cat);
  }
  $normalize=1 if $normalize==0;
  foreach my $cat(@cats) {
    $t = $t . "<NEW CATEGORY>\n".$self->category_name_singular($cat)."\n$color\n".($self->category_weight($cat)/$normalize)."\n";
  }
  $t = $t . <<STUFF;
[Codes]
0
[Attendance Codes]
0
[Grading Scale]
STUFF
  # GradeL is hard-coded to expect exactly 13 letter grades.
  my $s = $self->standards(); # hash ref
  foreach my $letter(keys %$s) {
    if (uc($letter) ne $letter) {
      $s->{uc($letter)}=$s->{$letter};
      delete $s->{$letter};
    }
  }
  my @letters = sort {$s->{$b} <=> $s->{$a}} keys %$s;
  my $handled_standards = 0;
  if (lc(join('',@letters)) eq 'a+aa-b+bb-c+cc-d+dd-f') {
    $s->{E} = $s->{F};
    delete $s->{F};
    $handled_standards = 1;
  }
  if (!$handled_standards && lc(join('',@letters)) eq 'abcdf') {
    $s->{E} = $s->{F};
    delete $s->{F};
    foreach my $letter('A','B','C','D') {$s->{"$letter+"}=$s->{$letter}+.01; $s->{"$letter-"}=$s->{$letter}-.01; }
    $handled_standards = 1;
  }
  if (!$handled_standards) {$s = {'A+'=>13, 'A'=>12, 'A-'=>11, 'B+'=>10, 'B'=>9, 'B-'=>8, 'C+'=>7, 'C'=>6, 'C-'=>5, 'D+'=>4, 'D'=>3, 'D-'=>2, 'E'=>0}}
       # ... Make something unreasonable, so there's no chance they'll think it's okay. 13% is an A+, so everyone will have an A+.
  @letters = sort {$s->{$b} <=> $s->{$a}} keys %$s;
  foreach my $letter(@letters) {$t = $t . "$letter\t".$s->{$letter}."\n"}
  $t = $t . <<STUFF;
[Seating Chart]
7
5
STUFF
  $t = $t . "-1\n" x 35;
  $t = $t . "[Comments]\n[Weights]\n".("1\n" x $nmp)."2\n"; # weights for each marking period and for each semester; apparently it assumes 2 semesters
  $t = $t . "[End of Class File]\n";
  return $t;
}

sub date_to_gradel_format {
  my $date = shift;
  $date =~ /(\d+)\-(\d+)/;
  my ($year,$month) = ($1,$2);
  return sprintf("%02d/%02d/%02d",$month,1,$year%100);
}

1;
