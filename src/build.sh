#!/bin/bash
# RubaiSTT Dictation — native macOS ilovasini build qiladi.
# whisper.cpp statik kutubxonalari $ROOT/whisper.cpp/build-static da bo'lishi kerak
# (setup.sh buni avtomatik tayyorlaydi).
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SRC/.." && pwd)"
WC="$ROOT/whisper.cpp"
LIB="$WC/build-static"
APP="$HOME/Applications/RubaiSTT Dictation.app"

if [ ! -f "$LIB/src/libwhisper.a" ]; then
    echo "Xato: whisper.cpp statik kutubxonalari topilmadi. Avval setup.sh ni ishga tushiring." >&2
    exit 1
fi

echo "[1/4] C bridge..."
clang -c "$SRC/whisper_bridge.c" -o "$SRC/whisper_bridge.o" -O2 \
    -I"$WC/include" -I"$WC/ggml/include"

echo "[2/4] Swift kompilyatsiya + linking..."
swiftc -O "$SRC/dictate.swift" "$SRC/whisper_bridge.o" \
    -import-objc-header "$SRC/Bridging.h" \
    "$LIB/src/libwhisper.a" \
    "$LIB/ggml/src/libggml.a" \
    "$LIB/ggml/src/libggml-base.a" \
    -Xlinker -force_load -Xlinker "$LIB/ggml/src/libggml-cpu.a" \
    -Xlinker -force_load -Xlinker "$LIB/ggml/src/ggml-metal/libggml-metal.a" \
    -framework Metal -framework MetalKit -framework Foundation \
    -framework Accelerate -framework AVFoundation -framework AppKit \
    -framework QuartzCore -framework CoreGraphics \
    -framework Carbon -framework ApplicationServices \
    -lc++ \
    -o "$SRC/RubaiSTTDictation"

echo "[3/4] .app bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$SRC/RubaiSTTDictation" "$APP/Contents/MacOS/RubaiSTTDictation"
cp "$ROOT/assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>RubaiSTT Dictation</string>
    <key>CFBundleDisplayName</key><string>RubaiSTT Dictation</string>
    <key>CFBundleIdentifier</key><string>com.rubaistt.dictation</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>RubaiSTTDictation</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSMicrophoneUsageDescription</key><string>Ovozingizni matnga o'girish uchun mikrofon kerak.</string>
</dict>
</plist>
PLIST

echo "[4/4] Ad-hoc imzolash..."
xattr -cr "$APP" 2>/dev/null || true
codesign --force --deep --sign - --entitlements "$SRC/entitlements.plist" "$APP" 2>/dev/null \
    || codesign --force --deep --sign - "$APP"

echo "Tayyor: $APP"
