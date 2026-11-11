#!/usr/bin/env bash
# test_leak_reap_server_sh_r1231.sh — r1231: 정리기(ft-leak-reap.sh) server.sh 갈래 — press 뒤 남은 `scripts/server/server.sh all`·tail -f 회수 (반례 R3~R7).
# 입력 = 가짜 ps 표(FT_PS_SNAPSHOT · 필드 5 · lstart 는 지금 기준 2시간·30분 전) + 가짜 lsof(FT_LSOF_CMD · LISTEN pid 표 · 호출 기록).
# --kill 은 «이 시험이 띄운» 가짜 server.sh(bash · 자식 tail -f) 한 벌만 표에 담는다 — 실 server.sh·실 프로세스 신호 0.
# 장부 = 임시 빈 파일(FT_BG_FINITE_LEDGER) — 실 하네스 상태 쓰기 0 · 자기 재호출 0 · 고정 sleep 0(상한 있는 조건 대기만).
# 변이: R1231_BIN=<변이 사본 폴더> bash <이 파일> → FAIL 이 나와야 한다.
# 사용: timeout 70 bash <이 파일> → 마지막 줄 RESULT pass=N fail=M · rc 0/1
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="${R1231_BIN:-$REPO/harness/bin}"; KIT="$REPO/harness/kit/fable-team/bin"
REAP="$BIN/ft-leak-reap.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"
cleanup() { pkill -TERM -f "$T/" 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT
trap 'exit 143' TERM INT
PASS=0; FAIL=0; START=$SECONDS
ok()  { PASS=$((PASS+1)); echo "PASS $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL $1"; }
has()   { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:400}";; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:400}";; *) ok "$3";; esac; }
alive() { kill -0 "$1" 2>/dev/null; }
until_ok() { local end=$((SECONDS + 5)); until eval "$1"; do [ "$SECONDS" -ge "$end" ] && return 1; sleep 0.05; done; }

[ -z "${R1231_BIN:-}" ] && { cmp -s "$BIN/ft-leak-reap.sh" "$KIT/ft-leak-reap.sh" && ok "키트 사본 cmp 0" || bad "키트 사본 어긋남"; }

: > "$T/ledger.tsv"
cat > "$T/fake-lsof" <<'EOF'
#!/bin/bash
echo "call $*" >> "$LSOF_LOG"
[ -n "${FAKE_LSOF_FAIL:-}" ] && { echo "lsof: boom" >&2; exit 1; }
for p in ${FAKE_LISTEN:-}; do printf 'p%s\nf3\n' "$p"; done
[ -n "${FAKE_LISTEN:-}" ] || exit 1
EOF
chmod +x "$T/fake-lsof"
lst() { LC_ALL=C date -r "$(( $(date +%s) - $1 ))" '+%a %b %e %H:%M:%S %Y' | tr -s ' '; }   # $1 = 몇 초 전
row() { printf '%6s %6s %s %10s %s\n' "$1" "$2" "$(lst "$3")" "$4" "$5"; }           # pid ppid 나이(초) time command
WT=/Users/x/BYZ-Agents/.worktrees/k7124-rep
# 실행: $1 = 표 · 나머지 = 정리기 인자 → OUT · RC · CALLS(이번 lsof 호출 수)
RUN() {
  local snap="$1"; shift; : > "$T/lsof.log"
  FT_PS_SNAPSHOT="$snap" FT_LSOF_CMD="$T/fake-lsof" LSOF_LOG="$T/lsof.log" FT_BG_FINITE_LEDGER="$T/ledger.tsv" \
    bash "$REAP" "$@" >"$T/out" 2>&1; RC=$?
  OUT="$(grep -v setlocale "$T/out")"   # 로켈 경고(mac 에 C.UTF-8 없음)는 비교에서 제외
  CALLS="$(grep -c . "$T/lsof.log")"
}

# R3 ⓐ server.sh all 2시간 · 자손 tail 1 · LISTEN 0 → 후보(server.sh + tail) · lsof 1회
{ row 1 0 900000 5:00.00 /sbin/launchd
  row 4187 4111 7200 0:00.03 "bash $WT/scripts/server/server.sh all --c2c-act-dev"
  row 4300 4187 7200 0:00.50 "tail -f /tmp/byz-gateway.log /tmp/byz-worker.log"
  row 4111 1 7300 0:00.10 "-zsh"; } > "$T/a.txt"
RUN "$T/a.txt" --dry-run
[ "$RC" = 10 ] && ok "R3 dry-run 발견 rc 10" || bad "R3 rc=$RC ← ${OUT:0:300}"
has "$OUT" "pid=4187" "R3 server.sh 후보"; has "$OUT" "pid=4300" "R3 자손 tail 후보"; hasnt "$OUT" "pid=4111" "R3 부모 셸은 대상 아님"
[ "$CALLS" = 1 ] && ok "R3 lsof 1회" || bad "R3 lsof 호출 $CALLS 회"

# R4 ⓑ 30분 → 회수 0 · lsof 0회(후보 없으면 부르지 않는다)
{ row 1 0 900000 5:00.00 /sbin/launchd
  row 4187 4111 1800 0:00.03 "bash $WT/scripts/server/server.sh all"
  row 4300 4187 1800 0:00.50 "tail -f /tmp/byz-gateway.log /tmp/byz-worker.log"; } > "$T/b.txt"
