#!/usr/bin/env bash
# test_merge_land_slot_wait_r1386.sh — r1386 ft-merge-land «무거운 git 자리» 대기 상한 = min(FT_HEAVY_WAIT_S(기본 30), LIM − 경과 − 예약 35초)
#   W1 자리 2개 참 · 3초 뒤 1개 풂 · 기본 env → 기다렸다 잡고 착지(rc0 · REJECT 0 · main 전진)
#   W2 자리 2개 계속 참 · FT_HEAVY_WAIT_S=4 → 약 4초 뒤 «무거운 git 자리 없음(… 대기 4초 초과 …)» rc1 · 착지 0
#   W3 FT_HEAVY_WAIT_S=6 · 5초 뒤 풂 → 잡음(env 값이 실제로 닿는다) — 자리 통과 뒤 fetch 에서 멈추는 유생 PR 로 확인
#   W4 FT_LAND_TOTAL_S=40 → 상한 = min(30, 40−경과−35) ≈ 5 → 6초 쥐면 «대기 1~5초 초과» rc1 · 총 시간 ≤ LIM
#   W5 FT_LAND_TOTAL_S=30 → 상한 음수 = 0 → 지금처럼 한 번만 시도 rc1 · 3초 안
#   W6 FT_HEAVY_SLOTS=0 → 자리 검사 0 → 자리 2개 참이어도 착지 rc0
#   변이 1(상한 0 복원) → W2 FAIL(«대기 0초 초과» 즉시) · 변이 2(예약 계산 삭제) → W4 FAIL · 변이 3(env 무시 상수 30) → W2 FAIL
#   실 원격·실 gh·실 자리 0 · 자기 재호출 0 · 고정 sleep 0(쥔 쪽 해제는 경과 초 폴링) · 시험 1개 상한 70초
set -uo pipefail
export FT_AUTONOMY_LEVEL=each FT_MERGE_LAND_CODE_AUTOMERGE=0
[ -z "${FT_R1386_REENTRY:-}" ] || { echo "FAIL 재진입"; exit 1; }
export FT_R1386_REENTRY=1
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export FT_HEAVY_POLL_SEC=0.25   # 대기 폴링 간격(기본 1초) — 시험 시간 상한 안에 6갈래를 돌리기 위해 좁힌다(동작 계약 아님)
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; LAND="$BIN/ft-merge-land.sh"; LIBD="$BIN/ft-heavy-slot-lib.sh"
. "$HERE/_merge_fixture.sh"
fail=0; BAD=""; BG=()
T="$(mktemp -d "${TMPDIR:-/tmp}/r1386.XXXXXX")"
trap 'for p in ${BG[@]+"${BG[@]}"}; do kill -9 "$p" 2>/dev/null; done; rm -rf "$T"' EXIT
ok(){ :; }; bad(){ echo "FAIL $1" >&2; fail=$((fail+1)); BAD="$BAD $1"; }
run(){ local n="$1" f="$2"; if "$f"; then return 0; fi; bad "$n"; return 1; }
ms(){ python3 -c 'import time;print(int(time.time()*1000))'; }
waitfor(){ local i; for i in $(seq 1 300); do [ -e "$1" ] && return 0; command sleep 0.03; done; return 1; }
probe(){ local f="$1" fd=9; { exec 9>>"$f"; } 2>/dev/null || return 2   # r1338: 고정 fd(bash 3.2)
  perl -MFcntl=:flock -e 'open(my $h, ">&=", $ARGV[0]) or exit 3; flock($h, LOCK_EX|LOCK_NB) or exit 1;' "$fd" 2>/dev/null
  local rc=$?; exec 9>&-; return $rc; }
