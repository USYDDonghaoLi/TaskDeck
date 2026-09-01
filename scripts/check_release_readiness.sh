#!/bin/zsh
set -uo pipefail

PROJECT_ROOT="${0:A:h:h}"
CONFIG_PATH="${TASKDECK_RELEASE_CONFIG:-$PROJECT_ROOT/scripts/release.env}"
FAILURES=0

pass() { print "[PASS] $1" }
warn() { print "[WARN] $1" }
fail() {
    print "[FAIL] $1"
    FAILURES=$((FAILURES + 1))
}

print "TaskDeck public-release readiness"
print ""

if [[ -f "$CONFIG_PATH" ]]; then
    source "$CONFIG_PATH"
    pass "Release configuration exists outside Git tracking"
else
    fail "Missing $CONFIG_PATH (copy scripts/release.env.example first)"
fi

TASKDECK_TEAM_ID="${TASKDECK_TEAM_ID:-}"
TASKDECK_APP_BUNDLE_IDENTIFIER="${TASKDECK_APP_BUNDLE_IDENTIFIER:-}"
TASKDECK_WIDGET_BUNDLE_IDENTIFIER="${TASKDECK_WIDGET_BUNDLE_IDENTIFIER:-}"
TASKDECK_APP_GROUP_IDENTIFIER="${TASKDECK_APP_GROUP_IDENTIFIER:-}"
TASKDECK_SIGNING_IDENTITY="${TASKDECK_SIGNING_IDENTITY:-}"
TASKDECK_NOTARY_PROFILE="${TASKDECK_NOTARY_PROFILE:-}"
TASKDECK_VERSION="${TASKDECK_VERSION:-}"
TASKDECK_BUILD_NUMBER="${TASKDECK_BUILD_NUMBER:-}"

DEVELOPER_DIRECTORY=$(xcode-select -p 2>/dev/null || true)
if [[ "$DEVELOPER_DIRECTORY" == *CommandLineTools* || -z "$DEVELOPER_DIRECTORY" ]]; then
    fail "Full Xcode is not selected; current developer directory is ${DEVELOPER_DIRECTORY:-unavailable}"
elif xcodebuild -version >/dev/null 2>&1; then
    pass "Full Xcode is selected"
else
    fail "xcodebuild is unavailable from the selected developer directory"
fi

for tool in notarytool stapler; do
    if xcrun --find "$tool" >/dev/null 2>&1; then
        pass "$tool is available"
    else
        fail "$tool is unavailable; install/select the latest full Xcode"
    fi
done

required_variables=(
    TASKDECK_TEAM_ID
    TASKDECK_APP_BUNDLE_IDENTIFIER
    TASKDECK_WIDGET_BUNDLE_IDENTIFIER
    TASKDECK_APP_GROUP_IDENTIFIER
    TASKDECK_SIGNING_IDENTITY
    TASKDECK_NOTARY_PROFILE
    TASKDECK_VERSION
    TASKDECK_BUILD_NUMBER
)
for variable_name in "${required_variables[@]}"; do
    if [[ -n "${(P)variable_name}" ]]; then
        pass "$variable_name is configured"
    else
        fail "$variable_name is empty"
    fi
done

