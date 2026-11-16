#!/usr/bin/env bash
# Unit tests of the wizard "sbx-instance add".
set -euo pipefail
# shellcheck source=tests/helpers.sh
. "$(dirname "$0")/helpers.sh"

# setup: no list, no marker file, no state of an instance. Each instance is signed in and has no policy.
setup() {
  fresh
  rm -rf "$state"
  mkdir -p "$state" "$home/none"
}
signed_out() { : >"$state/$1.signed-out"; }
# add [VAR=value]... -- <argument of add>...: runs the wizard with no terminal.
add() {
  local envs=()
  while [ "$1" != -- ]; do
    envs+=("$1")
    shift
  done
  shift
  run "$home/none" ${envs[@]+"${envs[@]}"} -- sbx-instance add "$@"
}
no_list() { [ ! -e "$list" ]; }
# stopped <status>: the wizard stopped with this status before it called sbx or changed the list.
stopped() { [ "$rc" -eq "$1" ] && no_calls && no_list; }
marker_is() { printf '%s\n' "$2" | cmp -s - "$1/.sbx-instance"; }
all=(--policy deny-all --settings-from none --yes)

echo "== a new instance"
setup
signed_out alpha
add -- alpha "${all[@]}"
expect "a new instance: status 0" rc_is 0
expect "a new instance: the name is on the list" list_is alpha
expect "a new instance: the sign-in, then the policy, each in the instance" calls_are \
  "sbx <--app-name> <alpha> <--no-input> <ls>" \
  "sbx <--app-name> <alpha> <login>" \
  "sbx <--app-name> <alpha> <--no-input> <ls>" \
  "sbx <--app-name> <alpha> <--no-input> <policy> <init> <deny-all>"
expect "the steps that are left: the base image" said "build.sh --load"
expect "the steps that are left: the first sandbox" said "sbx env create"
expect "the steps that are left: the Claude login" said "/login"
expect "with no folder, the output shows the marker file" said ".sbx-instance"

echo "== a second run"
add -- alpha --policy balanced --settings-from none --yes
expect "a second run: status 0" rc_is 0
expect "a second run: the name is on the list one time" list_is alpha
expect "a second run: no sign-in" not_called "<login>"
expect "a second run: it says that the instance is on the list" said "on the list already"
expect "a second run: it says that the instance is signed in" said "signed in already"
expect "a second run: it says that the policy stays" said "has a network policy already"
expect "a second run: the policy of the first run stays" [ "$(cat "$state/alpha.policy")" = deny-all ]

echo "== the instance default"
setup
signed_out default
add -- default "${all[@]}"
expect "default: the same steps with no --app-name" calls_are \
  "sbx <--no-input> <ls>" \
  "sbx <login>" \
  "sbx <--no-input> <ls>" \
  "sbx <--no-input> <policy> <init> <deny-all>"
expect "default: the name is on the list" list_is default

echo "== a typing error creates no instance"
setup
add -- Alpha "${all[@]}"
expect "a capital letter in the name: stopped, status 2" stopped 2
add -- a_b "${all[@]}"
expect "an underscore in the name: stopped, status 2" stopped 2
add -- a1234567890123456789012345678901 "${all[@]}"
expect "a name of 32 characters: stopped, status 2" stopped 2
add -- "${all[@]}"
expect "no name and no terminal: stopped, status 2" stopped 2
add -- alpha beta "${all[@]}"
expect "two names: stopped, status 2" stopped 2
add -- alpha --settings-from none --yes
expect "no --policy and no terminal: stopped, status 2" stopped 2
expect "no --policy and no terminal: the message names the option" said "--policy"
add -- alpha --policy open --settings-from none --yes
expect "a policy that sbx does not have: stopped, status 2" stopped 2
add -- alpha --policy deny-all --yes
expect "no --settings-from and no terminal: stopped, status 2" stopped 2
expect "no --settings-from and no terminal: the message names the option" said "--settings-from"
add -- alpha --policy deny-all --settings-from none
expect "no --yes and no terminal: stopped, status 2" stopped 2
expect "no --yes and no terminal: the message names the option" said "--yes"
add -- alpha "${all[@]}" --force
expect "an option that does not exist: stopped, status 2" stopped 2
add -- alpha --policy
expect "an option with no value: stopped, status 2" stopped 2
add "PATH=$no_real_path" -- alpha "${all[@]}"
expect "no real sbx: status 127, the list is unchanged" [ "$rc" -eq 127 ] && expect "no real sbx: no list" no_list

