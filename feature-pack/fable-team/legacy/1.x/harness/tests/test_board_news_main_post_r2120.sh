#!/usr/bin/env bash
# test_board_news_main_post_r2120.sh — 보드 뉴스 = 메인 채널 최상위 글 1개 · 골 줄 카드 진행 (r2120 · E1~E4 · 반례 ①~⑩).
#   ①~④ --news = post --channel(POST_ARGS) 1회 · reply 0 · 채널 없음 rc 2 · 실패 = news-last 그대로 · 변화 없음/디바운스 불변
#   ⑤ ⑥ post --keep-mention(실 byz_thread_post → 가짜 Slack) · ⑦ ⑧ 실 collect(임시 카드 폴더) → snapshot → body · ⑨ 열쇠 · ⑩ 본문 꼴
# 실 Slack · 실 news-last · 실 plist 0 · sleep 0(포트 = fifo). R2120_HARNESS = 시험할 harness 폴더(기준판·변이 사본용).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HX="${R2120_HARNESS:-$HERE/..}"
BIN="$HX/bin"; KIT="$HX/kit/slack-mirror"; PUB="$BIN/ft-board-publish.sh"
U=U0AC2JF0M7D; TSV=1794729663.977629; D0=2026-11-16
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

T="$(mktemp -d)"; SRV=""
trap '[ -n "$SRV" ] && kill "$SRV" 2>/dev/null; rm -rf "$T"' EXIT
R="$T/root"; FB="$R/.fable-team"; LAST="$FB/state/board/news-last.json"
mkdir -p "$FB/comm" "$FB/state" "$R/design/teams/harness" "$T/stub"; : > "$T/posts.jsonl"; mkfifo "$T/pf"
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

# 가짜 도구(argv 탭 1줄 · 본문 body.N.txt · rc = tp_rc) · collect 스텁 · 실 collect 감싸개
cat > "$T/stub/tp.py" <<'EOF'
import os, sys
d = os.path.dirname(os.path.abspath(__file__))
n = sum(1 for _ in open(f"{d}/argv.log")) if os.path.exists(f"{d}/argv.log") else 0
open(f"{d}/argv.log", "a").write("\t".join(sys.argv[1:]) + "\n")
open(f"{d}/body.{n + 1}.txt", "w", encoding="utf-8").write(open(sys.argv[sys.argv.index("--text-file") + 1], encoding="utf-8").read())
sys.exit(int(open(f"{d}/tp_rc").read()) if os.path.exists(f"{d}/tp_rc") else 0)
EOF
cat > "$T/stub/board" <<'EOF'
#!/usr/bin/env bash
[ "$1 $2" = "collect --out" ] || exit 9
cp "$(dirname "$0")/collect.json" "$3"
EOF
cat > "$T/stub/real" <<EOF
#!/usr/bin/env bash
exec python3 "$BIN/ft-board.py" "\$@"
EOF
printf '#!/bin/sh\n' > "$T/tmux.sh"; printf '#!/bin/sh\necho EMPTY\n' > "$T/inbox.sh"; echo '[]' > "$T/gh.json"
chmod +x "$T/stub/board" "$T/stub/real"
: > "$FB/state/verdicts.jsonl"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| harness | `design/teams/harness/` | x | 현역 |\n' > "$R/design/TEAMS.md"
printf '{"_label":"하네스","_cards":"cards","_master":"h-master#1","h-master#1":{"role":"master"}}' > "$FB/seats-harness.json"
git -C "$R" init -q && git -C "$R" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base

# mk <spec json> — 하네스 1팀 collect dict(스텁). spec: cards{id:폴더} · goals{id:골좌표} · done{id:날짜} · h(승인 대기 수)
cat > "$T/stub/mk.py" <<'EOF'
import json, sys
s = json.loads(sys.argv[1]); cards = s.get("cards", {})
counts = {k: sum(v == k for v in cards.values()) for k in ("완성", "진행", "대기", "중복")}
team = {"key": "harness", "label": "하네스", "states": cards, "counts": counts, "progress": {}, "seats": {},
        "oppa_todo": list(range(s.get("h", 0))), "axes": [], "goals": s.get("goals", {}), "done_on": s.get("done", {})}
