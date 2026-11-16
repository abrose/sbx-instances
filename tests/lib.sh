#!/usr/bin/env bash
# Unit tests of lib/instances.sh.
set -euo pipefail
# shellcheck source=tests/helpers.sh
. "$(dirname "$0")/helpers.sh"

# A wrapper that is not the one of the repo: si_real_sbx must skip the file $SI_ROOT/bin/sbx, whatever it holds.
froot=$tmp/froot
fbin=$tmp/fbin
mkdir -p "$froot/bin" "$fbin"
# shellcheck disable=SC2016
printf '#!/bin/sh\necho WRAPPER >>"$STUB_LOG"\n' >"$froot/bin/sbx"
chmod +x "$froot/bin/sbx"
ln -s "$froot/bin/sbx" "$fbin/sbx"
lpath=$fbin:$real:$shell:/usr/bin:/bin

# lib <folder> [VAR=value | unset:VAR]... -- <function> [argument...]: calls one function of the library.
lib() {
  local dir=$1 envs=()
  shift
  while [ "$1" != -- ]; do
    envs+=("$1")
    shift
  done
  shift
  # shellcheck disable=SC2016
  run "$dir" "SI_ROOT=$froot" "SI_LIB=$root/lib/instances.sh" "PATH=$lpath" ${envs[@]+"${envs[@]}"} -- \
    bash -c 'set -euo pipefail; . "$SI_LIB"; "$@"' lib "$@"
}

echo "== si_list_file"
lib "$home" -- si_list_file
expect "the list is below XDG_CONFIG_HOME" out_is "$home/.config/sbx-instances/instances"
lib "$home" unset:XDG_CONFIG_HOME -- si_list_file
expect "with no XDG_CONFIG_HOME the list is below ~/.config" out_is "$home/.config/sbx-instances/instances"
lib "$home" "XDG_CONFIG_HOME=$tmp/xdg" -- si_list_file
expect "another XDG_CONFIG_HOME moves the list" out_is "$tmp/xdg/sbx-instances/instances"

echo "== si_names, si_listed"
fresh
lib "$home" -- si_names
expect "no list file gives no name" no_out
expect "no list file is no error" rc_is 0
mkdir -p "$(dirname "$list")"
printf '# the instances\nalpha\n\n  beta  \n#gamma\ncheck' >"$list"
lib "$home" -- si_names
expect "the names of the list, with no comment and no empty line" out_is "alpha
beta
check"
lib "$home" -- si_listed alpha
expect "a name on the list is listed" rc_is 0
lib "$home" -- si_listed check
expect "the last line with no line end is listed" rc_is 0
lib "$home" -- si_listed gamma
expect "a name in a comment is not listed" rc_is 1
lib "$home" -- si_listed alph
expect "a part of a name is not listed" rc_is 1

echo "== si_valid"
valid() {
  lib "$home" -- si_valid "$1"
  [ "$rc" -eq 0 ]
}
invalid() {
  lib "$home" -- si_valid "$1"
  [ "$rc" -eq 1 ]
}
expect "a is valid" valid a
expect "a-b-1 is valid" valid a-b-1
expect "default is valid" valid default
expect "31 characters are valid" valid a123456789012345678901234567890
expect "32 characters are not valid" invalid a1234567890123456789012345678901
expect "a leading dash is not valid" invalid -a
expect "a capital letter is not valid" invalid A
expect "an underscore is not valid" invalid a_b
expect "a space is not valid" invalid "a b"
expect "the empty text is not valid" invalid ""
expect "two lines are not valid" invalid "a
b"

echo "== si_real_sbx"
lib "$home" -- si_real_sbx
expect "the first sbx that is not the wrapper" out_is "$real/sbx"
lib "$home" "PATH=$fbin:$fbin:$real:/usr/bin:/bin:$shell" -- si_real_sbx
expect "the wrapper two times in PATH" out_is "$real/sbx"
mkdir -p "$tmp/other" "$tmp/chain"
ln -s "$froot/bin/sbx" "$tmp/other/sbx"
ln -s ../fbin/sbx "$tmp/chain/sbx"
lib "$home" "PATH=$fbin:$tmp/other:$tmp/chain:$real:$shell:/usr/bin:/bin" -- si_real_sbx
expect "a second link and a link to the link are the wrapper too" out_is "$real/sbx"
lib "$home" "PATH=$froot/bin:$real:$shell:/usr/bin:/bin" -- si_real_sbx
expect "the wrapper file itself in PATH" out_is "$real/sbx"
mkdir -p "$tmp/folder/sbx" "$tmp/plain"
echo text >"$tmp/plain/sbx"
lib "$home" "PATH=$fbin:$tmp/folder:$tmp/plain::$real:$shell:/usr/bin:/bin" -- si_real_sbx
expect "a folder, a file that cannot run and an empty entry are skipped" out_is "$real/sbx"
lib "$home" "PATH=$fbin:$shell:/usr/bin:/bin" -- si_real_sbx
expect "no real sbx gives status 1" rc_is 1
expect "no real sbx prints nothing" no_out

