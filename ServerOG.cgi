#!/usr/bin/perl

#----------------------------------------------------------------
# Copyright (c) 2001 Benjamin Crowell, all rights reserved.
#
# This software is available under two different licenses: 
#  version 2 of the GPL, or
#  the Artistic License. 
# The software is copyrighted, and you must agree to one of
# these licenses in order to have permission to copy it. The full
# text of both licenses is given in the file titled Copying.
#
#----------------------------------------------------------------

use strict;

# The following four modules are distributed with Spotter, not with OpenGrade:
use FileTree;
use Query;
use WorkFile;
use Email;

use utf8;
use NetOG;
use Time::Local;

#$| = 1; # Set output to flush directly (for troubleshooting)

#----------------------------------------------------------------
# Initialization
#----------------------------------------------------------------


open(LOG_FILE,">>ServerOG.log");
my $request = NetOG->new();
$request->be_server_accepting();
my $account = $request->request_par('account');
my $user = $request->request_par('user');
print LOG_FILE "Got request, user=$user, account=$account, date=".(scalar localtime)."\n";
$account =~ s/[^\w]//g;
$user =~ s/[^\w]//g;
my $instructor_info_file = "spotter/$account/$user.instructor_info";
my $sessions_file = "spotter/$account/$user.sessions";
if (! -e $instructor_info_file) {print LOG_FILE "  instructor info file $instructor_info_file not found\n"}
if (! -r $instructor_info_file) {print LOG_FILE "  instructor info file $instructor_info_file not readable\n"}
if (-e $instructor_info_file && ! -e $sessions_file) {open(MAKE_IT,">$sessions_file"); close(MAKE_IT)}
my $err = $request->be_server_validating(INSTRUCTOR_INFO_FILE=>$instructor_info_file,
                               SESSIONS_FILE=>$sessions_file);
