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

package ServerDialogs;

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
  local $Words::words_prefix = "b.menus";
  my @items = ();
  &$add_item("SERVER_MENUB",\@items,'settings','',sub {set_options($self)});
  &$add_item("SERVER_MENUB",\@items,'class_description','',sub{server($self,'class_description')});
  &$add_item("SERVER_MENUB",\@items,'roster','',sub{server($self,'roster')});
  &$add_item("SERVER_MENUB",\@items,'list_work','',sub{server($self,'list_work')});
  &$add_item("SERVER_MENUB",\@items,'upload','',sub{server($self,'upload')});
  &$add_item("SERVER_MENUB",\@items,'disable_or_enable','',sub{server($self,'disable_or_enable')});
  &$add_item("SERVER_MENUB",\@items,'-');
  &$add_item("SERVER_MENUB",\@items,'email','',sub{server($self,'email')});
  &$add_item("SERVER_MENUB",\@items,'emailone','',sub{server($self,'emailone',$self->{ROSTER}->selected())});
  &$add_item("SERVER_MENUB",\@items,'post_message','',sub{server($self,'post_message')});
  &$add_item("SERVER_MENUB",\@items,'post_message_one','',sub{server($self,'post_message_one',$self->{ROSTER}->selected())});
  &$add_item("SERVER_MENUB",\@items,'sent_messages','',sub{server($self,'sent_messages',$self->{ROSTER}->selected())});
  return \@items;
}

=head4 server()

Make requests to the server. The argument tells what kind of request.

=cut
sub server {
  my $self = shift; # BrowserWindow object
  my $what = shift;
  local $Words::words_prefix = "b.server";
  my $gb = $self->{DATA}->{GB};
  my $prefs = $gb->preferences();
  my $recent_dir = $prefs->get('recent_directory');
  my $server_domain = $prefs->get('server_domain');
  my $server_user = $prefs->get('server_user');
  my $server_account = $prefs->get('server_account');
  my $server_key = $prefs->get('server_key');
  my $server_class = $gb->dir();
  my $err_info =  "domain=$server_domain user=$server_user account=$server_account key=$server_key class=$server_class\n";
  #print "$err_info\n";
  my $request = NetOG->new();
  my @generic = ($request,$gb,$server_domain,$server_key,$server_user,$server_account,$server_class,$err_info,
                 $recent_dir,$what);
  if ($what eq 'sent_messages') {
    my $who = shift;
    ServerDialogs::sent_messages(\@generic,$who);
  }
  if ($what eq 'post_message' || $what eq 'post_message_one') {
    my $who = shift;
    ServerDialogs::post_message(\@generic,w('set_server_key'),w('error_connecting'),w('confirm_whole_class'),$who);
  }
  if ($what eq 'email' || $what eq 'emailone') {
    my $who = shift; # may be undef if doing 'email'
    ServerDialogs::get_email_address(\@generic,$who);
  }
  if ($what eq 'class_description') {
    ServerDialogs::class_description(\@generic);
  }
  if ($what eq 'roster') {
    ServerDialogs::roster(\@generic);
  }
  if ($what eq 'disable_or_enable') {
    ServerDialogs::disable_or_enable(\@generic,$self->{DATA});
  }
  if ($what eq 'list_work') {
    ServerDialogs::list_work(\@generic,$self,Browser::main_window());
  }
  if ($what eq "upload") {
    ServerDialogs::upload(\@generic);
  }
}

sub generic {
  my ($generic,$extra_pars,$handler,$extra_pars_for_text_window) = (@_);
  # $extra_pars = hash ref of extra parameters for the request in addition to the standard ones
  # $handler = undef to do nothing with the results; string for title of text window; function ref for custom handler
  my ($request,$gb,$server_domain,$server_key,$server_user,$server_account,$server_class,$err_info,$recent_dir,$what) = @$generic;
  my $handler_sub;
  if (ref $handler) {
    $handler_sub = $handler;
  }
  else {
    $handler_sub = sub {
      my ($err) = @_;
      if ($err ne '') {
        ExtraGUI::error_message("Error, $err, $err_info");
      }
      else {
        ExtraGUI::show_text(TITLE=>$handler,TEXT=>$request->{RESPONSE_DATA},PATH=>$recent_dir,%$extra_pars_for_text_window);
      }
    };
  }
  my $err = $request->be_client(GB=>$gb,
      HOST=>$server_domain,SERVER_KEY=>$server_key,
      PARS=>{'account'=>$server_account,'user'=>$server_user,'class'=>$server_class,%$extra_pars}
      );
  &$handler_sub($err);
}

