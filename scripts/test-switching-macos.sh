#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root/macos"
export CLANG_MODULE_CACHE_PATH="$project_root/macos/.build/clang-cache"
mkdir -p .build
source "$project_root/scripts/macos-test-dependencies.sh"
sources=()
for source in Sources/LeonApp/*.swift; do
    if [ "$(basename "$source")" != "LeonApp.swift" ]; then sources+=("$source"); fi
done
swiftc -disable-sandbox -swift-version 5 -target "$(uname -m)-apple-macosx13.0" -parse-as-library "${math_flags[@]}" "${sources[@]}" Tests/SwitchingChecks.swift -o .build/switching-checks
.build/switching-checks
