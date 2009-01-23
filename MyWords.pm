#----------------------------------------------------------------
# Copyright (c) 2002 Benjamin Crowell, all rights reserved.
#
# This software is available under version 2 of the GPL license.
# The software is copyrighted, and you must agree to the
# license in order to have permission to copy it. The full
# text of the license is given in the file titled Copying.
#
#----------------------------------------------------------------

# The interface to this is in Words.pm. You don't ever need to
# access it directly.

package MyWords;


BEGIN {
  sub retrieve {
    my $key = shift;
    return $strings{$key} unless !exists $strings{$key};
    # Can't find the key:
    $key =~ s/^[^\.]+\./en./;   # Is there an English version?
    return $strings{$key} unless !exists $strings{$key};
    return $key;                # Last resort: return the key itself.
  }


%MyWords::strings = (

#--------------------------------------------------
# Generic error messages from the Input module
#--------------------------------------------------
"en.input.blank_not_allowed" => "A blank value is not allowed.",
"en.input.below_min" => "The minimum value is %s.",
"en.input.above_max" => "The maximum value is %s.",
"en.input.illegal_time_format" => "Times must be in the format h:mm or hh:mm.",
"en.input.illegal_date_format" => "Illegal date format: %s. Dates must be in the format month-day or year-month-day. Years, if supplied, must be four digits.",
"en.input.illegal_hour_or_minute" => "Illegal hour or minute.",
"en.input.illegal_month_or_day" => "Illegal month or day: %s.  Dates must be in the format month-day or year-month-day. Years, if supplied, must be four digits.",
#--------------------------------------------------
# "b." strings are for the GUI browser interface
#--------------------------------------------------
'en.b.dialog.none' => 'none',
'en.b.dialog.january' => 'Jan',
'en.b.dialog.february' => 'Feb',
'en.b.dialog.march' => 'Mar',
'en.b.dialog.april' => 'Apr',
'en.b.dialog.may' => 'May',
'en.b.dialog.june' => 'Jun',
'en.b.dialog.july' => 'Jul',
'en.b.dialog.august' => 'Aug',
'en.b.dialog.september' => 'Sep',
'en.b.dialog.october' => 'Oct',
'en.b.dialog.november' => 'Nov',
'en.b.dialog.december' => 'Dec',
'en.b.beep.goofy_key'=>'Invalid key pressed while entering a grade: %s',
'en.b.beep.num_lock'=>'Num lock appears to be turned off.',
'en.b.beep.grade_in_name_column'=>'Hit tab to change to the grade column.',
'en.b.beep.empty_roster'=>'There is no file open, or the roster is empty.',
'en.b.beep.nothing_left_to_delete'=>'There is nothing in the keyboard selection left to delete.',
'en.b.beep.key_not_recognized'=>'Key not recognized: %s',
'en.b.beep.no_such_student'=>"No student's name begins with %s",
'en.b.beep.'=>'',
'en.b.beep.'=>'',
'en.b.beep.'=>'',
"en.b.authentication.inauthentic" => <<STRING,
The digital watermark is not consistent with this password. This is probably because you
typed the password incorrectly. If you're certain you typed the password correctly, then
the file has been altered by someone (perhaps you, perhaps someone else) who did not
authenticate the alterations using your password; in this situation, you should click
on the View Report button and see what lines were changed. See the documentation for
suggestions on how to handle a case of apparent tampering.
STRING
"en.b.authentication.ok" => "OK",
"en.b.authentication.view_report" => "View Report",
"en.b.authentication.autosave_check" => <<STRING,
An autosave file, %s,
exists. This may happen, for instance, if your computer crashes
while OpenGrade has a file open. You should probably hit Cancel, get out of OpenGrade, and
see if the autosave file really has different data in it than the original file.
If you click on OK to open the file, your autosave file will be deleted.
STRING
"en.b.roster_options_menu.grade" => "grade",
"en.b.roster_options_menu.overall" => "overall",
"en.b.main_loop.confirm_revert"=>"Revert all changes, are you sure?",
"en.b.main_loop.startup_info"
  =>"OpenGrade    (c) 2002 B. Crowell, www.lightandmatter.com/ogr/ogr.html",
"en.b.refresh_title.program_name"
  =>"OpenGrade",
"en.b.refresh_header.no_file"
  =>"no file open",
"en.b.is_modified.modified" => "modified, and not saved yet",
"en.b.is_modified.not_modified" => "saved",
"en.b.data.close.written" => "The file %s has been saved.",
"en.b.main_loop.save_as" => "Save As",
"en.b.dialog.save_as" => "Save As",
"en.b.dialog.error_opening_for_output" => "There was an error opening the file %s for output.",
"en.b.dialog.save_on_top_of_gb" => "Can't save on top of a gradebook file.",
"en.b.dialog.save" => "Save",
"en.b.dialog.ok" => "OK",
"en.b.dialog.open" => "Open in an Editor",
"en.b.dialog.print" => "Print",
"en.b.dialog.no_open_command" => "You have not specified a unix shell command to use for opening a file in an editor. See the Preferences menu.",
"en.b.dialog.no_print_command" => "You have not specified a unix shell command to use for printing a file. See the Preferences menu.",
"en.b.dialog.cancel" => "Cancel",
"en.b.dialog.confirm" => "Confirm",
"en.b.dialog.confirm_overwrite" => "The file %s already exists. Overwrite it?",
"en.b.edit_student.title" => "Edit Information for %s",
"en.b.edit_student.id" => "Student ID",
"en.b.edit_student.pwd" => "Password",
"en.b.edit_student.first" => "First Name",
"en.b.edit_student.last" => "Last Name",
"en.b.delete_assignment.confirm" => "Delete %s?",
"en.b.edit_assignment.title" => "Edit Information for %s",
"en.b.edit_assignment.due" => "Due Date",
"en.b.edit_assignment.name" => "Long Name",
"en.b.edit_assignment.key" => "Short Name",
"en.b.edit_assignment.max" => "Maximum Score",
"en.b.edit_assignment.ignore" => "Ignored",
"en.b.edit_assignment.mp" => "Marking Period",
"en.b.add_or_drop.confirm" => "Drop %s?",
"en.b.add_or_drop.last" => "last name",
"en.b.add_or_drop.first" => "first name",
"en.b.add_or_drop.id" => "id (optional)",
"en.b.add_or_drop.pwd" => "password (optional, defaults to id)",
"en.b.add_or_drop.add_title" => "Add Students",
"en.b.add_or_drop.reinstate_title" => "Reinstate Student",
"en.b.add_or_drop.ok" => "OK",
"en.b.add_or_drop.cancel" => "Cancel",
"en.b.add_or_drop.add" => "Add",
"en.b.add_or_drop.done" => "Done",
"en.b.add_or_drop.already_exists" => "%s already exists. You may have dropped this student, in which case you can reinstate her/him.",
"en.b.add_or_drop.add_students_info" => <<STRING,
You can add as many students as you like, filling out the form and
clicking on Add each time.
You'll be alerted if the student already exists, or needs to be
reinstated rather than added.
After adding the last student, click on
Add, and then when the blank form reappears, click on Done.
STRING
"en.b.error_message.ok" => "OK",
"en.b.error_message.error" => "Error",
"en.b.menus.file" =>"File",
"en.b.menus.edit_menu" =>"Edit",
"en.b.menus.new" =>"New",
"en.b.menus.open" =>"Open...",
"en.b.menus.close"  =>"Close",
"en.b.menus.rekey"  =>"Change Password",
"en.b.menus.save"  =>"Save",
"en.b.menus.clear_recent"  =>"Clear List of Recent Files",
"en.b.menus.freeze_recent"  =>"Prevent Changes to this List",
"en.b.menus.quit"  =>"Quit",
"en.b.menus.undo" =>"Undo",
"en.b.menus.undo_operation" =>"Undo %s",
"en.b.menus.revert" =>"Revert",
"en.b.menus.students" =>"Students",
"en.b.menus.add" =>"Add",
"en.b.menus.reinstate" =>"Reinstate",
"en.b.menus.drop" =>"Drop %s",
"en.b.menus.edit" =>"Edit Information for %s",
"en.b.menus.edit_disabled" =>"Edit Information",
"en.b.menus.assignments" =>"Assignments",
"en.b.menus.new_assignment_blank" =>"New Assignment",
"en.b.menus.new_assignment" =>"New %s",
"en.b.menus.category_weights" =>"Edit Category Weights",
"en.b.menus.delete_category_blank" =>"Delete Category",
"en.b.menus.delete_category" =>"Delete Category %s",
"en.b.menus.new_category" =>"New Category",
"en.b.menus.edit_category_blank" =>"Edit Category Information",
"en.b.menus.edit_category" =>"Edit Information for %s",
"en.b.menus.edit_assignment_blank" =>"Edit Assignment Information",
"en.b.menus.edit_assignment" =>"Edit Information for %s",
"en.b.menus.delete_assignment_blank" =>"Delete Assignment",
"en.b.menus.delete_assignment" =>"Delete %s",
"en.b.menus.report" =>"Reports",
"en.b.menus.sort_by_overall" => "Overall Grade",
"en.b.menus.sort_by_category" => "Average in %s",
"en.b.menus.sort_by_category_blank" => "Average in Category",
"en.b.menus.sort_by_assignment" => "Score on %s",
"en.b.menus.sort_by_assignment_blank" => "Score on Assignment",
"en.b.menus.spreadsheet" => "Spreadsheet",
"en.b.menus.statistics_ass" => "Statistics for %s",
"en.b.menus.statistics_ass_blank" => "Statistics for an Assignment",
"en.b.menus.table" => "Table",
"en.b.menus.roster" => "Roster",
"en.b.menus.statistics" =>"General Statistics",
"en.b.menus.upload" =>"Post Grades",
"en.b.menus.server" =>"Spotter",
"en.b.menus.settings" =>"Client/Server Settings",
"en.b.menus.class_description" =>"Class Description",
"en.b.menus.roster" =>"Roster",
"en.b.menus.disable_or_enable" =>"Disable Account of Dropped Student",
"en.b.menus.list_work" =>"List Work",
"en.b.menus.email" =>"E-Mail List",
"en.b.menus.emailone" =>"E-Mail for One Student",
"en.b.menus.post_message" =>"Send Message",
"en.b.menus.post_message_one" =>"Send Message to One Student",
"en.b.menus.sent_messages" =>"View Messages Sent to One Student",
"en.b.menus.emailonename" =>"E-Mail for %s",
"en.b.menus.post_message_name" =>"Send Message to %s",
"en.b.menus.sent_messages_name" =>"View Messages Sent to %s",
"en.b.menus.online_grades" =>"Online Grades",
"en.b.menus.online_grades.upload" =>"Export Grades to Online Grades Format for Uploading",
"en.b.menus.online_grades.settings" =>"Settings",
"en.b.menus.standards" =>"Grading Standards",
"en.b.menus.marking_periods" =>"Marking Periods",
"en.b.menus.properties" =>"Properties",
"en.b.menus.clone" =>"Clone",
"en.b.menus.export" =>"Export...",
"en.b.menus.strip_watermark" =>"Remove Watermark",
"en.b.menus.reconcile" =>"Reconcile",
"en.b.menus.student" =>"Student",
"en.b.menus.preferences" =>"Preferences",
"en.b.menus.beep" =>"Beeping",
"en.b.menus.justify" =>"Left or Right Justification of Grades",
"en.b.menus.editor_command" =>"Command Used to Open an External Text Editor",
"en.b.menus.print_command" =>"Command Used to Print a Text File",
"en.b.menus.spreadsheet_command" =>"Command Used to Open a Spreadsheet",
"en.b.menus.hash_function" =>"Type of Digital Watermark",
"en.b.menus.activate_online_grades_plugin" =>"Show Online Grades Menu",
"en.b.menus.activate_spotter_plugin" =>"Show Server Menu for Spotter",
"en.b.menus.restart_to_change_menus" =>"The change you've made to the menu bar will show up the next time you start OpenGrade.",
"en.b.menus.help" =>"Help",
"en.b.menus.about" =>"About OpenGrade",
"en.b.about.about_og" => <<STRING,
--literal--
OpenGrade %s (Perl/Tk version %s, perl version %s, GTK2 version %s)
(c) 2002-2009 Benjamin Crowell

OpenGrade is free software that helps teachers keep track of their students' grades.
On OpenGrade's web page,
  http://www.lightandmatter.com/ogr/ogr.html   ,
you can find documentation, and information about how to contact me.

I'll be especially grateful if you can help me to improve OpenGrade by reporting bugs.
However, before reporting a bug, please make sure that you're running the most current
version of OpenGrade, and that your bug isn't already noted in the documentation. If
you e-mail me to report a bug, please tell me what operating system you're using and
what version of OpenGrade, and also, if possible, attach a copy of your gradebook file
(I realize that there are privacy concerns).

OpenGrade is listed on the Freshmeat web site,
  http://freshmeat.net   ,
where you can look at the history of releases, subscribe to e-mail announcements about
new releases, and make public comments about the software.

---------------------------------------------------------------------------------------------

The following is the licensing agreement under which OpenGrade is distributed.

            GNU GENERAL PUBLIC LICENSE
               Version 2, June 1991

 Copyright (C) 1989, 1991 Free Software Foundation, Inc.
                       59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 Everyone is permitted to copy and distribute verbatim copies
 of this license document, but changing it is not allowed.

            Preamble

  The licenses for most software are designed to take away your
freedom to share and change it.  By contrast, the GNU General Public
License is intended to guarantee your freedom to share and change free
software--to make sure the software is free for all its users.  This
General Public License applies to most of the Free Software
Foundation's software and to any other program whose authors commit to
using it.  (Some other Free Software Foundation software is covered by
the GNU Library General Public License instead.)  You can apply it to
your programs, too.

  When we speak of free software, we are referring to freedom, not
price.  Our General Public Licenses are designed to make sure that you
have the freedom to distribute copies of free software (and charge for
this service if you wish), that you receive source code or can get it
if you want it, that you can change the software or use pieces of it
in new free programs; and that you know you can do these things.

  To protect your rights, we need to make restrictions that forbid
anyone to deny you these rights or to ask you to surrender the rights.
These restrictions translate to certain responsibilities for you if you
distribute copies of the software, or if you modify it.

  For example, if you distribute copies of such a program, whether
gratis or for a fee, you must give the recipients all the rights that
you have.  You must make sure that they, too, receive or can get the
source code.  And you must show them these terms so they know their
rights.

  We protect your rights with two steps: (1) copyright the software, and
(2) offer you this license which gives you legal permission to copy,
distribute and/or modify the software.

  Also, for each author's protection and ours, we want to make certain
that everyone understands that there is no warranty for this free
software.  If the software is modified by someone else and passed on, we
want its recipients to know that what they have is not the original, so
that any problems introduced by others will not reflect on the original
authors' reputations.

  Finally, any free program is threatened constantly by software
patents.  We wish to avoid the danger that redistributors of a free
program will individually obtain patent licenses, in effect making the
program proprietary.  To prevent this, we have made it clear that any
patent must be licensed for everyone's free use or not licensed at all.

  The precise terms and conditions for copying, distribution and
modification follow.

    GNU GENERAL PUBLIC LICENSE
   TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION

  0. This License applies to any program or other work which contains
a notice placed by the copyright holder saying it may be distributed
under the terms of this General Public License.  The "Program", below,
refers to any such program or work, and a "work based on the Program"
means either the Program or any derivative work under copyright law:
that is to say, a work containing the Program or a portion of it,
either verbatim or with modifications and/or translated into another
language.  (Hereinafter, translation is included without limitation in
the term "modification".)  Each licensee is addressed as "you".

Activities other than copying, distribution and modification are not
covered by this License; they are outside its scope.  The act of
running the Program is not restricted, and the output from the Program
is covered only if its contents constitute a work based on the
Program (independent of having been made by running the Program).
Whether that is true depends on what the Program does.

  1. You may copy and distribute verbatim copies of the Program's
source code as you receive it, in any medium, provided that you
conspicuously and appropriately publish on each copy an appropriate
        copyright notice and disclaimer of warranty; keep intact all the
        notices that refer to this License and to the absence of any warranty;
and give any other recipients of the Program a copy of this License
along with the Program.

You may charge a fee for the physical act of transferring a copy, and
you may at your option offer warranty protection in exchange for a fee.

  2. You may modify your copy or copies of the Program or any portion
of it, thus forming a work based on the Program, and copy and
distribute such modifications or work under the terms of Section 1
above, provided that you also meet all of these conditions:

    a) You must cause the modified files to carry prominent notices
    stating that you changed the files and the date of any change.

    b) You must cause any work that you distribute or publish, that in
    whole or in part contains or is derived from the Program or any
    part thereof, to be licensed as a whole at no charge to all third
    parties under the terms of this License.

    c) If the modified program normally reads commands interactively
    when run, you must cause it, when started running for such
    interactive use in the most ordinary way, to print or display an
    announcement including an appropriate copyright notice and a
    notice that there is no warranty (or else, saying that you provide
    a warranty) and that users may redistribute the program under
    these conditions, and telling the user how to view a copy of this
    License.  (Exception: if the Program itself is interactive but
    does not normally print such an announcement, your work based on
    the Program is not required to print an announcement.)

