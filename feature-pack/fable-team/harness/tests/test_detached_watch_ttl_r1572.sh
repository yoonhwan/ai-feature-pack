#!/usr/bin/env bash
# test_detached_watch_ttl_r1572.sh — 카드 r1572 «좌석 밖 상주 감시 TTL» 수용 ⓐ·ⓑ·ⓒ + 변이 M1~M7
#   시험 입력 = 격리 폴더(mktemp) · 가짜 시계(파일 + 스텝) · 가짜 ps 표 · 가짜 launchctl · 가짜 lsof · 가짜 mbox · 가짜 tmux
#   실행: bash test_detached_watch_ttl_r1572.sh   · rc0 = 전건 PASS · rc1 = FAIL 있음 · 실제 좌석·실제 mbox·네트워크 호출 0
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; W="$BIN/ft-bg-watch.sh"; C="$BIN/ft-bg-watch-check.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/r1572.XXXXXX")"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()   { echo "PASS $1"; pass=$((pass+1)); }
bad()  { echo "FAIL $1${2:+ — $2}"; fail=$((fail+1)); }
eq()   { [ "$2" = "$3" ] && ok "$1" || bad "$1" "want=$3 got=$2"; }
has()  { case "$2" in *"$3"*) ok "$1";; *) bad "$1" "없음: $3";; esac; }
hasnt(){ case "$2" in *"$3"*) bad "$1" "있음: $3";; *) ok "$1";; esac; }
cnt()  { grep -c "$1" "$2" 2>/dev/null || true; }
lines(){ [ -f "$1" ] && wc -l <"$1" | tr -d ' ' || echo 0; }

# ── 가짜 도구 ────────────────────────────────────────────────────────────────
mkdir -p "$T/comm" "$T/state" "$T/bin"
cat >"$T/comm/mbox.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\t%s\n' "$2" "$3" >> "$SENT_LOG"
printf '%s\n' "$4" >> "$SENT_LOG.body"
EOF
SENT="$T/sent.log"
cat >"$T/bin/clock.sh" <<EOF
#!/usr/bin/env bash
n=\$(cat "$T/clock"); printf '%s\n' "\$n"; printf '%s\n' \$((n + \${BGW_STEP:-10})) > "$T/clock"
EOF
cat >"$T/bin/tmux" <<'EOF'
#!/usr/bin/env bash
for a; do case "$a" in seat-A|seat-H) exit 0;; esac; done; exit 1
EOF
cat >"$T/bin/kill" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$T/killcalled"; exit 0
EOF
printf '#!/usr/bin/env bash\nfor a; do case "$a" in 103) echo tPIPE;; esac; done\n' >"$T/bin/lsof_pipe.sh"
printf '#!/usr/bin/env bash\necho tPIPE\n' >"$T/bin/lsof_all.sh"
mkdir -p "$T/seatsdir" "$T/seats_r3" "$T/seats_nod"
printf '%s\n' '{"_desk":"seat-H","seat-A":{"role":"nano"},"seat-Z":{"role":"nano","_replaced_by":"seat-Z2"}}' >"$T/seatsdir/seats.json"
printf '%s\n' '{"_desk":"byz-planner-desk-pi#126","byz-planner-desk-pi#125":{"role":"desk"},"byz-planner-desk-pi#126":{"role":"desk"}}' >"$T/seats_r3/seats.json"
printf '%s\n' '{"seat-A":{"role":"nano"}}' >"$T/seats_nod/seats.json"
cat >"$T/bin/advance.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$1" >>"$T/sleep.log"
n=\$(cat "$T/clock"); printf '%s\n' \$((n + \${1:-0})) >"$T/clock"
EOF
chmod 755 "$T/comm/mbox.sh" "$T/bin/"*
export SENT_LOG="$SENT" FT_MBOX_DIR="$T/comm" FT_BGW_LEDGER="$T/state/bg-watch.tsv" FT_BGW_MBOX="$T/comm/mbox.sh" \
       FT_BGW_SLEEP_CMD=true FT_BGW_NOW_CMD="bash $T/bin/clock.sh" FT_BGW_TMUX_CMD="bash $T/bin/tmux {seat}" \
       FT_BGW_SEATS_X="$T/seatsdir" FT_BGW_PS_CMD="cat $T/ps.txt" FT_BGW_LAUNCHCTL_CMD="cat $T/launchctl.txt" FT_BGW_LSOF_CMD="bash $T/bin/lsof_pipe.sh {pid}" \
       PATH="$T/bin:$PATH"
