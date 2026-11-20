#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/leon-context-models.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
export CLANG_MODULE_CACHE_PATH="$check_dir/clang-cache"
swiftc -parse-as-library "$project_root/macos/Sources/LeonApp/Models.swift" "$project_root/macos/Sources/LeonApp/DocumentModels.swift" "$project_root/macos/Sources/LeonApp/NotificationModels.swift" "$project_root/macos/Tests/ContextMemoryChecks.swift" -o "$check_dir/mac-context-checks"
"$check_dir/mac-context-checks"
swiftc -parse-as-library -swift-version 5 -lz "$project_root"/ios/Sources/LeonCore/*.swift "$project_root/macos/Tests/ContextMemoryChecks.swift" -o "$check_dir/ios-context-checks"
"$check_dir/ios-context-checks"
