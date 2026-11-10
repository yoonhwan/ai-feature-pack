#!/usr/bin/env bash
# test_bg_watch_adopt_r1578.sh — 카드 r1578 «이미 도는 좌석 밖 감시를 kill 없이 장부에 올린다(--adopt) · hermes 데몬 면제» 수용 ⓐ~ⓕ + 변이 M1~M4
#   시험 입력 = 격리 폴더(mktemp) · 가짜 ps 표(FT_BGW_PS_CMD) · 가짜 시계 · 가짜 mbox · 가짜 tmux · 격리 장부 · 실제 좌석/실제 mbox/네트워크 호출 0
#   실행: bash test_bg_watch_adopt_r1578.sh  · rc0 = 전건 PASS · rc1 = FAIL 있음
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; W="$BIN/ft-bg-watch.sh"; C="$BIN/ft-bg-watch-check.sh"; R1572="$HERE/test_detached_watch_ttl_r1572.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/r1578.XXXXXX")"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()   { echo "PASS $1"; pass=$((pass+1)); }
bad()  { echo "FAIL $1${2:+ — $2}"; fail=$((fail+1)); }
eq()   { [ "$2" = "$3" ] && ok "$1" || bad "$1" "want=$3 got=$2"; }
has()  { case "$2" in *"$3"*) ok "$1";; *) bad "$1" "없음: $3";; esac; }
hasnt(){ case "$2" in *"$3"*) bad "$1" "있음: $3";; *) ok "$1";; esac; }
cnt()  { grep -c "$1" "$2" 2>/dev/null || true; }
lines(){ [ -f "$1" ] && wc -l <"$1" | tr -d ' ' || echo 0; }

# ── 가짜 도구 ────────────────────────────────────────────────────────────────
mkdir -p "$T/comm" "$T/state" "$T/seatsdir" "$T/bin"
cat >"$T/comm/mbox.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\t%s\n' "$2" "$3" >> "$SENT_LOG"
printf '%s\n' "$4" >> "$SENT_LOG.body"
EOF
cat >"$T/bin/tmux" <<'EOF'
#!/usr/bin/env bash
for a; do case "$a" in seat-A|seat-H) exit 0;; esac; done; exit 1
EOF
cat >"$T/bin/kill" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$T/killcalled"; exit 0
EOF
chmod 755 "$T/comm/mbox.sh" "$T/bin/"*
printf '%s\n' '{"_desk":"seat-H","seat-A":{"role":"nano"}}' >"$T/seatsdir/seats-planner.json"
: >"$T/launchctl.txt"
SENT="$T/sent.log"; TA="$T/anchor.tsv"; TB="$T/two.tsv"; TC="$T/hermes.tsv"
export SENT_LOG="$SENT" FT_MBOX_DIR="$T/comm" FT_BGW_LEDGER="$TA" FT_BGW_MBOX="$T/comm/mbox.sh" FT_BGW_UID=501 \
       FT_BGW_NOW_CMD="echo 1700000100" FT_BGW_PS_CMD="cat $T/ps.txt" FT_BGW_TMUX_CMD="bash $T/bin/tmux {seat}" \
       FT_BGW_SEATS_X="$T/seatsdir" FT_BGW_LAUNCHCTL_CMD="cat $T/launchctl.txt" FT_BGW_LSOF_CMD="true" \
       PATH="$T/bin:$PATH"
LST1="Mon Nov 10 10:00:00 2026"; LST2="Mon Nov 10 11:11:11 2026"
printf '501 9001 1 %s bash /x/anchor-watch.py --loop 10\n501 9002 1 %s bash /x/other-watch.sh --loop 5\n501 9003 2 %s bash /x/seat-watch.sh --loop 5\n501 9004 1 - bash /x/guard-watch.sh --loop 5\n502 9005 1 %s bash /x/alien-watch.sh --loop 5\n' \
  "$LST1" "$LST1" "$LST1" "$LST1" >"$T/ps.txt"
: >"$TA"