: >"$T/launchctl.txt"; : >"$T/ps.txt"

# ── ⓐ 띄우기 도우미 ──────────────────────────────────────────────────────────
echo "1700000000" >"$T/clock"
bash "$W" --seat seat-A --until "sha land" --every 5 -- true >/dev/null 2>&1; rc=$?
eq "M1 끝 시각 없이 띄우기 = 실행 전 rc2" "$rc" 2
[ -f "$FT_BGW_LEDGER" ] && bad "M1 거절인데 장부 줄이 생김" || ok "M1 거절이면 장부 0줄"
bash "$W" --until "sha land" --end-at 1700009999 --every 5 -- true >/dev/null 2>&1; eq "M1 소유 좌석 없으면 rc2" "$?" 2
bash "$W" --seat seat-A --end-at 1700009999 --every 5 -- true >/dev/null 2>&1;       eq "M1 끝 조건 1줄 없으면 rc2" "$?" 2
bash "$W" --seat seat-A --until x --end-at 1700009999 -- true >/dev/null 2>&1;        eq "M1 간격 없으면 rc2" "$?" 2
bash "$W" --seat seat-A --until x --end-at "언젠가" --every 5 -- true >/dev/null 2>&1; eq "M1 못 읽는 끝 시각 = rc2" "$?" 2
for o in --seat --until --end-at --every; do
  timeout 2 bash "$W" "$o" >/dev/null 2>&1; eq "R1 $o 값 없음 = 실행 전 rc2(무한 반복 0)" "$?" 2
done
[ -f "$FT_BGW_LEDGER" ] && bad "M1 거절 4회인데 장부 줄이 생김" || ok "M1 거절이면 장부 0줄(재확인)"

echo 1000 >"$T/clock"; rm -f "$FT_BGW_LEDGER" "$T/sleep.log"
out="$(BGW_STEP=0 FT_BGW_SLEEP_CMD="bash $T/bin/advance.sh" bash "$W" --seat seat-A --until "sha land" --end-at 1050 --every 10 -- true 2>&1)"; rc=$?
eq "ⓐ 정상 종료 rc0" "$rc" 0
has "ⓐ 끝줄 = end=deadline" "$out" "end=deadline rc=0"
eq "ⓐ 장부 up 1줄" "$(cnt $'^up\t' "$FT_BGW_LEDGER")" 1
eq "ⓐ 기한 앞 5회차" "$(cnt $'^round\t' "$FT_BGW_LEDGER")" 5
eq "ⓐ 장부 «끝남» 1줄" "$(cnt $'^done\t' "$FT_BGW_LEDGER")" 1
hasnt "ⓐ 회차 줄에 성공 표시 0" "$(cat "$FT_BGW_LEDGER")" $'\tok\t'
eq "ⓐ 장부에 끝 시각 적힘" "$(awk -F'\t' '$1=="up"{print $7}' "$FT_BGW_LEDGER")" 1050
eq "ⓐ 장부에 끝 조건 1줄 적힘" "$(awk -F'\t' '$1=="up"{print $9}' "$FT_BGW_LEDGER")" "sha land"
echo 1000 >"$T/clock"; rm -f "$FT_BGW_LEDGER"
BGW_STEP=0 bash "$W" --seat seat-A --until "sha land" --end-at 900 --every 10 -- true >/dev/null 2>&1
eq "ⓐ 기한 지난 채 띄우면 회차 0" "$(cnt $'^round\t' "$FT_BGW_LEDGER")" 0
eq "ⓐ 기한 지난 채 띄우면 장부 «끝남»" "$(cnt $'^done\t' "$FT_BGW_LEDGER")" 1

