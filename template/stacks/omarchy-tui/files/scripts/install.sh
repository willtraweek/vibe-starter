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
PREFIX="${PREFIX:-$HOME/.local}"
BINDIR="${BINDIR:-$PREFIX/bin}"
APPDIR="${APPDIR:-$PREFIX/share/applications}"
ICONDIR="${ICONDIR:-$PREFIX/share/icons/hicolor/scalable/apps}"
BINARY="${CARGO_TARGET_DIR:-target}/release/$APP_ID"

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
cd "$(dirname "$0")/.."  # after --help, which reads this script by its path

# Exec quotes the binary's path; these characters would need escaping there
# (desktop entry spec), so refuse them rather than write a broken entry.
case "$BINDIR" in
  *[\"\`\$\\%]*|*$'\n'*) echo "install.sh: unsupported character in BINDIR: $BINDIR" >&2; exit 2 ;;
esac

desktop_entry() {
  BINDIR="$BINDIR" VERSION="$(head -n 1 VERSION)" perl -pe \
    's/\@BINDIR\@/$ENV{BINDIR}/g; s/\@VERSION\@/$ENV{VERSION}/g' packaging/app.desktop.in
}

refresh_launcher() {
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$APPDIR" 2>/dev/null || true
  fi
}

case "$mode" in
  print)
    desktop_entry ;;
  uninstall)
    rm -f "$BINDIR/$APP_ID" "$APPDIR/$APP_ID.desktop" "$ICONDIR/$APP_ID.svg"
    refresh_launcher
    echo "Removed $APP_ID from $PREFIX." ;;
  install)
    if [ "$build" = 1 ]; then cargo build --locked --release; fi
    [ -x "$BINARY" ] || { echo "install.sh: $BINARY is missing; build it first" >&2; exit 1; }
    install -d "$BINDIR" "$APPDIR" "$ICONDIR"
    install -m 755 "$BINARY" "$BINDIR/$APP_ID"
    install -m 644 assets/icon.svg "$ICONDIR/$APP_ID.svg"
    desktop_entry > "$APPDIR/$APP_ID.desktop.tmp"
    chmod 644 "$APPDIR/$APP_ID.desktop.tmp"
    mv "$APPDIR/$APP_ID.desktop.tmp" "$APPDIR/$APP_ID.desktop"
    refresh_launcher
    echo "Installed $APP_ID $(head -n 1 VERSION):"
    echo "  $BINDIR/$APP_ID"
    echo "  $APPDIR/$APP_ID.desktop"
    echo "  $ICONDIR/$APP_ID.svg"
    case ":$PATH:" in *":$BINDIR:"*) ;; *) echo "Note: $BINDIR is not on PATH in this shell." ;; esac
    echo "Keybinding and window rule: docs/guides/omarchy.md" ;;
esac
