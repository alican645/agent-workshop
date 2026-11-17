#!/bin/zsh
# Agent Workshop.app paketini oluşturur. `--install` verilirse ~/Applications'a kopyalar.
set -euo pipefail
cd "${0:A:h}/.."

swift build -c release --product Atolye
swift build -c release --product atolye-host
BIN="$(swift build -c release --show-bin-path)/Atolye"
HOSTBIN="$(swift build -c release --show-bin-path)/atolye-host"
APP="build/Agent Workshop.app"

rm -rf "$APP" build/Atölye.app # eski ad
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/en.lproj" "$APP/Contents/Resources/tr.lproj"
cp "$BIN" "$APP/Contents/MacOS/Atolye"
cp "$HOSTBIN" "$APP/Contents/MacOS/atolye-host"
cp Resources/Atolye-Info.plist "$APP/Contents/Info.plist"
cp -R Sources/Atolye/Web "$APP/Contents/Resources/Web"
cp Resources/Atolye.icns "$APP/Contents/Resources/Atolye.icns"
codesign -s - --force "$APP" >/dev/null
echo "Oluşturuldu: $APP"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/Atölye.app" "$HOME/Applications/Agent Workshop.app"
  cp -R "$APP" "$HOME/Applications/Agent Workshop.app"
  echo "Kuruldu: $HOME/Applications/Agent Workshop.app"
fi
