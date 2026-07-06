#!/usr/bin/env bash
# Build + sign a release APK and emit the integrity proofs users check to know it's unaltered:
#   - SHA256SUMS.txt   (verify the file wasn't tampered in transit)
#   - the signing certificate SHA-256 (verify it was signed by YOUR key, not a repackager's)
#
# Usage:
#   KEYSTORE=~/keys/dopewars-release.jks KS_PASS=... KEY_ALIAS=dopewars KEY_PASS=... \
#     tools/release.sh 0.3.0
#
# For a real public release use a dedicated RELEASE keystore (create once, keep it OFF the repo):
#   keytool -genkey -v -keystore dopewars-release.jks -alias dopewars \
#           -keyalg RSA -keysize 4096 -validity 10000
# Falls back to the Godot debug keystore if none is given (fine for testing, NOT for public trust).
set -euo pipefail

VERSION="${1:?usage: release.sh <version>}"
# versionCode: monotonic from semver (major*10000 + minor*100 + patch), overridable via $VERSION_CODE.
IFS=. read -r _MA _MI _PA <<< "${VERSION%%-*}"
VERSION_CODE="${VERSION_CODE:-$(( ${_MA:-0} * 10000 + ${_MI:-0} * 100 + ${_PA:-0} ))}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dopewars-reup"
GODOT="${GODOT:-$HOME/.local/bin/godot}"
SDK="${ANDROID_HOME:-$HOME/Android/Sdk}"
BT="${BT:-$SDK/build-tools/37.0.0}"
OUT="$APP/builds"; mkdir -p "$OUT"
APK="$OUT/dopewars-reup-$VERSION.apk"

KEYSTORE="${KEYSTORE:-$HOME/.local/share/godot/keystores/debug.keystore}"
KS_PASS="${KS_PASS:-android}"; KEY_ALIAS="${KEY_ALIAS:-androiddebugkey}"; KEY_PASS="${KEY_PASS:-android}"

echo ">> 1/6 export game pack"
"$GODOT" --headless --path "$APP" --export-pack "Android" "$OUT/dwreup.pck" >/dev/null
cp "$OUT/dwreup.pck" "$APP/android/build/src/main/assets/assets.sparsepck"

echo ">> 2/6 gradle build (release variant, arm64)"
( cd "$APP/android/build"
  export JAVA_HOME="${JAVA_HOME:-/home/linuxbrew/.linuxbrew/Cellar/openjdk@17/17.0.19/libexec}"
  export PATH="$JAVA_HOME/bin:$PATH" ANDROID_HOME="$SDK"
  ./gradlew assembleStandardRelease --no-daemon -q -Pexport_enabled_abis="arm64-v8a|" \
    -Pexport_version_name="$VERSION" -Pexport_version_code="$VERSION_CODE" )

echo ">> 3/6 zipalign + sign"
"$BT/zipalign" -p -f 4 "$APP/android/build/build/outputs/apk/standard/release/android_release.apk" /tmp/dwreup-aligned.apk
"$BT/apksigner" sign --ks "$KEYSTORE" --ks-pass "pass:$KS_PASS" \
  --ks-key-alias "$KEY_ALIAS" --key-pass "pass:$KEY_PASS" --out "$APK" /tmp/dwreup-aligned.apk

echo ">> 4/6 checksums"
( cd "$OUT" && sha256sum "$(basename "$APK")" > SHA256SUMS.txt )

echo ">> 5/6 update manifest (latest.json — the in-app Updater polls this)"
REPO="${REPO:-sworrl/dopewars-reup}"
APK_SHA="$(sha256sum "$APK" | cut -d' ' -f1)"
NOTES="${NOTES:-See the release notes on GitHub.}"
cat > "$OUT/latest.json" <<JSON
{
  "version": "$VERSION",
  "url": "https://github.com/$REPO/releases/download/v$VERSION/$(basename "$APK")",
  "sha256": "$APK_SHA",
  "notes": "$NOTES"
}
JSON

echo ">> 6/6 signing certificate (publish this fingerprint so users can verify the signer)"
"$BT/apksigner" verify --print-certs "$APK" | grep -i "SHA-256"

echo
echo "Built  $APK"
echo "Sums   $OUT/SHA256SUMS.txt"
echo "Manif  $OUT/latest.json  (attach as a release asset named exactly latest.json)"
echo "Attach all three to the GitHub Release. Users verify with:"
echo "  sha256sum -c SHA256SUMS.txt"
echo "  apksigner verify --print-certs dopewars-reup-$VERSION.apk   # compare SHA-256 to the published cert"
