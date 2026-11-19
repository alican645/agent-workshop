#!/bin/zsh
# Agent Workshop.app paketini oluşturur. `--install` verilirse ~/Applications'a kopyalar.
set -euo pipefail
cd "${0:A:h}/.."

swift build -c release --product Atolye
swift build -c release --product atolye-host
swift build -c release --product atolye-hook
BIN="$(swift build -c release --show-bin-path)/Atolye"
HOSTBIN="$(swift build -c release --show-bin-path)/atolye-host"
HOOKBIN="$(swift build -c release --show-bin-path)/atolye-hook"
APP="build/Agent Workshop.app"

rm -rf "$APP" build/Atölye.app # eski ad
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/en.lproj" "$APP/Contents/Resources/tr.lproj"
cp "$BIN" "$APP/Contents/MacOS/Atolye"
cp "$HOSTBIN" "$APP/Contents/MacOS/atolye-host"
cp "$HOOKBIN" "$APP/Contents/MacOS/atolye-hook"
cp Resources/Atolye-Info.plist "$APP/Contents/Info.plist"
cp -R Sources/Atolye/Web "$APP/Contents/Resources/Web"
cp Resources/Atolye.icns "$APP/Contents/Resources/Atolye.icns"
# Sabit bir imza kimliği: Anahtar Zinciri uygulamayı derlemeler arasında aynı tanır, her açılışta şifre sormaz.
# CODESIGN_IDENTITY verilmezse ilk "Apple Development" kimliği; o da yoksa ad-hoc (o zaman her derlemede sorar).
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/{print $2; exit}')}"
IDENTITY="${IDENTITY:--}"
codesign -s "$IDENTITY" --force "$APP/Contents/MacOS/atolye-host" >/dev/null
codesign -s "$IDENTITY" --force "$APP/Contents/MacOS/atolye-hook" >/dev/null
codesign -s "$IDENTITY" --force "$APP" >/dev/null
echo "İmza: $IDENTITY"
echo "Oluşturuldu: $APP"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/Atölye.app" "$HOME/Applications/Agent Workshop.app"
  cp -R "$APP" "$HOME/Applications/Agent Workshop.app"
  echo "Kuruldu: $HOME/Applications/Agent Workshop.app"
fi
