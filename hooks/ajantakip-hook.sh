#!/bin/zsh
# AjanTakip — Claude Code hook'u. stdin'deki hook JSON'unu yerel AjanTakip uygulamasına iletir.
# Uygulama kapalıysa sessizce çıkar; Claude Code'u asla bekletmez veya bozmaz.

PORT="${AJANTAKIP_PORT:-}"
if [[ -z "$PORT" && -r "$HOME/.config/ajantakip/config" ]]; then
  PORT="$(sed -n 's/^port=\([0-9][0-9]*\)$/\1/p' "$HOME/.config/ajantakip/config" | head -n 1)"
fi
PORT="${PORT:-47823}"

curl -s -o /dev/null --max-time 0.3 -X POST --data-binary @- \
  -H "Content-Type: application/json" \
  -H "X-Cmux-Workspace: ${CMUX_WORKSPACE_ID:-}" \
  -H "X-Cmux-Surface: ${CMUX_SURFACE_ID:-}" \
  -H "X-Claude-Pid: ${CMUX_CLAUDE_PID:-$PPID}" \
  "http://127.0.0.1:${PORT}/event" 2>/dev/null || true
exit 0