hold(){ # <자리폴더> <이름> [풀리는 초] → holder 가 자리를 쥔다(초 없으면 stop 파일까지)
  local d="$1" n="$2" secs="${3:-}"; mkdir -p "$d"
  cat > "$T/hold-$n.sh" <<EOF
#!/usr/bin/env bash
export FT_HEAVY_DIR="$d"
. "$LIBD"
hs_acquire "$n" 0 >/dev/null || exit 1
trap 'hs_release' EXIT
touch "$T/held.$n"
s=\$(date +%s)
while [ ! -f "$T/stop.$n" ]; do
  [ -z "$secs" ] || [ \$(( \$(date +%s) - s )) -lt "$secs" ] || break
  command sleep 0.03
done
EOF
  rm -f "$T/held.$n" "$T/stop.$n"; bash "$T/hold-$n.sh" 2>/dev/null & BG+=($!); waitfor "$T/held.$n"; }
rel(){ touch "$T/stop.$1"; }
stopall(){ for p in ${BG[@]+"${BG[@]}"}; do kill -9 "$p" 2>/dev/null; done; BG=(); }
freewait(){ local i; for i in $(seq 1 200); do probe "$T/m/hs/slot-1.lock" >/dev/null 2>&1 && probe "$T/m/hs/slot-2.lock" >/dev/null 2>&1 && return 0; command sleep 0.03; done; return 1; }

# ── merge-land 준비(실 원격·실 gh 0) ──────────────────────────────
mkrepo "$T/m"; mkdir -p "$T/m/state" "$T/m/.fable-team" "$T/m/hs"
export FT_ROOT="$T/m" FT_AUTONOMY_STATE_DIR="$T/m/state" FT_GH="$T/m/gh-stub" FT_GH_WRITE="$T/m/gh-stub" \
       FT_RES_ROOT="$T/m" FT_HEAVY_DIR="$T/m/hs" STUB_JSON="$T/m/pr.json" STUB_LOG="$T/m/gh.log" \
       FT_INSTALL_CHECK="$T/m/install-stub" FT_INSTALL_CHECK_TIMEOUT=2
cat > "$T/m/gh-stub" <<'EOF'
#!/usr/bin/env bash
[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }
case "$1" in pr-close|pr-comment) exit 0;; *) echo "BADVERB $*" >> "$STUB_LOG"; exit 2;; esac
EOF
chmod +x "$T/m/gh-stub"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/m/install-stub"; chmod +x "$T/m/install-stub"   # 착지 뒤 설치 검사 = 이 카드 대상 아님(수십 초 소모) → 통과 스텁
N=0
apvfast(){ # 시험용 승인 기록 — ft-autonomy.sh approve-merge 와 «같은 파일·같은 줄» 을 직접 쓴다(승인 기제는 r336 계약 · 이 카드 대상 아님 · 9회 호출 시간을 줄인다)
  local s="$1" d="$FT_AUTONOMY_STATE_DIR/autonomy-merge-approved" ln; mkdir -p "$d"; ln="approve-merge $s OFF $(date +%s)"
  printf '%s\n' "$ln" > "$d/$s"; printf '%s\n' "$ln" >> "$FT_AUTONOMY_STATE_DIR/autonomy.log"; }
mkpr(){ N=$((N+1)); local b="pr$N"; git -C "$W" fetch -q origin; git -C "$W" checkout -q -B "$b" origin/main
  echo "pr $N" > "$W/pr$N.txt"; cm "$W" "pr $N work"; git -C "$W" push -q origin "$b:refs/pull/$N/head"; PRSHA="$(sha "$W" HEAD)"; PRN="$N"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"headRefName":sys.argv[2],"isCrossRepository":False,"title":"feat: PR "+sys.argv[3],"body":"본문 "+sys.argv[3],"state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$b" "$N" > "$STUB_JSON"
  apvfast "$PRSHA"; }
LA=(); MAINBEFORE=""
mkph(){ PHRASE=$(( ${PHRASE:-0} + 1 )); PRN="9$PHRASE"; PRSHA="$(sha "$W" HEAD)"   # 유령 PR — refs/pull 도 가지도 없다(자리 통과 «뒤» fetch 에서 멈춘다 = 자리 게이트를 통과했다는 표식) · 착지 꽃길 비용 0
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"headRefName":sys.argv[2],"isCrossRepository":False,"title":"feat: phantom "+sys.argv[3],"body":"phantom","state":"OPEN","baseRefName":"main"}))' "$PRSHA" "no-such-branch-$PHRASE" "$PRN" > "$STUB_JSON"
  apvfast "$PRSHA"; }
