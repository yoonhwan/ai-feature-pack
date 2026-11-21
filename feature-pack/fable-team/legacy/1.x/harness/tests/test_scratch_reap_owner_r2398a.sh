#!/usr/bin/env bash
# test_scratch_reap_owner_r2398a.sh — r2398a K1: ft-scratch-repo.sh --reap-owner <옛 좌석> = 은퇴한 좌석의 사본을 «출구 게이트 그대로» 지운다(대리 제거).
#   조건 = tmux 세션 «<옛 좌석>» 없음(있으면 REJECT rc2 · 삭제 0) · 등록부에서 주인 = <옛 좌석> 인 사본마다 delete_copy(r897 그대로 — 점유·더러움 = 거절 · 삭제 0) ·
#   좌석당 상한 = min(5초 + 7초×개수, 70초) · 넘긴 사본은 정리기 몫 · 끝 줄 «REAP <옛 좌석> done=N refused=N left=N» 1줄 ·
#   ft-seat-retire 는 마지막(좌석 세션 닫기 뒤)에 이 동사를 1회 부르고 결과 줄 1(REAP|REJECT|ERROR · 그 밖은 WARN 1줄) 만 찍는다 — 그 rc 는 은퇴 rc 를 바꾸지 않는다.
# 사례 = ① 없음+깨끗 2·더러움 1 → done=2 refused=1(더러운 사본·등록 줄 남음) · ② 세션 살아 있음 → REJECT rc2 · 삭제 0 / 사본 12개·사본 1개 7초(가짜) → left ≥ 1 · 회차 ≤ 70초 ·
#        ③ ft-seat-retire(가짜 tmux · kill 뒤) → --reap-owner 1회 · REAP 줄 1 · reap 실패도 은퇴 rc 그대로 · ④ (정정1) 지우기 도중 주인 재등장 = 그 사본부터 삭제 0 · ⑤ (정정2 DA #364832) 사전 확인 «뒤» 재등장 = 출구 게이트 G6 가 막는다
# 변이(원본과 같은 사례 1회 대조) = M1 세션 없음 조건 뺌 → ② 가 빨강 · M2 delete_copy 대신 rm -rf → ① 이 빨강(더러운 사본이 사라짐)
# 임시 저장소·가짜 tmux·가짜 lsof·가짜 명부만 쓴다 — 실 저장소·실 세션·실 명부·실 TMPDIR 0 · sleep 0(시계는 주입)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/.." && pwd)"
SUT="${FT_SUT:-$REPO/bin/ft-scratch-repo.sh}"   # FT_SUT = 변이 판(원본 대조) 실행용
RETIRE="$REPO/bin/ft-seat-retire.sh"
fail=0
ONLY="${FT_TEST_ONLY:-}"   # FT_TEST_ONLY=①,② = 그 칸만(하드 룰 22 · 한 칸 70초 안)
want() { [ -z "$ONLY" ] && return 0; printf '%s\n' "$ONLY" | tr ',' '\n' | grep -qx "$1"; }
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
[ -f "$SUT" ] || { bad "ft-scratch-repo.sh 없음 ($SUT)"; echo "(1 failed)"; exit 1; }
[ -f "$RETIRE" ] || { bad "ft-seat-retire.sh 없음 ($RETIRE)"; echo "(1 failed)"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
G="$T/src"; R="$T/R"; SCR="$T/scratch"; BIN="$T/bin"; STATE="$R/.fable-team/state"; TSV="$STATE/scratch-repos.tsv"
mkdir -p "$G" "$STATE" "$SCR" "$BIN"
git -C "$G" init -q && echo a > "$G/a.txt" && git -C "$G" add a.txt && git -C "$G" -c user.name=t -c user.email=t@t commit -q -m c1
SHA="$(git -C "$G" rev-parse HEAD)"

# ── 가짜 도구 ────────────────────────────────────────────────────────────────────────────────
#   tmux = $T/sessions 그대로 · lsof = 인자에 절대경로가 없으면 전체 지도(그 1회가 STEP 초를 먹는다 = «사본 1개 7초» 가짜) · 있으면 rc1(점유 없음)
cat > "$BIN/tmux" <<EOF
#!/bin/sh
[ "\${1:-}" = list-sessions ] || exit 0
# r2398a 정정1 대역: $T/sessions.late 가 있으면 «두 번째 호출부터» 그 목록(주인이 지우기 도중 다시 보임)
n=\$(cat "$T/tmux.n" 2>/dev/null || echo 0); n=\$((n+1)); echo \$n > "$T/tmux.n"
if [ "\${SWAP_AT:-0}" != 0 ] && [ "\$n" -ge "\${SWAP_AT:-0}" ] && [ -f "$T/sessions.late" ]; then cat "$T/sessions.late"; exit 0; fi
cat "$T/sessions" 2>/dev/null
exit 0
EOF
cat > "$BIN/lsof" <<EOF
#!/bin/sh
path=""
for a in "\$@"; do case "\$a" in /*) path="\$a";; esac; done
[ -n "\$path" ] && exit 1
if [ "\${STEP:-0}" != 0 ]; then n=\$(cat "$T/clock" 2>/dev/null || echo 1000000); echo \$((n + STEP)) > "$T/clock"; fi
cat "$T/lsof.all" 2>/dev/null
exit 0
EOF
cat > "$BIN/date" <<EOF
#!/bin/sh
case "\${1:-}" in
  +%s) cat "$T/clock" 2>/dev/null || exec "$(command -v date)" +%s;;
  *) exec "$(command -v date)" "\$@";;
esac
EOF
chmod 755 "$BIN/tmux" "$BIN/lsof" "$BIN/date"

MUTB="$T/mutbin"   # 변이 판 자리 — 원본 옆 동료 lib 를 symlink 로 붙인다(밖에 두면 ft-heavy-slot-lib.sh 를 못 찾아 조용히 삭제 0 · r1029 ⓓ 교훈)
mkdir -p "$MUTB"; for f in "$(dirname -- "$SUT")"/*; do [ "$(basename -- "$f")" = "$(basename -- "$SUT")" ] || ln -sfn "$f" "$MUTB/"; done
mkcopy() { # <번호> [dirty] → 경로 · 진짜 git worktree(detached · 깨끗) + 등록 줄(주인 gone-seat · 25시간 전)
  local d="$SCR/repo-0123abcd-$1-1"
  git -C "$G" worktree add --detach -q "$d" "$SHA" >/dev/null 2>&1
  printf '%s\t%s\t%s\t%s\n' "$d" "gone-seat" "$(( $(date +%s) - 90000 ))" "$SCR" >> "$TSV"
  [ "${2:-}" = dirty ] && echo x > "$d/dirty.txt"
  printf '%s\n' "$d"
}
reset() {
  rm -rf "$STATE" "$SCR"; mkdir -p "$STATE" "$SCR"
  : > "$TSV"; printf 'live-owner\n' > "$T/sessions"; printf 'p1\ncinit\nfcwd\nn/\n' > "$T/lsof.all"
  printf '%s\n' "$(( $(date +%s) + 1000 ))" > "$T/clock"; : > "$T/calls"; : > "$T/tmux.n"; rm -f "$T/sessions.late"
  git -C "$G" worktree prune >/dev/null 2>&1
}
sc() { # <인자…> → OUT·RC · STEP = 전체 지도 1회가 먹는 가짜 초(«사본 1개 N초»)
  OUT="$(env PATH="$BIN:$PATH" FT_RES_ROOT="$R" FT_SCRATCH_DIR="$SCR" TMPDIR="$T" FT_SCRATCH_OWNER=live-owner FT_HEAVY_SLOTS=0 \
    STEP="${STEP:-0}" SWAP_AT="${SWAP_AT:-0}" bash "${CASE_SUT:-$SUT}" "$@" 2>&1)"; RC=$?; }
puts() { printf '%s' "$1" | grep -qF -- "$2"; }
regline() { grep -cF -- "$1" "$TSV" 2>/dev/null; }

# ── ① 없음 + 깨끗 2 · 더러움 1 → done=2 refused=1 · 더러운 사본·등록 줄 남음 ─────────────────────
if want ①; then
  reset
  A="$(mkcopy 00)"; B="$(mkcopy 01)"; D="$(mkcopy 02 dirty)"
  t0=$SECONDS; sc --reap-owner gone-seat; t1=$SECONDS
  { [ "$RC" = 0 ] && puts "$OUT" "REAP gone-seat done=2 refused=1 left=0" \
    && [ ! -d "$A" ] && [ ! -d "$B" ] && [ -d "$D" ] && [ "$(regline "$D")" = 1 ] && [ "$(regline "$A")" = 0 ]; } \
    && ok "① 더러운 사본만 남김 — done=2 refused=1 · 등록 줄 유지 · $(( t1 - t0 ))초" \
    || bad "① rc=$RC A=$([ -d "$A" ] && echo 남음 || echo 지움) B=$([ -d "$B" ] && echo 남음 || echo 지움) D=$([ -d "$D" ] && echo 남음 || echo 지움) tsvD=$(regline "$D") out=$(printf '%s' "$OUT" | tail -2 | tr '\n' ' ')"
fi

# ── ② 세션 살아 있음 → REJECT rc2 · 삭제 0 / 사본 12개 · 사본 1개 7초(가짜) → left ≥ 1 · 회차 ≤ 70초
if want ②; then
  reset
  printf 'gone-seat\nlive-owner\n' > "$T/sessions"
  A="$(mkcopy 00)"; B="$(mkcopy 01)"
  sc --reap-owner gone-seat
  { [ "$RC" = 2 ] && puts "$OUT" "REJECT" && [ -d "$A" ] && [ -d "$B" ] && [ "$(regline "$A")" = 1 ]; } \
    && ok "②1 세션 살아 있음 — REJECT rc2 · 삭제 0(출구 게이트 앞에서 멈춤)" \
    || bad "②1 rc=$RC out=$(printf '%s' "$OUT" | tail -2 | tr '\n' ' ') A=$([ -d "$A" ] && echo 남음 || echo 지움)"
  reset
  printf 'live-owner\n' > "$T/sessions"
  for i in 00 01 02 03 04 05 06 07 08 09 10 11; do mkcopy "$i" >/dev/null; done
  t0=$SECONDS; STEP=7 sc --reap-owner gone-seat; t1=$SECONDS
  L="$(printf '%s\n' "$OUT" | sed -n 's/^REAP gone-seat done=\([0-9]*\) refused=\([0-9]*\) left=\([0-9]*\)$/\3/p' | tail -1)"
  { [ "$RC" = 0 ] && puts "$OUT" "REAP gone-seat done=" && [ -n "$L" ] && [ "$L" -ge 1 ] && [ $(( t1 - t0 )) -le 70 ] \
    && [ "$(ls -1 "$SCR" | wc -l | tr -d ' ')" -ge 1 ]; } \
    && ok "②2 사본 12개 · 사본 1개 7초(가짜) — left=$L ≥ 1 · 회차 $(( t1 - t0 ))초 ≤ 70초(좌석당 상한)" \
    || bad "②2 rc=$RC left=${L:-?} 시간=$(( t1 - t0 ))초 out=$(printf '%s' "$OUT" | tail -2 | tr '\n' ' ')"
fi

# ── ④ 정정1(DA H1): 지우기 도중 옛 좌석이 다시 보이면 그 사본부터 삭제 0 ──────────────────────────
if want ④; then
  reset
  A="$(mkcopy 00)"; B="$(mkcopy 01)"
  printf 'gone-seat\n' > "$T/sessions.late"   # 두 번째 list-sessions(사본 1개 지우기 직전 재확인)부터 옛 좌석이 보인다
  t0=$SECONDS; SWAP_AT=2 sc --reap-owner gone-seat; tm1=$SECONDS
  { [ "$RC" = 0 ] && [ -d "$A" ] && [ -d "$B" ] \
    && printf '%s' "$OUT" | grep -q '^REAP gone-seat done=0 ' && puts "$OUT" "세션이 다시 보임" ; } \
    && ok "④ 주인 재등장(두 번째 확인) — 삭제 0 · REAP done=0 · 사본 2개 그대로 · $(( tm1 - t0 ))초" \
    || bad "④ rc=$RC A=$([ -d "$A" ] && echo 남음 || echo 지움) B=$([ -d "$B" ] && echo 남음 || echo 지움) out=$(printf '%s' "$OUT" | tail -2 | tr '\n' ' ')"
fi

# ── ⑤ 정정2(DA #364832): G4 점유 조회 단계에서 주인이 다시 보여도 출구 게이트 G6 가 막는다 ──────────
#    (사전 확인은 tmux 2번째 호출 · 게이트 G6 는 3번째 호출 — 3번째부터 옛 좌석이 보이게 주입)
if want ⑤; then
  reset
  A="$(mkcopy 00)"; B="$(mkcopy 01)"
  printf 'gone-seat\n' > "$T/sessions.late"
  SWAP_AT=3 sc --reap-owner gone-seat
  { [ "$RC" = 0 ] && [ -d "$A" ] && [ -d "$B" ] \
    && printf '%s' "$OUT" | grep -q '^REAP gone-seat done=0 ' \
    && printf '%s' "$OUT" | grep -qE 'G6 .*주인 gone-seat 살아 있음|세션이 다시 보임' ; } \
    && ok "⑤ 게이트 G6 가 생존 재확인(사전 확인 뒤 재등장) — 삭제 0 · done=0 · 사본 2개 그대로" \
    || bad "⑤ rc=$RC A=$([ -d "$A" ] && echo 남음 || echo 지움) B=$([ -d "$B" ] && echo 남음 || echo 지움) out=$(printf '%s' "$OUT" | tail -3 | tr '\n' ' ')"
fi

# ── ③ ft-seat-retire(가짜 tmux · kill 뒤) → --reap-owner 1회 · REAP 줄 1 · 은퇴 rc 그대로 ─────────
if want ③; then
  printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/reap.sh"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/scratch.calls"\n[ "${FAKE_REAP_RC:-0}" = 0 ] && echo "REAP $2 done=1 refused=0 left=0"\nexit "${FAKE_REAP_RC:-0}"\n' "$T" > "$T/scratch.sh"
  chmod 755 "$T/reap.sh" "$T/scratch.sh"
  rbed() { # <이름> — 은퇴 1회(명부 1줄 · 가짜 tmux = 세션 없음)
    local w="$T/ret-$1"; mkdir -p "$w/.fable-team"; git -C "$w" init -q
    printf '{"byz-t-arch-pi#1": {"role": "arch", "agent": "claude", "model": "m", "tick": null}}' > "$w/.fable-team/seats-t.json"
    : > "$T/scratch.calls"
    (cd "$w" && HOME="$T/home" PATH="$T/fake-tmux:$PATH" env -u FT_SEATS_JSON FT_TMUX_BIN="$T/fake-tmux/tmux" \
      FT_SEAT_REAP_BIN="$T/reap.sh" FT_SCRATCH_REPO_BIN="$T/scratch.sh" FT_SEAT_QUIESCE_BIN=/bin/true \
      bash "$RETIRE" 'byz-t-arch-pi#1' 'byz-t-arch-pi#2' > "$T/ret-$1.out" 2>&1); echo $?
  }
  printf '#!/bin/sh\nexit 1\n' > /dev/null; mkdir -p "$T/fake-tmux"; printf '#!/bin/sh\nexit 1\n' > "$T/fake-tmux/tmux"; chmod 755 "$T/fake-tmux/tmux"
  RC1="$(rbed c1)"; N1="$(grep -c '^REAP byz-t-arch-pi#1 ' "$T/ret-c1.out")"; C1="$(grep -c -- '--reap-owner byz-t-arch-pi#1' "$T/scratch.calls")"
  { [ "$RC1" = 0 ] && [ "$N1" = 1 ] && [ "$C1" = 1 ]; } \
    && ok "③1 은퇴 rc=0 · --reap-owner 1회 호출 · REAP 줄 1" \
    || bad "③1 rc=$RC1 REAP줄=$N1 호출=$C1 out=$(printf '%s' "$(cat "$T/ret-c1.out")" | tail -3 | tr '\n' ' ')"
  RC2="$(FAKE_REAP_RC=3 rbed c2)"; N2="$(grep -c '^WARN 사본 정리' "$T/ret-c2.out")"
  { [ "$RC2" = 0 ] && [ "$N2" = 1 ]; } \
    && ok "③2 reap 실패(rc3) — 은퇴 rc 0 그대로 · WARN 1줄(조용한 0 아님)" \
    || bad "③2 rc=$RC2 WARN=$N2 out=$(printf '%s' "$(cat "$T/ret-c2.out")" | tail -3 | tr '\n' ' ')"
fi

# ── M1 변이 «세션 없음 조건 뺌» → ②1 이 빨강(살아 있는 좌석의 사본을 지운다) ────────────────────
if want M1; then
  # 생존 조건은 세 겹(처음 1회 + reap 사전 확인 + 출구 게이트 G6) — 변이는 세 겹을 다 없앤다
  sed -e 's/^  has_line "\$S" "\$old" && { echo "REJECT reap-owner \$old — 세션이 살아 있음 · 삭제 0"; return 2; }$/  :   # r2398a-mut: 처음 세션 조건 뺌/' \
      -e 's/if has_line "\$S2" "\$old"; then/if false; then   # r2398a-mut: 사본별 재확인도 뺌/' \
      -e 's/^      has_line "\$S" "\$own" && { gfail G6 1 "주인 \$own 살아 있음"; return; }$/      :   # r2398a-mut: 출구 게이트 G6 생존 검사도 뺌/' \
      "$SUT" > "$MUTB/$(basename -- "$SUT")"
  cmp -s "$SUT" "$MUTB/$(basename -- "$SUT")" && bad "M1 변이 주입 실패(바꾼 줄 없음)" || {
    reset; printf 'gone-seat\nlive-owner\n' > "$T/sessions"
    A="$(mkcopy 00)"; CASE_SUT="$MUTB/$(basename -- "$SUT")" sc --reap-owner gone-seat
    { [ "$RC" = 0 ] && [ ! -d "$A" ]; } \
      && ok "M1 세션 조건 제거 → 살아 있는 좌석의 사본이 지워짐 = ②1 빨강(변이 잡힘)" \
      || bad "M1 을 못 잡음 — 세션 조건을 없애도 rc=$RC A=$([ -d "$A" ] && echo 남음 || echo 지움)"
  }
fi

# ── M2 변이 «delete_copy 대신 rm -rf» → ① 이 빨강(더러운 사본이 사라진다) ──────────────────────
if want M2; then
  sed 's/^    delete_copy "\$p" reg "\$old" reap; rc=\$?$/    rm -rf -- "$p"; drop_reg "$p" >\/dev\/null 2>\&1; rc=0   # r2398a-mut: 게이트 없이 지움/' "$SUT" > "$MUTB/$(basename -- "$SUT")"
  cmp -s "$SUT" "$MUTB/$(basename -- "$SUT")" && bad "M2 변이 주입 실패(바꾼 줄 없음)" || {
    reset
    A="$(mkcopy 00)"; D="$(mkcopy 02 dirty)"; CASE_SUT="$MUTB/$(basename -- "$SUT")" sc --reap-owner gone-seat
    { [ ! -d "$A" ] && [ ! -d "$D" ] && puts "$OUT" "done=2"; } \
      && ok "M2 게이트 없이 rm -rf → 더러운 사본이 사라짐 = ① 빨강(변이 잡힘)" \
      || bad "M2 를 못 잡음 — rm -rf 로 바꿔도 D=$([ -d "$D" ] && echo 남음 || echo 지움) rc=$RC out=$(printf '%s' "$OUT" | tail -2 | tr '\n' ' ')"
  }
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "($fail failed)"
exit "$fail"
