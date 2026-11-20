#!/bin/bash
# Sourced by the standalone swiftc checks that also compile chat views.
swift build --build-system native --disable-sandbox --cache-path "$project_root/macos/.build/cache"
math_build="$project_root/macos/.build/debug"
math_flags=(-I "$math_build/Modules" "$math_build"/SwiftMath.build/*.o)
