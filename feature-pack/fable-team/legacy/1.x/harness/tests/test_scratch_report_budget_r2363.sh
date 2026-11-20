#!/usr/bin/env bash
# test_scratch_report_budget_r2363.sh — r2363: ft-scratch-repo.sh --report(·--summary) 도 지우기 길과 «같은 판정 예산(FT_SCRATCH_JUDGE_BUDGET · 기본 20초)» 안에서만 사본 크기(du)를 잰다.
#   예산을 넘은 사본은 표에 남기고 크기만 «?»(0.00 아님) 로 두며, 못 잰 수를 1줄로 알린다(--summary 는 같은 줄에 « · 크기 못 잼 N개») · 지우기 길·다른 길은 그대로.
# 임시 git 저장소·가짜 tmux·가짜 lsof·가짜 du·임시 TMPDIR 만 쓴다 — 실 저장소·실 세션·실 TMPDIR·실 상태 0 · 삭제는 임시 폴더 안에서만.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/.." && pwd)"
SUT="${FT_SUT:-$REPO/bin/ft-scratch-repo.sh}"   # FT_SUT = 변이 판(고장 주입) 대조 실행용
fail=0
# FT_TEST_ONLY=①,…,변이-M1,… = 그 칸만(하드 룰 22 · 한 칸 70초 안)
ONLY="${FT_TEST_ONLY:-}"
want() { [ -z "$ONLY" ] && return 0; printf '%s\n' "$ONLY" | tr ',' '\n' | grep -qx "$1"; }
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
[ -f "$SUT" ] || { bad "ft-scratch-repo.sh 없음 ($SUT)"; echo "(1 failed)"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
G="$T/src"; R="$T/R"; SCR="$T/scratch"; TMPD="$T/tmpdir"; BIN="$T/bin"
mkdir -p "$G" "$R/.fable-team/state" "$SCR" "$TMPD" "$BIN"
git -C "$G" init -q && echo a > "$G/a.txt" && git -C "$G" add a.txt && git -C "$G" -c user.name=t -c user.email=t@t commit -q -m c1
SHA="$(git -C "$G" rev-parse HEAD)"
STATE="$R/.fable-team/state"; TSV="$STATE/scratch-repos.tsv"; ARMED="$STATE/scratch-sweep.armed"
printf 'live-owner\n' > "$T/sessions"
printf '#!/bin/sh\n[ "$1" = list-sessions ] && cat "%s/sessions" 2>/dev/null\nexit 0\n' "$T" > "$BIN/tmux"
printf '#!/bin/sh\ncat "%s/lsof.all" 2>/dev/null\nexit 0\n' "$T" > "$BIN/lsof"
chmod 755 "$BIN/tmux" "$BIN/lsof"
printf 'p1\ncinit\nfcwd\nn/\n' > "$T/lsof.all"
# 가짜 du — r2363 대역: 호출마다 0.5초(고정 sleep 은 이 파일 안에서만 · 회차 계측용) · 호출 수를 센다 · 크기 = 1 GiB(사본 1개 = 1048576 kb)
printf '#!/bin/sh\nn=$(cat "%s/du.calls" 2>/dev/null || echo 0); echo $((n+1)) > "%s/du.calls"\nsleep 0.5\nprintf "1048576\\t%%s\\n" "$2"\n' "$T" "$T" > "$BIN/du"
chmod 755 "$BIN/du"

# 변이 판 자리 — 원본 옆 동료 lib(ft-heavy-slot-lib.sh 등)를 심링크로 붙인다(변이 판이 «다른 폴더» 라 lib 못 찾고 일찍 죽는 길 0 · 실 bin 폴더는 그대로)
MUTDIR="$T/mutbin"; mkdir -p "$MUTDIR"
for f in "$REPO/bin"/*; do [ "$(basename -- "$f")" = ft-scratch-repo.sh ] || ln -s "$f" "$MUTDIR/"; done

calls() { cat "$T/du.calls" 2>/dev/null || echo 0; }
bed() { # <사본 수> — 등록부·사본·호출 계수·armed 초기화(모두 임시 폴더 안)
  rm -rf "$STATE" "$SCR" "$TMPD"; mkdir -p "$STATE" "$SCR" "$TMPD"
  : > "$T/du.calls"; : > "$TSV"; : > "$T/lsof.all"; printf 'p1\ncinit\nfcwd\nn/\n' > "$T/lsof.all"
  local i d
  for i in $(seq 1 "$1"); do
    d="$SCR/repo-$(printf '%08d' "$i")-111-222"
    mkdir -p "$d"
    printf '%s\tgone-%s\t%s\n' "$d" "$i" "$(( $(date +%s) - 90000 ))" >> "$TSV"
  done
}
sc() { OUT="$(env PATH="$BIN:$PATH" FT_RES_ROOT="$R" FT_SCRATCH_DIR="$SCR" TMPDIR="$TMPD" FT_SCRATCH_OWNER=live-owner \
  FT_SCRATCH_JUDGE_BUDGET="${BUDGET:-20}" bash "${FT_SUT:-$SUT}" "$@" 2>&1)"; RC=$?; }
rows() { printf '%s\n' "$OUT" | awk -F'\t' 'NF>=3 && $2 ~ /\/repo-/' | wc -l | tr -d ' '; }      # 표 줄 수(크기·경로·사유 3열)
raws() { printf '%s\n' "$OUT" | awk -F'\t' '$1=="?"' | wc -l | tr -d ' '; }                        # 크기 «?» 줄 수 = 못 잰 사본
zero_rows() { printf '%s\n' "$OUT" | awk -F'\t' '$1=="0.00"' | wc -l | tr -d ' '; }
sumline() { printf '%s\n' "$OUT" | grep -m1 '^주인 없는 임시 사본'; }

if want ①; then
# ① K1 보고 예산 — 사본 12 · 가짜 du 0.5초/회 · 예산 2초 → du 부름 ≤ 6(12 아님) · 회차 ≤ 8초 · rc0
bed 12
BUDGET=2 sc --report; C="$(calls)"
{ [ "$RC" = 0 ] && [ "$C" -le 6 ] && [ "$C" -ge 2 ]; } && ok "① --report du 부름 ${C}회(사본 12 · 예산 2초)" || bad "① rc=$RC du호출=$C out=$(printf '%s' "$OUT" | head -3 | tr '\n' ' ')"
fi

if want ②; then
# ② K1 --summary 도 같은 예산 — 사본 12 · 예산 2초 → du 부름 ≤ 6 · 출력 1줄(--summary 계약) · rc0 · 회차 ≤ 8초
bed 12
t0=$SECONDS; BUDGET=2 sc --report --summary; t1=$SECONDS; C="$(calls)"
{ [ "$RC" = 0 ] && [ "$C" -le 6 ] && [ "$C" -ge 2 ] && [ "$(( t1 - t0 ))" -le 8 ] \
  && [ "$(printf '%s\n' "$OUT" | grep -c '^주인 없는 임시 사본')" = 1 ]; } \
  && ok "② --report --summary du 부름 ${C}회 · 회차 $(( t1 - t0 ))초 ≤ 8초 · 요약 1줄" || bad "② rc=$RC du호출=$C 시간=$(( t1 - t0 ))초 out=$OUT"
fi

if want ③; then
# ③ K2 못 잰 사본도 보임 — 예산을 넘어도 표 줄은 사본 12개 그대로 · 못 잰 줄은 «?»(0.00 아님) · 잰 줄 = du 부름 수
bed 12
BUDGET=2 sc --report; C="$(calls)"; NROWS="$(rows)"; QUES="$(raws)"; ZERO="$(zero_rows)"
{ [ "$RC" = 0 ] && [ "$NROWS" = 12 ] && [ "$QUES" -ge 1 ] && [ "$ZERO" = 0 ] \
  && [ $(( NROWS - QUES )) = "$C" ]; } \
  && ok "③ 표 줄 12개 그대로 · «?» ${QUES}개 · 숫자 $(( NROWS - QUES ))개 = du 부름 ${C}회 · «0.00» 0개" || bad "③ rc=$RC 줄=$NROWS «?»=$QUES «0.00»=$ZERO du호출=$C"
fi

if want ④; then
# ④ K3 못 잰 수 1줄 — stderr 경고 1줄 · 그 수 = «?» 줄 수 = 사본 12 - du 부름 수
bed 12
BUDGET=2 sc --report; C="$(calls)"; QUES="$(raws)"
WLINE="$(printf '%s\n' "$OUT" | grep -c '보고 예산(2초) 초과 · 크기 못 잰 사본')"
WN="$(printf '%s\n' "$OUT" | sed -n 's/.*크기 못 잰 사본 \([0-9]*\)개.*/\1/p' | head -1)"
{ [ "$WLINE" = 1 ] && [ -n "$WN" ] && [ "$WN" = "$QUES" ] && [ "$WN" = $(( 12 - C )) ]; } \
  && ok "④ 못 잰 수 경고 1줄 · «${WN}개» = «?» 줄 ${QUES}개 = 12 - $C" || bad "④ 경고=$WLINE 수=$WN «?»=$QUES du호출=$C out=$OUT"
fi

if want ⑤; then
# ⑤ K3 --summary 같은 줄 — 요약 줄에 «· 크기 못 잼 N개» · GiB = 예산 안에서 잰 수(사본 1개 = 1.00 GiB) · N = 12 - 잰 수
bed 12
BUDGET=2 sc --report --summary; C="$(calls)"; SL="$(sumline)"
GIB="$(printf '%s' "$SL" | sed -n 's/^주인 없는 임시 사본 12개 \([0-9]*\)\.00 GiB.*/\1/p')"
MISS="$(printf '%s' "$SL" | sed -n 's/.* · 크기 못 잼 \([0-9]*\)개.*/\1/p')"
{ [ "$RC" = 0 ] && [ -n "$GIB" ] && [ "$GIB" = "$C" ] && [ -n "$MISS" ] && [ "$MISS" = $(( 12 - C )) ]; } \
  && ok "⑤ 요약 같은 줄 — ${GIB}.00 GiB(잰 ${C}개) · 크기 못 잼 ${MISS}개" || bad "⑤ rc=$RC du호출=$C 요약=[$SL]"
fi

if want ⑥; then
# ⑥ K4 다른 길 그대로 — 예산이 넉넉하면(기본 20초 · 사본 3) 표는 «지금 그대로»: du 부름 = 사본 수 · «?» 0 · 못 잰 경고 0
bed 3
sc --report; C="$(calls)"; NROWS="$(rows)"; QUES="$(raws)"
{ [ "$RC" = 0 ] && [ "$C" = 3 ] && [ "$NROWS" = 3 ] && [ "$QUES" = 0 ] && ! printf '%s' "$OUT" | grep -q '크기 못 잰'; } \
  && ok "⑥ 예산 넉넉 — du 3회(사본 3) · «?» 0 · 경고 0(보고 표 그대로)" || bad "⑥ rc=$RC du호출=$C 줄=$NROWS «?»=$QUES out=$OUT"
fi

if want ⑦; then
# ⑦ K4 지우기 길 그대로 — --sweep 판정 예산 1초 · 사본 8 → du 부름 ≤ 5(8 아님) · «판정 예산(1초) 초과 · 남은 사본 … 다음 틱» 그대로 · rc0
bed 8
: > "$ARMED"
BUDGET=1 sc --sweep; C="$(calls)"
{ [ "$RC" = 0 ] && [ "$C" -le 5 ] && printf '%s' "$OUT" | grep -q '판정 예산(1초) 초과 · 남은 사본'; } \
  && ok "⑦ --sweep du 부름 ${C}회 ≤ 5 · «다음 틱» 1줄(지우기 길 그대로)" || bad "⑦ rc=$RC du호출=$C out=$(printf '%s' "$OUT" | tail -3 | tr '\n' ' ')"
fi

mut() { # <이름> <sed 식…> → $MUTDIR/ft-scratch-repo.sh (원본과 다르고 문법이 살아야 한다 · lib 는 옆 심링크)
  local n="$1" x s=(); shift
  for x in "$@"; do [ "$x" = -e ] || s+=(-e "$x"); done   # BSD sed 는 스크립트 뒤의 -e 를 옵션으로 안 본다
  sed "${s[@]}" "$SUT" > "$MUTDIR/ft-scratch-repo.sh"
  cmp -s "$SUT" "$MUTDIR/ft-scratch-repo.sh" && { bad "변이 $n 주입 실패(바뀐 줄 없음)"; return 1; }
  bash -n "$MUTDIR/ft-scratch-repo.sh" 2>/dev/null || { bad "변이 $n 문법 깨짐(가짜 변이)"; return 1; }
  MUT="$MUTDIR/ft-scratch-repo.sh"; return 0
}

if want 변이-M1; then
# M1 K1 «보고 길 예산 없음(ODL=0) = 지금 그대로» → ① 의 «du 부름 ≤ 6» 이 깨진다(사본 12 = 12회)
mut M1 's/ODL=$(( now + ${FT_SCRATCH_JUDGE_BUDGET:-20} ))   # r2363/ODL=0   # r2363-mut/' && {
  bed 12; FT_SUT="$MUT" BUDGET=2 sc --report; MC="$(calls)"
  [ "$MC" -gt 6 ] && ok "변이 M1(보고 길 예산 제거) → du ${MC}회 > 6 = ① 빨강(변이 잡힘)" || bad "변이 M1 을 못 잡음 — 예산을 없애도 du ${MC}회"
}
fi

if want 변이-M2; then
# M2 K2 «예산 바닥 = 지우기 길 꼴(continue)» → ③ 의 «표 줄 12개» 가 깨진다(못 잰 사본이 표에서 사라진다)
mut M2 's/\[ "\$oleft" != 0 \] || { ORPT_MARK=1; ODEF=\$((ODEF+1)); return 0; }/[ "$oleft" != 0 ] || { ORPT_MARK=1; ODEF=$((ODEF+1)); return 1; }/' && {
  bed 12; FT_SUT="$MUT" BUDGET=2 sc --report; MR="$(rows)"
  [ "$MR" -lt 12 ] && ok "변이 M2(표 줄 건너뜀) → 표 ${MR}줄 < 12 = ③ 빨강(변이 잡힘)" || bad "변이 M2 를 못 잡음 — 건너뛰어도 표 ${MR}줄"
}
fi

if want 변이-M3; then
# M3 K3 «못 잰 수를 안 센다(ODEF 증가 제거)» → ④ 의 경고 1줄·수 대조가 깨진다
mut M3 's/\[ "\$ORPT_MARK" = 0 \] || { ODEF=\$((ODEF+1)); return 0; }/[ "$ORPT_MARK" = 0 ] || { return 0; }/' \
  -e 's/{ ORPT_MARK=1; ODEF=\$((ODEF+1)); return 0; }/{ ORPT_MARK=1; return 0; }/' && {
  bed 12; FT_SUT="$MUT" BUDGET=2 sc --report
  MW="$(printf '%s\n' "$OUT" | grep -c '보고 예산(2초) 초과 · 크기 못 잰 사본')"
  [ "$MW" = 0 ] && ok "변이 M3(못 잰 수 안 셈) → 경고 0줄 = ④ 빨강(변이 잡힘)" || bad "변이 M3 을 못 잡음 — 안 세도 경고 ${MW}줄 out=$OUT"
}
fi

if want 변이-M4; then
# M4 K3 «--summary 같은 줄에 못 잰 수 없음» → ⑤ 가 깨진다
mut M4 's/ · 크기 못 잼 %s개//' && {
  bed 12; FT_SUT="$MUT" BUDGET=2 sc --report --summary; MS="$(sumline)"
  ! printf '%s' "$MS" | grep -q '크기 못 잼' && ok "변이 M4(요약에 못 잰 수 없음) → ⑤ 빨강(변이 잡힘): [$MS]" || bad "변이 M4 를 못 잡음 — 요약=[$MS]"
}
fi

if want 변이-M5; then
# M5 K4 «지우기 길 예산 가드 제거» → ⑦ 의 «du 부름 ≤ 5» 가 깨진다(사본 8 = 8회)
mut M5 's/if \[ "\$ODL" != 0 \] && \[ "\$oleft" = 0 \]; then ODEF=\$((ODEF+1)); return 1; fi/if [ 0 = 1 ]; then ODEF=$((ODEF+1)); return 1; fi/' && {
  bed 8; : > "$ARMED"; FT_SUT="$MUT" BUDGET=1 sc --sweep; MC="$(calls)"
  [ "$MC" -gt 5 ] && ok "변이 M5(지우기 길 가드 제거) → du ${MC}회 > 5 = ⑦ 빨강(변이 잡힘)" || bad "변이 M5 를 못 잡음 — 가드를 없애도 du ${MC}회"
}
fi

if want 변이-M6; then
# M6 K2 «표 awk 예산 밖 kb → 0(.00) 되돌림» → ③ 의 ««0.00» 0개» 가 깨진다
mut M6 's/{ printf "?\\t%s\\t%s\\n", \$2, \$4; next }/k=0;/' && {
  bed 12; FT_SUT="$MUT" BUDGET=2 sc --report; MZ="$(zero_rows)"
  [ "$MZ" -ge 1 ] && ok "변이 M6(«?» → 0.00) → «0.00» ${MZ}줄 = ③ 빨강(변이 잡힘)" || bad "변이 M6 를 못 잡음 — 되돌려도 «0.00» ${MZ}줄"
}
fi

if want cmp; then
# bin·kit 같은 글자(설치는 h 몫 · 여기서는 사본만 맞춘다)
cmp -s "$REPO/bin/ft-scratch-repo.sh" "$REPO/kit/fable-team/bin/ft-scratch-repo.sh" \
  && ok "bin·kit 같은 글자(cmp 0)" || bad "bin·kit 다름"
fi

[ $fail -eq 0 ] && echo "ALL PASS" || echo "($fail failed)"
exit $fail
