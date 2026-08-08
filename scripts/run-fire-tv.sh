#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/../Application" && pwd)"
AVD_NAME="${AVD_NAME:-fire-tv}"
PACKAGE_NAME="${PACKAGE_NAME:-com.fireappbuilder.android.calypso}"
DISPLAY="${DISPLAY:-:0}"
LOG_PATH="${FIRE_TV_EMULATOR_LOG:-/tmp/fire-tv-emulator.log}"
SDK_ROOT="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/android-sdk}}"
ADB="$SDK_ROOT/platform-tools/adb"
EMULATOR="$SDK_ROOT/emulator/emulator"

if [ ! -r /dev/kvm ] || [ ! -w /dev/kvm ]; then
  sudo chmod 666 /dev/kvm || true
fi
if [ ! -r /dev/kvm ] || [ ! -w /dev/kvm ]; then
  echo "KVM is not readable and writable: /dev/kvm" >&2
  exit 1
fi

if [ -z "${APK_PATH:-}" ]; then
  APK_PATH="$(ls -t "$APP_DIR"/app/build/outputs/apk/debug/*.apk 2>/dev/null | head -1 || true)"
fi
if [ -z "$APK_PATH" ] || [ ! -f "$APK_PATH" ]; then
  echo "APK not found; run: (cd $APP_DIR && ./gradlew assembleDebug)" >&2
  exit 1
fi

if ! "$ADB" -s emulator-5554 get-state >/dev/null 2>&1; then
  : >"$LOG_PATH"
  DISPLAY="$DISPLAY" "$EMULATOR" -avd "$AVD_NAME" -snapshot default_boot \
    -gpu host -no-boot-anim -noaudio -no-snapshot-save >"$LOG_PATH" 2>&1 &
fi

timeout 20 "$ADB" wait-for-device || true
booted=false
for _ in $(seq 1 180); do
  if "$ADB" shell getprop sys.boot_completed 2>/dev/null | grep -q '^1$'; then
    booted=true
    break
  fi
  sleep 1
done

if [ "$booted" != true ]; then
  "$ADB" emu kill >/dev/null 2>&1 || true
  : >"$LOG_PATH"
  DISPLAY="$DISPLAY" "$EMULATOR" -avd "$AVD_NAME" -snapshot default_boot \
    -gpu swiftshader_indirect -no-boot-anim -noaudio -no-snapshot-save >"$LOG_PATH" 2>&1 &
  timeout 20 "$ADB" wait-for-device || true
  for _ in $(seq 1 180); do
    if "$ADB" shell getprop sys.boot_completed 2>/dev/null | grep -q '^1$'; then
      booted=true
      break
    fi
    sleep 1
  done
fi

if [ "$booted" != true ]; then
  echo "Emulator did not finish booting; see $LOG_PATH" >&2
  exit 1
fi

"$ADB" install -r "$APK_PATH"
"$ADB" shell monkey -p "$PACKAGE_NAME" 1 >/dev/null
echo "Ready: $PACKAGE_NAME on $AVD_NAME"
