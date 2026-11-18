#!/usr/bin/env bash
# test_hil_desk_approve_ts_r2164.sh — r2164: 승인값 h 의 run-line 표지에 «desk 값 넣기 가능» 이 붙는 것은
#   계획 «# ft-hil-oppa-ask: <질문 ts>» 1줄 + <h>.sha 64자 → ft_oppa_slack_check <ts> --plan-sha <64자> 가 SLACK-OK 일 때뿐 (반례 ①~⑨ · ⑤b · 변이 M1~M5)
# 격리: 가짜 조회(FT_SLACK_REPLIES_CMD · ts 마다 JSON 파일) · 임시 h · 임시 계획 · 실 Slack·토큰·/tmp/h* 0 · sleep 0
#   ⑤ 시간 초과 = bin 사본의 확인기를 막힌 대역으로 바꿔 7초 + 재시도 1 을 실제로 넘긴다(약 14초 · 대역은 alarm 으로 끝남)
# 기준판 대조: FT_R2164_BIN=<팩 origin/main bin 사본> 이면 ① FAIL(꼬리 0) · 변이 · kit cmp 는 건너뜀
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${FT_R2164_BIN:-$HERE/../bin}"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
OPPA="U0AC2JF0M7D"; BOT="U0BOTDESK"
TAG=' · 승인값 필요(사람 · 변수 HIL_APPROVED · 오빠 ! 줄로만)'
Q=1794900000.000100; D=1794900010.000200; O=1794900020.000300; OLD=1794875630.706789; Q2=1794900100.000400
B64=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb; B40=2222222222222222222222222222222222222222
TH="$T/threads"; mkdir -p "$TH"
printf '#!/usr/bin/env python3\nimport os,sys\nopen(os.environ["CALLS"],"a").write(os.environ["FT_SLACK_TS"]+"\\n")\np=os.path.join(os.environ["THREADS"],os.environ["FT_SLACK_TS"]+".json")\nos.path.exists(p) or sys.exit(9)\nsys.stdout.write(open(p,encoding="utf-8").read())\n' > "$T/stub"; chmod +x "$T/stub"
cat > "$T/mk.py" <<'MKPY'
import json, sys
ts, d = sys.argv[1], sys.argv[2]
msgs = []
for line in sys.stdin.read().split("\n"):
    if line.strip():
        t, u, x = line.split("|", 2)
        msgs.append({"ts": t, "user": u, "text": x, **({"thread_ts": ts} if msgs else {})})
body = json.dumps({"ok": True, "messages": msgs}, ensure_ascii=False)
for m in msgs:
    open(d + "/" + m["ts"] + ".json", "w", encoding="utf-8").write(body)
MKPY
# 계획 · h · .sha — A = 이 h 의 계획 sha256(64자)
P="$T/plan.sh.hil"; H="$T/h1"
mkplan() {  # <머리 주석 줄들(\n 구분)>
  printf '#!/usr/bin/env bash\n%b[ "${HIL_APPROVED:-}" = 1 ] || exit 2\necho ok\n' "$1" > "$P"
  printf '# ft-hil-entry plan=%s\n' "$P" > "$H"; shasum -a 256 < "$P" | cut -d' ' -f1 > "$H.sha"; A="$(cat "$H.sha")"; }