print(json.dumps({"date": "2026-11-16", "verdicts": [], "issues": [], "teams": [team]}, ensure_ascii=False))
EOF
mk() { python3 "$T/stub/mk.py" "$1" > "$T/stub/collect.json"; }
goal() { { echo "## 골 진행"; echo; echo "| 골 번호 | 골 짧은 이름 | 닫힘 n | 전체 m | 지금 상태 1줄 |"; echo "|---|---|---|---|---|"
  for r in "$@"; do echo "| $r |"; done; } > "$T/goal.md"; }
reset() { rm -rf "$FB/state/board" "$T/stub/argv.log" "$T/stub"/body.*.txt "$T/stub/tp_rc"; }
calls() { [ -f "$T/stub/argv.log" ] && wc -l < "$T/stub/argv.log" | tr -d ' ' || echo 0; }
lastbody() { cat "$T/stub/body.$(calls).txt"; }
lastargv() { tail -n 1 "$T/stub/argv.log" 2>/dev/null; }
posts() { wc -l < "$T/posts.jsonl" | tr -d ' '; }
lastpost() { tail -n 1 "$T/posts.jsonl"; }
ptext() { lastpost | python3 -c 'import json,sys; sys.stdout.write(json.loads(sys.stdin.read())["text"])'; }
# pub <시각> [env…] — 기본 = 가짜 도구 · collect 스텁 · POST_ARGS «--channel C1» · THREAD_TS 있음
pub() { local at="$1"; shift; RC=0
  env FT_ROOT="$R" FT_BOARD_BIN="$T/stub/board" FT_THREAD_POST="$T/stub/tp.py" FT_GOAL_PROGRESS_MD="$T/goal.md" FT_OPPA_SLACK_UID="$U" \
    FT_BOARD_POST_ARGS="--channel C1" FT_BOARD_THREAD_TS="$TSV" FT_BOARD_NOW="$D0T$at" FT_SLACK_TOPIC_ONLY= FT_SLACK_THREADS="$T/reg.json" \
    FT_BOARD_GH_TTL=0 FT_BOARD_GH_REFRESH=1 FT_VERDICT_BIN="$BIN/ft-verdict.sh" FT_BOARD_TMUX="bash $T/tmux.sh" FT_BOARD_GH="cat $T/gh.json" \
    FT_BOARD_INBOX="bash $T/inbox.sh" FT_BOARD_SEAT_STATUS=/usr/bin/true "$@" bash "$PUB" --news > "$T/out" 2> "$T/err" || RC=$?; }
D0T="${D0}T"
G6="6 | 하네스 운영 정리 | 3 | 5 | 진행 중"
BASE1='{"cards":{"r1-a":"대기","r2-b":"진행"},"h":0}'

# ① 최상위 글(E1)
reset; goal "$G6"; mk "$BASE1"; pub 10:00:00
chk "① rc 0 · 가짜 도구 호출 1 · 동사 post · --channel C1" '[ "$RC" = 0 ] && [ "$(calls)" = 1 ] && lastargv | grep -q "^post	" && lastargv | grep -qF -- "--channel	C1"'
chk "① reply 0 · --ts 0(THREAD_TS 안 읽음)" '! grep -q "reply" "$T/stub/argv.log" && ! grep -qF -- "--ts" "$T/stub/argv.log"'
chk "① news-last 갱신 · 출력 «글 1통 발행»" '[ -s "$LAST" ] && grep -qxF "ft-board-publish: 글 1통 발행" "$T/out"'

# ② 도구 실패 = news-last 바이트 그대로(E1)
cp "$LAST" "$T/last.bak"; echo 1 > "$T/stub/tp_rc"; goal "6 | 하네스 운영 정리 | 4 | 5 | 진행 중"; pub 10:15:00
chk "② 가짜 post rc 1 → rc 1 · 호출 1 더 · news-last 바이트 그대로" '[ "$RC" = 1 ] && [ "$(calls)" = 2 ] && cmp -s "$LAST" "$T/last.bak"'
rm -f "$T/stub/tp_rc"

# ③ 채널 없음(E1)
reset; goal "$G6"; mk "$BASE1"; pub 10:00:00 FT_BOARD_POST_ARGS=""
chk "③ --channel 없음(THREAD_TS 만) → rc 2 · «뉴스 채널 없음» · 호출 0 · news-last 0" '[ "$RC" = 2 ] && grep -qF "뉴스 채널 없음" "$T/err" && [ "$(calls)" = 0 ] && [ ! -f "$LAST" ]'

