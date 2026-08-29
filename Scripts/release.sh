#!/usr/bin/env bash
# Build a Release ClaudeView.app, Developer ID sign with Hardened Runtime,
# notarize via Apple, staple, package as DMG, Sparkle-sign and write appcast.xml.
#
# ┌──────────────────────────────────────────────────────────────────────────┐
# │ SPARKLE SIGNING KEY — DO NOT REGENERATE                                  │
# │ Updates are EdDSA-signed with the private key stored in the login        │
# │ keychain under account "ClaudeView". Its public half is embedded in the  │
# │ app as SUPublicEDKey in project.yml:                                     │
# │     nz/9n40yF0Ei9n3Y5BCsbRjT8BeeHuTup172jlQQtSg=                         │
# │ NEVER run `generate_keys` again for this account and NEVER change        │
# │ SUPublicEDKey — every installed app would reject all future updates.     │
# └──────────────────────────────────────────────────────────────────────────┘
#
# Usage: ./Scripts/release.sh <version>       e.g. ./Scripts/release.sh 1.0.0
# Outputs release/ClaudeView-<version>.dmg + appcast.xml at the repo root.
# Does NOT push to GitHub — prints the suggested `gh release create` command.

set -euo pipefail

VERSION="${1:?Usage: ./Scripts/release.sh <version>  (e.g. 1.0.0)}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# 1. project.yml must declare the same MARKETING_VERSION
if ! grep -q "MARKETING_VERSION: $VERSION" project.yml; then
  echo "✗ MARKETING_VERSION in project.yml does not match $VERSION" >&2
  grep "MARKETING_VERSION" project.yml | sed 's/^/    /' >&2
  exit 1
fi

# 2. Regenerate xcodeproj
echo "→ xcodegen generate"
xcodegen generate >/dev/null

# 3. Build Release (manual signing below; CODE_SIGNING_ALLOWED=NO works around
# com.apple.provenance xattrs that break CLI codesign)
echo "→ xcodebuild Release"
xcodebuild -project ClaudeView.xcodeproj \
  -scheme ClaudeView \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -3

APP="$ROOT/build/Build/Products/Release/ClaudeView.app"
[ -d "$APP" ] || { echo "✗ Build did not produce $APP" >&2; exit 1; }

# 4. Stage clean (ditto strips xattrs), sign deepest-first with retries
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application: Vincent LAURIAT (KFLACS69T9)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AppliMacVincentGithub}"

STAGING_DIR="$(mktemp -d)"
STAGING="$STAGING_DIR/ClaudeView.app"
echo "→ Staging to $STAGING_DIR"
ditto --norsrc --noextattr --noacl "$APP" "$STAGING"

codesign_ts() {
  local target="$1" attempt
  for attempt in 1 2 3 4 5; do
    if codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$target" 2>&1; then
      return 0
    fi
    [ "$attempt" -lt 5 ] && { echo "  ↻ codesign retry ($attempt/5)…"; sleep 5; }
  done
  echo "✗ codesign $target failed after 5 attempts" >&2
  return 1
}

echo "→ Codesigning Sparkle.framework nested binaries (deepest first)"
SPARKLE_FW="$STAGING/Contents/Frameworks/Sparkle.framework"
SPARKLE_VER="$SPARKLE_FW/Versions/B"
codesign_ts "$SPARKLE_VER/Autoupdate"
codesign_ts "$SPARKLE_VER/XPCServices/Downloader.xpc"
codesign_ts "$SPARKLE_VER/XPCServices/Installer.xpc"
codesign_ts "$SPARKLE_VER/Updater.app"
codesign_ts "$SPARKLE_FW"

echo "→ Codesigning the app with Developer ID + Hardened Runtime"
codesign_ts "$STAGING"
codesign --verify --strict --deep "$STAGING"

# 5. DMG: app + /Applications alias
RELEASE_DIR="$ROOT/release"
mkdir -p "$RELEASE_DIR"
DMG="$RELEASE_DIR/ClaudeView-$VERSION.dmg"
rm -f "$DMG"
DMG_LAYOUT_DIR="$STAGING_DIR/dmg-layout"
mkdir -p "$DMG_LAYOUT_DIR"
ditto --norsrc --noextattr --noacl "$STAGING" "$DMG_LAYOUT_DIR/ClaudeView.app"
ln -s /Applications "$DMG_LAYOUT_DIR/Applications"
echo "→ Creating $DMG"
hdiutil create -volname "ClaudeView $VERSION" -srcfolder "$DMG_LAYOUT_DIR" \
  -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null
rm -rf "$STAGING_DIR"

# 6. Notarize + staple
echo "→ Submitting to Apple notary service (2–5 min)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
echo "→ Stapling"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

# 7. Sparkle EdDSA signature + appcast.xml
SPARKLE_VERSION="2.9.1"
SPARKLE_TOOLS="$ROOT/.sparkle-tools"
if [ ! -x "$SPARKLE_TOOLS/bin/sign_update" ]; then
  echo "→ Fetching Sparkle $SPARKLE_VERSION tools"
  mkdir -p "$SPARKLE_TOOLS"
  curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" \
    | tar -xJ -C "$SPARKLE_TOOLS"
fi
echo "→ Signing DMG with Sparkle EdDSA key (account ClaudeView)"
SPARKLE_SIG_LINE=$("$SPARKLE_TOOLS/bin/sign_update" --account "ClaudeView" "$DMG")

# Sparkle compares CFBundleVersion (build number), not the marketing version.
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")
PUB_DATE=$(date -R)
echo "→ Writing appcast.xml (sparkle:version=$BUILD_NUMBER, shortVersionString=$VERSION)"
cat > "$ROOT/appcast.xml" <<APPCAST
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>ClaudeView</title>
    <link>https://raw.githubusercontent.com/vincentlauriat/ClaudeView/main/appcast.xml</link>
    <description>ClaudeView release feed</description>
    <language>en</language>
    <item>
      <title>v$VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/vincentlauriat/ClaudeView/releases/tag/v$VERSION</sparkle:releaseNotesLink>
      <enclosure
        url="https://github.com/vincentlauriat/ClaudeView/releases/download/v$VERSION/ClaudeView-$VERSION.dmg"
        type="application/octet-stream"
        $SPARKLE_SIG_LINE />
    </item>
  </channel>
</rss>
APPCAST

DMG_SIZE=$(ls -lh "$DMG" | awk '{print $5}')
echo ""
echo "✅ Built, signed, notarized, stapled and Sparkle-signed: $DMG ($DMG_SIZE)"
echo "✅ appcast.xml written for v$VERSION"
echo ""
echo "Next steps:"
echo "  1. gh release create v$VERSION $DMG --title \"v$VERSION\" --notes-file release/release-notes-$VERSION.md"
echo "  2. git add appcast.xml && git commit -m 'chore: appcast for v$VERSION' && git push"
