#!/usr/bin/env bash
# test_scratch_sweep_cursor_r2372.sh — r2372: ft-scratch-repo.sh --sweep 의 차례와 «끊긴 자리»(cursor) — 반례 ①~⑩(변이 M1~M8 = test_scratch_sweep_cursor_mut_r2372.sh(M1~M4) · mut2(M5~M6) · mut3(M7~M8) — 파일마다 70초 안)
#   지우기 길(REPORT_ONLY=0)에서만 · 등록 사본 줄과 $TMPDIR 의 tmp.* 를 갈래마다 경로 LC_ALL=C 순서로 정렬 ·
#   갈래 시작 = cursor 경로 «이상» 인 첫 항목(그 앞 항목은 갈래 끝으로 돌림) · 판정·삭제는 두 갈래 번갈아(tmp · reg · tmp · reg) ·
#   회차 끝에 갈래마다 «판정 못 한» 또는 «삭제 차례가 안 온» 첫 항목을 <STATE>/scratch-sweep.cursor(reg|tmp<TAB>경로)에 쓴다(임시 파일 + mv · 실패 = WARN 1줄)
#   · --report 는 순서·표 그대로(cursor 손 0) · lsof·tmux 고장 = 삭제 0 · cursor 손 0
# 임시 ROOT·TMPDIR·FT_SCRATCH_DIR·가짜 tmux·lsof·date(가상 시계)·du(시계 한 칸 + 호출 기록) 만 쓴다 — 실 저장소·실 TMPDIR·실 상태 0 · sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/.." && pwd)"
SUT="${FT_SUT:-$REPO/bin/ft-scratch-repo.sh}"   # FT_SUT = 변이 판·기준판 대조 실행용
fail=0
ONLY="${FT_TEST_ONLY:-}"   # FT_TEST_ONLY=①,② = 그 칸만(하드 룰 22 · 한 칸 70초 안)
want() { [ -z "$ONLY" ] && return 0; printf '%s\n' "$ONLY" | tr ',' '\n' | grep -qx "$1"; }
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
[ -f "$SUT" ] || { bad "ft-scratch-repo.sh 없음 ($SUT)"; echo "(1 failed)"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
R="$T/R"; STATE="$R/.fable-team/state"; TSV="$STATE/scratch-repos.tsv"; CURSOR="$STATE/scratch-sweep.cursor"; ARMED="$STATE/scratch-sweep.armed"
SCR="$T/scratch"; TMPD="$T/tmpdir"; BIN="$T/bin"; CLK="$T/clk"; DUC="$T/du.calls"
mkdir -p "$STATE" "$SCR" "$TMPD" "$BIN"
REAL_DATE="$(command -v date)"; REAL_SORT="$(command -v sort)"; REAL_MV="$(command -v mv)"
[ -n "$REAL_DATE" ] && [ -n "$REAL_SORT" ] && [ -n "$REAL_MV" ] || { bad "date·sort·mv 실제 경로를 못 찾음"; echo "(1 failed)"; exit 1; }

# ── 가짜 도구 ────────────────────────────────────────────────────────────────────────────────
#   date +%s = 가상 시계($CLK) · +%F 등 나머지는 실제 date · du = 호출 기록 + 시계를 DU_STEP(기본 1)칸 민다(«사본마다 1초» 대신 시계 주입 · 고정 sleep 0)
#   lsof = -p <pid> 대조(절대경로 인자 없음)는 전체 지도, 사본별(+D <경로>)은 «아무도 안 씀» rc1 · tmux = $T/sessions
mkbin() {
  cat > "$BIN/date" <<EOF
#!/bin/sh
case "\${1:-}" in
  +%s) cat "$CLK" 2>/dev/null || echo 1000000;;
  *) exec "$REAL_DATE" "\$@";;
esac
EOF
  cat > "$BIN/du" <<EOF
#!/bin/sh
printf '%s\n' "\${2:-}" >> "$DUC"
n=\$(cat "$CLK" 2>/dev/null || echo 1000000); echo \$((n + \${DU_STEP:-1})) > "$CLK"
printf '1024\t%s\n' "\${2:-}"
EOF
  cat > "$BIN/lsof" <<EOF
