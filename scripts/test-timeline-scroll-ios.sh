#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
sdk="$(xcrun --sdk macosx --show-sdk-path)"
output="$project_root/ios/.build/timeline-scroll"
app="$output/TimelineScrollChecks.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$output/modules"
python3 - "$app/Contents/Info.plist" <<'PY'
import plistlib,sys
with open(sys.argv[1],'wb') as file:
    plistlib.dump(dict(CFBundleIdentifier='com.leon.tests.timeline-scroll',CFBundleExecutable='TimelineScrollChecks',CFBundleName='TimelineScrollChecks',CFBundlePackageType='APPL',CFBundleVersion='1',CFBundleShortVersionString='1',LSMinimumSystemVersion='13.0',UIDeviceFamily=[2],NSHighResolutionCapable=True,UIApplicationSceneManifest=dict(UIApplicationSupportsMultipleScenes=False,UISceneConfigurations={})),file)
PY
cp -R ios/Resources/Markdown "$app/Contents/Resources/"
sources=()
while IFS= read -r source; do sources+=("$source"); done < <(rg --files ios/Sources -g '*.swift' | sort | sed '/\/LeonIOSApp.swift$/d')
xcrun swiftc -target "$(uname -m)-apple-ios16.0-macabi" -sdk "$sdk" \
    -F "$sdk/System/iOSSupport/System/Library/Frameworks" \
    -I "$sdk/System/iOSSupport/usr/include" -L "$sdk/System/iOSSupport/usr/lib" \
    -module-cache-path "$output/modules" -lz \
    "${sources[@]}" ios/Tests/Layout/TimelineScrollChecks.swift \
    -o "$app/Contents/MacOS/TimelineScrollChecks"
LEON_SCROLL_RESULT="$output/result.txt" "$app/Contents/MacOS/TimelineScrollChecks"
