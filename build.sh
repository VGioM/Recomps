#!/bin/zsh
# Construit « Recomps.app » dans dist/ ; ./build.sh install la copie aussi dans /Applications.
set -e
cd "$(dirname "$0")"
APP="dist/Recomps.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macos14.0 -o "$APP/Contents/MacOS/Recomps" App/main.swift
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Recomps</string>
  <key>CFBundleDisplayName</key><string>Recomps</string>
  <key>CFBundleIdentifier</key><string>me.vgiom.recomps</string>
  <key>CFBundleExecutable</key><string>Recomps</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF
codesign --force --sign - "$APP"
echo "OK : $APP"
if [[ "$1" == "install" ]]; then
  rm -rf "/Applications/Recomps.app"
  cp -R "$APP" /Applications/
  echo "Installé dans /Applications"
fi
