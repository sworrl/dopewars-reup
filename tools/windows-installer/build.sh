#!/usr/bin/env bash
# Assemble DopeWarsReUp-Windows-Installer.zip from source-controlled pieces.
#
#   tools/windows-installer/build.sh <path-to-signed.apk> <output-dir>
#
# Pulls Google's official Windows platform-tools (adb.exe + DLLs) from
# dl.google.com, caches the download, converts the .bat/.txt to CRLF, and
# zips everything under a single DopeWarsReUp-Windows-Installer/ folder so
# "Extract All" produces one tidy directory.
set -euo pipefail

APK="${1:?usage: build.sh <signed.apk> <outdir>}"
OUTDIR="${2:?usage: build.sh <signed.apk> <outdir>}"
HERE="$(cd "$(dirname "$0")" && pwd)"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/dopewars-platform-tools"
PT_ZIP="$CACHE/platform-tools-latest-windows.zip"

mkdir -p "$CACHE" "$OUTDIR"
OUTDIR="$(cd "$OUTDIR" && pwd)"
if [ ! -f "$PT_ZIP" ]; then
  echo ">> downloading Google platform-tools (Windows)"
  curl -fL --retry 3 -o "$PT_ZIP" \
    "https://dl.google.com/android/repository/platform-tools-latest-windows.zip"
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
PKG="$STAGE/DopeWarsReUp-Windows-Installer"
mkdir -p "$PKG"

unzip -j -q "$PT_ZIP" \
  "platform-tools/adb.exe" \
  "platform-tools/AdbWinApi.dll" \
  "platform-tools/AdbWinUsbApi.dll" -d "$PKG"

cp "$APK" "$PKG/dopewars-reup.apk"
# CRLF for Notepad/cmd friendliness
sed 's/\r\?$/\r/' "$HERE/Install DopeWars.bat" > "$PKG/Install DopeWars.bat"
sed 's/\r\?$/\r/' "$HERE/READ ME FIRST.txt"    > "$PKG/READ ME FIRST.txt"

ZIP="$OUTDIR/DopeWarsReUp-Windows-Installer.zip"
rm -f "$ZIP"
( cd "$STAGE" && zip -r -q "$ZIP" "DopeWarsReUp-Windows-Installer" )
echo "Built $ZIP"
