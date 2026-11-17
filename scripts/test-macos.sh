#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root/macos"
export CLANG_MODULE_CACHE_PATH="$project_root/macos/.build/clang-cache"
mkdir -p .build
swiftc -parse-as-library Sources/LeonApp/Models.swift Sources/LeonApp/MentionCompletion.swift Tests/MessageChecks.swift -o .build/message-checks
.build/message-checks