runl(){ local t0 t1; MAINBEFORE="$(sha "$ORIGIN" refs/heads/main)"; t0="$(ms)"
  out="$(cd "$W" && env "${LA[@]}" bash "$LAND" "$PRN" --approve-sha "$PRSHA" --repo "$W" 2>&1)"; rc=$?
  t1="$(ms)"; el=$(( (t1-t0)/1000 )); }
caseprep(){ stopall; freewait || { echo "  자리 안 풀림" >&2; return 1; }; }

W1(){ caseprep || return 1; mkpr; : > "$STUB_LOG"; hold "$T/m/hs" a1 3 || return 1; hold "$T/m/hs" a2 || return 1
  LA=(); runl; stopall
  [ "$rc" = 0 ] || { echo "  W1 rc=$rc el=${el}s out=${out:0:400}" >&2; return 1; }
  case "$out" in *LANDED*) ;; *) echo "  W1 LANDED 없음: ${out:0:300}" >&2; return 1;; esac
  case "$out" in *REJECT*) echo "  W1 REJECT 있음: ${out:0:300}" >&2; return 1;; esac
  [ "$el" -ge 2 ] || { echo "  W1 안 기다림 ${el}s" >&2; return 1; }
  [ "$(sha "$ORIGIN" refs/heads/main)" != "$MAINBEFORE" ] || { echo "  W1 main 그대로" >&2; return 1; }; }
W2(){ caseprep || return 1; mkpr; hold "$T/m/hs" b1 "${HREL:-12}" || return 1; hold "$T/m/hs" b2 "${HREL:-12}" || return 1
  LA=("FT_HEAVY_WAIT_S=4"); runl; stopall
  [ "$rc" = 1 ] || { echo "  W2 rc=$rc el=${el}s out=${out:0:300}" >&2; return 1; }
  printf '%s' "$out" | grep -q '무거운 git 자리 없음' || { echo "  W2 문구: ${out:0:300}" >&2; return 1; }
  printf '%s' "$out" | grep -q '대기 [45]초 초과' || { echo "  W2 대기 초: ${out:0:300}" >&2; return 1; }
  { [ "$el" -ge 3 ] && [ "$el" -le 20 ]; } || { echo "  W2 경과 ${el}s" >&2; return 1; }
  [ "$(sha "$ORIGIN" refs/heads/main)" = "$MAINBEFORE" ] || { echo "  W2 main 움직임" >&2; return 1; }; }
W3(){ caseprep || return 1; mkph; hold "$T/m/hs" c1 5 || return 1; hold "$T/m/hs" c2 "${HREL:-12}" || return 1
  LA=("FT_HEAVY_WAIT_S=6"); runl; stopall
  [ "$rc" = 1 ] || { echo "  W3 rc=$rc el=${el}s out=${out:0:300}" >&2; return 1; }
  printf '%s' "$out" | grep -q 'PR head fetch 실패' || { echo "  W3 자리 통과 못함(env 6): ${out:0:300}" >&2; return 1; }
  case "$out" in *"무거운 git 자리 없음"*) echo "  W3 자리 거절: ${out:0:300}" >&2; return 1;; esac
  [ "$el" -ge 1 ] || { echo "  W3 안 기다림 ${el}s" >&2; return 1; }; }
W4(){ caseprep || return 1; mkph; hold "$T/m/hs" d1 "${HREL:-12}" || return 1; hold "$T/m/hs" d2 "${HREL:-12}" || return 1
  LA=("FT_LAND_TOTAL_S=40"); runl; stopall
  [ "$rc" = 1 ] || { echo "  W4 rc=$rc el=${el}s out=${out:0:300}" >&2; return 1; }
  printf '%s' "$out" | grep -q '대기 [1-5]초 초과' || { echo "  W4 대기 초(예약 35 반영 · 상한 ≤ 5): ${out:0:300}" >&2; return 1; }
  [ "$el" -le 40 ] || { echo "  W4 총 시간 ${el}s > LIM 40" >&2; return 1; }
  [ "$(sha "$ORIGIN" refs/heads/main)" = "$MAINBEFORE" ] || { echo "  W4 main 움직임" >&2; return 1; }; }