These requirements apply to the modified work as a whole.  If
identifiable sections of that work are not derived from the Program,
and can be reasonably considered independent and separate works in
themselves, then this License, and its terms, do not apply to those
sections when you distribute them as separate works.  But when you
distribute the same sections as part of a whole which is a work based
on the Program, the distribution of the whole must be on the terms of
this License, whose permissions for other licensees extend to the
entire whole, and thus to each and every part regardless of who wrote it.

Thus, it is not the intent of this section to claim rights or contest
        your rights to work written entirely by you; rather, the intent is to
exercise the right to control the distribution of derivative or
collective works based on the Program.

In addition, mere aggregation of another work not based on the Program
with the Program (or with a work based on the Program) on a volume of
a storage or distribution medium does not bring the other work under
the scope of this License.

  3. You may copy and distribute the Program (or a work based on it,
under Section 2) in object code or executable form under the terms of
Sections 1 and 2 above provided that you also do one of the following:

    a) Accompany it with the complete corresponding machine-readable
    source code, which must be distributed under the terms of Sections
        1 and 2 above on a medium customarily used for software interchange; or,

    b) Accompany it with a written offer, valid for at least three
    years, to give any third party, for a charge no more than your
    cost of physically performing source distribution, a complete
    machine-readable copy of the corresponding source code, to be
    distributed under the terms of Sections 1 and 2 above on a medium
        customarily used for software interchange; or,

    c) Accompany it with the information you received as to the offer
    to distribute corresponding source code.  (This alternative is
    allowed only for noncommercial distribution and only if you
    received the program in object code or executable form with such
    an offer, in accord with Subsection b above.)

