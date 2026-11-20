#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root/macos"
export CLANG_MODULE_CACHE_PATH="$project_root/macos/.build/clang-cache"
swift build --build-system native -c release --disable-sandbox --cache-path "$project_root/macos/.build/cache"
bundle="$project_root/dist/Leon.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp .build/release/LeonApp "$bundle/Contents/MacOS/LeonApp.new"
mv -f "$bundle/Contents/MacOS/LeonApp.new" "$bundle/Contents/MacOS/LeonApp"
cp "$project_root/macos/Info.plist" "$bundle/Contents/Info.plist"
ditto .build/release/SwiftMath_SwiftMath.bundle "$bundle/Contents/Resources/SwiftMath_SwiftMath.bundle"
cp "$project_root/macos/Vendor/SwiftMath/LICENSE" "$bundle/Contents/Resources/SwiftMath-LICENSE.txt"
ditto "$project_root/shared/markdown/runtime" "$bundle/Contents/Resources/MarkdownRuntime"
swift "$project_root/scripts/make-icon.swift" "$project_root/dist/Leon.iconset"
iconutil -c icns "$project_root/dist/Leon.iconset" -o "$bundle/Contents/Resources/Leon.icns"
signing_identity="${LEON_CODESIGN_IDENTITY:-Leon Local Signing}"
if [ "$signing_identity" = "-" ]; then
    echo "A persistent signing identity is required for Keychain access across updates." >&2
    exit 1
fi
codesign --force --sign "$signing_identity" "$bundle"
codesign --verify --deep --strict "$bundle"
ditto -c -k --keepParent "$bundle" "$project_root/dist/Leon-macOS.zip"
echo "Built: $bundle"
