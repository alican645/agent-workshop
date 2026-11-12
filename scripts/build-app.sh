#!/bin/zsh
# AjanTakip.app paketini oluşturur. `--install` verilirse ~/Applications'a kopyalar.
set -euo pipefail
cd "${0:A:h}/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/AjanTakip"
APP=build/AjanTakip.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/AjanTakip"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp hooks/ajantakip-hook.sh "$APP/Contents/Resources/ajantakip-hook.sh"
codesign -s - --force "$APP" >/dev/null
echo "Oluşturuldu: $APP"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/AjanTakip.app"
  cp -R "$APP" "$HOME/Applications/AjanTakip.app"
  echo "Kuruldu: $HOME/Applications/AjanTakip.app"
fi
