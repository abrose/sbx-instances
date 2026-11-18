# shellcheck shell=bash
# "sbx-instance check": proves the setup, with one line for each test. It asks sbx and changes nothing. A daemon
# that did not run before the check is stopped again. bin/sbx-instance sources this file.

check_failed=0
check_jq=1
check_pass() { echo "PASS $1"; }
# check_fail <line> [advice...]: the FAIL line, and each advice in an own line below it.
check_fail() {
  echo "FAIL $1"
  shift
  [ $# -eq 0 ] || printf '     %s\n' "$@"
  check_failed=1
}

# check_instance <name>: the tests of one instance on the list.
check_instance() {
  local name=$1 status socket rows
  if ! si_valid "$name"; then
    check_fail "$name: is an instance name (small letters, digits and dashes). Correct the list $(si_list_file)"
    return 0
  fi
  if ! status=$(in_instance "$name" --no-input daemon status 2>&1); then
    check_fail "$name: sbx daemon status answers. sbx says: $status"
    return 0
  fi
  if [ "$name" != default ]; then
    socket=$(grep -E '^ *Socket:' <<<"$status" || true)
    case "$socket" in
      *"/run_$name/"* | *"/sandboxes-$name/"*)
        check_pass "$name: the socket path holds the name, so --app-name separates the instances"
        ;;
      *)
        # The hidden argument does not work as before, so each further call could reach another instance.
        check_fail "$name: the socket path holds the name. sbx says: ${socket:-no Socket line}." \
          "Do not use the named instances with this sbx"
        return 0
        ;;
    esac
  fi
  if in_instance "$name" --no-input ls >/dev/null 2>&1; then
    check_pass "$name: signed in to Docker"
    rows=$(in_instance "$name" --no-input policy ls 2>/dev/null) || rows=""
    if grep -q '^default-' <<<"$rows"; then
      check_pass "$name: has a network policy ($(grep -o '^default-[^ ]*' <<<"$rows" | head -1))"
    else
      check_fail "$name: has a network policy. Run: sbx-instance add $name"
    fi
    check_label "$name"
  else
    check_fail "$name: signed in to Docker (sbx ls fails in it). Run: sbx-instance run $name -- login" \
      "If '$name' is a typing error in the list $(si_list_file), correct the list"
    echo "SKIP $name: the network policy, as the instance is not signed in"
    echo "SKIP $name: the label, as the instance is not signed in"
  fi
  if si_daemon_stopped "$status"; then
    # A sandbox that a person started during the check keeps its daemon.
    if si_sandbox_runs "$(in_instance "$name" --no-input ls --json 2>/dev/null)"; then
      echo "NOTE $name: the daemon stays running: it did not run before the check, but a sandbox runs in it now"
    else
      in_instance "$name" --no-input daemon stop >/dev/null 2>&1 || true
    fi
  fi
}

# check_label <name>: the test of the label of an instance that is signed in.
check_label() {
  local name=$1 label
  if [ "$check_jq" -eq 0 ]; then
    echo "SKIP $name: the label, as jq is not in PATH"
    return 0
  fi
  # The check asks for the row of the label only, so it prints no other row of the secret store.
  label=$(in_instance "$name" --no-input secret ls -g --env-name "$SI_LABEL_VAR" --json 2>/dev/null |
    jq -r --arg var "$SI_LABEL_VAR" \
      '[.custom_secrets[]? | select(.env == $var and .scope == "global") | .placeholder] | join(" ")' \
      2>/dev/null) || label=""
  if [ "$label" = "$name" ]; then
    check_pass "$name: labels its sandboxes ($SI_LABEL_VAR=$name)"
  elif [ -n "$label" ]; then
    check_fail "$name: labels its sandboxes. Run: sbx-instance add $name (the label says '$label')"
  else
    check_fail "$name: labels its sandboxes. Run: sbx-instance add $name"
  fi
}

cmd_check() {
  local first real name names
  [ $# -eq 0 ] || usage
  first=$(type -P sbx) || first=""
  if si_wrapper_first; then
    check_pass "the wrapper is the first sbx in PATH ($first)"
  else
    check_fail "the wrapper is the first sbx in PATH: the first one is ${first:-none}." \
      "Put the folder with the link to $SI_ROOT/bin/sbx before it in PATH"
  fi
  if command -v jq >/dev/null 2>&1; then
    check_pass "jq is in PATH ($(command -v jq))"
  else
    check_jq=0
    check_fail "jq is in PATH: the check needs it for the label, and the wizard for the settings. Install jq"
  fi
  if real=$(si_real_sbx); then
    check_pass "a real sbx is in PATH ($real)"
  else
    check_fail "a real sbx is in PATH"
    echo "SKIP the instances, as there is no sbx to ask"
    return 1
  fi
  names=$(si_names)
  [ -n "$names" ] || echo "the list $(si_list_file) is empty: no instance to test. Add one: sbx-instance add"
  for name in $names; do
    check_instance "$name"
  done
  [ "$check_failed" -eq 0 ]
}
