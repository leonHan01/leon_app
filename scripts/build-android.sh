#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root/android"
if [ -z "${ANDROID_HOME:-}" ] && [ -d /opt/homebrew/share/android-commandlinetools ]; then
    export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
fi
./gradlew --no-daemon assembleDebug testDebugUnitTest lintDebug
mkdir -p "$project_root/dist"
cp app/build/outputs/apk/debug/app-debug.apk "$project_root/dist/Leon-android-debug.apk"
echo "Built: $project_root/dist/Leon-android-debug.apk"
