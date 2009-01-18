#!/usr/bin/perl
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

package ogr;

use FindBin;
use lib $FindBin::RealBin;
   # RealBin follows symbolic links, as opposed to Bin, which doesn't.
use Cwd;
use GradeBook;
use TermUI;
use Term::ReadKey;
use Getopt::Long qw(GetOptions);
use POSIX;
use Portable;
use File::Spec::Functions qw(catfile);

BEGIN {
  # Look for plugins. Search likely members of @INC for subdirectories named "plugins," and
  # add them to @INC. This has to happen in a BEGIN block so the compiler knows about the changes to @INC in time.
  # Likely members of @INC are defined by whether they match /opengrade/i. (Can't do this on all members of @INC,
  # which would likely give us some bogus results.) Catfile is from File::Spec::Functions, does the platform-independent
  # equivalent of "$a/$b".
  @INC = (@INC,grep {-d $_} (map {catfile($_,'plugins')} grep(/opengrade/i,@INC)));
}

# We maintain the following list so that we can panic-save
# when we get an interrupt.
our @open_files = ();

catch_signals();

my $whirlpool_err = '';
if (!defined LineByLine::do_whirlpool('')) {
 $whirlpool_err = "You must install either Digest::Whirlpool (using the get_dependencies_from_cpan.pl script) or whirlpooldeep (debian package md5deep)";
}

our %options=(
  't'=>0,
  'help'=>0,
  'copy'=>0,
  'output'=>'',
  'output_format'=>'default',
  'input_password'=>'',
  'output_password'=>undef,
  'authenticate'=>0,
  'identical'=>0,
  'version'=>0,
);
our %command_line_options = (
  't'=>\$options{'t'},
  'help'=>\$options{'help'},
  'copy'=>\$options{'copy'},
  'output=s'=>\$options{'output'},
  'output_format=s'=>\$options{'output_format'},
  'input_password=s'=>\$options{'input_password'},
  'output_password=s'=>\$options{'output_password'},
  'authenticate!'=>\$options{'authenticate'},
  'identical'=>\$options{'identical'},
  'version'=>\$options{'version'},
);
GetOptions(%command_line_options); # from Getopt::Long
my ($command_line_file_argument,$gui);
if (@ARGV) {$command_line_file_argument=$ARGV[0]} # something left over on command line after options were pulled out

#----------------------------------------------------------------
# scripting:
#----------------------------------------------------------------

# opengrade.pl --copy --output=bar.gb foo.gb ... parses foo.gb, writes back out to bar.gb
# opengrade.pl --copy foo.gb                 ... similar, but to stdout
# can also set --output_format=(old|json|default)
if ($options{'help'}) {
  do_help();
  exit;
}
if ($options{'version'}) {
  do_version();
  exit;
}
if ($options{'copy'}) {
  do_copy($command_line_file_argument,$options{'output'},$options{'output_format'},$options{'input_password'},$options{'output_password'},$options{'authenticate'});
  exit;
}
if ($options{'identical'}) {
  do_identical($ARGV[0],$ARGV[1]);
  exit;
}

#----------------------------------------------------------------
# Run a user interface:
#----------------------------------------------------------------

if (!$options{'t'}) {
  require Browser;
  Browser::main_loop($command_line_file_argument,$whirlpool_err);
}
else {
  die $whirlpool_err if $whirlpool_err;
  TermUI::main_loop($command_line_file_argument);
}

# Now exit the program.

#----------------------------------------------------------------
# helper routines:
#----------------------------------------------------------------

sub do_help {
  print <<HELP;
opengrade
  ... runs the graphical user interface
opengrade -t
  ... runs the terminal-based interface
opengrade --help
  ... prints this message and exits
opengrade --version
  ... prints version number and exits
opengrade --identical a.gb b.gb
  ... test files for identicality
opengrade --copy --output_format=old --output=b.gb a.gb
  ... copy, with error checking and possible change of format

For documentation on how to use the graphical user interface, see the online documentation, in
PDF format at http://www.lightandmatter.com/ogr/ogr.html .

For more detailed information on the command-line interface, see the Scripting section of the
documentation.
HELP
}

sub do_version {
  print Version::version(),"\n";
}