sub class_description {
  my ($generic) = @_;
  generic($generic,{'what'=>'get_class_data','get_what'=>'description'},Browser::w('class_description'),{});
}

sub roster {
  my ($generic) = @_;
  generic($generic,{'what'=>'get_class_data','get_what'=>'roster'},Browser::w('roster'),{});
}

sub sent_messages {
  my ($generic,$who) = @_;
  generic($generic,{'what'=>'sent_messages','who'=>$who},$who,{WIDTH=>85});
}

sub get_email_address {
  my ($generic,$who) = @_;
  my ($request,$gb,$server_domain,$server_key,$server_user,$server_account,$server_class,$err_info,
        $recent_dir,$what)
           = @$generic;
  my $list = '';
  if ($what eq 'email') {
    my @roster = $gb->student_keys();
    foreach my $who(@roster) {$list = $list.",".$who}
    $list =~ s/^,//;
  }
  if ($what eq 'emailone') {
    $list = $who;
  }
  generic($generic,{'what'=>'get_class_data','get_what'=>'email','who'=>$list},$who,{});
}

sub post_message {
    my ($generic,$msg_set_server_key,$msg_error_connecting,$msg_confirm_whole_class,$who) = @_;
    my ($request,$gb,$server_domain,$server_key,$server_user,$server_account,$server_class,$err_info,
        $recent_dir,$what)
           = @$generic;
    my $default_recipient = '*';
    if ($what eq 'post_message_one') {
      $default_recipient = $who;
    }
    my $class_description = find_best_class_description($generic);
    my $post_it = sub {
      my $args = shift;
      my $to = $args->{'to'};
      my $do_email = (1==($args->{'do_email'}));
      my $body = $args->{'body'};
      my $subject = $args->{'subject'};
      my $other_headers = '';
      if (exists $args->{'other_headers'}) {$other_headers = $args->{'other_headers'}}
      my $date = DateOG::current_date_for_message_key();
      if ($to eq '*') {$to = join "," , ($gb->student_keys())} # This lists only active students.
      generic($generic,
              {'what'=>'post_message','body'=>$body,'to'=>"to=$to",'subject'=>"subject=$subject",
               'other_headers'=>$other_headers,'date'=>$date,'hash'=>Fun::hash_usable_in_filename($to.$body.$date),'do_email'=>$do_email,},
              sub {
                my $err = shift;
                if ($err eq '') {$err = $request->{RESPONSE_DATA}}
                if ($err ne '') {
                  if ($err eq 'set_server_key') {$err = $msg_set_server_key}
                  if ($err eq 'error_connecting') {$err = $msg_error_connecting}
                  ExtraGUI::error_message("Error: $err")
                }
              },
              {}
              );
    };
    my @inputs = Fun::server_send_email_construct_inputs($default_recipient,$class_description);
    my $do_form = sub { ExtraGUI::fill_in_form(INPUTS=>\@inputs,CALLBACK=>$post_it,COLUMNS=>1,WIDTH=>120) };
    if ($default_recipient ne '*') {
      &$do_form();
    }
    else {
      ExtraGUI::confirm($msg_confirm_whole_class,sub{my $ok=shift; if ($ok) {&$do_form}});
    }
}

sub find_best_class_description {
    my $generic = shift;
    my ($request,$gb,$server_domain,$server_key,$server_user,$server_account,$server_class,$err_info,
        $recent_dir,$what)
           = @$generic;
    my $class_description = $gb->title(); # in case the following fails because they aren't connected yet
    my $foofoo = $request->be_client(GB=>$gb,
        HOST=>$server_domain,SERVER_KEY=>$server_key,
        PARS=>{'account'=>$server_account,'user'=>$server_user,'class'=>$server_class,
               'what'=>'get_class_data',
               'get_what'=>'description'}
        );
    if ($foofoo eq '') {$class_description = $request->{RESPONSE_DATA}}
    return $class_description;
}

