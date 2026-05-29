#!/usr/bin/env bash
#
# scripts/release.sh
#
# Builds a signed, notarized, stapled Blinken.dmg ready for distribution.
#
# Pipeline (all steps fail fast on error):
#   1. xcodebuild archive            (Release config, Universal 2)
#   2. xcodebuild -exportArchive     (signed for Developer ID)
#   3. xcrun notarytool submit       (notarize via Apple, --wait)
#   4. xcrun stapler staple          (attach ticket to the .app)
#   5. codesign + spctl verification
#   6. create-dmg                    (with /Applications drop target)
#
# ─── One-time setup before first run ─────────────────────────────────────
#
#   1. Developer ID Application certificate must be in your login Keychain.
#      (You should already have this from other apps. Verify with:
#       security find-identity -v -p codesigning | grep "Developer ID")
#
#   2. Store notarization credentials in the Keychain:
#         xcrun notarytool store-credentials "BLINKEN_NOTARY" \
#             --apple-id "marc@axiomic.ai" \
#             --team-id "XXXXXXXXXX" \
#             --password "<app-specific-password>"
#      Generate an app-specific password at: https://appleid.apple.com
#      The team-id is your 10-character Apple Developer Team ID.
#
#   3. Install create-dmg:
#         brew install create-dmg
#
# ─── Usage ───────────────────────────────────────────────────────────────
#
#   DEVELOPER_ID="Developer ID Application: Marc Hoag (XXXXXXXXXX)" \
#   NOTARY_PROFILE="BLINKEN_NOTARY" \
#   ./scripts/release.sh
#
# Output: build/Blinken.dmg, signed + notarized + stapled + Gatekeeper-approved.
#

set -euo pipefail

cd "$(dirname "$0")/.."

# ─── config ──────────────────────────────────────────────────────────────
SCHEME="Blinken"
PROJECT="Blinken.xcodeproj"
BUILD_DIR="build"
ARCHIVE_PATH="${BUILD_DIR}/Blinken.xcarchive"
EXPORT_PATH="${BUILD_DIR}/export"
STAGING_PATH="${BUILD_DIR}/dmg-staging"
APP_NAME="Blinken.app"
DMG_NAME="Blinken.dmg"
DMG_PATH="${BUILD_DIR}/${DMG_NAME}"

# ─── helpers ─────────────────────────────────────────────────────────────
log() { printf "\033[1;36m▸\033[0m %s\n" "$*"; }
ok()  { printf "\033[1;32m✓\033[0m %s\n" "$*"; }
err() { printf "\033[1;31m✗\033[0m %s\n" "$*" >&2; exit 1; }

# ─── prereqs ─────────────────────────────────────────────────────────────
[[ -n "${DEVELOPER_ID:-}" ]]   || err "DEVELOPER_ID env var required — see script header for the full identity string"
[[ -n "${NOTARY_PROFILE:-}" ]] || err "NOTARY_PROFILE env var required — see script header for setup"
command -v xcodebuild  >/dev/null || err "xcodebuild not found (Xcode developer tools required)"
command -v xcrun       >/dev/null || err "xcrun not found"
command -v create-dmg  >/dev/null || err "create-dmg not found — install with: brew install create-dmg"

# ─── version from project.yml ────────────────────────────────────────────
VERSION="$(grep -E '^[[:space:]]+MARKETING_VERSION' project.yml | head -1 | awk -F'"' '{print $2}')"
BUILD_NO="$(grep -E '^[[:space:]]+CURRENT_PROJECT_VERSION' project.yml | head -1 | awk -F'"' '{print $2}')"
[[ -n "$VERSION" ]]  || err "Could not read MARKETING_VERSION from project.yml"
[[ -n "$BUILD_NO" ]] || err "Could not read CURRENT_PROJECT_VERSION from project.yml"

log "Building Blinken ${VERSION} (build ${BUILD_NO})"

# ─── clean prior build ───────────────────────────────────────────────────
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ─── regenerate Xcode project (defensive) ────────────────────────────────
if command -v xcodegen >/dev/null; then
    log "Regenerating Xcode project from project.yml"
    xcodegen generate >/dev/null
fi

# ─── archive (Release config, signed for Developer ID) ───────────────────
log "Archiving (Release, Universal 2, Developer ID signing)"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE_PATH" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$DEVELOPER_ID" \
    archive

# ─── export signed .app from the archive ─────────────────────────────────
cat > "${BUILD_DIR}/ExportOptions.plist" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>${DEVELOPER_ID}</string>
</dict>
</plist>
XML

log "Exporting signed .app"
xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "${BUILD_DIR}/ExportOptions.plist"

APP_PATH="${EXPORT_PATH}/${APP_NAME}"
[[ -d "$APP_PATH" ]] || err "Expected ${APP_NAME} at $APP_PATH after export"

# ─── notarize ────────────────────────────────────────────────────────────
log "Zipping for notarization"
ZIP_PATH="${BUILD_DIR}/Blinken-notary.zip"
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

log "Submitting to Apple notary service (this takes a few minutes)"
xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
ok "Notarization accepted"

# ─── staple ──────────────────────────────────────────────────────────────
log "Stapling notarization ticket"
xcrun stapler staple "$APP_PATH"
ok "Ticket stapled"

# ─── verify ──────────────────────────────────────────────────────────────
log "Verifying signature & Gatekeeper acceptance"
codesign --verify --strict --verbose=2 "$APP_PATH" 2>&1 | sed 's/^/    /'
spctl -a -vvv --type install "$APP_PATH" 2>&1 | sed 's/^/    /'
ok "App is signed, notarized, stapled, and Gatekeeper-approved"

# ─── stage just the .app for create-dmg ──────────────────────────────────
rm -rf "$STAGING_PATH"
mkdir -p "$STAGING_PATH"
cp -R "$APP_PATH" "$STAGING_PATH/"

# ─── package DMG ─────────────────────────────────────────────────────────
log "Packaging DMG"
create-dmg \
    --volname "Blinken ${VERSION}" \
    --window-pos 200 120 \
    --window-size 540 360 \
    --icon-size 96 \
    --icon "${APP_NAME}" 130 180 \
    --hide-extension "${APP_NAME}" \
    --app-drop-link 410 180 \
    --no-internet-enable \
    "$DMG_PATH" \
    "$STAGING_PATH"

# ─── done ────────────────────────────────────────────────────────────────
ok "Built ${DMG_PATH} ($(du -h "$DMG_PATH" | cut -f1))"
echo
echo "Next steps:"
echo "  1. Smoke-test the DMG:    open ${DMG_PATH}"
echo "  2. Tag + push the release:"
echo "       git tag v${VERSION}"
echo "       git push origin v${VERSION}"
echo "  3. Create the GitHub Release with the DMG attached:"
echo "       gh release create v${VERSION} ${DMG_PATH} \\"
echo "           --title \"Blinken ${VERSION}\" \\"
echo "           --notes-file MD-ACTIVE/CHANGELOG-CURRENT.md"
echo
echo "Asset must be named exactly Blinken.dmg so the homepage's"
echo "/latest/download/Blinken.dmg URL resolves to it."
