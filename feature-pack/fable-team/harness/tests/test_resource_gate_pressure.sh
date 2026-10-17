#!/usr/bin/env bash
# test_resource_gate_pressure.sh — R213 자원 문지기 황금값(커널 압력 단계 · 메모리 여유 % · 스왑 증가 속도 · 스왑 상한 · 승계 별 한도) + 샘플러 시험.
# 측정 명령은 PATH 앞 가짜 sysctl·vm_stat·memory_pressure·df·pgrep 만 쓴다 — 실 측정·실 동결 파일·실 launchd 0 · 임시 FT_RES_ROOT.
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1   # R201: 시험은 추적 사본 원본을 직접 부른다(LIVE_BIN 으로 넘기지 않음)
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
R="$T/R"; S="$T/stub"; mkdir -p "$R/.fable-team/state" "$S"
TSV="$R/.fable-team/state/pressure.tsv"; FREEZE="$R/.fable-team/state/RESOURCE_FREEZE"

# 가짜 측정 명령 — 값은 FAKE_* env 로 준다.
cat > "$S/sysctl" <<'X'
#!/bin/sh
case "$2" in
  vm.swapusage) echo "total = 14336.00M  used = ${FAKE_SWAP}.00M  free = 1000.00M  (encrypted)"; exit "${FAKE_RC_SWAP:-0}";;
  kern.memorystatus_vm_pressure_level) [ -n "${FAKE_LEVEL_FAIL:-}" ] && exit 1; echo "$FAKE_LEVEL"; exit "${FAKE_RC_LEVEL:-0}";;
  *) exit 1;;
esac
X
printf '#!/bin/sh\necho "System-wide memory free percentage: ${FAKE_MEMFREE}%%"\nexit "${FAKE_RC_MEM:-0}"\n' > "$S/memory_pressure"
printf '#!/bin/sh\necho "Mach Virtual Memory Statistics: (page size of 16384 bytes)"\necho "Swapouts:                          2303978."\nexit "${FAKE_RC_VM:-0}"\n' > "$S/vm_stat"
printf '#!/bin/sh\necho "Filesystem 1024-blocks Used Available Capacity Mounted"\necho "/dev/x 999999999 1 104857600 1%% /System/Volumes/Data"\nexit "${FAKE_RC_DF:-0}"\n' > "$S/df"
printf '#!/bin/sh\n[ "$1" = has-session ] && exit "${FAKE_HAS:-1}"\nexit 1\n' > "$S/tmux"
cat > "$S/pgrep" <<'X'
#!/bin/sh
[ "$1" = "-a" ] && shift
case "$*" in
  "-x claude") [ "${FAKE_AGENTS:-0}" -gt 0 ] && { seq 101 $((100+FAKE_AGENTS)); exit 0; }; exit 1;;
  "-x codex") exit 1;;
  *) exit 99;;
