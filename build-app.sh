#!/bin/zsh
# Baut build/GimmeTheVerse.app. Mit --install wird die App nach ~/Applications kopiert.
set -euo pipefail
cd "${0:A:h}"

for f in verses.json books.json themes.json embeddings.f16 prior.f32; do
  [[ -f Resources/$f ]] || { echo "Resources/$f fehlt – erst: uv run --with numpy tools/build_index.py"; exit 1; }
done

swift build -c release

APP=build/GimmeTheVerse.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/GimmeTheVerse "$APP/Contents/MacOS/"
cp Resources/{verses.json,books.json,themes.json,embeddings.f16,prior.f32} "$APP/Contents/Resources/"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

VERSION=$(git describe --tags --always 2>/dev/null || echo 0.1)
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>GimmeTheVerse</string>
  <key>CFBundleDisplayName</key><string>GimmeTheVerse</string>
  <key>CFBundleIdentifier</key><string>local.gimmetheverse.app</string>
  <key>CFBundleExecutable</key><string>GimmeTheVerse</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleDevelopmentRegion</key><string>de</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.lifestyle</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "→ $APP"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p ~/Applications
  rm -rf ~/Applications/GimmeTheVerse.app
  cp -R "$APP" ~/Applications/
  echo "→ ~/Applications/GimmeTheVerse.app"
fi
