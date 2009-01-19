VERSION = 3.0.3
# ... When changing this version number, make sure to change the one in Version.pm as well.

prefix=/usr
exec_prefix=$(prefix)
bindir=$(exec_prefix)/bin

MANDIR = $(prefix)/share/man/man1

SHELL = /bin/sh

EXECUTABLE_DIR = $(DESTDIR)$(bindir)
ICON_DIR = /usr/local/share/icons/hicolor/48x48/apps
SOUND_DIR = /usr/share/apps/opengrade/sounds
# ...If I change this, change it in ExtraGUI.pm as well.
ICON = $(ICON_STEM).png
CH_SOUND = ch.wav
AMBIGUOUS_SOUND = ambiguous.wav
CHOPSTICKS_SOUND = chopsticks.wav
# ...If I change this, change it in ExtraGUI.pm as well.
# We have a link called opengrade, pointing to the file opengrade.pl. The reason for this is that on Windows, the executable has to have
# the extension .pl so that Windows knows what to do when you double-click on it, but on Unix, we want to be able to run the program by
# using the command opengrade from the command line.
EXECUTABLE = opengrade.pl
EXECUTABLE_LINK = opengrade
ICON_STEM = opengrade_icon
REQUIRED_SOURCES = Browser.pm BrowserData.pm BrowserWindow.pm Crunch.pm DateOG.pm ExtraGUI.pm Fun.pm GradeBook.pm Input.pm LineByLine.pm MyWords.pm NetOG.pm Portable.pm Preferences.pm Report.pm TermUI.pm Text.pm UtilOG.pm Words.pm Version.pm Stage.pm Assignments.pm Roster.pm Score.pm $(EXECUTABLE)
# ... This is the list that's installed by default; doesn't include plugins.
PLUGINS = ServerDialogs.pm OnlineGrades.pm
SOURCES = $(REQUIRED_SOURCES) $(PLUGINS)
# ... This is the list that's distributed with the tarball; includes plugins.
DIST_DIR = opengrade-$(VERSION)
DIST_TARBALL = opengrade-$(VERSION).tar.gz

INSTALL_PROGRAM = install
# The FreeBSD style seems to be this:
#   INSTALL_PROGRAM = $(INSTALL)
# but /don't/ do that, because it breaks compatibility with GNU make!

SOURCE_DIR = `perl -e 'use Config; print $$Config{sitelib}'`/OpenGrade
#... e.g., /usr/local/lib/perl5/site_perl/5.8.0/OpenGrade
PLUGIN_DIR = $(SOURCE_DIR)/plugins

all:
	@echo "No compilation is required. Documentation on how to install the software can be downloaded from"
	@echo "  http://www.lightandmatter.com/ogr/ogr.html   ."
	@echo "For the impatient, the basic process on Linux is to do 'make depend' or 'make ubuntu',"
	@echo "and then 'make install'."

ubuntu:
	apt-get install perl-tk libdate-calc-perl libdigest-sha1-perl libclone-perl libterm-readkey-perl md5deep build-essential alsa-utils libjson-perl

depend:
	perl get_dependencies_from_cpan.pl

