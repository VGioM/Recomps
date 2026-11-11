#!/bin/zsh
# Construit « Recomps.app » dans dist/ ; ./build.sh install la copie aussi dans /Applications.
set -e
cd "$(dirname "$0")"
APP="dist/Recomps.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [[ ! -f App/AppIcon.icns || App/make_icon.swift -nt App/AppIcon.icns ]]; then
  rm -rf build/AppIcon.iconset && mkdir -p build
  swift App/make_icon.swift build/AppIcon.iconset && iconutil -c icns build/AppIcon.iconset -o App/AppIcon.icns
fi
swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macos14.0 -o "$APP/Contents/MacOS/Recomps" App/main.swift App/UI.swift App/SelfUpdate.swift
cp App/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Recomps</string>
  <key>CFBundleDisplayName</key><string>Recomps</string>
  <key>CFBundleIdentifier</key><string>me.vgiom.recomps</string>
  <key>CFBundleExecutable</key><string>Recomps</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.3.0</string>
  <key>CFBundleVersion</key><string>5</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF
# Certificat local s'il existe (./signing-cert.sh le crée) : c'est lui que la
# mise à jour intégrée vérifie, et il permet à macOS de garder ses
# autorisations d'une version à l'autre. Sinon, signature ad hoc.
strip -S "$APP/Contents/MacOS/Recomps" 2>/dev/null || true
IDENTITY="-"
if security find-identity -p codesigning 2>/dev/null | grep -q "VGioM Local Signing"; then
    IDENTITY="VGioM Local Signing"
fi
codesign --force --sign "$IDENTITY" "$APP"
echo "Signé : $IDENTITY"
echo "OK : $APP"
if [[ "$1" == "install" ]]; then
  rm -rf "/Applications/Recomps.app"
  cp -R "$APP" /Applications/
  echo "Installé dans /Applications"
fi
