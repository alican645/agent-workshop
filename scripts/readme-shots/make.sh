#!/bin/zsh
# README görsellerini yeniden üretir: docs/images/workshop.gif ve docs/images/balloon.png
set -euo pipefail
cd "${0:A:h}/../.."
T=$(mktemp -d)
swiftc -O scripts/readme-shots/shot.swift -o "$T/shot"
W=Sources/Atolye/Web
"$T/shot" "$PWD/$W" scripts/readme-shots/demo.json "$W/i18n/en.json" "$T"
ffmpeg -loglevel error -y -framerate 12 -i "$T/f%03d.png" \
  -vf "scale=800:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" \
  -loop 0 docs/images/workshop.gif
cp "$T/balloon.png" docs/images/balloon.png
echo "docs/images güncellendi"