The source code for a work means the preferred form of the work for
making modifications to it.  For an executable work, complete source
code means all the source code for all modules it contains, plus any
associated interface definition files, plus the scripts used to
control compilation and installation of the executable.  However, as a
special exception, the source code distributed need not include
anything that is normally distributed (in either source or binary
form) with the major components (compiler, kernel, and so on) of the
operating system on which the executable runs, unless that component
itself accompanies the executable.

If distribution of executable or object code is made by offering
access to copy from a designated place, then offering equivalent
access to copy the source code from the same place counts as
distribution of the source code, even though third parties are not
compelled to copy the source along with the object code.

  4. You may not copy, modify, sublicense, or distribute the Program
except as expressly provided under this License.  Any attempt
otherwise to copy, modify, sublicense or distribute the Program is
void, and will automatically terminate your rights under this License.
However, parties who have received copies, or rights, from you under
this License will not have their licenses terminated so long as such
parties remain in full compliance.

  5. You are not required to accept this License, since you have not
signed it.  However, nothing else grants you permission to modify or
distribute the Program or its derivative works.  These actions are
prohibited by law if you do not accept this License.  Therefore, by
modifying or distributing the Program (or any work based on the
Program), you indicate your acceptance of this License to do so, and
all its terms and conditions for copying, distributing or modifying
the Program or works based on it.

  6. Each time you redistribute the Program (or any work based on the
Program), the recipient automatically receives a license from the
original licensor to copy, distribute or modify the Program subject to
these terms and conditions.  You may not impose any further
restrictions on the recipients' exercise of the rights granted herein.
You are not responsible for enforcing compliance by third parties to
this License.

  7. If, as a consequence of a court judgment or allegation of patent
