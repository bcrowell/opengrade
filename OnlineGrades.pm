#----------------------------------------------------------------
# Copyright (c) 2008 Benjamin Crowell, all rights reserved.
#
# This software is available under version 2 of the GPL license.
# The software is copyrighted, and you must agree to the
# license in order to have permission to copy it. The full
# text of the license is given in the file titled Copying.
#
#----------------------------------------------------------------

# This package is for all the dialog boxes that are under the Server menu.

use strict;
use Digest::SHA1;

package OnlineGrades;

use ExtraGUI;
use GradeBook;
use Words qw(w get_w);
use MyWords;
use UtilOG;
use DateOG;
use Input;
use NetOG;
use Fun;
use Digest::SHA1;
use Version;
use MyWords;
use DateOG;

sub available {
  return 1;
}

sub create_server_menu {
  my $self = shift; # BrowserWindow object
  my $add_item = shift; # reference to a sub
  local $Words::words_prefix = "b.menus.online_grades";
  my @items = ();
  &$add_item("ONLINE_GRADES_MENUB",\@items,'upload','',sub{upload($self)});
  &$add_item("ONLINE_GRADES_MENUB",\@items,'settings','',sub{set_options($self)});
  return \@items;
}

sub upload {
  my $self = shift;
  my $gb = $self->{DATA}->{GB};
  my $prefs;
  if ($gb) {$prefs = $gb->preferences()} else {$prefs = Preferences->new()}
  my ($t,$err) = create_online_grades_xml($gb);
  if ($err) {
    ExtraGUI::error_message($err);
  }
  else {
    my $recent_dir = $prefs->get('recent_directory');
    my $filename = $gb->file_name();
    my $xml_filename = $filename;
    $xml_filename =~ s/\.gb/\.xml/;
    ExtraGUI::save_plain_text_to_file($t,$recent_dir,$xml_filename);
    # The xml file contains the password, so it's a security risk. Make it not world-readable, and mark it for later deletion.
    if (-e $xml_filename) {
      if (chmod(0600,$xml_filename)==1) {
        $prefs->add_to_list_without_duplication('files_to_delete',$xml_filename);
      }
      else {
        ExtraGUI::error_message("Error setting permissions of file $xml_filename, $!");
      }
    }
  }
}

sub create_online_grades_xml {
  my $gb = shift;
  my $prefs = $gb->preferences();
  my $err;
  my $t = '';
  $t = $t . "<BasmatiL>\n<CLASS>\n";
  my $do_tag = sub {my $tag = shift; my $contents = shift; return '<'.uc($tag).'> '.$contents.' </'.uc($tag).">\n"}; # helper for one-liner tags
  my $tag_from_course_data = sub {my $tag = shift; my $field = shift; return &$do_tag($tag,$gb->class_data($field))};
  my $tag_from_prefs = sub {my $tag = shift; my $field = shift; return &$do_tag($tag,$prefs->get("online_grades_$field"))};
  $t = $t . &$tag_from_course_data('cc','online_grades_course_code');
  $t = $t . &$tag_from_course_data('sn','online_grades_section_number');
  $t = $t . &$tag_from_course_data('cname','title');
  $t = $t . &$tag_from_course_data('misc1','staff');
  $t = $t . &$tag_from_prefs('misc','phone');
  $t = $t . &$tag_from_course_data('misc3','');
  $t = $t . &$tag_from_course_data('per','time');
  $t = $t . &$do_tag('tid',$gb->password());
  $t = $t . &$tag_from_prefs('tname','teacher_name');
  $t = $t . &$tag_from_course_data('term','online_grades_term');
  $t = $t . &$tag_from_course_data('cltext','online_grades_cltext');
  $t = $t . "</CLASS>\n";
  my @c = split(",",$gb->category_list());
  foreach my $c(@c) {
    my $single_assignment_category = $gb->category_property_boolean($c,'single');
    if (!$single_assignment_category) {
      my @a = split(",",$gb->assignment_list());
      foreach my $a(@a) {
        my ($cat,$ass) = (GradeBook::first_part_of_label($a),GradeBook::second_part_of_label($a));
        if ($cat eq $c) {
          my $ass_properties = $gb->assignment_properties($a);
          my $due_date = $ass_properties->{"due"};
          $due_date = DateOG::disambiguate_year($due_date,$gb->term()) if $due_date;
          my $due = ($due_date eq "") || (DateOG::is_past(DateOG::disambiguate_year($due_date,$gb->term())));
          my $max = $gb->assignment_property($a,"max");
          my $ass_name = $gb->assignment_name($cat,$ass);
          my $explain_whether_due = '';
          $explain_whether_due=" (not counted for computing grades, because it isn't due until $due_date)" if !$due; # $due_date guaranteed not null, because then $due is true
          my $ealr = $explain_whether_due;
          $ealr = $ealr . " Extra credit." if ($max==0);
          $t = $t . "<ASSIGN>\n";
          $t = $t . &$do_tag('assign_date',$due_date);
          $t = $t . &$do_tag('descr',$ass_name);
          $t = $t . &$do_tag('points',$max);
          $t = $t . &$do_tag('ealr',$ealr);
          $t = $t . "</ASSIGN>\n";
        }
      }
    }
  }
  my @roster = $gb->student_keys();
  @roster = sort {$gb->compare_names($a,$b)} @roster;
  foreach my $who(@roster) {
    $t = $t . "<STUDENT>\n";
    my $id = $gb->id($who);
    unless ($id=~/^\d+$/) {$err = "Student $who has id \"$id\", which is not a string of digits as required by Online Grades."}
    $t = $t . &$do_tag('id',$id);
    my @scores;
    foreach my $c(@c) {
      my $single_assignment_category = $gb->category_property_boolean($c,'single');
      if (!$single_assignment_category) {
        my @a = split(",",$gb->assignment_list());
        foreach my $a(@a) {
          my ($cat,$ass) = (GradeBook::first_part_of_label($a),GradeBook::second_part_of_label($a));
          if ($cat eq $c) {
            push @scores,$gb->get_current_grade($who,$cat,$ass);
          }
        }
      }
    }
    $t = $t . &$do_tag('scores',join(',',@scores));
    my $frac = Crunch::totals($gb,$who)->{all};
    my ($percentage,$letter) = Report::fraction_to_pct_and_letter($gb,$frac);
    $t = $t . &$do_tag('percent',int($percentage+.5));
    $t = $t . &$do_tag('grade',$letter);
    $t = $t . &$do_tag('comments',',');
    $t = $t . "</STUDENT>\n";
  }
  $t = $t . "</BasmatiL>\n";
  return ($t,$err);
}