# ④ 변화 없음 · 디바운스 = 기준판과 같음(E1)
reset; goal "$G6"; mk "$BASE1"; pub 10:00:00; cp "$LAST" "$T/last.bak"; pub 10:15:00
chk "④ 같은 입력 → «변화 없음» · 호출 0 더 · news-last 그대로" '[ "$RC" = 0 ] && [ "$(calls)" = 1 ] && grep -qF "변화 없음" "$T/out" && cmp -s "$LAST" "$T/last.bak"'
goal "6 | 하네스 운영 정리 | 4 | 5 | 진행 중"; pub 10:04:59
chk "④ 열쇠 바뀜 · 직전 299초 → «디바운스» · 호출 0 더 · news-last 그대로" '[ "$RC" = 0 ] && [ "$(calls)" = 1 ] && grep -qF "디바운스" "$T/out" && cmp -s "$LAST" "$T/last.bak"'

# ⑤ 태그(E2) — 승인 대기 1 · 원장 글 <@U1> → 실 byz_thread_post post → 가짜 Slack
reset; goal "6 | 하네스 운영 정리 | 3 | 5 | 결정 담당 <@U1>"; mk '{"cards":{"r1-a":"대기"},"h":1}'
pub 10:00:00; chk "⑤ 가짜 도구 argv = post … --keep-mention $U" '[ "$RC" = 0 ] && lastargv | grep -q "^post	" && lastargv | grep -qF -- "--keep-mention	$U"'
reset; n0="$(posts)"; pub 10:00:00 FT_THREAD_POST="$KIT/byz_thread_post.py" FT_BOARD_POST_ARGS="--channel C0TEST --slack-base $BASE --token-file $T/tok"
chk "⑤ 실 post → rc 0 · 받은 글 1 · 채널 C0TEST · thread_ts 0" '[ "$RC" = 0 ] && [ "$(posts)" = $((n0 + 1)) ] && lastpost | grep -qF "\"channel\": \"C0TEST\"" && ! lastpost | grep -qF thread_ts'
chk "⑤ 받은 글 진짜 태그 «<@$U>» 1개 · «<@U1>» 0 · «&lt;@» 0" '[ "$(ptext | grep -oF "<@$U>" | wc -l | tr -d " ")" = 1 ] && [ "$(ptext | grep -oF "<@" | wc -l | tr -d " ")" = 1 ] && ! ptext | grep -qF "&lt;@"'

# ⑥ post --keep-mention 꼴 아님(E2)
for bad_uid in u0ac2jf0m7d U1 "<@$U>"; do
  n0="$(posts)"; printf 'x\n' > "$T/b.txt"
  env FT_ROOT="$R" FT_SLACK_THREADS="$T/reg.json" python3 "$KIT/byz_thread_post.py" post --channel C0TEST --token-file "$T/tok" --slack-base "$BASE" \
    --keep-mention "$bad_uid" --text-file "$T/b.txt" > "$T/out" 2>&1; RC=$?
  chk "⑥ post --keep-mention «${bad_uid}» → rc 1 · 게시 0" '[ "$RC" = 1 ] && [ "$(posts)" = "$n0" ]'
done

# ⑤-b 카운팅 머리줄 경계(DA HOLD #319310 R1) — 뉴스 post = 머리줄 0 · 일반 post = 머리줄 그대로
printf '스크립트 1(판정 42) · 인터뷰 0 · 막힌 팀 대기 0\n' > "$T/count.md"
reset; goal "$G6"; mk '{"cards":{"r1-a":"대기"},"h":1}'; n0="$(posts)"
pub 10:00:00 FT_TEAM_STATUS_FILE="$T/count.md" FT_THREAD_POST="$KIT/byz_thread_post.py" FT_BOARD_POST_ARGS="--channel C0TEST --slack-base $BASE --token-file $T/tok"
chk "⑤-b 카운팅 메모(판정 42) 있어도 뉴스 → rc 0 · 받은 글 1 · 첫 줄 = 골 진행 알림 · news-last 갱신" \
  '[ "$RC" = 0 ] && [ "$(posts)" = $((n0 + 1)) ] && ptext | head -n 1 | grep -q "^골 진행 알림" && [ -s "$LAST" ]'
