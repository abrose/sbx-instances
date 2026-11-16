# shellcheck shell=bash
# The shared code of the wrapper sbx and of the tool sbx-instance: the list of the instances, the marker files, the
# real sbx. The caller sets SI_ROOT to the resolved root of the repo first. No function here changes a file.

SI_MARKER=.sbx-instance

# si_trim <text>: prints the text with no space, tab or line end around it.
si_trim() {
  local text=$1
  text=${text#"${text%%[![:space:]]*}"}
  text=${text%"${text##*[![:space:]]}"}
  printf '%s' "$text"
}

# si_resolve <path>: prints the path with its folder and each link resolved. The file itself need not exist.
si_resolve() {
  local path=$1 dir target
  while [ -L "$path" ]; do
    dir=$(cd -P "$(dirname "$path")" 2>/dev/null && pwd) || return 1
    target=$(readlink "$path")
    case "$target" in
      /*) path=$target ;;
      *) path=$dir/$target ;;
    esac
  done
  dir=$(cd -P "$(dirname "$path")" 2>/dev/null && pwd) || return 1
  printf '%s/%s\n' "${dir%/}" "$(basename "$path")"
}

# si_list_file: prints the path of the list of the instances.
si_list_file() {
  printf '%s\n' "${XDG_CONFIG_HOME:-${HOME:-}/.config}/sbx-instances/instances"
}

# si_names: prints the names on the list, one in each line. Empty lines and lines that start with # do not count.
si_names() {
  local file line
  file=$(si_list_file)
  [ -f "$file" ] && [ -r "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line=$(si_trim "$line")
    case "$line" in
      "" | "#"*) ;;
      *) printf '%s\n' "$line" ;;
    esac
  done <"$file"
}

# si_valid <name>: true when the text is an instance name.
si_valid() {
  local pattern='^[a-z0-9][a-z0-9-]{0,30}$'
  [[ $1 =~ $pattern ]]
}

# si_listed <name>: true when the name is on the list.
si_listed() {
  local name
  while IFS= read -r name; do
    [ "$name" != "$1" ] || return 0
  done < <(si_names)
  return 1
}

# si_real_sbx: prints the path of the first sbx in PATH that is not the wrapper of this repo.
si_real_sbx() {
  local dir candidate rest=${PATH:-}:
  while [ -n "$rest" ]; do
    dir=${rest%%:*}
    rest=${rest#*:}
    candidate=$dir/sbx
    [ -n "$dir" ] && [ -f "$candidate" ] && [ -x "$candidate" ] || continue
    [ "$(si_resolve "$candidate")" != "$SI_ROOT/bin/sbx" ] || continue
    printf '%s\n' "$candidate"
    return 0
  done
  return 1
}

# si_marker: prints the path of the nearest marker file, from the physical working folder upward, up to and with
# the physical home folder. A working folder outside the home folder has no marker file.
si_marker() {
  local dir home
  [ -n "${HOME:-}" ] || return 1
  home=$(cd -P "$HOME" 2>/dev/null && pwd) || return 1
  dir=$(pwd -P 2>/dev/null) || return 1
  case "$dir/" in
    "${home%/}/"*) ;;
    *) return 1 ;;
  esac
  while true; do
    if [ -e "$dir/$SI_MARKER" ] || [ -L "$dir/$SI_MARKER" ]; then
      printf '%s\n' "${dir%/}/$SI_MARKER"
      return 0
    fi
    [ "$dir" != "$home" ] || return 1
    dir=$(dirname "$dir")
  done
}

# si_marker_name <file>: prints the first line of the file that is not empty, with no space around it.
si_marker_name() {
  local line
  [ -f "$1" ] && [ -r "$1" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    line=$(si_trim "$line")
    [ -n "$line" ] || continue
    printf '%s\n' "$line"
    return 0
  done <"$1"
  return 1
}

# si_hidden_arg <argument>...: true when an argument before the first -- is the hidden argument of sbx.
si_hidden_arg() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      --) return 1 ;;
      --app-name | --app-name=*) return 0 ;;
    esac
  done
  return 1
}

# si_run <name> [argument...]: replaces this shell with the real sbx in the instance.
si_run() {
  local name=$1 real
  shift
  real=$(si_real_sbx) || {
    echo "sbx-instances: no sbx in PATH but this wrapper. Install sbx, or put its folder into PATH" >&2
    exit 127
  }
  [ "$name" != default ] || exec "$real" "$@"
  exec "$real" --app-name "$name" "$@"
}

# si_refuse <line>...: prints the message of a refusal.
si_refuse() {
  printf 'sbx-instances: %s\n' "$1" >&2
  shift
  [ $# -eq 0 ] || printf '  %s\n' "$@" >&2
}

# si_select: finds the instance of the working folder. Sets SI_NAME and SI_SOURCE (the marker file). When no
# instance is selected, it prints the message of the refusal and returns 64. Call it in this shell, not in $(...).
si_select() {
  local here
  local ways=("Nothing ran. To select an instance:"
    "- put its name into a $SI_MARKER file in this folder or in a folder above it, or"
    "- run one command in a named instance: sbx-instance run <name> -- <sbx arguments>, or"
    "- set up an instance and its folders: sbx-instance add")
  SI_NAME=""
  SI_SOURCE=""
  here=$(pwd -P 2>/dev/null) || here="(a folder that does not exist any more)"
  if ! SI_SOURCE=$(si_marker); then
    si_refuse "no instance for the folder $here: no $SI_MARKER file in it or above it, up to the home folder." \
      "${ways[@]}"
    return 64
  fi
  if ! SI_NAME=$(si_marker_name "$SI_SOURCE") || ! si_valid "$SI_NAME"; then
    si_refuse "the marker file $SI_SOURCE holds no instance name: its first line must be one name." "${ways[@]}"
    return 64
  fi
  if ! si_listed "$SI_NAME"; then
    si_refuse "the marker file $SI_SOURCE names the instance '$SI_NAME'." \
      "The list $(si_list_file) does not hold this name." \
      "${ways[@]}"
    return 64
  fi
}

# si_refuse_hidden: prints the message for a call that holds the hidden argument of sbx.
si_refuse_hidden() {
  si_refuse "the argument --app-name is not allowed here: the folder or sbx-instance run names the instance." \
    "Nothing ran." \
    "For one command in a named instance: sbx-instance run <name> -- <sbx arguments>" \
    "For a command in a sandbox that has an argument of this name, put -- before the command:" \
    "sbx exec <sandbox> -- <command> --app-name x"
}

# si_refuse_unlisted <name>: prints the message for a name that is not on the list.
si_refuse_unlisted() {
  si_refuse "the instance '$1' is not on the list $(si_list_file). Nothing ran." \
    "The names on the list: sbx-instance list" \
    "To set up an instance: sbx-instance add"
}
