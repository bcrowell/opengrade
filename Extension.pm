use strict;
package Extension;
use IPC::System::Simple;
use IPC::Run;


sub apply_scalar_function_of_x {
  my $f = shift; # source code, with x as the input
                 # example using lisp: "* x 0.1"
                 # example using bc: "x*0.1"
  my $x = shift;
                 # As a convenience feature, if $f is undefined or null string, we return the input unaltered,
                 # and likewise if $x$ is a null string.
  if (!defined $f || $f eq '' || $x eq '') {return $x}
  if (1) { # bc
    my $source_code = "define f(x) {\nreturn($f)}\nf($x)\n";
    return execute_bc_code($source_code);
  }
  if (0) { # Guile
    my $source_code = "(display ((lambda (x) ($f)) $x))";
    return execute_guile_code($source_code);
  }
}

sub execute_bc_code {
  my $source_code = shift; # the source code of a complete Guile program
  my ($err,$out);
  IPC::Run::run ['bc','-s'], \$source_code, \$out, \$err;
  if ($err eq '') {
    chomp($out);
    return $out;
  }
  else {
    print STDERR "Error executing code using bc:\n$err\ncode:\n$source_code\n";
    return undef;
  }
}

# Returns the output of the Guile program. If there's an error, prints error info to stderr and returns undef.
# Thanks to haukex for the code.
sub execute_guile_code {
  my $source_code = shift; # the source code of a complete Guile program
  my $result;
  if (not eval { $result = IPC::System::Simple::capturex('guile','-c',$source_code); 1 }) {
      print STDERR "Error executing scheme code using guile:\n$@.\n";
      return undef;
  }
  return $result;
}

1;