echo "== si_marker"
fresh
mkdir -p "$home/proj/a/b"
lib "$home/proj/a/b" -- si_marker
expect "no marker file gives status 1" rc_is 1
a_marker "$home/proj" alpha
lib "$home/proj" -- si_marker
expect "the marker file of the working folder" out_is "$home/proj/.sbx-instance"
lib "$home/proj/a/b" -- si_marker
expect "a marker file two folders up" out_is "$home/proj/.sbx-instance"
a_marker "$home/proj/a" beta
lib "$home/proj/a/b" -- si_marker
expect "the nearest marker file wins" out_is "$home/proj/a/.sbx-instance"
fresh
mkdir -p "$home/proj"
a_marker "$home" alpha
lib "$home/proj" -- si_marker
expect "a marker file in the home folder counts" out_is "$home/.sbx-instance"
lib "$home" -- si_marker
expect "the home folder as the working folder" out_is "$home/.sbx-instance"
fresh
mkdir -p "$home/proj" "$tmp/outside/sub"
a_marker "$tmp" alpha
lib "$home/proj" -- si_marker
expect "a marker file above the home folder does not count" rc_is 1
a_marker "$tmp/outside" alpha
lib "$tmp/outside/sub" -- si_marker
expect "a working folder outside the home folder has no marker file" rc_is 1
rm "$tmp/.sbx-instance"
mkdir -p "$home/proj/sub" "$home/links"
a_marker "$home/proj" alpha
ln -s "$home/proj/sub" "$home/links/in"
ln -s "$tmp/outside/sub" "$home/links/out"
lib "$home/links/in" -- si_marker
expect "a working folder behind a link: the physical folder counts" out_is "$home/proj/.sbx-instance"
lib "$home/links/out" -- si_marker
expect "a link to a folder outside the home folder has no marker file" rc_is 1
a_marker "$home/links" beta
lib "$home/links/in" -- si_marker
expect "a marker file beside the link does not count" out_is "$home/proj/.sbx-instance"
ln -s "$home" "$tmp/homelink"
lib "$home/proj/sub" "HOME=$tmp/homelink" -- si_marker
expect "a home folder that is a link" out_is "$home/proj/.sbx-instance"
lib "$home/proj/sub" unset:HOME -- si_marker
expect "with no HOME there is no marker file" rc_is 1
lib "$home/proj/sub" HOME= -- si_marker
expect "with an empty HOME there is no marker file" rc_is 1
mkdir -p "$home/dirmark/.sbx-instance" "$home/dirmark/sub"
lib "$home/dirmark/sub" -- si_marker
expect "a folder with the name of the marker file is the nearest one" out_is "$home/dirmark/.sbx-instance"

echo "== si_marker_name"
name_of() {
  # shellcheck disable=SC2059
  printf "$1" >"$tmp/marker"
  lib "$home" -- si_marker_name "$tmp/marker"
}
name_of 'alpha\n'
expect "the name in the file" out_is alpha
name_of '  alpha \t\r\n'
expect "the spaces around the name go" out_is alpha
name_of '\n\n beta\n'
expect "the first line that is not empty" out_is beta
name_of 'alpha'
expect "a file with no line end" out_is alpha
name_of ''
expect "an empty file gives status 1" rc_is 1
name_of ' \n\n'
expect "a file of spaces gives status 1" rc_is 1
lib "$home" -- si_marker_name "$tmp/none"
expect "no file gives status 1" rc_is 1
lib "$home" -- si_marker_name "$home/dirmark/.sbx-instance"
expect "a folder gives status 1" rc_is 1
if [ "$(id -u)" -ne 0 ]; then
  name_of 'alpha\n'
  chmod 000 "$tmp/marker"
  lib "$home" -- si_marker_name "$tmp/marker"
  expect "a file that cannot be read gives status 1" rc_is 1
  expect "a file that cannot be read prints no name" no_out
  chmod 600 "$tmp/marker"
fi

echo "== si_hidden_arg"
hidden() {
  lib "$home" -- si_hidden_arg "$@"
  [ "$rc" -eq 0 ]
}
not_hidden() {
  lib "$home" -- si_hidden_arg "$@"
  [ "$rc" -eq 1 ]
}
expect "--app-name first" hidden --app-name x ls
expect "--app-name after the subcommand" hidden ls --app-name x
expect "--app-name=x" hidden ls --app-name=x
expect "--app-name after -- is an argument of the command in the sandbox" not_hidden exec box -- tool --app-name x
expect "--app-name before and after --" hidden exec --app-name x box -- tool
expect "no --app-name" not_hidden ls -a
expect "no argument at all" not_hidden
expect "another argument that starts the same" not_hidden --app-names x

echo "== si_run"
lib "$home" -- si_run alpha ls -a
expect "a named instance gets --app-name first" calls_are "sbx <--app-name> <alpha> <ls> <-a>"
lib "$home" -- si_run default ls -a
expect "default gets no --app-name" calls_are "sbx <ls> <-a>"
lib "$home" -- si_run alpha exec box sh -c 'echo  a  b' "" '*' -- --x
expect "each argument arrives as it came" calls_are "sbx <--app-name> <alpha> <exec> <box> <sh> <-c> <echo  a  b> <> <*> <--> <--x>"
lib "$home" STUB_EXIT=7 -- si_run alpha ls
expect "the status of sbx is the status" rc_is 7
lib "$home" "PATH=$fbin:$shell:/usr/bin:/bin" -- si_run alpha ls
expect "no real sbx gives status 127" rc_is 127
expect "no real sbx gives a message" said "no sbx"
expect "the wrapper does not run itself" not_called WRAPPER

finish