#!/bin/sh
# r2398a: 지우기 길은 du 를 부르지 않는다(K2) — 차례·시계 신호를 «전체 지도 1회 실패 → 사본별 후퇴» 의 +D 호출로 받는다
#   · 경로 인자 있음(+D <사본>) = 그 사본 판정 1회 → 이름을 DUC 에 적고 시계를 DU_STEP 칸 민다(«사본마다 du 1회» 자리 그대로) · rc1(아무도 안 씀)
#   · -p <pid> 대조 = 전체 지도(lsof.all) · -a 전체 지도 호출 = map.fail 있으면 rc1(후퇴 강제) 아니면 lsof.all · -a 없는 전체 = 게이트 재확인 = lsof.all
path=""
for a in "\$@"; do case "\$a" in /*) path="\$a";; esac; done
if [ -z "\$path" ]; then
  case " \$* " in *" -p "*) cat "$T/lsof.all" 2>/dev/null; exit 0;; esac
  case " \$* " in *" -a "*) [ -f "$T/map.fail" ] && exit 1;; esac
  cat "$T/lsof.all" 2>/dev/null; exit 0
fi
printf '%s\n' "\${path##*/}" >> "$DUC"
n=\$(cat "$CLK" 2>/dev/null || echo 1000000); echo \$((n + \${DU_STEP:-1})) > "$CLK"
exit 1
EOF
  cat > "$BIN/tmux" <<EOF
#!/bin/sh
[ "\${1:-}" = list-sessions ] && cat "$T/sessions" 2>/dev/null
exit 0
EOF
  chmod 755 "$BIN/date" "$BIN/du" "$BIN/lsof" "$BIN/tmux"
}
# 가짜 sort(사례 ⑤ 전용) — 로캘이 C 가 아니면 -f 로 정렬하고 «비C 호출» 을 기록한다(구현이 LC_ALL=C 를 안 박으면 여기 남는다 · r2375 H1 꼴)
mksort() {
  cat > "$BIN/sort" <<EOF
#!/bin/sh
case "\${LC_ALL:-}" in
  C|POSIX) exec "$REAL_SORT" "\$@";;
esac
printf 'nonc\n' >> "$T/sort.nonc"
exec "$REAL_SORT" -f "\$@"
EOF
  chmod 755 "$BIN/sort"
}
# 가짜 mv(사례 ⑦ 전용) — 목적지가 cursor 자리일 때만 rc1(다른 mv 는 그대로 · 하드 룰 19: cursor 자리에 폴더를 만들지 않는다)
mkmv() {
  cat > "$BIN/mv" <<EOF
#!/bin/sh
last=""
for a in "\$@"; do last="\$a"; done
case "\$last" in *scratch-sweep.cursor) exit 1;; esac
exec "$REAL_MV" "\$@"
EOF
  chmod 755 "$BIN/mv"
}
mkbin
rm -f "$BIN/sort" "$BIN/mv"