RUN "$T/b.txt" --dry-run
[ "$RC" = 0 ] && ok "R4 30분 → 유출 0 rc 0" || bad "R4 rc=$RC ← ${OUT:0:300}"
hasnt "$OUT" "pid=4187" "R4 server.sh 비후보"; [ "$CALLS" = 0 ] && ok "R4 lsof 0회" || bad "R4 lsof 호출 $CALLS 회"

# R5 ⓒ 2시간 · 자손 uvicorn LISTEN 8080(실제 서버 중) → 회수 0 · 누적 CPU 5초+ 도 회수 0
{ row 1 0 900000 5:00.00 /sbin/launchd
  row 4187 4111 7200 0:00.03 "bash $WT/scripts/server/server.sh all"
  row 4200 4187 7200 1:00.00 "$WT/.venv/bin/python $WT/.venv/bin/uvicorn gateway.main:app --reload --port 8080"
  row 4201 4200 7200 3:00.00 "$WT/.venv/bin/python -c from multiprocessing.spawn import spawn_main"
  row 4300 4187 7200 0:00.50 "tail -f /tmp/byz-gateway.log /tmp/byz-worker.log"
  row 5187 5111 7200 0:06.00 "bash /Users/x/wt2/scripts/server/server.sh all"; } > "$T/c.txt"
FAKE_LISTEN="4201 999" RUN "$T/c.txt" --dry-run
[ "$RC" = 0 ] && ok "R5 자손 LISTEN → 유출 0 rc 0" || bad "R5 rc=$RC ← ${OUT:0:300}"
hasnt "$OUT" "pid=4187" "R5 서버 중 server.sh 비후보"; hasnt "$OUT" "pid=5187" "R5 CPU 6초 server.sh 비후보"

# R6 ⓓ 옛 바쁜 루프(PPID=1 · CPU 40초) → 지금처럼 후보 · server.sh 후보 없으면 lsof 0회
{ row 1 0 900000 5:00.00 /sbin/launchd
  row 6001 1 600 0:40.00 "bash -c (while :; do :; done) & : x"; } > "$T/d.txt"
RUN "$T/d.txt" --dry-run
[ "$RC" = 10 ] && ok "R6 바쁜 루프 발견 rc 10" || bad "R6 rc=$RC ← ${OUT:0:300}"
has "$OUT" "pid=6001" "R6 바쁜 루프 후보(회귀)"; [ "$CALLS" = 0 ] && ok "R6 lsof 0회" || bad "R6 lsof 호출 $CALLS 회"

# R7 lsof 실패 → server.sh 갈래 판정 불가 1줄 · 회수 0 · 바쁜 루프 갈래는 그대로
cat "$T/a.txt" > "$T/e.txt"; row 6001 1 600 0:40.00 "bash -c (while :; do :; done) & : x" >> "$T/e.txt"
FAKE_LSOF_FAIL=1 RUN "$T/e.txt" --dry-run
[ "$RC" = 10 ] && ok "R7 바쁜 루프 그대로 rc 10" || bad "R7 rc=$RC ← ${OUT:0:300}"
has "$OUT" "pid=6001" "R7 바쁜 루프 후보"; hasnt "$OUT" "pid=4187" "R7 server.sh 회수 0"; hasnt "$OUT" "pid=4300" "R7 tail 회수 0"
[ "$(printf '%s\n' "$OUT" | grep -c '판정 불가')" = 1 ] && ok "R7 판정 불가 1줄" || bad "R7 판정 불가 줄 수 ≠ 1 ← ${OUT:0:300}"

# R3 --kill — 이 시험이 띄운 가짜 server.sh(자식 tail -f) 한 벌만 표에 담는다 → 둘 다 끝 + 회수 줄 1
mkdir -p "$T/wt/scripts/server"; : > "$T/wt/gw.log"
printf '#!/bin/bash\ntail -f %q &\nwait\n' "$T/wt/gw.log" > "$T/wt/scripts/server/server.sh"
bash "$T/wt/scripts/server/server.sh" all & SRV=$!
until_ok '[ -n "$(pgrep -P $SRV -x tail)" ]'; TL="$(pgrep -P "$SRV" -x tail | head -1)"
{ row 1 0 900000 5:00.00 /sbin/launchd
  row "$SRV" "$$" 7200 0:00.01 "bash $T/wt/scripts/server/server.sh all"
  row "${TL:-999999}" "$SRV" 7200 0:00.01 "tail -f $T/wt/gw.log"; } > "$T/k.txt"
RUN "$T/k.txt" --kill --quiet
[ "$RC" = 0 ] && ok "R3 --kill rc 0" || bad "R3 --kill rc=$RC ← ${OUT:0:300}"
until_ok "! alive $SRV && ! alive ${TL:-999999}" && ok "R3 --kill server.sh·tail 끝" || bad "R3 --kill 살아 있음"
[ "$(printf '%s\n' "$OUT" | grep -c "server.sh 회수 1건")" = 1 ] && ok "R3 회수 줄 1(--quiet 여도)" || bad "R3 회수 줄 ← ${OUT:0:400}"
has "$OUT" "$T/wt" "R3 회수 줄에 워크트리"

echo "단계별 초: 전체 $((SECONDS - START))"
echo "RESULT pass=$PASS fail=$FAIL"
[ "$FAIL" = 0 ]