printf '스크립트 1 · 인터뷰 0 · 막힌 팀 대기 0\n' > "$T/count.md"; printf '일반 글\n' > "$T/b.txt"
postdirect() { env FT_ROOT="$R" FT_SLACK_THREADS="$T/reg.json" FT_TEAM_STATUS_FILE="$T/count.md" python3 "$KIT/byz_thread_post.py" post --channel C0TEST \
  --token-file "$T/tok" --slack-base "$BASE" --text-file "$T/b.txt" "$@" > "$T/out" 2>&1; RC=$?; }
n0="$(posts)"; postdirect
chk "⑤-b 일반 post(인자 없음) → 첫 줄 = 카운팅 머리줄(기준판 그대로)" '[ "$RC" = 0 ] && [ "$(posts)" = $((n0 + 1)) ] && [ "$(ptext | head -n 1)" = "스크립트 1 · 인터뷰 0 · 막힌 팀 대기 0" ]'
n0="$(posts)"; postdirect --no-status-head
chk "⑤-b post --no-status-head → 받은 글 = 본문만" '[ "$RC" = 0 ] && [ "$(posts)" = $((n0 + 1)) ] && [ "$(ptext)" = "일반 글" ]'

# ⑦ ⑧ 실 collect(임시 카드 폴더) → snapshot → body (E3)
card() {  # card <폴더> <id> <골좌표 줄 | -> [mtime YYYYMMDDhhmm] [앞 빈 줄 수]
  mkdir -p "$R/cards/$1"; { echo "# 인덱스: $2"; for _ in $(seq 1 "${5:-0}"); do echo "- 칸: x"; done; [ "$3" = - ] || echo "- 골좌표: $3"; echo "본문"; } > "$R/cards/$1/$2.md"
  touch -t "${4:-202611160900}" "$R/cards/$1/$2.md"; }
H6="6 · 하네스 운영 정리"; SUF="카드 완성 2장(오늘 +1), 진행 1장, 대기 1장"
goalline() { lastbody | awk '/^지금$/{f=1;next} /^다음$/{f=0} f' | grep -F "하네스 운영 정리"; }
rm -rf "$R/cards"; card 완성 r1-a "$H6" 202611160900; card 완성 r2-b "$H6" 202611100900; card 진행 r3-c "$H6"; card 대기 r4-d "$H6"
reset; goal "$G6"; pub 10:00:00 FT_BOARD_BIN="$T/stub/real"
chk "⑦ 실 collect → rc 0 · 호출 1" '[ "$RC" = 0 ] && [ "$(calls)" = 1 ]'
chk "⑦ 하네스 골 줄 끝 «${SUF}»" 'goalline | grep -q -- "${SUF}\$"'
K1="$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["key"], ensure_ascii=False))' "$LAST")"
card 완성 r2-b "7 · 다른 골" 202611100900; pub 10:15:00 FT_BOARD_BIN="$T/stub/real"
K2="$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["key"], ensure_ascii=False))' "$LAST")"
chk "⑦ 1장 골좌표만 «7 · 다른 골» → POST · 줄 끝 «카드 완성 1장(오늘 +1), 진행 1장, 대기 1장» · 열쇠 다름" \
  '[ "$RC" = 0 ] && [ "$(calls)" = 2 ] && goalline | grep -q "카드 완성 1장(오늘 +1), 진행 1장, 대기 1장$" && [ "$K1" != "$K2" ]'
G1J="$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["snap"].get("card_goals", {}).get("하네스"), ensure_ascii=False, sort_keys=True))' "$LAST")"
mv "$R/cards" "$R/cards.x"; pub 10:30:00 FT_BOARD_BIN="$T/stub/real"
G2J="$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["snap"].get("card_goals", {}).get("하네스"), ensure_ascii=False, sort_keys=True))' "$LAST")"
chk "⑦ 수집 실패 팀 → 직전 골 칸 이어씀 · 줄 끝 카드 진행 그대로" '[ "$RC" = 0 ] && [ "$(calls)" = 3 ] && [ "$G1J" != null ] && [ "$G1J" = "$G2J" ] && goalline | grep -q "카드 완성 1장(오늘 +1), 진행 1장, 대기 1장$"'
mv "$R/cards.x" "$R/cards"

rm -rf "$R/cards"; card 완성 r1-a -; card 진행 r2-b "7 · 하네스 운영 개선"; card 대기 r3-c "$H6" 202611160900 12
reset; goal "$G6"; pub 10:00:00 FT_BOARD_BIN="$T/stub/real"
chk "⑧ 골좌표 없음 · 다른 이름 · 머리 12줄 밖 → 셈 0 · 줄 끝 덧붙임 0" '[ "$RC" = 0 ] && goalline | grep -qxF "하네스 운영 정리 ▓▓▓▓▓▓░░░░ 3/5. 진행 중" && ! lastbody | grep -q "카드 완성\|진행 [0-9]장\|대기 [0-9]장"'

