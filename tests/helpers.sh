# shellcheck shell=bash
# shellcheck disable=SC2034  # the test files use these variables
# Helpers of the unit tests. A test file sources this file first.
# No test runs the real sbx or reads the files of the person who runs the tests: each command runs with an empty
# environment, a HOME below a temporary folder, and a PATH that holds only the folders of the test and of the system.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(cd "$(mktemp -d)" && pwd -P)
passed=0
fails=0
count=0
rc=0
# The file that a command of run gets as its stdin.
input=/dev/null
cleanup() {
  chmod -R u+rwx "$tmp" 2>/dev/null || true
  rm -rf "$tmp"
  [ "$passed" -eq 1 ] || exit 1
}
trap cleanup EXIT

home=$tmp/home
real=$tmp/real
wbin=$tmp/wbin
shell=$tmp/shell
calls=$tmp/calls
out=$tmp/out
err=$tmp/err
state=$tmp/state
list=$home/.config/sbx-instances/instances
mkdir -p "$home" "$real" "$wbin" "$shell" "$state"
# The scripts start with "env bash": this link makes them run with the bash that runs the test.
ln -s "$BASH" "$shell/bash"
ln -s "$root/bin/sbx" "$wbin/sbx"
ln -s "$root/bin/sbx-instance" "$wbin/sbx-instance"
# The wrapper first, then the stub in the place of the real sbx.
path=$wbin:$real:$shell:/usr/bin:/bin
no_real_path=$wbin:$shell:/usr/bin:/bin

# The stub in the place of the real sbx: one line in $STUB_LOG for each call, with each argument in <...>.
# STUB_ENV and STUB_STDIN name a file that gets the environment and the stdin of the call. STUB_EXIT is the status.
cat >"$real/sbx" <<'EOF'
#!/usr/bin/env bash
{
  printf 'sbx'
  for arg in "$@"; do printf ' <%s>' "$arg"; done
  printf '\n'
} >>"$STUB_LOG"
[ -z "${STUB_ENV:-}" ] || env >"$STUB_ENV"
[ -z "${STUB_STDIN:-}" ] || cat >"$STUB_STDIN"
exit "${STUB_EXIT:-0}"
EOF
chmod +x "$real/sbx"

# run <folder> [VAR=value | unset:VAR]... -- <command> [argument...]: runs the command in the folder, with the test
# environment only. Sets rc; stdout goes to $out, stderr to $err, the calls of the stub to $calls.
# stdin is the file $input.
run() {
  local dir=$1 item name
  local envs=("HOME=$home" "XDG_CONFIG_HOME=$home/.config" "PATH=$path" "STUB_LOG=$calls" "STUB_STATE=$state")
  local kept=()
  shift
  while [ "$1" != -- ]; do
    case "$1" in
      unset:*)
        name=${1#unset:}
        kept=()
        for item in "${envs[@]}"; do
          [ "${item%%=*}" = "$name" ] || kept+=("$item")
        done
        envs=("${kept[@]}")
        ;;
      *) envs+=("$1") ;;
    esac
    shift
  done
  shift
  : >"$calls"
  rc=0
  (cd "$dir" && exec env -i "${envs[@]}" "$@") >"$out" 2>"$err" <"$input" || rc=$?
}

# expect <title> <command> [argument...]: one assertion.
expect() {
  local title=$1
  shift
  count=$((count + 1))
  if "$@"; then
    echo "PASS $title"
  else
    echo "FAIL $title"
    fails=$((fails + 1))
  fi
}

called() { grep -qF -- "$1" "$calls"; }
not() { ! "$@"; }
not_called() { ! called "$1"; }
# calls_are <line>...: the stub got exactly these calls, in this order.
calls_are() {
  local want=""
  [ $# -eq 0 ] || want=$(printf '%s\n' "$@")
  [ "$(cat "$calls")" = "$want" ]
}
said() { grep -qF -- "$1" "$out" "$err"; }
not_said() { ! said "$1"; }
rc_is() { [ "$rc" -eq "$1" ]; }
out_is() { [ "$(cat "$out")" = "$1" ]; }
no_out() { [ ! -s "$out" ]; }

# fresh: a home folder with no list and no marker file.
fresh() {
  chmod -R u+rwx "$home" 2>/dev/null || true
  rm -rf "$home"
  mkdir -p "$home"
}
# a_marker <folder> <content>: a marker file with this content and a line end.
a_marker() {
  mkdir -p "$1"
  printf '%s\n' "$2" >"$1/.sbx-instance"
}
# a_list <name>...: the list holds these names.
a_list() {
  local name
  mkdir -p "$(dirname "$list")"
  : >"$list"
  for name in "$@"; do
    echo "$name" >>"$list"
  done
}
list_is() { [ "$(cat "$list" 2>/dev/null)" = "$1" ]; }

finish() {
  echo "$((count - fails)) of $count passed"
  [ "$fails" -eq 0 ] || exit 1
  passed=1
}
