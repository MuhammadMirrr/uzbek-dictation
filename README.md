# 🎙️ RubaiSTT Dictation — O'zbekcha ovozli yozuv (macOS)

Istalgan ilovada (Telegram, Messages, brauzer, hujjat — qayerda kursor bo'lsa) **⌃⌥D** bosib o'zbekcha gapiring — matn avtomatik o'sha joyga lotin alifbosida yoziladi.

macOS'ning o'rnatilgan diktovkasi kabi, lekin **o'zbek tili uchun maxsus**, **butunlay oflayn** (internetsiz), va **bepul**.

> System-wide Uzbek speech-to-text dictation for macOS. Press **⌃⌥D** anywhere, speak Uzbek, and the transcribed text is typed into the focused field. Powered by the [rubaiSTT](https://huggingface.co/islomov/rubaistt_v2_medium) model running locally via [whisper.cpp](https://github.com/ggml-org/whisper.cpp) with Metal acceleration. Fully offline.

---

## ✨ Xususiyatlar / Features

- 🌐 **Tizim bo'ylab** — istalgan ilovada ishlaydi (global hotkey **⌃⌥D**)
- 🇺🇿 **O'zbek tiliga maxsus** — `rubaiSTT v2 medium` modeli, lotin alifbosi
- ⚡ **Metal tezlashtirish** — Apple Silicon GPU'da tez · Intel'da CPU bilan ishlaydi (universal)
- 🔌 **To'liq oflayn** — hech qanday server/internet kerak emas, ovoz qurilmangizdan chiqmaydi
- 🪶 **Yengil** — menyu-bar ilovasi; model 3 daqiqa ishlatilmasa RAM'dan bo'shaydi
- ⌨️ **Sozlanadigan tugma** — diktovka tugmasini Sozlamalar oynasidan o'zgartirish mumkin (standart ⌃⌥D)

## 📋 Talablar / Requirements

- macOS 13+ · **Universal** — Apple Silicon (M1–M5, Metal bilan tez) yoki Intel (CPU, sekinroq)
- [Homebrew](https://brew.sh)
- Xcode Command Line Tools (`xcode-select --install`)
- ~1 GB disk (model ~820 MB, q8_0)

## 🚀 O'rnatish / Install

### A) Tayyor ilova (oson) — DMG

1. **[⬇️ RubaiSTT-Dictation.dmg yuklab olish](https://github.com/MuhammadMirrr/uzbek-dictation/releases/download/v1.0/RubaiSTT-Dictation.dmg)** (~785 MB, model ichida)
2. DMG'ni oching va ilovani **Applications** papkasiga torting
3. Ilovani ishga tushiring — **Xush kelibsiz** oynasi ikkita ruxsatni (mikrofon + Accessibility) berishda yo'l-yo'riq ko'rsatadi

Model ilova ichida — **to'liq oflayn**, terminal kerak emas.

#### Birinchi ochish (muhim)

Ilova **Developer ID bilan imzolangan**, lekin hozircha notarize qilinmagan. Shuning uchun **birinchi marta** macOS ogohlantirishi mumkin (*"Apple cannot check it for malicious software"*). Bir martalik yechim:

- **macOS 13–14:** ilovaga **o'ng tugma (Control-click) → Open → Open**
- **macOS 15 (Sequoia):** ilovani oching → bloklanadi → **System Settings → Privacy & Security** → pastga tushing → **«Open Anyway» / «Все равно открыть»** → tasdiqlang

Bir marta shunday qilsangiz, keyin doim normal ochiladi.

### B) Manbadan build (developer)

```bash
git clone https://github.com/MuhammadMirrr/uzbek-dictation.git
cd uzbek-dictation
./setup.sh
```

`setup.sh` avtomatik: kerakli vositalarni o'rnatadi → whisper.cpp'ni Metal bilan build qiladi → modelni yuklaydi → ilovani build qilib o'rnatadi → login'da avto-ishga tushishni sozlaydi.

### Oxirgi qadam — Accessibility ruxsati

Matn avtomatik joylashishi uchun (⌘V yuborish) bir marta ruxsat bering:

1. **System Settings → Privacy & Security → Accessibility**
2. **"RubaiSTT Dictation"** ni qo'shing (`+`) va **yoqing** ✅

Birinchi yozishda **mikrofon** ruxsati ham so'raladi — ruxsat bering.

## 🎯 Ishlatish / Usage

1. Istalgan joyda kursorni yozish maydoniga qo'ying
2. **⌃⌥D** bosing → 🔴 gapiring → **⌃⌥D** yana bosing
3. Matn o'sha joyga yoziladi

Menyu-bardagi 🎙️ ikonadan ham boshqarish mumkin.

## 📦 Tarqatish / Release (developer)

Imzolangan + notarize qilingan DMG yasash:

```bash
# Bir martalik: notarize uchun keychain profil
xcrun notarytool store-credentials rubai-notary \
    --apple-id "siz@example.com" --team-id "TEAMID" \
    --password "xxxx-xxxx-xxxx-xxxx"   # app-specific parol

brew install create-dmg     # chiroyli DMG foni uchun (ixtiyoriy)
./scripts/release.sh        # build → Developer ID imzo → notarize → DMG
```

Natija: `dist/RubaiSTT-Dictation.dmg`. Skript "Developer ID Application" sertifikatini avtomatik topadi; model `.app` ichiga joylanadi.

## ⚠️ Eslatma / Notes

- Tayyor DMG **Developer ID bilan imzolangan** (hardened runtime). Notarize keyinroq qo'shiladi — shu sababli birinchi ochishda yuqoridagi bir martalik qadam kerak. Manbadan build (`setup.sh`) esa **ad-hoc imzolangan** (lokal, Gatekeeper bloklamaydi).
- App Store'ga **chiqmaydi** — tizim bo'ylab matn yozish (synthetic ⌘V) sandbox'da taqiqlangan; shuning uchun Developer ID orqali tarqatiladi.
- **Universal binary** — Apple Silicon (Metal GPU) va Intel (CPU). Intel'da sezilarli sekinroq, lekin ishlaydi.

## 🛠 Texnik tafsilotlar

- **Model:** [`islomov/rubaistt_v2_medium`](https://huggingface.co/islomov/rubaistt_v2_medium) → ggml **q8_0** (8-bit) ga siqilgan — ~820 MB, ~700 MB kamroq RAM, aniqlik deyarli o'zgarmaydi
- **Inference:** whisper.cpp + Metal, beam search (maksimal aniqlik)
- **Til:** `uz`, lotin alifbosi
- **UI:** Swift / AppKit, menyu-bar (LSUIElement), global hotkey Carbon orqali
- **Matn kiritish:** clipboard + ⌘V (CGEvent) — Accessibility ruxsati kerak

## 📄 Litsenziya

MIT (`LICENSE`). Model va whisper.cpp o'z litsenziyalari ostida.

## 🙏 Minnatdorchilik

- [rubaiSTT](https://huggingface.co/islomov/rubaistt_v2_medium) — Sardor Islomov (o'zbek STT modeli)
- [whisper.cpp](https://github.com/ggml-org/whisper.cpp) — Georgi Gerganov
- [OpenAI Whisper](https://github.com/openai/whisper)
