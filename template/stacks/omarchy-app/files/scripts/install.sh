#!/usr/bin/env bash
# Install {{PROJECT_NAME}} for this user: the release binary, a desktop entry and
# an icon, so it shows up in the Omarchy launcher. No root needed.
#
#   ./scripts/install.sh                        # build, then install under ~/.local
#   ./scripts/install.sh --no-build             # install the binary cargo already built
#   ./scripts/install.sh --uninstall            # remove exactly what install put there
#   ./scripts/install.sh --print-desktop-entry  # print the entry install would write
#   sudo PREFIX=/usr/local ./scripts/install.sh --no-build  # system-wide, after a build
set -euo pipefail

APP_ID="{{PACKAGE_NAME}}"
# PREFIX is the one setting. Generic names such as APPDIR, which every AppImage
# exports to its children, are never read from the environment.
PREFIX="${PREFIX:-$HOME/.local}"

mode=install
build=1
for arg in "$@"; do
  case "$arg" in
    --no-build) build=0 ;;
    --uninstall) mode=uninstall ;;
    --print-desktop-entry) mode=print ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "install.sh: unknown argument: $arg" >&2; exit 2 ;;
  esac
done
# After --help, which reads this script by its path. A CDPATH entry must not pick the directory.
CDPATH='' cd -- "$(dirname -- "$0")/.."