install: opengrade.1
	rm -f /usr/local/bin/opengrade # Used to be installed in this directory. If they're installing a new version, get rid of the old one. 
	$(INSTALL_PROGRAM) -d $(SOURCE_DIR)
	$(INSTALL_PROGRAM) $(REQUIRED_SOURCES) $(SOURCE_DIR)
	ln -fs $(SOURCE_DIR)/$(EXECUTABLE) $(EXECUTABLE_DIR)/$(EXECUTABLE_LINK)
	$(INSTALL_PROGRAM) -d $(ICON_DIR)
	$(INSTALL_PROGRAM) $(ICON) $(ICON_DIR)
	$(INSTALL_PROGRAM) -d $(SOUND_DIR)
	rm -f $(SOUND_DIR)/*.ogg
	$(INSTALL_PROGRAM) $(CH_SOUND) $(SOUND_DIR)
	$(INSTALL_PROGRAM) $(AMBIGUOUS_SOUND) $(SOUND_DIR)
	$(INSTALL_PROGRAM) $(CHOPSTICKS_SOUND) $(SOUND_DIR)
	gzip -9 <opengrade.1 >opengrade.1.gz
	- test -d $(DESTDIR)$(MANDIR) || mkdir -p $(DESTDIR)$(MANDIR)
	install --mode=644 opengrade.1.gz $(DESTDIR)$(MANDIR)
	rm -f opengrade.1.gz
	$(INSTALL_PROGRAM) -d $(PLUGIN_DIR)
	$(INSTALL_PROGRAM) ServerDialogs.pm $(PLUGIN_DIR)
	$(INSTALL_PROGRAM) -d $(PLUGIN_DIR)
	$(INSTALL_PROGRAM) OnlineGrades.pm $(PLUGIN_DIR)
	rm -f $(SOURCE_DIR)/ServerDialogs.pm $(SOURCE_DIR)/OnlineGrades.pm # delete old, redundant copies sitting in the main directory, which actually cause an error
	@echo ""
	@echo "================================================================================="
	@echo "OpenGrade has been installed."
	@echo ""
	@echo "You may also need to install some libraries if this"
	@echo "is the first time you've installed OpenGrade on this."
	@echo "computer. The documentation explains how to do that."
	@echo ""
	@echo "The documentation can be downloaded separately from"
	@echo "    http://www.lightandmatter.com/ogr/ogr.html"
	@echo ""
	@echo "Opengrade's icon has been installed here:"
	@echo "    $(ICON_DIR)/$(ICON)"
	@echo ""
	@echo "If you ever want to remove OpenGrade from your system, use"
	@echo "the command"
	@echo "    make deinstall"
	@echo ""
	@echo "To see if sound is working, you can do"
	@echo "    make test_sound"
	@echo "================================================================================="

reinstall: install
	;

deinstall:
	rm -Rf $(PLUGIN_DIR) # is normally a subdirectory of SOURCE_DIR, in which case this is superfluous, but harmless
	rm -Rf $(SOURCE_DIR)
	rm -f $(EXECUTABLE_DIR)/$(EXECUTABLE)
	rm -f $(ICON_DIR)/$(ICON)
	rm -f $(SOUND_DIR)/$(CH_SOUND)
	rm -f $(SOUND_DIR)/$(AMBIGUOUS_SOUND)
	rm -f $(SOUND_DIR)/$(CHOPSTICKS_SOUND)
	rm -f $(DESTDIR)$(MANDIR)/opengrade.1.gz

doc: opengrade_doc.pdf
	#

opengrade_doc.pdf: opengrade_doc.tex
	pdflatex opengrade_doc
	pdflatex opengrade_doc

internals.html: Browser.pm BrowserData.pm BrowserWindow.pm ExtraGUI.pm GradeBook.pm Input.pm Fun.pm ServerDialogs.pm
	rm -f internals.pl
	cat Browser.pm BrowserData.pm BrowserWindow.pm ExtraGUI.pm GradeBook.pm Input.pm Fun.pm ServerDialogs.pm >internals.pl
	pod2html --title="OpenGrade internals" <internals.pl >internals.html
	rm -f internals.pl

clean:
	rm -f opengrade_doc.log
	rm -f opengrade_doc.aux
	# Get rid of some MacOS X cruft:
	rm -f */.DS_Store
	rm -f */*/.DS_Store
	rm -fR */.FBCLockFolder
	rm -fR */*/.FBCLockFolder
	# Emacs backup files:
	rm -f Makefile~
	rm -f *.tex~
	rm -f *.pm~
	rm -f *.pl~
	rm -f *.cgi~
	rm -f *.cls~
	rm -f *.gb~
	# Misc:
	rm -f a.a
	# ... done.


post: opengrade_doc.pdf
	cp $(DIST_TARBALL) $(HOME)/Lightandmatter/ogr
	cp opengrade_doc.pdf $(HOME)/Lightandmatter/ogr

dist: manpage.pod
	git archive --format=tar --prefix=$(DIST_DIR)/ HEAD | gzip >$(DIST_TARBALL)

test_sound:
	echo "You should hear a beep, then a 'ch' sound, then a piano clash, then a voice saying 'ambiguous.'"
	perl -e 'use Tk; $$w = MainWindow->new; $$w->bell()'
	sleep 1
	aplay /usr/share/apps/opengrade/sounds/ch.wav
	sleep 1
	aplay /usr/share/apps/opengrade/sounds/chopsticks.wav
	sleep 1
	aplay /usr/share/apps/opengrade/sounds/ambiguous.wav

opengrade.1: manpage.pod Makefile
	# dependency on Makefile is so it will detect new value of VERSION
	pod2man --section=1 --center="OpenGrade $(VERSION)" --release="$(VERSION)" \
	        --name=OPENGRADE <manpage.pod >opengrade.1