# ── ⓐ 등록(띄우지 않고 장부 1줄) + 필수 값 ───────────────────────────────────
out="$(bash "$W" --adopt 9001 --seat seat-A --until "anchor 끝" --end-at 1700009999 -- bash -c "touch $T/launched" 2>&1)"; rc=$?
eq "ⓐ adopt rc0" "$rc" 0
has "ⓐ 출력 1줄 = adopt pid·key·rc=0" "$out" "bg-watch adopt pid=9001 key=501:9001:$LST1:"
has "ⓐ 출력 rc=0" "$out" "rc=0"
eq "ⓐ 장부 adopt 1줄" "$(cnt $'^adopt\t' "$TA")" 1
eq "ⓐ 장부 up 줄 0(띄우지 않는다)" "$(cnt $'^up\t' "$TA")" 0
eq "ⓐ every 칸 = -" "$(awk -F'\t' '$1=="adopt"{print $8}' "$TA")" "-"
eq "ⓐ 끝 시각 적힘" "$(awk -F'\t' '$1=="adopt"{print $7}' "$TA")" 1700009999
eq "ⓐ 끝 조건 적힘" "$(awk -F'\t' '$1=="adopt"{print $9}' "$TA")" "anchor 끝"
[ -f "$T/launched" ] && bad "ⓐ adopt 가 1회 명령을 실행함(띄우면 안 된다)" || ok "ⓐ adopt 는 프로세스를 띄우지 않는다"
: >"$TA"
bash "$W" --seat seat-A --until x --end-at 1700009999 --adopt >/dev/null 2>&1;             eq "ⓐ --adopt 값 없음 = rc2" "$?" 2
bash "$W" --adopt 9001 --until x --end-at 1700009999 >/dev/null 2>&1;                eq "ⓐ --seat 없음 = rc2" "$?" 2
bash "$W" --adopt 9001 --seat seat-A --end-at 1700009999 >/dev/null 2>&1;            eq "ⓐ --until 없음 = rc2" "$?" 2
bash "$W" --adopt 9001 --seat seat-A --until x >/dev/null 2>&1;                      eq "ⓐ --end-at 없음 = rc2" "$?" 2
eq "ⓐ 거절 4회 = 장부 0줄" "$(lines "$TA")" 0

# ── ⓑ 거절 = rc2 · 쓰기 0 ────────────────────────────────────────────────────
out="$(bash "$W" --adopt 8999 --seat seat-A --until x --end-at 1700009999 2>&1)"; eq "ⓑ pid 없음 = rc2" "$?" 2
has "ⓑ pid 없음 사유" "$out" "판정 불가 프로세스 없음"
out="$(bash "$W" --adopt 9005 --seat seat-A --until x --end-at 1700009999 2>&1)"; eq "ⓑ 내 uid 아님 = rc2" "$?" 2
has "ⓑ uid 사유" "$out" "내 uid 아님"
out="$(bash "$W" --adopt 9003 --seat seat-A --until x --end-at 1700009999 2>&1)"; eq "ⓑ ppid ≠ 1 = rc2" "$?" 2
has "ⓑ ppid 사유" "$out" "고아가 아니다"
out="$(bash "$W" --adopt 9004 --seat seat-A --until x --end-at 1700009999 2>&1)"; eq "ⓑ 시작 시각 없음 = rc2" "$?" 2
has "ⓑ 시작 시각 사유" "$out" "시작 시각을 못 읽음"
out="$(bash "$W" --adopt 9001 --seat seat-A --until x --end-at 1700000000 2>&1)"; eq "ⓑ 끝 시각 지남 = rc2" "$?" 2
has "ⓑ 끝 시각 사유" "$out" "끝 시각이 이미 지났다"
bash "$W" --adopt abc --seat seat-A --until x --end-at 1700009999 >/dev/null 2>&1; eq "ⓑ pid 숫자 아님 = rc2" "$?" 2
eq "ⓑ 거절 6회 = 장부 0줄" "$(lines "$TA")" 0

