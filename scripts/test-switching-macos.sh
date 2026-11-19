#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root/macos"
export CLANG_MODULE_CACHE_PATH="$project_root/macos/.build/clang-cache"
mkdir -p .build
sources=()
for source in Sources/LeonApp/*.swift; do
    if [ "$(basename "$source")" != "LeonApp.swift" ]; then sources+=("$source"); fi
done
swiftc -parse-as-library "${sources[@]}" Tests/SwitchingChecks.swift -o .build/switching-checks
.build/switching-checks
