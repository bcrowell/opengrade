use strict;

my $n = 10; # number of assignments

open(F,">commands_temp");
print F qq(add_category,["e","",null]),"\n";
foreach my $i(1..$n) {
  print F qq(add_assignment,["CATEGORY","e","ASS",$i]),"\n";
}
foreach my $i(ord('a')..ord('z')) {
  foreach my $j(ord('a')..ord('z')) {
    my $c1 = chr($i);
    my $c2 = chr($j);
    print F qq(add_student,["LAST","$c1$c2","FIRST","joe"]),"\n";
    foreach my $k(1..$n) {
      print F qq(set_grades_on_assignment,["CATEGORY","e","ASS",$k,"GRADES",{"$c1$c2":1}]),"\n";
    }
  }
}
close F;
system(qq(opengrade --verbose --copy --modify='<commands_temp' blank.gb >a.gb))==0 or die "error, $!";
print STDERR "Output was written to a.gb\n";

unlink("commands_temp");