if ($err) {print LOG_FILE "  error validating request, $err\n";}
my $describe_validity;
if ($request->{VALID}) {
  $describe_validity = 'valid';
}
else {
  $describe_validity = 'not valid';
}
print LOG_FILE "  Request was $describe_validity.\n";
if ($request->{VALID}) {
  my $class = '';
  my $tree;
  my $what = $request->request_par('what');
  print LOG_FILE "  Type of request=$what\n";
  my $response_data = '';
  my $response_pars = {};
  if ($request->request_par('class')) {
    $class = $request->request_par('account').'/'.$request->request_par('class');
    $class =~ s/[^\w\/]//g;
    $tree = FileTree->new(DATA_DIR=>$request->{DATA_DIR},CLASS=>$class);
    if ($tree->class_err()) {
      my $err = $tree->class_err();
      $what = ''; # don't try to process request
      print LOG_FILE "  error: $err\n";
      $request->be_server_responding(PARS=>{'err'=>1},DATA=>$err);
    }
    print LOG_FILE "  Class=$class\n";
    if ($what eq 'disable') {
      my $who = $request->request_par('who');
      my $info_file = $tree->student_info_file_name($who);
      my $err = '';
			open(FILE,"<$info_file") or $err=die "Error opening file $info_file for input";
      if (!$err) {
  			my $stuff = '';
  			while (my $line= <FILE>) {
  				$stuff = $stuff .  $line;
  			}
  			close(FILE);
  			$stuff =~ s/disabled=\"0\"/disabled=\"1\"/;
  			open(FILE,">$info_file") or die "Error opening file $info_file for output";
  			print FILE $stuff;
  			close(FILE);
  		}
      $request->be_server_responding(DATA=>$err);
    }
    if ($what eq 'sent_messages') {
      my $who = $request->request_par('who');
      my $msgs = $tree->messages_directory();
      if (! -e $msgs) {mkdir($msgs)}
      my $list_file = "$msgs/$who";
      my $err = '';
      if (!open(FILE,"<$list_file")) {$err = "Error opening file $list_file for input"}
      my $response_data = '';
      if ($err eq '') {
        my %when_received = ();
        my %text = ();
        my %when_sent = ();
        while (my $line=<FILE>) {
          $line =~ m/([^,]+),([^,]+),([^,]+)$/;
          my ($what,$when,$msg) = ($1,$2,$3);
          $when_sent{$msg} = $when  if ($what =~ 'sent');
          $when_received{$msg} = $when if ($what =~ 'received');
          my $tfile = "$msgs/$msg";
          my $text = '';
          if (open(TFILE,"<$tfile")) {
            while (my $tline=<TFILE>) {
              $text = $text . $tline;
            }
            close TFILE;
          }
          else {
            $text = "error opening file $tfile\n";
          }
          $text{$msg} = $text;
        }
        close FILE;
        foreach my $msg(sort keys %text) {
          my $text = '';
          $text = $text . "sent $when_sent{$msg}\n" if exists $when_sent{$msg};
          $text = $text . "received $when_received{$msg}\n" if exists $when_received{$msg};
          my $stuff = $text{$msg};
          $stuff =~ s/^to=[^\n]+//; # to line not needed, is often lengthy if it went to whole class
          $text = $text . $stuff;
          $response_data = $response_data . ('=' x 80) . "\n" . $text;
        }
      }
      if ($err ne '') {print LOG_FILE "  err=$err\n"; $response_data = $err}
      $request->be_server_responding(DATA=>$response_data);
    }
    if ($what eq 'post_message') {
      my $body = $request->request_par('body');
      my $to = $request->request_par('to');
      my $do_email = $request->request_par('do_email');
      my $subject = $request->request_par('subject');
      my $other_headers = $request->request_par('other_headers');
      my $date = $request->request_par('date');
      my $hash = $request->request_par('hash');
      my $msgs = $tree->messages_directory();
      if (! -e $msgs) {mkdir($msgs)}
      my $headers = "$to\n$subject\n$other_headers\n";
      $headers =~ s/\n\n/\n/g;
      my $key = "$date-$hash";
      my $filename = "$msgs/$key";
      my $whole_message = "$headers\n$body\n";
      $headers =~ s/\n\n$/\n/;
      print LOG_FILE "  Messages directory is $msgs\n";
      print LOG_FILE "  body=$body\n";
      print LOG_FILE "  to=$to\n";
      print LOG_FILE "  do_email=$do_email\n";
      print LOG_FILE "  subject=$subject\n";
      print LOG_FILE "  other_headers=$other_headers\n";
      print LOG_FILE "  date=$date\n";
      print LOG_FILE "  hash=$hash\n";
      print LOG_FILE "  filename=$filename\n";
      my $err = '';
      if (!open(FILE,">$filename")) {$err = "Error opening file $filename for output"}
      if ($err eq '') {
        print FILE $whole_message;
        close FILE;
      }
      if ($err eq '') {
              $to =~ m/to\=(.*)/;
        my @recipients = split /,/ , $1;
        my @failed = ();
				my %failure_reasons = ();
        # Build a table of students who actually have accounts:
          my @roster = $tree->get_roster();
          my %roster = ();
          foreach my $student(@roster) {
            $roster{$student} = 1;
          }
        # Try to send all the messages:
        my $any_succeeded = 0;
        my $any_failed = 0;

        my $email_severe_error = 0;
        foreach my $recipient(@recipients) {

          my $this_one_succeeded = 1; # to be ANDed with other stuff
          my $this_one_failed = 0; # to be ORed with other stuff
          my $err = '';

          #----- Put the message where they'll see it when they log in to Spotter:
          if ((exists $roster{$recipient}) && open(FILE,">>$msgs/$recipient")) {
            print FILE "    sent,$date,$key\n";
            close FILE;
          }
          else {
            $this_one_failed = 1;
            $this_one_succeeded = 0;
            $err = "error for recipient $recipient: doesn't exist in roster, or unable to append to file $msgs/$recipient";
          } # open to append; create if necessary

          #----- Email it as well:
          if ($do_email && !$email_severe_error) {
            my $email = $tree->get_student_par($recipient,"email");
            print LOG_FILE "  email address=$email\n";
            $subject =~ m/subject\=(.*)/;
            my $email_subject = $1;
            my $email_body = "$body\n---\nReplying to this address will not work. To reply, log in to Spotter and click on e-mail.\n";
            if ($email ne '') {
              print LOG_FILE "  sending e-mail\n";
              my $r = Email::send_email(TO=>$email,SUBJECT=>$email_subject,BODY=>$email_body,DK=>1);
              my $err2 = $r->[0];
              my $severity2 = $r->[1];
              print LOG_FILE "  ...result=$err2=\n";
              if ($err2 ne '') {
                $this_one_failed = 1;
                $this_one_succeeded = 0;
                $err = $err . $err2;
                if ($severity2>=2) {$email_severe_error = 1; $err = $err . ' Because a severe error occurred while sending email, no more attempts to send email will be made.'}
              }
            }
          }

          if ($this_one_failed) {
            push @failed,$recipient;
            $failure_reasons{$recipient} = $err;
          }
          $any_succeeded = $any_succeeded || $this_one_succeeded;
          $any_failed    = $any_failed    || $this_one_failed;

        }# end loop over recipients

        if ($any_succeeded && $any_failed) {$err = "Failed to send message to these students: ".(join ",",@failed)}
        if ($any_failed && !$any_succeeded) {$err = "Failed to send message to any recipients."}
        if ((!$any_failed) && (!$any_succeeded)) {$err = "The list of recipients was empty."}
				if ($any_failed) {
          foreach my $recipient(keys %failure_reasons) {
            $err = $err . $failure_reasons{$recipient};
          }
				}
      }
      if ($err ne '') {print LOG_FILE "  err=$err\n"}
      $request->be_server_responding(DATA=>$err);
    }
    if ($what eq 'upload_grade_report') {
      my $who = $request->request_par('who');
      my $report = $request->request_par('report');
      my $file_name = $tree->grade_report_file_name($who);
      my $err = '';
      open(FILE,">$file_name") or $err="error opening output file $file_name, $!";
      if (!$err) {
        print FILE $report;
        close FILE;
      }
      my $response_data = '';
      if ($err eq '') {
        $response_data = "ok $file_name";
      }
      else {
        $response_data = "error $err";
        print LOG_FILE "  error=$err, $!\n" if $err;
      }
        $request->be_server_responding(DATA=>$response_data);
    }
    if ($what eq 'back_up_gradebook_file') {
      my $contents = $request->{REQUEST_DATA};
      my $file_name = $tree->class_dir()."/".$request->request_par('name');
      open(FILE,">$file_name");
      print FILE $contents;
      close FILE;
      $request->be_server_responding(DATA=>$file_name);
    }
    if ($what eq 'get_class_data') {
      my $get_what = $request->request_par('get_what');
      print LOG_FILE "  Get_what=$get_what\n";
      $response_data = '';
      if ($get_what eq 'description') {
        $response_data = $tree->class_description();
        #$response_data = $response_data . "foo";
      }
      if ($get_what eq 'roster') {
        my @roster = sort $tree->get_roster();
        foreach my $student(@roster) {
          $response_data = $response_data . "$student\n";
        }
      }
      if ($get_what eq 'email') {
        my $list = $request->request_par('who');
        while ($list =~ m/([^,]+)/g) {
          my $student = $1;
          my $it = $tree->get_student_par($student,"email");
          if ($it ne '' && $it =~ m/.+\@.+\..+/) {$response_data = $response_data . $it . ','}
        }
        $response_data =~ s/,$//;
        $response_data = $response_data . "\n";
      }
      if ($get_what eq 'list_work') {
        my @queries = WorkFile::list_all_work($tree);
        foreach my $query(@queries) {
          $response_data = $response_data . $query."\n";
        }
      }
      if ($get_what eq 'answers') {
        my $problem =  $request->request_par('which');
        my ($whole,$part) = ($problem,'');
        if ($problem =~ m/^(.*)\&find=([^\&]*)$/) {
          ($whole,$part) = ($1,$2);
        }
        $response_data = $response_data . WorkFile::report_answers_on_one_problem($tree,$problem);
      }
      if ($get_what eq 'get_scores') {
        my $due =  $request->request_par('due');
        my $list =  $request->request_par('which');
        my $client_time_zone =  $request->request_par('client_time_zone');
        my $server_time_zone = WorkFile::my_time_zone();
        my $time_zone_correction = $client_time_zone-$server_time_zone;
        my @stuff = ();
        while ($list=~m/^(.+)$/mg) {
          push @stuff,$1;
        }
        my @roster = sort $tree->get_roster();
        my %scores = ();
        foreach my $student(@roster) {
          $scores{$student} = {};
        }
        my %wholes = ();
        my @wholes = ();
        foreach my $thing(@stuff) {
          my ($whole,$part) = ($thing,'');
          if ($thing =~ m/^(.*)\&find=([^\&]*)$/) {
            ($whole,$part) = ($1,$2);
          }
          if (!exists($wholes{$whole})) {push @wholes,$whole}
          $wholes{$whole} = 1;
          foreach my $student(@roster) {
            my $got_it = WorkFile::look_for_correct_answer($tree,$student,$thing,$due,$time_zone_correction);
            my $s = $scores{$student};
            if (!exists($s->{$whole})) {
              $s->{$whole} = $got_it;
            }
            else {
              $s->{$whole} = $s->{$whole} && $got_it;
            }
          }
        }
        foreach my $student(@roster) {
            $response_data = $response_data . "$student=";
          my $s = $scores{$student};
          foreach my $whole(@wholes) {
              $response_data = $response_data . $s->{$whole};
          }
            $response_data = $response_data . "\n";
        }
          $response_data = $response_data . "=key";
        foreach my $whole(@wholes) {
            $response_data = "$response_data,$whole";
        }
          $response_data = $response_data . "\n";
      }
      $request->be_server_responding(DATA=>$response_data);
      my $describe_class_data_response;
      if ($response_data ne '') {
        $describe_class_data_response = "response is not a null string";
      }
      else {
        $describe_class_data_response = "response is a null string";
      }
      print LOG_FILE "  Result of get_class_data request: $describe_class_data_response.\n";
    }# end if $what eq 'get_class_data'
  }# end if class par was set
  else {
    print LOG_FILE "  No class specified.\n";
  }
}# end if valid
print LOG_FILE "  Done processing request.\n";
close(LOG_FILE);
