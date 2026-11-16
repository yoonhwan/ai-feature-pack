#!/usr/bin/env bash
# test_news_reply_oppa_tag_r2108.sh — 보드 뉴스 답글의 오빠 태그 1개를 진짜 태그로 (r2108 · A1~A4).
#   ① --keep-mention 꼴 아님(u0ac2… · U1 · <@U…>) ∨ --ts 없이(--thread desk) → rc≠0 · 받은 글 0
#   ② --keep-mention U0AC2JF0M7D --ts → 받은 글에 `<@U0AC2JF0M7D>` 1개 · `&lt;@` 0
#   ③ 같은 태그 2 + 다른 UID 1 + <!channel> 1 → 첫 태그만 되돌림 · 원장 글의 `&lt;@UID&gt;` 글자 = 되돌림 0
#   ④ 원장 상태 글 mention(body 모듈 quiet) + 도구 태그 → 진짜 태그 1개(publish → 진짜 reply → 가짜 Slack)
#   ⑤ 인자 없음 → 받은 글 · 출력 꼴 · rc = 기준판과 같음(`&lt;@…&gt;`)
#   ⑥ ft-board-publish.sh → 가짜 TP argv: env 판 · 기본 판 · python 읽기 실패 판(인자 0 + WARN 1줄) · rc 0 · news-last 쓰임
#     읽기 실패 = 출력 없음 rc1 · 유효 UID 출력 + rc1(DA R1) · 9초 뒤 UID 출력(DA R2 · 7초 상한 → 9초 전에 끝남)
# 실 Slack · 실 토큰 · 실 원장 0 · sleep 0(포트 = fifo). R2108_HARNESS = 시험할 harness 폴더(기준판·변이 사본용).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HX="${R2108_HARNESS:-$HERE/..}"
KIT="$HX/kit/slack-mirror"; PUB="$HX/bin/ft-board-publish.sh"
U=U0AC2JF0M7D; TS=1794729663.977629
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

T="$(mktemp -d)"; SRV=""
trap '[ -n "$SRV" ] && kill "$SRV" 2>/dev/null; rm -rf "$T"' EXIT
mkdir -p "$T/ft/.fable-team" "$T/stub" "$T/py"; : > "$T/posts.jsonl"; mkfifo "$T/pf"
printf 'YOONHWAN_BOT_TOKEN=x\n' > "$T/tok"
python3 - "$T/posts.jsonl" "$T/pf" <<'PY' &
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
log, n = sys.argv[1], [0]
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _send(self, out):
        raw = json.dumps(out).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(raw))); self.end_headers(); self.wfile.write(raw)
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        n[0] += 1; ts = f"1800000000.{n[0]:06d}"
        with open(log, "a") as f: f.write(json.dumps({"ts": ts, **body}, ensure_ascii=False) + "\n")
        self._send({"ok": True, "ts": ts})
    def do_GET(self): self._send({"ok": True, "messages": []})
s = HTTPServer(("127.0.0.1", 0), H)
with open(sys.argv[2], "w") as f: f.write(str(s.server_port) + "\n")
s.serve_forever()
PY
SRV=$!
read -r PORT < "$T/pf"; BASE="http://127.0.0.1:$PORT"

posts() { wc -l < "$T/posts.jsonl" | tr -d ' '; }
last() { [ -s "$T/posts.jsonl" ] || return 0; tail -n 1 "$T/posts.jsonl" | python3 -c 'import json,sys; sys.stdout.write(json.loads(sys.stdin.read())["text"])'; }
cnt() { last | grep -oF -- "$1" | wc -l | tr -d ' '; }
reply() {  # reply <본문> <인자…> — 출력 $T/out · rc $RC
  printf '%s\n' "$1" > "$T/body.txt"; shift
  env FT_ROOT="$T/ft" FT_SLACK_THREADS="$T/reg.json" FT_SLACK_TOPIC_ONLY= python3 "$KIT/byz_thread_post.py" reply \
    --token-file "$T/tok" --slack-base "$BASE" --text-file "$T/body.txt" "$@" > "$T/out" 2>&1; RC=$?
}
B2="<@$U> 오빠 승인 대기 1건"