infringement or for any other reason (not limited to patent issues),
conditions are imposed on you (whether by court order, agreement or
otherwise) that contradict the conditions of this License, they do not
excuse you from the conditions of this License.  If you cannot
distribute so as to satisfy simultaneously your obligations under this
License and any other pertinent obligations, then as a consequence you
may not distribute the Program at all.  For example, if a patent
license would not permit royalty-free redistribution of the Program by
all those who receive copies directly or indirectly through you, then
the only way you could satisfy both it and this License would be to
refrain entirely from distribution of the Program.

If any portion of this section is held invalid or unenforceable under
any particular circumstance, the balance of the section is intended to
apply and the section as a whole is intended to apply in other
circumstances.

It is not the purpose of this section to induce you to infringe any
patents or other property right claims or to contest validity of any
such claims; this section has the sole purpose of protecting the
integrity of the free software distribution system, which is
implemented by public license practices.  Many people have made
generous contributions to the wide range of software distributed
through that system in reliance on consistent application of that
system; it is up to the author/donor to decide if he or she is willing
to distribute software through any other system and a licensee cannot
impose that choice.

This section is intended to make thoroughly clear what is believed to
be a consequence of the rest of this License.

  8. If the distribution and/or use of the Program is restricted in
certain countries either by patents or by copyrighted interfaces, the
original copyright holder who places the Program under this License
may add an explicit geographical distribution limitation excluding
those countries, so that distribution is permitted only in or among
countries not thus excluded.  In such case, this License incorporates
the limitation as if written in the body of this License.

  9. The Free Software Foundation may publish revised and/or new versions
of the General Public License from time to time.  Such new versions will
be similar in spirit to the present version, but may differ in detail to
address new problems or concerns.

Each version is given a distinguishing version number.  If the Program
specifies a version number of this License which applies to it and "any
later version", you have the option of following the terms and conditions
either of that version or of any later version published by the Free
Software Foundation.  If the Program does not specify a version number of
this License, you may choose any version ever published by the Free Software
Foundation.

  10. If you wish to incorporate parts of the Program into other free
programs whose distribution conditions are different, write to the author
to ask for permission.  For software which is copyrighted by the Free
Software Foundation, write to the Free Software Foundation; we sometimes
make exceptions for this.  Our decision will be guided by the two goals
of preserving the free status of all derivatives of our free software and
of promoting the sharing and reuse of software generally.

    NO WARRANTY

  11. BECAUSE THE PROGRAM IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE PROGRAM, TO THE EXTENT PERMITTED BY APPLICABLE LAW.  EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE PROGRAM "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED
OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.  THE ENTIRE RISK AS
TO THE QUALITY AND PERFORMANCE OF THE PROGRAM IS WITH YOU.  SHOULD THE
PROGRAM PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL NECESSARY SERVICING,
REPAIR OR CORRECTION.

  12. IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE PROGRAM AS PERMITTED ABOVE, BE LIABLE TO YOU FOR DAMAGES,
INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL OR CONSEQUENTIAL DAMAGES ARISING
OUT OF THE USE OR INABILITY TO USE THE PROGRAM (INCLUDING BUT NOT LIMITED
TO LOSS OF DATA OR DATA BEING RENDERED INACCURATE OR LOSSES SUSTAINED BY
YOU OR THIRD PARTIES OR A FAILURE OF THE PROGRAM TO OPERATE WITH ANY OTHER
PROGRAMS), EVEN IF SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE
POSSIBILITY OF SUCH DAMAGES.

     END OF TERMS AND CONDITIONS

    How to Apply These Terms to Your New Programs

  If you develop a new program, and you want it to be of the greatest
possible use to the public, the best way to achieve this is to make it
free software which everyone can redistribute and change under these terms.

  To do so, attach the following notices to the program.  It is safest
to attach them to the start of each source file to most effectively
convey the exclusion of warranty; and each file should have at least
the "copyright" line and a pointer to where the full notice is found.

    <one line to give the program's name and a brief idea of what it does.>
    Copyright (C) <year>  <name of author>

        This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
        the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
        but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
        along with this program; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA


Also add information on how to contact you by electronic and paper mail.

If the program is interactive, make it output a short notice like this
when it starts in an interactive mode:

    Gnomovision version 69, Copyright (C) year name of author
        Gnomovision comes with ABSOLUTELY NO WARRANTY; for details type `show w'.
    This is free software, and you are welcome to redistribute it
    under certain conditions; type `show c' for details.

The hypothetical commands `show w' and `show c' should show the appropriate
parts of the General Public License.  Of course, the commands you use may
be called something other than `show w' and `show c'; they could even be
mouse-clicks or menu items--whatever suits your program.

You should also get your employer (if you work as a programmer) or your
school, if any, to sign a "copyright disclaimer" for the program, if
        necessary.  Here is a sample; alter the names:

  Yoyodyne, Inc., hereby disclaims all copyright interest in the program
  `Gnomovision' (which makes passes at compilers) written by James Hacker.

  <signature of Ty Coon>, 1 April 1989
  Ty Coon, President of Vice

This General Public License does not permit incorporating your program into
proprietary programs.  If your program is a subroutine library, you may
consider it more useful to permit linking proprietary applications with the
library.  If this is what you want to do, use the GNU Library General
Public License instead of this License.
STRING
"en.b.about.about_og_title" => "About OpenGrade",
"en.b.grade_frame.student" => "Student: ",
"en.b.grade_frame.assignment" => "Assignment: ",
"en.b.grade_frame.grade" => "Grade: ",
"en.b.open_file.dlog_title" => "Open Gradebook",
"en.b.open_file.password" => "Password",
"en.b.browser_data.new.password" => "Password",
"en.b.strip_watermark.dlog_title" => "Remove Watermark",
"en.b.reconcile.summary" => "Summary of Changes",
"en.b.reconcile.file_to_change" => "File to Change",
"en.b.reconcile.password" =>"Password",
"en.b.reconcile.file_to_fold_in" => "File to Fold In",
"en.b.reconcile.pick" => "The grade for %s on %s is %s. Change it to %s?",
"en.b.reconcile.yes" => "Yes",
"en.b.reconcile.no" => "No",
"en.b.rekey_file.dlog_title" => "Change Password",
"en.b.rekey_file.password" => "New password",
"en.b.new_file.file_name" => "Filename", # Most of the New File stuff is shared with the text UI.
"en.new_file.file_dlog_title" => "New File",
"en.new_file.file_exists" => "The file %s already exists.",
"en.new_file.file_created" => <<STRING,
Your file has been created. You might want to use the File menu now to
set your grading standards, and the Server menu to set yourself up to let students
view their grades on the web. You will also need to use the Assignments menu
to create categories (exams, homework, etc.) and make assignments within those
categories. And of course you have students! You can put in their names using the
Students menu.
STRING
"en.b.delete_category.title" => "Delete an Entire Category",
"en.b.delete_category.confirm" => "You are asking to delete the entire category %s, which contains %s %s. Are you sure you want to do this?",
"en.b.edit_category_weights.title" => "Editing Category Weights",
"en.b.edit_category_weights.not_weighted" => "This gradebook has been set up using point-total grading, not weighted grading.",
"en.b.edit_category_weights.no_categories" => "This gradebook doesn't yet have any categories.",
"en.b.edit_category_weights.weight_for" => "Weight for %s",
"en.b.new_assignment.single_assignment_cat_already_has_one" => "This is a single-assignment category, and it already has an assignment in it.",
"en.b.new_assignment.assignment_exists" => "The assignment %s already exists in category %s.",
"en.b.new_assignment.new_assignment_title" => "New %s",
"en.b.new_assignment.name" => "Number or name",
"en.b.new_assignment.max_score" => "Maximum score",
"en.b.new_assignment.due" => "Due date (optional)",
"en.b.new_assignment.mp" => "Marking Period",
"en.b.grades_queue.nonnumeric_title" => "Grade Must Be Numeric",
"en.b.grades_queue.nonnumeric" => <<STRING,
Grades must be numeric.
STRING
"en.b.grades_queue.too_high_title" => "Score Greater Than Maximum",
"en.b.grades_queue.too_high" => <<STRING,
The score of %s for %s on %s is greater than the maximum of %s. 
To confirm this score, hit OK.
To restore this score to its previous value, hit cancel.
To correct this score, enter the corrected value and hit OK. To avoid this
warning in the future, you can enter a greater-than-maximum score with an x on the
end, e.g., 105x.
STRING
"en.b.report.which_period" => "Which marking period?",
"en.b.report.all_marking_periods" => "All marking periods",
"en.b.report.stats_title" => "Class Statistics",
"en.b.report.password" => "Password",
"en.b.report.sort_by_overall.title" => "Report: Overall Grade",
"en.b.report.sort_by_category.title" => "Report: Averages in a Category",
"en.b.report.sort_by_assignment.title" => "Report: Scores on an Assignment",
"en.b.report.stats_ass.title" => "Report: Statistics For an Assignment",
"en.b.report.sort_by_score" => "Sort by score",
"en.b.report.sort_by_name" => "Sort by name",
"en.b.report.graphical_roster" => "Print Graphical Version Using Inkscape",
"en.b.properties.properties" => "Properties",
"en.b.properties.weighting_mode" => "Weighting mode",
"en.b.properties.straight_points" => "straight points",
"en.b.properties.weighted" => "weighted",
"en.b.properties.no_cats" => "not defined, because no categories have been set up yet",
"en.b.properties.marking_periods" => "Marking periods",
"en.b.properties.none" => "none",
"en.b.clone.what" => "Cloning a File",
"en.b.clone.save_as" => "Save As",
"en.b.clone.title" => "Please enter a description of the class, to appear at the top of reports.",
"en.b.clone.days_of_week" =><<STRING,
Please enter the days of the week on which the class meets, using R for
Thursday, and U for Sunday. Supplying accurate information here will make it
quicker for you to enter due dates. If the class doesn't meet on definite days
of the week, just leave it blank to accept the default, which is MTWRF.
STRING
"en.b.clone.time" => <<STRING,
Please enter the time the class meets, in 24-hour hh:mm format. For example,
if it meets at 1:30 in the afternoon, enter 13:30.
It's OK if you leave this blank.
STRING
"en.b.clone.year" =>"Please enter the calendar year during which the term started.",
"en.b.clone.month" =>"Please enter the number of the month (1-12) in which the term started.",
"en.b.clone.password" =><<STRING,
Please enter a password that you will use for authentication. You will need
to enter this password whenever you open this file. The password can be blank
if you don't want to remember a real one.
STRING
"en.b.clone.dir" =><<STRING,
If you will be posting students' grades on a server using Spotter, please enter the subdirectory for the class.
STRING
"en.b.export.export_to" => 'Format',
"en.b.export.prompt" => <<STRING,
For Online Grades format, make sure you have the right options set up in Settings under the Online Grades menu.
To make the Online Grades menu appear, use the Preferences menu and restart OpenGrade.
STRING
"en.b.server.ok" => 'OK',
"en.b.server.cancel" => 'Cancel',
"en.b.server.confirm_whole_class" => "Broadcast a message to the whole class -- are you sure?",
"en.b.server.class_description" => "Class Description",
"en.b.server.roster" => "Roster",
"en.b.server.deactivate_whom" => "Deactivate Account",
"en.b.server.error" => "Error",
"en.b.server.to" => "to",
"en.b.server.do_email" => "send e-mail?",
"en.b.server.subject" => "subject",
"en.b.server.body" => "body",
"en.b.server.set_server_key" => <<STRING,
You must set the server key. This is done through Client/Server Settings in the
Server menu.
STRING
"en.b.server.error_connecting" => "There was an error connecting to the server.",

"en.b.input.yes" => "yes",
"en.b.input.no" => "no",

"en.b.options.ok" => "OK",
"en.b.options.cancel" => "Cancel",
"en.b.options.standards.symbols_title" => "Grade Symbols",
"en.b.options.standards.pct_title" => "Minimum Percentages",
"en.b.options.standards.custom" => "Custom: Enter a series of symbols separated by spaces, in order from highest to lowest. At the end, you must include a grade symbol that is the lowest of all, requiring zero percent to attain.",
"en.b.options.standards.at_least_two" => "You must have at least two grade symbols.",
"en.b.options.standards.too_many" => "Too many grade symbols.",
"en.b.options.standards.not_unique" => "All grade symbols must be unique.",
"en.b.options.standards.not_in_order" => "Percentages must be in descending order, and must not be the same.",

"en.b.options.marking_periods.name" => "Name of marking period %s",
"en.b.options.marking_periods.start" => "Starting date of marking period %s",

"en.b.options.web.title" => "Client/Server Settings",

"en.b.options.web.server_username" =>
"Please enter the username you'll use on the server.",

"en.b.options.web.server_account" =>
"Please enter account you'll use on the server.",

"en.b.options.web.server" => <<STRING,
Please enter the name of the server, e.g., myserver.edu.
STRING

"en.b.options.web.server_class" => <<STRING,
Please enter the subdirectory for the class, e.g., f2002/205.
STRING

"en.b.options.web.server_key" => <<STRING,
Please enter the server key.
STRING

"en.b.options.web.cgi" =>
"Please enter the location of the cgi-bin on your server.",

"en.b.options.web.subdir" => <<STRING,
Please enter the class's subdirectory, relative to cgi-bin.
This is typically of the form spotter/username/term/course.
STRING

"en.b.options.online_grades.title" => "Settings for Online Grades",
"en.b.options.online_grades.server" => "Server",
"en.b.options.online_grades.server_title" => "Title of course",
"en.b.options.online_grades.server_username" => "Username or email address",
"en.b.options.online_grades.server_course_code" => "Course code",
"en.b.options.online_grades.server_section_number" => "Section number",
"en.b.options.online_grades.server_teacher_name" => "Teacher's name to display on reports, e.g., Ms. Smith",
"en.b.options.online_grades.server_term" => "Term",
"en.b.options.online_grades.server_cltext" => "Text to display regarding the class",
"en.b.options.online_grades.server_period" => "Period (optional)",
"en.b.options.online_grades.server_phone" => "Phone number (optional)",


"en.b.options.preferences.beep" => <<STRING,
Do you want OpenGrade to beep at you?
STRING

"en.b.options.preferences.justify" => <<STRING,
Do you want grades left-justified, or right-justified?
STRING

"en.b.options.preferences.editor_command" => <<STRING,
Enter the Unix shell command you want to use for opening a text file in an external editor, e.g., gedit.
STRING

"en.b.options.preferences.print_command" => <<STRING,
Enter the Unix shell command you want to use to print a text file, e.g., lpr -o page-left=40 -o page-right=36 -o page-top=100 -o page-bottom=36.
STRING

"en.b.options.preferences.spreadsheet_command" => <<STRING,
Enter the Unix shell command you want to use to open a spreadsheet file, e.g., soffice -calc.
STRING

"en.b.options.preferences.hash_function" => <<STRING,
You can set the cryptographic algorithm used for creating the digital watermarks in gradebook files. SHA1 is automatically supported
if you install OpenGrade with all its dependencies, but weaknesses in the SHA1 algorithm have been showing up, leading to the possibility
of forgery at some point in the future. Whirlpool is also automatically supported
if you install OpenGrade with all its dependencies, but will be slow unless you also install the Digest::Whirlpool module from CPAN.
STRING

"en.main_loop.startup_info"
  =>"OpenGrade    (c) 2002 B. Crowell, www.lightandmatter.com/opengrade",
"en.main_loop.enter_grades_alpha"
  =>"to enter grades on an assignment, in alphabetical order,",
"en.main_loop.enter_grades_1"
  =>"to enter grades on an assignment, selecting one student at a time,",
"en.main_loop.edit"
  =>"to edit the roster or the list of categories,",
"en.main_loop.reports"
  =>"for reports,",
"en.main_loop.upload_grades"
  =>"to upload grades,",
"en.main_loop.save_and_close"
  =>"to save and close this file",
"en.main_loop.close"
  =>"to close this file,",
"en.main_loop.save"
  =>"to save this file",
"en.main_loop.save_not_necessary"
  =>"(not necessary, because it has not been modified)",
"en.main_loop.revert"
  =>"to close this file without saving it,",
"en.main_loop.new"
  =>"to create a new file,",
"en.main_loop.open"
  =>"to open a file,",
"en.main_loop.quit"
  =>"to quit.",
"en.main_loop.save_and_quit"
  =>"to save this file and quit.",
"en.main_loop.user"
  =>"user",
"en.main_loop.date"
  =>"date",
"en.main_loop.main_menu_header"
  =>"Main menu --- enter",
"en.main_loop.writing_file"
  =>"Writing file.",
"en.main_loop.enter_filename_to_open"
  =>"Enter the name of the gradebook file to open.",
"en.main_loop.done"
  =>"Done.",

"en.edit.menu_header"
  =>"Edit menu --- enter",
"en.edit.edit_categories"
  =>"to edit categories,",
"en.edit.edit_students"
  =>"to edit students,",
"en.edit.main_menu"
  =>"- or m to return to the main menu.",

"en.edit_categories.edit_category_dialog_title"=>'Edit Category',

"en.edit_categories.add"
  => "to add a new category,",
"en.edit_categories.edit_menu"
  => "to go back to the edit menu,",
"en.edit_categories.main_menu"
  => "to go back to the main menu.",
"en.edit_categories.category_exists"
  => "That category already exists.",
"en.edit_categories.enter_short_name"
  => <<STRING,
Please enter a short name for the category,
 e.g., e for exams, or hw for homework.
It should contain only lowercase letters from a to z. It will be used
as a column header in table reports.
STRING
"en.edit_categories.enter_singular_noun"
  => <<STRING,
Please enter a singular noun to describe this category. This will
be combined with the names of assignments, e.g., exam+1=exam 1.
STRING
"en.edit_categories.enter_plural_noun"
  => <<STRING,
Please enter a plural form of this noun. This will be used as a header
in reports.
STRING
"en.edit_categories.enter_number_to_drop"
  => <<STRING,
Please enter the number of assignments in this category that will be
dropped, e.g. 2 if you want to ignore the lowest two scores.
STRING
"en.edit_categories.type"=>'Type',
"en.edit_categories.numerical"=>'numerical',
"en.edit_categories.attendance"=>'attendance',

"en.edit_categories.will_it_count" => <<STRING,
If this category will count toward the students' grades, just leave this blank.
If it won't count, enter a period (.)
STRING

"en.edit_categories.b.will_it_count" => <<STRING,
Will this category will count toward the students' grades?
STRING

"en.edit_categories.b.is_it_ignored" => <<STRING,
Will this category be ignored for purposes of computing grades?
STRING

"en.edit_categories.b.is_it_single" => <<STRING,
Will there only be one assignment in this category?
STRING

"en.edit_categories.propagate_ignore" => <<STRING,
Newly created assignments in this category will be ignored in the
calculation of grades. Do you want to ignore all preexisting
assignments as well?
STRING

"en.edit_categories.propagate_not_ignore" => <<STRING,
Newly created assignments in this category will be counted in the
calculation of grades. Do you want to make all preexisting
assignments count as well?
STRING

"en.edit_categories.propagate_max" => <<STRING,
Newly created assignments in this category will have the new value
for the maximum number of points. Do you want to apply this to
preexisting assignments as well?
STRING


"en.edit_categories.enter_max" => <<STRING,
 If every assignment in this category will be worth a different number
 of points, leave this blank. If they will all be worth the same number
 of points, enter that number.
STRING

"en.edit_categories.weight" => 'weight',

"en.edit_categories.enter_weight" => <<STRING,
 If you want to use point-total grading for this class, leave this
 blank. Otherwise, enter the weight for this category.
STRING

"en.edit_categories.gimme_weight" => <<STRING,
 Weight for this category. Leave this blank if you don't want weighted grading.
 Setting a weight will turn on weighted grading for this gradebook.
STRING

"en.edit_categories.gimme_weight_required" => <<STRING,
 Weight for this category (required, because this gradebook is using weighted grading).
STRING

"en.edit_categories.add_title" => "New Category",

"en.edit_categories.confirm_add" =>
 "Add this category?",

"en.add_assignment.where_to_insert" => "Error, couldn't find where to insert assignment.",
"en.add_assignment.exists" => "Error, assignment %s already exists.",

#-----------------------------------------------------
# edit_students
#-----------------------------------------------------

"en.edit_students.menu_header" =>
 "Edit menu --- enter",

"en.edit_students.add" =>
 "to add students",

"en.edit_students.drop" =>
 "to drop a students",

"en.edit_students.reinstate" =>
 "to reinstate a student whom you previously dropped",

"en.edit_students.exit" =>
 "to return to the edit menu",

"en.edit_students.main" =>
 "to return to the main menu",

"en.edit_students.last_name" =>
 "Last name, or return to quit",

"en.edit_students.first_name" =>
 "First name",

"en.edit_students.student_id" =>
  "Student ID",

"en.edit_students.password" =>
  "Password",

"en.edit_students.added" =>
 "Added %s %s.",

"en.edit_students.dropped" =>
 "Dropped %s. This student can be reinstated later.",

"en.edit_students.reinstated" =>
 "Reinstated %s.",

#-----------------------------------------------------
# new_file
#-----------------------------------------------------
"en.new_file.title" =>
 "Please enter a description of the class, to appear at the top of reports.",


"en.new_file.staff" => <<STRING,
Please enter a list, separated by commas, of the usernames of all the
people who will be editing this file. If you will be the only person editing
this file, then you can just hit return to accept the default username supplied
below.
STRING

"en.new_file.staff_gui" => <<STRING,
Please enter a list, separated by commas, of the usernames of all the
people who will be editing this file. If you are using a system that doesn't
have usernames, you can leave this blank.
STRING

"en.new_file.password" => <<STRING,
Please enter a password that you will use for authentication. You will need
to enter this password whenever you open this file. The password can be blank
if you don't want to remember a real one.
STRING

"en.new_file.lame_system" => <<STRING,
 Since your system doesn't seem to support usernames, it doesn't really
 matter what naming convention you pick, as long as it's easy for you and
 your co-instructors to remember.
STRING

"en.new_file.cool_system" => <<STRING,
 Your system seems to support usernames, so it will be most convenient if
 you use the ones it supplies, rather than making up new ones. That way you
 will simply be recognized automatically when you start the software
STRING

"en.new_file.days_of_week" => <<STRING,
Please enter the days of the week on which the class meets, using R for
Thursday, and U for Sunday. Supplying accurate information here will make it
quicker for you to enter due dates. If the class doesn't meet on definite days
of the week, just leave it blank to accept the default, which is MTWRF.
It's OK if you leave this blank.
STRING

"en.new_file.time" => <<STRING,
Please enter the time the class meets, in 24-hour hh:mm format. For example,
if it meets at 1:30 in the afternoon, enter 13:30.
It's OK if you leave this blank.
STRING

"en.new_file.illegal_day_of_week" =>
 "Please use only the letters M, T, W, R, F, S, and U.",

"en.new_file.year" =>
"Please enter the calendar year during which the term started.",

"en.new_file.month" =>
"Please enter the number of the month (1-12) in which the term started.",

"en.new_file.standards_header" => <<STRING,
Grading standards: If you don't want to set grading standards right now,
just hit return. The lowest letter grade in your grading system, typically
F, needs to be entered explicitly, with a minimum percentage of zero.
STRING

"en.new_file.letter_grade" =>
 "Enter a letter grade, or hit return if you're done.",

"en.new_file.min_percentage" =>
"Enter the minimum percentage required for this grade.",

"en.new_file.illegal_percentage" =>
 "Please enter a numerical value from 0 to 100.",

"en.new_file.web_reports_header" => <<STRING,
The following questions relate to posting grades on the web. You can leave
these blank if you won't be using this feature.
STRING

"en.new_file.ftp_username" =>
"Please enter the FTP username you'll use for uploading web reports.",

"en.new_file.ftp_server" => <<STRING,
Please enter the name of the FTP server to which you'll
upload web reports, e.g., myserver.edu.
STRING

"en.new_file.cgi" =>
"Please enter the location of the cgi-bin on your server.",

"en.new_file.subdir" => <<STRING,
Please enter the subdirectory for web reports, relative to cgi-bin. This directory should exist before you upload grades.
STRING

"en.new_file.file_name" =>
"Please enter the name of the file to create.",

"en.new_file.already_exists" =>
 "The file %s already exists. Overwrite it?",

"en.new_file.created" => <<STRING,
Your new gradebook has been created. You will probably want to choose 'e'
from the main menu to input your assignment categories and the names of the
students, and then 's' to save the file.
STRING

#-----------------------------------------------------
# open_gb
#-----------------------------------------------------
"en.open_gb.password"=>"Enter password",
#-----------------------------------------------------
# view_a_report
#-----------------------------------------------------

"en.view_a_report.menu_header" =>
"Reports menu --- enter",

"en.view_a_report.totals" =>
"to view class totals",

"en.view_a_report.one_student" =>
"to view a report for one student",

"en.view_a_report.web" =>
"to create web reports",

"en.view_a_report.stats" =>
"to see statistics",

"en.view_a_report.connection" =>
"Please make sure you have an active internet connection.",

"en.view_a_report.server" => "server",
"en.view_a_report.cgi_bin" => "cgi_bin",
"en.view_a_report.dir" => "dir",
"en.view_a_report.backup" => "backup",
"en.view_a_report.yes" => "yes",
"en.view_a_report.no" => "no",
"en.view_a_report.username" => "username",

"en.view_a_report.password" =>
"Enter ftp password for %s",

"en.view_a_report.success" =>
"All files were uploaded successfully.",

#-----------------------------------------------------
# choose_student
#-----------------------------------------------------
"en.choose_student.prompt" =>
 "Enter the beginning of the student's last name",
"en.choose_student.none_begin_with" =>
 "No students have last names beginning with",

#-----------------------------------------------------
# choose_assignment
#-----------------------------------------------------
"en.choose_assignment.prompt" =>
 "Enter the short name of the assignment.",
"en.choose_assignment.create_new" =>
 "Create new assignment",

#-----------------------------------------------------
# choose_category
#-----------------------------------------------------
"en.choose_category.prompt" =>
 "Enter the beginning of the category's name",
"en.choose_category.none_begin_with" =>
 "No categories have names beginning with",

#-----------------------------------------------------
# grade_an_assignment
#-----------------------------------------------------
"en.grade_an_assignment.no_cats" =>
"You must create categories first.",

"en.grade_an_assignment.header" =>
"Entering grades for an assignment:",

"en.grade_an_assignment.no_such_cat" =>
"No such category",

"en.grade_an_assignment.where_to_put_it" => <<STRING,
 To add this new assignment to the end of the list of
 assignments for this category, type return. If you don't want to create
 it, type a period (.). If you want to add it before the end of the list, enter
 the beginning of the name of the assignment before which you want to insert it.
STRING

"en.grade_an_assignment.action_canceled" =>
"Action canceled.",

"en.grade_an_assignment.maximum_score" =>
 "maximum score",

"en.grade_an_assignment.max_help" =>
"The maximum score possible.",

"en.grade_an_assignment.due_date" =>
 "due date, in mm-dd format (optional)",

"en.grade_an_assignment.due_date_help" =>
"The date when the assignment is due.",

"en.grade_an_assignment.max_is" =>
 "The maximum score is %s.",

"en.grade_an_assignment.how_to_enter_scores" => <<STRING,
Enter a grade for each student, or press return to leave it as it is.
Type q to quit before the end of the list, c to cancel, up arrow
to back up to the previous student, and b to change a preexisting
 grade to a blank.
STRING

"en.grade_an_assignment.how_to_enter_one" => <<STRING,
 When you're done entering grades, hit return instead of selecting a student.
 That is greater than the maximum score for this assignment.
 Hit return to confirm this score, or enter another value.
 Type x to leave this score unchanged.
STRING

#-----------------------------------------------------
# enter_one_grade
#-----------------------------------------------------

"en.enter_one_grade.too_high" => <<STRING,
That is greater than the maximum score for this assignment.
Hit return to confirm this score, or enter another value.
Type x to leave this score unchanged.
STRING

"en.enter_one_grade.invalid_input" =>
 "Invalid input.",


);

}

1;
