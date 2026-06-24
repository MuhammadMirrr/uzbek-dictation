#!/bin/bash
# rubaiSTT modelini HuggingFace'dan yuklab, whisper.cpp ggml formatiga o'giradi.
# (Sekin va og'ir — torch kerak. Tezroq yo'l: setup.sh release'dan tayyor ggml yuklaydi.)
set -e
SRC="$(cd "$(dirname "$0")/../src" && pwd)"
ROOT="$(cd "$SRC/.." && pwd)"
WC="$ROOT/whisper.cpp"
OUT="$HOME/rubai-stt/models"
ENVDIR="$ROOT/.venv"
MODEL_ID="islomov/rubaistt_v2_medium"

mkdir -p "$OUT"
echo "[1/4] Python muhiti..."
python3 -m venv "$ENVDIR"
# shellcheck disable=SC1091
source "$ENVDIR/bin/activate"
pip install --quiet --upgrade pip
pip install --quiet torch transformers numpy huggingface_hub

echo "[2/4] Modelni yuklab olish ($MODEL_ID)..."
SNAP=$(python3 -c "from huggingface_hub import snapshot_download; print(snapshot_download('$MODEL_ID'))")

echo "[3/4] mel_filters.npz..."
mkdir -p "$ROOT/.assets/whisper/assets"
curl -sL -o "$ROOT/.assets/whisper/assets/mel_filters.npz" \
    https://github.com/openai/whisper/raw/main/whisper/assets/mel_filters.npz

echo "[4/4] ggml'ga o'girish..."
python3 "$WC/models/convert-h5-to-ggml.py" "$SNAP" "$ROOT/.assets" "$OUT"
mv "$OUT/ggml-model.bin" "$OUT/ggml-rubaistt.bin"
echo "Tayyor: $OUT/ggml-rubaistt.bin"
