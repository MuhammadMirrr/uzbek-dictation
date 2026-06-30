#!/bin/bash
# RubaiSTT Dictation — native macOS ilovasini build qiladi.
# whisper.cpp statik kutubxonalari $ROOT/whisper.cpp/build-static da bo'lishi kerak
# (setup.sh buni avtomatik tayyorlaydi).
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SRC/.." && pwd)"
WC="$ROOT/whisper.cpp"
LIB_ARM="$WC/build-static"   # arm64 — Metal GPU
LIB_X64="$WC/build-x64"      # x86_64 — faqat CPU (Intel)
APP="$HOME/Applications/RubaiSTT Dictation.app"

if [ ! -f "$LIB_ARM/src/libwhisper.a" ]; then
    echo "Xato: whisper.cpp statik kutubxonalari topilmadi. Avval setup.sh ni ishga tushiring." >&2
    exit 1
fi

# Qaysi arxitekturalar build qilinadi: doim arm64; build-x64 mavjud bo'lsa — universal.
ARCHS=("arm64")
[ -f "$LIB_X64/src/libwhisper.a" ] && ARCHS+=("x86_64")

COMMON_FW="-framework Foundation -framework Accelerate -framework AVFoundation \
    -framework AppKit -framework QuartzCore -framework CoreGraphics \
    -framework Carbon -framework ApplicationServices"

echo "[1/4] Kompilyatsiya + linking (${ARCHS[*]})..."
EXES=()
for ARCH in "${ARCHS[@]}"; do
    if [ "$ARCH" = "arm64" ]; then
        LIB="$LIB_ARM"; TRIPLE="arm64-apple-macos13.0"
        # arm64 — Metal backend'ni force_load + Metal freymvorklari
        METAL="-Xlinker -force_load -Xlinker $LIB/ggml/src/ggml-metal/libggml-metal.a \
            -framework Metal -framework MetalKit"
    else
        LIB="$LIB_X64"; TRIPLE="x86_64-apple-macos13.0"; METAL=""
    fi
    echo "  -> $ARCH"
    clang -c "$SRC/whisper_bridge.c" -arch "$ARCH" -O2 \
        -I"$WC/include" -I"$WC/ggml/include" -o "$SRC/whisper_bridge.$ARCH.o"
    swiftc -O -target "$TRIPLE" "$SRC/dictate.swift" "$SRC/whisper_bridge.$ARCH.o" \
        -import-objc-header "$SRC/Bridging.h" \
        "$LIB/src/libwhisper.a" \
        "$LIB/ggml/src/libggml.a" \
        "$LIB/ggml/src/libggml-base.a" \
        -Xlinker -force_load -Xlinker "$LIB/ggml/src/libggml-cpu.a" \
        $METAL $COMMON_FW -lc++ \
        -o "$SRC/RubaiSTTDictation.$ARCH"
    EXES+=("$SRC/RubaiSTTDictation.$ARCH")
done

# Universal binarga birlashtirish (yoki bitta arxitektura)
if [ ${#EXES[@]} -gt 1 ]; then
    lipo -create "${EXES[@]}" -output "$SRC/RubaiSTTDictation"
    echo "  universal: $(lipo -archs "$SRC/RubaiSTTDictation")"
else
    cp "${EXES[0]}" "$SRC/RubaiSTTDictation"
fi
rm -f "$SRC"/whisper_bridge.*.o "$SRC"/RubaiSTTDictation.arm64 "$SRC"/RubaiSTTDictation.x86_64

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