sub set_options {
    my $self = shift;
    my $gb = $self->{DATA}->{GB};
    local $Words::words_prefix = "b.options.online_grades";
    my $prefs;
    if ($gb) {$prefs = $gb->preferences()} else {$prefs = Preferences->new()}
    my $username = UtilOG::guess_username();
    my $web_callback = sub {
      my $results = shift;
      my $prefs = $gb->preferences();

      $prefs->set('online_grades_teacher_name',$results->{'teacher_name'});
      $prefs->set('online_grades_phone',$results->{'phone'});

      # per-course data:
      $gb->class_data('staff',$results->{'user'});
      $gb->class_data('title',$results->{'title'});
      $gb->class_data('time',$results->{'period'});
      $gb->class_data('online_grades_cltext',$results->{'cltext'});
      $gb->class_data('online_grades_course_code',$results->{'course_code'});
      $gb->class_data('online_grades_section_number',$results->{'section_number'});
      $gb->class_data('online_grades_term',$results->{'term'});

      $self->is_modified(1);
    };
    my $default_user = $gb->staff() || 'faculty'; # The latter is their demo account.
    my $default_title =  $gb->title();
    my $default_period =  $gb->time();

    my $default_term =  $gb->class_data('online_grades_term') || '';
    my $default_cltext =  $gb->class_data('online_grades_cltext') || '';
    my $default_course_code =  $gb->class_data('online_grades_course_code') || '';
    my $default_section_number =  $gb->class_data('online_grades_section_number') || '';

    my $default_domain = $prefs->get('online_grades_server_domain');
    my $default_teacher_name =  $prefs->get('online_grades_teacher_name') || "Mr./Ms. $default_user";
    my $default_phone =  $prefs->get('online_grades_phone');
    ExtraGUI::fill_in_form(
      TITLE=>w('title'),
      CALLBACK=>$web_callback,
      COLUMNS=>1,
      INPUTS=>[
        #Input->new(KEY=>"domain",PROMPT=>w("server"),TYPE=>'string',DEFAULT=>$default_domain),
        Input->new(KEY=>"user",PROMPT=>w("server_username"),TYPE=>'string',DEFAULT=>$default_user),
        Input->new(KEY=>"title",PROMPT=>w("server_title"),TYPE=>'string',DEFAULT=>$default_title),
        Input->new(KEY=>"course_code",PROMPT=>w("server_course_code"),TYPE=>'string',DEFAULT=>$default_course_code),
        Input->new(KEY=>"section_number",PROMPT=>w("server_section_number"),TYPE=>'string',DEFAULT=>$default_section_number),
        Input->new(KEY=>"teacher_name",PROMPT=>w("server_teacher_name"),TYPE=>'string',DEFAULT=>$default_teacher_name),
        Input->new(KEY=>"term",PROMPT=>w("server_term"),TYPE=>'string',DEFAULT=>$default_term),
        Input->new(KEY=>"cltext",PROMPT=>w("server_cltext"),TYPE=>'string',DEFAULT=>$default_cltext),
        Input->new(KEY=>"period",PROMPT=>w("server_period"),TYPE=>'string',DEFAULT=>$default_period),
        Input->new(KEY=>"phone",PROMPT=>w("server_phone"),TYPE=>'string',DEFAULT=>$default_phone),
      ]
    );
}

sub enable_and_disable_menu_items {
  my ($self,$data,$dir,$student) = @_;
  my $server_menub = $self->{ONLINE_GRADES_MENUB};
  if ($data->file_is_open()) {
    $server_menub->entryconfigure($dir->{'ONLINE_GRADES_MENUB*settings'},-state=>'normal');
    $server_menub->entryconfigure($dir->{'ONLINE_GRADES_MENUB*upload'},-state=>'normal');
  }
  else {
    $server_menub->entryconfigure($dir->{'ONLINE_GRADES_MENUB*settings'},-state=>'disabled');
    $server_menub->entryconfigure($dir->{'ONLINE_GRADES_MENUB*upload'},-state=>'disabled');
  }
}

#----------------------------------------------------------------

1;
