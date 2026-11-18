#!/usr/bin/env bash
# test_ask_post_oppa_tag_r2190.sh — 오빠께 묻는 글(첫 줄 머리 «[질문»·«[인터뷰»·«[답 요청»·«[결정 요청» ∨ --ask)에 오빠 진짜 태그 1개 (r2190 · B1~B4 · 반례 ②~⑫).
#   실 byz_thread_post(post · reply --ts · reply --to-slack) → 가짜 Slack(http.server) · 받은 글 바이트를 기대 파일과 cmp.
# 실 Slack · 실 mbox · 실 등록부 0 · sleep 0(포트 = fifo). R2190_HARNESS = 시험할 harness 폴더(기준판·변이 사본용).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HX="${R2190_HARNESS:-$HERE/..}"
TP="$HX/kit/slack-mirror/byz_thread_post.py"
U=U0AC2JF0M7D; OTS=1794913567.825359; HL="스크립트 1 · 인터뷰 0 · 막힌 팀 대기 0"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

T="$(mktemp -d)"; SRV=""
trap '[ -n "$SRV" ] && kill "$SRV" 2>/dev/null; rm -rf "$T"' EXIT
R="$T/root"; mkdir -p "$R/.fable-team/state" "$T/st"; : > "$T/posts.jsonl"; mkfifo "$T/pf"
printf 'YOONHWAN_BOT_TOKEN=x\n' > "$T/tok"; printf '%s\n' "$HL" > "$T/count.md"
printf '{"baseline": "0.0", "seen": {}, "ledger": {"%s": {"thread": "", "done": {}, "attempt": {}, "recips": [], "finished": true}}}' "$OTS" > "$T/st/byz_slack_mbox_inbound.C0TEST.json"
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
    def do_GET(self): self._send({"ok": True, "messages": [{"ts": "1794913567.825359", "text": "오빠 글: 다음 순서를 알려 줘"}]})
s = HTTPServer(("127.0.0.1", 0), H)
with open(sys.argv[2], "w") as f: f.write(str(s.server_port) + "\n")
s.serve_forever()
PY
SRV=$!
read -r PORT < "$T/pf"; BASE="http://127.0.0.1:$PORT"

posts() { wc -l < "$T/posts.jsonl" | tr -d ' '; }
ptext() { tail -n 1 "$T/posts.jsonl" | python3 -c 'import json,sys; sys.stdout.write(json.loads(sys.stdin.read())["text"])'; }
# tp <동사> <본문> [인자…] — 실 도구 1회 · RC · 기본 BYZ_DESK_MENTION 없음(= mirror_lib.DESK_MENTION)
tp() { local verb="$1" body="$2"; shift 2; printf '%s' "$body" > "$T/b.txt"; RC=0
  env -u BYZ_DESK_MENTION FT_ROOT="$R" FT_SLACK_THREADS="$T/reg.json" FT_TEAM_STATUS_FILE="$T/count.md" FT_SLACK_TOPIC_ONLY= BYZ_DESK_CHANNEL=C0TEST \
    FT_SLACK_STATE_DIR="$T/st" FT_SLACK_ANSWERED="$T/st/answered.json" ${XENV:-} \
    python3 "$TP" "$verb" --token-file "$T/tok" --slack-base "$BASE" --text-file "$T/b.txt" "$@" > "$T/out" 2> "$T/err" || RC=$?; }
# same <기대 글> — 받은 마지막 글 바이트 = 기대(머리줄 포함)
same() { printf '%s' "$1" > "$T/want"; ptext > "$T/got"; cmp -s "$T/want" "$T/got"; }
TAG="<@$U>"

# ok1 <이름> — rc 0 · 받은 글 1 늘어남 · 바이트 = $W
ok1() { chk "$1" '[ "$RC" = 0 ] && [ "$(posts)" = $((n0 + 1)) ] && same "$W"'; }
NL=$'\n'

# ② post 질문 머리 · 인자 없음 → 첫 줄 끝 진짜 태그 1개
n0="$(posts)"; tp post "[질문] 배포 창을 금요일로 옮길까요${NL}둘째 줄 설명" --channel C0TEST
W="$HL${NL}[질문] 배포 창을 금요일로 옮길까요 $TAG${NL}둘째 줄 설명"; ok1 "② post «[질문]» → 첫 줄 끝 태그 1"

# ③ reply --ts · reply --to-slack 질문 머리
B3="[인터뷰] 다시 여는 순서를 정해 주세요${NL}둘째 줄 설명"
W="$HL${NL}[인터뷰] 다시 여는 순서를 정해 주세요 $TAG${NL}둘째 줄 설명"
n0="$(posts)"; tp reply "$B3" --ts 1700000000.000100 --channel C0TEST
ok1 "③ reply --ts «[인터뷰]» → 태그 1"
chk "③ reply --ts thread_ts 있음" 'tail -n 1 "$T/posts.jsonl" | grep -qF "\"thread_ts\": \"1700000000.000100\""'
n0="$(posts)"; tp reply "$B3" --to-slack "$OTS" --asked 1 --answered 1
ok1 "③ reply --to-slack «[인터뷰]» → 같은 글"
chk "③ reply --to-slack thread_ts = 오빠 글" 'tail -n 1 "$T/posts.jsonl" | grep -qF "\"thread_ts\": \"$OTS\""'

