#!/bin/bash
# Сборка Button-S.app из SPM-пакета.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
APP="Build/Button-S.app"
BIN=".build/$CONFIG/ButtonS"

echo "== сборка ($CONFIG) =="
swift build -c "$CONFIG"

if [[ ! -f "$BIN" ]]; then
    echo "бинарник не найден: $BIN" >&2
    exit 1
fi

echo "== упаковка =="
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/Button-S"

if [[ -f Resources/Icons/icon.icns ]]; then
    cp Resources/Icons/icon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

mkdir -p "$APP/Contents/Resources/Data"
cp Resources/Data/*.txt "$APP/Contents/Resources/Data/"

# SPM-бандлы: без них Bundle.module падает при старте.
for bundle in .build/"$CONFIG"/*.bundle; do
    [[ -d "$bundle" ]] && cp -R "$bundle" "$APP/Contents/Resources/"
done

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Button-S</string>
    <key>CFBundleDisplayName</key>
    <string>Button-S</string>
    <key>CFBundleIdentifier</key>
    <string>com.button.v2</string>
    <key>CFBundleExecutable</key>
    <string>Button-S</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Button-S записывает голос для распознавания речи на устройстве.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "== подпись =="
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -1 | sed -E 's/.*"(.*)"/\1/')
if [ -n "$IDENTITY" ]; then
  echo "подписываю как: $IDENTITY"
  codesign --force --deep --options runtime --timestamp=none \
    --entitlements Resources/Entitlements.plist \
    --sign "$IDENTITY" "$APP"
else
  echo "нет сертификата, ad-hoc"
  codesign --force --deep --sign - "$APP"
fi

echo "готово: $APP"
