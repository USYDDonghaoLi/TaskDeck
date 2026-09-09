#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
SDK_PATH="${TASKDECK_SDKROOT:-}"
MODULE_CACHE="$PROJECT_ROOT/.build/module-cache"
CHECK_BINARY="$PROJECT_ROOT/.build/taskdeck-pdf-check"
OUTPUT_PDF="${TASKDECK_PDF_OUTPUT:-$PROJECT_ROOT/tmp/pdfs/TaskDeck-示例月报.pdf}"

if [[ -z "$SDK_PATH" ]]; then
    SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
fi
SWIFTC_PATH="$(xcrun --find swiftc)"
HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
    arm64|x86_64) TARGET_TRIPLE="$HOST_ARCH-apple-macosx13.0" ;;
    *) print "Unsupported build architecture: $HOST_ARCH"; exit 1 ;;
esac

mkdir -p "$MODULE_CACHE" "$PROJECT_ROOT/outputs" "$PROJECT_ROOT/tmp/pdfs"
env SDKROOT="$SDK_PATH" CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
    "$SWIFTC_PATH" \
    -sdk "$SDK_PATH" \
    -target "$TARGET_TRIPLE" \
    -module-cache-path "$MODULE_CACHE" \
    "$PROJECT_ROOT/Sources/TaskDeck/Localization.swift" \
    "$PROJECT_ROOT/Sources/TaskDeck/TaskItem.swift" \
    "$PROJECT_ROOT/Sources/TaskDeck/FocusModels.swift" \
    "$PROJECT_ROOT/Sources/TaskDeck/TaskDatabase.swift" \
    "$PROJECT_ROOT/Sources/TaskDeck/TaskDeckArchive.swift" \
    "$PROJECT_ROOT/Sources/TaskDeck/SharedTaskAccess.swift" \
    "$PROJECT_ROOT/Sources/TaskDeck/FocusStore.swift" \
    "$PROJECT_ROOT/Sources/TaskDeck/PDFReportExporter.swift" \
    "$PROJECT_ROOT/scripts/pdf_report_check.swift" \
    -o "$CHECK_BINARY"

"$CHECK_BINARY" "$OUTPUT_PDF"
