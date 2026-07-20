#!/usr/bin/env bash
#
# release.sh — build, sign, notarize, and staple the Blinken DMG.
#
# Implements the pipeline in the build guide §5, which had been a manual
# checklist. Every release is months apart, which is exactly why it should not
# live in anyone's head.
#
# Usage:  ./scripts/release.sh            # version comes from project.yml
#         ./scripts/release.sh --skip-notarize   # local smoke test, unstapled
#
# Output: build/Blinken.dmg
#
# The artifact name is deliberately unversioned. The download link on the site
# is GitHub's permalink:
#     https://github.com/marchoag/blinken/releases/latest/download/Blinken.dmg
# which resolves by *asset filename*, so shipping "Blinken-1.0.2.dmg" would 404
# every existing link. Same reasoning for -volname: a bare "Blinken" means the
# mounted volume and its window layout stay correct across releases.

set -euo pipefail

cd "$(dirname "$0")/.."

SKIP_NOTARIZE=0
PACKAGE_ONLY=0
APP_IN=""
case "${1:-}" in
    --skip-notarize) SKIP_NOTARIZE=1 ;;
    # Xcode's Organizer ▸ Distribute App ▸ Direct Distribution already archives,
    # signs, notarizes, and staples — but it stops at a .app and can't build a
    # DMG. This mode picks up from there: hand it the exported app and it does
    # only the packaging half.
    --package-only)  PACKAGE_ONLY=1; APP_IN="${2:-}" ;;
    "") ;;
    *) printf 'usage: %s [--skip-notarize | --package-only [path/to/Blinken.app]]\n' "$0" >&2; exit 2 ;;
esac

# Apple Team ID that owns the Developer ID cert (the Axiomic, LLC team — not a
# personal Apple Development team, which can't be notarized). Not a secret: it's
# readable via `codesign -dvvv` on any shipped build. Kept out of the repo anyway
# to match the build guide's choice to omit DEVELOPMENT_TEAM from project.yml.
#   export BLINKEN_TEAM_ID=XXXXXXXXXX
# Not needed for --package-only: nothing is built or signed by us in that mode.
readonly TEAM_ID="${BLINKEN_TEAM_ID:-}"
[[ -n "${TEAM_ID}" || ${PACKAGE_ONLY} -eq 1 ]] || {
    printf '\n❌ BLINKEN_TEAM_ID is not set.\n' >&2
    printf '   It is the 10-character Apple Team ID owning the Developer ID cert.\n' >&2
    printf '   Recover it from the last shipped build:\n' >&2
    printf '     codesign -dvvv /Applications/Blinken.app 2>&1 | grep TeamIdentifier\n' >&2
    printf '   Then:  export BLINKEN_TEAM_ID=XXXXXXXXXX   (add to ~/.zshrc to persist)\n\n' >&2
    exit 1
}
readonly NOTARY_PROFILE="blinken-notarize"
readonly BUILD_DIR="build"
readonly DMG="${BUILD_DIR}/Blinken.dmg"
readonly ARCHIVE="${BUILD_DIR}/Blinken.xcarchive"

# xcode-select points at CommandLineTools on this machine, which can't run
# xcodebuild. Override per-invocation rather than requiring sudo xcode-select -s.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

die() { printf '\n❌ %s\n' "$1" >&2; exit 1; }
step() { printf '\n▸ %s\n' "$1"; }

# ── Preflight ────────────────────────────────────────────────────────────────
# Fail here with an explanation rather than 10 minutes in with a codesign error.

step "Preflight"

command -v xcodegen  >/dev/null || die "xcodegen not installed:  brew install xcodegen"
command -v create-dmg >/dev/null || die "create-dmg not installed:  brew install create-dmg"

# A local Developer ID identity is optional: this project has historically signed
# via Xcode-managed (cloud) signing, where the private key lives on Apple's
# servers and never appears here. So an empty result is normal, not fatal — the
# export step below still signs correctly via signingStyle:automatic + teamID.
# What it does change is whether we can sign the DMG wrapper ourselves (step 5).
IDENTITY=$(security find-identity -v -p codesigning \
           | grep "Developer ID Application" \
           | head -1 \
           | sed -E 's/.*"(.+)"/\1/') || true

