#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root/macos"
export CLANG_MODULE_CACHE_PATH="$project_root/macos/.build/clang-cache"
mkdir -p .build
swiftc -parse-as-library Sources/LeonApp/Models.swift Sources/LeonApp/UsagePricing.swift Sources/LeonApp/MentionCompletion.swift Sources/LeonApp/ChatCommand.swift Tests/MessageChecks.swift -o .build/message-checks
.build/message-checks
swiftc -parse-as-library Sources/LeonApp/MessageMarkdown.swift Tests/MarkdownChecks.swift -o .build/markdown-checks
.build/markdown-checks
image_sources=()
for source in Sources/LeonApp/*.swift; do
    if [ "$(basename "$source")" != "LeonApp.swift" ]; then image_sources+=("$source"); fi
done
swiftc -parse-as-library "${image_sources[@]}" Tests/ImageChecks.swift -o .build/image-checks
.build/image-checks
swiftc -parse-as-library "${image_sources[@]}" Tests/ComposerChecks.swift -o .build/composer-checks
.build/composer-checks

swiftc -parse-as-library Sources/LeonApp/Models.swift Sources/LeonApp/LeonBlogExporter.swift Tests/ArchiveChecks.swift -o .build/archive-checks
.build/archive-checks
bash "$project_root/scripts/test-switching-macos.sh"