# ── ⓒ 점검 대조(장부 안 · 기한 뒤 알림 · kill 0) + 변이 M4 ───────────────────
printf '501 9001 1 %s bash /x/anchor-watch.py --loop 10\n' "$LST1" >"$T/ps.txt"   # 이 절은 점검 대상 1개만 둔다
bash "$W" --adopt 9001 --seat seat-A --until x --end-at 1700009999 >/dev/null 2>&1
rm -f "$SENT" "$SENT.body" "$TA.seen"
FT_BGW_NOW_CMD="echo 1700000100" bash "$C" >"$T/c1" 2>&1; eq "ⓒ 점검 rc0" "$?" 0
has "ⓒ adopt 줄 = 장부 안(알림 0)" "$(cat "$T/c1")" "SKIP 9001 장부 안·기한 전"
eq "ⓒ 기한 전 = 알림 0통" "$(lines "$SENT")" 0
sed -i '' 's/1700009999/1700000050/' "$TA" 2>/dev/null || sed -i 's/1700009999/1700000050/' "$TA"
rm -f "$SENT" "$SENT.body" "$TA.seen"
FT_BGW_NOW_CMD="echo 1700000100" bash "$C" >"$T/c2" 2>&1
has "ⓒ adopt 줄 기한 지남 = NOTIFY" "$(cat "$T/c2")" "NOTIFY 9001 "
has "ⓒ 사유 = 기한지남" "$(cat "$T/c2")" "기한지남"
eq "ⓒ 소유 좌석 1통" "$(cut -f1 "$SENT")" "seat-A"
[ -f "$T/killcalled" ] && bad "ⓒ 점검이 kill 호출" "$(cat "$T/killcalled")" || ok "ⓒ 점검 kill 0"
python3 - "$C" "$T/c_m4.py" <<'PYM'
import sys
s = open(sys.argv[1], encoding="utf-8").read()
old = 'if f[0] in ("up", "adopt"):'
assert old in s, "M4 변이 대상 못 찾음"
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(old, 'if f[0] == "up":'))
PYM
cp "$T/c_m4.py" "$T/c_m4.sh"
printf '501 9001 1 %s bash /x/anchor-watch.py --loop 10\n' "$LST1" >"$T/ps.txt"
bash "$W" --adopt 9001 --seat seat-A --until x --end-at 1700009999 >/dev/null 2>&1
rm -f "$SENT" "$SENT.body" "$TA.seen"
FT_BGW_NOW_CMD="echo 1700000100" bash "$T/c_m4.sh" >"$T/c_m4o" 2>&1
has "M4 변이(adopt 줄을 장부 밖으로 셈) = 검출" "$(cat "$T/c_m4o")" "NOTIFY 9001 501:9001:$LST1:"

# ── ⓓ 인스턴스 키 유지(다른 lstart = 새 인스턴스) + 변이 M2 ──────────────────
printf '501 9001 1 %s bash /x/anchor-watch.py --loop 10\n' "$LST1" >"$T/ps.txt"
: >"$TA"; bash "$W" --adopt 9001 --seat seat-A --until x --end-at 1700009999 >/dev/null 2>&1
printf '501 9001 1 %s bash /x/anchor-watch.py --loop 10\n' "$LST2" >"$T/ps2.txt"
rm -f "$SENT" "$SENT.body" "$TA.seen"
FT_BGW_PS_CMD="cat $T/ps2.txt" FT_BGW_NOW_CMD="echo 1700000100" bash "$C" >"$T/d1" 2>&1
has "ⓓ 같은 pid·다른 lstart = 새 인스턴스(알림 1통)" "$(cat "$T/d1")" "NOTIFY 9001 501:9001:$LST2:"
eq "ⓓ 새 인스턴스 1통" "$(lines "$SENT")" 1
python3 - "$W" "$T/w_m2.sh" <<'PYM'
import sys
s = open(sys.argv[1], encoding="utf-8").read()
old = 'ROW adopt "$SEAT" "$A_UID" "$ADOPT" "$A_LST" "$A_CMDH"'
assert old in s, "M2 변이 대상 못 찾음"
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(old, 'ROW adopt "$SEAT" "$A_UID" "$ADOPT" "" "$A_CMDH"'))
PYM
: >"$TA"; printf '501 9001 1 %s bash /x/anchor-watch.py --loop 10\n' "$LST1" >"$T/ps.txt"
bash "$T/w_m2.sh" --adopt 9001 --seat seat-A --until x --end-at 1700009999 >/dev/null 2>&1
rm -f "$SENT" "$SENT.body" "$TA.seen"
FT_BGW_NOW_CMD="echo 1700000100" bash "$C" >"$T/d2" 2>&1
has "M2 변이(lstart 대신 빈칸) = 검출" "$(cat "$T/d2")" "NOTIFY 9001 501:9001:"

