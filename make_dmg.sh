#!/bin/bash
# Builds Open-Wispr.app and wraps it in a distributable DMG. Run: ./make_dmg.sh
#
# The DMG contains the app, a shortcut to /Applications, and a short first-run
# note. The copy that ships is re-signed ad-hoc so no personal signing identity
# — and no API key — ever leaves this machine.
set -euo pipefail
cd "$(dirname "$0")"

APP="Open-Wispr.app"
VOLNAME="Open-Wispr"
OUTDIR="dist"
STAGE="$(mktemp -d /tmp/openwispr-dmg.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT

./build.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="$OUTDIR/Open-Wispr-$VERSION.dmg"

echo "Staging…"
cp -R "$APP" "$STAGE/$APP"
ln -s /Applications "$STAGE/Applications"

find "$STAGE/$APP" -name '.DS_Store' -delete

# --- Release safety gate -----------------------------------------------------
# Nothing private may ride along to strangers' Macs: no API key, no signing
# certificate or other credential file, and nothing that writes to their privacy
# database. The app is only ever allowed to ASK, through Apple's own prompts.
fail() { echo "ABORT: $1" >&2; exit 1; }

if grep -rqa 'sk-or-v1-[A-Za-z0-9]' "$STAGE/$APP"; then
  fail "an OpenRouter API key is embedded in the app bundle."
fi
if grep -rqa 'BEGIN [A-Z ]*PRIVATE KEY' "$STAGE/$APP"; then
  fail "a private key is embedded in the app bundle."
fi
CREDS=$(find "$STAGE/$APP" \( -name '.env' -o -name '*.p12' -o -name '*.pem' \
        -o -name '*.key' -o -name '*.cer' -o -name '*.mobileprovision' \
        -o -name '*.provisionprofile' \) )
[ -z "$CREDS" ] || fail "credential file(s) in the bundle:"$'\n'"$CREDS"
if grep -rqa 'tccutil' "$STAGE/$APP"; then
  fail "the bundle references tccutil — it must never touch a user's privacy settings."
fi
echo "Safety gate passed: no key, no credentials, no privacy-database writes."
# -----------------------------------------------------------------------------

# Ship an ad-hoc signature, never the local dev certificate.
codesign --force --sign - "$STAGE/$APP"
codesign --verify --strict "$STAGE/$APP"

cat > "$STAGE/Read Me First.txt" <<'EOF'
Open-Wispr — hold fn, speak, and your words are typed wherever the cursor is.

INSTALL
  1. Drag Open-Wispr onto the Applications folder in this window.
  2. Open-Wispr is signed but not notarised by Apple, so the first launch needs
     one extra step: open Applications in Finder, RIGHT-CLICK Open-Wispr,
     choose "Open", then "Open" again in the dialog. You only do this once.

     If macOS still refuses ("damaged" / "cannot be opened"), run this in
     Terminal once, then launch normally:

         xattr -dr com.apple.quarantine /Applications/Open-Wispr.app

FIRST RUN
  3. The settings window opens. Paste your own OpenRouter API key under
     "Transcription" and hit Save. Get one at https://openrouter.ai/keys —
     no key ships with this app, and yours is stored only on your Mac in
     ~/.config/openwispr/.env (chmod 600).
  4. System Settings -> Keyboard -> "Press (globe) key to" -> "Do Nothing",
     otherwise fn opens the emoji picker instead of dictating.
  5. Grant Accessibility + Input Monitoring (System Settings -> Privacy &
     Security), and allow the Microphone when prompted.

     Open-Wispr only ASKS: it triggers Apple's own permission prompts and can
     open the right Settings pane for you. It never edits your privacy
     settings, and every grant stays revocable in System Settings.

Hold fn while you speak and release to transcribe, or tap fn to start
hands-free and tap again to finish.

https://github.com/soorower/Open-Wispr
EOF

mkdir -p "$OUTDIR"
rm -f "$DMG"
echo "Building $DMG…"

# Two-step so the mounted volume carries the app icon: writable image first,
# brand it, then compress. (hdiutil has no -volicon on every macOS.)
RW="${TMPDIR:-/tmp}/openwispr-rw-$$.dmg"
rm -f "$RW"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -fs HFS+ \
  -format UDRW -quiet "$RW"

MOUNT=$(hdiutil attach -nobrowse -noverify -noautoopen "$RW" |
        grep -o '/Volumes/.*$' | tail -1)
if [ -n "$MOUNT" ]; then
  cp AppIcon.icns "$MOUNT/.VolumeIcon.icns"
  # FinderInfo bit 10 = "has custom icon".
  xattr -wx com.apple.FinderInfo \
    "0000000000000000040000000000000000000000000000000000000000000000" "$MOUNT" || true
  hdiutil detach "$MOUNT" -quiet
fi

hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -quiet -o "$DMG"
rm -f "$RW"

SIZE=$(du -h "$DMG" | cut -f1 | tr -d ' ')
echo "Built $DMG ($SIZE)"
echo "Test it with: open \"$DMG\""
