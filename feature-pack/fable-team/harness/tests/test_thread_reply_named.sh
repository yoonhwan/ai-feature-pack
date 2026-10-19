#!/usr/bin/env bash
# test_thread_reply_named.sh — r414: `byz_thread_post.py reply --thread <이름>` 뿌리 ts 를 도구가 소유(등록부 slack-threads.json)
# + ft-successor-open.sh desk·planner 본문 `--ts <슬랙 ts>` 손 복사 REJECT. 가짜 슬랙(--slack-base 로컬 서버) + 임시 폴더만 — 실제 슬랙·홈·명부 쓰기 0.
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1   # R201: 추적 사본 원본을 직접 부른다
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../../harness/kit/slack-mirror"
SO="$HERE/../../harness/kit/fable-team/bin/ft-successor-open.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

TMP="$(mktemp -d)"; SRV=""
trap '[ -n "$SRV" ] && kill "$SRV" 2>/dev/null; rm -rf "$TMP"' EXIT
POSTS="$TMP/posts.jsonl"; REG="$TMP/state/slack-threads.json"; : > "$POSTS"
printf 'YOONHWAN_BOT_TOKEN=x\n' > "$TMP/tok"; printf '오늘 보고 한 줄\n' > "$TMP/body.txt"
# 가짜 슬랙: chat.postMessage 요청 본문을 한 줄씩 기록하고 ts 를 1씩 올려 돌려준다
python3 - "$POSTS" "$TMP/port" <<'PY' &
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
log, portf, n = sys.argv[1], sys.argv[2], [0]
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        n[0] += 1; ts = f"1800000000.{n[0]:06d}"
        with open(log, "a") as f: f.write(json.dumps({"ts": ts, **body}, ensure_ascii=False) + "\n")
        raw = json.dumps({"ok": True, "ts": ts}).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(raw))); self.end_headers(); self.wfile.write(raw)
s = HTTPServer(("127.0.0.1", 0), H); open(portf, "w").write(str(s.server_port)); s.serve_forever()
PY
SRV=$!
for _ in $(seq 50); do [ -s "$TMP/port" ] && break; sleep 0.1; done
BASE="http://127.0.0.1:$(cat "$TMP/port")"

reply() { # reply <인자…> — 출력 $TMP/out · rc $RC
  env FT_SLACK_THREADS="$REG" FT_ROOT="$TMP" python3 "$KIT/byz_thread_post.py" reply --token-file "$TMP/tok" --slack-base "$BASE" \
      --text-file "$TMP/body.txt" "$@" > "$TMP/out" 2>&1; RC=$?
}
posts() { wc -l < "$POSTS" | tr -d ' '; }
last() { tail -1 "$POSTS" | python3 -c "import json,sys;print(json.load(sys.stdin).get('$1',''))"; }
regf() { python3 -c "import json,sys;d=json.load(open('$REG'))['desk'];print(d$1)"; }
TODAY="$(TZ=Asia/Seoul date +%F)"

# ⓐ 등록부 없음 → 뿌리 글 1건(`[desk 보고 <오늘>]`) + 등록 + 답글 1건(thread_ts = 그 뿌리)
reply --thread desk --channel C9DESK
root="$(head -1 "$POSTS" | python3 -c 'import json,sys;print(json.load(sys.stdin)["ts"])')"
first="$(head -1 "$POSTS" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["channel"], d["text"], d.get("thread_ts",""))')"
{ [ "$RC" = 0 ] && [ "$(posts)" = 2 ] && [ "$first" = "C9DESK [desk 보고 $TODAY] " ] && [ "$(last thread_ts)" = "$root" ] \
  && [ "$(last channel)" = C9DESK ] && [ "$(regf "['root_ts']")" = "$root" ] && [ "$(regf "['date']")" = "$TODAY" ] && [ "$(regf "['channel']")" = C9DESK ]; } \
  && ok "ⓐ 등록부 없음 → 뿌리 1 + 등록 + 답글 1(thread_ts=뿌리) rc0" || bad "ⓐ rc=$RC posts=$(cat "$POSTS") out=$(cat "$TMP/out")"

