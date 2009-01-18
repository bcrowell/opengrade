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

package Text;

# Text->new(format)
# Format can be plain, html
sub new {
    my $class = shift;
    my $format = shift;
    my $self = {};
    bless($self,$class);
    $self->{FORMAT} = lc($format);
    $self->{TEXT} = "";
    return $self;
}

sub text {
    my $self = shift;
    if (@_) {$self->{TEXT} = shift}
    return $self->{TEXT};
}

sub format {
    my $self = shift;
    if (@_) {$self->{FORMAT} = shift}
    return $self->{FORMAT};
}

# Can specify line breaks using P and BR params, or can just
# put \n's in the text; in html mode, these get translated to
# br tags
sub put {
    my $self = shift;
    my %args = (
                TEXT=>"",
                INDENTATION=>0,
                P=>0, # <p> in html, \n\n in text
                BR=>0, # <br> in html, \n in text
                @_,
                );
    my $text = $args{TEXT};
    my $indentation = $args{INDENTATION};
    my $p = $args{P};
    my $br = $args{BR};
    my $stuff = $text;
    if ($self->format() eq "plain") {
        $stuff = " "x(4*$indentation) . $stuff;
        if ($p) {
            $stuff = $stuff . "\n\n";
        }
        else {
            if ($br) {$stuff = $stuff . "\n";}
        }
    }
    if ($self->format() eq "html") {
        $stuff =~ s/\n/<br\/>\n/g;
        if ($indentation>=1) {
            $stuff = "<ul>$stuff</ul>"; # bug: doesn't work for double indentation
        }
        if ($p) {
            $stuff = "<p>\n  " . $stuff . "\n</p>";
        }
        else {
            if ($br && $indentation<1) {$stuff = $stuff . "<br/>";}
        }
        $stuff = $stuff . "\n"; # just makes HTML source more readable
    }
    
    $self->text($self->text().$stuff);
}

1;









