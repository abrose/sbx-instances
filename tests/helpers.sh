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
[ "${STUB_EXIT:-0}" -eq 0 ] || exit "$STUB_EXIT"
# The stub answers some commands as sbx does. $name is the instance of the call.
name=default
if [ "${1:-}" = --app-name ]; then
  name=$2
  shift 2
fi
[ "${1:-}" != --no-input ] || shift
# The state of an instance is in files: $STUB_STATE/<name>.signed-out (not signed in to Docker), <name>.policy (its
# network policy) and <name>.settings.json (the answer of "settings ls --json").
case "${1:-} ${2:-}" in
  "ls "*)
    if [ -e "$STUB_STATE/$name.signed-out" ]; then
      echo "error: not signed in to Docker" >&2
      exit 1
    fi
    # "ls --json": one sandbox. STUB_RUNNING holds the instances where it runs; elsewhere it is stopped.
    if [ "${2:-}" = --json ]; then
      case " ${STUB_RUNNING:-} " in
        *" $name "*) echo '[{"name":"box","status":"running"}]' ;;
        *) echo '[{"name":"box","status":"stopped"}]' ;;
      esac
    fi
    ;;
  "login "*)
    # STUB_LOGIN_FAILS=1: the sign-in does not work.
    [ -n "${STUB_LOGIN_FAILS:-}" ] || rm -f "$STUB_STATE/$name.signed-out"
    ;;
  "policy init")
    # STUB_POLICY_FAILS=1: sbx cannot set the policy.
    if [ -n "${STUB_POLICY_FAILS:-}" ]; then
      echo "error: daemon fault" >&2
      exit 1
    fi
    if [ -e "$STUB_STATE/$name.policy" ]; then
      echo "error: global network policy is already initialized; reset it first to change it" >&2
      exit 1
    fi
    echo "$3" >"$STUB_STATE/$name.policy"
    ;;
  "policy ls")
    echo "POLICY             SOURCE   APPLIES TO   SUMMARY"
    [ ! -e "$STUB_STATE/$name.policy" ] ||
      echo "default-$(cat "$STUB_STATE/$name.policy")   local    all          network"
    echo "local-policy       local    all          filesystem read: 1 allow"
    ;;
  "secret set-custom")
    # STUB_LABEL_FAILS=1: sbx cannot store the custom secret. Else the placeholder goes to <name>.label.
    if [ -n "${STUB_LABEL_FAILS:-}" ]; then
      echo "error: daemon fault" >&2
      exit 1
    fi
    while [ $# -gt 1 ]; do
      [ "$1" != --placeholder ] || echo "$2" >"$STUB_STATE/$name.label"
      shift
    done
    echo "Saved custom secret for target sbx-instance.invalid env SBX_INSTANCE ((global))"
    ;;
  "secret ls")
    # The answer of "secret ls -g --env-name SBX_INSTANCE --json", as sbx v0.53.0 gives it.
    if [ -e "$STUB_STATE/$name.label" ]; then
      printf '{\n  "custom_secrets": [\n    {\n      "scope": "global",\n      "targets": [\n'
      printf '        "sbx-instance.invalid"\n      ],\n      "env": "SBX_INSTANCE",\n'
      printf '      "placeholder": "%s",\n      "secret": "*****"\n    }\n  ]\n}\n' "$(cat "$STUB_STATE/$name.label")"
    else
      printf '{\n  "custom_secrets": []\n}\n'
    fi
    ;;
  "settings ls")
    if [ -f "$STUB_STATE/$name.settings.json" ]; then
      cat "$STUB_STATE/$name.settings.json"
    else
      echo '[]'
    fi
    ;;
  "settings set")
    # STUB_SET_FAILS is a key that sbx cannot set.
    if [ "${STUB_SET_FAILS:-}" = "$3" ]; then
      echo "error: daemon fault" >&2
      exit 1
    fi
    # STUB_RESTART holds the keys whose change needs a restart of the daemon.
    case " ${STUB_RESTART:-} " in
      *" $3 "*)
        echo "warning: this setting takes effect only after a daemon restart"
        echo "  try: sbx daemon restart"
        ;;
    esac
    ;;
  "daemon status")
    # STUB_SOCKET_DIR is the folder in the socket path; without it, the folder holds the name as sbx does it.
    dir=sandboxes-$name
    [ "$name" != default ] || dir=sandboxes
    dir=${STUB_SOCKET_DIR:-$dir}
    # STUB_STOPPED holds the instances whose daemon does not run.
    case " ${STUB_STOPPED:-} " in
      *" $name "*)
        echo "  Status:  stopped"
        echo "  Socket:  /stub/.sbx/${STUB_SOCKET_DIR:-run_$name}/d/sandboxd.sock (not connected)"
        ;;
      *)
        echo "  Status:  ● running"
        echo "  Socket:  /stub/Application Support/$dir/sandboxd/sandboxd.sock"
        echo "  Logs:    /stub/Application Support/$dir/sandboxd/daemon.log"
        ;;
    esac
    # STUB_STATUS_MORE=1: the answer has a second Status line, for a part of the daemon that does not run.
    [ -z "${STUB_STATUS_MORE:-}" ] || echo "  Status:  stopped (kit registry)"
    ;;
esac
exit 0
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
# in_order <a> <b>: the first call that holds <a> comes before the first call that holds <b>.
in_order() {
  local a b
  a=$(grep -nF -- "$1" "$calls" | head -1 | cut -d: -f1) || true
  b=$(grep -nF -- "$2" "$calls" | head -1 | cut -d: -f1) || true
  [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]
}
# label_call <name>: the arguments of the call that sets the label of an instance.
label_call() {
  echo "<--no-input> <secret> <set-custom> <--host> <sbx-instance.invalid> <--env> <SBX_INSTANCE> <--placeholder> <$1> <--value> <$1>"
}
said() { grep -qF -- "$1" "$out" "$err"; }
not_said() { ! said "$1"; }
rc_is() { [ "$rc" -eq "$1" ]; }
out_is() { [ "$(cat "$out")" = "$1" ]; }
no_calls() { [ ! -s "$calls" ]; }
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

# typed <text>: writes the text as a person does, with a wait before it and before the end of the input. When the
# text and the end come at once, script gives the end of the input to the terminal first.
typed() {
  sleep 1
  printf '%s' "$1"
  sleep 1
}

# run_typed <folder> <text> [VAR=value]... -- <command> [argument...]: as run, but stdin is a terminal (from script)
# that gets the text. The terminal takes stdout and stderr, so both are in $out.
run_typed() {
  local dir=$1 text=$2
  local envs=("HOME=$home" "XDG_CONFIG_HOME=$home/.config" "PATH=$path" "STUB_LOG=$calls" "STUB_STATE=$state")
  shift 2
  while [ "$1" != -- ]; do
    envs+=("$1")
    shift
  done
  shift
  : >"$calls"
  : >"$err"
  rc=0
  typed "$text" | (cd "$dir" && exec env -i "${envs[@]}" script -q /dev/null "$@") >"$out" 2>&1 || rc=$?
}
