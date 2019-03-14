#!/bin/bash
cd ..
rm -f i18n/opengrade.pot
cp -f MyWords.pm MyWords_.pm
sed -i 's|=>| => |g' MyWords_.pm
sed -i 's|^"en.\S*\s||g' MyWords_.pm
sed -i "s|^'en.\S*\s||g" MyWords_.pm
sed -i 's|^"en.*"$||g' MyWords_.pm
sed -i "s|^'en.*'$||g" MyWords_.pm
sed -i "s|=> '',||g" MyWords_.pm
xgettext -a MyWords_.pm -o i18n/opengrade.pot
rm -f MyWords_.pm 
