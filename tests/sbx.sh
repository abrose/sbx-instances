#!/usr/bin/env bash
# Unit tests of the wrapper bin/sbx. The wrapper runs as a person runs it: by the name sbx, through a link in PATH.
set -euo pipefail
# shellcheck source=tests/helpers.sh
. "$(dirname "$0")/helpers.sh"

refused() { [ "$rc" -eq 64 ] && no_calls && no_out; }

# setup: the list holds alpha and beta; the folder p has a marker file for alpha; the folder none has none.
setup() {
  fresh
  a_list alpha beta
  a_marker "$home/p" alpha
  mkdir -p "$home/p/a/b" "$home/none"
}

echo "== rule 1: the hidden argument"
setup
run "$home/p" -- sbx --app-name x ls
expect "--app-name first: refused" refused
expect "--app-name first: the message names sbx-instance run" said "sbx-instance run"
run "$home/p" -- sbx ls --app-name x
expect "--app-name after the subcommand: refused" refused
run "$home/p" -- sbx ls --app-name=x
expect "--app-name=x: refused" refused
run "$home/p" -- sbx version --app-name x
expect "--app-name with a command that needs no instance: refused" refused
run "$home/p" -- sbx exec box -- tool --app-name x
expect "--app-name after -- goes to the sandbox" \
  calls_are "sbx <--app-name> <alpha> <exec> <box> <--> <tool> <--app-name> <x>"

echo "== rule 2: a command that needs no instance"
setup
plain() {
  local want="sbx" arg
  for arg in "$@"; do want="$want <$arg>"; done
  run "$home/none" -- sbx "$@"
  [ "$rc" -eq 0 ] && calls_are "$want"
}
expect "version runs with no instance" plain version
expect "help runs with no instance" plain help
expect "--help runs with no instance" plain --help
expect "-h runs with no instance" plain -h
expect "completion runs with no instance" plain completion zsh
expect "__complete runs with no instance" plain __complete ls ""
expect "__completeNoDesc runs with no instance" plain __completeNoDesc ls
run "$home/p" -- sbx version
expect "version in a folder with a marker file runs with no instance too" calls_are "sbx <version>"

echo "== rules 3 and 7: the nearest marker file"
setup
run "$home/p/a/b" -- sbx ls
expect "a marker file two folders up selects the instance" calls_are "sbx <--app-name> <alpha> <ls>"
a_marker "$home/p/a" beta
run "$home/p/a/b" -- sbx ls
expect "a marker file below another one wins" calls_are "sbx <--app-name> <beta> <ls>"
run "$home/p" -- sbx ls
expect "the folder above still has its own instance" calls_are "sbx <--app-name> <alpha> <ls>"
run "$home/p" -- sbx
expect "no argument, with a marker file" calls_are "sbx <--app-name> <alpha>"

echo "== rule 4: no marker file"
setup
run "$home/none" -- sbx ls
expect "no marker file: refused" refused
expect "no marker file: the message names the working folder" said "$home/none"
expect "no marker file: the message names the three ways" said "sbx-instance add"
run "$home/none" -- sbx
expect "no marker file and no argument: refused" refused
a_marker "$tmp/outside" alpha
run "$tmp/outside" -- sbx ls
expect "a working folder outside the home folder: refused" refused
a_marker "$tmp" alpha
run "$home/none" -- sbx ls
expect "a marker file above the home folder: refused" refused
rm "$tmp/.sbx-instance"