REGT=$(( $(date +%s) - 90000 ))   # 등록 시각 = 25시간 전(나이 문턱 240분 통과 · 빠른 길 안 탐)
# 등록 사본 = 일반 폴더 + git init(출구 게이트가 «연결 워크트리 아님» rc3 로 거절 · 실제 삭제 0 · 판정·차례만 본다)
mreg() { # <두자리 번호> → 경로
  local d="$SCR/repo-0123abcd-$1-1"
  mkdir -p "$d" && git -c init.defaultBranch=main init -q "$d" >/dev/null 2>&1
  printf '%s\t%s\t%s\t%s\n' "$d" "gone-$1" "$REGT" "$SCR" >> "$TSV"
  printf '%s\n' "$d"
}
oldmtime() { touch -t "$("$REAL_DATE" -v-6H +%Y%m%d%H%M 2>/dev/null || "$REAL_DATE" -d '6 hours ago' +%Y%m%d%H%M)" "$1"; }
mtmp() { # <이름> → $TMPDIR/tmp.<이름> 경로 · mtime 6시간 전
  local d="$TMPD/tmp.$1"; mkdir -p "$d" && oldmtime "$d"
  printf '%s\n' "$d"
}
reset() {
  rm -rf "$STATE" "$SCR" "$TMPD" "$T/sort.nonc"
  mkdir -p "$STATE" "$SCR" "$TMPD"
  : > "$TSV"; : > "$DUC"; : > "$ARMED"; : > "$T/map.fail"   # r2398a: 기본 = 전체 지도 실패(사본별 후퇴 길에서 차례·시계를 본다)
  printf 'live-owner\n' > "$T/sessions"
  printf 'p1\ncinit\nfcwd\nn/\n' > "$T/lsof.all"
  printf '%s\n' "$(( $(date +%s) + 1000 ))" > "$CLK"   # 가상 시계 = 지금 근처(등록 시각 대조가 «옛 사본» 으로 읽히게)
  rm -f "$BIN/sort" "$BIN/mv"
}
#   · 무거운 git 자리는 FT_HEAVY_SLOTS=0 으로 끈다(자리 자체는 test_heavy_slot_* 몫 · 가상 시계와 대기 루프가 섞이면 회차가 흔들린다)
sc() { OUT="$(env PATH="$BIN:$PATH" FT_RES_ROOT="$R" FT_SCRATCH_DIR="$SCR" TMPDIR="$TMPD" FT_SCRATCH_OWNER=live-owner FT_HEAVY_SLOTS=0 \
  ${BUDGET:+FT_SCRATCH_JUDGE_BUDGET=$BUDGET} ${DU_STEP:+DU_STEP=$DU_STEP} ${LCX:+LC_ALL=$LCX} \
  bash "${CASE_SUT:-$SUT}" "$@" 2>&1)"; RC=$?; }
ducalls() { cat "$DUC" 2>/dev/null | tr '\n' ' '; }   # r2398a: 차례 = 사본별 점유 조회(+D) 호출 순서 = 가짜 lsof 가 적은 사본 이름(예전엔 du 호출 순서였다 — K2 로 du 0)
curshow() { cat "$CURSOR" 2>/dev/null; }
curreg() { curshow | awk -F'\t' '$1=="reg"{print $2}'; }
curtmp() { curshow | awk -F'\t' '$1=="tmp"{print $2}'; }
puts() { printf '%s' "$1" | grep -qF -- "$2"; }   # 출력에 그 줄이 있나(고정 문자열)

# ── ① K1 차례 — 예산이 3개면 앞 3개만 판정하고 cursor reg = a3 · 2회차는 a3 부터 ───────────────
if want ①; then
  reset
  for i in 00 01 02 03 04 05 06 07 08 09; do mreg "$i" >/dev/null; done
  BUDGET=3 sc --sweep
  L1="$(ducalls)"; C1="$(curreg)"
  { [ "$L1" = "repo-0123abcd-00-1 repo-0123abcd-01-1 repo-0123abcd-02-1 " ] && [ "$C1" = "$SCR/repo-0123abcd-03-1" ] \
    && puts "$OUT" "판정 예산(3초) 초과" ; } \
    && ok "①1 예산 3 — 1회차 판정 a0·a1·a2 · cursor reg = a3 · «다음 틱» 1줄" \
    || bad "①1 차례=[$L1] cursor=[$C1] out=$(printf '%s' "$OUT" | tail -2 | tr '\n' ' ')"
  : > "$DUC"
  BUDGET=3 sc --sweep
  L2="$(ducalls)"; C2="$(curreg)"
  { [ "$L2" = "repo-0123abcd-03-1 repo-0123abcd-04-1 repo-0123abcd-05-1 " ] && [ "$C2" = "$SCR/repo-0123abcd-06-1" ]; } \
    && ok "①2 2회차는 a3 부터(a3·a4·a5) · cursor reg = a6 — 기준판은 2회차도 a0~a2(Red)" \
    || bad "①2 차례=[$L2] cursor=[$C2]"
fi

