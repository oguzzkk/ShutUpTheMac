#!/bin/bash
# Xcode olmadan .app paketi üretir: SwiftPM derler, bundle elle kurulur, ad-hoc imzalanır.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/Shut Up The Mac.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ShutUpApp "$APP/Contents/MacOS/ShutUpTheMac"
cp .build/release/shutup "$APP/Contents/Resources/shutup"
cp translations.json "$APP/Contents/Resources/translations.json"

# İkon: yoksa üret (Xcode gerekmez), sonra pakete koy
if [ ! -f build/ShutUpTheMac.icns ]; then
    swift tools/make-icon.swift
    rm -f build/ShutUpTheMac.iconset/icon_64x64.png build/ShutUpTheMac.iconset/icon_1024x1024.png
    iconutil -c icns build/ShutUpTheMac.iconset -o build/ShutUpTheMac.icns
fi
cp build/ShutUpTheMac.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Shut Up The Mac</string>
    <key>CFBundleDisplayName</key><string>Shut Up The Mac</string>
    <key>CFBundleIdentifier</key><string>com.oguzkaan.shutupthemac</string>
    <key>CFBundleExecutable</key><string>ShutUpTheMac</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.2.0</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Shut Up The Mac, uygulama başına ses seviyesini ayarlayabilmek için sistem ses akışını okur. Mikrofon kaydı yapmaz.</string>
    <key>NSAudioCaptureUsageDescription</key>
    <string>Shut Up The Mac, uygulama başına sesi kısabilmek için ses akışlarını işaretler.</string>
</dict>
</plist>
PLIST

# Sabit kimlikle imzala: ad-hoc imza her derlemede değiştiği için macOS verilen
# sistem sesi iznini düşürüyordu. Kimlik yoksa ad-hoc'a düşer.
IDENTITY="Shut Up The Mac Dev"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    codesign --force --sign "$IDENTITY" --options runtime --timestamp=none "$APP" >/dev/null 2>&1 \
        || codesign --force --sign "$IDENTITY" "$APP" >/dev/null 2>&1
else
    codesign --force --sign - "$APP" >/dev/null 2>&1
fi
echo "✅ $PWD/$APP"

# --install: kalıcı konuma kur ve oradan başlat
if [ "${1:-}" = "--install" ]; then
    TARGET="/Applications/Shut Up The Mac.app"
    pkill -x ShutUpTheMac 2>/dev/null || true   # -x: süreç adıyla eşleş, komut satırıyla değil (kendini öldürmesin)
    sleep 1
    rm -rf "$TARGET"
    cp -R "$APP" "$TARGET"
    if security find-identity -v -p codesigning 2>/dev/null | grep -q "Shut Up The Mac Dev"; then
        codesign --force --sign "Shut Up The Mac Dev" "$TARGET" >/dev/null 2>&1
    else
        codesign --force --sign - "$TARGET" >/dev/null 2>&1
    fi
    open "$TARGET"
    echo "✅ kuruldu ve başlatıldı: $TARGET"
fi