if [[ ${SKIP_NOTARIZE} -eq 0 && ${PACKAGE_ONLY} -eq 0 ]]; then
    xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1 \
        || die "Notary profile '${NOTARY_PROFILE}' not found in the keychain.
   Fix (interactive — needs an app-specific password from appleid.apple.com):
        xcrun notarytool store-credentials \"${NOTARY_PROFILE}\" \\
          --apple-id <your-apple-id> --team-id ${TEAM_ID}
   Or skip the CLI entirely: Xcode ▸ Product ▸ Archive ▸ Distribute App ▸
   Direct Distribution, then:  ./scripts/release.sh --package-only <exported.app>"
fi

VERSION=$(grep 'MARKETING_VERSION:' project.yml | sed -E 's/.*"(.+)".*/\1/')
BUILD_NUM=$(grep 'CURRENT_PROJECT_VERSION:' project.yml | sed -E 's/.*"(.+)".*/\1/')
[[ -n "${VERSION}" ]] || die "Could not read MARKETING_VERSION from project.yml"

if [[ ${PACKAGE_ONLY} -eq 1 ]]; then
    printf '   mode     : package-only (app already built + notarized by Xcode)\n'
    # Labelled as project.yml's, since the packaged app is the real authority here.
    printf '   project.yml says: %s (build %s)\n' "${VERSION}" "${BUILD_NUM}"
elif [[ -n "${IDENTITY}" ]]; then
    printf '   identity : %s\n' "${IDENTITY}"
else
    printf '   identity : (none local — relying on Xcode-managed signing, team %s)\n' "${TEAM_ID}"
fi
[[ ${PACKAGE_ONLY} -eq 1 ]] || printf '   version  : %s (build %s)\n' "${VERSION}" "${BUILD_NUM}"

# ── Package-only: validate Xcode's output, then jump straight to packaging ────
# Everything Xcode's Direct Distribution flow already did is trusted but verified
# — the two failure modes worth catching are an Apple Development signature
# (won't pass Gatekeeper elsewhere) and a missing notarization ticket (shows the
# "cannot be opened" dialog on any Mac that can't reach Apple at first launch).

if [[ ${PACKAGE_ONLY} -eq 1 ]]; then
    [[ -n "${APP_IN}" ]] || APP_IN="${BUILD_DIR}/Blinken.app"
    [[ -d "${APP_IN}" ]] || die "No app bundle at '${APP_IN}'.
   Pass the path Xcode exported:  ./scripts/release.sh --package-only ~/Desktop/Blinken.app"

    step "Validating ${APP_IN}"

    APP_SIG=$(codesign -dvvv "${APP_IN}" 2>&1 || true)
    grep -q "Authority=Developer ID Application" <<<"${APP_SIG}" \
        || die "Not signed with a Developer ID Application cert.
   Signed with: $(grep -m1 'Authority=' <<<"${APP_SIG}" || echo '(none)')
   In Xcode, Distribute App ▸ Direct Distribution (not Debugging/Testing)."

    xcrun stapler validate "${APP_IN}" >/dev/null 2>&1 \
        || die "No notarization ticket stapled to this app.
   In Organizer, the archive must finish notarizing (status 'Ready to distribute')
   before you export it."

    APP_VERSION=$(defaults read "$(cd "$(dirname "${APP_IN}")" && pwd)/$(basename "${APP_IN}")/Contents/Info.plist" \
                  CFBundleShortVersionString 2>/dev/null || echo "?")
    printf '   signed   : %s\n' "$(grep -m1 'Authority=' <<<"${APP_SIG}" | sed 's/Authority=//')"
    printf '   stapled  : yes\n'
    printf '   version  : %s\n' "${APP_VERSION}"
    [[ "${APP_VERSION}" == "${VERSION}" ]] \
        || printf '\n⚠️  App is %s but project.yml says %s — check you exported the right archive.\n' \
                  "${APP_VERSION}" "${VERSION}"

    # Stage into build/ so the packaging step below is identical in both modes.
    mkdir -p "${BUILD_DIR}"
    [[ "$(cd "$(dirname "${APP_IN}")" && pwd)/$(basename "${APP_IN}")" == "$(pwd)/${BUILD_DIR}/Blinken.app" ]] \
        || { rm -rf "${BUILD_DIR}/Blinken.app"; cp -R "${APP_IN}" "${BUILD_DIR}/Blinken.app"; }
