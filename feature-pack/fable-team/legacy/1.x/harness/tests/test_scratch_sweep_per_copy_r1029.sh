#!/usr/bin/env bash
# test_scratch_sweep_per_copy_r1029.sh — r1029: ft-scratch-repo.sh --sweep 의 점유(cwd) 조회를 «전체 1회» 에서 «사본별 1회(사본당 7초)» 로 쪼갠다 — 한 사본의 lsof 실패·지연은 그 사본만 «붙잡음(조회 실패 · 삭제 보류)», 다른 사본은 계속 판정 · 판정 예산(FT_SCRATCH_JUDGE_BUDGET)을 넘긴 사본은 다음 틱(1줄 · 조용한 0 아님) · 나이 문턱 기본 240분(241분=자격 · 239분=보존 · 주인 살아 있음·cwd 보유=보존).
# 임시 git 저장소·가짜 tmux·가짜 lsof·임시 TMPDIR 만 쓴다 — 실 저장소·실 세션·실 TMPDIR·실 상태 0 · 실제 삭제는 임시 폴더 안에서만.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/.." && pwd)"
SUT="${FT_SUT:-$REPO/bin/ft-scratch-repo.sh}"   # FT_SUT = 변이 판(고장 주입) 대조 실행용
fail=0
# FT_TEST_ONLY=ⓕ,변이-ⓖ = 그 칸만(하드 룰 22 · 한 칸 70초 안 · 고정 sleep 0)
ONLY="${FT_TEST_ONLY:-}"
want() { [ -z "$ONLY" ] && return 0; printf '%s\n' "$ONLY" | tr ',' '\n' | grep -qx "$1"; }
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
[ -f "$SUT" ] || { bad "ft-scratch-repo.sh 없음 ($SUT)"; echo "(1 failed)"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
G="$T/src"; R="$T/R"; SCR="$T/scratch"; TMPD="$T/tmpdir"; BIN="$T/bin"
mkdir -p "$G" "$R/.fable-team/state" "$SCR" "$TMPD" "$BIN" "$T/lsof.d"
git -C "$G" init -q && echo a > "$G/a.txt" && git -C "$G" add a.txt && git -C "$G" -c user.name=t -c user.email=t@t commit -q -m c1
SHA="$(git -C "$G" rev-parse HEAD)"
STATE="$R/.fable-team/state"; TSV="$STATE/scratch-repos.tsv"; SLOG="$STATE/scratch-sweep.log"; ARMED="$STATE/scratch-sweep.armed"
printf 'live-owner\n' > "$T/sessions"
printf '#!/bin/sh\n[ "$1" = list-sessions ] && cat "%s/sessions" 2>/dev/null\nexit 0\n' "$T" > "$BIN/tmux"
# 가짜 lsof — r1029 대역: 인자에 사본 경로(절대경로)가 있으면 «그 사본» 의 지시 파일만 본다(다른 사본과 섞이지 않는다).
#   $T/lsof.d/<이름>.sleep = N  → N초 자고 rc1(그 사본 조회가 멈춘 상황 · 7초 상한에 걸린다)
#   $T/lsof.d/<이름>.fail       → rc2 (못 읽음)
#   $T/lsof.d/<이름>.rows       → 그 사본을 cwd 로 쓰는 프로세스 줄
#   경로 인자 없음(전체 조회·대조 -p) = $T/lsof.all (전체 지도)
cat > "$BIN/lsof" <<EOF
#!/bin/sh
path=""
for a in "\$@"; do case "\$a" in /*) path="\$a";; esac; done
if [ -z "\$path" ]; then cat "$T/lsof.all" 2>/dev/null; exit 0; fi
b=\$(basename "\$path")
if [ -f "$T/lsof.d/\$b.sleep" ]; then sleep "\$(cat "$T/lsof.d/\$b.sleep")"; exit 1; fi
if [ -f "$T/lsof.d/\$b.fail" ]; then exit 2; fi
if [ -f "$T/lsof.d/\$b.rows" ]; then cat "$T/lsof.d/\$b.rows"; exit 0; fi
exit 1
EOF
chmod 755 "$BIN/tmux" "$BIN/lsof"
printf 'p1\ncinit\nfcwd\nn/\n' > "$T/lsof.all"   # 전체 지도 = 아무 사본도 점유하지 않음(대조 조회가 «본다» 는 증거)
lrows() { local c="$1" f; shift; f="$T/lsof.d/$(basename "$c").rows"; : > "$f"; while [ "$#" -ge 3 ]; do printf 'p%s\nc%s\nfcwd\nn%s\n' "$2" "$3" "$1" >> "$f"; shift 3; done; }   # <사본> <경로> <pid> <명령> …

# 가짜 du — 호출마다 1초 자고 호출 수를 센다(ⓕ·변이-ⓖ 대역 · 고정 sleep 은 여기 안에서만)
mkdu() {
cat > "$BIN/du" <<EOF
#!/bin/sh
n=\$(cat "$T/du.calls" 2>/dev/null || echo 0); echo \$((n+1)) > "$T/du.calls"
sleep 1
printf '1024\t%s\n' "\$2"
EOF
chmod 755 "$BIN/du"
: > "$T/du.calls"
}
sc() { OUT="$(env PATH="$BIN:$PATH" FT_RES_ROOT="$R" FT_SCRATCH_DIR="$SCR" TMPDIR="$TMPD" FT_SCRATCH_OWNER="${OWN:-live-owner}" ${BUDGET:+FT_SCRATCH_JUDGE_BUDGET=$BUDGET} bash "${FT_SUT:-$SUT}" "$@" 2>&1)"; RC=$?; }
mk() { OWN="$1" sc "$SHA" --repo "$G"; printf '%s' "$OUT"; }
age_reg() { awk -F'\t' -v p="$1" -v t="$(( $(date +%s) - $2 ))" 'BEGIN{OFS="\t"} $1==p{$3=t} {print}' "$TSV" > "$TSV.n" && mv "$TSV.n" "$TSV"; }
fresh() { rm -rf "$R/.fable-team/state" "$SCR" "$TMPD"; mkdir -p "$STATE" "$SCR" "$TMPD" "$T/lsof.d"; : > "$T/lsof.all"; printf 'p1\ncinit\nfcwd\nn/\n' > "$T/lsof.all"; }

if want ⓐ; then
# ⓐ 사본 하나의 조회가 멈춰도(7초 상한) 그 사본만 보류 · 나머지는 계속 판정 · 한 회차 ≤ 20초
fresh
A="$(mk gone-a)";  age_reg "$A" 90000; printf '8\n' > "$T/lsof.d/$(basename "$A").sleep"     # 조회 8초 = 7초 상한 초과
B="$(mk gone-b)";  age_reg "$B" 90000
C="$(mk gone-c)";  age_reg "$C" 90000
{ [ -d "$A" ] && [ -d "$B" ] && [ -d "$C" ]; } || { bad "ⓐ 사본 3개 생성 실패"; echo "($fail failed)"; exit "$fail"; }
t0=$SECONDS
sc --sweep; LIST="$(printf '%s\n' "$OUT" | grep -m1 '목록 보고')"   # 첫 회차 = 목록 보고만(실삭제 0 · r444/r897 그대로)
t1=$SECONDS
{ [ $RC = 0 ] && [ -n "$LIST" ] && [ -d "$A" ] && printf '%s' "$OUT" | grep -q "점유 조회 실패" \
  && printf '%s' "$LIST" | grep -q "$B" && ! printf '%s' "$LIST" | grep -q "$A"; } \
  && ok "ⓐ1 첫 --sweep(목록) — 멈춘 조회 A 는 «조회 실패» 로 보류 · B·C 는 후보" || bad "ⓐ1 rc=$RC out=$OUT"
{ [ $(( t1 - t0 )) -le 20 ]; } && ok "ⓐ2 회차 시간 $(( t1 - t0 ))초 ≤ 20초(멈춘 사본이 회차를 잡아먹지 않음)" || bad "ⓐ2 회차 $(( t1 - t0 ))초 > 20초"
t0=$SECONDS; sc --sweep; t1=$SECONDS
{ [ $RC = 0 ] && [ -d "$A" ] && [ ! -d "$B" ] && [ ! -d "$C" ] \
  && printf '%s' "$OUT" | grep -q "\[장비 정리\] 사본 $A — 점유 조회 실패(lsof) · 삭제 보류"; } \
  && ok "ⓐ3 둘째 --sweep — A 만 보류(조회 실패) · B·C 는 삭제(다른 사본 계속)" || bad "ⓐ3 rc=$RC out=$OUT A=$([ -d "$A" ] && echo 남음 || echo 지움) B=$([ -d "$B" ] && echo 남음 || echo 지움) C=$([ -d "$C" ] && echo 남음 || echo 지움)"
grep -q "붙잡음 $A (점유 조회 실패 · 삭제 보류 · 주인 gone-a)" "$SLOG" \
  && ok "ⓐ4 로그에 «붙잡음 … 점유 조회 실패 · 삭제 보류» 1줄" || bad "ⓐ4 로그: $(grep '붙잡음' "$SLOG" | tail -1)"
{ [ $(( t1 - t0 )) -le 20 ]; } && ok "ⓐ5 회차 시간 $(( t1 - t0 ))초 ≤ 20초" || bad "ⓐ5 회차 $(( t1 - t0 ))초 > 20초"
fi

if want ⓑ; then
# ⓑ 나이 문턱 기본 240분 — 241분·주인 없음 = 삭제 / 239분 = 보존 / 주인 살아 있음(24시간) = 보존 / cwd 보유 = 붙잡음
fresh
mkdir -p "$STATE" && : > "$ARMED"                                                 # armed = 다음부터 자동 삭제
D241="$(mk gone-d)"; age_reg "$D241" $((241*60))
D239="$(mk gone-e)"; age_reg "$D239" $((239*60))
PALV="$(mk live-owner)"; age_reg "$PALV" 90000
HELD="$(mk gone-f)"; age_reg "$HELD" 90000; lrows "$HELD" "$HELD/sub" 777 pytest           # 그 사본 아래 폴더를 cwd 로 쓰는 프로세스
sc --sweep
{ [ $RC = 0 ] && [ ! -d "$D241" ] && [ -d "$D239" ] && [ -d "$PALV" ] && [ -d "$HELD" ] \
  && printf '%s' "$OUT" | grep -q "\[장비 정리\] 주인 gone-f 사본 $HELD 에서 pid 777 pytest 실행 중 — 삭제 보류"; } \
  && ok "ⓑ 241분=삭제 · 239분=보존 · 주인 살아 있음=보존 · cwd 보유=붙잡음(기본 문턱 240분)" || bad "ⓑ rc=$RC out=$OUT d241=$([ -d "$D241" ] && echo 남음 || echo 지움) d239=$([ -d "$D239" ] && echo 남음 || echo 지움) palv=$([ -d "$PALV" ] && echo 남음 || echo 지움) held=$([ -d "$HELD" ] && echo 남음 || echo 지움)"
fi

if want ⓒ; then
# ⓒ 판정 예산(FT_SCRATCH_JUDGE_BUDGET) — 넘긴 사본은 조용한 0 이 아니라 «다음 틱» 1줄 · 이번 회차 삭제 0
fresh
: > "$ARMED"
X="$(mk gone-x)"; age_reg "$X" 90000; printf '2\n' > "$T/lsof.d/$(basename "$X").sleep"
Y="$(mk gone-y)"; age_reg "$Y" 90000
Z="$(mk gone-z)"; age_reg "$Z" 90000
BUDGET=1 sc --sweep
{ [ $RC = 0 ] && [ -d "$X" ] && [ -d "$Y" ] && [ -d "$Z" ] \
  && printf '%s' "$OUT" | grep -q "판정 예산(1초) 초과 · 남은 사본" ; } \
  && ok "ⓒ 예산 1초 — 넘긴 사본 «다음 틱» 1줄 · 삭제 0(조용한 0 아님)" || bad "ⓒ rc=$RC out=$OUT"
fi

if want ⓓ; then
# ⓓ 변이 1 «점유 조회를 전체 1회로 되돌림» → ⓐ 의 «멈춘 조회 = 그 사본만 보류» 가 깨진다(A 가 «아무도 안 씀» 으로 읽혀 지워진다)
sed 's/lsof -w -a -d cwd -Fpcn +D "\$1" 2>\/dev\/null/lsof -w -d cwd -Fpcn 2>\/dev\/null/' "$SUT" > "$T/mut1.sh"
cmp -s "$SUT" "$T/mut1.sh" && bad "ⓓ 변이 1 주입 실패(바꾼 줄 없음)" || {
fresh
M1="$(mk gone-m1)"; age_reg "$M1" 90000; printf '8\n' > "$T/lsof.d/$(basename "$M1").sleep"
M2="$(mk gone-m2)"; age_reg "$M2" 90000
: > "$ARMED"
FT_SUT="$T/mut1.sh" sc --sweep
{ [ ! -d "$M1" ]; } && ok "ⓓ 변이 1(전체 1회 복원) → 멈춘 사본 M1 이 지워져 FAIL(변이 잡힘 · 올바른 판은 M1 을 보류한다)" || bad "ⓓ 변이 1 을 못 잡음 — 전체 1회로 되돌려도 M1 이 보류됨"
}
fi

if want ⓔ; then
# ⓔ 변이 2 «나이 문턱 1440 복원» → ⓑ 의 «241분 = 자격» 이 깨진다
sed 's/FT_SCRATCH_AGE_MIN:-240}/FT_SCRATCH_AGE_MIN:-1440}/' "$SUT" > "$T/mut2.sh"
cmp -s "$SUT" "$T/mut2.sh" && bad "ⓔ 변이 2 주입 실패(바꾼 줄 없음)" || {
fresh
N="$(mk gone-n)"; age_reg "$N" $((241*60))
: > "$ARMED"
FT_SUT="$T/mut2.sh" sc --sweep
[ -d "$N" ] && ok "ⓔ 변이 2(문턱 1440 복원) → 241분 사본이 안 지워져 FAIL(변이 잡힘)" || bad "ⓔ 변이 2 를 못 잡음 — 문턱 1440 인데 241분 사본이 지워짐"
}
fi

if want ⓕ; then
# ⓕ (반송 r2) 판정 예산이 바닥이면 크기(du)도 부르지 않는다 — 사본 30 · 가짜 du 1초/회 · 예산 3초 → 회차 ≤ 10초 · du 호출 ≤ 10(30 아님) · «다음 틱» 1줄 · 삭제 0
fresh
: > "$ARMED"
mkdu
for i in $(seq 1 30); do d="$SCR/repo-$(printf '%08d' "$i")-111-222"; mkdir -p "$d"; printf '%s\tgone-%s\t%s\n' "$d" "$i" "$(( $(date +%s) - 90000 ))" >> "$TSV"; done
t0=$SECONDS; BUDGET=3 sc --sweep; t1=$SECONDS
CALLS="$(cat "$T/du.calls" 2>/dev/null || echo 0)"
{ [ "$RC" = 0 ] && [ $(( t1 - t0 )) -le 10 ] && [ "$CALLS" -le 10 ] && printf '%s' "$OUT" | grep -q "판정 예산(3초) 초과 · 남은 사본" ; } \
  && ok "ⓕ 예산 3초 · 사본 30 — 회차 $(( t1 - t0 ))초 ≤ 10초 · du 호출 $CALLS ≤ 10(30 아님) · «다음 틱» 1줄" || bad "ⓕ rc=$RC 시간=$(( t1 - t0 ))초 du호출=$CALLS out=$OUT"
fi

if want 변이-ⓖ; then
# ⓖ 변이 3 «예산이 바닥이어도 du 를 부른다(가드 제거)» → ⓕ 의 «du 호출 ≤ 10 · 회차 ≤ 10초» 가 깨진다
sed 's/\[ "\$oleft" = 0 \]/[ 0 = 1 ]/' "$SUT" > "$T/mut3.sh"
cmp -s "$SUT" "$T/mut3.sh" && bad "ⓖ 변이 3 주입 실패(바꾼 줄 없음)" || {
fresh
: > "$ARMED"
mkdu
for i in $(seq 1 12); do d="$SCR/repo-$(printf '%08d' "$i")-111-222"; mkdir -p "$d"; printf '%s\tgone-%s\t%s\n' "$d" "$i" "$(( $(date +%s) - 90000 ))" >> "$TSV"; done
BUDGET=3 FT_SUT="$T/mut3.sh" sc --sweep
MCALLS="$(cat "$T/du.calls" 2>/dev/null || echo 0)"
[ "$MCALLS" -gt 10 ] && ok "ⓖ 변이 3(du 가드 제거) → du 호출 $MCALLS > 10 = FAIL 검출(올바른 판은 예산 안에서만 du)" || bad "ⓖ 변이 3 을 못 잡음 — 가드를 없애도 du 호출 $MCALLS"
}
fi

[ $fail -eq 0 ] && echo "ALL PASS" || echo "($fail failed)"
exit $fail