W5(){ caseprep || return 1; mkph; hold "$T/m/hs" e1 "${HREL:-12}" || return 1; hold "$T/m/hs" e2 "${HREL:-12}" || return 1
  LA=("FT_LAND_TOTAL_S=30"); runl; stopall
  [ "$rc" = 1 ] || { echo "  W5 rc=$rc el=${el}s out=${out:0:300}" >&2; return 1; }
  printf '%s' "$out" | grep -q '대기 0초 초과' || { echo "  W5 상한 0 아님: ${out:0:300}" >&2; return 1; }
  [ "$el" -le 3 ] || { echo "  W5 한 번만 시도 아님 ${el}s" >&2; return 1; }; }
W6(){ caseprep || return 1; mkph; hold "$T/m/hs" f1 "${HREL:-12}" || return 1; hold "$T/m/hs" f2 "${HREL:-12}" || return 1
  LA=("FT_HEAVY_SLOTS=0"); runl; stopall
  printf '%s' "$out" | grep -q 'PR head fetch 실패' || { echo "  W6 자리 검사 0 아님: ${out:0:300}" >&2; return 1; }
  case "$out" in *"무거운 git 자리 없음"*) echo "  W6 자리 거절: ${out:0:300}" >&2; return 1;; esac
  [ "$el" -le 3 ] || { echo "  W6 느림 ${el}s" >&2; return 1; }; }

CASES="${FT_CASES:-W1 W2 W3 W4 W5 W6}"
want(){ case " $CASES " in *" $1 "*) return 0;; esac; return 1; }
runv(){ local c="$1" n="$2" f="$3" hr="${4:-6.5}"; want "$c" || return 0; echo "  변이 $n → $f · LAND=${LAND##*/}(${LAND%/*}) HREL=$hr" >&2; if HREL="$hr" "$f"; then bad "변이 $n — $f 통과"; else echo "변이 $n → $f FAIL(정상)"; fi; }
for c in $CASES; do _t=$SECONDS; run "$c" "$c"; echo "  [$c $((SECONDS-_t))초]" >&2; done
mkvar(){ # <이름> <파일> <python 치환> → 변이 폴더(bin 전체 링크)의 같은 이름 파일
  local d="$T/vb-$1" out f; mkdir -p "$d" || return 1
  for f in "$BIN"/*; do ln -sf "$f" "$d/${f##*/}" 2>/dev/null || true; done
  out="$d/${2##*/}"; rm -f "$out"; python3 -I - "$2" "$out" "$3" <<'PY' || return 1
import sys
s = open(sys.argv[1], encoding="utf-8").read()
ns = {"s": s}; exec(sys.argv[3], ns)
assert ns["s"] != s
open(sys.argv[2], "w", encoding="utf-8").write(ns["s"])
PY
}
L0="$LAND"
mkvar 1 "$L0" 's = s.replace("""hs_acquire land \"$HW\"""", """hs_acquire land 0""")' \
  && { LAND="$T/vb-1/ft-merge-land.sh"; runv W2 "1(상한 0 복원)" W2 12; }
LAND="$L0"; mkvar 2 "$L0" 's = s.replace("""HRM=$((LIM - (SECONDS - T0) - HRS))""", """HRM=$((LIM - (SECONDS - T0)))""")' \
  && { LAND="$T/vb-2/ft-merge-land.sh"; runv W4 "2(예약 계산 삭제)" W4; }
LAND="$L0"; mkvar 3 "$L0" 's = s.replace("""HW=\"${FT_HEAVY_WAIT_S:-30}\"""", """HW=30""")' \
  && { LAND="$T/vb-3/ft-merge-land.sh"; runv W2 "3(env 무시 상수 30)" W2; }
LAND="$L0"
[ -z "$BAD" ] && { echo "ALL PASS"; exit 0; }
echo "FAILED $fail$BAD"; exit 1
