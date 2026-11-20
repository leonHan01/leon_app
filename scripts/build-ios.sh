#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
platform="${1:-simulator}"
case "$platform" in simulator|device) ;; *) echo 'Usage: build-ios.sh [simulator|device]' >&2; exit 2 ;; esac
if [ -z "${DEVELOPER_DIR:-}" ] && ! xcodebuild -version >/dev/null 2>&1 && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
if ! xcodebuild -version >/dev/null 2>&1; then
    echo '需要完整 Xcode；当前 Command Line Tools 无法编译 UIKit / iOS。' >&2
    exit 1
fi
bash "$project_root/scripts/test-ios-core.sh"
if [ ! -d "$project_root/shared/markdown/node_modules/esbuild" ]; then
    npm ci --prefix "$project_root/shared/markdown" --cache "$project_root/ios/.build/npm-cache"
fi
node "$project_root/ios/Tools/prepare-assets.mjs"
node "$project_root/ios/Tools/test-renderer.mjs"
python3 "$project_root/ios/Tools/generate-project.py"
if [ "$platform" = simulator ]; then
    sdk=iphonesimulator; destination='generic/platform=iOS Simulator'; configuration=Debug
else
    sdk=iphoneos; destination='generic/platform=iOS'; configuration=Release
fi
xcodebuild -project "$project_root/ios/Leon.xcodeproj" -scheme Leon -configuration "$configuration" \
    -sdk "$sdk" -destination "$destination" -derivedDataPath "$project_root/ios/build" CODE_SIGNING_ALLOWED=NO build
mkdir -p "$project_root/dist"
ditto -c -k --keepParent "$project_root/ios/build/Build/Products/$configuration-$sdk/Leon.app" "$project_root/dist/Leon-iOS-$platform-unsigned.zip"
