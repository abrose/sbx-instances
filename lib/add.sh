# shellcheck shell=bash
# The wizard "sbx-instance add": it asks, shows one summary, and acts only after a yes. Each step that is done
# already is left as it is, so a second run repairs an instance. bin/sbx-instance sources this file.

add_usage() {
  cat >&2 <<'EOF'
usage: sbx-instance add [<name>] [--policy deny-all|balanced|allow-all] [--settings-from <name>|none]
                        [--folder <folder>]... [--yes]
The wizard asks for each answer that no option gives. With no terminal, each answer needs its option;
no --folder then means no folder.
EOF
  exit 2
}

# add_stop <status> <line>...: prints the message and stops the wizard.
add_stop() {
  local status=$1
  shift
  si_refuse "$@"
  exit "$status"
}

# add_ask <question> <proposal>: prints the answer of the person. Enter gives the proposal.
add_ask() {
  local answer
  printf '%s' "$1" >&2
  [ -z "$2" ] || printf ' [%s]' "$2" >&2
  printf ': ' >&2
  IFS= read -r answer || add_stop 1 "no answer: nothing is changed."
  answer=$(si_trim "$answer")
  printf '%s\n' "${answer:-$2}"
}

# add_needs_terminal <option>: stops when there is no terminal to ask on.
add_needs_terminal() {
  [ -t 0 ] || add_stop 2 "no terminal to ask on: give $1. Nothing is changed."
}

# add_folder <folder>: prints the physical path of a folder that can select an instance.
add_folder() {
  local folder=$1 dir home
  # shellcheck disable=SC2088  # a tilde in the text of the person, not a path of the shell
  case "$folder" in
    "~") folder=$HOME ;;
    "~/"*) folder=$HOME/${folder#"~/"} ;;
  esac
  dir=$(cd -P "$folder" 2>/dev/null && pwd) || add_stop 2 "'$1' is no folder. Nothing is changed."
  home=$(cd -P "${HOME:-/nonexistent}" 2>/dev/null && pwd) || add_stop 2 "there is no home folder. Nothing is changed."
  case "$dir/" in
    "${home%/}/"*) ;;
    *) add_stop 2 "the folder $dir is not below the home folder $home: a marker file there does not count." ;;
  esac
  printf '%s\n' "$dir"
}

# add_value <settings as JSON> <key>: prints the value of the key as the argument of "settings set".
add_value() {
  jq -r --arg key "$2" '.[] | select(.key == $key) | .value | if type == "string" then . else tojson end' <<<"$1"
}

