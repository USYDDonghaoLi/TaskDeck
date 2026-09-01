#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
SDK_PATH="${TASKDECK_SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk}"
MODULE_CACHE="$PROJECT_ROOT/.build/module-cache"
CHECK_BINARY="$PROJECT_ROOT/.build/taskdeck-logic-check"

mkdir -p "$MODULE_CACHE"
env SDKROOT="$SDK_PATH" CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
    swiftc \
    -sdk "$SDK_PATH" \
    -target arm64-apple-macosx13.0 \
    -module-cache-path "$MODULE_CACHE" \
    "$PROJECT_ROOT/Sources/TaskDeck/TaskItem.swift" \
    "$PROJECT_ROOT/Sources/TaskDeck/TaskStore.swift" \
    "$PROJECT_ROOT/Sources/TaskDeck/FocusStore.swift" \
    "$PROJECT_ROOT/scripts/logic_check.swift" \
    -o "$CHECK_BINARY"

"$CHECK_BINARY"