# A relative PREFIX would resolve against this project, not the caller's
# directory, and write a relative Exec=.
case "$PREFIX" in
  /*) ;;
  *) echo "install.sh: PREFIX must be an absolute path: $PREFIX" >&2; exit 2 ;;
esac
# Exec quotes the binary's path; these characters would need escaping there
# (desktop entry spec), so refuse them rather than write a broken entry.
case "$PREFIX" in
  *[\"\`\$\\%]*|*$'\n'*) echo "install.sh: unsupported character in PREFIX: $PREFIX" >&2; exit 2 ;;
esac
bindir="$PREFIX/bin"
appdir="$PREFIX/share/applications"
icondir="$PREFIX/share/icons/hicolor/scalable/apps"
version="$(head -n 1 VERSION)"

desktop_entry() {
  BINDIR="$bindir" VERSION="$version" perl -pe \
    's/\@BINDIR\@/$ENV{BINDIR}/g; s/\@VERSION\@/$ENV{VERSION}/g' packaging/app.desktop.in
}

refresh_launcher() {
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$appdir" 2>/dev/null || true
  fi
}

# Compare Exec bytes literally: awk -v would interpret template backslashes.
owned_entry() {
  local entry="$1" expected_exec
  expected_exec="$(desktop_entry | sed -n '/^Exec=/p')"
  [ -f "$entry" ] && [ ! -L "$entry" ] && [ -r "$entry" ] && [ -n "$expected_exec" ] \
    && VIBE_INSTALL_EXPECTED_EXEC="$expected_exec" awk -v id="$APP_ID" '
      /^\[/ { active = ($0 == "[Desktop Entry]"); if (active) groups++ }
      active && /^X-Vibe-Starter-AppId=/ { markers++; if ($0 == "X-Vibe-Starter-AppId=" id) marker_ok++ }
      active && /^Exec=/ { commands++; if ($0 == ENVIRON["VIBE_INSTALL_EXPECTED_EXEC"]) command_ok++ }
      END { exit !(groups == 1 && markers == 1 && marker_ok == 1 && commands == 1 && command_ok == 1) }
    ' "$entry"
}

# A marked entry with this launch command owns the three installed files.
# Check before building or touching any destination; names alone prove nothing.
# Versions may differ during an upgrade, and missing owned companions may be
# restored or removed. Never follow a destination symlink or replace a directory.
check_ownership() {
  local path present=0 entry="$appdir/$APP_ID.desktop"
  for path in "$bindir/$APP_ID" "$entry" "$icondir/$APP_ID.svg"; do
    if [ -e "$path" ] || [ -L "$path" ]; then
      present=1
      if [ ! -f "$path" ] || [ -L "$path" ]; then
        echo "install.sh: refusing to replace or remove $path: not a regular, non-symlink file" >&2
        return 1
      fi
    fi
  done
  [ "$present" = 1 ] || return 0
  if owned_entry "$entry"; then
    return 0
  fi
  echo "install.sh: refusing to replace or remove existing files: no valid ownership entry at $entry; move unrelated files aside first" >&2
  return 1
}

case "$mode" in install|uninstall) check_ownership || exit 1 ;; esac
case "$mode" in
  print)
    desktop_entry ;;
  uninstall)
    rm -f "$bindir/$APP_ID" "$appdir/$APP_ID.desktop" "$icondir/$APP_ID.svg"
    refresh_launcher
    echo "Removed $APP_ID from $PREFIX." ;;
  install)
    if [ "$build" = 1 ]; then
      # Install the binary cargo reports building: build.target-dir,
      # CARGO_BUILD_TARGET_DIR and build.target all move it, and sudo drops
      # CARGO_TARGET_DIR. Its diagnostics still reach the terminal.
      command -v jq >/dev/null 2>&1 || { echo "install.sh: jq not found; it reads where cargo put the binary" >&2; exit 1; }
      binary="$(cargo build --locked --release --message-format=json-render-diagnostics \
        | jq -r --arg id "$APP_ID" 'select(.reason == "compiler-artifact" and .target.name == $id and .executable != null) | .executable')"
      [ -n "$binary" ] || { echo "install.sh: cargo built no $APP_ID binary" >&2; exit 1; }
    else
      binary="${CARGO_TARGET_DIR:-target}/release/$APP_ID"
    fi
    [ -x "$binary" ] || { echo "install.sh: $binary is missing; build it first" >&2; exit 1; }
    # It must be this app at this VERSION: a build from before the last bump
    # would install under the new version's entry. That is all --no-build can
    # check, so an older build of the same VERSION still gets through; the
    # default path installs exactly what cargo just built.
    reported="$("$binary" --version 2>/dev/null || true)"
    if [ "$reported" != "$APP_ID $version" ]; then
      echo "install.sh: $binary reports '$reported', not '$APP_ID $version': rebuild it" >&2
      exit 1
    fi
    install -d "$bindir" "$appdir" "$icondir"
    # Prepare every artifact before publishing anything. The private directory
    # is beside the entry, so its rename is atomic even with a mounted PREFIX.
    stage="$(mktemp -d "$appdir/.$APP_ID.install.XXXXXX")"
    trap 'rm -rf -- "$stage"' EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    install -m 755 "$binary" "$stage/$APP_ID"
    install -m 644 assets/icon.svg "$stage/$APP_ID.svg"
    desktop_entry > "$stage/$APP_ID.desktop"
    chmod 644 "$stage/$APP_ID.desktop"
    if ! owned_entry "$stage/$APP_ID.desktop"; then
      echo "install.sh: rendered desktop entry is not a valid ownership entry" >&2
      exit 1
    fi
    # Publish ownership first. If a later copy fails or a catchable signal
    # interrupts it, the entry permits either retry or uninstall of the partial
    # install. Never touch the old predictable .desktop.tmp pathname.
    mv "$stage/$APP_ID.desktop" "$appdir/$APP_ID.desktop"
    install -m 755 "$stage/$APP_ID" "$bindir/$APP_ID"
    install -m 644 "$stage/$APP_ID.svg" "$icondir/$APP_ID.svg"
    refresh_launcher
    echo "Installed $APP_ID $version:"
    echo "  $bindir/$APP_ID"
    echo "  $appdir/$APP_ID.desktop"
    echo "  $icondir/$APP_ID.svg"
    case ":$PATH:" in *":$bindir:"*) ;; *) echo "Note: $bindir is not on PATH in this shell." ;; esac
    echo "Keybinding and window rule: docs/guides/omarchy.md" ;;
esac