echo "== rule 5: a name that is not on the list"
setup
a_marker "$home/p/a" gamma
run "$home/p/a/b" -- sbx ls
expect "a name not on the list, below a good marker file: refused" refused
expect "the message names the marker file" said "$home/p/a/.sbx-instance"
expect "the message names the list" said "$list"
a_marker "$home/p/a" Alpha
run "$home/p/a/b" -- sbx ls
expect "a name that is not valid: refused" refused
a_marker "$home/p/a" "alpha beta"
run "$home/p/a/b" -- sbx ls
expect "two names in one line: refused" refused
: >"$home/p/a/.sbx-instance"
run "$home/p/a/b" -- sbx ls
expect "an empty marker file: refused" refused
rm "$home/p/a/.sbx-instance"
mkdir "$home/p/a/.sbx-instance"
run "$home/p/a/b" -- sbx ls
expect "a marker file that is a folder: refused" refused
rmdir "$home/p/a/.sbx-instance"
a_marker "$home/p/a" "  beta  "
run "$home/p/a/b" -- sbx ls
expect "spaces around the name in the marker file" calls_are "sbx <--app-name> <beta> <ls>"

echo "== rule 6: default"
setup
a_marker "$home/d" default
run "$home/d" -- sbx ls
expect "default that is not on the list: refused" refused
a_list alpha default
run "$home/d" -- sbx ls -a
expect "default on the list runs with no --app-name" calls_are "sbx <ls> <-a>"

echo "== a selection never fails without a word"
setup
if [ "$(id -u)" -ne 0 ]; then
  chmod 000 "$home/p/.sbx-instance"
  run "$home/p" -- sbx ls
  expect "a marker file that cannot be read: refused" refused
  chmod 600 "$home/p/.sbx-instance"
  chmod 000 "$list"
  run "$home/p" -- sbx ls
  expect "a list that cannot be read: refused" refused
  chmod 600 "$list"
fi
run "$home/p" unset:HOME -- sbx ls
expect "no HOME: refused" refused
run "$home/p" HOME= -- sbx ls
expect "an empty HOME: refused" refused
rm "$list"
run "$home/p" -- sbx ls
expect "no list file: refused" refused
setup
mkdir "$home/p/gone"
: >"$calls"
rc=0
(cd "$home/p/gone" && rmdir "$home/p/gone" &&
  exec env -i "HOME=$home" "XDG_CONFIG_HOME=$home/.config" "PATH=$path" "STUB_LOG=$calls" sbx ls) \
  >"$out" 2>"$err" </dev/null || rc=$?
expect "a working folder that is gone: no call with no instance" not_called "sbx <ls>"

echo "== the call passes through"
setup
run "$home/p" -- sbx exec box sh -c 'echo  a  b' "" '*' -- --x
expect "each argument arrives as it came" \
  calls_are "sbx <--app-name> <alpha> <exec> <box> <sh> <-c> <echo  a  b> <> <*> <--> <--x>"
run "$home/p" STUB_EXIT=7 -- sbx ls
expect "the status of sbx is the status of the wrapper" rc_is 7
printf 'typed text' >"$tmp/in"
input=$tmp/in
run "$home/p" "STUB_STDIN=$tmp/got" -- sbx exec box cat
input=/dev/null
expect "stdin reaches sbx" [ "$(cat "$tmp/got" 2>/dev/null)" = "typed text" ]
run "$home/p" PROBE_VAR=1 "STUB_ENV=$tmp/env" -- sbx ls
expect "a variable of the caller reaches sbx" grep -qx 'PROBE_VAR=1' "$tmp/env"
expect "the wrapper adds no variable of its own" not grep -qE '^(SI_|SBX_INSTANCE)' "$tmp/env"

echo "== the real sbx"
setup
run "$home/p" "PATH=$no_real_path" -- sbx ls
expect "no real sbx: status 127" rc_is 127
expect "no real sbx: a message" said "no sbx"
mkdir -p "$tmp/second"
ln -sf "$wbin/sbx" "$tmp/second/sbx"
run "$home/p" "PATH=$wbin:$wbin:$tmp/second:$real:$shell:/usr/bin:/bin" -- sbx ls
expect "the wrapper two times and a second link in PATH: the real sbx runs" \
  calls_are "sbx <--app-name> <alpha> <ls>"
run "$home/p" "PATH=$wbin:$tmp/second:$shell:/usr/bin:/bin" -- sbx ls
expect "only links to the wrapper in PATH: status 127, no loop" rc_is 127

finish
