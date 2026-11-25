#!/usr/bin/env bash
# The Android round trip from a clean checkout: builds libps_client.so (arm64-v8a, x86_64), the Kotlin bindings and the
# test server in the Rust repository (RUST_CLIENT, default ../universal-gpu-reinspire-client), copies them into this
# project, starts the server, and runs the instrumentation test on a connected device or emulator. With no device
# connected and AVD set, it starts that emulator headless first.
#
#   ANDROID_HOME, ANDROID_NDK_HOME, JAVA_HOME (17)   default to the Homebrew paths used when this was written
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
RUST="$(cd "${RUST_CLIENT:-$HERE/../universal-gpu-reinspire-client}" && pwd)"
PORT="${PORT:-8787}"
BASE="http://127.0.0.1:$PORT"
export ANDROID_HOME="${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$ANDROID_HOME/ndk/27.2.12479018}"
export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}"
ADB="$ANDROID_HOME/platform-tools/adb"

"$RUST/scripts/build-android.sh"
"$RUST/scripts/build-server.sh"
rm -rf "$HERE/src/main/jniLibs" "$HERE/src/main/kotlin/uniffi"
mkdir -p "$HERE/src/main/kotlin"
cp -R "$RUST/dist/android/jniLibs" "$HERE/src/main/jniLibs"
cp -R "$RUST/dist/android/kotlin/uniffi" "$HERE/src/main/kotlin/uniffi"

if ! "$ADB" get-state >/dev/null 2>&1; then
  [[ -n "${AVD:-}" ]] || { echo "no device connected; connect one or set AVD=<name> to start an emulator" >&2; exit 1; }
  nohup "$ANDROID_HOME/emulator/emulator" -avd "$AVD" -no-window -no-audio -no-boot-anim -no-snapshot \
    > /tmp/umbra-android-emulator.log 2>&1 &
  "$ADB" wait-for-device
fi
for _ in $(seq 1 120); do [[ "$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]] && break; sleep 2; done

mkdir -p "$HERE/results"
REPORTS="$HERE/results/reports.jsonl"
: > "$REPORTS"
if curl -s -o /dev/null "$BASE/tables"; then echo "port $PORT is already in use" >&2; exit 1; fi
"$RUST/target/release/ps-server" --port "$PORT" --reports "$REPORTS" \
  --table 2048x2048 --table 8192x4096 --table 32768x2048 > "$HERE/results/server.log" 2>&1 &
SERVER=$!
cleanup() { kill "$SERVER" 2>/dev/null || true; wait "$SERVER" 2>/dev/null || true; }
trap cleanup EXIT
for _ in $(seq 1 120); do curl -s -o /dev/null "$BASE/tables" && break; sleep 0.5; done

cd "$HERE"
nice -n 10 ./gradlew --no-daemon connectedDebugAndroidTest \
  -Pandroid.testInstrumentationRunnerArguments.server="http://10.0.2.2:$PORT" > results/gradle.log 2>&1 \
  || { tail -40 results/gradle.log >&2; exit 1; }
grep -E "Starting|Finished|BUILD" results/gradle.log
cat "$REPORTS"
[[ "$(grep -c '"android-emulator"' "$REPORTS")" -eq 3 ]] || { echo "expected 3 reports" >&2; exit 1; }
if grep -q '"match":false' "$REPORTS"; then echo "FAIL: a decoded row differs" >&2; exit 1; fi
echo "PASS: every decoded row equals the table's row"
