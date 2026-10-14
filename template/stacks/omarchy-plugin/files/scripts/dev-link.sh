#!/usr/bin/env bash
# Develop the plugin in place: link this checkout into Omarchy's plugin folder
# and put the widget in the bar.
#
#   ./scripts/dev-link.sh            # link, rescan, enable (right side of the bar)
#   ./scripts/dev-link.sh --reload   # rescan after an edit (a link doesn't reload on save)
#   ./scripts/dev-link.sh --unlink   # disable it and remove the link
set -euo pipefail
case "${1:-}" in -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
CDPATH='' cd -- "$(dirname -- "$0")/.."   # a CDPATH entry must not pick the directory
id="$(jq -r .id manifest.json)"
dest="$HOME/.config/omarchy/plugins/$id"
case "${1:-}" in
  "")
    command -v omarchy >/dev/null 2>&1 || { echo "dev-link.sh: omarchy not found; this needs an Omarchy 4 desktop" >&2; exit 1; }
    if [ "$dest" -ef "$PWD" ]; then
      :  # already linked, or cloned straight into the plugin folder
    elif [ -e "$dest" ] && [ ! -L "$dest" ]; then
      echo "dev-link.sh: $dest exists and is not a link; move it aside first ('omarchy plugin remove' deletes it)" >&2
      exit 1
    else
      mkdir -p "$(dirname "$dest")"
      ln -sfn "$PWD" "$dest"
    fi
    omarchy-shell shell rescanPlugins
    # The rescan finishes in the background: wait until Omarchy lists the plugin,
    # as `omarchy plugin add` does, or enabling it fails.
    found=0
    for (( attempt = 0; attempt < 40; attempt++ )); do
      if omarchy plugin list --json | jq -e --arg id "$id" 'any(.[]; .id == $id)' >/dev/null; then
        found=1
        break
      fi
      sleep 0.05
    done
    [ "$found" = 1 ] || { echo "dev-link.sh: Omarchy doesn't list $id after a rescan (omarchy plugin list)" >&2; exit 1; }
    omarchy plugin enable "$id" --section right
    echo "Linked $dest -> $PWD and enabled $id." ;;
  --reload) omarchy-shell shell rescanPlugins ;;
  --unlink)
    # --yes skips Omarchy's prompt, and its remove deletes a cloned plugin
    # outright, so only ever remove this checkout's own link.
    if [ ! -L "$dest" ] || [ ! "$dest" -ef "$PWD" ]; then
      echo "dev-link.sh: $dest is not a link to this checkout" >&2
      exit 1
    fi
    omarchy plugin remove "$id" --yes ;;
  *) echo "dev-link.sh: unknown argument: $1" >&2; exit 2 ;;
esac