# ① 꼴 검사(A1)
for bad_uid in u0ac2jf0m7d U1 "<@$U>"; do
  n0="$(posts)"; reply "$B2" --no-status-head --ts "$TS" --keep-mention "$bad_uid"
  chk "① --keep-mention «${bad_uid}» → rc≠0 · 받은 글 0" '[ "$RC" != 0 ] && [ "$(posts)" = "$n0" ]'
done
n0="$(posts)"; reply "$B2" --thread desk --channel C0TEST --keep-mention "$U"
chk "① --thread desk + --keep-mention → rc≠0 · 받은 글 0(뿌리 글도 0)" '[ "$RC" != 0 ] && [ "$(posts)" = "$n0" ]'

# ② 되돌림(A2)
n0="$(posts)"; reply "$B2" --no-status-head --ts "$TS" --keep-mention "$U"
chk "② rc 0 · 받은 글 1" '[ "$RC" = 0 ] && [ "$(posts)" = $((n0 + 1)) ]'
chk "② 받은 글 «<@$U>» 1개 · «&lt;@» 0" '[ "$(cnt "<@$U>")" = 1 ] && [ "$(cnt "&lt;@")" = 0 ]'
chk "② 받은 글 = «<@$U> 오빠 승인 대기 1건»" '[ "$(last)" = "$B2" ]'

# ③ 첫 1개만(A2)
reply "$(printf '%s\n' "$B2" "<@$U> 다시" "<@U0ZZZZZZZZ> 남" "<!channel> 모두")" --no-status-head --ts "$TS" --keep-mention "$U"
chk "③ rc 0 · 첫 태그만 «<@$U>» · 둘째 «&lt;@$U&gt;»" '[ "$RC" = 0 ] && [ "$(cnt "<@$U>")" = 1 ] && [ "$(cnt "&lt;@$U&gt;")" = 1 ] && last | head -n 1 | grep -qxF "$B2"'
chk "③ 다른 UID · <!channel> = 중화 그대로 · 받은 글 «<» 1개" '[ "$(cnt "&lt;@U0ZZZZZZZZ&gt;")" = 1 ] && [ "$(cnt "&lt;!channel&gt;")" = 1 ] && [ "$(cnt "<")" = 1 ]'
reply "원장 글 &lt;@$U&gt; 그대로" --no-status-head --ts "$TS" --keep-mention "$U"
chk "③ 본문의 «&lt;@$U&gt;» 글자 → «&amp;lt;…» · 진짜 태그 0" '[ "$RC" = 0 ] && [ "$(cnt "<@")" = 0 ] && [ "$(cnt "&amp;lt;@$U&amp;gt;")" = 1 ]'

# ⑤ 인자 없음 = 지금과 같음(A3)
n0="$(posts)"; reply "$B2" --no-status-head --ts "$TS"
chk "⑤ 인자 없음 → rc 0 · 받은 글 = «&lt;@$U&gt; 오빠 승인 대기 1건» · 출력 «reply ts=…» 1줄" \
  '[ "$RC" = 0 ] && [ "$(posts)" = $((n0 + 1)) ] && [ "$(last)" = "&lt;@$U&gt; 오빠 승인 대기 1건" ] && grep -qx "reply ts=1800000000\.[0-9]*" "$T/out" && [ "$(wc -l < "$T/out" | tr -d " ")" = 1 ]'

# ④ ⑥ 발행 도구(A4 · A2) — 가짜 board(collect) · 골 표 · 시계 주입
cat > "$T/stub/board" <<'EOF'
#!/usr/bin/env bash
[ "$1 $2" = "collect --out" ] || exit 9
cp "$(dirname "$0")/collect.json" "$3"
EOF
cat > "$T/stub/tp.py" <<'EOF'
import os, sys
open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "argv.log"), "a").write("\t".join(sys.argv[1:]) + "\n")
EOF
REALPY="$(command -v python3)"
cat > "$T/py/python3" <<EOF
#!/usr/bin/env bash
case "\$*" in *OPPA_SLACK_UID*) case "\$(cat "$T/py/mode")" in
  out1) echo $U; exit 1 ;;
  slow) exec "$REALPY" -c 'import time; time.sleep(9); print("$U")' ;;
  *) exit 1 ;; esac ;; esac