fi

# ── 1. Regenerate + clean build ──────────────────────────────────────────────
# project.yml is the source of truth and .xcodeproj is gitignored, so a stale
# generated project will happily ship yesterday's version number.
#
# Steps 1-5 are Xcode's job in --package-only mode; skip straight to packaging.

if [[ ${PACKAGE_ONLY} -eq 0 ]]; then

step "Generating project from project.yml"
xcodegen generate

step "Archiving (Release)"
rm -rf "${BUILD_DIR}"
xcodebuild clean -project Blinken.xcodeproj -scheme Blinken -quiet
# DEVELOPMENT_TEAM is deliberately absent from project.yml (build guide §2) so the
# repo carries no account identifiers. Supply it here instead of committing it.
xcodebuild -project Blinken.xcodeproj -scheme Blinken \
    -configuration Release archive -archivePath "${ARCHIVE}" \
    DEVELOPMENT_TEAM="${TEAM_ID}" CODE_SIGN_STYLE=Automatic -quiet

# ── 2. Export the signed .app ────────────────────────────────────────────────

step "Exporting signed .app"
# Generated rather than committed, so the team ID stays out of the repo. Written
# into build/ (gitignored). signingStyle:automatic lets Xcode pick the Developer
# ID cert — including a cloud-managed one, whose private key never lands in the
# local keychain, which is how this project has always signed.
EXPORT_PLIST="${BUILD_DIR}/ExportOptions.plist"
mkdir -p "${BUILD_DIR}"
cat > "${EXPORT_PLIST}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive -archivePath "${ARCHIVE}" \
    -exportPath "${BUILD_DIR}" \
    -exportOptionsPlist "${EXPORT_PLIST}" -quiet

# ── 3. Verify the signature before wrapping it in a DMG ──────────────────────

step "Verifying .app signature"
codesign --verify --deep --strict --verbose=2 "${BUILD_DIR}/Blinken.app"
# Catch the failure mode that matters: exporting with an Apple Development cert
# instead of Developer ID. It builds and runs locally, then fails notarization —
# or worse, ships and trips Gatekeeper on every other Mac.
# Captured to a variable rather than piped: under `set -o pipefail`, `grep -q`
# exits on first match, codesign takes SIGPIPE, and the pipeline reports failure
# even though the signature is fine.
APP_SIG=$(codesign -dvvv "${BUILD_DIR}/Blinken.app" 2>&1 || true)
grep -q "Authority=Developer ID Application" <<<"${APP_SIG}" \
    || die "Exported app is NOT signed with a Developer ID Application cert.
   Signed with: $(grep -m1 'Authority=' <<<"${APP_SIG}" || echo '(no authority found)')
   Check Xcode ▸ Settings ▸ Accounts is signed into the Axiomic team (${TEAM_ID})."

# ── 4-5. Notarize + staple THE APP, before packaging ─────────────────────────
#
# The app is the unit that gets notarized, not the DMG. Verified against shipped
# 1.0.1: its Blinken.app validates standalone ("stapler validate" passes) while
# the DMG has no ticket at all — so the app was stapled first, then packaged.
#
# This ordering is also the more robust one. A ticket stapled to the .app travels
# with it after the user drags it to /Applications and throws the DMG away;
# a ticket stapled only to the DMG does not. Without it, first launch on a Mac
# that's offline (or hitting a throttled Apple endpoint) shows the "cannot be
# opened" scare dialog.

if [[ ${SKIP_NOTARIZE} -eq 1 ]]; then
    printf '\n⚠️  Skipping notarization — output will NOT be distributable.\n'
else
    step "Notarizing app (this takes a few minutes)"
    # notarytool takes .zip/.dmg/.pkg, not a bare .app bundle. ditto's --keepParent
    # preserves the bundle directory itself inside the archive.
    ditto -c -k --keepParent "${BUILD_DIR}/Blinken.app" "${BUILD_DIR}/Blinken-notarize.zip"
    xcrun notarytool submit "${BUILD_DIR}/Blinken-notarize.zip" \
        --keychain-profile "${NOTARY_PROFILE}" --wait
    rm -f "${BUILD_DIR}/Blinken-notarize.zip"

    step "Stapling app"
    xcrun stapler staple "${BUILD_DIR}/Blinken.app"
    xcrun stapler validate "${BUILD_DIR}/Blinken.app"

    step "Verifying Gatekeeper acceptance"
    # The check that actually predicts the user's experience: this must report
    # "source=Notarized Developer ID".
    spctl -a -vvv "${BUILD_DIR}/Blinken.app"