# If they differ, exits with code 1, else 0.
# If they differ, it prints a log to stdout of how they differ.
# The semantics are meant so, e.g.:
#      opengrade --identical a.gb b.gb || echo "assertion of identicality failed"
sub do_identical {
  my ($file_a,$file_b) = @_; # two input files
  #print STDERR "comparing files $file_a and $file_b\n";
  my @gb;
  foreach my $file($file_a,$file_b) {
    my $gb = GradeBook->read($file); # don't bother with password, since it's read-only
    if (!ref $gb) {die $gb}
    $gb->close();
    push @gb,$gb;
  }
  my $log = $gb[0]->differ($gb[1]);
  if ($log) {
    print "The following is a list of the changes that would have to be made to reconcile the files.\nThe files have not actually been modified\n$log";
    exit 1;
  } 
  else {
   exit 0;
  }
}

# If $out is logically false, write to stdout.
# Format can be old, json, or default, as defined in the comments at the top of GradeBook::write.
sub do_copy {
  my ($in,$out,$format,$in_pwd,$out_pwd,$auth) = @_;
  if (!$in) {die "no input file specified on command line for --copy"}
  my $to_stdout = 0;
  my $describe_out = $out;
  if (!$out) {$out = POSIX::tmpnam(); $to_stdout = 1; $describe_out = 'stdout'}
  #print STDERR "copying from $in to $describe_out, output format=$format\n";
  my $gb = GradeBook->read($in,$in_pwd);
  if (!ref $gb) {die $gb}
  $gb->close();
  if ($auth && $gb->{AUTHENTICITY}) {
    die $gb->{AUTHENTICITY};
  }
  if (!defined $out_pwd) {$out_pwd = $in_pwd}
  $gb->password($out_pwd);
  my $err = $gb->write_to_named_file($out,$format);
  die $err if $err;
  if ($to_stdout) {open(FILE,"<$out") or die "error, temp file $out doesn't exist"; my $data; my $x=sub {local $/; $data=<FILE>;};  &$x(); print $data; unlink $out}
}

sub catch_signals {
  $SIG{TERM} = sub{panic('term')};
  $SIG{INT}  = sub{panic('int')};
  $SIG{QUIT} = sub{panic('quit')};
  $SIG{TSTP} = sub{panic('tstp')};
  $SIG{HUP}  = sub{panic('hup')};
  $SIG{ABRT} = sub{panic('abrt')};
  $SIG{SEGV} = sub{panic('segv')};
      # ... segmentation violation could indicate data are corrupted, in which
      # case you wouldn't want to save to disk; however, the data is all
      # pure Perl, and when segvs occur, they're presumably occurring in
      # Perl/Tk, which means saving the data is the right thing to do.
}

sub add_to_list_of_open_files {
    my $gb = shift;
    push @open_files,$gb;
}

sub remove_from_list_of_open_files {
    my $gb = shift;
    for (my $j=0; $j<=$#open_files; $j++) {
        my $x = $open_files[$j];
        if ($gb==$x) {
					  for (my $k=$j; $k<=$#open_files-1; $k++) {
                $open_files[$k] = $open_files[$k+1];
					  }
            $#open_files = ($#open_files)-1; 
        }
    }
}

# Try to do an auto-save when we get a TERM signal or something like that.
sub panic {
    my $signal = shift;
    my $list = clean_up_before_exiting();
    die "\nOpenGrade has been terminated, signal=$signal. $list\n";
}


sub clean_up_before_exiting {
    my $list = close_all();
    if (!$gui) {Term::ReadKey::ReadMode("normal")};
          # ...Otherwise the terminal can be left in a goofy mode.
          # Trying to do this when the GUI is running causes it to freeze, if the gui was run with an & from the command line.
    return $list;
}


sub close_all {
    my $list = "";
    foreach my $gb(@open_files) {
        if (ref($gb)) {
          $gb->auto_save();
          $list = $list . ", " . $gb->autosave_filename();
        }
    }
    if ($list eq "") {
        $list = "";
    }
    else {
        $list =~ s/^, //;
        $list = "The following files have been auto-saved: ".$list;
    }
    return $list;
}