
print <<INFO;
OpenGrade installation for Windows

This installer will download and install some open-source software
from activestate.com that is required for OpenGrade to run.

If you continue with installation, you will probably get lots and lots
of output on the screen. If everything is working as it should, you can
ignore all of it!

Do you want to continue with installation?
Enter y to continue, or n to quit.
INFO


my $response = <STDIN>;
$response = lc($response);
exit unless $response =~ m/^y/;


do_ppm("Clone");
do_ppm("Date-Calc");
do_ppm("libnet");
do_ppm("TermReadKey");
do_ppm("Digest-SHA");
do_ppm("Tk");
do_ppm("JSON");

print <<DONE;

----------------------------------------------------------------------
Installation was completed successfully.
For information on how to run and use OpenGrade, see the documentation:
  http://www.lightandmatter.com/ogr/opengrade_doc.pdf
If there's anything that's not working right, please send me an e-mail
that includes the complete error message. You can find out my
current e-mail address at
  http://www.lightandmatter.com/area4author.html

Hit enter to continue.
DONE

# The following is because the DOS window vanishes immediately after the script is done running.
<STDIN>;

sub do_ppm {
  my $what = shift;
  print "\nInstalling $what...\n";
  system("ppm install $what");
  print "$what installed.\n";
}