# ── ⓔ hermes 데몬 면제(모듈 꼴만) + 변이 M3 ──────────────────────────────────
cat >"$T/ps.txt" <<EOF
501 9101 1 $LST1 python3 -m browser_harness.daemon --port 1
501 9102 1 $LST1 /x/harness/python /x/browser_harness/daemon.py
501 9103 1 $LST1 bash /x/hermes-watch.sh --loop 10
EOF
: >"$TC"; rm -f "$SENT" "$SENT.body" "$TC.seen"
FT_BGW_LEDGER="$TC" FT_BGW_NOW_CMD="echo 1700000100" bash "$C" >"$T/e1" 2>&1
has "ⓔ 모듈 꼴(python -m browser_harness.daemon) = 면제" "$(cat "$T/e1")" "SKIP 9101 hermes 데몬"
has "ⓔ 경로 꼴(…/browser_harness/daemon.py) = 면제" "$(cat "$T/e1")" "SKIP 9102 hermes 데몬"
has "ⓔ «hermes» 글자만 있는 감시는 면제 0" "$(cat "$T/e1")" "NOTIFY 9103 "
eq "ⓔ 알림 = hermes-watch.sh 1통뿐" "$(lines "$SENT")" 1
python3 - "$C" "$T/c_m3.py" <<'PYM'
import sys
s = open(sys.argv[1], encoding="utf-8").read()
old = '    if HERMESRE.search(cmd): return "hermes 데몬"'
assert old in s, "M3 변이 대상 못 찾음"
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(old, '    if "hermes" in cmd.lower(): return "hermes 데몬"'))
PYM
cp "$T/c_m3.py" "$T/c_m3.sh"; rm -f "$SENT" "$SENT.body" "$TC.seen"
FT_BGW_LEDGER="$TC" FT_BGW_NOW_CMD="echo 1700000100" bash "$T/c_m3.sh" >"$T/e2" 2>&1
has "M3 변이(«hermes» 글자 포함 면제) = 검출" "$(cat "$T/e2")" "SKIP 9103 hermes 데몬"

# ── 변이 M1(ppid 검사 빼기) ──────────────────────────────────────────────────
python3 - "$W" "$T/w_m1.sh" <<'PYM'
import sys
s = open(sys.argv[1], encoding="utf-8").read()
old = '  [ "$A_PPID" = "1" ] ||'
assert old in s, "M1 변이 대상 못 찾음"
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(old, '  true ||'))
PYM
printf '501 9003 2 %s bash /x/seat-watch.sh --loop 5\n' "$LST1" >"$T/ps.txt"
out="$(FT_BGW_LEDGER="$T/m1.tsv" bash "$T/w_m1.sh" --adopt 9003 --seat seat-A --until x --end-at 1700009999 2>&1)"; rc=$?
eq "M1 변이(ppid 검사 없음) = rc2 여야 하는데 rc0 = 검출" "$rc" 0
has "M1 변이 검출 근거 = 장부에 adopt 가 쌓임" "$out" "rc=0"

# ── ⓕ 불변: r1572 시험 그대로 ────────────────────────────────────────────────
out="$( (unset FT_BGW_LEDGER FT_BGW_UID FT_BGW_MBOX FT_BGW_NOW_CMD FT_BGW_PS_CMD FT_BGW_TMUX_CMD FT_BGW_SEATS_X FT_BGW_LAUNCHCTL_CMD FT_BGW_LSOF_CMD FT_BGW_SEEN FT_BGW_DESK SENT_LOG FT_MBOX_DIR; timeout 70 bash "$R1572" ) 2>&1)"; rc=$?
eq "ⓕ r1572 시험 rc0" "$rc" 0
has "ⓕ r1572 시험 76 PASS 유지" "$out" "PASS=76 FAIL=0"

echo "── PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0
