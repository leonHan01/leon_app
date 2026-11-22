#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root/macos"
export CLANG_MODULE_CACHE_PATH="$project_root/macos/.build/clang-cache"
mkdir -p .build
sources=(Sources/LeonApp/Models.swift Sources/LeonApp/DocumentModels.swift Sources/LeonApp/NotificationModels.swift Sources/LeonApp/LeonBlogExporter.swift)
swiftc -swift-version 5 -parse-as-library "${sources[@]}" Tests/ArchiveChecks.swift -o .build/archive-checks
.build/archive-checks
swiftc -swift-version 5 -parse-as-library "${sources[@]}" Sources/LeonApp/ChatStore.swift Sources/LeonApp/ChatCommand.swift Sources/LeonApp/ConversationScrollPosition.swift Sources/LeonApp/ChatImageDraft.swift Sources/LeonApp/Keychain.swift Tests/ArchiveFlowChecks.swift -o .build/archive-flow-checks
.build/archive-flow-checks