if [[ -n "$TASKDECK_TEAM_ID" ]]; then
    if [[ ${#TASKDECK_TEAM_ID} -ne 10 || "$TASKDECK_TEAM_ID" == *[^A-Z0-9]* ]]; then
        fail "TASKDECK_TEAM_ID must be the 10-character Apple Team ID"
    else
        pass "Apple Team ID format is valid"
    fi
fi

if [[ -n "$TASKDECK_APP_BUNDLE_IDENTIFIER" ]]; then
    if [[ "$TASKDECK_APP_BUNDLE_IDENTIFIER" == local.* || "$TASKDECK_APP_BUNDLE_IDENTIFIER" == com.example.* ]]; then
        fail "Main bundle identifier is still a development/example value"
    else
        pass "Main bundle identifier is production-shaped"
    fi
fi

if [[ -n "$TASKDECK_WIDGET_BUNDLE_IDENTIFIER" ]]; then
    if [[ "$TASKDECK_WIDGET_BUNDLE_IDENTIFIER" == local.* || "$TASKDECK_WIDGET_BUNDLE_IDENTIFIER" == com.example.* ]]; then
        fail "Widget bundle identifier is still a development/example value"
    elif [[ "$TASKDECK_WIDGET_BUNDLE_IDENTIFIER" == "$TASKDECK_APP_BUNDLE_IDENTIFIER".* ]]; then
        pass "Widget bundle identifier is namespaced under the main app"
    else
        warn "Widget bundle identifier is not namespaced under the main app"
    fi
fi

if [[ -n "$TASKDECK_APP_GROUP_IDENTIFIER" ]]; then
    if [[ "$TASKDECK_APP_GROUP_IDENTIFIER" == group.local.* || "$TASKDECK_APP_GROUP_IDENTIFIER" == group.com.example.* ]]; then
        fail "App Group identifier is still a development/example value"
    elif [[ "$TASKDECK_APP_GROUP_IDENTIFIER" == group.* ]]; then
        pass "App Group identifier format is valid"
    else
        fail "App Group identifier must begin with group."
    fi
fi

if [[ -n "$TASKDECK_SIGNING_IDENTITY" ]]; then
    if [[ "$TASKDECK_SIGNING_IDENTITY" != "Developer ID Application:"* ]]; then
        fail "Signing identity must be a Developer ID Application certificate"
    elif security find-identity -v -p codesigning 2>/dev/null | grep -F -q "$TASKDECK_SIGNING_IDENTITY"; then
        pass "Developer ID Application identity is installed"
    else
        fail "Configured Developer ID Application identity is not installed in Keychain"
    fi
fi

if [[ -n "$TASKDECK_VERSION" ]]; then
    if print -r -- "$TASKDECK_VERSION" | grep -E -q '^[0-9]+\.[0-9]+\.[0-9]+$'; then
        pass "Marketing version format is valid"
    else
        fail "TASKDECK_VERSION must use semantic numeric form such as 1.6.0"
    fi
fi

if [[ -n "$TASKDECK_BUILD_NUMBER" ]]; then
    if print -r -- "$TASKDECK_BUILD_NUMBER" | grep -E -q '^[1-9][0-9]*$'; then
        pass "Build number format is valid"
    else
        fail "TASKDECK_BUILD_NUMBER must be a positive integer"
    fi
fi

if plutil -lint \
    "$PROJECT_ROOT/Assets/Info.plist" \
    "$PROJECT_ROOT/WidgetExtension/Info.plist" \
    "$PROJECT_ROOT/Assets/TaskDeck.entitlements" \
    "$PROJECT_ROOT/Assets/TaskDeckWidget.entitlements" \
    "$PROJECT_ROOT/TaskDeck.xcodeproj/project.pbxproj" >/dev/null; then
    pass "Xcode project and property lists are structurally valid"
else
    fail "An Xcode project or property list is invalid"
fi

if [[ -n "$(plutil -extract NSHumanReadableCopyright raw "$PROJECT_ROOT/Assets/Info.plist" 2>/dev/null)" ]]; then
    pass "Copyright metadata is present"
else
    fail "NSHumanReadableCopyright is missing"
fi

if grep -q "ENABLE_HARDENED_RUNTIME = YES" "$PROJECT_ROOT/TaskDeck.xcodeproj/project.pbxproj"; then
    pass "Hardened Runtime is enabled"
else
    fail "Hardened Runtime is not enabled"
fi

if [[ "$(plutil -extract 'com\.apple\.security\.app-sandbox' raw "$PROJECT_ROOT/Assets/TaskDeckWidget.entitlements" 2>/dev/null)" == "true" ]] \
    && grep -q "ENABLE_APP_SANDBOX = YES" "$PROJECT_ROOT/TaskDeck.xcodeproj/project.pbxproj"; then
    pass "The Widget extension is sandboxed"
else
    fail "The Widget extension must enable App Sandbox"
fi

if [[ -f "$PROJECT_ROOT/PRIVACY.md" ]]; then
    pass "Privacy policy exists"
else
    fail "PRIVACY.md is missing"
fi

if [[ -f "$PROJECT_ROOT/CHANGELOG.md" ]]; then
    pass "Version changelog exists"
else
    fail "CHANGELOG.md is missing"
fi

if git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [[ -n "$(git -C "$PROJECT_ROOT" status --porcelain 2>/dev/null)" ]]; then
        warn "Git worktree is not clean; release only from a reviewed commit"
    else
        pass "Git worktree is clean"
    fi
fi

print ""
if (( FAILURES > 0 )); then
    print "Readiness check found $FAILURES blocking item(s)."
    exit 1
fi
print "All local release prerequisites are ready."