# ⓑ 같은 날 재호출(--channel 없이) → 뿌리 0 · 답글 1 · 등록부 그대로
before="$(cat "$REG")"; reply --thread desk
{ [ "$RC" = 0 ] && [ "$(posts)" = 3 ] && [ "$(last thread_ts)" = "$root" ] && [ "$(last channel)" = C9DESK ] && [ "$(cat "$REG")" = "$before" ]; } \
  && ok "ⓑ 같은 날 → 뿌리 0 · 답글 1 · 등록부 불변" || bad "ⓑ rc=$RC posts=$(posts) out=$(cat "$TMP/out")"

# ⓒ 등록부 날짜 ≠ 오늘 → 새 뿌리 1 + 등록부 갱신 · 옛 뿌리는 history
python3 -c "import json;p='$REG';d=json.load(open(p));d['desk']['date']='2000-01-01';json.dump(d,open(p,'w'))"
reply --thread desk
new="$(regf "['root_ts']")"
{ [ "$RC" = 0 ] && [ "$(posts)" = 5 ] && [ "$new" != "$root" ] && [ "$(last thread_ts)" = "$new" ] && [ "$(regf "['date']")" = "$TODAY" ] \
  && [ "$(regf "['history'][-1]['root_ts']")" = "$root" ] && [ "$(regf "['history'][-1]['date']")" = 2000-01-01 ]; } \
  && ok "ⓒ 날짜 바뀜 → 새 뿌리 1 + 등록부 갱신 · 옛 뿌리 history" || bad "ⓒ rc=$RC reg=$(cat "$REG") out=$(cat "$TMP/out")"

# ⓓ --ts 와 --thread 동시 = usage rc2 · 둘 다 없음 = rc2 · --ts 만 = 기존 동작(기본 채널 · thread_ts 그대로 · 등록부 불변)
n="$(posts)"; reply --ts 1700000000.000100 --thread desk; r1=$RC
reply; r2=$RC
before="$(cat "$REG")"; reply --ts 1700000000.000100
{ [ "$r1" = 2 ] && [ "$r2" = 2 ] && [ "$RC" = 0 ] && [ "$(posts)" = $((n+1)) ] && [ "$(last thread_ts)" = 1700000000.000100 ] \
  && [ "$(last channel)" = C0C6MJGRR89 ] && [ "$(cat "$REG")" = "$before" ]; } \
  && ok "ⓓ --ts+--thread·없음 = rc2 · --ts 만 = 기존 동작 불변" || bad "ⓓ r1=$r1 r2=$r2 rc=$RC last=$(tail -1 "$POSTS") out=$(cat "$TMP/out")"

# ⓓ-2 등록부 없는 이름에 --channel 없음 = rc1 · 게시 0 / 이름 꼴 위반 = rc1 · 게시 0
n="$(posts)"; reply --thread planner; r1=$RC; reply --thread 'Desk!' --channel C9DESK
{ [ "$r1" = 1 ] && [ "$RC" = 1 ] && [ "$(posts)" = "$n" ]; } \
  && ok "ⓓ-2 채널 모름·이름 꼴 위반 → rc1 · 게시 0" || bad "ⓓ-2 r1=$r1 rc=$RC posts=$(posts)"

# ⓓ-3 본문이 post_guard 에 걸리면 뿌리·등록부 불변(새 이름 · 날짜 바뀐 경우 모두 뿌리 0)
n="$(posts)"; printf '경로 /Users/x\n' > "$TMP/body.txt"; reply --thread ops --channel C9DESK
{ [ "$RC" = 1 ] && [ "$(posts)" = "$n" ] && python3 -c "import json,sys;sys.exit('ops' in json.load(open('$REG')))"; } \
  && ok "ⓓ-3 본문 거부 → 뿌리 0 · 등록부 불변" || bad "ⓓ-3 rc=$RC posts=$(posts) reg=$(cat "$REG")"

