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
    install -m 755 "$binary" "$bindir/$APP_ID"
    install -m 644 assets/icon.svg "$icondir/$APP_ID.svg"
    desktop_entry > "$appdir/$APP_ID.desktop.tmp"
    chmod 644 "$appdir/$APP_ID.desktop.tmp"
    mv "$appdir/$APP_ID.desktop.tmp" "$appdir/$APP_ID.desktop"
    refresh_launcher
    echo "Installed $APP_ID $version:"
    echo "  $bindir/$APP_ID"
    echo "  $appdir/$APP_ID.desktop"
    echo "  $icondir/$APP_ID.svg"
    case ":$PATH:" in *":$bindir:"*) ;; *) echo "Note: $bindir is not on PATH in this shell." ;; esac
    echo "Keybinding and window rule: docs/guides/omarchy.md" ;;
esac
