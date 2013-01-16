#----------------------------------------------------------------
# Copyright (c) 2002 Benjamin Crowell, GPL v2 license.
#----------------------------------------------------------------

package Version;

sub version {
  return "3.1.17";
}

sub default_hash_function {
  return "SHA1"; # for watermarks; Whirlpool and SHA1 are supported; to add a new hash function, need to add it in GradeBook (LineByLine doesn't need to support new ones)
}

# The following is so we can check for an incompatibility between GTK2+
# and Perl/Tk. This code won't work on BSD, etc.
sub gtk_version {
  my $debug = 0;
  my $os_name = lc($^O);
  print "os_name=$os_name\n" if $debug;
  if ($os_name=~m/linux/) {
    print "is linux\n" if $debug;
    system("ldconfig -p >/dev/null")==0 or return undef;
    print "ldconfig worked\n" if $debug;
    my $ldconfig_output = `ldconfig -p`;
    # should contain:    libgtk-x11-2.0.so.0 (libc6) => /usr/lib/libgtk-x11-2.0.so.0
    $ldconfig_output =~ m@libgtk\-x11\-2\.0\.so\.0 \(libc6\) \=\> (.*)@ or return undef;
    print "matched\n" if $debug;
    my $link = $1; # e.g., /usr/lib/libgtk-x11-2.0.so.0
    `file $1` =~ m/libgtk\-x11\-2\.0\.so\.0\.(.*)\'/;
    my $version = $1; # e.g., "800.6" for gtk 2.8.6
    $version =~ s/^(\d)00/$1/;
    return "2.$version";
  }
  else {
    return undef;
  }
}

1;