echo 1000 >"$T/clock"; rm -f "$FT_BGW_LEDGER" "$SENT"
out="$(BGW_STEP=0 FT_BGW_ROUND_SEC=1 bash "$W" --seat seat-A --until "sha land" --end-at 1700999 --every 10 -- bash -c 'sleep 30' 2>&1)"; rc=$?
eq "ⓐ 회차 상한 초과 = rc1" "$rc" 1
has "ⓐ 상한 초과 끝줄 = end=fail" "$out" "end=fail rc=1"
eq "ⓐ 실패 장부 1줄" "$(cnt $'^fail\t' "$FT_BGW_LEDGER")" 1
eq "ⓐ 실패 알림 소유자 1통" "$(lines "$SENT")" 1
eq "ⓐ 실패 뒤 새 회차 0" "$(cnt $'^round\t' "$FT_BGW_LEDGER")" 0
hasnt "ⓐ 실패 장부에 성공 처리 0" "$(cat "$FT_BGW_LEDGER")" "성공"

echo 1000 >"$T/clock"; rm -f "$FT_BGW_LEDGER" "$T/sleep.log"
BGW_STEP=0 FT_BGW_SLEEP_CMD="bash $T/bin/advance.sh" bash "$W" --seat seat-A --until x --end-at 1010 --every 3600 -- true >"$T/o_r2" 2>&1; rc=$?
eq "R2 대기가 min(간격, 남은 기한)으로 잘린다 = rc0" "$rc" 0
has "R2 끝줄 = end=deadline" "$(cat "$T/o_r2")" "end=deadline"
eq "R2 요청 대기 최대 = 남은 기한 10초" "$(awk '{if($1>m)m=$1}END{print m+0}' "$T/sleep.log")" 10
eq "R2 기한 뒤 새 회차 0" "$(cnt $'^round\t' "$FT_BGW_LEDGER")" 1
eq "R2 종료 시각 = 기한 1010" "$(cat "$T/clock")" 1010

# ── 변이 M4·M5 (사본을 고쳐 «검출되는지») ───────────────────────────────────
grep -v 'if \[ "\$T" -ge "\$END_AT" \]' "$W" >"$T/w_m4.sh"
[ "$(grep -c 'END_AT" \]; then ROW done' "$T/w_m4.sh")" = 0 ] && ok "M4 변이 = 회차 전 기한 검사 삭제" || bad "M4 변이 생성 실패"
echo "1700000000" >"$T/clock"; rm -f "$T/m4.tsv"
FT_BGW_LEDGER="$T/m4.tsv" timeout 3 bash "$T/w_m4.sh" --seat seat-A --until x --end-at 1600000000 --every 1 -- true >/dev/null 2>&1
[ "$(cnt $'^round\t' "$T/m4.tsv")" -gt 0 ] && ok "M4 기한 뒤 새 회차 1회 이상 = ⓐ FAIL(검출)" || bad "M4 변이를 못 잡음"
echo "1700000000" >"$T/clock"; rm -f "$T/m5.tsv"
python3 - "$W" "$T/w_m5.sh" <<'PY'
import sys
s = open(sys.argv[1], encoding="utf-8").read()
s = s.replace("cap=$((ROUND_SEC*5))", "cap=999999999")
open(sys.argv[2], "w", encoding="utf-8").write(s)
PY
timeout 6 bash "$T/w_m5.sh" --seat seat-A --until x --end-at 1700009999 --every 1 -- bash -c 'sleep 60' >/dev/null 2>&1; rc=$?
eq "M5 회차 상한 제거 = 안 끝나는 명령에 영구 대기(timeout 124)" "$rc" 124