# ── ② K1 번갈아 — tmp 4 + 등록 사본 10 · 예산 4 → 차례 = tmp·reg·tmp·reg ─────────────────────
if want ②; then
  reset
  for i in t0 t1 t2 t3; do mtmp "$i" >/dev/null; done
  for i in 00 01 02 03 04 05 06 07 08 09; do mreg "$i" >/dev/null; done
  BUDGET=4 sc --sweep
  L="$(ducalls)"; CR="$(curreg)"; M="$(curtmp)"
  { [ "$L" = "tmp.t0 repo-0123abcd-00-1 tmp.t1 repo-0123abcd-01-1 " ] && [ "$CR" = "$SCR/repo-0123abcd-02-1" ] && [ "$M" = "$TMPD/tmp.t2" ]; } \
    && ok "② 예산 4 — 판정 차례 tmp·reg·tmp·reg(tmp 2 · reg 2) · cursor reg = a2 · tmp = tmp.t2(기준판은 reg 4 · tmp 0 = Red)" \
    || bad "② 차례=[$L] cursor reg=[$CR] tmp=[$M]"
fi

# ── ③ K1 cursor 가 사라진 이름 — «C 순서 이상» 첫 항목부터 + 그 앞 항목은 회차 끝에 판정 ─────────
if want ③; then
  reset
  for i in 00 01 02 03 04 05 06 07 08 09; do mreg "$i" >/dev/null; done
  rm -rf "$SCR/repo-0123abcd-04-1"   # cursor 가 가리키던 a4 가 그 사이 지워졌다
  printf 'reg\t%s\n' "$SCR/repo-0123abcd-04-1" > "$CURSOR"
  BUDGET=100 sc --sweep
  L="$(ducalls)"
  { [ "$L" = "repo-0123abcd-05-1 repo-0123abcd-06-1 repo-0123abcd-07-1 repo-0123abcd-08-1 repo-0123abcd-09-1 repo-0123abcd-00-1 repo-0123abcd-01-1 repo-0123abcd-02-1 repo-0123abcd-03-1 " ] && [ -z "$(curreg)" ]; } \
    && ok "③ 사라진 cursor a4 — 시작 a5 · a0~a3 은 회차 끝 차례(9개 전부 판정)" \
    || bad "③ 차례=[$L] cursor=[$(curreg)]"
fi

# ── ④ K1 한 바퀴 끝 — cursor 가 a9 면 a9 부터 돌고 다 판정하면 reg 줄 0 ────────────────────────
if want ④; then
  reset
  for i in 00 01 02 03 04 05 06 07 08 09; do mreg "$i" >/dev/null; done
  printf 'reg\t%s\n' "$SCR/repo-0123abcd-09-1" > "$CURSOR"
  BUDGET=100 sc --sweep
  L="$(ducalls)"
  { [ "$L" = "repo-0123abcd-09-1 repo-0123abcd-00-1 repo-0123abcd-01-1 repo-0123abcd-02-1 repo-0123abcd-03-1 repo-0123abcd-04-1 repo-0123abcd-05-1 repo-0123abcd-06-1 repo-0123abcd-07-1 repo-0123abcd-08-1 " ] && [ -z "$(curreg)" ]; } \
    && ok "④ cursor a9 — a9 부터 a0~a8 로 돌아 다 판정 · cursor 파일에 reg 줄 0(한 바퀴 끝)" \
    || bad "④ 차례=[$L] cursor=[$(curreg)]"
fi

# ── ⑤ K1 C 순서 — env 로캘 ko_KR · PATH 앞 가짜 sort · 사라진 cursor …/repo-a-0 ────────────────
if want ⑤; then
  reset
  mksort
  for n in repo-B repo-a-1 repo-a.1; do
    d="$SCR/$n"; mkdir -p "$d" && git -c init.defaultBranch=main init -q "$d" >/dev/null 2>&1
    printf '%s\t%s\t%s\t%s\n' "$d" "gone-$(printf '%s' "$n" | tr -d '.-')" "$REGT" "$SCR" >> "$TSV"
  done
  printf 'reg\t%s\n' "$SCR/repo-a-0" > "$CURSOR"   # 사라진 cursor(그 사이 지워짐)
  LCX=ko_KR.UTF-8 BUDGET=100 sc --sweep
  L="$(ducalls)"
  NONC=0; [ -f "$T/sort.nonc" ] && NONC="$(wc -l < "$T/sort.nonc" | tr -d ' ')"
  { [ "$L" = "repo-a-1 repo-a.1 repo-B " ] && [ "$NONC" = 0 ]; } \
    && ok "⑤ C 순서 — 시작 repo-a-1(그 앞 repo-B 는 회차 끝) · 비C(sort -f) 호출 0(LC_ALL=C 강제)" \
    || bad "⑤ 차례=[$L] 비C sort 호출=$NONC(LC_ALL=C 안 박힘?)"