# ⓔ ft-successor-open.sh — desk·planner 후계 본문의 `--ts <슬랙 ts>` = REJECT · 열기 0 / --thread 꼴·다른 역할 = 통과
FAKE="$TMP/fakebin"; LOG="$TMP/calls.log"; REPO="$TMP/repo"; mkdir -p "$FAKE" "$REPO"; git -C "$REPO" init -q
mkstub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$FAKE/$1"; chmod +x "$FAKE/$1"; }
mkstub tmux  'case "$1" in has-session) exit 0;; list-panes) echo 4242;; display-message) echo "$PANE_CWD";; esac; exit 0'
mkstub tmuxc 'echo "tmuxc $*" >> "$LOG"; exit 0'
mkstub pgrep 'case "$*" in "-a -x claude"|"-a -x codex") exec "$SENSORS/pgrep" "$@";; esac; echo 5555; exit 0'
mkstub send  'echo send >> "$LOG"; echo "QUEUED seq=777 to=$1 pending=1 doorbell=sent"; exit 0'
mkstub mbox  'exit 0'
mkstub reach 'exit 0'
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$TMP/sensors" ok; SENSORS="$TMP/sensors/fake-sensors"; RES="$FT_RES_ROOT"
so() { # so <구> <후계> <본문 4번째 줄>
  printf '골 1\n골 2\n골 3\n%s\n' "$3" > "$TMP/so-body.txt"; : > "$LOG"
  env HOME="$TMP/home" PANE_CWD="$TMP/pane" PATH="$FAKE:$PATH" LOG="$LOG" FT_SO_POLL=0 FT_SO_WAIT_MAX=2 FT_RES_ROOT="$RES" SENSORS="$SENSORS" \
      FT_SEND_VERIFIED="$FAKE/send" FT_MBOX_SH="$FAKE/mbox" FT_REACH_CHECK="$FAKE/reach" \
      bash "$SO" "$1" "$REPO" --name "$2" --agent claude --model 'claude-opus-5-5[1m]' --body-file "$TMP/so-body.txt" > "$TMP/out" 2>&1; RC=$?
}
TSLINE='5. cd ~/.hermes/scripts; timeout 9 python3 byz_thread_post.py reply --channel C0C9GRFHJE5 --ts 1792148660.782579 --text-file f'
so 'byz-planner-desk-claude#20' 'byz-planner-desk-claude#21' "$TSLINE"
{ [ "$RC" = 1 ] && grep -q 'REJECT 본문에 슬랙 ts 손 복사' "$TMP/out" && ! grep -q tmuxc "$LOG"; } \
  && ok "ⓔ desk 본문 --ts 손 복사 → REJECT · 열기 0" || bad "ⓔ desk rc=$RC out=$(cat "$TMP/out")"
so 'byz-planner-master-claude#7' 'byz-planner-planner-claude#8' "$TSLINE"
{ [ "$RC" = 1 ] && grep -q 'REJECT 본문에 슬랙 ts' "$TMP/out"; } && ok "ⓔ planner 본문 --ts → REJECT" || bad "ⓔ planner rc=$RC out=$(cat "$TMP/out")"
so 'byz-planner-desk-claude#20' 'byz-planner-desk-claude#21' '5. python3 byz_thread_post.py reply --thread desk --text-file f'
{ ! grep -q 'REJECT 본문에 슬랙 ts' "$TMP/out" && grep -q tmuxc "$LOG"; } && ok "ⓔ desk --thread 꼴 → 통과(열기 진행)" || bad "ⓔ thread rc=$RC out=$(cat "$TMP/out")"
so 'byz-t-arch-claude#1' 'byz-t-arch-claude#2' "$TSLINE"
{ ! grep -q 'REJECT 본문에 슬랙 ts' "$TMP/out" && grep -q tmuxc "$LOG"; } && ok "ⓔ 다른 역할 → 통과" || bad "ⓔ other rc=$RC out=$(cat "$TMP/out")"

# 600/300 초 상한 0 (바꾼 파일)
! grep -nE '\b(600|300)\b' "$KIT/thread_post_update.py" "$KIT/thread_post_args.py" && ok "600/300 0" || bad "600/300 발견"

[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
