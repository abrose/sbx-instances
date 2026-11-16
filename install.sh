#!/usr/bin/env bash
# Links the wrapper sbx and the tool sbx-instance into a folder of PATH, then runs "sbx-instance check".
# The folder is ~/.local/bin, or SBX_INSTANCES_BIN. To remove the tool, delete the two links.
set -euo pipefail

root=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
bin=${SBX_INSTANCES_BIN:-$HOME/.local/bin}

for name in sbx sbx-instance; do
  link=$bin/$name
  if [ -L "$link" ] && [ "$(readlink "$link")" = "$root/bin/$name" ]; then
    continue
  fi
  if [ -e "$link" ] || [ -L "$link" ]; then
    echo "install.sh: $link exists and is not a link of this install. Nothing is changed." \
      "Remove it, or set SBX_INSTANCES_BIN to another folder of PATH" >&2
    exit 1
  fi
done
mkdir -p "$bin"
for name in sbx sbx-instance; do
  [ -L "$bin/$name" ] || ln -s "$root/bin/$name" "$bin/$name"
done

cat <<EOF
The links are in $bin.
From now on, a plain sbx in a folder with no .sbx-instance file refuses. A folder gets its instance from the
nearest .sbx-instance file. For the sandboxes that exist in the instance of sbx itself: sbx-instance add default
EOF
"$bin/sbx-instance" check