echo "== the sign-in fails"
setup
signed_out alpha
add STUB_LOGIN_FAILS=1 -- alpha "${all[@]}"
expect "a failed sign-in: status 1" rc_is 1
expect "a failed sign-in: the command to run by hand" said "sbx-instance run alpha -- login"
expect "a failed sign-in: no policy" not_called "<policy>"
expect "a failed sign-in: the name stays on the list" list_is alpha

echo "== the policy fails"
setup
a_list beta
add STUB_POLICY_FAILS=1 -- alpha "${all[@]}" --settings-from beta
expect "a failed policy init: status 1" rc_is 1
expect "a failed policy init: the message of sbx" said "daemon fault"
expect "a failed policy init: no settings call in the instance" not_called "<alpha> <--no-input> <settings>"
setup
add STUB_EXIT=3 -- alpha "${all[@]}"
expect "sbx fails at each call: status 1" rc_is 1

echo "== the settings"
settings() {
  setup
  a_list beta
  cat >"$state/beta.settings.json" <<'EOF'
[{"key":"telemetry.disabled","value":true,"source":"override","type":"bool","default":false},
 {"key":"kit.allowedSources","value":["docker.io/","git+https://example.com/"],"source":"override","type":"json"},
 {"key":"browser.enabled","value":true,"source":"default","type":"bool"},
 {"key":"some.text","value":"a b","source":"override","type":"string"}]
EOF
  cat >"$state/alpha.settings.json" <<'EOF'
[{"key":"telemetry.disabled","value":true,"source":"override","type":"bool"},
 {"key":"kit.allowedSources","value":["docker.io/"],"source":"default","type":"json"},
 {"key":"browser.enabled","value":false,"source":"override","type":"bool"},
 {"key":"some.text","value":"x","source":"default","type":"string"}]
EOF
}
settings
add -- alpha --policy deny-all --settings-from beta --yes
expect "settings: status 0" rc_is 0
expect "settings: the first call reads the source instance" \
  [ "$(head -1 "$calls")" = "sbx <--app-name> <beta> <--no-input> <settings> <ls> <--json>" ]
expect "settings: a changed JSON value is one argument" called \
  'sbx <--app-name> <alpha> <--no-input> <settings> <set> <kit.allowedSources> <["docker.io/","git+https://example.com/"]>'
expect "settings: a changed text value is the text" called \
  "sbx <--app-name> <alpha> <--no-input> <settings> <set> <some.text> <a b>"
expect "settings: a value that is equal already is not set" not_called "<set> <telemetry.disabled>"
expect "settings: a value that the source did not change is not set" not_called "<set> <browser.enabled>"
expect "settings: no restart when sbx does not ask for one" not_called "<daemon> <restart>"
expect "settings: the summary lists the keys of the source" said "kit.allowedSources"
expect "settings: the source instance is not changed" not_called "<beta> <--no-input> <settings> <set>"
settings
add "STUB_RESTART=some.text" -- alpha --policy deny-all --settings-from beta --yes
expect "settings: a restart of the daemon when sbx asks for one" called \
  "sbx <--app-name> <alpha> <--no-input> <daemon> <restart>"
