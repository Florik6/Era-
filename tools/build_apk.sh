#!/bin/bash
# Reproducible Android build for ERA: Ascension (Godot 4.7.1, template-based export, no Gradle).
# Requirements: godot 4.7.1 on PATH, export templates 4.7.1.stable installed,
# an Android SDK dir containing platform-tools/adb and build-tools/<ver>/apksigner, a JDK (keytool).
# Usage: tools/build_apk.sh [debug|release|both]
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-both}"
SDK="${ANDROID_SDK_ROOT:-/opt/android-sdk}"
JDK="${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk-amd64}"
mkdir -p builds android
# 1) debug keystore (public, standard Android debug credentials)
if [ ! -f android/debug.keystore ]; then
  keytool -genkeypair -keystore android/debug.keystore -storepass android -alias androiddebugkey \
    -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1
fi
# 2) editor settings so the exporter finds SDK/JDK/debug key
VER=$(godot --version | cut -d. -f1-2)
CFG="$HOME/.config/godot"
mkdir -p "$CFG"
for f in "editor_settings-$VER.tres" "editor_settings-4.tres"; do
cat > "$CFG/$f" <<EOT
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "$SDK"
export/android/java_sdk_path = "$JDK"
export/android/debug_keystore = "$PWD/android/debug.keystore"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
EOT
done
# 3) import resources
godot --headless --path . --import >/dev/null 2>&1 || true
if [ "$MODE" = "debug" ] || [ "$MODE" = "both" ]; then
  godot --headless --path . --export-debug "Android" builds/ERA_Ascension-debug.apk
  ls -la builds/ERA_Ascension-debug.apk
fi
if [ "$MODE" = "release" ] || [ "$MODE" = "both" ]; then
  # Release signing: provide your own key via env vars; otherwise a local key is generated
  # (keep android/release.keystore + android/release_pass.txt safe: updates must use the same key).
  KS="${ERA_RELEASE_KEYSTORE:-$PWD/android/release.keystore}"
  ALIAS="${ERA_RELEASE_ALIAS:-era}"
  if [ -z "${ERA_RELEASE_PASSWORD:-}" ]; then
    if [ ! -f android/release_pass.txt ]; then
      head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 20 > android/release_pass.txt
    fi
    ERA_RELEASE_PASSWORD=$(cat android/release_pass.txt)
  fi
  if [ ! -f "$KS" ]; then
    keytool -genkeypair -keystore "$KS" -storepass "$ERA_RELEASE_PASSWORD" -alias "$ALIAS" -keypass "$ERA_RELEASE_PASSWORD" \
      -keyalg RSA -keysize 4096 -validity 10000 -dname "CN=ERA Ascension,O=ERA,C=RU" >/dev/null 2>&1
  fi
  export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$KS"
  export GODOT_ANDROID_KEYSTORE_RELEASE_USER="$ALIAS"
  export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$ERA_RELEASE_PASSWORD"
  godot --headless --path . --export-release "Android" builds/ERA_Ascension.apk
  ls -la builds/ERA_Ascension.apk
  # compatibility build: same package and key, OpenGL ES 3 renderer for
  # phones whose Vulkan drivers misbehave (installs over the main one)
  godot --headless --path . --export-release "Android GL" builds/ERA_Ascension_GL.apk
  ls -la builds/ERA_Ascension_GL.apk
fi
