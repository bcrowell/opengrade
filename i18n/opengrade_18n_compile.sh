#/bin/bash

echo "Compiling translations"
rm -rf ../locale
for lang in `ls ./|grep -v \.pot|grep -v \.sh|cut -d "." --fields=1`
do
  mkdir -p ../locale/$lang/LC_MESSAGES
  msgfmt ./$lang.po -o ./$lang.mo
  mv -f ./$lang.mo ../locale/$lang/LC_MESSAGES/opengrade.mo
done
echo "Done."