cmd_add() {
  local name="" policy="" source="" yes=0 item dir file found above answer out key value restart=0
  local folders=() dirs=() notes=() overrides="[]" keys="" target may_restart=1 question other

  while [ $# -gt 0 ]; do
    case "$1" in
      --policy | --settings-from | --folder)
        [ $# -ge 2 ] || add_usage
        case "$1" in
          --policy) policy=$2 ;;
          --settings-from) source=$2 ;;
          --folder) folders+=("$2") ;;
        esac
        shift 2
        ;;
      --yes)
        yes=1
        shift
        ;;
      -*) add_usage ;;
      *)
        [ -z "$name" ] || add_usage
        name=$1
        shift
        ;;
    esac
  done

  # The answers. Nothing changes and no sbx runs in the new instance before the yes.
  if [ -z "$name" ]; then
    add_needs_terminal "the name of the instance"
    name=$(add_ask "The name of the instance" "")
  fi
  si_valid "$name" ||
    add_stop 2 "'$name' is no instance name: small letters, digits and dashes, at most 31 characters." \
      "Nothing is changed."

  if [ -z "$policy" ]; then
    add_needs_terminal "--policy"
    policy=$(add_ask "The network policy of a new instance (deny-all, balanced, allow-all)" deny-all)
  fi
  case "$policy" in
    deny-all | balanced | allow-all) ;;
    *) add_stop 2 "'$policy' is no network policy: deny-all, balanced or allow-all. Nothing is changed." ;;
  esac

  if [ -z "$source" ]; then
    add_needs_terminal "--settings-from"
    item=none
    if [ "$name" != default ] && si_listed default; then
      item=default
    fi
    source=$(add_ask "Copy the changed sbx settings from which instance (a name on the list, or none)" "$item")
  fi
  if [ "$source" != none ]; then
    if [ "$source" = "$name" ] || ! si_listed "$source"; then
      add_stop 2 "--settings-from '$source': the source is another instance on the list, or none." \
        "Nothing is changed."
    fi
  fi

  if [ ${#folders[@]} -eq 0 ] && [ -t 0 ]; then
    question="A folder that selects the instance (Enter: no folder)"
    while true; do
      item=$(add_ask "$question" "")
      [ -n "$item" ] || break
      folders+=("$item")
      question="One more folder that selects the instance (Enter: no more)"
    done
  fi
  for item in ${folders[@]+"${folders[@]}"}; do
    dir=$(add_folder "$item")
    for other in ${dirs[@]+"${dirs[@]}"}; do
      if [ "$other" = "$dir" ]; then
        echo "the folder $dir is given two times: it counts one time" >&2
        continue 2
      fi
    done
    file=$dir/$SI_MARKER
    if [ -e "$file" ] || [ -L "$file" ]; then
      found=$(si_marker_name "$file") || found=""
      [ "$found" = "$name" ] ||
        add_stop 1 "the marker file $file names another instance ('$found'). Nothing is changed." \
          "The wizard does not change such a file. Remove the file or name another folder."
      notes+=("$file (names '$name' already)")
    elif above=$(cd "$dir/.." && si_marker) && found=$(si_marker_name "$above") && [ "$found" != "$name" ]; then
      notes+=("$file (new; for this folder it overrides $above, which names '$found')")
    else
      notes+=("$file (new)")
    fi
    dirs+=("$dir")
  done

  si_real_sbx >/dev/null || add_stop 127 "no sbx in PATH but the wrapper. Nothing is changed."
  if [ "$source" != none ]; then
    overrides=$(in_instance "$source" --no-input settings ls --json 2>/dev/null |
      jq -c '[.[] | select(.source == "override") | {key, value}]' 2>/dev/null) ||
      add_stop 1 "cannot read the sbx settings of the instance '$source'. Nothing is changed." \
        "Look at: sbx-instance run $source -- settings ls"
    keys=$(jq -r '.[].key' <<<"$overrides")
  fi

  # The daemon of an instance that can have sandboxes in use is not restarted: the instance of sbx itself, and an
  # instance that was on the list before this run.
  if [ "$name" = default ] || si_listed "$name"; then
    may_restart=0
  fi

  echo "The setup of the sbx instance '$name':"
  if si_listed "$name"; then
    echo "  list:            '$name' is on the list already"
  else
    echo "  list:            add '$name' to $(si_list_file)"
  fi
  echo "  Docker sign-in:  when the instance is not signed in, sbx login runs in this terminal"
  echo "  network policy:  $policy, when the instance has none"
  echo "  label:           $SI_LABEL_VAR=$name in each new sandbox of the instance (a custom secret that is no secret)"
  if [ "$source" = none ]; then
    echo "  settings:        no copy"
  else
    echo "  settings:        each of these settings of '$source', when it differs in '$name':"
    for key in $keys; do
      echo "                     $key = $(add_value "$overrides" "$key")"
    done
    if [ "$may_restart" -eq 1 ]; then
      echo "                   the daemon of '$name' restarts when a changed setting needs it"
    else
      echo "                   no restart of the daemon of '$name', as it can have sandboxes in use:"
      echo "                   when a changed setting needs a restart, the wizard prints the command"
    fi
  fi
  if [ ${#notes[@]} -eq 0 ]; then
    echo "  marker files:    none"
  else
    echo "  marker files:"
    printf '                     %s\n' "${notes[@]}"
  fi
  if [ "$yes" -eq 0 ]; then
    add_needs_terminal "--yes"
    answer=$(add_ask "Go on? (y or n)" n)
    case "$answer" in
      y | Y | yes) ;;
      *)
        echo "nothing is changed"
        return 1
        ;;
    esac
  fi

  # 1. The list.
  if si_listed "$name"; then
    echo "list: '$name' is on the list already"
  else
    file=$(si_list_file)
    mkdir -p "$(dirname "$file")"
    [ ! -s "$file" ] || [ -z "$(tail -c 1 "$file")" ] || echo >>"$file"
    echo "$name" >>"$file"
    echo "list: added '$name'"
  fi

  # 2. The Docker sign-in. sbx ls works only in an instance that is signed in.
  if in_instance "$name" --no-input ls >/dev/null 2>&1; then
    echo "Docker sign-in: signed in already"
  else
    [ -t 0 ] ||
      add_stop 1 "the instance '$name' is not signed in to Docker, and there is no terminal for the sign-in." \
        "Sign in on a terminal, then run the wizard again:" \
        "sbx-instance run $name -- login"
    echo "Docker sign-in: sbx login runs now, for the instance '$name'"
    in_instance "$name" login || true
    in_instance "$name" --no-input ls >/dev/null 2>&1 ||
      add_stop 1 "the instance '$name' is not signed in to Docker (sbx ls fails in it)." \
        "Sign in by hand, then run the wizard again:" \
        "sbx-instance run $name -- login"
    echo "Docker sign-in: done"
  fi

  # 3. The network policy. sbx refuses a second init and changes nothing then.
  if out=$(in_instance "$name" --no-input policy init "$policy" 2>&1); then
    echo "network policy: $policy"
  else
    case "$out" in
      *"already initialized"*)
        echo "network policy: the instance has a network policy already; it stays (see: sbx policy ls)"
        ;;
      *) add_stop 1 "sbx policy init $policy fails in the instance '$name':" "$out" ;;
    esac
  fi

  # 4. The label. sbx creates or updates the custom secret, so a later run gives the same result.
  out=$(in_instance "$name" --no-input secret set-custom --host "$SI_LABEL_HOST" --env "$SI_LABEL_VAR" \
    --placeholder "$name" --value "$name" 2>&1) ||
    add_stop 1 "cannot set the label of the instance '$name':" "$out"
  echo "label: $SI_LABEL_VAR=$name in each new sandbox of the instance"

  # 5. The settings.
  if [ "$source" != none ]; then
    target=$(in_instance "$name" --no-input settings ls --json 2>/dev/null |
      jq -c '[.[] | {key, value}]' 2>/dev/null) ||
      add_stop 1 "cannot read the sbx settings of the instance '$name'."
    for key in $keys; do
      value=$(add_value "$overrides" "$key")
      if [ "$value" = "$(add_value "$target" "$key")" ]; then
        echo "settings: $key is equal already"
        continue
      fi
      out=$(in_instance "$name" --no-input settings set "$key" "$value" 2>&1) ||
        add_stop 1 "sbx settings set $key fails in the instance '$name':" "$out"
      echo "settings: $key = $value"
      case "$out" in *"daemon restart"*) restart=1 ;; esac
    done
    if [ "$restart" -eq 1 ] && [ "$may_restart" -eq 1 ]; then
      in_instance "$name" --no-input daemon restart >/dev/null ||
        add_stop 1 "the restart of the daemon fails. Run: sbx-instance run $name -- daemon restart"
      echo "settings: restarted the daemon of '$name', as a changed setting needs it"
    elif [ "$restart" -eq 1 ]; then
      echo "settings: a changed setting takes effect only after a restart of the daemon of '$name'."
      echo "    A restart can stop the work in its sandboxes. Run it when no sandbox is in use:"
      echo "    sbx-instance run $name -- daemon restart"
    fi
  fi

  # 6. The marker files.
  for dir in ${dirs[@]+"${dirs[@]}"}; do
    file=$dir/$SI_MARKER
    if [ -e "$file" ]; then
      echo "marker file: $file names '$name' already"
    else
      printf '%s\n' "$name" >"$file"
      echo "marker file: wrote $file"
    fi
  done
  if [ ${#dirs[@]} -eq 0 ]; then
    echo "marker file: none written. A marker file has the name $SI_MARKER and holds one line:"
    echo "    $name"
    echo "  sbx in the folder of the file, and in each folder below it, runs in the instance '$name'."
  fi

  # 7. What is left for the person.
  cat <<EOF

The instance '$name' is set up. What is left for you:
  1. Load the base image into the instance. In the repo sbx-stack-base:
       bash build.sh --load
  2. Create the first sandbox, in a folder with a marker file for '$name':
       sbx env create --name <sandbox> <project file>
  3. Sign in to Claude in that sandbox. One login holds for all sandboxes of the instance:
       /login
EOF
}
