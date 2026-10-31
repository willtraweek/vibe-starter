#!/usr/bin/env bash
# The project's pinned tools: Godot and GDScript Formatter, at the versions below.
#
#   ./scripts/godot-kit.sh            install whichever is missing, then say where both are
#   ./scripts/godot-kit.sh godot      print the path of the pinned Godot; installs nothing
#   ./scripts/godot-kit.sh formatter  print the path of the pinned formatter; installs nothing
#
# A copy counts only if it reports the pinned version. They are looked for in this order:
# GODOT_BIN or GDSCRIPT_FORMATTER_BIN (which must then be right), the kit's cache
# (GODOT_KIT_DIR, else ~/.cache/godot-kit), then godot or gdscript-formatter on PATH.
# Installing downloads the official release for this machine from GitHub (or from
# GODOT_KIT_MIRROR, a URL holding the same files), checks it against the sums below, and
# publishes it into the cache with one rename. Needs curl, unzip (or python3) and, once,
# the network. Bump a pin on purpose: the version and all of its sums together, and for
# Godot the "4.7" that starts config/features in project.godot.
set -euo pipefail

GODOT_VERSION=4.7.2-stable
# From the SHA512-SUMS.txt of Godot's release.
GODOT_SHA512_LINUX_X86_64=9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65
GODOT_SHA512_LINUX_ARM64=dd59918da086bd49bde2f5450b5e567ff8650cbde9abbd7b8f4ca1197ff8c609baa38834666d032deafb47099078d7822279e2a0e06e5665745468f26533e7e2
GODOT_SHA512_MACOS=38aa16e5bba2083941fc5b3e54be0089bd4cc35e32415f5b9fd9a8a6a7b9818255d44532ea8ef94b5aef56c4b407c2d634fa4f657e4ebe681ebbf59b7bac69ca
FORMATTER_VERSION=0.27.0
# The SHA-256 digests GitHub records for the formatter's release assets.
FORMATTER_SHA256_LINUX_X86_64=56c8b7566b6ba6eb8738156ca13b2e93c2489b66a15ae6070aea0321d37a5323
FORMATTER_SHA256_LINUX_AARCH64=b400fcf7145715d0868a2b5ef05bb99d86d32395264c0c239c8826ac979ac5b9
FORMATTER_SHA256_MACOS_AARCH64=e7d9fe240d5c5630b8738f6e0616a2473807037b9d10b70a11690ab1a73bc5bc
FORMATTER_SHA256_MACOS_X86_64=0aa9e345b879de2d2211801be83728a44246ff1b75a6e319bfafa672f282b995

kit="${GODOT_KIT_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/godot-kit}"

case "$(uname -s)/$(uname -m)" in
  Linux/x86_64 | Linux/amd64) platform=linux-x86_64 ;;
  Linux/aarch64 | Linux/arm64) platform=linux-aarch64 ;;
  Darwin/arm64) platform=macos-aarch64 ;;
  Darwin/x86_64) platform=macos-x86_64 ;;
  *) platform="" ;;
esac

# Sets asset, binary (inside the unpacked asset), sum, bits and url for tool $1 here.
pick() {
  case "$1/$platform" in
    godot/linux-x86_64)
      asset="Godot_v${GODOT_VERSION}_linux.x86_64.zip" binary="Godot_v${GODOT_VERSION}_linux.x86_64"
      sum=$GODOT_SHA512_LINUX_X86_64 ;;
    godot/linux-aarch64)
      asset="Godot_v${GODOT_VERSION}_linux.arm64.zip" binary="Godot_v${GODOT_VERSION}_linux.arm64"
      sum=$GODOT_SHA512_LINUX_ARM64 ;;
    godot/macos-*)
      asset="Godot_v${GODOT_VERSION}_macos.universal.zip" binary=Godot.app/Contents/MacOS/Godot
      sum=$GODOT_SHA512_MACOS ;;
    formatter/linux-x86_64) sum=$FORMATTER_SHA256_LINUX_X86_64 ;;
    formatter/linux-aarch64) sum=$FORMATTER_SHA256_LINUX_AARCH64 ;;
    formatter/macos-aarch64) sum=$FORMATTER_SHA256_MACOS_AARCH64 ;;
    formatter/macos-x86_64) sum=$FORMATTER_SHA256_MACOS_X86_64 ;;
    *)
      echo "godot-kit: no pinned $1 for $(uname -s) $(uname -m); set $(env_name "$1") to your own copy" >&2
      return 1 ;;
  esac
  case "$1" in
    godot) bits=512 url="https://github.com/godotengine/godot-builds/releases/download/$GODOT_VERSION" ;;
    formatter)
      asset="gdscript-formatter-$FORMATTER_VERSION-$platform.zip" binary="gdscript-formatter-$FORMATTER_VERSION-$platform"
      bits=256 url="https://github.com/GDQuest/GDScript-formatter/releases/download/$FORMATTER_VERSION" ;;
  esac
  url="${GODOT_KIT_MIRROR:-$url}/$asset"
}

