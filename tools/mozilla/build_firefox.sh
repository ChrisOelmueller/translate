#!/bin/bash -e
#
# Copyright 2009 João Miguel Neves <joao.neves@intraneia.com>
# Copyright 2008 Zuza Software Foundation
#
# This file is part of Virtaal.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, see <http://www.gnu.org/licenses/>.

##########################################################################
# NOTE: Documentation regarding (the use of) this script can be found at #
# http://translate.sourceforge.net/wiki/toolkit/mozilla_l10n_scripts     #
##########################################################################

opt_vc="yes"
opt_build_xpi=""
opt_compare_locales="yes"
opt_copyfiles="yes"

progress=none
errorlevel=traceback
export USECPO=0
hgverbosity="--quiet" # --verbose to make it noisy
gitverbosity="--quiet" # --verbose to make it noisy
svnverbosity="--quiet"
pomigrate2verbosity="--quiet"

for option in $*
do
	if [ "${option##-*}" != "$option" ]; then
		case $option in
			--xpi)
				opt_build_xpi="yes"
			;;
			--no-vc)
				opt_vc=""
			;;
			--no-compare-locales)
				opt_compare_locales=""
			;;
			--no-copyfiles)
				opt_copyfiles=""
			;;
			--verbose)
				hgverbosity="--verbose"
				gitverbosity=""
				svnverbosity=""
				progress=bar
				pomigrate2verbosity=""
			;;
			*) 
			echo "Unkown option: $option"
			exit
			;;
		esac
		shift
	else
		break
	fi
done

