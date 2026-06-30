#!/bin/bash
# RubaiSTT Dictation — tarqatish uchun imzolangan + notarize qilingan DMG yasaydi.
#
# Talab: Apple Developer account, "Developer ID Application" sertifikati keychain'da.
# Notarize uchun bir martalik (keychain profil) sozlash:
#   xcrun notarytool store-credentials rubai-notary \
#       --apple-id "siz@example.com" --team-id "ABCDE12345" \
#       --password "xxxx-xxxx-xxxx-xxxx"   # app-specific parol (appleid.apple.com)
#
# Ishlatish:
#   ./scripts/release.sh
# Ixtiyoriy o'zgaruvchilar:
#   DEV_ID="Developer ID Application: Ism (TEAMID)"   # bo'sh bo'lsa avtomatik topiladi
#   NOTARY_PROFILE="rubai-notary"                      # bo'sh bo'lsa notarize o'tkazib yuboriladi
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$HOME/Applications/RubaiSTT Dictation.app"
ENT="$ROOT/src/entitlements.plist"
MODEL="$HOME/rubai-stt/models/ggml-rubaistt.bin"
DIST="$ROOT/dist"
DMG="$DIST/RubaiSTT-Dictation.dmg"
VOLNAME="RubaiSTT Diktovka"
NOTARY_PROFILE="${NOTARY_PROFILE:-rubai-notary}"

echo "==> [1/7] Ilova build qilinmoqda..."
bash "$ROOT/src/build.sh"

echo "==> [2/7] Model .app ichiga joylanmoqda (to'liq offline)..."
if [ ! -f "$MODEL" ]; then
    echo "Xato: model topilmadi: $MODEL"
    echo "      Avval setup.sh ni ishga tushiring (model yuklab oladi)." >&2
    exit 1
fi
cp "$MODEL" "$APP/Contents/Resources/ggml-rubaistt.bin"

echo "==> [3/7] Developer ID sertifikati aniqlanmoqda..."
if [ -z "$DEV_ID" ]; then
    DEV_ID=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/')
fi
if [ -z "$DEV_ID" ]; then
    echo "Xato: 'Developer ID Application' sertifikati topilmadi." >&2
    echo "      Xcode > Settings > Accounts orqali yarating yoki DEV_ID= bering." >&2
    exit 1
fi
echo "    Sertifikat: $DEV_ID"

echo "==> [4/7] Hardened runtime bilan imzolanmoqda..."
xattr -cr "$APP" 2>/dev/null || true
# Avval ichki ikkilik fayl, keyin bundle
codesign --force --options runtime --timestamp \
    --entitlements "$ENT" --sign "$DEV_ID" \
    "$APP/Contents/MacOS/RubaiSTTDictation"
codesign --force --options runtime --timestamp \
    --entitlements "$ENT" --sign "$DEV_ID" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "==> [5/7] Notarize..."
mkdir -p "$DIST"
# Notarize profili bor-yo'qligini bir marta aniqlaymiz (keyin DMG uchun ham ishlatamiz)
HAVE_NOTARY=0
if security find-generic-password -s "com.apple.gke.notary.tool" -a "$NOTARY_PROFILE" >/dev/null 2>&1; then
    HAVE_NOTARY=1
fi
if [ "$HAVE_NOTARY" = "1" ]; then
    ZIP="$DIST/RubaiSTT-notarize.zip"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "    Apple'ga yuborilmoqda (bir necha daqiqa)..."
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    rm -f "$ZIP"
    echo "    Notarize ✓ (ilovaga staple qilindi)"
else
    echo "    ⚠️  '$NOTARY_PROFILE' keychain profili topilmadi — notarize o'tkazib yuborildi."
    echo "       (Imzolangan, lekin notarize qilinmagan DMG ham yasaladi.)"
fi

echo "==> [6/7] DMG fon rasmi..."
BG="$ROOT/assets/dmg-bg.png"
swift "$ROOT/scripts/make_dmg_bg.swift" "$BG"

echo "==> [7/7] DMG yasalmoqda..."
rm -f "$DMG"
if command -v create-dmg >/dev/null 2>&1; then
    create-dmg \
        --volname "$VOLNAME" \
        --background "$BG" \
        --window-pos 200 120 --window-size 600 400 \
        --icon-size 110 \
        --icon "RubaiSTT Dictation.app" 165 205 \
        --app-drop-link 435 205 \
        --hide-extension "RubaiSTT Dictation.app" \
        --no-internet-enable \
        "$DMG" "$APP"
else
    echo "    'create-dmg' yo'q (chiroyli fon uchun:  brew install create-dmg)."
    echo "    Oddiy DMG yasalmoqda..."
    STAGE="$DIST/stage"; rm -rf "$STAGE"; mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
    rm -rf "$STAGE"
fi

# DMG'ni ham imzolab, notarize qilamiz (agar profil bo'lsa)
codesign --force --sign "$DEV_ID" "$DMG" 2>/dev/null || true
if [ "$HAVE_NOTARY" = "1" ]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
fi

echo ""
echo "✅ Tayyor:  $DMG"
echo "   Tekshirish:  spctl -a -t open --context context:primary-signature \"$DMG\""
echo "   Foydalanuvchi shunchaki ochib, ilovani Applications'ga tortadi."
