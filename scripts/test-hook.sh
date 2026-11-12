#!/bin/zsh
# hooks/ajantakip-hook.sh için uçtan uca test.
set -u
cd "${0:A:h}/.."
HOOK=hooks/ajantakip-hook.sh
fail() { echo "FAIL: $1"; exit 1; }
[[ -x $HOOK ]] || fail "$HOOK yok veya çalıştırılabilir değil"

# 1) Dinleyen yokken: exit 0 ve < 0.5 sn
start=$(perl -MTime::HiRes=time -e 'print time')
echo '{"session_id":"t"}' | AJANTAKIP_PORT=47999 $HOOK
code=$?
end=$(perl -MTime::HiRes=time -e 'print time')
[[ $code -eq 0 ]] || fail "dinleyen yokken çıkış kodu $code"
(( end - start < 0.5 )) || fail "dinleyen yokken süre $((end - start)) sn"

# 2) Yakalayan sunucu ile başlık ve gövde kontrolü
TMP=$(mktemp -d)
cat > $TMP/srv.py <<'PY'
import http.server, json, sys
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        json.dump({"path": self.path, "ws": self.headers.get("X-Cmux-Workspace"),
                   "sf": self.headers.get("X-Cmux-Surface"), "pid": self.headers.get("X-Claude-Pid"),
                   "body": body.decode()}, open(sys.argv[1], "w"))
        self.send_response(204); self.end_headers()
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", 47998), H).handle_request()
PY
python3 -I $TMP/srv.py $TMP/out.json &
SRV=$!
sleep 0.3
BODY='{"session_id":"abc","hook_event_name":"Stop"}'
print -rn -- "$BODY" | CMUX_WORKSPACE_ID=W CMUX_SURFACE_ID=S CMUX_CLAUDE_PID=42 AJANTAKIP_PORT=47998 $HOOK
wait $SRV
python3 -I - "$TMP/out.json" "$BODY" <<'PY' || fail "yakalanan istek beklenenden farklı"
import json, sys
d = json.load(open(sys.argv[1]))
exp = {"path": "/event", "ws": "W", "sf": "S", "pid": "42", "body": sys.argv[2]}
assert d == exp, (d, exp)
PY
rm -rf $TMP
echo OK
