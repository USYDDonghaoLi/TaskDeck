#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
CONFIG_PATH="${TASKDECK_RELEASE_CONFIG:-$PROJECT_ROOT/scripts/release.env}"

[[ -f "$CONFIG_PATH" ]] || {
    print "Missing $CONFIG_PATH"
    print "Copy scripts/release.env.example and fill in the registered Apple values."
    exit 2
}
source "$CONFIG_PATH"

"$PROJECT_ROOT/scripts/check_release_readiness.sh"

RELEASE_ROOT="$PROJECT_ROOT/.release/${TASKDECK_VERSION}-${TASKDECK_BUILD_NUMBER}"
ARCHIVE_PATH="$RELEASE_ROOT/TaskDeck.xcarchive"
EXPORT_PATH="$RELEASE_ROOT/export"
DMG_STAGE="$RELEASE_ROOT/dmg-stage"
APP_ZIP="$RELEASE_ROOT/TaskDeck-${TASKDECK_VERSION}.zip"
DMG_PATH="$RELEASE_ROOT/TaskDeck-${TASKDECK_VERSION}.dmg"
EXPORT_OPTIONS="$RELEASE_ROOT/ExportOptions.plist"
PUBLIC_OUTPUT="$PROJECT_ROOT/outputs/releases"

rm -rf "$RELEASE_ROOT"
mkdir -p "$RELEASE_ROOT" "$EXPORT_PATH" "$DMG_STAGE" "$PUBLIC_OUTPUT"

print "[1/8] Archiving a Universal Release build with Xcode"
xcodebuild \
    -project "$PROJECT_ROOT/TaskDeck.xcodeproj" \
    -scheme TaskDeck \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    clean archive \
    "DEVELOPMENT_TEAM=$TASKDECK_TEAM_ID" \
    "CODE_SIGN_STYLE=Automatic" \
    "TASKDECK_APP_BUNDLE_IDENTIFIER=$TASKDECK_APP_BUNDLE_IDENTIFIER" \
    "TASKDECK_WIDGET_BUNDLE_IDENTIFIER=$TASKDECK_WIDGET_BUNDLE_IDENTIFIER" \
    "TASKDECK_APP_GROUP_IDENTIFIER=$TASKDECK_APP_GROUP_IDENTIFIER" \
    "MARKETING_VERSION=$TASKDECK_VERSION" \
    "CURRENT_PROJECT_VERSION=$TASKDECK_BUILD_NUMBER" \
    'ARCHS=arm64 x86_64' \
    'ONLY_ACTIVE_ARCH=NO'

plutil -create xml1 "$EXPORT_OPTIONS"
plutil -insert method -string developer-id "$EXPORT_OPTIONS"
plutil -insert destination -string export "$EXPORT_OPTIONS"
plutil -insert signingStyle -string automatic "$EXPORT_OPTIONS"
plutil -insert teamID -string "$TASKDECK_TEAM_ID" "$EXPORT_OPTIONS"
plutil -insert signingCertificate -string "$TASKDECK_SIGNING_IDENTITY" "$EXPORT_OPTIONS"
plutil -insert stripSwiftSymbols -bool true "$EXPORT_OPTIONS"

print "[2/8] Exporting with the Developer ID Application certificate"
xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -allowProvisioningUpdates

APP_PATH="$EXPORT_PATH/TaskDeck.app"
WIDGET_PATH="$APP_PATH/Contents/PlugIns/TaskDeckWidget.appex"
[[ -d "$APP_PATH" ]] || {
    print "Exported TaskDeck.app was not found."
    exit 1
}
[[ -d "$WIDGET_PATH" ]] || {
    print "Exported TaskDeckWidget.appex was not found."
    exit 1
}

[[ "$(plutil -extract CFBundleIdentifier raw "$APP_PATH/Contents/Info.plist")" == "$TASKDECK_APP_BUNDLE_IDENTIFIER" ]]
[[ "$(plutil -extract CFBundleIdentifier raw "$WIDGET_PATH/Contents/Info.plist")" == "$TASKDECK_WIDGET_BUNDLE_IDENTIFIER" ]]
[[ "$(plutil -extract TaskDeckAppGroupIdentifier raw "$APP_PATH/Contents/Info.plist")" == "$TASKDECK_APP_GROUP_IDENTIFIER" ]]