sub disable_or_enable {
    my ($generic,$data) = @_;
    my ($request,$gb,$server_domain,$server_key,$server_user,$server_account,$server_class,$err_info,
        $recent_dir,$what)
           = @$generic;
    my $prefs = $gb->preferences();
    my $server_domain = $prefs->get('server_domain');
    my $server_user = $prefs->get('server_user');
    my $server_account = $prefs->get('server_account');
    my $server_key = $prefs->get('server_key');
    my $server_class = $gb->dir();

    my $who = '';
    my %active = ();
    my @candidates = ();
    my ($lb,$box);
    my @dropped;

    # Get a roster from the server. The server only returns a roster of people who have
    # active accounts.
    my $request = NetOG->new();
    my $err = $request->be_client(GB=>$gb,
        HOST=>$server_domain,SERVER_KEY=>$server_key,
        PARS=>{'account'=>$server_account,'user'=>$server_user,'class'=>$server_class,
               'what'=>'get_class_data',
               'get_what'=>'roster'}
        );
    my @active = split /\s+/,($request->{RESPONSE_DATA});
    foreach my $active(@active) {$active{$active}=1}
    if ($err ne '') {ExtraGUI::error_message("Error, $err, $err_info")}
    if (!$err) {
      @dropped = $gb->student_keys("dropped");
      foreach my $dropped(@dropped) {
        push @candidates,$dropped if exists $active{$dropped};
      }
    }
    if (!(@candidates)) {
      ExtraGUI::error_message("There are no dropped students whose Spotter accounts are active.");
      $err = 1;
    }
    if (!$err) {
      $box = Browser::empty_toplevel_window(Browser::w('deactivate_whom'));
      $lb = $box->Scrolled("Listbox",-scrollbars=>"e")
                         ->pack(-side=>'top',-expand=>1,-fill=>'y');
      my @names = ();
      my %name_to_key;
      foreach my $key(@candidates) {
        my $name = $data->key_to_name(KEY=>$key);
        push @names,$name;
        $name_to_key{$name} = $key;
      }
      $lb->insert('end',@names);
      $lb->bind('<Button-1>',
        sub {
          $who = $name_to_key{$lb->get($lb->curselection())};
        }
      );
      $box->Button(-text=>Browser::w("ok"),-command=>sub{
        $box->destroy();
        my $request = NetOG->new();
        my $err = $request->be_client(GB=>$gb,
          HOST=>$server_domain,SERVER_KEY=>$server_key,
          PARS=>{'account'=>$server_account,'user'=>$server_user,'class'=>$server_class,
                 'what'=>'disable','who'=>$who,
                }
          );
        if ($err ne '') {ExtraGUI::error_message("Error, $err, $err_info")}
      })->pack();
      $box->Button(-text=>Browser::w("cancel"),-command=>sub{$box->destroy()})->pack();
    }
}

sub upload {
    my ($generic) = @_;
    my ($request,$gb,$server_domain,$server_key,$server_user,$server_account,$server_class,$err_info,
        $recent_dir,$what)
           = @$generic;
    my $n = 40;
    my ($bar,$w,$text);


    $w = Browser::empty_toplevel_window('uploading');
    $w->geometry(ExtraGUI::preferred_location());
    $text = "-" x $n;
    $w->withdraw();
    $w->Label(-text=>'uploading...')->pack(-side=>'top');
    $bar = $w->Label(-textvariable=>\$text,-font=>ExtraGUI::font('fixed_width'))->pack(-side=>'top');

    $w->deiconify();
    $w->raise();
    my $error = Report::upload_grades(GB=>$gb,
         PROGRESS_BAR_CALLBACK=>sub{
            my $x = shift;
            my $m = $x*$n;
            Browser::main_window()->update;
            $text = ("=" x $m . "-" x ($n-$m));
            Browser::main_window()->update;
          },
          FINAL_CALLBACK=>sub{
            $w->destroy()
          }
    );
    if ($error ne '') {ExtraGUI::error_message($error)}
}

