#!/usr/bin/env bash
# test_seat_reap_cap25_r1406.sh — r1406: ft-seat-reap.sh 의 로컬 프로세스 조회 4곳(ps 실행기 · bg 헬퍼 · lsof cwd · lsof LISTEN)의
#   외부 호출 상한이 런타임 7초가 아니라 «로컬 하네스 25초»(판정 4114 · env FT_SEAT_REAP_CAP_SEC 1~70)를 쓴다.
#   부하 30+ 에서 lsof 가 7초를 넘겨 나노 닫기가 rc 20(CLOSE-FAIL)으로 멈추던 일 0 · 넘으면 지금처럼 rc 20 «판정 불가»(조용한 통과 0).
#   Q1 가짜 lsof LISTEN 12초 → 25초 상한 안 · reap rc0 left=0
#   Q2 가짜 lsof 26초 → rc 20 · 문구 «상한 25» · 끝 줄 left=?
#   Q3 FT_SEAT_REAP_CAP_SEC=abc → WARN + 25 · =10 → 가짜 12초에서 rc 20(«상한 10») · =71(범위 밖) → WARN + 25
#   Q4 가짜 lsof cwd 12초 → 통과(cwd 호출이 실제로 불렸는지 lsof 호출 기록으로 확인)
#   Q5 네 곳 모두 CAP(:57 실행기 · :98 bg 헬퍼 · :164 cwd · :181 LISTEN) · timeout=7 잔존 0 (변이 1·2 가 여기서도 걸린다)
#   기준판(옛 bin): R1406_REAP=<옛 bin/ft-seat-reap.sh> → Q1 FAIL(7초 상한에 12초가 걸린다) 이 기대값 · 변이: 한 곳만 7 로 되돌리면 Q1/Q4/Q5 FAIL · env 꼴 검사 삭제 → Q3 FAIL
# 가짜 lsof = $TMP/pbin 에 지연만 씌우고 실 lsof 로 넘긴다(읽기 전용) · 실 프로세스 kill 0 · 지연은 병렬로 돌려 시험 전체 ≤ 70초.
# 실 프로세스·tmux·네트워크·Redis 0 — reap 은 후보 0 인 좌석 이름으로만 부른다.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; KIT="$HERE/../../harness/kit/fable-team/bin"
REAP="${R1406_REAP:-$BIN/ft-seat-reap.sh}"
T0="$(mktemp -d)"; TMP="$(cd "$T0" && pwd -P)"; ST="$TMP/st"
mkdir -p "$ST/pbin" "$ST/defer" "$ST/wt/.git"; : > "$ST/ledger.tsv"; : > "$ST/lsof.calls"
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$T0"' EXIT   # 병렬 CASE 자식(이미 wait 했음) + 임시 폴더 정리
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:600}";; esac; }
rc()  { cat "$ST/$1.rc" 2>/dev/null || echo "?"; }
last() { tail -1 "$ST/$1.out"; }
LSOF="$(command -v lsof)" || { echo "FAIL lsof 없음 — 이 시험은 실 lsof 위에 지연만 씌운다"; exit 1; }

cat > "$ST/pbin/lsof" <<EOF
#!/usr/bin/env bash
# 가짜 lsof(시험 전용) — LISTEN/cwd 를 갈라 지연만 주입하고 실 lsof 로 넘긴다 · 호출 기록은 \$LSOF_CALLS
kind=other
case " \$* " in
  *" -iTCP "*) kind=listen;;
  *" -d cwd "*) kind=cwd;;
esac
[ -n "\${LSOF_CALLS:-}" ] && echo "\$kind \$*" >> "\$LSOF_CALLS" 2>/dev/null
d=0
[ "\$kind" = listen ] && d="\${FAKE_LSOF_LISTEN_DELAY:-0}"
[ "\$kind" = cwd ] && d="\${FAKE_LSOF_CWD_DELAY:-0}"
if [ -n "\$d" ] && [ "\$d" != 0 ]; then sleep "\$d"; fi
exec "$LSOF" "\$@"
EOF
chmod 755 "$ST/pbin/lsof"

bash -n "$REAP" && ok "bash -n ft-seat-reap.sh" || bad "bash -n $REAP"
[ -n "${R1406_REAP:-}" ] || { cmp -s "$BIN/ft-seat-reap.sh" "$KIT/ft-seat-reap.sh" && ok "짝 cmp0 ft-seat-reap.sh" || bad "짝 다름 ft-seat-reap.sh"; }

