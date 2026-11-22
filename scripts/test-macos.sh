#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root/macos"
export CLANG_MODULE_CACHE_PATH="$project_root/macos/.build/clang-cache"
mkdir -p .build
source "$project_root/scripts/macos-test-dependencies.sh"
swiftc -parse-as-library Sources/LeonApp/Models.swift Sources/LeonApp/DocumentModels.swift Sources/LeonApp/NotificationModels.swift Sources/LeonApp/UsagePricing.swift Sources/LeonApp/MentionCompletion.swift Sources/LeonApp/ChatCommand.swift Tests/MessageChecks.swift -o .build/message-checks
.build/message-checks
swiftc -parse-as-library Sources/LeonApp/MathMarkup.swift Sources/LeonApp/MessageMarkdown.swift Tests/MarkdownChecks.swift -o .build/markdown-checks
.build/markdown-checks
markdown_sources=(Sources/LeonApp/{ChatFontSize,MathMarkup,MessageMarkdown,MathRenderer,RichMarkdownMessageView,MarkdownMessageView}.swift)
swiftc -parse-as-library "${math_flags[@]}" "${markdown_sources[@]}" Tests/MathChecks.swift -o .build/math-checks
.build/math-checks
swiftc -parse-as-library "${math_flags[@]}" "${markdown_sources[@]}" Tests/TableLayoutChecks.swift -o .build/table-layout-checks
.build/table-layout-checks
image_sources=()
for source in Sources/LeonApp/*.swift; do
    if [ "$(basename "$source")" != "LeonApp.swift" ]; then image_sources+=("$source"); fi
done
swiftc -parse-as-library "${math_flags[@]}" "${image_sources[@]}" Tests/RichMarkdownChecks.swift -o .build/rich-markdown-checks
.build/rich-markdown-checks
swiftc -parse-as-library "${math_flags[@]}" "${image_sources[@]}" Tests/ImageChecks.swift -o .build/image-checks
.build/image-checks
swiftc -parse-as-library "${math_flags[@]}" "${image_sources[@]}" Tests/ComposerChecks.swift -o .build/composer-checks
.build/composer-checks

bash "$project_root/scripts/test-archive-macos.sh"
bash "$project_root/scripts/test-switching-macos.sh"
bash "$project_root/scripts/test-chat-search-macos.sh"
