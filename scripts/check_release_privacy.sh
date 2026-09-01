#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
APP_PATH="${1:-$PROJECT_ROOT/outputs/TaskDeck.app}"
DENYLIST_PATH="${TASKDECK_PRIVACY_DENYLIST:-$PROJECT_ROOT/scripts/privacy_denylist.txt}"
AUDIT_WORK=$(mktemp -d)
trap 'rm -rf "$AUDIT_WORK"' EXIT
FAILURES=0

pass() { print "[PASS] $1" }
fail() {
    print "[FAIL] $1"
    FAILURES=$((FAILURES + 1))
}

guarded_findings="$AUDIT_WORK/guarded-files.txt"
path_findings="$AUDIT_WORK/private-paths.txt"
email_findings="$AUDIT_WORK/emails.txt"

[[ -d "$APP_PATH" ]] || {
    print "Usage: $0 /path/to/TaskDeck.app"
    exit 2
}

find "$APP_PATH" -type f \( \
    -iname '*.sqlite' -o \
    -iname '*.sqlite3' -o \
    -iname '*.db' -o \
    -iname '*.json' -o \
    -iname '*.env' -o \
    -iname '*.pem' -o \
    -iname '*.p12' -o \
    -iname '*.cer' \
\) -print > "$guarded_findings"

if [[ -s "$guarded_findings" ]]; then
    fail "App bundle contains a database, JSON export, credential, or certificate file"
    sed 's/^/       /' "$guarded_findings"
else
    pass "No task database, JSON export, credential, or certificate is bundled"
fi

if LC_ALL=C grep -R -a -E -n '/Users/[A-Za-z0-9._-]+' "$APP_PATH" > "$path_findings" 2>/dev/null; then
    fail "App bundle contains an absolute macOS home-directory path"
else
    pass "No absolute macOS home-directory path is embedded"
fi

if LC_ALL=C grep -R -a -E -n '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$APP_PATH" > "$email_findings" 2>/dev/null; then
    fail "App bundle contains an email-like string"
else
    pass "No email-like string is embedded"
fi

if [[ -f "$DENYLIST_PATH" ]]; then
    denylist_failures_before=$FAILURES
    line_number=0
    while IFS= read -r private_value || [[ -n "$private_value" ]]; do
        line_number=$((line_number + 1))
        [[ -z "$private_value" || "$private_value" == \#* ]] && continue
        if LC_ALL=C grep -R -a -F -q -- "$private_value" "$APP_PATH"; then
            fail "Private denylist entry on line $line_number was found in the app bundle"
        fi
    done < "$DENYLIST_PATH"
    if (( FAILURES == denylist_failures_before )); then
        pass "Private denylist scan completed without printing protected values"
    fi
else
    print "[WARN] No private denylist found; copy scripts/privacy_denylist.txt.example for personalized scanning"
fi

if codesign --verify --deep --strict "$APP_PATH" >/dev/null 2>&1; then
    pass "Nested code signatures are structurally valid"
else
    fail "Code signature verification failed"
fi

if (( FAILURES > 0 )); then
    print "Privacy audit failed with $FAILURES blocking item(s)."
    exit 1
fi
print "TaskDeck release privacy audit passed."
