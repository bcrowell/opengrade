#----------------------------------------------------------------
# Copyright (c) 2002 Benjamin Crowell, all rights reserved.
#
# This software is available under version 2 of the GPL license.
# The software is copyrighted, and you must agree to the
# license in order to have permission to copy it. The full
# text of the license is given in the file titled Copying.
#
#----------------------------------------------------------------



=head2 Input.pm

The Input class is a way of checking a string input by the user
to see if it's valid. It also contains information about the
default value and the prompt, which are only for convenience ---
Input's methods don't use them. Synopsis:

  $i = Input->new(
         KEY=>"file_name",
         PROMPT=>"Filename",
         DEFAULT=>"foo.bar",
         TYPE=>"numeric",MIN=>"...",MAX=>"..."
  );
  $i = Input->new(
         ...
         TYPE=>"string",BLANK_ALLOWED=>1
  );
  if ($i->check($x)) { $error_code = ($i->check($x))[0]; ...}
          # ...may have other error info in [1], ...

  Dates:
    WIDGET_TYPE=>'date',
    TYPE=>'date',
    TERM=>... ... mandatory
    Result will automatically be checked and disambiguated.
    DEFAULT can be supplied in ambiguous form, and will be disambiguated immediately.
    Set BLANK_ALLOWED if it's ok for it to be null.

=cut

use strict;

package Input;

use Words qw(w get_w);
use MyWords;


sub new {
    my $words_prefix = "b.input";
    my $class = shift;
    my @save_args = @_; # otherwise might get clobbered by w('yes') ...?
    my %args = (
      KEY=>"",
      PROMPT=>"",
      DEFAULT=>"",
      TYPE=>"numeric", # used for error checking
      TERM=>'', # required if TYPE is 'date', for error checking and disambiguation of year
      MIN=>"",
      MAX=>"",
      BLANK_ALLOWED=>1,
      ZERO_ALLOWED=>1,
      WIDGET_TYPE=>'entry', # can also be 'text' for multiline text, or 'radio_buttons', or 'date', or 'menu'
      ITEM_MAP=>{1=>Browser::get_w($words_prefix,'yes'),0=>Browser::get_w($words_prefix,'no')}, # a ref to a hash, giving the text for each value
      ITEM_KEYS=>[1,0],
            @save_args,
    );
    my $self = {};
    bless($self,$class);
    $self->{KEY} = $args{KEY};
    $self->{PROMPT} = $args{PROMPT};
    $self->{DEFAULT} = $args{DEFAULT};
    $self->{TYPE} = $args{TYPE};
    $self->{TERM} = $args{TERM};
    $self->{MAX} = $args{MAX};
    $self->{MIN} = $args{MIN};
    $self->{BLANK_ALLOWED} = $args{BLANK_ALLOWED};
    $self->{ZERO_ALLOWED} = $args{ZERO_ALLOWED};
    $self->{WIDGET_TYPE} = $args{WIDGET_TYPE};
    $self->{ITEM_MAP} = $args{ITEM_MAP};
    $self->{ITEM_KEYS} = $args{ITEM_KEYS};
    $self->{ITEM_KEYS} = $args{ITEM_KEYS};
    $self->{ITEM_MAP} = $args{ITEM_MAP};
    return $self;
}

sub check {
  my $self = shift;
  my $x = shift;

  local $Words::words_prefix = "input";

  #print "dumping...\n";
  #dump_str($x);

  my @stuff = ();
  if ($x eq "" && !($self->{BLANK_ALLOWED})) {push @stuff,"blank_not_allowed"}
  if ($x eq "0" && !($self->{ZERO_ALLOWED})) {push @stuff,"zero_not_allowed"}
  if ($self->{TYPE} eq "numeric") {
    if (!($x eq "" && $self->{BLANK_ALLOWED})) {
      if ($self->{MIN} ne "" && $x<$self->{MIN}) {@stuff = ("below_min",$self->{MIN})}
      if ($self->{MAX} ne "" && $x>$self->{MAX}) {@stuff = ("above_max",$self->{MAX})}
    }
  }
  if ($self->{TYPE} eq "time") {
    if ($x eq "" && !($self->{BLANK_ALLOWED})) {push @stuff,"blank_not_allowed"} # sometimes causes mysterious complaints when not blank!?
    my $illegal_format = $x ne "" && !($x=~m/^\d{1,2}:\d\d$/);
    if ($illegal_format) {push @stuff,"illegal_time_format"}
    if (!$illegal_format) {$x=~m/^\d{1,2}:\d\d$/; my ($h,$m)=($1,$2); if ($h>=24 || $m>=60) {push @stuff,"illegal_hour_or_minute"}}
  }
  if ($self->{TYPE} eq "date") {
    if ($x eq "" && !($self->{BLANK_ALLOWED})) {push @stuff,"blank_not_allowed"}
    my $illegal_format = $x ne "" && !($x=~m/^(\d{4,4}\-)?\d{1,2}\-\d{1,2}$/);
    if ($illegal_format) {push @stuff,"illegal_date_format"; push @stuff,$x}
    if (!$illegal_format && $x ne '' && !DateOG::is_legal($x,$self->{TERM})) {push @stuff,"illegal_month_or_day"; push @stuff,$x}
    die "programming error: TERM not supplied to new Input with type=date" unless $self->{TERM};
    if ($self->{DEFAULT} ne '') {$self->{DEFAULT}=DateOG::disambiguate_year($self->{DEFAULT},$self->{TERM})}
  }
  if (!@stuff) {return @stuff}
  return map {w($_)} @stuff;
}

# for debugging
sub dump_str {
  my $x = shift;
  print "string=$x=\n";
  while ($x=~m/(.)/g) {
    my $c = $1;
    print "==$c==".ord($c)."==\n";
  }
}

1;