# ④ --ask (머리표 없음)
n0="$(posts)"; tp post '배포 창을 정해 주세요' --channel C0TEST --ask
W="$HL${NL}배포 창을 정해 주세요 $TAG"; ok1 "④ post --ask → 첫 줄 끝 태그 1"
n0="$(posts)"; tp reply '순서를 골라 주세요' --ts 1700000000.000100 --channel C0TEST --ask
W="$HL${NL}순서를 골라 주세요 $TAG"; ok1 "④ reply --ask → 첫 줄 끝 태그 1"

# ⑤ 질문 아님 → 기준판 바이트(머리줄 + esc 본문 · 태그 0)
n0="$(posts)"; tp post "[작업상황] 진행 중${NL}[질문] 둘째 줄에만 머리" --channel C0TEST
W="$HL${NL}[작업상황] 진행 중${NL}[질문] 둘째 줄에만 머리"; ok1 "⑤ «[작업상황]» + 둘째 줄 «[질문]» → 태그 0 · 기준판 바이트"
n0="$(posts)"; tp reply ' 질문은 아니고 상태 <@U1>' --ts 1700000000.000100 --channel C0TEST
W="$HL${NL}질문은 아니고 상태 &lt;@U1&gt;"; ok1 "⑤ 머리 없는 답글 · 남의 mention → 글자 그대로 · 태그 0"

# ⑥ 손 태그 2개 → 첫 자리 1개만 진짜 · 덧붙임 0
n0="$(posts)"; tp post "[질문] $TAG 이거 봐 주세요${NL}다시 $TAG" --channel C0TEST
W="$HL${NL}[질문] $TAG 이거 봐 주세요${NL}다시 &lt;@$U&gt;"; ok1 "⑥ 본문 태그 2 → 진짜 1(첫 자리) · 둘째 글자 · 덧붙임 0"

# ⑦ keep-mention 겹침 · 보드 뉴스 꼴
n0="$(posts)"; tp post "[질문] $TAG 봐 주세요" --channel C0TEST --keep-mention "$U"
W="$HL${NL}[질문] $TAG 봐 주세요"; ok1 "⑦ «[질문]» + --keep-mention 오빠 → 태그 1"
n0="$(posts)"; tp post "골 진행 알림 · 오빠 승인 대기 1건 $TAG${NL}둘째 줄" --channel C0TEST --keep-mention "$U" --no-status-head
W="골 진행 알림 · 오빠 승인 대기 1건 $TAG${NL}둘째 줄"; ok1 "⑦ 보드 뉴스 꼴 → 기준판 바이트"

# ⑧ UID 출처
n0="$(posts)"; XENV="BYZ_DESK_MENTION=U0TESTTEST1" tp post '[질문] 출처 시험' --channel C0TEST
W="$HL${NL}[질문] 출처 시험 <@U0TESTTEST1>"; ok1 "⑧ BYZ_DESK_MENTION=U0TESTTEST1 → 그 UID 태그"
n0="$(posts)"; XENV="BYZ_DESK_MENTION=bad_id" tp post '[질문] 출처 시험' --channel C0TEST
W="$HL${NL}[질문] 출처 시험"; ok1 "⑧ BYZ_DESK_MENTION=bad_id → 태그 0 · rc 0"
chk "⑧ bad_id → stderr 1줄" '[ "$(wc -l < "$T/err" | tr -d " ")" = 1 ]'

# ⑨ 글자 — 백틱 · $(…) · 큰따옴표 · &
n0="$(posts)"; tp post '[질문] `ls` $(touch '"$T"'/mark) "인용" & 끝' --channel C0TEST
W="$HL${NL}"'[질문] `ls` $(touch '"$T"'/mark) "인용" &amp; 끝 '"$TAG"; ok1 "⑨ 태그 1 · 나머지 esc"
chk "⑨ 표식 파일 0" '[ ! -e "$T/mark" ]'

# ⑩ 검사 순서 — 본문 검사(post_guard)가 거절하는 질문 글 → 게시 0 · rc 1(기준판과 같음)
n0="$(posts)"; tp post '[질문] /Users/x 경로를 볼까요' --channel C0TEST
chk "⑩ 걸리는 «[질문]» → rc 1 · 게시 0" '[ "$RC" = 1 ] && [ "$(posts)" = "$n0" ]'

# ⑪ 받는 이가 오빠 아님(ⓗ · 머리만 본다 = 태그 붙음) · ⑫ «[결정 요청» 붙음 · «[결정]» 0(ⓖ)
n0="$(posts)"; tp post '[질문] arch 에게 묻습니다' --channel C0TEST
W="$HL${NL}[질문] arch 에게 묻습니다 $TAG"; ok1 "⑪ «[질문] arch 에게» → 태그 붙음"
n0="$(posts)"; tp post '[결정 요청] 이 순서로 할까요' --channel C0TEST
W="$HL${NL}[결정 요청] 이 순서로 할까요 $TAG"; ok1 "⑫ «[결정 요청]» → 태그 붙음"
n0="$(posts)"; tp post '[결정] GO r1 착수' --channel C0TEST
W="$HL${NL}[결정] GO r1 착수"; ok1 "⑫ «[결정] GO» → 태그 0"

echo "r2190 FAIL=$fail"
[ "$fail" = 0 ]
