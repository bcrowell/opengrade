use strict;
package Extension;


sub apply_scalar_function_of_x {
  my $f = shift; # lisp source code, with x as the input, e.g., "* x 0.1"
                 # As a convenience feature, if $f is undefined or null string, we return the input unaltered.
  my $x = shift;
  if (!defined $f) {return $x}
  my $lisp = "(display ((lambda (x) ($f)) $x))";
  my $result = `guile -c '$lisp'`;
  if ($? == 0) {
    return $result;
  }
  else {
    print STDERR "Error executing scheme code $lisp using guile.";
    return undef; # occurs if guile is not installed or the guile code dies with an error
  }
  # to do:
  #   Escape single quotes inside the string.
}

1;