sub list_work {
    my ($generic,$self,$mw) = @_;
    my ($request,$gb,$server_domain,$server_key,$server_user,$server_account,$server_class,$err_info,
        $recent_dir,$what)
           = @$generic;
    my $err = $request->be_client(GB=>$gb,
        HOST=>$server_domain,SERVER_KEY=>$server_key,
        PARS=>{'account'=>$server_account,'user'=>$server_user,'class'=>$server_class,
               'what'=>'get_class_data',
               'get_what'=>'list_work'}
        );
    if ($err ne '') {ExtraGUI::error_message("Error, $err")}
    else {
    my $list = $request->{RESPONSE_DATA};
    my $box = Browser::empty_toplevel_window('');
    my $f1 = $box->Frame()->pack();
    my $due = $gb->most_recent_class_meeting(DateOG::current_date_sortable());
    my $time = $gb->time();
    ($due,$time) = Fun::server_list_work_add_time_slop($due,$time,1);
    $due = "$due $time";
    $f1->Label(-text=>'due date')->pack(-side=>'left');
    $f1->Entry(-width=>16,-textvariable=>\$due)->pack(-side=>'left');
    $box->Frame->pack()->Label(-text=>"Today is ".DateOG::current_date("month").'-'.DateOG::current_date("day"))->pack(-side=>'left');
    my $s = $box->Scrolled("Canvas",-scrollbars=>'e',-height=>(($mw->screenheight)-150),-width=>400,)->pack();
    my @checked;
    my ($n,$stuff) = list_work_populate_list_of_assignments($s,$list,\@checked);
    my @stuff = @$stuff;
    my %scores;
    my @roster;
    my $f = $box->Frame();
    my $get_em = sub {
                 my $do_what = shift;
                 $box->destroy();
                 my $which = '';
                 for (my $i=0; $i<$n; $i++) {
                   if ($checked[$i]) {$which = $which . $stuff[$i]."\n"}
                 }
                 $request->be_client(GB=>$gb,
                      HOST=>$server_domain,SERVER_KEY=>$server_key,
                      PARS=>{'account'=>$server_account,'user'=>$server_user,'class'=>$server_class,
                             'what'=>'get_class_data','get_what'=>'get_scores','due'=>$due,'which'=>$which,
                             'client_time_zone'=>Fun::my_time_zone()
                             }
                 );
                 my $r = $request->{RESPONSE_DATA};
                 @roster = $gb->student_keys();
                 my ($t,$s) = Fun::server_list_work_construct_request(\@roster,$r,$gb);
                 my %scores = %$s;
                 if ($do_what eq 'show') {
                   ExtraGUI::show_text(TITLE=>'',TEXT=>$t,PATH=>$recent_dir);
                 }
                 if ($do_what eq 'save') {
                    my $a_key = shift;
                    foreach my $who(@roster) {
                      if (exists $scores{$who}) {
                        $self->grades_queue(ACTION=>'put',KEY=>"$who.$a_key",SCORE=>$scores{$who}); # sets is_modified(1)
                      }
                    }
                    $self->grades_queue();
                    $self->refresh_assignments();
                 }
    };
    $f->Button(-text=>'ok',
               -command=>sub {&$get_em('show')}
    )->pack(-side=>'left');
    $f->Button(-text=>'cancel',-command=>sub{$box->destroy()})->pack(-side=>'left');
    $f->Button(
             -text=>"view log",
             -command=>sub
               {
                 $box->destroy();
                 my $which = '';
                 for (my $i=0; $i<$n; $i++) {
                   if ($checked[$i]) {$which = $which . $stuff[$i]."\n"} 
                 }
                 if ($which eq '') {ExtraGUI::error_message('no assignments specified')}
                 #print "n=$n, which=$which\n";
                 $request->be_client(GB=>$gb,
                      HOST=>$server_domain,SERVER_KEY=>$server_key,
                      PARS=>{'account'=>$server_account,'user'=>$server_user,'class'=>$server_class,
                             'what'=>'get_class_data','get_what'=>'answers','which'=>$which,
                             }
                 );
                 my $r = $request->{RESPONSE_DATA};
                 ExtraGUI::show_text(TITLE=>$which,TEXT=>$r,WIDTH=>100,PATH=>$recent_dir);
               }
    )->pack(-side=>'left');
    if ($self->{ASSIGNMENTS}->specific_assignment_selected()) {
      my $ass = $self->{ASSIGNMENTS}->selected();
      $ass =~ m/([^\.]*)\.([^\.]*)/;
      my ($c,$a) = ($1,$2);
      my $ass_name = $gb->assignment_name($c,$ass);
      $f->Button(
             -text=>"save in $ass_name",
             -command=>sub{&$get_em('save',$ass)}
      )->pack(-side=>'left');
    }
    $f->pack();
    $box->geometry(ExtraGUI::preferred_location());
    }#end if no error
}

sub list_work_populate_list_of_assignments {
    my ($s,$list,$checked_ref) = @_;
    my ($a,$b,$foo) = Fun::server_list_work_massage_list_of_problems($list);
    my @list = @$a;
    my @raw_and_cooked = @$b;
    my @stuff = @$foo;
    my $c = $s->Subwidget("canvas");
    my $n = 0;
    foreach my $rc(@raw_and_cooked) {
      my $raw = $rc->{'raw'};
      my $cooked = $rc->{'cooked'};
      my $b = $s->Checkbutton(-text=>$cooked,-variable=>\($checked_ref->[$n]));
      $checked_ref->[$n] = 0;
      $s->createWindow(0,25*($n+1),-window=>$b,-anchor=>'w');
      $n++;
    }
    return ($n,\@stuff);  
}

