#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
export CLANG_MODULE_CACHE_PATH="$project_root/ios/.build/clang-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$project_root/ios/.build/fixtures"
python3 "$project_root/ios/Tools/test-fixtures.py" "$project_root/ios/.build/fixtures"
swiftc -parse-as-library -swift-version 5 -lz "$project_root"/ios/Sources/LeonCore/*.swift \
    "$project_root"/ios/Tests/*.swift -o "$project_root/ios/.build/native-checks"
"$project_root/ios/.build/native-checks" "$project_root/ios/.build/fixtures"
swiftc -frontend -parse "$project_root"/ios/Sources/LeonIOS/*.swift
plutil -lint "$project_root/ios/Info.plist" "$project_root/ios/Leon.xcodeproj/project.pbxproj"