settings
add -- alpha "${all[@]}"
expect "settings from none: no settings call" not_called "<settings>"
settings
add -- alpha --policy deny-all --settings-from gamma --yes
expect "settings from a name not on the list: status 2, no call" [ "$rc" -eq 2 ] && expect "and no call" no_calls
add -- beta --policy deny-all --settings-from beta --yes
expect "settings from the instance itself: status 2, no call" [ "$rc" -eq 2 ] && expect "and no call" no_calls
settings
echo "no json" >"$state/beta.settings.json"
add -- alpha --policy deny-all --settings-from beta --yes
expect "settings of the source cannot be read: status 1" rc_is 1
expect "settings of the source cannot be read: no call in the new instance" not_called "<alpha>"
expect "settings of the source cannot be read: the list is unchanged" list_is beta

echo "== the marker files"
setup
mkdir -p "$home/w1" "$home/w2/sub" "$tmp/outside"
ln -s "$home/w2/sub" "$home/link"
add -- alpha "${all[@]}" --folder "$home/w1" --folder "$home/link"
expect "two folders: status 0" rc_is 0
expect "the marker file of the first folder holds the name and a line end" marker_is "$home/w1" alpha
expect "a folder behind a link gets its marker file" marker_is "$home/w2/sub" alpha
add -- alpha "${all[@]}" --folder "$home/w1"
expect "a marker file that names the instance already: status 0" rc_is 0
expect "a marker file that names the instance already stays" marker_is "$home/w1" alpha
setup
mkdir -p "$home/w1"
add -- alpha "${all[@]}" --folder "$home/missing"
expect "a folder that does not exist: stopped, status 2" stopped 2
add -- alpha "${all[@]}" --folder "$tmp/outside"
expect "a folder outside the home folder: stopped, status 2" stopped 2
a_marker "$home/w1" beta
add -- alpha "${all[@]}" --folder "$home/w1"
expect "a marker file that names another instance: stopped, status 1" stopped 1
expect "a marker file that names another instance is unchanged" marker_is "$home/w1" beta
expect "a marker file that names another instance: the message names the file" said "$home/w1/.sbx-instance"
mkdir -p "$home/w1/below"
add -- alpha "${all[@]}" --folder "$home/w1/below"
expect "a marker file above names another instance: the new file is written" marker_is "$home/w1/below" alpha
expect "a marker file above names another instance: the summary says that the new file overrides it" said "overrides"
setup
mkdir -p "$home/w3"
run "$home/w3" -- sbx-instance add alpha "${all[@]}" --folder .
expect "a folder relative to the working folder" marker_is "$home/w3" alpha

echo "== with a terminal"
setup
mkdir -p "$home/t1"
run_typed "$home/none" "alpha
balanced
none
$home/t1

y
" -- sbx-instance add
expect "each answer typed: status 0" rc_is 0
expect "each answer typed: the name is on the list" list_is alpha
expect "each answer typed: the policy" called "sbx <--app-name> <alpha> <--no-input> <policy> <init> <balanced>"
expect "each answer typed: the marker file" marker_is "$home/t1" alpha
setup
a_list default
run_typed "$home/none" "


y
" -- sbx-instance add alpha
expect "Enter takes the proposal deny-all" called "sbx <--app-name> <alpha> <--no-input> <policy> <init> <deny-all>"
expect "Enter takes the proposal default as the source of the settings" called "sbx <--no-input> <settings> <ls> <--json>"
expect "Enter at the folder: no marker file is written" [ ! -e "$home/none/.sbx-instance" ]
setup
run_typed "$home/none" "n
" -- sbx-instance add alpha --policy deny-all --settings-from none
expect "a no at the summary: no sbx call" no_calls
expect "a no at the summary: no list" no_list
expect "a no at the summary: it says that nothing is changed" said "nothing is changed"
setup
run_typed "$home/none" "" -- sbx-instance add alpha --policy deny-all --settings-from none
expect "the end of the input at the summary: no sbx call" no_calls
expect "the end of the input at the summary: no list" no_list

finish