fi

# ── ⑥ K2 삭제 차례가 안 온 첫 항목(시계 주입) — 다음 회차는 그 항목부터 ──────────────────────────
if want ⑥; then
  reset
  for i in 00 01 02 03 04 05 06 07 08 09; do mreg "$i" >/dev/null; done
  printf 'reg\t%s\n' "$SCR/repo-0123abcd-05-1" > "$CURSOR"
  BUDGET=100 DU_STEP=6 sc --sweep   # 판정 10개 = 60초(70초 안) → 삭제 단계는 «남은 15초 미만» 으로 끊긴다
  L="$(ducalls)"; C="$(curreg)"; LEFT="$(ls -1 "$SCR" | wc -l | tr -d ' ')"
  { [ "$LEFT" = 10 ] && [ "$C" = "$SCR/repo-0123abcd-05-1" ] && puts "$OUT" "회차 예산 15초 미만" ; } \
    && ok "⑥1 삭제 단계 끊김 — 삭제 0 · cursor reg = 회전 시작 a5(경로가 작은 a0 아님 · 차례 앞선 것)" \
    || bad "⑥1 남은=$LEFT cursor=[$C] out=$(printf '%s' "$OUT" | tail -2 | tr '\n' ' ')"
  : > "$DUC"
  BUDGET=100 sc --sweep
  L2="$(ducalls)"
  { [ "$L2" = "repo-0123abcd-05-1 repo-0123abcd-06-1 repo-0123abcd-07-1 repo-0123abcd-08-1 repo-0123abcd-09-1 repo-0123abcd-00-1 repo-0123abcd-01-1 repo-0123abcd-02-1 repo-0123abcd-03-1 repo-0123abcd-04-1 " ]; } \
    && ok "⑥2 다음 회차는 그 항목(a5)부터 판정(차례 = a5…a4)" \
    || bad "⑥2 차례=[$L2]"
fi

# ── ⑦ K2 cursor 쓰기 실패 — WARN 1줄 · 지운 수·끝 줄·rc 그대로 ─────────────────────────────────
if want ⑦; then
  reset
  mkmv
  for i in 00 01 02 03; do mreg "$i" >/dev/null; done
  BUDGET=2 sc --sweep
  N="$(printf '%s\n' "$OUT" | grep -c 'cursor 못 씀')"
  { [ "$RC" = 0 ] && [ "$N" = 1 ] && puts "$OUT" "swept=0 owner-dead=0" && [ ! -f "$CURSOR" ]; } \
    && ok "⑦ cursor 쓰기 실패(가짜 mv rc1) — WARN 1줄 · 끝 줄 그대로 · rc 0 그대로 · cursor 파일 0" \
    || bad "⑦ rc=$RC WARN=$N cursor=$([ -e "$CURSOR" ] && echo 있음 || echo 없음) out=$(printf '%s' "$OUT" | tail -3 | tr '\n' ' ')"
fi

# ── ⑧ K2 cursor 꼴 틀림 — 그 갈래 처음부터 + WARN 1줄 · 다른 갈래 줄은 그대로 씀 ────────────────
if want ⑧; then
  reset
  for i in 00 01 02; do mreg "$i" >/dev/null; done
  mtmp t0 >/dev/null; mtmp t1 >/dev/null
  printf 'xx\t/a\n\n탭없는줄\nreg\t%s\ntmp\t%s\n' "$SCR/repo-0123abcd-99-1" "$TMPD/tmp.t1" > "$CURSOR"
  BUDGET=100 sc --sweep
  L="$(ducalls)"; W="$(printf '%s\n' "$OUT" | grep -c 'cursor 꼴 틀림')"
  { [ "$W" = 1 ] && [ "$L" = "tmp.t1 repo-0123abcd-00-1 tmp.t0 repo-0123abcd-01-1 repo-0123abcd-02-1 " ]; } \
    && ok "⑧ 꼴 틀린 줄(xx·빈 줄·탭 없음) = WARN 1줄 · reg 처음부터 · tmp 는 그 줄(t1)부터" \
    || bad "⑧ WARN=$W 차례=[$L]"
