#!/bin/bash
# RubaiSTT Dictation — bir buyruqli o'rnatuvchi (macOS, Apple Silicon).
#   curl -fsSL .../setup.sh | bash    yoki     ./setup.sh
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
WC="$ROOT/whisper.cpp"
MODELDIR="$HOME/rubai-stt/models"
MODEL="$MODELDIR/ggml-rubaistt.bin"       # q8_0 (yengil ~820MB) — ilova shu nomdan o'qiydi
MODEL_F16="$MODELDIR/ggml-rubaistt-f16.bin"
# Tayyor q8_0 ggml model (GitHub Release). Bo'sh bo'lsa — HF'dan konversiya + quant qilinadi.
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

# 2b) x86_64 (Intel) statik — universal ilova uchun (CPU, Metal'siz). Faqat Apple Silicon'da cross-compile.
if [ "$(uname -m)" = "arm64" ] && [ ! -f "$WC/build-x64/src/libwhisper.a" ]; then
    echo "==> whisper.cpp x86_64 (Intel, CPU) build..."
    cmake -S "$WC" -B "$WC/build-x64" \
        -DCMAKE_OSX_ARCHITECTURES=x86_64 -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
        -DGGML_NATIVE=OFF -DGGML_METAL=OFF -DBUILD_SHARED_LIBS=OFF \
        -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_TESTS=OFF -DGGML_BLAS=OFF
    cmake --build "$WC/build-x64" --config Release -j --target whisper
fi

# 3) Model — avval release'dan tayyor q8_0 (tez), bo'lmasa HuggingFace'dan + quant
if [ ! -f "$MODEL" ]; then
    mkdir -p "$MODELDIR"
    if [[ "$MODEL_URL" == http* ]] && curl -fL --progress-bar -o "$MODEL" "$MODEL_URL"; then
        echo "==> Model (q8_0, yengil) release'dan yuklandi ✓"
    else
        echo "==> Release'dan olinmadi — HuggingFace'dan yuklab konversiya qilinmoqda"
        echo "    (ochiq model, token shart emas; biroz vaqt oladi)..."
        rm -f "$MODEL"
        # f16 ga o'giradi -> $MODEL_F16
        bash "$ROOT/scripts/convert_model.sh"
        # quantize vositasini build qilib, f16 -> q8_0 ga siqamiz (kamroq RAM/disk)
        echo "==> Model q8_0 ga quantize qilinmoqda (kamroq RAM)..."
        if [ ! -x "$WC/build-quant/bin/whisper-quantize" ]; then
            cmake -S "$WC" -B "$WC/build-quant" \
                -DWHISPER_BUILD_EXAMPLES=ON -DWHISPER_BUILD_TESTS=OFF \
                -DGGML_METAL=OFF -DGGML_BLAS=OFF >/dev/null
            cmake --build "$WC/build-quant" --target whisper-quantize -j
        fi
        "$WC/build-quant/bin/whisper-quantize" "$MODEL_F16" "$MODEL" q8_0
        rm -f "$MODEL_F16"   # f16 zaxira kerak emas — diskni bo'shatamiz
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