fi

fi  # end: steps 1-5, skipped in --package-only mode

# ── 6. Package the (now stapled) app ─────────────────────────────────────────

step "Packaging DMG"
# create-dmg positions the icons by driving Finder over AppleScript, which needs
# Automation permission for whatever terminal you're in. First run may show
# "Terminal wants to control Finder" — allow it. In a context that can't prompt
# (CI, some agent shells) it fails with AppleScript error -1743, so fall back to
# a plain disk image rather than blocking the release on a permission dialog.
if ! create-dmg \
        --volname "Blinken" \
        --window-size 500 300 \
        --icon "Blinken.app" 100 150 \
        --app-drop-link 400 150 \
        "${DMG}" "${BUILD_DIR}/Blinken.app"; then
    printf '\n⚠️  create-dmg layout step failed (usually Finder Automation permission:\n'
    printf '   System Settings ▸ Privacy & Security ▸ Automation ▸ <your terminal> ▸ Finder).\n'
    printf '   Falling back to a plain DMG — functional, but no custom window layout.\n\n'
    rm -f "${DMG}" "${BUILD_DIR}"/rw.*.dmg
    STAGE="${BUILD_DIR}/dmg-stage"
    rm -rf "${STAGE}" && mkdir -p "${STAGE}"
    cp -R "${BUILD_DIR}/Blinken.app" "${STAGE}/"
    ln -s /Applications "${STAGE}/Applications"
    hdiutil create -volname "Blinken" -srcfolder "${STAGE}" \
        -ov -format UDZO "${DMG}" >/dev/null
    rm -rf "${STAGE}"
fi
# create-dmg leaves its read-write intermediate behind when it bails mid-way.
rm -f "${BUILD_DIR}"/rw.*.dmg

# ── 7. Sign the DMG wrapper (best effort) ────────────────────────────────────
# Shipped DMGs through 1.0.1 were unsigned — the guide's step 5 was skipped in
# practice, and users were fine because the stapled app inside carries the
# ticket. Sign it when a local identity exists anyway: it's the difference
# between Gatekeeper vouching for the disk image itself and only for its payload.

if [[ -n "${IDENTITY}" ]]; then
    step "Signing DMG"
    codesign --sign "${IDENTITY}" "${DMG}"
else
    step "Signing DMG — skipped (no local Developer ID identity)"
    printf '   Matches 1.0.1 and earlier; the app inside is signed + stapled either way.\n'
fi

[[ ${SKIP_NOTARIZE} -eq 1 ]] && { printf '\n⚠️  %s is NOT distributable (unnotarized).\n' "${DMG}"; exit 0; }

# Report the version of the app actually inside the DMG, not project.yml's. In
# --package-only mode the app comes from Xcode and can be from a different build
# than the working tree — printing project.yml's number there would label the
# release with a version it doesn't contain.
SHIPPED_VERSION=$(defaults read "$(pwd)/${BUILD_DIR}/Blinken.app/Contents/Info.plist" \
                  CFBundleShortVersionString 2>/dev/null || echo "${VERSION}")
SHIPPED_BUILD=$(defaults read "$(pwd)/${BUILD_DIR}/Blinken.app/Contents/Info.plist" \
                CFBundleVersion 2>/dev/null || echo "${BUILD_NUM}")

cat <<EOF

✅ ${DMG}  —  v${SHIPPED_VERSION} (build ${SHIPPED_BUILD})   ← version read from the packaged app

Next:
  1. gh release create v${SHIPPED_VERSION} ${DMG} --title "Blinken ${SHIPPED_VERSION}" --notes-file CHANGELOG.md
     (the asset MUST upload as exactly "Blinken.dmg" — the site's download
      permalink resolves by filename)
  2. Deploy the site from /Users/marchoag/dev/Axiomic (labs.axiomic.ai/blinken)
  3. Verify: curl -sIL https://github.com/marchoag/blinken/releases/latest/download/Blinken.dmg | tail -2
EOF
