#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
sdk="$(xcrun --sdk macosx --show-sdk-path)"
output="$PWD/ios/.build/composer-layout"
app="$output/ComposerLayoutChecks.app"
mkdir -p "$app/Contents/MacOS" "$output/modules"
python3 - "$app/Contents/Info.plist" <<'PY'
import plistlib,sys
with open(sys.argv[1],'wb') as f:
    plistlib.dump(dict(CFBundleIdentifier='com.leon.tests.composer-layout',CFBundleExecutable='ComposerLayoutChecks',CFBundleName='ComposerLayoutChecks',CFBundlePackageType='APPL',CFBundleVersion='1',CFBundleShortVersionString='1',LSMinimumSystemVersion='13.0',UIDeviceFamily=[2],NSHighResolutionCapable=True,UIApplicationSceneManifest=dict(UIApplicationSupportsMultipleScenes=False,UISceneConfigurations={})),f)
PY
sources=()
while IFS= read -r source; do sources+=("$source"); done < <(rg --files ios/Sources -g '*.swift' | sort | sed '/\/LeonIOSApp.swift$/d')
xcrun swiftc -target "$(uname -m)-apple-ios16.0-macabi" -sdk "$sdk" \
  -F "$sdk/System/iOSSupport/System/Library/Frameworks" \
  -I "$sdk/System/iOSSupport/usr/include" -L "$sdk/System/iOSSupport/usr/lib" \
  -module-cache-path "$output/modules" -lz \
  "${sources[@]}" ios/Tests/Layout/ComposerLayoutChecks.swift \
  -o "$app/Contents/MacOS/ComposerLayoutChecks"
codesign --force --sign - "$app"
export LEON_LAYOUT_RESULT="$output/result.txt"
rm -f "$LEON_LAYOUT_RESULT"
"$app/Contents/MacOS/ComposerLayoutChecks" > "$output/runtime.log" 2>&1 &
process=$!
for ((attempt=0;attempt<45;attempt++)); do
  if ! kill -0 "$process" 2>/dev/null; then break; fi
  sleep 1
done
if kill -0 "$process" 2>/dev/null; then
  kill "$process"
  echo 'FAIL: composer layout harness timed out'
  exit 1
fi
status=0
wait "$process" || status=$?
if [[ -f "$LEON_LAYOUT_RESULT" ]]; then cat "$LEON_LAYOUT_RESULT"; else cat "$output/runtime.log"; fi
exit "$status"
