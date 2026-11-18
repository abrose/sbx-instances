#!/usr/bin/env bash
# Unit tests of the tool bin/sbx-instance. The tool runs by its name, through a link in PATH.
set -euo pipefail
# shellcheck source=tests/helpers.sh
. "$(dirname "$0")/helpers.sh"

refused() { [ "$rc" -eq 64 ] && no_calls && no_out; }
usage_error() { [ "$rc" -eq 2 ] && no_calls && no_out && said "usage: sbx-instance"; }

# setup: the list holds alpha and beta; the folder p has a marker file for alpha; the folder none has none.
setup() {
  fresh
  a_list alpha beta
  a_marker "$home/p" alpha
  mkdir -p "$home/p/a/b" "$home/none"
}

echo "== no command"
setup
run "$home" -- sbx-instance
expect "no command: the usage, status 2" usage_error
run "$home" -- sbx-instance nothing
expect "a command that does not exist: the usage, status 2" usage_error

echo "== list"
setup
run "$home/none" -- sbx-instance list
expect "list prints the names" out_is "alpha
beta"
expect "list calls no sbx" calls_are
a_list
run "$home" -- sbx-instance list
expect "an empty list prints nothing" no_out
expect "an empty list is no error" rc_is 0
fresh
run "$home" -- sbx-instance list
expect "no list file prints nothing" no_out
expect "no list file is no error" rc_is 0

echo "== which"
setup
run "$home/p/a/b" -- sbx-instance which
expect "which prints the name alone on stdout" out_is alpha
expect "which names the marker file on stderr" grep -qF "$home/p/.sbx-instance" "$err"
expect "which calls no sbx" calls_are
# The real sbx before the wrapper in PATH: a plain sbx there uses no instance, so which must not name one.
run "$home/p/a/b" "PATH=$real:$wbin:$shell:/usr/bin:/bin" -- sbx-instance which
expect "which, the real sbx is first in PATH: refused" refused
expect "which, the real sbx is first in PATH: the message names it" said "$real/sbx"
run "$home/p/a/b" "PATH=$wbin/sbx-instance-only:$shell:/usr/bin:/bin" -- "$wbin/sbx-instance" which
expect "which, no sbx in PATH: refused" refused
run "$home/none" -- sbx-instance which
expect "which with no marker file: refused as the wrapper does" refused
expect "which with no marker file: the message of the wrapper" said "sbx-instance add"
a_marker "$home/p/a" gamma
run "$home/p/a/b" -- sbx-instance which
expect "which with a name not on the list: refused" refused

echo "== run"
setup
a_marker "$home/q" beta
a_marker "$tmp/outside" beta
run "$home/none" -- sbx-instance run alpha -- ls
expect "run in a folder with no marker file" calls_are "sbx <--app-name> <alpha> <ls>"
run "$home/q" -- sbx-instance run alpha -- ls
expect "run in a folder whose marker file names another instance" calls_are "sbx <--app-name> <alpha> <ls>"
run "$tmp/outside" -- sbx-instance run alpha -- ls
expect "run in a folder outside the home folder" calls_are "sbx <--app-name> <alpha> <ls>"
run "$home/none" -- sbx-instance run alpha --
expect "run with no sbx argument" calls_are "sbx <--app-name> <alpha>"
run "$home/none" -- sbx-instance run default -- ls
expect "run default, not on the list: refused" refused
a_list alpha default
run "$home/none" -- sbx-instance run default -- ls -a
expect "run default gives no --app-name" calls_are "sbx <ls> <-a>"
run "$home/none" -- sbx-instance run gamma -- ls
expect "run with a name not on the list: refused" refused
expect "run with a name not on the list: the message names the list" said "$list"
run "$home/none" -- sbx-instance run Alpha -- ls
expect "run with a name that is not valid: refused" refused
run "$home/none" -- sbx-instance run alpha -- ls --app-name x
expect "run with the hidden argument in the sbx arguments: refused" refused
run "$home/none" -- sbx-instance run alpha -- --app-name=x ls
expect "run with --app-name=x in the sbx arguments: refused" refused
run "$home/none" -- sbx-instance run alpha -- exec box -- tool --app-name x
expect "run: --app-name after the second -- goes to the sandbox" \
  calls_are "sbx <--app-name> <alpha> <exec> <box> <--> <tool> <--app-name> <x>"