th() {  # <질문 ts> <질문 글> <덧글|빈칸> <오빠 답글> — 질문 → (desk 덧글) → 오빠 답글
  rm -f "$TH"/*.json; { echo "$1|$BOT|$2"; [ -z "$3" ] || echo "$D|$BOT|$3"; echo "$O|$OPPA|$4"; } | python3 "$T/mk.py" "$1" "$TH"; }
rl() {  # <bin> → OUT · RC · NC(조회 횟수)
  : > "$T/calls"; OUT="$(CALLS="$T/calls" THREADS="$TH" FT_SLACK_REPLIES_CMD="$T/stub" bash "$1/ft-hil-gate.sh" run-line "$H" 2>/dev/null)"; RC=$?
  NC="$(grep -c . "$T/calls")"; }
OPEN() { echo "bash $H · 승인값 필요(변수 HIL_APPROVED) · 오빠 승인 reply=$O · desk 값 넣기 가능 · 실행 줄에 ts 기록"; }
shut() {  # <사유|빈칸> — r2161 표지 그대로(+ 사유) · rc 0 · «=1» 0
  local w="bash $H$TAG${1:+ · $1}"; [ "$RC" = 0 ] && [ "$OUT" = "$w" ] || { echo "«${OUT}» rc=$RC ≠ «${w}»"; return 1; }; }
askq() { mkplan "# ft-hil-oppa-ask: $Q\n"; }
QTXT() { echo "[질문 · DB apply 승인] yoonhwan 오빠, 계획 sha256 ${1:-$A} 실행해도 될까요?"; }

c1() { askq; th "$Q" "$(QTXT)" "" "네"; rl "$1"
  [ "$RC" = 0 ] && [ "$OUT" = "$(OPEN)" ] && [ "$NC" -ge 1 ] && case "$OUT" in *HIL_APPROVED=1*) false;; *) :;; esac || { echo "① «${OUT}» rc=$RC calls=$NC"; return 1; }; }
c2() { askq; th "$Q" "$(QTXT "$B64")" "" "네"; rl "$1"; shut "거절"; }
c3() { askq; th "$Q" "$(QTXT)" "" "네? 왜요"; rl "$1"; shut "판정 불가"; }
c4() { mkplan "# ft-hil-oppa-ts: $OLD\n"; th "$OLD" "$(QTXT)" "" "네"; rl "$1"; shut "" && [ "$NC" = 0 ] || { echo "④ calls=$NC «${OUT}»"; return 1; }; }
c5() {  # 조회 실패(대역 rc 9 → 확인기 판정 불가) · 확인기 rc 2 · rc 3 · 시간 초과(7초 + 재시도 1) — 사례마다 따로
  askq; th "$Q" "$(QTXT)" "" "네"; rm -f "$TH/$Q.json"; rl "$1"; shut "판정 불가" || return 1
  local f m="$T/fk"; rm -rf "$m"; mkdir -p "$m"; cp -R "$1/." "$m/"; mkfifo "$T/fifo" 2>/dev/null
  for f in 'print("REJECT 오빠 슬랙 승인 확인 실패: 판정 불가: 조회 rc=9"); sys.exit(2)|판정 불가' 'print("REJECT 오빠 슬랙 승인 확인 실패: 오빠 거절 답글 reply=1"); sys.exit(2)|거절' \
           'sys.stderr.write("REPLY-NONE\\n"); sys.exit(3)|답글 없음' 'os.read(os.open(os.environ["FIFO"], os.O_RDWR), 1)|판정 불가'; do
    printf 'import os, sys\nopen(os.environ["CALLS"], "a").write("x\\n")\n%s\n' "${f%|*}" > "$m/ft_oppa_slack_check.py"
    : > "$T/calls"; OUT="$(FIFO="$T/fifo" CALLS="$T/calls" bash "$m/ft-hil-gate.sh" run-line "$H" 2>/dev/null)"; RC=$?; NC="$(grep -c . "$T/calls")"
    shut "${f#*|}" || return 1
    case "$f" in os.read*) [ "$NC" = 2 ] || { echo "⑤ 시간 초과 재시도 횟수 $NC ≠ 2"; return 1; };; esac
  done; }
c5b() { local x
  for x in "# ft-hil-oppa-ask: $Q\n# ft-hil-oppa-ask: $Q\n" "# ft-hil-oppa-ask: $Q\n# ft-hil-oppa-ask: $Q2\n"; do
    mkplan "$x"; th "$Q" "$(QTXT)" "" "네"; rl "$1"; shut "ask 줄 여럿" && [ "$NC" = 0 ] || { echo "⑤b ask 2줄 calls=$NC"; return 1; }; done
  askq; rm -f "$H.sha"; th "$Q" "$(QTXT)" "" "네"; rl "$1"; shut "sha 없음" && [ "$NC" = 0 ] || { echo "⑤b .sha 없음 calls=$NC"; return 1; }; }
chkr() {  # <bin> <인자…> → 확인기 stdout + rc 1덩이
  local o; o="$(CALLS="$T/calls" THREADS="$TH" FT_SLACK_REPLIES_CMD="$T/stub" python3 "$1/ft_oppa_slack_check.py" "${@:2}" 2>/dev/null)"; echo "$o rc=$?"; }
c6() {  # 40자 approve-merge 길 · --reply-only 길 · positional 64자 = 기준판과 같은 출력 (여러 실 꼴)
  local a40=1111111111111111111111111111111111111111 x s
  for s in "|네" "[멈춤] 점검 중|네" "[알림] 다른 건 head $B40|네" "[정리] 다른 계획 $B64|네" "다음 질문|네" "|네? 왜요" "|아니오"; do
    askq; th "$Q" "$(QTXT) head $a40" "${s%|*}" "${s#*|}"
    for x in "$Q $a40" "$Q $A" "--reply-only $Q" "--reply-only $Q --after $D"; do
      # shellcheck disable=SC2086
      [ "$(chkr "$1" $x)" = "$(chkr "$BASE" $x)" ] || { echo "⑥ «$s» «$x»: $(chkr "$1" $x) ≠ 기준판 $(chkr "$BASE" $x)"; return 1; }
    done; done; }
c8() { local h
  for h in "[알림]" "[정리]" "[멈춤]"; do
    askq; th "$Q" "$(QTXT)" "$h 다른 계획 B 승인 요청 $B64" "네"; rl "$1"; shut "답글 없음" || { echo "⑧ $h"; return 1; }
    case "$(chkr "$1" "$Q" "$A")" in "SLACK-OK $A parent=$Q reply=$O rc=0") ;; *) echo "⑧ $h positional 64자 = $(chkr "$1" "$Q" "$A")"; return 1;; esac
  done; }
c9() { askq; th "$Q" "$(QTXT)" "[알림] 처리 중" "네"; rl "$1"; [ "$OUT" = "$(OPEN)" ] || { echo "⑨ hex 0 안내 «${OUT}»"; return 1; }
  th "$Q" "$(QTXT)" "[재게시] 계획 sha256 $A 다시 여쭙니다" "네"; rl "$1"; [ "$OUT" = "$(OPEN)" ] || { echo "⑨ 재게시 «${OUT}»"; return 1; }
  th "$Q" "$(QTXT)" "[알림] 다른 건 head $B40" "네"; rl "$1"; shut "답글 없음" || { echo "⑨ 다른 40자"; return 1; }; }
chk() { local o; o="$("$1" "$2")" && ok "$3" || bad "$3 — $o"; }

t0=$(date +%s); BASE="${FT_R2164_BASE:-$BIN}"
echo "== 계약 ①~⑨ (bin = ${BIN})"
chk c1 "$BIN" "① ask 1줄 + 질문 글 64자 + 오빠 «네» → «오빠 승인 reply=<ts> · desk 값 넣기 가능» · =1 0"
chk c2 "$BIN" "② 질문 글 64자가 다른 계획 것 → 표지 그대로 · 거절"
chk c3 "$BIN" "③ 답글 «네? 왜요» → 표지 그대로 · 판정 불가"
chk c4 "$BIN" "④ ask 0 · «# ft-hil-oppa-ts» 옛 ts 만 → r2161 표지 그대로 · 조회 0"
t5=$(date +%s); chk c5 "$BIN" "⑤ 조회 실패 · rc 2 · rc 3 · 시간 초과(재시도 1) → 표지 그대로 · 사유"; t5=$(( $(date +%s) - t5 ))
chk c5b "$BIN" "⑤b ask 2줄(같은 ts · 다른 ts) · .sha 없음 → 표지 그대로 · 조회 0"
[ -n "${FT_R2164_BASE:-}" ] && chk c6 "$BIN" "⑥ 40자 길 · 64자 positional · --reply-only = 기준판 출력 그대로" || echo "SKIP ⑥ (FT_R2164_BASE 없음)"
chk c8 "$BIN" "⑧ [알림]·[정리]·[멈춤] × 다른 계획 64자 = 창 경계 → 표지 그대로 · positional 64자는 SLACK-OK"
chk c9 "$BIN" "⑨ hex 0 안내 · 같은 64자 재게시 = 잇는다 · 다른 40자 = 끊는다"
K="$HERE/../kit/fable-team/bin"
if [ -z "${FT_R2164_BIN:-}" ]; then
  for f in ft-hil-gate.sh ft_oppa_slack_check.py; do cmp -s "$BIN/$f" "$K/$f" && ok "cmp0 kit $f" || bad "kit 사본 다름: $f"; done
  echo "== 변이 (사본 · 변이마다 원본 같은 사례 1회 더)"
  mut() {  # <이름> <파일> <옛 글자> <새 글자> <사례…>
    local m="$T/$1" c r; mkdir -p "$m"; cp -R "$BIN/." "$m/"; shift
    python3 -c 'import sys;p,a,b=sys.argv[1:4];s=open(p,encoding="utf-8").read();assert s.count(a)==1,a;open(p,"w",encoding="utf-8").write(s.replace(a,b))' "$m/$1" "$2" "$3" \
      || { bad "${m##*/} 변이 글자 못 찾음"; return; }
    shift 3
    for c in "$@"; do
      r="$("$c" "$m")" && bad "${m##*/} 가 $c 를 못 깬다" || ok "${m##*/}: $c FAIL — ${r:0:160}"
      "$c" "$BIN" >/dev/null && ok "  └ 원본 $c PASS" || bad "  └ 원본 $c FAIL"
    done; }
  mut M1 ft_oppa_slack_check.py 'if not re.search(r"(?<![0-9a-fA-F])%s(?![0-9a-fA-F])" % sha, text, re.I) and sha:' 'if False:' c2
  mut M2 ft-hil-gate.sh "ft-hil-oppa-ask:' \"\$2\"" "ft-hil-oppa-ts:' \"\$2\"" c4
  mut M3 ft_oppa_slack_check.py 'if plan_note(txt)}' 'if status_note(txt)}' c8
  mut M4 ft_oppa_slack_check.py 'return not HEXW.search(txt) and' 'return False and' c9
  mut M5 ft-hil-gate.sh '[ "$n" = 1 ] ||' '[ "$n" -ge 1 ] ||' c5b
fi
echo "단계별 초: ⑤ ${t5}초 · 전체 $(( $(date +%s) - t0 ))초"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
