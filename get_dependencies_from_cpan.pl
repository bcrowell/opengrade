use strict;

use CPAN;

my @modules = (
              "Clone",
              "Term::ReadKey",
              "Date::Calc",
              "Digest::SHA1",
              "Digest::Whirlpool",
              "Tk",
              "JSON",
              "Storable", # is distributed as part of the perl package in ubuntu
              );
	# modules with ! in front of the names are ignored

print <<INFO;
OpenGrade installation

This installer will download and install some open-source software
from cpan.org that is required for OpenGrade to run. You should use
this script if you're running Linux or MacOS X. If you're running
Windows, you should use the install_win.pl script. If you're running
FreeBSD, see the documentation for more information.

Please check
the following checklist before continuing:

  1. You must be logged in as an administrator. On Linux, you do this
     with the command ``su''. On MacOS X, do ``sudo tcsh''.
  2. You must have a C compiler installed. On Linux, you presumably
     have gcc. On MacOS X, make sure you have installed the Developer
     Tools from the CD or from a disk image that was on your hard disk
     when you got your machine.
  3. The following modules will be required:
INFO

foreach my $mod(@modules) {
  print "      $mod\n" unless $mod =~ m/^!/;
}

print <<INFO;
     Modules that are already installed will not be touched.

If you continue with installation, you will probably get lots and lots
of output on the screen. If everything is working as it should, you can
ignore all of it!

Do you want to continue with installation?
Enter y to continue, or n to quit.
INFO


my $response = <STDIN>;
$response = lc($response);
exit unless $response =~ m/^y/;

foreach my $mod(@modules) {
  if (!($mod=~m/^!/)) {
    print "----------------------------\nInstalling $mod\n";
    install $mod;
  }
}

print "\n\n---------------------\nInstallation was completed successfully.\n";
print "For information on how to run and use OpenGrade, see the documentation:\n";
print "  http://www.lightandmatter.com/ogr/opengrade_doc.pdf\n";