# ── ⓑ 비모델 점검 ────────────────────────────────────────────────────────────
hashf() { printf '%s' "$1" | shasum -a 1 | cut -c1-12; }
C102="bash /x/ft-bg-watch.sh --seat seat-A --until sha --end-at 1700009999 --every 60"
C103="python3 /x/serena-mcp-server.py --loop 10"
printf '501 102 1 Mon Nov 10 10:00:00 2026 %s\n501 103 1 Mon Nov 10 10:00:00 2026 %s\n' "$C102" "$C103" >"$T/ps.txt"
printf 'PID\tStatus\tLabel\n777\t0\tcom.byz.keep\n' >"$T/launchctl.txt"
printf 'up\tseat-A\t501\t102\tMon Nov 10 10:00:00 2026\t%s\t1700009999\t60\tsha\t1700000000\tx\n' "$(hashf "$C102")" >"$FT_BGW_LEDGER"
rm -f "$SENT" "$SENT.body" "$FT_BGW_LEDGER.seen"
rc=0; FT_BGW_NOW_CMD="echo 1700000100" bash "$C" >"$T/o1" 2>&1; rc=$?
eq "ⓑ 점검 rc0" "$rc" 0
has "ⓒ 현역 MCP(파이프 연결) = 알림 0" "$(cat "$T/o1")" "SKIP 103 현역 MCP(파이프 연결)"
has "M2 장부 안 ∧ 기한 전 = 알림 0" "$(cat "$T/o1")" "SKIP 102 장부 안·기한 전"
eq "ⓒ 장부 안 감시에 알림 0통" "$(lines "$SENT")" 0

printf '501 101 1 Mon Nov 10 10:00:00 2026 bash /x/main-land-watch.sh --loop 10\n' >>"$T/ps.txt"
FT_BGW_NOW_CMD="echo 1700000100" bash "$C" >"$T/o2" 2>&1
has "ⓑ 장부 밖 = NOTIFY" "$(cat "$T/o2")" "NOTIFY 101 "
has "ⓑ 장부 밖 사유 = 장부밖" "$(cat "$T/o2")" "장부밖"
eq "ⓑ 알림 1통" "$(lines "$SENT")" 1
eq "ⓑ 받는 좌석 = 명부 _desk(seat-H)" "$(cut -f1 "$SENT")" "seat-H"
has "ⓑ 알림 본문 = 끝내는 사람·등록 안내" "$(cat "$SENT.body")" "등록 = ft-bg-watch.sh"
FT_BGW_NOW_CMD="echo 1700000100" bash "$C" >"$T/o3" 2>&1
has "ⓑ 같은 인스턴스 두 번째 = 이미 1통" "$(cat "$T/o3")" "SKIP 101 이미 1통"
eq "ⓑ 두 번째 실행 알림 0통(총 1통)" "$(lines "$SENT")" 1

python3 - "$T/ps.txt" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(s.replace("Mon Nov 10 10:00:00 2026 bash /x/main-land-watch.sh",
                                                "Mon Nov 10 11:11:11 2026 bash /x/main-land-watch.sh"))
PY
FT_BGW_NOW_CMD="echo 1700000100" bash "$C" >"$T/o4" 2>&1
has "M6 같은 PID·다른 시작 시각 = 새 인스턴스(따로 1통)" "$(cat "$T/o4")" "Mon Nov 10 11:11:11 2026"
eq "M6 총 2통" "$(lines "$SENT")" 2

printf '501 102 1 Mon Nov 10 10:00:00 2026 %s\n' "$C102" >"$T/ps.txt"
printf 'up\tseat-A\t501\t102\tMon Nov 10 10:00:00 2026\t%s\t1700000050\t60\tsha\t1700000000\tx\n' "$(hashf "$C102")" >"$FT_BGW_LEDGER"
rm -f "$SENT" "$SENT.body" "$FT_BGW_LEDGER.seen"; FT_BGW_NOW_CMD="echo 1700000100" bash "$C" >"$T/o5" 2>&1
has "ⓑ 기한 지남 = NOTIFY" "$(cat "$T/o5")" "NOTIFY 102 "
has "ⓑ 기한 지남 사유" "$(cat "$T/o5")" "기한지남"
eq "ⓑ 소유자 좌석 살아 있으면 소유자에게" "$(cut -f1 "$SENT")" "seat-A"
printf 'up\tseat-Z\t501\t102\tMon Nov 10 10:00:00 2026\t%s\t1700000050\t60\tsha\t1700000000\tx\n' "$(hashf "$C102")" >"$FT_BGW_LEDGER"
rm -f "$SENT" "$SENT.body" "$FT_BGW_LEDGER.seen"; FT_BGW_NOW_CMD="echo 1700000100" bash "$C" >"$T/o6" 2>&1
eq "ⓑ 소유자 좌석이 닫혔으면 _desk(seat-H)" "$(cut -f1 "$SENT")" "seat-H"