sub set_options {
    my $self = shift;
    my $gb = $self->{DATA}->{GB};
    local $Words::words_prefix = "b.options.web";
    my $prefs;
    if ($gb) {$prefs = $gb->preferences()} else {$prefs = Preferences->new()}
    my $username = UtilOG::guess_username();
    my $web_callback = sub {
      my $results = shift;
      my $prefs = $gb->preferences();
      $prefs->set('server_domain',$results->{'domain'});
      $prefs->set('server_user',$results->{'user'});
      $prefs->set('server_account',$results->{'account'});
      $prefs->set('server_key',$results->{'key'});
      $gb->dir($results->{'class'});
      $self->is_modified(1);
    };
    my $default_domain = $prefs->get('server_domain');
    #print "default_domain=$default_domain\n";
    if ($default_domain eq '') {$default_domain='lightandmatter.com'}
    my $default_user = $prefs->get('server_user');
    if ($default_user eq '') {$default_user=$username}
    my $default_account = $prefs->get('server_account');
    if ($default_account eq '') {$default_account=$username}
    my $default_key = $prefs->get('server_key');
    ExtraGUI::fill_in_form(
      TITLE=>w('title'),
      CALLBACK=>$web_callback,
      COLUMNS=>1,
      INPUTS=>[
        Input->new(KEY=>"domain",PROMPT=>w('server'),TYPE=>'string',DEFAULT=>$default_domain),
        Input->new(KEY=>"user",PROMPT=>w("server_username"),TYPE=>'string',DEFAULT=>$default_user),
        Input->new(KEY=>"account",PROMPT=>w("server_account"),TYPE=>'string',DEFAULT=>$default_account),
        Input->new(KEY=>"class",PROMPT=>w("server_class"),TYPE=>'string',DEFAULT=>$gb->dir()),
        Input->new(KEY=>"key",PROMPT=>w("server_key"),TYPE=>'string',DEFAULT=>$default_key),
      ]
    );
}

sub enable_and_disable_menu_items {
  my ($self,$data,$dir,$student) = @_;
  my $server_menub = $self->{SERVER_MENUB};
  if ($data->file_is_open() && $student ne "") {
    $server_menub->entryconfigure($dir->{'SERVER_MENUB*emailone'},-state=>'normal',
                       -label=>(sprintf w('emailonename'),$data->key_to_name(KEY=>$student,ORDER=>'firstlast')));
    $server_menub->entryconfigure($dir->{'SERVER_MENUB*post_message_one'},-state=>'normal',
                       -label=>(sprintf w('post_message_name'),$data->key_to_name(KEY=>$student,ORDER=>'firstlast')));
    $server_menub->entryconfigure($dir->{'SERVER_MENUB*sent_messages'},-state=>'normal',
                       -label=>(sprintf w('sent_messages_name'),$data->key_to_name(KEY=>$student,ORDER=>'firstlast')));
  }
  else { # no student selected
    $server_menub->entryconfigure($dir->{'SERVER_MENUB*emailone'},-state=>'disabled');
    $server_menub->entryconfigure($dir->{'SERVER_MENUB*post_message_one'},-state=>'disabled');
    $server_menub->entryconfigure($dir->{'SERVER_MENUB*sent_messages'},-state=>'disabled');
  }
  if ($data->file_is_open()) {
    $server_menub->entryconfigure($dir->{'SERVER_MENUB*settings'},-state=>'normal');
    $server_menub->entryconfigure($dir->{'SERVER_MENUB*class_description'},-state=>'normal');
    $server_menub->entryconfigure($dir->{'SERVER_MENUB*roster'},-state=>'normal');
    $server_menub->entryconfigure($dir->{'SERVER_MENUB*list_work'},-state=>'normal');
    $server_menub->entryconfigure($dir->{'SERVER_MENUB*upload'},-state=>'normal');
    $server_menub->entryconfigure($dir->{'SERVER_MENUB*email'},-state=>'normal');
    $server_menub->entryconfigure($dir->{'SERVER_MENUB*post_message'},-state=>'normal');
  }
  else {
    $server_menub->entryconfigure($dir->{'SERVER_MENUB*settings'},-state=>'disabled');
    $server_menub->entryconfigure($dir->{'SERVER_MENUB*class_description'},-state=>'disabled');
    $server_menub->entryconfigure($dir->{'SERVER_MENUB*roster'},-state=>'disabled');
    $server_menub->entryconfigure($dir->{'SERVER_MENUB*list_work'},-state=>'disabled');
    $server_menub->entryconfigure($dir->{'SERVER_MENUB*upload'},-state=>'disabled');
    $server_menub->entryconfigure($dir->{'SERVER_MENUB*email'},-state=>'disabled');
    $server_menub->entryconfigure($dir->{'SERVER_MENUB*post_message'},-state=>'disabled');
  }
}

#----------------------------------------------------------------

1;
