#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
SDK_PATH="${TASKDECK_SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk}"
MODULE_CACHE="$PROJECT_ROOT/.build/module-cache"
CHECK_BINARY="$PROJECT_ROOT/.build/taskdeck-pdf-check"
OUTPUT_PDF="$PROJECT_ROOT/outputs/TaskDeck-示例月报.pdf"

mkdir -p "$MODULE_CACHE" "$PROJECT_ROOT/outputs" "$PROJECT_ROOT/tmp/pdfs"
env SDKROOT="$SDK_PATH" CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
    swiftc \
    -sdk "$SDK_PATH" \
    -target arm64-apple-macosx13.0 \
    -module-cache-path "$MODULE_CACHE" \
    "$PROJECT_ROOT/Sources/TaskDeck/Localization.swift" \
    "$PROJECT_ROOT/Sources/TaskDeck/TaskItem.swift" \
    "$PROJECT_ROOT/Sources/TaskDeck/SharedTaskAccess.swift" \
    "$PROJECT_ROOT/Sources/TaskDeck/FocusStore.swift" \
    "$PROJECT_ROOT/Sources/TaskDeck/PDFReportExporter.swift" \
    "$PROJECT_ROOT/scripts/pdf_report_check.swift" \
    -o "$CHECK_BINARY"

"$CHECK_BINARY" "$OUTPUT_PDF"