printf '501 106 1 - bash /x/guard-watch.sh --loop 5\n' >"$T/ps.txt"
rm -f "$SENT" "$SENT.body" "$FT_BGW_LEDGER.seen"; FT_BGW_NOW_CMD="echo 1700000100" bash "$C" >"$T/o7" 2>&1
has "M7 시작 시각 못 읽음 = 판정 불가 1줄" "$(cat "$T/o7")" "NA 106 판정 불가"
eq "M7 판정 불가 = 알림 0통" "$(lines "$SENT")" 0
[ -f "$FT_BGW_LEDGER.seen" ] && bad "M7 판정 불가를 «알림 완료/면제» 로 기록함" || ok "M7 판정 불가를 면제로 기록 0"
FT_BGW_NOW_CMD="echo 1700000100" bash "$C" >"$T/o8" 2>&1
has "M7 다음 점검도 다시 본다" "$(cat "$T/o8")" "NA 106 판정 불가"

cat >"$T/bin/psenv.sh" <<EOF
#!/usr/bin/env bash
printf '%s/%s\n' "\$LC_ALL" "\$TZ" >"$T/psenv.txt"
cat "$T/ps.txt"
EOF
chmod 755 "$T/bin/psenv.sh"
FT_BGW_PS_CMD="bash $T/bin/psenv.sh" FT_BGW_NOW_CMD="echo 1700000100" bash "$C" >/dev/null 2>&1
eq "ⓑ ps 는 LC_ALL=C TZ=UTC 로 부른다(lstart 5토큰 고정)" "$(cat "$T/psenv.txt" 2>/dev/null)" "C/UTC"
printf '501 301 1 Mon Nov 10 10:00:00 2026 /opt/homebrew/Cellar/python@3.14/3.14.8/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python /x/capacity/anchor-watch.py --snapshot --loop 10\n' >"$T/ps.txt"
: >"$FT_BGW_LEDGER"; rm -f "$SENT" "$SENT.body" "$FT_BGW_LEDGER.seen"
FT_BGW_NOW_CMD="echo 1700000100" bash "$C" >"$T/o9a" 2>&1
has "ⓑ 실사건 꼴(Python.framework + anchor-watch.py) = 감시 꼴로 잡힌다" "$(cat "$T/o9a")" "NOTIFY 301 "