if [ $# -eq 0 ]; then
	HG_LANGS="ach af ak am cy en-ZA ff gd hi-IN hz ki lg ng nso ny sah son st-LS su sw tn ur ve wo xog zu"
	COUNT_LANGS=25
else
	HG_LANGS=$*
	COUNT_LANGS=$#
fi

# FIXME lets make this the execution directory
BUILD_DIR="$(pwd)"
MOZCENTRAL_DIR="${BUILD_DIR}/mozilla-aurora" # Change "../mozilla-central" on line 39 too if you change this var
L10N_DIR="${BUILD_DIR}/l10n"
PO_DIR="${BUILD_DIR}/po"
TOOLS_DIR="${BUILD_DIR}/tools"
POUPDATED_DIR="${BUILD_DIR}/po-updated"
# FIXME we should build this from the get_moz_enUS script
PRODUCT_DIRS="browser dom netwerk security services/sync toolkit mobile embedding" # Directories in language repositories to clear before running po2moz
LANGPACK_DIR="${BUILD_DIR}/xpi"

# Include current dir in path (for buildxpi and others)
CURDIR=$(dirname $0)
if [ "$CURDIR" == "" -o  "$CURDIR" == '.' ]; then
    CURDIR=$(pwd)
fi
PATH=${CURDIR}:${PATH}

# Make sure all directories exist
for dir in ${L10N_DIR} ${POUPDATED_DIR} ${LANGPACK_DIR}
do
	[ ! -d ${dir} ] && mkdir -p ${dir}
done

# Compute relative paths of ${L10N_DIR} and ${POUPDATED_DIR}.
# (This assumes that both directories are sub-directories of ${BUILD_DIR}
L10N_DIR_REL=`echo ${L10N_DIR} | sed "s#${BUILD_DIR}/##"`
POUPDATED_DIR_REL=`echo ${POUPDATED_DIR} | sed "s#${BUILD_DIR}/##"`

[ $opt_vc ] && if [ -d ${TOOLS_DIR}/translate/.git ]; then
	(cd ${TOOLS_DIR}/translate/
	git stash $gitverbosity
	git pull $gitverbosity --rebase
	git checkout $gitverbosity
	git stash pop $gitverbosity || true)
else
	git clone $gitverbosity git@github.com:translate/translate.git ${TOOLS_DIR}/translate || git clone git://github.com/translate/translate.git ${TOOLS_DIR}/translate 
fi

export PYTHONPATH="${TOOLS_DIR}/translate":"$PYTHONPATH"
export PATH="${TOOLS_DIR}/translate/tools":\
"${TOOLS_DIR}/translate/translate/convert":\
"${TOOLS_DIR}/translate/translate/tools":\
"${TOOLS_DIR}/translate/translate/filters":\
"${TOOLS_DIR}/translate/tools/mozilla":\
"$PATH"

if [ $opt_vc ]; then
	if [ -d "${MOZCENTRAL_DIR}/.hg" ]; then
		cd ${MOZCENTRAL_DIR}
		hg pull $hgverbosity -u
		hg update $hgverbosity -C
	else
		hg clone $hgverbosity http://hg.mozilla.org/releases/mozilla-aurora/ ${MOZCENTRAL_DIR}
	fi
    (find ${MOZCENTRAL_DIR} -name '*.orig' | xargs  --no-run-if-empty rm)
fi

[ $opt_vc ] && if [ -d ${PO_DIR} ]; then
	svn up $svnverbosity --depth=files ${PO_DIR}
else
	svn co $svnverbosity --depth=files  https://zaf.svn.sourceforge.net/svnroot/zaf/trunk/po/fftb ${PO_DIR}
fi
if [ ! -d ${POUPDATED_DIR}/.svn ]; then
	cp -rp ${PO_DIR}/.svn ${POUPDATED_DIR}
fi

# Update all Mercurial-managed languages
cd ${L10N_DIR}
for lang in ${HG_LANGS}
do
	if [ $opt_vc ]; then
		if [ -d ${lang} ]; then
			if [ -d ${lang}/.hg ]; then
			        (cd ${lang}
				hg revert $hgverbosity --all -r default
				hg pull $hgverbosity -u
				hg update $hgverbosity -C)
			else
			        rm -rf ${lang}/* 
			fi
		else
		    hg clone $hgverbosity http://hg.mozilla.org/releases/l10n/mozilla-aurora/${lang} ${lang} || mkdir ${lang}
		fi
		find ${lang} -name '*.orig' | xargs  --no-run-if-empty rm
	fi
done

[ -d pot ] && rm -rf pot

# Extract the en-US source files from the repo into localisation structure
rm -rf en-US
get_moz_enUS.py -s ../mozilla-aurora -d . -p browser  # add -v to debug
get_moz_enUS.py -s ../mozilla-aurora -d . -p mobile   # add -v to debug

# CREATE POT FILES FROM en-US
moz2po --errorlevel=$errorlevel --progress=$progress -P --duplicates=msgctxt --exclude '.hg' en-US pot
find pot \( -name '*.html.pot' -o -name '*.xhtml.pot' \) -exec rm -f {} \;

# The following functions are used in the loop following it
function copyfile {
	filename=$1
	language=$2
	directory=$(dirname $filename)
	if [ -f ${L10N_DIR}/en-US/$filename ]; then
		mkdir -p ${L10N_DIR}/$language/$directory
		cp -p ${L10N_DIR}/en-US/$filename ${L10N_DIR}/$language/$directory
	fi
}

function copyfileifmissing {
	filename=$1
	language=$2
	if [ ! -f ${L10N_DIR}/$language/$filename ]; then
		copyfile $1 $2
	fi
}

function copyfiletype {
	filetype=$1
	language=$2
	files=$(cd ${L10N_DIR}/en-US; find . -name "$filetype")
	for file in $files
	do
		copyfile $file $language
	done
}

function copydir {
	dir=$1
	language=$2
	if [ -d ${L10N_DIR}/en-US/$dir ]; then
		files=$(cd ${L10N_DIR}/en-US/$dir && find . -type f)
		for file in $files
		do
			copyfile $dir/$file $language
		done
	fi
}

for lang in ${HG_LANGS}
do
	[ $COUNT_LANGS -gt 1 ] && echo "Language: $lang"
	# Try and update existing PO files
        polang=$(echo $lang|sed "s/-/_/g")
	(cd ${PO_DIR}; svn up $svnverbosity ${polang})

	# Copy directory structure while preserving version control metadata
	if [ -d ${PO_DIR}/${polang} ]; then
		rm -rf ${POUPDATED_DIR}/${polang}
		cp -R ${PO_DIR}/${polang} ${POUPDATED_DIR}
		(cd ${POUPDATED_DIR/${polang}; find $PRODUCT_DIRS -name '*.po' -exec rm -f {} \;)
	fi

	## MIGRATE - Migrate PO files to new POT files.
	# Comment out the following "pomigrate2"-line if migration should not be done.
	tempdir=`mktemp -d tmp.XXXXXXXXXX`
	[ -d ${PO_DIR}/${polang} ] && cp -R ${PO_DIR}/${polang} ${tempdir}/${polang}
	pomigrate2 --use-compendium --pot2po $pomigrate2verbosity ${tempdir}/${polang} ${POUPDATED_DIR}/${polang} ${L10N_DIR}/pot
	rm -rf ${tempdir}

	## Cleanup migrated PO files
	# msgcat to make them look the same
	if [ $USECPO -eq 0 ]; then
		(cd ${POUPDATED_DIR}/${polang}
		for po in $(find ${PRODUCT_DIRS} -name "*.po")
		do
			msgcat -o $po.2 $po 2> >(egrep -v "warning: internationalised messages should not contain the .* escape sequence" >&2) && mv $po.2 $po
		done
		)
	fi

	# Revert files with only header changes
	[ -d ${POUPDATED_DIR}/${polang}/.svn ] && svn revert $svnverbosity $(svn diff --diff-cmd diff -x "--unified=3 --ignore-matching-lines=POT-Creation --ignore-matching-lines=X-Generator -s" ${POUPDATED_DIR}/${polang} |
	egrep "are identical$" |
	sed "s/^Files //;s/\(\.po\).*/\1/") || echo "No header only changes, so no reverts needed"

	## Migrate to new PO files: move old to obsolete/ and add new files
	if [ ! -d ${POUPDATED_DIR}/${polang}/.svn ]; then
		# No VC so assume it's a new language
		svn add $svnverbosity ${POUPDATED_DIR}/${polang}
	else
		(cd ${POUPDATED_DIR}/${polang}
		for newfile in $(svn status $PRODUCT_DIRS | egrep "^\?" | sed "s/\?\w*//")
		do
			[ -d $newfile ] && svn add $svnverbosity $newfile
			[ -f $newfile -a "$(echo $newfile | cut -d"." -f3)" = "po" ] && svn add $svnverbosity $newfile
		done

		if [ -d obsolete/.svn ]; then
			svn revert $svnverbosity -R obsolete
		else
			mkdir -p obsolete
			svn add $svnverbosity obsolete
		fi

		for oldfile in $(svn status $PRODUCT_DIRS | egrep "^!"| sed "s/!\w*//")
		do
			if [ -d $newfile ]; then
				svn revert $svnverbosity -R $oldfile
				svn move $svnverbosity --parents $oldfile obsolete/$oldfile
			fi
			if [ -f $newfile -a "$(echo $newfile | cut -d"." -f3)" = "po" ]; then
				svn revert $svnverbosity $oldfile
				svn move $svnverbosity --parents $oldfile obsolete/$oldfile
			fi
		done
		)
	fi

	# Pre-po2moz hacks
	lang_product_dirs=
	for dir in ${PRODUCT_DIRS}; do lang_product_dirs="${lang_product_dirs} ${L10N_DIR}/$lang/$dir"; done
	for product_dir in ${lang_product_dirs}
	do
		[ -d ${product_dir} ] && find ${product_dir} \( -name '*.dtd' -o -name '*.properties' \) -exec rm -f {} \;
	done
	find ${POUPDATED_DIR} \( -name '*.html.po' -o -name '*.xhtml.po' \) -exec rm -f {} \;

	# PO2MOZ - Create Mozilla l10n layout from migrated PO files.
	# Comment out the "po2moz"-line below to prevent l10n files to be updated to the current PO files.
	po2moz --progress=$progress --errorlevel=$errorlevel --exclude=".svn" --exclude=".hg" --exclude="obsolete" --exclude="editor" --exclude="mail" --exclude="thunderbird" \
		-t ${L10N_DIR}/en-US -i ${POUPDATED_DIR}/${polang} -o ${L10N_DIR}/${lang}

	# Copy files not handled by moz2po/po2moz
	if [ $opt_copyfiles ]; then
		copyfiletype "*.xhtml" ${lang} # Our XHTML and HTML is broken
		copyfiletype "*.rdf" ${lang}   # Don't support .rdf files
		copyfile browser/firefox-l10n.js ${lang}
		copyfile browser/profile/chrome/userChrome-example.css ${lang}
		copyfile browser/profile/chrome/userContent-example.css ${lang}
		copyfileifmissing toolkit/chrome/global/intl.css ${lang}
		# This one needs special approval but we need it to pass and compile
		copyfileifmissing browser/searchplugins/list.txt ${lang}
		# Revert some files that need careful human review or authorisation
		if [ -d ${L10N_DIR}/${lang}/.hg ]; then
			(cd ${L10N_DIR}/${lang}
			hg revert $hgverbosity browser/chrome/browser-region/region.properties browser/searchplugins/list.txt
			rm -f browser/chrome/browser-region/region.properties.orig browser/searchplugins/list.txt.orig )
		fi
	fi

	## CREATE XPI LANGPACK
	if [ $opt_build_xpi ]; then
		buildxpi.py -d -L ${L10N_DIR} -s ${MOZCENTRAL_DIR} -o ${LANGPACK_DIR} ${lang}
	fi

	# COMPARE LOCALES
	if [ $opt_compare_locales ]; then
		compare-locales ${MOZCENTRAL_DIR}/browser/locales/l10n.ini ${L10N_DIR} $lang
		compare-locales ${MOZCENTRAL_DIR}/mobile/locales/l10n.ini ${L10N_DIR} $lang
	fi

done

# Cleanup rubbish we seem to leave behind
rm -rf ${L10N_DIR}/tmp*
