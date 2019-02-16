use strict;
package Extension;
use IPC::System::Simple;
use IPC::Run;


sub apply_scalar_function_of_x {
  my $code = shift; # source code, with x as the input
                 # example using lisp: "guile:* x 0.1"
                 # example using bc: "bc:x*0.1"
  my $x = shift;
                 # As a convenience feature, if $f is undefined or null string, we return the input unaltered,
                 # and likewise if $x$ is a null string.
  if (!defined $code || $code eq '' || $x eq '') {return $x}
  unless ($code=~/\A([a-z]+):(.*)\Z/s) {
    extension_err("Error executing code, no language specified:\ncode:\n$code\n");
    return undef;
  }
  my ($language,$f) = ($1,$2);
  if ($language eq 'bc') {
    my $source_code = "define f(x) {\nreturn($f)}\nf($x)\n";
    return execute_bc_code($source_code);
  }
  if ($language eq 'guile') {
    if (1) {
      extension_err("Error executing code, guile disabled for security reasons:\ncode:\n$f\n");
      return undef;
    }
    my $source_code = "(display ((lambda (x) ($f)) $x))";
    return execute_guile_code($source_code);
  }
  extension_err("Error executing code, unrecognized language: $language\ncode:\n$code\n");
  return undef;
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
    extension_err("Error executing code using bc:\n$err\ncode:\n$source_code\n");
    return undef;
  }
}

# Returns the output of the Guile program. If there's an error, prints error info to stderr and returns undef.
# Thanks to haukex for the code.
sub execute_guile_code {
  my $source_code = shift; # the source code of a complete Guile program
  my $result;
  if (not eval { $result = IPC::System::Simple::capturex('guile','-c',$source_code); 1 }) {
      extension_err("Error executing scheme code using guile:\n$@.\n");
      return undef;
  }
  return $result;
}

sub extension_err {
  my $message = shift;
  print STDERR $message;
}


1;