# R3 — 명부 포인터(_desk)로 수신자를 정한다(옛 desk 세션이 살아 있어도)
printf '501 402 1 Mon Nov 10 10:00:00 2026 bash /x/main-land-watch.sh --loop 10\n' >"$T/ps.txt"
: >"$FT_BGW_LEDGER"; rm -f "$SENT" "$SENT.body" "$FT_BGW_LEDGER.seen"
FT_BGW_SEATS_X="$T/seats_r3" FT_BGW_TMUX_CMD="exit 0" FT_BGW_NOW_CMD="echo 1700000100" bash "$C" >"$T/o_r3" 2>&1
eq "R3 수신자 = _desk 현역(#126, 옛 #125 아님)" "$(cut -f1 "$SENT")" "byz-planner-desk-pi#126"
# R3-b — _desk 가 없으면 임의 desk 로 성공 처리하지 않는다
rm -f "$SENT" "$SENT.body" "$FT_BGW_LEDGER.seen"
FT_BGW_SEATS_X="$T/seats_nod" FT_BGW_TMUX_CMD="exit 0" FT_BGW_NOW_CMD="echo 1700000100" bash "$C" >"$T/o_r3b" 2>&1
has "R3 _desk 없음 = 판정 불가 1줄" "$(cat "$T/o_r3b")" "판정 불가 — 명부에 _desk 없음"
eq "R3 _desk 없음 = 알림 0통(성공 처리 0)" "$(lines "$SENT")" 0
[ -f "$FT_BGW_LEDGER.seen" ] && bad "R3 _desk 없음을 발신 완료로 기록" || ok "R3 _desk 없음 = 발신 완료 기록 0"
# R4 — 일반 감시의 stdout 파이프는 MCP 가 아니다(파이프만으로 제외 0)
printf '501 401 1 Mon Nov 10 10:00:00 2026 python3 /tmp/main-land-watch.py\n501 403 1 Mon Nov 10 10:00:00 2026 python3 /x/serena-mcp-server.py --loop 5\n' >"$T/ps.txt"
rm -f "$SENT" "$SENT.body" "$FT_BGW_LEDGER.seen"
FT_BGW_LSOF_CMD="bash $T/bin/lsof_all.sh {pid}" FT_BGW_NOW_CMD="echo 1700000100" bash "$C" >"$T/o_r4" 2>&1
has "R4 일반 감시 + stdout 파이프 = 알림 1통" "$(cat "$T/o_r4")" "NOTIFY 401 "
has "R4 현역 MCP(파이프+MCP 증거)는 그대로 제외" "$(cat "$T/o_r4")" "SKIP 403 현역 MCP(파이프 연결)"
eq "R4 알림 1통" "$(lines "$SENT")" 1

cat >"$T/ps.txt" <<'EOF'
501 201 1 Mon Nov 10 10:00:00 2026 bash /x/launchd-watch.sh --loop
501 202 1 Mon Nov 10 10:00:00 2026 /opt/homebrew/bin/tmux -L x new-session -d -s s
501 203 1 Mon Nov 10 10:00:00 2026 /Applications/Foo.app/Contents/MacOS/watchdog
501 204 1 Mon Nov 10 10:00:00 2026 /usr/local/bin/node server.js
501 205 0 Mon Nov 10 10:00:00 2026 bash /x/seat-watch.sh --loop
EOF
printf 'PID\tStatus\tLabel\n201\t0\tcom.byz.launchd-watch\n' >"$T/launchctl.txt"
: >"$FT_BGW_LEDGER"; rm -f "$SENT" "$SENT.body" "$FT_BGW_LEDGER.seen"
FT_BGW_NOW_CMD="echo 1700000100" bash "$C" >"$T/o9" 2>&1
has "ⓒ launchd 소유 = 알림 0" "$(cat "$T/o9")" "SKIP 201 launchd 소유"
has "ⓒ tmux 서버 = 알림 0" "$(cat "$T/o9")" "SKIP 202 tmux 서버"
has "ⓒ 사람 앱 = 알림 0" "$(cat "$T/o9")" "SKIP 203 사람 앱"
has "ⓒ 감시 꼴 아님 = 알림 0" "$(cat "$T/o9")" "SKIP 204 감시 꼴 아님"
hasnt "ⓒ 좌석 안(ppid≠1) = 대상 아님" "$(cat "$T/o9")" "205"
eq "ⓒ 오탐 0통" "$(lines "$SENT")" 0

FT_BGW_LSOF_CMD="bash $T/bin/lsof_pipe.sh {pid}"
rm -f "$T/killcalled"
printf '501 101 1 Mon Nov 10 10:00:00 2026 bash /x/main-land-watch.sh --loop 10\n' >"$T/ps.txt"
bash "$C" >/dev/null 2>&1; bash "$C" >/dev/null 2>&1
[ -f "$T/killcalled" ] && bad "M3 점검이 kill 호출" "$(cat "$T/killcalled")" || ok "M3 점검은 kill 0(실행 경로)"
hasnt "M3 점검 소스에 kill 0" "$(grep -v '^ *#' "$C")" "kill"

echo "── PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0
