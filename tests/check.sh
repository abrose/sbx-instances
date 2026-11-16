#!/usr/bin/env bash
# Unit tests of "sbx-instance check".
set -euo pipefail
# shellcheck source=tests/helpers.sh
. "$(dirname "$0")/helpers.sh"

# setup <name>...: these names are on the list; each instance is signed in and has a network policy.
setup() {
  local name
  fresh
  rm -rf "$state"
  mkdir -p "$state"
  a_list "$@"
  for name in "$@"; do
    echo deny-all >"$state/$name.policy"
  done
}
# check [VAR=value]...: runs the check.
check() { run "$home" "$@" -- sbx-instance check; }
lines() { [ "$(grep -c "^$1 " "$out")" -eq "$2" ]; }
# one_fail <text>: the check failed with one FAIL line, and the line holds the text.
one_fail() { [ "$rc" -eq 1 ] && lines FAIL 1 && grep '^FAIL ' "$out" | grep -qF -- "$1"; }

echo "== a good setup"
setup alpha beta
check
expect "a good setup: status 0" rc_is 0
expect "a good setup: no FAIL line" lines FAIL 0
expect "a good setup: a line for each test" lines PASS 8
expect "a good setup: three questions for each instance, and no change" calls_are \
  "sbx <--app-name> <alpha> <--no-input> <daemon> <status>" \
  "sbx <--app-name> <alpha> <--no-input> <ls>" \
  "sbx <--app-name> <alpha> <--no-input> <policy> <ls>" \
  "sbx <--app-name> <beta> <--no-input> <daemon> <status>" \
  "sbx <--app-name> <beta> <--no-input> <ls>" \
  "sbx <--app-name> <beta> <--no-input> <policy> <ls>"
expect "a good setup: the list is unchanged" list_is "alpha
beta"
run "$home" -- sbx-instance check more
expect "check with an argument: the usage" rc_is 2

echo "== the instance default"
setup default
check
expect "default: status 0" rc_is 0
expect "default: no socket test, so two lines for the instance" lines PASS 4
expect "default: the questions go to sbx with no --app-name" calls_are \
  "sbx <--no-input> <daemon> <status>" \
  "sbx <--no-input> <ls>" \
  "sbx <--no-input> <policy> <ls>"

echo "== an empty list"
setup
check
expect "an empty list: status 0" rc_is 0
expect "an empty list: a line says so" said "is empty"
expect "an empty list: no sbx call" no_calls

echo "== the wrapper and the real sbx"
setup alpha
check "PATH=$real:$wbin:$shell:/usr/bin:/bin"
expect "the real sbx before the wrapper in PATH: one FAIL" one_fail "first sbx in PATH"
run "$home" "PATH=$real:$shell:/usr/bin:/bin" -- "$wbin/sbx-instance" check
expect "no wrapper in PATH: one FAIL" one_fail "first sbx in PATH"
check "PATH=$no_real_path"
expect "no real sbx: one FAIL" one_fail "real sbx"
expect "no real sbx: no call" no_calls

echo "== the hidden argument does not separate the instances any more"
setup alpha
check STUB_SOCKET_DIR=sandboxes
expect "a socket path with no name: one FAIL" one_fail "socket path"
expect "a socket path with no name: no more question in this instance" calls_are \
  "sbx <--app-name> <alpha> <--no-input> <daemon> <status>"
setup alpha
check STUB_SOCKET_DIR=sandboxes-alpha2
expect "a socket path with a longer name: one FAIL" one_fail "socket path"
setup alpha
check STUB_EXIT=1
expect "sbx daemon status fails: one FAIL" one_fail "daemon status"

echo "== the Docker sign-in and the network policy"
setup alpha beta
: >"$state/alpha.signed-out"
check
expect "an instance that is not signed in: one FAIL" one_fail "alpha: signed in"
expect "an instance that is not signed in: the policy is not tested" not_called "<alpha> <--no-input> <policy>"
expect "an instance that is not signed in: the next instance is tested" called "<beta> <--no-input> <policy> <ls>"
setup alpha beta
rm "$state/beta.policy"
check
expect "an instance with no network policy: one FAIL" one_fail "beta: has a network policy"
expect "an instance with no network policy: the check creates none" not_called "<init>"

echo "== the daemons stay as they were"
setup alpha beta
check STUB_STOPPED=alpha
expect "a daemon that was stopped: status 0" rc_is 0
expect "a daemon that was stopped is stopped again" called "sbx <--app-name> <alpha> <--no-input> <daemon> <stop>"
expect "a daemon that ran is not stopped" not_called "<beta> <--no-input> <daemon> <stop>"
setup alpha
check STUB_STOPPED=alpha STUB_SOCKET_DIR=sandboxes
expect "a socket path with no name: nothing is stopped" not_called "<stop>"

finish
