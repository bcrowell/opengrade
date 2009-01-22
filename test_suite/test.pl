use strict;

my @sample_files = qw(new_no_watermark.gb  new_watermarked.gb  old_no_watermark.gb  old_watermarked.gb);

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
test_no_failure(<<TEST
  opengrade --copy --modify='delete_category,["e"]' --undo new_watermarked.gb >temp1.gb &&
  opengrade --identical new_watermarked.gb temp1.gb
TEST
);

unlink("temp1.gb");

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
