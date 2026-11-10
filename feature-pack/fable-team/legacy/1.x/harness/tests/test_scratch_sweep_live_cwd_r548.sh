#!/usr/bin/env bash
# test_scratch_sweep_live_cwd_r548.sh — r548: ft-scratch-repo.sh --sweep/--report 가 «어떤 프로세스의 cwd 인 사본» 을 지우지 않고 붙잡는다(등록 사본·tmp 둘 다 · 폴더 경계 비교) · cwd 를 못 묻는 lsof 실패 = 이번 정리 전체 삭제 0 + ERROR · 등록 사본도 «등록 후 24시간» 문턱(판정 1920 · r444 문턱 0 되돌림).
# 임시 git 저장소·가짜 tmux·가짜 lsof·임시 TMPDIR 만 쓴다 — 실 저장소·실 세션·실 TMPDIR·실 상태 0 · 실제 삭제는 임시 폴더 안에서만.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/.." && pwd)"
SUT="${FT_SUT:-$REPO/bin/ft-scratch-repo.sh}"   # FT_SUT = «고치기 전 판» 대조 실행용(증거 촬영)
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
[ -f "$SUT" ] || { bad "ft-scratch-repo.sh 없음 ($SUT)"; echo "(1 failed)"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
G="$T/src"; R="$T/R"; SCR="$T/scratch"; TMPD="$T/tmpdir"; BIN="$T/bin"
mkdir -p "$G" "$R/.fable-team/state" "$SCR" "$TMPD" "$BIN"
git -C "$G" init -q && echo a > "$G/a.txt" && git -C "$G" add a.txt && git -C "$G" -c user.name=t -c user.email=t@t commit -q -m c1
SHA="$(git -C "$G" rev-parse HEAD)"
STATE="$R/.fable-team/state"; TSV="$STATE/scratch-repos.tsv"; SLOG="$STATE/scratch-sweep.log"; ARMED="$STATE/scratch-sweep.armed"
printf 'live-owner\n' > "$T/sessions"   # tmux 세션 목록 = 이 한 줄(다른 주인은 전부 «주인 없음»)
printf '#!/bin/sh\n[ "$1" = list-sessions ] && cat "%s/sessions" 2>/dev/null\nexit 0\n' "$T" > "$BIN/tmux"
# 가짜 lsof: `-Fpcn` 꼴을 $T/lsof.out 에서 그대로 내고, 종료코드는 $T/lsof.rc 가 정한다(없으면 0)
cat > "$BIN/lsof" <<EOF
#!/bin/sh
[ -f "$T/lsof.rc" ] && exit "\$(cat "$T/lsof.rc")"
cat "$T/lsof.out" 2>/dev/null
exit 0
EOF
chmod 755 "$BIN/tmux" "$BIN/lsof"
cwd_rows() { : > "$T/lsof.out"; while [ "$#" -ge 3 ]; do printf 'p%s\nc%s\nfcwd\nn%s\n' "$2" "$3" "$1" >> "$T/lsof.out"; shift 3; done; }   # <경로> <pid> <명령> …
cwd_rows / 1 zsh   # 기준 = 사본 폴더를 cwd 로 쓰는 프로세스 0
sc() { OUT="$(env PATH="$BIN:$PATH" FT_RES_ROOT="$R" FT_SCRATCH_DIR="$SCR" TMPDIR="$TMPD" FT_SCRATCH_OWNER="${OWN:-live-owner}" ${AGE_MIN:+FT_SCRATCH_AGE_MIN=$AGE_MIN} bash "$SUT" "$@" 2>&1)"; RC=$?; }
mk() { OWN="$1" sc "$SHA" --repo "$G"; printf '%s' "$OUT"; }                                   # <주인> → 사본 경로
age_reg() { awk -F'\t' -v p="$1" -v t="$(( $(date +%s) - $2 ))" 'BEGIN{OFS="\t"} $1==p{$3=t} {print}' "$TSV" > "$TSV.n" && mv "$TSV.n" "$TSV"; }   # 등록 시각을 <초> 전으로
reg_col3() { awk -F'\t' -v p="$1" -v v="$2" 'BEGIN{OFS="\t"} $1==p{$3=v} {print}' "$TSV" > "$TSV.n" && mv "$TSV.n" "$TSV"; }

P="$(mk live-owner)"; age_reg "$P" 90000                                         # 주인 살아 있음 = 후보 아님
A="$(mk gone-a)";     age_reg "$A" 90000                                         # 주인 없음 · 25시간 · cwd 로 쓰임
D="$(mk gone-d)";     age_reg "$D" 90000                                         # 주인 없음 · 25시간 · cwd 아님
[ -d "$A" ] && [ -d "$D" ] && [ -d "$P" ] || { bad "사본 3개 생성 실패 A=$A D=$D P=$P"; echo "($fail failed)"; exit "$fail"; }
cwd_rows / 1 zsh "$A/scripts" 4242 uvicorn                                    # A 아래 폴더를 cwd 로 쓰는 서버 세트(그 폴더는 실재하지 않아도 된다)

# ⓕ 첫 --sweep = 목록 보고만(실삭제 0) 유지 · 붙잡은 A 는 «목록» 이 아니라 «장비 정리» 줄로
sc --sweep; LIST="$(printf '%s\n' "$OUT" | grep -m1 '목록 보고')"
{ [ $RC = 0 ] && [ -n "$LIST" ] && printf '%s' "$OUT" | grep -q '실삭제 0' && [ -d "$A" ] && [ -d "$D" ] \
  && ! printf '%s' "$LIST" | grep -q "$A" && printf '%s' "$LIST" | grep -q "$D" \
  && printf '%s' "$OUT" | grep -q "\[장비 정리\] 주인 gone-a 사본 $A 에서 pid 4242 uvicorn 실행 중 — 삭제 보류"; } \
  && ok "ⓕ 첫 --sweep = 목록 보고만 · 붙잡은 A 는 목록에 없고 «장비 정리» 줄로 따로" || bad "ⓕ rc=$RC out=$OUT"
[ -f "$ARMED" ] && ok "ⓕ armed 표식 생김(다음부터 자동)" || bad "ⓕ armed 없음"

# ⓐ/ⓑ 둘째 --sweep: cwd 사본 A = 삭제 0 + 붙잡음(로그·stdout) · cwd 아닌 D = 지금처럼 삭제 · 살아 있는 주인 P = 그대로
sc --sweep
{ [ $RC = 0 ] && [ -d "$A" ] && [ ! -d "$D" ] && [ -d "$P" ] \
  && printf '%s' "$OUT" | grep -q "\[장비 정리\] 주인 gone-a 사본 $A 에서 pid 4242 uvicorn 실행 중 — 삭제 보류"; } \
  && ok "ⓐ cwd 로 쓰이는 등록 사본 A = 삭제 0 · stdout [장비 정리] 1줄" || bad "ⓐ rc=$RC out=$OUT A=$([ -d "$A" ] && echo 있음 || echo 없음) D=$([ -d "$D" ] && echo 있음 || echo 없음)"
grep -q "붙잡음 $A (pid 4242 uvicorn · 주인 gone-a)" "$SLOG" && ok "ⓑ 로그 «붙잡음 …» 줄(경로·pid·명령·주인)" || bad "ⓑ 로그 붙잡음 줄 없음: $(grep -c . "$SLOG")줄"
grep -q 'swept=1 owner-dead=1 tmp=0 held=1' "$SLOG" && ok "ⓑ 요약 줄에 held=1" || bad "ⓑ 요약 줄: $(grep 'swept=' "$SLOG" | tail -1)"
[ -d "$P" ] && ok "ⓒ 주인 살아 있는 사본 P 는 그대로(동작 유지)" || bad "ⓒ P 삭제됨"
sc --report; printf '%s' "$OUT" | grep -q "$A	.*붙잡음 pid 4242 uvicorn" && : ; { printf '%s' "$OUT" | grep "$A" | grep -q '붙잡음 pid 4242 uvicorn'; } \
  && ok "ⓒ --report 도 붙잡음을 «붙잡음» 칸으로 보임" || bad "ⓒ report [$OUT]"

# ⓓ lsof 실패(rc≠0 · 0줄) = «아무도 안 씀» 으로 읽지 않는다 — 등록·tmp 둘 다 삭제 0 + 로그·stdout ERROR
E="$(mk gone-e)"; age_reg "$E" 90000; mkdir -p "$TMPD/tmp.old9"; touch -t 202001010000 "$TMPD/tmp.old9"
echo 1 > "$T/lsof.rc"; sc --sweep
{ [ $RC = 0 ] && [ -d "$E" ] && [ -d "$TMPD/tmp.old9" ] \
  && printf '%s' "$OUT" | grep -q 'ERROR lsof 실패 — 삭제 0' && grep -q 'ERROR lsof 실패 — 삭제 0' "$SLOG"; } \
  && ok "ⓓ lsof rc=1 → 등록·tmp 삭제 0 + 로그·stdout ERROR 1줄" || bad "ⓓ rc=$RC out=$OUT E=$([ -d "$E" ] && echo 있음 || echo 없음)"
: > "$T/lsof.out"; echo 0 > "$T/lsof.rc"; sc --sweep
{ [ -d "$E" ] && [ -d "$TMPD/tmp.old9" ] && printf '%s' "$OUT" | grep -q 'ERROR lsof 실패 — 삭제 0'; } \
  && ok "ⓓ lsof 출력 0줄 → 삭제 0 + ERROR" || bad "ⓓ 0줄 out=$OUT"
rm -f "$T/lsof.rc"

# ⓔ 폴더 경계 비교: tmp.ab(오래됨 · cwd 아님) 는 지우고 tmp.abc(cwd) 는 붙잡는다
mkdir -p "$TMPD/tmp.ab" "$TMPD/tmp.abc"; touch -t 202001010000 "$TMPD/tmp.ab" "$TMPD/tmp.abc"
cwd_rows / 1 zsh "$TMPD/tmp.abc" 5151 pytest
sc --sweep
{ [ ! -d "$TMPD/tmp.ab" ] && [ -d "$TMPD/tmp.abc" ] && grep -q "붙잡음 $TMPD/tmp.abc (pid 5151 pytest · 주인 -)" "$SLOG"; } \
  && ok "ⓔ tmp.ab 만 삭제 · tmp.abc(cwd) 붙잡음 — 앞부분 글자 비교 아님(폴더 경계)" || bad "ⓔ ab=$([ -d "$TMPD/tmp.ab" ] && echo 남음 || echo 지움) abc=$([ -d "$TMPD/tmp.abc" ] && echo 남음 || echo 지움)"

# ⓗ 등록 사본 나이 문턱(판정 1920 문구 = «주인 세션 없음 ∧ 등록 24시간 지남»)
F="$(mk gone-f)"; age_reg "$F" 3600                                              # 1시간 전 등록
sc --report; { ! printf '%s\n' "$OUT" | grep -q "	$F	"; } && ok "ⓗ 1시간 전 등록 = 후보 아님(삭제 0)" || bad "ⓗ 1시간 후보 [$OUT]"
sc --sweep; [ -d "$F" ] && ok "ⓗ 1시간 전 등록 사본 = --sweep 이 안 지움" || bad "ⓗ 1시간 사본 삭제됨"
age_reg "$F" 90000; sc --report; printf '%s' "$OUT" | grep -q "$F" && ok "ⓗ 25시간 지남 = 후보" || bad "ⓗ 25시간 후보 아님 [$OUT]"
age_reg "$F" 3600; AGE_MIN=60 sc --report; printf '%s' "$OUT" | grep -q "$F" && ok "ⓗ env FT_SCRATCH_AGE_MIN=60 이면 1시간 전도 후보" || bad "ⓗ env 60분 [$OUT]"
reg_col3 "$F" "?"; sc --report
{ ! printf '%s\n' "$OUT" | grep -q "	$F	" && printf '%s' "$OUT" | grep -q 'ERROR 등록표 3열이 숫자 아님 — 삭제 0'; } \
  && ok "ⓗ 3열 나이 모름 = 후보 아님 + ERROR(삭제 0)" || bad "ⓗ 나이 모름 [$OUT]"
sc --sweep; [ -d "$F" ] && ok "ⓗ 나이 모르는 사본 = --sweep 이 안 지움" || bad "ⓗ 나이 모름 사본 삭제됨"

# ⓖ 기존 시험 2종 그대로 통과(이 변경이 기존 동작을 깨지 않는다)
( cd "$HERE" && bash ./test_scratch_repo.sh ) > "$T/g1.txt" 2>&1; g1=$?
( cd "$HERE/scripts" && pytest -q test_scratch_repo_census.py ) > "$T/g2.txt" 2>&1; g2=$?
{ [ "$g1" = 0 ] && grep -q '^ALL PASS' "$T/g1.txt"; } && ok "ⓖ 기존 test_scratch_repo.sh = ALL PASS" || bad "ⓖ 기존 셸 시험 rc=$g1 ($(grep -c '^FAIL' "$T/g1.txt") FAIL)"
{ [ "$g2" = 0 ] && grep -q ' passed' "$T/g2.txt"; } && ok "ⓖ 기존 test_scratch_repo_census.py = 통과" || bad "ⓖ 기존 pytest rc=$g2 ($(tail -2 "$T/g2.txt" | tr '\n' ' '))"

[ $fail -eq 0 ] && echo "ALL PASS" || echo "($fail failed)"
exit $fail
