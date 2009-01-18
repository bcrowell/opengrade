#----------------------------------------------------------------
# Copyright (c) 2002 Benjamin Crowell, all rights reserved.
#
# This software is available under version 2 of the GPL license.
# The software is copyrighted, and you must agree to the
# license in order to have permission to copy it. The full
# text of the license is given in the file titled Copying.
#
#----------------------------------------------------------------

=head2 Words.pm

This module manages all the strings that would have
to be translated if the program was internationalized,
and all the strings that should not be duplicated between
different user interfaces to the underlying code.
The actual strings themselves are in MyWords.pm.

This code handles line breaks: if you're going to output a string
on the terminal, it inserts newlines at the appropriate places
to make the lines the right length. If the string is going to
be displayed in some other way, it doesn't insert them.
If you want to force linebreaks, you can put in html-style
<br/> tags. Likewise, paragraph breaks can be put in using
<p></p>. In terminal mode, <p></p> gets expanded to a double newline.
If it's convenient for you, you can embed newlines in the string
itself, but by default these are stripped out (converted to
single blanks) before anything else happens.

To prevent stripping of newlines, add a line at the beginning of the
text like this:
  --literal--

=cut

use strict;

use MyWords;

package Words;

require Exporter;
use vars qw(@ISA @EXPORT $VERSION);
@ISA =  qw(Exporter);
@EXPORT = qw(w get_w words_prefix);
$VERSION = 1.0;

our $words_prefix; # intended to be modified from outside the package: local $Words::words_prefix = "en.b.foo"
our $words; # This is typically initialized in main_loop (of which there are two versions, one for terminal and one for gui).

sub w {
    my $key = shift;
    return get_w($words_prefix,$key);
}
sub get_w {
    my $prefix = shift;
    my $key = shift;
    die "Words::words is uninitialized" unless defined $words;
    my $newline = "";
    if ($key =~ m/\n$/) {$newline="\n"}
    chomp $key;
    return $words->get($prefix.".".$key).$newline;
}

# Words->new(...) creates a new Words object.
# Arguments:
#   FORMAT=>
#     "terminal" -- linebreaks are inserted as needed, according to WIDTH; whitespace
#                   is generally maintained religiously and literally, so, e.g., you
#                   can use blanks to line up columns
#     "html" -- nothing is done with linebreaks
#     "flow" -- <br/> converted to \n, <p></p> to \n\n
#     "TeX" -- <br/> converted to \\, <p></p> to \n\n
#   WIDTH
#     only relevant for FORMAT=>"terminal"
#   LANGUAGE
#     two-letter language code, according to the usual WWW convention
#   MIN_WIDTH, MAX_WIDTH
#     These default to 40 and 100, respectively. The width 
#       is forced into this range as a programming convenience (<40 would produce ugly
#       results and look like a bug in the code; >100 is unreadable, and
#       should not be used even if the terminal window really is that wide).
sub new {
    my $class = shift;
    my %args = (
                LANGUAGE => "en",
                FORMAT => "terminal",
                WIDTH => "80",
                MIN_WIDTH => "40",
                MAX_WIDTH => "100",
                @_
                );
    my $self = {};
    bless($self,$class);
    $self->{LANGUAGE} = $args{LANGUAGE};
    $self->{FORMAT} = $args{FORMAT};
    $self->{WIDTH} = $args{WIDTH};
    my $min_width = $args{MIN_WIDTH};
    my $max_width = $args{MAX_WIDTH};
    if ($self->{WIDTH}<$min_width) {$self->{WIDTH} = $min_width}
    if ($self->{WIDTH}>$max_width) {$self->{WIDTH} = $max_width}
    return $self;
}

sub get {
    my $self = shift;
    my $key = shift;
    return $self->get_fancy(KEY=>$key);
}

sub get_fancy {
    my $self = shift;
    my %args = (
      KEY=>"",
      NEWLINES_TO_BLANKS=>1,
      SUPPRESS_TRAILING_NEWLINE=>1,
      @_,                
                );
    my $key = $self->{LANGUAGE}.".".$args{KEY};
    my $the_string = MyWords::retrieve($key);
    if ($the_string=~m/^\s*\-\-literal\-\-/) {
      $the_string =~ s/^\s*\-\-literal\-\-\n?//;
      return $the_string;
    }
    else {
      return $self->format(
        STRING=>$the_string,
        NEWLINES_TO_BLANKS=>$args{NEWLINES_TO_BLANKS},
        SUPPRESS_TRAILING_NEWLINE=>$args{SUPPRESS_TRAILING_NEWLINE}
                  );
    }
}

sub format {
    my $self = shift;
    my %args = (
                STRING=>"",
                NEWLINES_TO_BLANKS=>1,
                SUPPRESS_TRAILING_NEWLINE=>1,
                @_,
                );
    my $string = $args{STRING};
    if ($args{NEWLINES_TO_BLANKS}) {
      $string =~ s|\n| |g;
    }
    if ($self->{FORMAT} eq "html") {
      # Do nothing.
    }
    if ($self->{FORMAT} eq "flow" || $self->{FORMAT} eq "terminal") {
      $string =~ s|\<br\/\>|\n|gi;
      $string =~ s|\<p\>||gi;
      $string =~ s|\<\/p\>|\n\n|gi;
      # If it's terminal, we do more stuff below.
    }
    if ($self->{FORMAT} eq "TeX") {
      $string =~ s|\<br\/\>|\\\\|gi;
      $string =~ s|\<p\>||gi;
      $string =~ s|\<\/p\>|\n\n|gi;
    }
    if ($self->{FORMAT} eq "terminal") { # Already handled html above.
      # The following line splits the code into words, with each word carrying
      # its trailing whitespace along with it. Note that the trailing whitespace
      # could contain newlines and double newlines.
      # This code would not work if I ever allowed html tags containing
      # blanks. Note that the \s* may look wrong, but it's right; it covers
      # the case where this is the last word in the string, and it also
      # works correctly in other cases, because the [^\s]+ part is greedy.
      my @words = ($string =~ /([^\s]+\s*)/g); # Perl Cookbook, p. 171
      my $result = "";
      my $line = "";
      my $width = $self->{WIDTH};
      foreach my $word(@words) {
        if ($line ne "" && length($line)+length($word)>$width) {
        $result = $result . terminal_mode_flush_line($line);
        $line = "";
            }
            $line = $line . $word;
            if ($word =~ m/\n\s*$/) {
        $result = $result . terminal_mode_flush_line($line);
        $line = "";
            }
    }
    $result = $result . terminal_mode_flush_line($line);
    $string = $result;
    if ($args{SUPPRESS_TRAILING_NEWLINE}) {
            $string =~ s/\s+$//;
    }
  }
  $string =~ s/  +/ /g;
  return $string;
}

sub terminal_mode_flush_line {
    my $line = shift;
    $line =~ s/ +$//; # eliminate trailing blanks
    if (!($line =~ m/\n$/)) {$line = $line . "\n"} # at least one newline
    return $line;
}

# For internationalization, could add an optional second argument
# specifying the language.
sub pluralize {
    my $word = shift;
    if (lc($word) eq "quiz") {return $word."zes"}
    return $word."s";
}


1;
