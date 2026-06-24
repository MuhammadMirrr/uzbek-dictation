#!/bin/bash
# RubaiSTT Dictation — bir buyruqli o'rnatuvchi (macOS, Apple Silicon).
#   curl -fsSL .../setup.sh | bash    yoki     ./setup.sh
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
WC="$ROOT/whisper.cpp"
MODELDIR="$HOME/rubai-stt/models"
MODEL="$MODELDIR/ggml-rubaistt.bin"
# Tayyor ggml model (GitHub Release). Bo'sh bo'lsa — HF'dan konversiya qilinadi.
MODEL_URL="https://github.com/MuhammadMirrr/uzbek-dictation/releases/download/v1.0/ggml-rubaistt.bin"

echo "==> RubaiSTT Dictation o'rnatilmoqda"

# 1) Talablar
if ! xcode-select -p >/dev/null 2>&1; then
    echo "Xcode Command Line Tools kerak. O'rnatish: xcode-select --install" >&2; exit 1
fi
if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew kerak: https://brew.sh" >&2; exit 1
fi
command -v cmake  >/dev/null 2>&1 || { echo "==> cmake o'rnatilmoqda";  brew install cmake; }
command -v ffmpeg >/dev/null 2>&1 || { echo "==> ffmpeg o'rnatilmoqda"; brew install ffmpeg; }

# 2) whisper.cpp (Metal, statik)
if [ ! -f "$WC/build-static/src/libwhisper.a" ]; then
    echo "==> whisper.cpp klonlash va build (Metal)..."
    [ -d "$WC" ] || git clone --depth 1 https://github.com/ggml-org/whisper.cpp.git "$WC"
    cmake -S "$WC" -B "$WC/build-static" \
        -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DBUILD_SHARED_LIBS=OFF \
        -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_TESTS=OFF -DGGML_BLAS=OFF
    cmake --build "$WC/build-static" --config Release -j --target whisper
fi

# 3) Model — avval release'dan (tez), bo'lmasa HuggingFace'dan (har doim ishlaydi)
if [ ! -f "$MODEL" ]; then
    mkdir -p "$MODELDIR"
    if [[ "$MODEL_URL" == http* ]] && curl -fL --progress-bar -o "$MODEL" "$MODEL_URL"; then
        echo "==> Model release'dan yuklandi ✓"
    else
        echo "==> Release'dan olinmadi — HuggingFace'dan yuklab konversiya qilinmoqda"
        echo "    (ochiq model, token shart emas; biroz vaqt oladi)..."
        rm -f "$MODEL"
        bash "$ROOT/scripts/convert_model.sh"
    fi
fi

# 4) Ilovani build qilish
echo "==> Ilova build qilinmoqda..."
bash "$ROOT/src/build.sh"

# 5) Avto-ishga tushish (login'da, open orqali — TCC to'g'ri bog'lanishi uchun)
PLIST="$HOME/Library/LaunchAgents/com.rubaistt.dictation.plist"
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.rubaistt.dictation</string>
  <key>ProgramArguments</key>
  <array><string>/usr/bin/open</string><string>$HOME/Applications/RubaiSTT Dictation.app</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><false/>
</dict></plist>
PL
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

echo ""
echo "✅ O'rnatildi! Menyu-bardagi 🎙️ ikonkani ko'rasiz."
echo ""
echo "OXIRGI QADAM — Accessibility ruxsati (⌘V yuborish uchun):"
echo "  System Settings > Privacy & Security > Accessibility"
echo "  → 'RubaiSTT Dictation' ni qo'shing va yoqing"
echo ""
echo "Ishlatish: istalgan joyda  ⌃⌥D  → gapiring → ⌃⌥D"
