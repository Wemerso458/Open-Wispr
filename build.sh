#!/bin/bash
# Builds Open-Wispr.app from main.swift. Run: ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

APP="Open-Wispr.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling…"
# Every .swift here is part of the app except the standalone icon generator.
SOURCES=$(ls *.swift | grep -v '^make_icon.swift$' | tr '\n' ' ')
swiftc -O -swift-version 5 $SOURCES -o "$APP/Contents/MacOS/Open-Wispr"

cp Info.plist "$APP/Contents/Info.plist"

if [ ! -f AppIcon.icns ] || [ make_icon.swift -nt AppIcon.icns ]; then
  echo "Generating icon…"
  swift make_icon.swift
  iconutil -c icns AppIcon.iconset -o AppIcon.icns
  rm -rf AppIcon.iconset
fi
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Sign with a stable local cert if you have one — permissions then SURVIVE
# rebuilds. Set SIGN_IDENTITY to use your own (e.g. a Developer ID). Fallback:
# ad-hoc signing, where every rebuild invalidates the Accessibility grant.
IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  for candidate in "Open-Wispr Dev" "Wispr-Soro Dev"; do
    if security find-identity -v -p codesigning 2>/dev/null | grep -q "$candidate"; then
      IDENTITY="$candidate"; break
    fi
  done
fi

if [ -n "$IDENTITY" ]; then
  codesign --force -s "$IDENTITY" "$APP"
  echo "Signed with stable identity: $IDENTITY (permissions survive rebuilds)"
else
  codesign --force -s - "$APP"
  echo "Ad-hoc signed — macOS sees a new app, so re-grant Accessibility and"
  echo "Input Monitoring in System Settings › Privacy & Security after this build."
  # Opt-in only. This clears THIS app's Accessibility entry in your own privacy
  # database so the next launch re-prompts instead of showing a dead ON toggle.
  # Nothing in the shipped app touches privacy settings — it only ever triggers
  # Apple's standard permission prompts.
  if [ "${OPENWISPR_RESET_TCC:-0}" = "1" ]; then
    tccutil reset Accessibility com.openwispr.app >/dev/null 2>&1 || true
    echo "Reset this app's Accessibility entry (OPENWISPR_RESET_TCC=1)."
  fi
fi

echo "Built $APP"
echo "Launch with: open $APP"