CASE() {   # CASE <태그> <좌석> <LISTEN 지연> <cwd 지연> <CAP env> [reap 인자…] — 병렬 실행(시험 전체 시간 = 가장 긴 하나)
  local tag="$1" seat="$2" ld="$3" cwd="$4" capv="$5"; shift 5
  ( export PATH="$ST/pbin:$PATH" FAKE_LSOF_LISTEN_DELAY="$ld" FAKE_LSOF_CWD_DELAY="$cwd" FT_SEAT_REAP_CAP_SEC="$capv"
    export LSOF_CALLS="$ST/lsof.calls" FT_BG_FINITE_LEDGER="$ST/ledger.tsv" FT_REAP_DEFER_DIR="$ST/defer"
    export FT_PERMIT_DIR="$ST/permits" FT_PRESS_RUNNER_RE="r1406-never-$$"
    bash "$REAP" "$seat" "$@" >"$ST/$tag.out" 2>&1; echo "$?" > "$ST/$tag.rc" ) &
}
T1=$SECONDS
CASE q1  "r1406a-$$#0" 12 0  ""
CASE q2  "r1406b-$$#0" 26 0  ""
CASE q3a "r1406c-$$#0" 0  0  "abc"
CASE q3b "r1406d-$$#0" 12 0  "10"
CASE q3c "r1406e-$$#0" 0  0  "71"
CASE q4  "r1406f-$$#0" 0  12 "" --wt "$ST/wt"
wait
Q=$((SECONDS - T1))

echo "== Q1 가짜 lsof LISTEN 12초 → 25초 상한 안(옛 7초 상한이면 여기서 rc 20)"
has "$(cat "$ST/lsof.calls")" "listen " "Q1 가짜 lsof LISTEN 이 실제로 불림"
chk "Q1 reap rc0" "$(rc q1)" 0
chk "Q1 끝 줄 left=0" "$(last q1)" "reap r1406a-$$#0 stopped=0 left=0 rc=0"

echo "== Q2 가짜 lsof 26초 → rc 20 «판정 불가» · 문구에 상한 초 1개"
chk "Q2 rc 20" "$(rc q2)" 20
has "$(cat "$ST/q2.out")" "상한 25" "Q2 문구 «상한 25»"
chk "Q2 끝 줄 left=?" "$(last q2)" "reap r1406b-$$#0 stopped=0 left=? rc=20"

echo "== Q3 env FT_SEAT_REAP_CAP_SEC 꼴 검사(1~70 정수만 · 틀리면 WARN + 25)"
chk "Q3a =abc → rc0(25로 진행)" "$(rc q3a)" 0
has "$(cat "$ST/q3a.out")" "FT_SEAT_REAP_CAP_SEC=abc" "Q3a WARN 값 노출"
has "$(cat "$ST/q3a.out")" "상한 25" "Q3a WARN 이 25 로 진행"
chk "Q3b =10 · 가짜 12초 → rc 20" "$(rc q3b)" 20
has "$(cat "$ST/q3b.out")" "상한 10" "Q3b 문구 «상한 10»"
chk "Q3c =71(범위 밖) → rc0(25로 진행)" "$(rc q3c)" 0
has "$(cat "$ST/q3c.out")" "FT_SEAT_REAP_CAP_SEC=71" "Q3c WARN 값 노출"

echo "== Q4 가짜 lsof cwd(:164) 12초 → 통과(네 곳 모두 같은 상한)"
has "$(cat "$ST/lsof.calls")" "cwd " "Q4 가짜 lsof cwd 가 실제로 불림(--wt 로 cwds 경로 진입)"
chk "Q4 reap rc0" "$(rc q4)" 0
chk "Q4 끝 줄 left=0" "$(last q4)" "reap r1406f-$$#0 stopped=0 left=0 rc=0"

echo "== Q5 네 곳 모두 CAP · 런타임 7초 잔존 0(변이 1·2 가 여기서도 걸린다)"
chk "Q5 timeout=CAP 4곳" "$(grep -c 'timeout=CAP' "$REAP")" 4
chk "Q5 timeout=7 잔존 0" "$(grep -c 'timeout=7' "$REAP")" 0
chk "Q5 기본 상한 25" "$(grep -c '^CAP = cap_sec()' "$REAP")" 1

echo "== 시간 — 병렬 실행 합계 $Q 초(단일 시험 상한 70초)"
[ "$Q" -le 70 ] && ok "시간 $Q 초 ≤ 70" || bad "시간 $Q 초 > 70 (병렬이 깨졌다)"

echo "== 결과: fail=$fail"
[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || exit 1