ARCHITECTURES=$(lipo -archs "$APP_PATH/Contents/MacOS/TaskDeck")
[[ "$ARCHITECTURES" == *arm64* && "$ARCHITECTURES" == *x86_64* ]] || {
    print "Release is not Universal: $ARCHITECTURES"
    exit 1
}
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign -dvv "$APP_PATH" 2>&1 | grep -q 'flags=.*runtime'
codesign -dvv "$APP_PATH" 2>&1 | grep -F -q 'Authority=Developer ID Application:'
codesign -dvv "$APP_PATH" 2>&1 | grep -F -q "TeamIdentifier=$TASKDECK_TEAM_ID"
codesign -dvv "$WIDGET_PATH" 2>&1 | grep -q 'flags=.*runtime'

APP_ENTITLEMENTS="$RELEASE_ROOT/app-effective-entitlements.plist"
WIDGET_ENTITLEMENTS="$RELEASE_ROOT/widget-effective-entitlements.plist"
codesign -d --entitlements :- "$APP_PATH" > "$APP_ENTITLEMENTS" 2>/dev/null
codesign -d --entitlements :- "$WIDGET_PATH" > "$WIDGET_ENTITLEMENTS" 2>/dev/null
[[ "$(plutil -extract 'com\.apple\.security\.application-groups'.0 raw "$APP_ENTITLEMENTS")" == "$TASKDECK_APP_GROUP_IDENTIFIER" ]]
[[ "$(plutil -extract 'com\.apple\.security\.application-groups'.0 raw "$WIDGET_ENTITLEMENTS")" == "$TASKDECK_APP_GROUP_IDENTIFIER" ]]
[[ "$(plutil -extract 'com\.apple\.security\.app-sandbox' raw "$WIDGET_ENTITLEMENTS")" == "true" ]]
"$PROJECT_ROOT/scripts/check_release_privacy.sh" "$APP_PATH"

print "[3/8] Submitting the signed app to Apple notarization"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$APP_ZIP"
xcrun notarytool submit "$APP_ZIP" \
    --keychain-profile "$TASKDECK_NOTARY_PROFILE" \
    --wait
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl --assess --type execute --verbose=2 "$APP_PATH"

print "[4/8] Creating the public DMG"
ditto "$APP_PATH" "$DMG_STAGE/TaskDeck.app"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create \
    -volname "TaskDeck $TASKDECK_VERSION" \
    -srcfolder "$DMG_STAGE" \
    -format UDZO \
    -ov \
    "$DMG_PATH"

print "[5/8] Signing the DMG"
codesign --force \
    --timestamp \
    --sign "$TASKDECK_SIGNING_IDENTITY" \
    "$DMG_PATH"
hdiutil verify "$DMG_PATH"

print "[6/8] Submitting the DMG to Apple notarization"
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$TASKDECK_NOTARY_PROFILE" \
    --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

print "[7/8] Running Gatekeeper and privacy verification"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"
"$PROJECT_ROOT/scripts/check_release_privacy.sh" "$APP_PATH"

print "[8/8] Publishing local release artifacts"
FINAL_DMG="$PUBLIC_OUTPUT/TaskDeck-${TASKDECK_VERSION}.dmg"
ditto "$DMG_PATH" "$FINAL_DMG"
shasum -a 256 "$FINAL_DMG" > "$FINAL_DMG.sha256"
if [[ -f "$PROJECT_ROOT/outputs/TaskDeck-${TASKDECK_VERSION%%.0}-更新说明.md" ]]; then
    cp "$PROJECT_ROOT/outputs/TaskDeck-${TASKDECK_VERSION%%.0}-更新说明.md" "$PUBLIC_OUTPUT/"
fi

print ""
print "Public release completed:"
print "$FINAL_DMG"
print "$FINAL_DMG.sha256"