esac
X
chmod 755 "$S"/*

now() { date +%s; }
# mk_tsv <첫 swap> <분당 증가 MiB> — 60초 간격 6표본, 마지막 = 지금.
mk_tsv() { local n i t; n=$(now); : > "$TSV"; for i in 0 1 2 3 4 5; do t=$((n-(5-i)*60)); printf '%s\t%s\t50\t1\t2303978\n' "$t" $(( $1 + $2*i )) >> "$TSV"; done; }
rm_freeze() { rm -f "$FREEZE"; }
# g <check|check --succession|status> — 기본 정상 값(오늘 실측: level 1·memfree 51·swap 6133·agents 35)에 env 로 덮어쓴다. OUT·RC
g() { local a="$1"; shift; OUT="$(env FT_RES_ROOT="$R" PATH="$S:$PATH" FAKE_SWAP=6133 FAKE_LEVEL=1 FAKE_MEMFREE=51 FAKE_AGENTS=35 "$@" bash "$REPO/scripts/fable-team-bin/ft-resource-gate.sh" $a 2>&1)"; RC=$?; }
# expect <이름> <rc> <출력 패턴(grep -E)>
expect() { { [ "$RC" -eq "$2" ] && echo "$OUT" | grep -Eq "$3"; } && ok "$1" || bad "$1 rc=$RC want=$2 /$3/ OUT=$OUT"; }

rm_freeze; mk_tsv 6133 0
# ⓐ 오늘 실측 → OK (두 모드)
g check;              expect "ⓐ level1·memfree51·swap6133·rate0 새 좌석 OK" 0 '^OK .*level=1 rate=0 '
g "check --succession"; expect "ⓐ 승계 OK" 0 '^OK '
# ⓑ level 2(평소 값) → 새 좌석·승계 모두 OK (오빠 판정 1832)
g check FAKE_LEVEL=2;              expect "ⓑ level2 새 좌석 OK" 0 '^OK .*level=2 '
g "check --succession" FAKE_LEVEL=2; expect "ⓑ level2 승계 OK" 0 '^OK .*level=2 '
# ⓒ level 4 → 둘 다 REJECT
g check FAKE_LEVEL=4;              expect "ⓒ level4 새 좌석 REJECT" 3 '^REJECT resource level=4 limit=2$'
g "check --succession" FAKE_LEVEL=4; expect "ⓒ level4 승계 REJECT" 3 '^REJECT resource level=4 limit=3$'
# ⓓ rate 400 → 둘 다 OK(관측 최대 347 통과) · rate 600 → 새 좌석 REJECT·승계 OK · rate 1100 → 둘 다 REJECT
mk_tsv 6000 400
g check;              expect "ⓓ rate400 새 좌석 OK" 0 '^OK .*rate=400 '
g "check --succession"; expect "ⓓ rate400 승계 OK" 0 '^OK .*rate=400 '
mk_tsv 6000 600
g check;              expect "ⓓ rate600 새 좌석 REJECT" 3 '^REJECT resource rate=600MiB/min limit=512MiB/min$'
g "check --succession"; expect "ⓓ rate600 승계 OK" 0 '^OK .*rate=600 '
mk_tsv 6000 1100
g check;              expect "ⓓ rate1100 새 좌석 REJECT" 3 '^REJECT resource rate=1100MiB/min '
g "check --succession"; expect "ⓓ rate1100 승계 REJECT" 3 '^REJECT resource rate=1100MiB/min limit=1024MiB/min$'
# ⓔ swap 12289 → 둘 다 REJECT · swap 9000(옛 8192 초과) level1 rate≤0 → OK(후행 구간)
mk_tsv 12289 0
g check FAKE_SWAP=12289;              expect "ⓔ swap12289 새 좌석 REJECT" 3 '^REJECT resource swap=12289MiB limit=12288MiB$'
g "check --succession" FAKE_SWAP=12289; expect "ⓔ swap12289 승계 REJECT" 3 '^REJECT resource swap=12289MiB '
mk_tsv 9500 -100
g check FAKE_SWAP=9000;              expect "ⓔ swap9000·rate≤0 새 좌석 OK(후행 구간)" 0 '^OK .*swap=9000MiB .*rate=-'
# ⓕ agents 65 → 새 좌석 OK · 66 → 새 좌석 REJECT · 승계 OK
mk_tsv 6133 0
g check FAKE_AGENTS=65;              expect "ⓕ agents65 새 좌석 OK" 0 '^OK .*agents=65$'
g check FAKE_AGENTS=66;              expect "ⓕ agents66 새 좌석 REJECT" 3 '^REJECT resource agents=66 limit=65$'
g "check --succession" FAKE_AGENTS=66; expect "ⓕ agents66 승계 OK" 0 '^OK .*agents=66$'
# ⓖ memfree 12 → 새 좌석 REJECT · 승계 OK · memfree 9 → 둘 다 REJECT
g check FAKE_MEMFREE=12;              expect "ⓖ memfree12 새 좌석 REJECT" 3 '^REJECT resource memfree=12% limit=15%$'
g "check --succession" FAKE_MEMFREE=12; expect "ⓖ memfree12 승계 OK" 0 '^OK '
g check FAKE_MEMFREE=9;              expect "ⓖ memfree9 새 좌석 REJECT" 3 '^REJECT resource memfree=9% '
g "check --succession" FAKE_MEMFREE=9; expect "ⓖ memfree9 승계 REJECT" 3 '^REJECT resource memfree=9% limit=10%$'
# ⓗ 표본 낡음(마지막 표본 400초 전) → 문지기가 샘플러를 1회 직접 돌려 잰다(rc0+WARN) · 샘플러가 못 쓰면 rc4
n=$(now); printf '%s\t6133\t50\t1\t1\n%s\t6133\t50\t1\t1\n' $((n-460)) $((n-400)) > "$TSV"
g check; { [ "$RC" -eq 0 ] && echo "$OUT" | grep -q '^WARN resource pressure.tsv 없음/낡음' && [ "$(wc -l < "$TSV" | tr -d ' ')" = 3 ]; } && ok "ⓗ 표본 낡음 → 문지기 직접 1회 측정(3줄)" || bad "ⓗ rc=$RC $OUT"
printf '%s\t6133\t50\t1\t1\n%s\t6133\t50\t1\t1\n' $((n-460)) $((n-400)) > "$TSV"; chmod 444 "$TSV"
g check; expect "ⓗ 낡음+샘플러 기록 실패 → rc4" 4 '^ERROR resource measure pressure sample 실패'
g "check --succession"; expect "ⓗ 승계도 rc4" 4 '^ERROR resource measure pressure sample 실패'
chmod 644 "$TSV"
# ⓘ 표본 1줄·0줄 → rate=na + WARN + 나머지 신호로 판정
printf '%s\t6133\t50\t1\t1\n' "$(now)" > "$TSV"
g check; { [ "$RC" -eq 0 ] && echo "$OUT" | grep -q '^WARN resource rate=na' && echo "$OUT" | grep -q '^OK .*rate=na '; } && ok "ⓘ 표본 1줄 rate=na+WARN OK" || bad "ⓘ rc=$RC $OUT"
g check FAKE_LEVEL=4; expect "ⓘ rate=na 여도 level4 새 좌석 REJECT" 3 'REJECT resource level=4'
rm -f "$TSV"
g check; { [ "$RC" -eq 0 ] && echo "$OUT" | grep -q 'rate=na'; } && ok "ⓘ 표본 파일 없음 → 문지기 1회 측정 + rate=na" || bad "ⓘ(없음) rc=$RC $OUT"
# ⓙ 동결 파일 → 둘 다 REJECT(현행)
mk_tsv 6133 0; echo "시험 동결" > "$FREEZE"
g check;              expect "ⓙ 동결 새 좌석 REJECT" 3 '^REJECT resource freeze='
g "check --succession"; expect "ⓙ 동결 승계 REJECT" 3 '^REJECT resource freeze='
rm_freeze
# status 한 줄 + level 측정 실패 = ERROR exit 4 + 옛 env 폐기
g status; { [ "$RC" -eq 0 ] && [ "$(echo "$OUT" | grep -c '^disk=')" = 1 ] && echo "$OUT" | grep -q '^disk=.* level=1 rate=0 agents=35 freeze=0$'; } && ok "status 한 줄 level·rate 칸" || bad "status rc=$RC $OUT"
g check FAKE_LEVEL_FAIL=1; expect "level 측정 실패 exit 4" 4 '^ERROR resource measure level '
g check FT_SWAP_MAX_MIB=100; expect "옛 FT_SWAP_MAX_MIB 는 읽지 않는다" 0 '^OK '
g "check --bogus"; expect "알 수 없는 2번째 인자 exit 2" 2 'usage:'

# H1 — 측정 명령 rc≠0 이면 출력이 숫자여도 rc4(gate·sampler · 표본 줄 0) · 깨진 TSV 줄도 rc4
mk_tsv 6133 0
for v in LEVEL SWAP MEM DF; do g check FAKE_RC_$v=42; expect "H1 gate $v 명령 rc42+유효 출력 → rc4" 4 '^ERROR resource measure .* rc≠0$'; done
n=$(now); printf '%s\toops\t50\t1\t1\n%s\toops\t50\t1\t1\n' $((n-60)) "$n" > "$TSV"
g check; expect "H1 swap 칸 oops 두 줄 → rc4 corrupt" 4 '^ERROR resource measure pressure.tsv corrupt'
printf '%s\t6133\t50\t1\n%s\t6133\t50\t1\n' $((n-60)) "$n" > "$TSV"
g check; expect "H1 4칸 줄 → rc4 corrupt" 4 'pressure.tsv corrupt'
printf '%s\t6133\t50\t1\t1\n%s\t6133\t50\t1\t1\n' "$n" $((n-60)) > "$TSV"
g check; expect "H1 시각 내림차순 → rc4 corrupt" 4 'pressure.tsv corrupt'
printf '%s\t6133\t50\t1\t1\n%s\t6133\t50\t1\t1\n' "$n" "$n" > "$TSV"
g check; expect "H1 시각 차 0(두 줄 같은 시각) → rc4 corrupt" 4 'pressure.tsv corrupt'
SAMP="$REPO/scripts/fable-team-bin/ft-resource-sample.sh"
sm() { OUT="$(env FT_RES_ROOT="$R" PATH="$S:$PATH" FAKE_SWAP=6133 FAKE_LEVEL=1 FAKE_MEMFREE=51 "$@" bash "$SAMP" 2>&1)"; RC=$?; }
for v in LEVEL SWAP MEM VM; do
  rm -f "$TSV"; sm FAKE_RC_$v=42
  { [ "$RC" -eq 4 ] && echo "$OUT" | grep -q '^ERROR resource sample .* rc≠0$' && [ ! -s "$TSV" ]; } && ok "H1 sampler $v 명령 rc42+유효 출력 → rc4·줄 0" || bad "H1 sampler $v rc=$RC $OUT"
done
# H2(r2) — rate=na 는 검증 통과한 «1줄뿐»(180초 안)만 · 지나면 다시 재서 2줄 · ready 표식 없음 · 미래 시각/역행 rc4
n=$(now)
printf '%s\t6133\t50\t1\t1\n' $((n-400)) > "$TSV"
g check; { [ "$RC" -eq 0 ] && [ "$(wc -l < "$TSV" | tr -d ' ')" = 2 ] && echo "$OUT" | grep -q 'rate=[0-9-]'; } && ok "H2 400초 된 1줄 → 직접 재서 2줄·rate 숫자(예외 닫힘)" || bad "H2 400초 1줄 rc=$RC $OUT"
rm -f "$TSV"; g check; { [ "$RC" -eq 0 ] && echo "$OUT" | grep -q 'rate=na'; } && ok "H2 파일 없음 첫 호출 → rate=na" || bad "H2 첫 rc=$RC $OUT"
g check; { [ "$RC" -eq 0 ] && echo "$OUT" | grep -q 'rate=na' && [ "$(wc -l < "$TSV" | tr -d ' ')" = 1 ]; } && ok "H2 반복 호출(180초 안) → 같은 1줄 rate=na" || bad "H2 반복 rc=$RC $OUT"
printf '%s\t6133\t50\t1\t1\n' $(( $(now) - 200 )) > "$TSV"
g check; { echo "$OUT" | grep -q 'rate=[0-9-]' && [ "$RC" -eq 0 ]; } && ok "H2 부트스트랩 기한 180초 — 지나면 rate 숫자" || bad "H2 기한 rc=$RC $OUT"
: > "$R/.fable-team/state/pressure.ready"; rm -f "$TSV"; g check
[ "$RC" -eq 0 ] && ok "H2 ready 표식은 무시(있어도 없어도 같음)" || bad "H2 ready rc=$RC $OUT"
rm -f "$R/.fable-team/state/pressure.ready"
n=$(now); printf '%s\t6133\t50\t1\t1\n%s\t6133\t50\t1\t1\n' $((n+3600)) $((n+3660)) > "$TSV"
g check; expect "H2 미래 시각 두 줄 → rc4 clock-skew" 4 'pressure.tsv clock-skew'
printf '%s\t6133\t50\t1\t1\n' $((n+3600)) > "$TSV"
g check; expect "H2 미래 시각 1줄 → rc4 clock-skew" 4 'pressure.tsv clock-skew'
printf '%s\toops\tbad\t1\t1\n' "$n" > "$TSV"
g check; expect "H1(r2) 1줄 숫자 칸 oops → rc4 corrupt" 4 'pressure.tsv corrupt'
printf '%s\t6133\t50\t1\t1\n%s\t6133\t50\t1\t1\n' "$n" $((n-60)) > "$TSV"
g check; expect "H2 시각 역행 → rc4 corrupt" 4 'pressure.tsv corrupt'
rm -f "$TSV"
mk_tsv 6133 0; g check FAKE_AGENTS=99; expect "probe 일반 agents99 gate rc3" 3 '^REJECT resource agents=99 limit=65$'
# H3(r2) — 승계 면제 = NAME==OLD 계보 베이스#(N+1) ∧ OLD 가 명부 역할 키(_master 등) 값 ∧ OLD tmux 생존 (agents 99 로 일반 REJECT 되는 상황)
mk_tsv 6133 0
SUC="$REPO/scripts/fable-team-bin/ft-successor-open.sh"; mkdir -p "$T/cwd" "$T/home"; echo 본문 > "$T/body.txt"
so() { OUT="$(cd "$T/cwd" && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY HOME="$T/home" FT_RES_ROOT="$R" PATH="$S:$PATH" FAKE_SWAP=6133 FAKE_LEVEL=1 FAKE_MEMFREE=51 FAKE_AGENTS=99 FT_RECLAIM=0 "$@" bash "${SUCX:-$SUC}" "$OLDN" "$T/cwd" --name "$NEWN" --agent claude --model m --body-file "$T/body.txt" 2>&1)"; RC=$?; }
agents_rej() { { [ "$RC" -eq 3 ] && echo "$OUT" | grep -q 'REJECT resource agents=99 limit=65'; }; }
printf '{"_master":"alive-old#1","other#2":{"role":"nano"}}\n' > "$R/.fable-team/seats-t.json"
OLDN='alive-old#1'; NEWN='alive-old#2'; so FAKE_HAS=0
echo "$OUT" | grep -q 'REJECT resource' && bad "H3 계보·역할 키·생존 → 면제돼야 함: $OUT" || ok "H3 계보 O·역할 키 O·세션 O → agents 면제"
NEWN='alive-old#2'; so FAKE_HAS=1
agents_rej && ok "H3 세션 없음 → 일반 기준" || bad "H3 세션 없음 rc=$RC $OUT"
NEWN='unrelated-new#9'; so FAKE_HAS=0
agents_rej && ok "H3 계보 불일치(무관한 새 이름) → 일반 기준" || bad "H3 계보 불일치 rc=$RC $OUT"
NEWN='alive-old#3'; so FAKE_HAS=0
agents_rej && ok "H3 N+2 건너뜀 → 일반 기준" || bad "H3 N+2 rc=$RC $OUT"
OLDN='other#2'; NEWN='other#3'; so FAKE_HAS=0
agents_rej && ok "H3 역할 키 값이 아닌 일반 좌석 키(other#2) → 일반 기준" || bad "H3 일반 키 rc=$RC $OUT"
OLDN='missing-old#1'; NEWN='missing-old#2'; so FAKE_HAS=0
agents_rej && ok "H3 명부에 없는 OLD → 일반 기준" || bad "H3 명부 없음 rc=$RC $OUT"
printf '{"_master":"missing-old#1"}\n' > "$R/.fable-team/seats-other.json"
OLDN='missing-old#1'; NEWN='unrelated-new#9'; so FAKE_HAS=0
agents_rej && ok "H3 다른 팀 명부의 OLD + 무관한 새 이름 → 일반 기준(DA 반례)" || bad "H3 다른 팀 rc=$RC $OUT"
# 변이 — 계보 검사를 지운 successor-open 은 위 불일치 단언에서 «걸려야» 한다
MUT="$T/mut"; mkdir -p "$MUT"; cp "$REPO"/scripts/fable-team-bin/ft-*.sh "$MUT"/
sed 's/\[ "\$NAME" = "\${BASH_REMATCH\[1\]}#\$((BASH_REMATCH\[2\]+1))" \]/true/' "$SUC" > "$MUT/ft-successor-open.sh"
cmp -s "$MUT/ft-successor-open.sh" "$SUC" && bad "H3 변이 준비 실패(치환 0)" || {
  OLDN='alive-old#1'; NEWN='unrelated-new#9'; SUCX="$MUT/ft-successor-open.sh" so FAKE_HAS=0
  echo "$OUT" | grep -q 'REJECT resource' && bad "H3 변이: 계보 검사 삭제가 검출되지 않음" || ok "H3 변이(계보 검사 삭제) 검출"; }
rm -f "$R/.fable-team/seats-t.json" "$R/.fable-team/seats-other.json"

# ⓚ 샘플러 — 1줄 추가 · 3일 회전 · 측정 실패 rc 4 줄 0
n=$(now); printf '%s\t1\t1\t1\t1\n%s\t6000\t50\t1\t1\n' $((n-300000)) $((n-60)) > "$TSV"
sm
{ [ "$RC" -eq 0 ] && [ "$(wc -l < "$TSV" | tr -d ' ')" = 2 ] && awk -F'\t' 'END{exit !(NF==5 && $2==6133 && $3==51 && $4==1 && $5==2303978)}' "$TSV"; } && ok "ⓚ 샘플러 1줄 추가(5칸)+3일 넘은 줄 회전" || bad "ⓚ rc=$RC lines=$(wc -l < "$TSV") $(cat "$TSV")"
before="$(cat "$TSV")"
sm FAKE_LEVEL_FAIL=1
{ [ "$RC" -eq 4 ] && echo "$OUT" | grep -q '^ERROR resource sample level' && [ "$(cat "$TSV")" = "$before" ]; } && ok "ⓚ 측정 실패 rc4·줄 안 씀" || bad "ⓚ(실패) rc=$RC $OUT"
rm -f "$TSV"; sm
{ [ "$RC" -eq 0 ] && [ "$(wc -l < "$TSV" | tr -d ' ')" = 1 ]; } && ok "ⓚ 표본 파일 없어도 생성" || bad "ⓚ(생성) rc=$RC $OUT"

# DA r3 — 샘플러 직렬화 잠금: 동시 교차(A 가 회전 mv 직전 정지 · B 가 끝낸 뒤 A 재개) 에도 표본 2줄 유지 · 같은 초 표본 추가 0 · 죽은 pid/30초 초과 잠금 회수 · 살아 있는 잠금은 2초 뒤 rc4
LK="$R/.fable-team/state/pressure.lock.d"; CT="$T/ctrl"; mkdir -p "$CT" "$T/mvstub"
cat > "$T/mvstub/mv" <<'X'
#!/bin/bash
if [ "${RUN_ID:-}" = A ]; then touch "$CTRL/mvready"; n=0; while [ ! -f "$CTRL/finishA" ] && [ $n -lt 600 ]; do sleep 0.01; n=$((n+1)); done; fi
exec /bin/mv "$@"
X
printf '#!/bin/sh\n[ -n "${FAKE_NOW:-}" ] && [ "$1" = "+%%s" ] && { echo "$FAKE_NOW"; exit 0; }\nexec /bin/date "$@"\n' > "$S/date"
chmod 755 "$T/mvstub/mv" "$S/date"
unlock() { rm -f "$LK/owner"; rmdir "$LK" 2>/dev/null; return 0; }
# conc <샘플러 경로> — A: mv 직전 정지(잠금 보유) → 1.1초 뒤 B 시작 → A 재개. ROWS·RA·RB
conc() {
  unlock; rm -f "$TSV" "$CT"/*
  env RUN_ID=A CTRL="$CT" FT_RES_ROOT="$R" PATH="$T/mvstub:$S:$PATH" FAKE_SWAP=6133 FAKE_LEVEL=1 FAKE_MEMFREE=51 bash "$1" >/dev/null 2>&1 & pa=$!
  n=0; while [ ! -f "$CT/mvready" ] && [ $n -lt 500 ]; do sleep 0.01; n=$((n+1)); done
  sleep 1.1
  env RUN_ID=B CTRL="$CT" FT_RES_ROOT="$R" PATH="$T/mvstub:$S:$PATH" FAKE_SWAP=6133 FAKE_LEVEL=1 FAKE_MEMFREE=51 bash "$1" >/dev/null 2>&1 & pb=$!
  sleep 0.3; touch "$CT/finishA"
  wait $pa; RA=$?; wait $pb; RB=$?
  ROWS="$(wc -l < "$TSV" | tr -d ' ')"
}
conc "$SAMP"
{ [ "$ROWS" = 2 ] && [ "$RA" = 0 ] && [ "$RB" = 0 ] && [ ! -d "$LK" ]; } && ok "r3 동시 교차 → 표본 2줄 유지·rc0·잠금 해제" || bad "r3 동시 교차 rows=$ROWS A=$RA B=$RB"
MUT2="$T/mut2"; mkdir -p "$MUT2"; cp "$REPO"/scripts/fable-team-bin/ft-*.sh "$MUT2"/
sed 's/^until mkdir "\$LOCK" 2>\/dev\/null; do$/until true; do/' "$SAMP" > "$MUT2/ft-resource-sample.sh"
cmp -s "$MUT2/ft-resource-sample.sh" "$SAMP" && bad "r3 변이 준비 실패(치환 0)" || {
  conc "$MUT2/ft-resource-sample.sh"
  [ "$ROWS" = 2 ] && bad "r3 변이: 잠금 제거가 검출되지 않음" || ok "r3 변이(잠금 제거) 검출 rows=$ROWS"; }
unlock; rm -f "$TSV"
# 같은 초 표본 추가 0 · 시계 역행 rc4
printf '%s\t1\t1\t1\t1\n' 2000000000 > "$TSV"
sm FAKE_NOW=2000000000
{ [ "$RC" -eq 0 ] && [ "$(wc -l < "$TSV" | tr -d ' ')" = 1 ]; } && ok "r3 같은 초 표본 추가 0" || bad "r3 같은 초 rc=$RC $OUT"
sm FAKE_NOW=2000000001
{ [ "$RC" -eq 0 ] && [ "$(wc -l < "$TSV" | tr -d ' ')" = 2 ]; } && ok "r3 다음 초 표본 추가" || bad "r3 다음 초 rc=$RC $OUT"
sm FAKE_NOW=1999999999
{ [ "$RC" -eq 4 ] && echo "$OUT" | grep -q 'clock-backwards' && [ "$(wc -l < "$TSV" | tr -d ' ')" = 2 ]; } && ok "r3 시계 역행 rc4·줄 0" || bad "r3 역행 rc=$RC $OUT"
# 닫는 사건 — 죽은 pid 잠금 · 30초 넘은 잠금은 회수, 살아 있는 신선한 잠금은 2초 뒤 rc4(잠금 유지)
rm -f "$TSV"; true & dp=$!; wait $dp
mkdir "$LK"; echo "$dp $(now)" > "$LK/owner"
sm
{ [ "$RC" -eq 0 ] && [ "$(wc -l < "$TSV" | tr -d ' ')" = 1 ] && [ ! -d "$LK" ]; } && ok "r3 죽은 pid 잠금 → 회수·정상 기록(영구 rc4 0)" || bad "r3 죽은 pid rc=$RC $OUT"
rm -f "$TSV"; mkdir "$LK"; echo "$$ $(( $(now) - 40 ))" > "$LK/owner"
sm
{ [ "$RC" -eq 0 ] && [ "$(wc -l < "$TSV" | tr -d ' ')" = 1 ] && [ ! -d "$LK" ]; } && ok "r3 30초 넘은 잠금 → 회수" || bad "r3 age>30 rc=$RC $OUT"
rm -f "$TSV"; mkdir "$LK"; echo "$$ $(now)" > "$LK/owner"
sm
{ [ "$RC" -eq 4 ] && echo "$OUT" | grep -q 'lock 대기 2초 초과' && [ -d "$LK" ] && [ ! -s "$TSV" ]; } && ok "r3 살아 있는 신선한 잠금 → 2초 뒤 rc4·남의 잠금 유지·줄 0" || bad "r3 live lock rc=$RC $OUT"
unlock; rm -f "$TSV"

# 감시자 tick 이 샘플러를 부른다(가짜 측정·임시 루트·동결 문턱 밖 값)
rm -f "$TSV"
env FT_RES_ROOT="$R" PATH="$S:$PATH" FAKE_SWAP=6133 FAKE_LEVEL=1 FAKE_MEMFREE=51 FAKE_AGENTS=35 FT_RES_SNAP_SEC=999999 bash "$REPO/scripts/fable-team-bin/ft-resource-watch.sh" tick >/dev/null 2>&1
{ [ -s "$TSV" ] && [ ! -f "$FREEZE" ]; } && ok "감시자 tick → pressure.tsv 1줄" || bad "감시자 tick 표본 없음"

# 키트 사본 일치 · 감시자 줄 수 · bash -n · core.bare
for f in ft-resource-gate.sh ft-resource-watch.sh ft-resource-sample.sh ft-resource-reclaim.sh ft-successor-open.sh; do
  bash -n "$REPO/scripts/fable-team-bin/$f" && cmp -s "$REPO/scripts/fable-team-bin/$f" "$REPO/scripts/harness-install/fable-team/bin/$f" && ok "bash -n + 키트 cmp $f" || bad "$f"
done
[ "$(wc -l < "$REPO/scripts/fable-team-bin/ft-resource-watch.sh" | tr -d ' ')" -le 209 ] && ok "감시자 줄 수 ≤209" || bad "감시자 줄 수"
grep -q '_rgsucc="--succession"' "$REPO/scripts/fable-team-bin/ft-successor-open.sh" && ok "successor-open 이 조건부 --succession" || bad "successor-open --succession"
[ "$(git -C "$REPO" config --get core.bare)" = false ] && ok "core.bare=false" || bad "core.bare"
echo "fail=$fail"; [ $fail -eq 0 ]