fi

# ── ⑨ K3 --report 는 그대로 — 순서(등록 순서) 그대로 · cursor 읽기·쓰기 0 ──────────────────────
if want ⑨; then
  reset
  mreg 02 >/dev/null; mreg 00 >/dev/null; mreg 01 >/dev/null   # 등록 순서 ≠ C 순서(정렬하면 00·01·02)
  mtmp t0 >/dev/null
  printf 'reg\t%s\n' "$SCR/repo-0123abcd-00-1" > "$CURSOR"
  BEFORE="$(curshow)"
  rm -f "$T/map.fail"   # r2398a: 보고 길은 전체 지도 1회(r2363 그대로) — 이 사례만 지도가 살아 있다
  sc --report
  L="$(printf '%s\n' "$OUT" | awk -F'\t' 'NF>=3{printf "%s ", $2}')"
  { [ "$L" = "$SCR/repo-0123abcd-02-1 $SCR/repo-0123abcd-00-1 $SCR/repo-0123abcd-01-1 $TMPD/tmp.t0 " ] \
    && [ "$(curshow)" = "$BEFORE" ] && [ "$(printf '%s\n' "$OUT" | grep -c cursor)" = 0 ]; } \
    && ok "⑨ --report — 표 순서 = 등록 순서(정렬 0) · cursor 파일 그대로 · cursor 줄 0" \
    || bad "⑨ 표=[$L] cursor바뀜=$([ "$(curshow)" = "$BEFORE" ] && echo 아님 || echo 예)"
fi

# ── ⑩ K3 lsof·tmux 고장 — 삭제 0 · cursor 파일 손 0 ───────────────────────────────────────────
if want ⑩; then
  reset
  for i in 00 01 02; do mreg "$i" >/dev/null; done
  printf 'reg\t%s\n' "$SCR/repo-0123abcd-01-1" > "$CURSOR"
  BEFORE="$(curshow)"
  cat > "$BIN/lsof" <<EOF
#!/bin/sh
exit 2
EOF
  chmod 755 "$BIN/lsof"
  sc --sweep
  A="$([ "$(curshow)" = "$BEFORE" ] && echo 그대로 || echo 바뀜)"; N1="$(ls -1 "$SCR" | wc -l | tr -d ' ')"; E1="$(puts "$OUT" "ERROR lsof 실패" && echo 있음 || echo 없음)"
  mkbin   # 가짜 lsof·tmux 복구
  cat > "$BIN/tmux" <<EOF
#!/bin/sh
exit 1
EOF
  chmod 755 "$BIN/tmux"
  sc --sweep
  B="$([ "$(curshow)" = "$BEFORE" ] && echo 그대로 || echo 바뀜)"; N2="$(ls -1 "$SCR" | wc -l | tr -d ' ')"; E2="$(puts "$OUT" "ERROR tmux" && echo 있음 || echo 없음)"
  { [ "$A" = 그대로 ] && [ "$B" = 그대로 ] && [ "$N1" = 3 ] && [ "$N2" = 3 ] && [ "$E1" = 있음 ] && [ "$E2" = 있음 ]; } \
    && ok "⑩ lsof 고장·tmux 실패 — 삭제 0(3개 그대로) · cursor 파일 손 0" \
    || bad "⑩ lsof후=$A($N1) tmux후=$B($N2) out=$(printf '%s' "$OUT" | tail -2 | tr '\n' ' ')"
  mkbin   # 다음 사례를 위해 가짜 lsof·tmux 복구
fi

[ $fail -eq 0 ] && echo "ALL PASS" || echo "($fail failed)"
exit $fail