exec "$REALPY" "\$@"
EOF
chmod +x "$T/stub/board" "$T/py/python3"
python3 - > "$T/stub/collect.json" <<'PY'
import json
team = {"key": "harness", "label": "하네스", "states": {"r1-a": "대기"}, "counts": {"완성": 0, "진행": 0, "대기": 1, "중복": 0},
        "progress": {}, "seats": {}, "oppa_todo": [0], "axes": []}
print(json.dumps({"date": "2026-11-16", "verdicts": [], "issues": [], "teams": [team]}, ensure_ascii=False))
PY
printf '%s\n' "## 골 진행" "" "| 골 번호 | 골 짧은 이름 | 닫힘 n | 전체 m | 지금 상태 1줄 |" "|---|---|---|---|---|" \
  "| 1 | 하네스 운영 | 3 | 5 | 결정 담당 <@$U> |" > "$T/goal.md"
pub() {  # pub <TP> [env…] — rc $RC · stderr $T/err
  local tp="$1"; shift; rm -rf "$T/ft/.fable-team/state" "$T/stub/argv.log"
  env FT_ROOT="$T/ft" FT_BOARD_BIN="$T/stub/board" FT_THREAD_POST="$tp" FT_GOAL_PROGRESS_MD="$T/goal.md" FT_SLACK_TOPIC_ONLY= \
    FT_BOARD_POST_ARGS="--channel C0TEST --slack-base $BASE --token-file $T/tok" FT_SLACK_THREADS="$T/reg.json" \
    FT_BOARD_NOW=2026-11-16T10:00:00 FT_BOARD_THREAD_TS="$TS" "$@" bash "$PUB" --news > "$T/out" 2> "$T/err"; RC=$?
}
km() { awk -F'\t' '{for (i = 1; i < NF; i++) if ($i == "--keep-mention") print $(i + 1)}' "$T/stub/argv.log" | paste -sd, -; }
newslast() { [ -s "$T/ft/.fable-team/state/board/news-last.json" ]; }

n0="$(posts)"; pub "$KIT/byz_thread_post.py"
chk "④ publish → 진짜 post(r2120) → rc 0 · 받은 글 1" '[ "$RC" = 0 ] && [ "$(posts)" = $((n0 + 1)) ]'
chk "④ 받은 글 진짜 태그 «<@» 1개(도구 것 · 승인 대기 줄 머리) · 원장 mention «@${U}» 꺾쇠 0" \
  '[ "$(cnt "<@")" = 1 ] && last | grep -qxF "$B2" && last | grep -qF "결정 담당 @$U" && [ "$(cnt "&lt;@")" = 0 ]'

pub "$T/stub/tp.py" FT_OPPA_SLACK_UID=U0TEST00001
chk "⑥ env 판 → argv 동사 post(r2120) · «--keep-mention U0TEST00001» 1쌍 · rc 0 · news-last 쓰임" '[ "$RC" = 0 ] && [ "$(cut -f1 "$T/stub/argv.log")" = post ] && [ "$(km)" = U0TEST00001 ] && newslast'
pub "$T/stub/tp.py"
chk "⑥ 기본 판 → argv «--keep-mention ${U}»(OPPA_SLACK_UID) 1쌍 · rc 0 · news-last 쓰임" '[ "$RC" = 0 ] && [ "$(km)" = "$U" ] && newslast'
for mode in fail out1 slow; do
  echo "$mode" > "$T/py/mode"; s0=$SECONDS; pub "$T/stub/tp.py" PATH="$T/py:$PATH"; el=$((SECONDS - s0))
  chk "⑥ python 읽기 실패 판($mode) → 인자 0 · stderr WARN 1줄 · rc 0 · news-last 쓰임 · ${el}초 < 9" \
    '[ "$RC" = 0 ] && [ -s "$T/stub/argv.log" ] && [ -z "$(km)" ] && [ "$(grep -c "WARN" "$T/err")" = 1 ] && newslast && [ "$el" -lt 9 ]'
done

echo "fail=$fail"; [ "$fail" = 0 ]