env_name() { if [ "$1" = godot ]; then echo GODOT_BIN; else echo GDSCRIPT_FORMATTER_BIN; fi; }
version() { if [ "$1" = godot ]; then echo "Godot $GODOT_VERSION"; else echo "GDScript Formatter $FORMATTER_VERSION"; fi; }
cached() { if [ "$1" = godot ]; then echo "$kit/godot-$GODOT_VERSION-$platform"; else echo "$kit/gdscript-formatter-$FORMATTER_VERSION-$platform"; fi; }

# 0 when binary $2 reports the pinned version of tool $1.
reports() {
  local out
  out="$("$2" --version 2>/dev/null)" || return 1
  case "$1/$out" in
    "godot/${GODOT_VERSION%%-*}.${GODOT_VERSION#*-}."*) return 0 ;;
    "formatter/gdscript-formatter $FORMATTER_VERSION" | "formatter/gdscript-formatter $FORMATTER_VERSION"$'\n'*) return 0 ;;
  esac
  return 1
}

# Prints the path of a copy of tool $1 at the pinned version: 0 found, 1 none, 2 refused.
find_tool() {
  local chosen dir name path
  chosen="$(printenv "$(env_name "$1")" || true)"
  if [ -n "$chosen" ]; then
    reports "$1" "$chosen" && { printf '%s\n' "$chosen"; return 0; }
    echo "godot-kit: $(env_name "$1")=$chosen is not $(version "$1")" >&2
    return 2
  fi
  if [ -n "$platform" ] && pick "$1" 2>/dev/null; then
    dir="$(cached "$1")"
    if [ -e "$dir" ]; then
      reports "$1" "$dir/$binary" && { printf '%s\n' "$dir/$binary"; return 0; }
      echo "godot-kit: $dir is not $(version "$1"); delete it and run ./scripts/godot-kit.sh again" >&2
      return 2
    fi
  fi
  for name in $(if [ "$1" = godot ]; then echo godot godot4; else echo gdscript-formatter; fi); do
    path="$(command -v "$name" || true)"
    if [ -n "$path" ] && reports "$1" "$path"; then
      printf '%s\n' "$path"
      return 0
    fi
  done
  return 1
}

sha() {  # $1 = bits, $2 = file: its hex digest
  if command -v "sha${1}sum" >/dev/null 2>&1; then "sha${1}sum" "$2"; else shasum -a "$1" "$2"; fi | cut -d' ' -f1
}

# Downloads tool $1, checks its sum and publishes it into the cache.
install() {
  local dest new name unpacked
  pick "$1"
  dest="$(cached "$1")"
  mkdir -p "$kit"
  new="$(mktemp -d "$kit/.install.XXXXXX")"
  name="${new##*/}"
  unpacked="$new/$name"
  # A copy already at $dest (another install's, maybe in use) is never replaced. If one
  # appears first, the rename below lands inside it instead, and this removes that again.
  trap 'rm -rf "$new" "$dest/${name:?}"' EXIT
  echo "godot-kit: downloading $(version "$1") ($asset)..." >&2
  curl -fsSL --retry 3 -o "$new/$asset" "$url"
  if [ "$(sha "$bits" "$new/$asset")" != "$sum" ]; then
    echo "godot-kit: $asset does not match its pinned SHA-$bits sum; refusing it" >&2
    exit 1
  fi
  mkdir "$unpacked"
  if command -v unzip >/dev/null 2>&1; then
    unzip -q "$new/$asset" -d "$unpacked"
  else
    python3 -I -m zipfile -e "$new/$asset" "$unpacked"
    chmod +x "$unpacked/$binary"
  fi
  if ! reports "$1" "$unpacked/$binary"; then
    echo "godot-kit: the downloaded $asset does not run as $(version "$1") here" >&2
    exit 1
  fi
  [ -e "$dest" ] || mv "$unpacked" "$dest" 2>/dev/null || true
  rm -rf "$new" "$dest/${name:?}"
  trap - EXIT
}

case "${1:-}" in
  godot | formatter)
    rc=0
    find_tool "$1" || rc=$?
    if [ "$rc" = 1 ]; then
      echo "godot-kit: $(version "$1") is not installed: run ./scripts/godot-kit.sh (or set $(env_name "$1"))" >&2
    fi
    exit "$rc" ;;
  '')
    for tool in godot formatter; do
      rc=0
      path="$(find_tool "$tool")" || rc=$?
      if [ "$rc" = 1 ]; then
        install "$tool"
        path="$(find_tool "$tool")"
      elif [ "$rc" != 0 ]; then
        exit 1
      fi
      echo "$(version "$tool"): $path"
    done ;;
  *)
    echo "usage: ./scripts/godot-kit.sh [godot | formatter]" >&2
    exit 2 ;;
esac
