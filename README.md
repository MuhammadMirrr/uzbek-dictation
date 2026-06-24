# 🎙️ RubaiSTT Dictation — O'zbekcha ovozli yozuv (macOS)

Istalgan ilovada (Telegram, Messages, brauzer, hujjat — qayerda kursor bo'lsa) **⌃⌥D** bosib o'zbekcha gapiring — matn avtomatik o'sha joyga lotin alifbosida yoziladi.

macOS'ning o'rnatilgan diktovkasi kabi, lekin **o'zbek tili uchun maxsus**, **butunlay oflayn** (internetsiz), va **bepul**.

> System-wide Uzbek speech-to-text dictation for macOS. Press **⌃⌥D** anywhere, speak Uzbek, and the transcribed text is typed into the focused field. Powered by the [rubaiSTT](https://huggingface.co/islomov/rubaistt_v2_medium) model running locally via [whisper.cpp](https://github.com/ggml-org/whisper.cpp) with Metal acceleration. Fully offline.

---

## ✨ Xususiyatlar / Features

- 🌐 **Tizim bo'ylab** — istalgan ilovada ishlaydi (global hotkey **⌃⌥D**)
- 🇺🇿 **O'zbek tiliga maxsus** — `rubaiSTT v2 medium` modeli, lotin alifbosi
- ⚡ **Metal tezlashtirish** — Apple Silicon GPU'da tez ishlaydi
- 🔌 **To'liq oflayn** — hech qanday server/internet kerak emas, ovoz qurilmangizdan chiqmaydi
- 🪶 **Yengil** — menyu-bar ilovasi; model 3 daqiqa ishlatilmasa RAM'dan bo'shaydi

## 📋 Talablar / Requirements

- macOS 13+ (**Apple Silicon** — M1/M2/M3/M4/M5)
- [Homebrew](https://brew.sh)
- Xcode Command Line Tools (`xcode-select --install`)
- ~2 GB disk (model 1.5 GB)

## 🚀 O'rnatish / Install

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

## ⚠️ Eslatma / Notes

- Ilova **ad-hoc imzolangan** (Apple Developer sertifikati yo'q). Shuning uchun manbadan build qilinadi — `setup.sh` lokal build qiladi, Gatekeeper bloklamaydi.
- Faqat **Apple Silicon** (Metal). Intel Mac'lar sinalmagan.

## 🛠 Texnik tafsilotlar

- **Model:** [`islomov/rubaistt_v2_medium`](https://huggingface.co/islomov/rubaistt_v2_medium) → ggml (f16) ga o'girilgan
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