run "$home/none" -- sbx-instance run alpha ls
expect "run with no --: the usage" usage_error
run "$home/none" -- sbx-instance run alpha
expect "run with a name only: the usage" usage_error
run "$home/none" -- sbx-instance run
expect "run with no name: the usage" usage_error
run "$home/none" -- sbx-instance run -- ls
expect "run with -- in the place of the name: the usage" usage_error
run "$home/none" -- sbx-instance run alpha -- exec box sh -c 'echo  a  b' "" '*'
expect "run: each argument arrives as it came" \
  calls_are "sbx <--app-name> <alpha> <exec> <box> <sh> <-c> <echo  a  b> <> <*>"
run "$home/none" STUB_EXIT=7 -- sbx-instance run alpha -- ls
expect "run: the status of sbx is the status" rc_is 7
printf 'typed text' >"$tmp/in"
input=$tmp/in
run "$home/none" "STUB_STDIN=$tmp/got" -- sbx-instance run alpha -- exec box cat
input=/dev/null
expect "run: stdin reaches sbx" [ "$(cat "$tmp/got" 2>/dev/null)" = "typed text" ]
run "$home/none" "PATH=$no_real_path" -- sbx-instance run alpha -- ls
expect "run with no real sbx: status 127" rc_is 127

echo "== remove"
setup
printf '# my instances\nalpha\n  beta\n' >"$list"
run "$home/none" -- sbx-instance remove beta
expect "remove takes the name off the list and keeps the other lines" list_is "# my instances
alpha"
expect "remove: status 0" rc_is 0
expect "remove asks sbx only for the paths of the instance" calls_are "sbx <--app-name> <beta> <daemon> <status>"
expect "remove says that nothing else is deleted" said "Nothing else is deleted"
expect "remove prints the paths of the instance that stay" said "/stub/Application Support/sandboxes-beta/"
expect "remove names the marker files" said ".sbx-instance"
expect "remove leaves no part of a file" [ ! -e "$list.new" ]
run "$home/none" -- sbx-instance remove gamma
expect "remove with a name not on the list: refused" refused
expect "remove with a name not on the list: the list is unchanged" list_is "# my instances
alpha"
run "$home/none" -- sbx-instance remove
expect "remove with no name: the usage" usage_error
run "$home/none" STUB_EXIT=1 -- sbx-instance remove alpha
expect "remove when sbx does not answer: the name still goes" list_is "# my instances"
expect "remove when sbx does not answer: status 0" rc_is 0
a_list alpha
run "$home/none" "PATH=$no_real_path" -- sbx-instance remove alpha
expect "remove with no real sbx: the name still goes" list_is ""
# A name on the list that is no instance name never reaches sbx: sbx would create an instance of that name.
a_list alpha Alpha
run "$home/none" -- sbx-instance remove Alpha
expect "remove of a listed name that is no instance name: the name goes" list_is alpha
expect "remove of a listed name that is no instance name: status 0" rc_is 0
expect "remove of a listed name that is no instance name: no sbx call" no_calls
# A list file that is a link (for example into a dotfiles repo) stays a link.
a_list alpha beta
mkdir -p "$home/dotfiles"
mv "$list" "$home/dotfiles/instances"
ln -s ../../dotfiles/instances "$list"
run "$home/none" -- sbx-instance remove beta
expect "remove through a link: the list file is still a link" [ -L "$list" ]
expect "remove through a link: the file behind the link lost the name" \
  [ "$(cat "$home/dotfiles/instances")" = alpha ]

finish