# ⑨ 열쇠 = 골별 완성 수만(E3 · 전환 1회)
GJ='"goals":{"r1-a":"6 · 하네스 운영 정리","r2-b":"6 · 하네스 운영 정리","r3-c":"6 · 하네스 운영 정리"}'
reset; goal "$G6"; mk "{\"cards\":{\"r1-a\":\"완성\",\"r2-b\":\"진행\",\"r3-c\":\"대기\"},$GJ,\"done\":{\"r1-a\":\"2026-11-15\"}}"; pub 10:00:00
mk "{\"cards\":{\"r1-a\":\"완성\",\"r2-b\":\"대기\",\"r3-c\":\"대기\"},$GJ,\"done\":{\"r1-a\":\"2026-11-15\"}}"; pub 10:15:00
chk "⑨ table 같음 · 진행 1장 → 대기 이동만 → «변화 없음» · 호출 0 더" '[ "$RC" = 0 ] && [ "$(calls)" = 1 ] && grep -qF "변화 없음" "$T/out"'
mk "{\"cards\":{\"r1-a\":\"완성\",\"r2-b\":\"완성\",\"r3-c\":\"대기\"},$GJ,\"done\":{\"r1-a\":\"2026-11-15\",\"r2-b\":\"2026-11-16\"}}"; pub 10:30:00
chk "⑨ 완성 1장 늘어남 → POST" '[ "$RC" = 0 ] && [ "$(calls)" = 2 ]'
python3 - "$LAST" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); k = d["key"]; d["key"] = k[:k.index("정해진 다음 한 수 없음") + 1]  # 옛 열쇠 = standing + 다음 칸
json.dump(d, open(sys.argv[1], "w"), ensure_ascii=False)
PY
pub 10:45:00; c1="$(calls)"; pub 11:00:00
chk "⑨ 옛 열쇠 · 같은 입력 · 900초 뒤 → 첫 회차 POST 1 · 둘째 회차 호출 0" '[ "$c1" = 3 ] && [ "$(calls)" = 3 ] && grep -qF "변화 없음" "$T/out"'

# ⑩ 본문 꼴(E4)
reset; goal "$G6"; mk "{\"cards\":{\"r1-a\":\"완성\",\"r2-b\":\"진행\",\"r3-c\":\"대기\"},$GJ,\"h\":1}"; pub 10:00:00
order() { lastbody | awk '$0=="지금"{print "지금"} $0=="다음"{print "다음"} $0=="막힌 것, 오빠 할 일"{print "막힘"} /^근거:/{print "근거"}' | paste -sd/ -; }
chk "⑩ «|» 줄 0 · \`\`\` 0 · 순서 머리 → 지금 → 다음 → 막힌 것 → 근거" \
  '! lastbody | grep -q "^|" && ! lastbody | grep -qF "\`\`\`" && lastbody | head -n 1 | grep -q "^골 진행 알림" && [ "$(order)" = "지금/다음/막힘/근거" ]'
rows=(); gj=""; cj=""  # 골 46개 = 막대·덧붙임 있으면 3500B 넘고 ⓒ 본문은 상한 안(계산 실측)
for i in $(seq 10 55); do rows+=("$i | 골$i 이름 | 1 | 9 | 진행 중"); gj+="\"c$i\":\"$i · 골$i 이름\","; cj+="\"c$i\":\"진행\","; done
reset; goal "${rows[@]}"; mk "{\"cards\":{${cj%,}},\"goals\":{${gj%,}}}"; pub 10:00:00
chk "⑩ 3500B 넘김 → ⓒ 막대 · 카드 진행 덧붙임 함께 빠짐 · 상한 안" \
  '[ "$RC" = 0 ] && [ "$(calls)" = 1 ] && ! lastbody | grep -q "[▓░]" && ! lastbody | grep -q "진행 1장" && [ "$(lastbody | wc -c | tr -d " ")" -le 3500 ] && lastbody | grep -qxF "골55 이름: 9단계 중 1단계 끝남. 진행 중"'

echo "fail=$fail"; [ "$fail" = 0 ]
