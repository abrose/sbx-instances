#!/usr/bin/env bash
# Unit tests of install.sh.
set -euo pipefail
# shellcheck source=tests/helpers.sh
. "$(dirname "$0")/helpers.sh"

ibin=$home/.local/bin
ipath=$ibin:$real:$shell:/usr/bin:/bin
# install [VAR=value]...: runs install.sh with the folder of the links first in PATH.
install() { run "$home" "PATH=$ipath" "$@" -- bash "$root/install.sh"; }
link_is() { [ -L "$1" ] && [ "$(readlink "$1")" = "$2" ]; }

echo "== a first install"
fresh
install
expect "a first install: status 0" rc_is 0
expect "the link sbx points into the repo" link_is "$ibin/sbx" "$root/bin/sbx"
expect "the link sbx-instance points into the repo" link_is "$ibin/sbx-instance" "$root/bin/sbx-instance"
expect "the install runs the check" said "PASS the wrapper is the first sbx in PATH"
expect "the install says what a plain sbx does from now on" said "refuses"
a_list alpha
echo deny-all >"$state/alpha.policy"
a_marker "$home/p" alpha
run "$home/p" "PATH=$ipath" -- sbx ls
expect "the installed wrapper selects the instance" calls_are "sbx <--app-name> <alpha> <ls>"

echo "== a second install"
install
expect "a second install: status 0" rc_is 0
expect "a second install: the link sbx is unchanged" link_is "$ibin/sbx" "$root/bin/sbx"

echo "== a file that is not a link of the install"
fresh
mkdir -p "$ibin"
echo mine >"$ibin/sbx-instance"
install
expect "a file with the name of a link: status 1" rc_is 1
expect "a file with the name of a link is unchanged" [ "$(cat "$ibin/sbx-instance")" = mine ]
expect "a file with the name of a link: the message names it" said "$ibin/sbx-instance"
expect "a file with the name of a link: no link is made" [ ! -e "$ibin/sbx" ]
fresh
mkdir -p "$ibin"
ln -s /usr/bin/true "$ibin/sbx"
install
expect "a link to another place: status 1" rc_is 1
expect "a link to another place is unchanged" link_is "$ibin/sbx" /usr/bin/true

echo "== another folder for the links"
fresh
install "SBX_INSTANCES_BIN=$tmp/ibin"
expect "a folder that is not in PATH: the links are made" link_is "$tmp/ibin/sbx" "$root/bin/sbx"
expect "a folder that is not in PATH: the check fails, status 1" rc_is 1
expect "a folder that is not in PATH: the FAIL line of the check" said "FAIL the wrapper is the first sbx in PATH"
expect "the default folder gets no link then" [ ! -e "$ibin/sbx" ]

finish
