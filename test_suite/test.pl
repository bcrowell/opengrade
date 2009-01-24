use strict;

my @sample_files = qw(new_no_watermark.gb  new_watermarked.gb  old_no_watermark.gb  old_watermarked.gb);

#######################################################################################################################

header("read files in OpenGrade 2.x and 3.x formats, with and without watermarks");
for (my $i=1; $i<@sample_files; $i++) {
  test_no_failure(qq(opengrade --identical $sample_files[0] $sample_files[$i]));
}

header("extract grades");
test_output(qq(opengrade --query="grades,e,newton_ike,1" new_watermarked.gb),'77');
test_output(qq(opengrade --query="grades,e,newton_ike,3" new_watermarked.gb),'null');

header("copy a file without corruption of data");
test_no_failure(qq(opengrade --copy new_watermarked.gb >temp1.gb && opengrade --identical new_watermarked.gb temp1.gb));

header("delete a category");
test_output(qq(opengrade --copy --modify='delete_category,["e"]' new_watermarked.gb >temp1.gb && opengrade --query="grades,e,newton_ike,1" temp1.gb),'null');
test_output(qq(opengrade --query="grades,att,curie_marie,first_meeting" temp1.gb),qq("p")); # temp1.gb is left over from the previous test; make sure other data not deleted

header("undo");

#---------- single undo ------------
test_no_failure(<<TEST
  opengrade --copy --modify='delete_category,["e"]' --undo=1 new_watermarked.gb >temp1.gb &&
  opengrade --identical new_watermarked.gb temp1.gb
TEST
);

#---------- multiple undo ------------
open(F,">commands_temp");
print F <<COMMANDS;
delete_category,["e"]
delete_category,["att"]
COMMANDS
close F;
test_no_failure(<<TEST
  opengrade --copy --modify='<commands_temp' --undo=2 new_watermarked.gb >temp1.gb &&
  opengrade --identical new_watermarked.gb temp1.gb
TEST
);

#---------- undo setting grade ------------
test_no_failure(<<TEST
  opengrade --copy --modify='set_grades_on_assignment,["CATEGORY","e","ASS","1","GRADES",{"newton_ike":33}]' --undo=1 new_watermarked.gb >temp1.gb &&
  opengrade --identical new_watermarked.gb temp1.gb
TEST
);

#---------- single undo after setting multiple grades; important in order to test shortcut that we use for efficiency on undo for setting grades------------
open(F,">commands_temp");
print F <<COMMANDS;
set_grades_on_assignment,["CATEGORY","e","ASS","1","GRADES",{"newton_ike":33}]
set_grades_on_assignment,["CATEGORY","e","ASS","1","GRADES",{"curie_marie":22}]
COMMANDS
close F;
test_output(<<TEST
  opengrade --copy --modify='<commands_temp' --undo=1 new_watermarked.gb >temp1.gb &&
  opengrade --query="grades,e,curie_marie,1" temp1.gb
TEST
,
97
);


#######################################################################################################################

unlink("temp1.gb");
unlink("commands_temp");

#######################################################################################################################

sub header {
  my $message = shift;
  print "$message\n";
}

sub test_output {
  my $shell = shift;
  my $expected = shift;
  show_shell("`$shell` == $expected");
  my $result = qx($shell);
  die "unexpected error running '$shell', return value \$?>>8=".($?>>8) if $?;
  $result eq $expected or die "result of '$shell' was $result, expected $expected";
}

sub test_no_failure {
  my $shell = shift;
  show_shell($shell);
  system($shell)==0 or die "test using '$shell' failed, $?"
}

sub show_shell {
  my $x = shift;
  print "        $x\n";
}
