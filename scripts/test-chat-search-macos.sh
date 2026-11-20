#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root/macos"
export CLANG_MODULE_CACHE_PATH="$project_root/macos/.build/clang-cache"
mkdir -p .build
swiftc -parse-as-library Sources/LeonApp/Models.swift Sources/LeonApp/DocumentModels.swift Sources/LeonApp/NotificationModels.swift Sources/LeonApp/ChatSearchState.swift Tests/SearchChecks.swift -o .build/search-checks
.build/search-checks
