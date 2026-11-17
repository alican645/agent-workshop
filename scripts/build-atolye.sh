#!/bin/zsh
# Atölye.app paketini oluşturur. `--install` verilirse ~/Applications'a kopyalar.
set -euo pipefail
cd "${0:A:h}/.."

swift build -c release --product Atolye
swift build -c release --product atolye-host
BIN="$(swift build -c release --show-bin-path)/Atolye"
HOSTBIN="$(swift build -c release --show-bin-path)/atolye-host"
APP=build/Atölye.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Atolye"
cp "$HOSTBIN" "$APP/Contents/MacOS/atolye-host"
cp Resources/Atolye-Info.plist "$APP/Contents/Info.plist"
cp -R Sources/Atolye/Web "$APP/Contents/Resources/Web"
cp Resources/Atolye.icns "$APP/Contents/Resources/Atolye.icns"
codesign -s - --force "$APP" >/dev/null
echo "Oluşturuldu: $APP"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/Atölye.app"
  cp -R "$APP" "$HOME/Applications/Atölye.app"
  echo "Kuruldu: $HOME/Applications/Atölye.app"
fi
