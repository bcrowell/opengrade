use strict;
package Extension;
use IPC::System::Simple;


sub apply_scalar_function_of_x {
  my $f = shift; # lisp source code, with x as the input, e.g., "* x 0.1"
                 # As a convenience feature, if $f is undefined or null string, we return the input unaltered.
  my $x = shift;
  if (!defined $f) {return $x}
  my $lisp = "(display ((lambda (x) ($f)) $x))";
  return execute_guile_code($lisp);
}

# Returns the output of the Guile program. If there's an error, prints error info to stderr and returns undef.
sub execute_guile_code {
  my $lisp = shift; # the source code of a complete Guile program
  my $result;
  if (not eval { $result = IPC::System::Simple::capturex('guile','-c',$lisp); 1 }) {
      print STDERR "Error executing scheme code using guile:\n$@.\n";
      return undef;
  }
  return $result;
}

1;
