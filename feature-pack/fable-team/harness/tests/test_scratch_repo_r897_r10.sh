#!/usr/bin/env bash
# test_scratch_repo_r897_r10.sh — r897 r10.2: ft-scratch-repo.sh 의 «지우는 길» 을 한 곳씩 막는다
#   V0 실측(대역 아님): macOS lsof 는 물리 경로(/private/var/…)를 낸다 → 기준판 글자 비교는 «붙잡음» 0 (빨강 재현) · 고친 판 «붙잡음»(초록)
#   ⓐ cwd 비교 = 물리 경로(+경로 못 읽음 = 붙잡음) · ⓑ 주인 대조 = 정확 대조(이름에 정규식 글자) · ⓒ 2720 빠른 길 4조건 · ⓓ 지우기 직전 재확인
#   ⓔ --done = 주인 자신·정확 대조·lsof 실패 rc4·탭/개행 rc2
#   ⓤ 빠른 길의 «못 읽음» = 빠른 길 아님(symbolic-ref rc128) · ⓥ 재확인 예산(tmux 8초 멈춤 = 7초 상한·호출 뒤 마감 검사)
#   ⓦ 빠른 길 호출 나무 전수 rc 검사(judged 안 merge-base·git log 포함) — 출력은 있으나 rc128 = 못 읽음 = 지우기 0(DA⑥ r2 반례 1)
#   ⓨ 기계 검사(손 전수 표 대체): 지우는 길 함수(출구 게이트 delete_copy 포함) 범위에서 `$(`·`<(`·백틱·파이프 0 · 삭제 명령은 delete_copy 안에만 · CALLTREE 자동 생성(FT_CALLTREE_OUT)
#   ⓙⓚⓛ r996: ① 장부 둘(ROOT + 원 저장소 — --done·--sweep 이 한쪽 장부만 있어도 봄) ② 판정 2720 입구(판정 끝 ∧ 주인 없음 = 24시간 없이 · 완성 표식 필요 · .scratch-judged) ③ ⓗ 선등록 안전(있던 폴더 rm 0 · rm 실패 = 등록 유지 · 재사용은 완성 표식만)
#   ⓕ 기존 시험 4종 + 출구 게이트 시험(test_scratch_exit_gate_r897.sh — 이웃 생존 · --gate · 주입 전수 · 변이) + kit cmp0 · 변이 9 — «기대한 칸 이름» 의 FAIL 만 있을 때 검출
#   (r10.5 의 ⓧ 주입 칸은 r5 에서 이웃 생존 단언과 함께 test_scratch_exit_gate_r897.sh 로 옮겼다)
# 임시 git 저장소·가짜 tmux/lsof/date·임시 TMPDIR 만 쓴다 — 실 저장소·실 세션·실 삭제 0(임시 폴더 안만).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/.." && pwd)"
SUT="${FT_SUT:-$REPO/bin/ft-scratch-repo.sh}"            # FT_SUT = 변이·기준판 대조 실행
CASES="${FT_CASES:-all}"                                  # 케이스만 돌리기(변이 시험용): 예 FT_CASES=ⓑ
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
want() { case "$CASES" in all) return 0;; *"$1"*) return 0;; esac; return 1; }
[ -f "$SUT" ] || { bad "ft-scratch-repo.sh 없음 ($SUT)"; echo "(1 failed)"; exit 1; }

T="$(mktemp -d)"; trap 'chmod -R u+rwX "$T" 2>/dev/null; rm -rf "$T"' EXIT
G="$T/src"; R="$T/R"; SCR="$T/scratch"; TMPD="$T/tmpdir"; BIN="$T/bin"
mkdir -p "$G" "$SCR" "$TMPD" "$BIN"
cm() { git -C "$1" -c user.name=t -c user.email=t@t commit -q -m "$2"; }
git -C "$G" init -q -b main && echo a > "$G/a.txt" && git -C "$G" add a.txt && cm "$G" c1
SHA="$(git -C "$G" rev-parse HEAD)"
git clone -q "$G" "$R" && mkdir -p "$R/.fable-team/state"   # ROOT = git 저장소(judged 의 «판정 기준 트리» 전제 · r645)
STATE="$R/.fable-team/state"; TSV="$STATE/scratch-repos.tsv"; SLOG="$STATE/scratch-sweep.log"; ARMED="$STATE/scratch-sweep.armed"

printf 'live-owner\n' > "$T/sessions"; printf 'live-owner\nseat[\n' > "$T/sessions.late"
# 가짜 tmux: n번째 호출부터 SWAP_AT 이면 sessions.late 를 낸다(«그 사이 주인이 생겼다» 재현) · SLEEP_AT 번째부터 SLEEP_SECS 만큼 멈춘다(«tmux 가 늘어짐» 재현 · r10.3)
cat > "$BIN/tmux" <<EOF
#!/bin/sh
[ "\$1" = list-sessions ] || exit 0
n=\$(( \$(cat "$T/tmux.n" 2>/dev/null || echo 0) + 1 )); echo "\$n" > "$T/tmux.n"
if [ -n "\${SLEEP_AT:-}" ] && [ "\$n" -ge "\${SLEEP_AT}" ]; then sleep "\${SLEEP_SECS:-8}"; fi
if [ -n "\${SWAP_AT:-}" ] && [ "\$n" -ge "\${SWAP_AT}" ] && [ -f "$T/sessions.late" ]; then cat "$T/sessions.late"; exit 0; fi
cat "$T/sessions"
EOF
# 가짜 lsof: $T/lsof.out 을 내고, LATE_AT 번째 호출부터 LATE_RC 로 실패한다 · $T/lsof.rc 가 있으면 그 값으로 조기 종료
cat > "$BIN/lsof" <<EOF
#!/bin/sh
[ -f "$T/lsof.rc" ] && exit "\$(cat "$T/lsof.rc")"
n=\$(( \$(cat "$T/lsof.n" 2>/dev/null || echo 0) + 1 )); echo "\$n" > "$T/lsof.n"
if [ -n "\${LATE_AT:-}" ] && [ "\$n" -ge "\${LATE_AT}" ]; then exit "\${LATE_RC:-1}"; fi
cat "$T/lsof.out" 2>/dev/null
exit 0
EOF
# 가짜 date: DSKEW_AT 번째 «+%s» 호출부터 100초 앞으로(«재확인 70초 초과» 재현)
cat > "$BIN/date" <<EOF
#!/bin/sh
if [ "\$1" = "+%s" ] && [ -n "\${DSKEW_AT:-}" ] && [ -n "\${DCNT:-}" ]; then
  n=\$(( \$(cat "\$DCNT" 2>/dev/null || echo 0) + 1 )); echo "\$n" > "\$DCNT"
  [ "\$n" -lt "\${DSKEW_AT}" ] || { /bin/date +%s | awk '{print \$1+100}'; exit 0; }
fi
exec /bin/date "\$@"
EOF
chmod 755 "$BIN/tmux" "$BIN/lsof" "$BIN/date"
cwd_rows() { : > "$T/lsof.out"; while [ "$#" -ge 3 ]; do printf 'p%s\nc%s\nfcwd\nn%s\n' "$2" "$3" "$1" >> "$T/lsof.out"; shift 3; done; }
physp() { ( cd "$1" 2>/dev/null && pwd -P ) || printf '%s' "$1"; }
sc() { : > "$T/tmux.n"; : > "$T/lsof.n"; : > "$T/date.n"
  OUT="$(env PATH="$BIN:$PATH" FT_RES_ROOT="$R" FT_SCRATCH_DIR="${SDIR:-$SCR}" TMPDIR="$TMPD" FT_SCRATCH_OWNER="${OWN:-live-owner}" \
    FT_SCRATCH_MAIN="${MAIN:-$SHA}" FT_SCRATCH_JUDGE_BUDGET="${JB:-20}" SWAP_AT="${SWAP_AT:-}" LATE_AT="${LATE_AT:-}" LATE_RC="${LATE_RC:-}" \
    SLEEP_AT="${SLEEP_AT:-}" SLEEP_SECS="${SLEEP_SECS:-}" \
    DCNT="${DSKEW_AT:+$T/date.n}" DSKEW_AT="${DSKEW_AT:-}" FT_SCRATCH_AGE_MIN="${AGE_MIN:-}" \
    FGIT_MODE="${FGIT_MODE:-}" FGIT_RC="${FGIT_RC:-}" \
    bash "$SUT" "$@" 2>&1)"; RC=$?; }
mk() { OWN="$1" sc "$SHA" --repo "$G"; printf '%s' "$OUT"; }
age_reg() { awk -F'\t' -v p="$1" -v t="$(( $(date +%s) - $2 ))" 'BEGIN{OFS="\t"} $1==p{$3=t} {print}' "$TSV" > "$TSV.n" && mv "$TSV.n" "$TSV"; }
reg_add() { printf '%s\t%s\t%s\n' "$1" "$2" "$(( $(date +%s) - $3 ))" >> "$TSV"; }
ready() { [ -f "$STATE/scratch-ready/${1##*/}" ]; }   # r996 완성 표식(상태 폴더의 사본별 표식 — 사본 트리 밖)
cwd_rows / 1 zsh   # 기준 대역 = 사본 폴더를 cwd 로 쓰는 프로세스 0(각 케이스가 필요하면 다시 깐다)

# ── V0 선행 실측(대역 아님) — 실제 lsof 는 /private/var/… 를 낸다 ─────────────────────────
if want V0; then
  held="$TMPD/tmp.held"; mkdir -p "$held"; touch -t 202001010000 "$held"; ( cd "$held" && sleep 20 ) & SPID=$!
  sleep 0.4
  lsof -w -d cwd -Fpcn 2>/dev/null > "$T/lsof.out"
  ROW="$(sed -n 's/^n//p' "$T/lsof.out" | grep -F 'tmp.held' | head -1)"
  case "$ROW" in /private/*) LSOF_PHYS=1;; *) LSOF_PHYS=0;; esac
  # 기준판 글자 비교(고치기 전): 등록부 꼴 /var/… vs lsof /private/var/… → 불일치 = «붙잡음 0» 재현
  case "$ROW" in "$held"|"$held"/*) OLD_HELD=1;; *) OLD_HELD=0;; esac
  AGE_MIN=0 sc --report
  { [ "$LSOF_PHYS" = 1 ] && [ "$OLD_HELD" = 0 ] && printf '%s' "$OUT" | grep -q 'tmp.held.*붙잡음'; } \
    && ok "V0 실 lsof 물리 경로($ROW) · 기준판 글자 비교 = 붙잡음 0(빨강) · 고친 판 = 붙잡음(초록)" \
    || bad "V0 phys=$LSOF_PHYS old=$OLD_HELD row=$ROW out=[$OUT]"
  kill "$SPID" 2>/dev/null; wait "$SPID" 2>/dev/null; rm -rf "$held"
fi

# ── ⓐ cwd 비교 = 물리 경로 · 경로 못 읽음 = 붙잡음 ─────────────────────────────────────
if want ⓐ; then
  P="$(mk gone-a)"; age_reg "$P" 90000
  ln -s "$P" "$T/link-copy"; printf '%s\t%s\t%s\n' "$T/link-copy" gone-a "$(( $(date +%s) - 90000 ))" >> "$TSV"
  cwd_rows "$(physp "$P")/scripts" 4242 uvicorn
  sc --report
  { printf '%s' "$OUT" | grep -q "link-copy	.*붙잡음 pid 4242 uvicorn"; } \
    && ok "ⓐ 등록 경로 /var 꼴 · lsof 물리 경로 → «붙잡음»(재현 빨강 닫힘)" || bad "ⓐ report [$OUT]"
  sc --sweep; sc --sweep
  { [ -d "$P" ] && [ -L "$T/link-copy" ]; } && ok "ⓐ cwd 물린 사본 = --sweep 2회 뒤에도 삭제 0" || bad "ⓐ 사본 삭제됨 $P"
  Q="$SCR/repo-dead-1-1"; mkdir -p "$Q"; chmod 000 "$Q"; reg_add "$Q" gone-dead 90000
  cwd_rows / 1 zsh
  sc --report
  { printf '%s' "$OUT" | grep -q "repo-dead-1-1.*붙잡음"; } && ok "ⓐ 경로 못 읽음(cd 실패) = 붙잡음(지우기 0)" || bad "ⓐ 못 읽음 [$OUT]"
  chmod 755 "$Q"
fi

# ── ⓑ 주인 대조 = 정확 대조(-F) — 이름에 정규식 글자 ────────────────────────────────
if want ⓑ; then
  S="$(mk gone-seat)"; OWN='seat[' sc "$SHA" --repo "$G"; S="$(printf '%s' "$OUT")"; age_reg "$S" 90000
  printf 'seat[\n' > "$T/sessions"
  : > "$T/lsof.out"; cwd_rows / 1 zsh
  sc --report
  { [ $RC = 0 ] && ! printf '%s\n' "$OUT" | grep -q "$S"; } && ok "ⓑ 주인 'seat[' = 후보 0(grep rc2 를 «주인 없음» 으로 읽지 않는다)" || bad "ⓑ 후보 [$OUT]"
  sc --sweep; sc --sweep
  [ -d "$S" ] && ok "ⓑ --sweep 2회 뒤에도 삭제 0" || bad "ⓑ 삭제됨 $S"
  printf 'live-owner\n' > "$T/sessions"
fi

# ── ⓒ 2720 빠른 길: «주인 없음 ∧ 이름꼴 ∧ HEAD=sha8 ∧ detached ∧ judged rc0» 넷 다 참일 때만 ──
if want ⓒ; then
  C1="$(mk gone-c1)"; C2="$(mk gone-c2)"; C3="$(mk gone-c3)"
  git -C "$C2" -c user.name=t -c user.email=t@t commit -q --allow-empty -m extra          # ② 커밋 1개 추가
  git -C "$C3" checkout -q -b side                                                       # ③ 가지 체크아웃
  git -C "$G" checkout -q --orphan other; echo o > "$G/o.txt"; git -C "$G" add o.txt; cm "$G" c3; OTHER="$(git -C "$G" rev-parse HEAD)"; git -C "$G" checkout -q -
  git -C "$R" fetch -q origin   # ROOT 에도 그 커밋이 있어야 judged 가 «못 읽음» 이 아니라 «안 끝남»(rc1) 을 낸다
  C5="$SCR/repo-nope-1-1"; mkdir -p "$C5"; reg_add "$C5" gone-c5 60
  sc --sweep; sc --sweep
  { [ ! -d "$C1" ] && grep -q "judged" "$SLOG"; } && ok "ⓒ 넷 다 참 = 삭제 · 로그에 사유 judged" || bad "ⓒ rc=$RC [$OUT]"
  { [ -d "$C2" ] && [ -d "$C3" ] && [ -d "$C5" ]; } && ok "ⓒ 커밋 추가·가지 체크아웃·이름꼴 아님 = 삭제 0(24h 규칙으로 후퇴)" || bad "ⓒ C2=$([ -d "$C2" ] && echo 남음 || echo 지움) C3=$([ -d "$C3" ] && echo 남음 || echo 지움) C5=$([ -d "$C5" ] && echo 남음 || echo 지움)"
  C4="$(mk gone-c4)"; MAIN="$OTHER" sc --sweep
  { [ -d "$C4" ] && ! printf '%s\n' "$OUT" | grep -q "$C4"; } && ok "ⓒ judged rc1 = 후보 0(삭제 0)" || bad "ⓒ judged rc1 후보 [$OUT]"
fi

# ── ⓓ 지우기 직전 재확인 — 주인 생김 / lsof 못 읽음 / 70초 초과 ────────────────────────
if want ⓓ; then
  : > "$TSV"; rm -f "$ARMED"
  D1="$(mk gone-d1)"; D2="$(mk gone-d2)"; age_reg "$D1" 90000; age_reg "$D2" 90000
  : > "$T/lsof.out"; cwd_rows / 1 zsh
  printf 'live-owner\ngone-d2\n' > "$T/sessions.late"
  SWAP_AT=3 sc --sweep; SWAP_AT=3 sc --sweep        # orphans tmux=1 · 재확인 D1=2 · D2=3 → late(주인 생김)
  { [ ! -d "$D1" ] && [ -d "$D2" ] && printf '%s' "$OUT" | grep -q '재확인에서 쓰는 중·주인 생김'; } \
    && ok "ⓓ 재확인에서 주인 생김 = 그 항목 삭제 0(앞 항목은 지움)" || bad "ⓓ rc=$RC [$OUT] D1=$([ -d "$D1" ] && echo 남음 || echo 지움) D2=$([ -d "$D2" ] && echo 남음 || echo 지움)"
  rm -f "$TSV"; : > "$T/lsof.out"; D3="$(mk gone-d3)"; D4="$(mk gone-d4)"; age_reg "$D3" 90000; age_reg "$D4" 90000
  cwd_rows / 1 zsh
  # r1029: 점유 조회가 사본별 1회 — 한 사본의 조회 실패는 그 사본만 «붙잡음(조회 실패)» 이고 다른 사본은 계속 판정한다
  LATE_AT=3 LATE_RC=124 sc --sweep
  { printf '%s' "$OUT" | grep -q '점유 조회 실패' && { [ -d "$D3" ] || [ -d "$D4" ]; }; } \
    && ok "ⓓ 점유 조회 실패 = 그 사본만 붙잡음(삭제 보류 · r1029 계약 · 사본별 검증은 test_scratch_sweep_per_copy_r1029)" || bad "ⓓ lsof [$OUT]" 
  # «삭제 직전 마감 초과» 계약은 ⓥ2 가 시계 대역(호출 수 실측)으로 잰다 — 여기서는 중복 측정하지 않는다(r1029 로 date 호출 수가 바뀌어 고정 번호가 못 쓴다)
fi

# ── ⓔ --done = 주인 자신 · 정확 대조 · 붙잡음/ lsof 실패 rc4 · 탭·개행 rc2 ──────────────
if want ⓔ; then
  : > "$TSV"   # 앞 케이스의 등록 줄과 섞이지 않게(«그 줄만 빠짐» 을 정확히 센다)
  E1="$(mk live-owner)"; echo b > "$G/b.txt"; git -C "$G" add b.txt; cm "$G" c2; SHA2="$(git -C "$G" rev-parse HEAD)"
  OWN=live-owner sc "$SHA2" --repo "$G"; E2="$OUT"; cwd_rows / 1 zsh
  OWN=other sc --done "$E1"
  { [ $RC = 2 ] && [ -d "$E1" ] && printf '%s' "$OUT" | grep -q '주인 아님'; } && ok "ⓔ 남의 사본 --done = rc2 · 삭제 0" || bad "ⓔ 남의 사본 rc=$RC [$OUT]"
  sc --done '.*'
  { [ $RC = 2 ] && [ -d "$E1" ] && [ -d "$E2" ] && [ "$(grep -c . "$TSV")" = 2 ]; } && ok "ⓔ --done '.*' = rc2 · 등록부 그대로(정규식 해석 0)" || bad "ⓔ rc=$RC rows=$(grep -c . "$TSV") [$OUT]"
  cwd_rows "$E1/scripts" 777 uvicorn; sc --done "$E1"
  { [ $RC = 4 ] && [ -d "$E1" ] && printf '%s' "$OUT" | grep -q '붙잡음'; } && ok "ⓔ cwd 물린 사본 --done = rc4 · 삭제 0" || bad "ⓔ 붙잡음 rc=$RC [$OUT]"
  echo 1 > "$T/lsof.rc"; sc --done "$E1"; rm -f "$T/lsof.rc"; cwd_rows / 1 zsh
  { [ $RC = 4 ] && [ -d "$E1" ]; } && ok "ⓔ lsof 실패 = rc4 · 삭제 0" || bad "ⓔ lsof rc=$RC [$OUT]"
  sc --done "$E2"
  { [ $RC = 0 ] && [ ! -d "$E2" ] && [ -d "$E1" ] && grep -q "^$E1	" "$TSV" && ! grep -q "^$E2	" "$TSV"; } \
    && ok "ⓔ 정상 --done = DONE · 그 줄만 빠짐" || bad "ⓔ 정상 rc=$RC [$OUT]"
  # r10.1 이스케이프: 등록 줄이 «\\161» 해석으로 같아지는 쌍 — awk -v 였다면 남의 줄과 맞는다
  ESC="$T/a\\161b"; EQ="$T/aqb"; mkdir -p "$ESC" "$EQ"; : > "$TSV"; reg_add "$EQ" other 60
  sc --done "$ESC"
  { [ $RC = 2 ] && [ -d "$EQ" ] && grep -q "^$EQ	" "$TSV"; } && ok "ⓔ \\161 경로 = 등록 줄 없음 rc2(이스케이프로 남의 줄과 안 맞음) · 삭제 0" || bad "ⓔ esc rc=$RC [$OUT]"
  # r10.2 불변식: 탭·개행 경로 = rc2 · 사본 생성 0
  sc --done "$T/x	y"
  { [ $RC = 2 ] && printf '%s' "$OUT" | grep -q '등록 불가 경로(탭·개행)'; } && ok "ⓔ --done 탭 경로 = rc2" || bad "ⓔ 탭 done rc=$RC [$OUT]"
  SDIR="$T/sc	rib" sc "$SHA" --repo "$G"
  { [ $RC = 2 ] && [ -z "$(ls -A "$T/sc	rib" 2>/dev/null)" ] && printf '%s' "$OUT" | grep -q '등록 불가 경로(탭·개행)'; } \
    && ok "ⓔ 생성 경로에 탭 = rc2 · 사본 0" || bad "ⓔ 탭 생성 rc=$RC [$OUT]"
fi

# ── ⓤ 빠른 길의 «못 읽음» = 빠른 길 아님 — symbolic-ref 오류(rc128)를 detached 로 읽지 않는다(DA⑥ r1 반례 1) ──
if want ⓤ; then
  : > "$TSV"; rm -f "$ARMED"; : > "$T/lsof.out"; cwd_rows / 1 zsh
  REALGIT="$(command -v git)"
  cat > "$BIN/git" <<EOF2
#!/bin/sh
for a in "\$@"; do [ "\$a" = symbolic-ref ] && exit 128; done
exec "$REALGIT" "\$@"
EOF2
  chmod 755 "$BIN/git"
  U="$(mk gone-u)"     # 새 사본 = 이름꼴·HEAD=sha8·detached·judged rc0 다 참 · 주인 gone-u 없음 → 빼면 지워진다
  sc --sweep; sc --sweep
  [ -d "$U" ] && ok "ⓤ symbolic-ref rc128 = «빠른 길 아님» · 삭제 0(24h 규칙 아래 = 후보 0)" || bad "ⓤ rc128 을 detached 로 읽고 지움 [$OUT]"
  rm -f "$BIN/git"
  sc --sweep; sc --sweep   # 대조: 같은 조건에서 symbolic-ref 정상(rc1)이면 이번엔 지운다(첫 회 = 목록 보고 · 둘째 = 삭제)
  [ ! -d "$U" ] && ok "ⓤ 대조(정상 symbolic-ref rc1) = 같은 사본은 지운다" || bad "ⓤ 대조 미상 [$OUT]"
fi

# ── ⓥ 재확인 예산 — tmux 가 늘어지면 7초 안에 끝·지우기 0 · 호출 «뒤» 마감 검사 ──
if want ⓥ; then
  : > "$TSV"; rm -f "$ARMED"; : > "$T/lsof.out"; cwd_rows / 1 zsh
  V1="$(mk gone-v1)"; age_reg "$V1" 90000
  sc --sweep                              # 첫 1회 = 목록 보고(armed)
  SECONDS=0; SLEEP_AT=2 SLEEP_SECS=8 sc --sweep; EL=$SECONDS   # 재확인 tmux=2번째 호출 — 8초 멈춤
  { [ -d "$V1" ] && [ "$EL" -le 15 ] && printf '%s' "$OUT" | grep -q '재확인 못 읽음'; } \
    && ok "ⓥ tmux 8초 멈춤 = ${EL}초에 끝남(예산 7초) · 지우기 0 + WARN" || bad "ⓥ el=${EL}s [$OUT] V1=$([ -d "$V1" ] && echo 남음 || echo 지움)"
  # ⓥ2 호출 «뒤» 마감 검사: tmux·lsof 는 빨리 끝나고 시계가 호출 직후에 마감을 넘은 상황
  rm -f "$ARMED"; : > "$TSV"
  P0="$(mk gone-v0)"; age_reg "$P0" 90000   # r5: 같은 꼴 실사본으로 «+%s» 호출 수를 잰다(마지막 = 삭제 직전 마감 검사)
  sc --sweep; DSKEW_AT=999999 sc --sweep >/dev/null 2>&1; ND="$(cat "$T/date.n" 2>/dev/null || echo 0)"
  rm -f "$TSV"; V2="$(mk gone-v2)"; age_reg "$V2" 90000
  DSKEW_AT="$ND" sc --sweep
  { [ -d "$V2" ] && printf '%s' "$OUT" | grep -q '삭제 직전 마감 초과'; } \
    && ok "ⓥ 호출 뒤 마감 초과(ND=$ND) = 그 항목 지우기 0 + WARN" || bad "ⓥ 마감 [$OUT] V2=$([ -d "$V2" ] && echo 남음 || echo 지움)"
fi

# ── ⓦ 빠른 길 호출 나무 전수 rc 검사 — 출력은 있으나 rc≠0 = «못 읽음» = 지우기 0 (DA⑥ r2 반례 1) ─────
if want ⓦ; then
  # 판정 기준 트리(ROOT=$R)에 «사본 sha8 이 적힌 옛 design 문서» 를 만든다 → judged 가 merge-base 로 끝지 못하고
  # git grep → git log 경로로 간다(ⓒ 는 ancestor 경로로 조기 종료 = 이 가지를 안 지난다)
  git -C "$G" checkout -q --orphan wbranch; echo w > "$G/w.txt"; git -C "$G" add w.txt; cm "$G" cw
  WSHA="$(git -C "$G" rev-parse HEAD)"; W8="$(printf '%.8s' "$WSHA")"; git -C "$G" checkout -q main
  git -C "$R" fetch -q origin
  mkdir -p "$R/design/w"; printf 'verdict %s\n' "$W8" > "$R/design/w/VERDICT.md"; git -C "$R" add design/w/VERDICT.md
  GIT_COMMITTER_DATE='2020-01-01T00:00:00' GIT_AUTHOR_DATE='2020-01-01T00:00:00' cm "$R" doc; WMAIN="$(git -C "$R" rev-parse HEAD)"
  # 대조: 같은 조건에서 대역이 없으면 «판정 끝» 이라 지운다(아래 지우기 0 이 «다른 이유» 가 아님을 보인다)
  : > "$TSV"; : > "$ARMED"; : > "$T/lsof.out"; cwd_rows / 1 zsh
  MAIN="$WMAIN" OWN=gone-w-ctl sc "$WSHA" --repo "$G"; CTL="$OUT"
  MAIN="$WMAIN" sc --sweep
  { [ -n "$CTL" ] && [ ! -d "$CTL" ]; } && ok "ⓦ 대조(호출 전부 rc0) = judged 끝 · 삭제" || bad "ⓦ 대조 [$OUT] CTL=$CTL"
  REALGIT="$(command -v git)"
  cat > "$BIN/git" <<EOF2
#!/bin/sh
mode=""
for a in "\$@"; do case "\$a" in
  --git-dir) mode=gitdir;; rev-parse) [ -n "\$mode" ] || mode=revparse;;
  merge-base) mode=mergebase;; grep) mode=grep;; log) mode=log;;
  symbolic-ref) mode=symbolic;; worktree) mode=worktree;; esac; done
if [ -n "\${FGIT_RC:-}" ] && [ "\$mode" = "\${FGIT_MODE:-}" ]; then
  out="\$("$REALGIT" "\$@")"; printf '%s\n' "\$out"; exit "\$FGIT_RC"
fi
exec "$REALGIT" "\$@"
EOF2
  chmod 755 "$BIN/git"
  for spec in revparse gitdir mergebase grep log; do   # 빠른 길 호출 나무의 호출마다 «출력 있음 + rc128» 1칸
    : > "$TSV"; : > "$ARMED"; : > "$SLOG"
    MAIN="$WMAIN" OWN="gone-w-$spec" sc "$WSHA" --repo "$G"; CP="$OUT"
    if [ ! -d "$CP" ]; then bad "ⓦ $spec 사본 생성 실패 [$CP]"; continue; fi
    FGIT_MODE="$spec" FGIT_RC=128 MAIN="$WMAIN" sc --sweep
    { [ -d "$CP" ] && ! grep -qF "삭제 $CP" "$SLOG"; } && ok "ⓦ $spec rc128(출력 있음) = 못 읽음 = 지우기 0" || bad "ⓦ $spec 지움 [$OUT]"
  done
  rm -f "$BIN/git"
fi

# ── ⓨ 기계 검사 — 지우는 길 함수 범위에 `$(`·백틱·파이프 0 (손 전수 표 대체 · CALLTREE 자동 생성) ─────
if want ⓨ; then
  # 지우는 길 함수 + 그 함수들이 부르는 도우미(표시 전용 kb·gib·first_paths 와 cap 자신은 밖 · cwd_parse 는 파이프 1개를 pipefail 로 rc 전달 — 아래 따로 본다)
  RANGE="delete_copy gate_rows gate_base gfail gok past_deadline phys_tmo gq fast judged main_ref orphans cwd_holder remtmo sweep_run done_run has_line has_ctl phys reg_owner row_owner tmux_sessions tmux_sessions_tmo bounded drop_reg held_report reg_list reg_rows reg_write gen_rollback ready_mark"
  body() { awk -v f="$1" '$0 ~ "^"f"\\(\\) \\{" {on=1; s=NR} on{printf "%d\t%s\n", NR, $0} on && (/^}/ || (NR==s && /;[[:space:]]*}[[:space:]]*(#.*)?$/)) {exit}' "$SUT"; }
  code() { sed -E 's/^([0-9]+\t)[[:space:]]*#.*$/\1/; s/[[:space:]]+# .*$//'; }   # 주석 줄·줄 끝 주석(« # ») 빼고 코드만
  : > "$T/range"; miss=""
  for f in $RANGE; do b="$(body "$f")"; [ -n "$b" ] || miss="$miss $f"; printf '%s\n' "$b" | sed "s/^/$f\t/" >> "$T/range"; done
  [ -z "$miss" ] && ok "ⓨ 지우는 길 함수·도우미 ${RANGE// /·} 전부 찾음" || bad "ⓨ 함수 못 찾음:$miss"
  [ "$(body cwd_parse | code | grep -c ' | ')" = 1 ] && [ "$(body cwd_parse | code | grep -cE '\$\([^(]|`')" = 0 ] && ok "ⓨ cwd_parse = 파이프 1개(pipefail 로 rc 전달 · cap 으로 받는 곳 전부 rc 검사)" || bad "ⓨ cwd_parse 꼴 바뀜"
  HITS="$(cut -f2- "$T/range" | code | grep -E '\$\([^(]|<\(|`| \| ')"
  [ -z "$HITS" ] && ok "ⓨ 범위 안 \`\$(\`·\`<(\`·백틱·파이프 = 0" || bad "ⓨ 범위 안 rc 안 보는 꼴: $(printf '%s' "$HITS" | head -3 | tr '\n' ' ')"
  # r5: 삭제 명령(rm -r · worktree remove)은 delete_copy 안에만 · r996: 생성 실패 되돌림(gen_rollback)만 예외 · 옛 삭제 함수 이름 0
  ALLC="$(awk '{printf "%d\t%s\n", NR, $0}' "$SUT" | code)"; DC="$(body delete_copy | cut -f1)"; GR="$(body gen_rollback | cut -f1)"
  OUTSIDE="$(printf '%s\n' "$ALLC" | grep -E 'rm -r|worktree remove' | while IFS="$(printf '\t')" read -r n rest; do { printf '%s\n' "$DC"; printf '%s\n' "$GR"; } | grep -qx "$n" || printf '%s\t%s\n' "$n" "$rest"; done)"
  [ -z "$OUTSIDE" ] && [ "$(printf '%s\n' "$ALLC" | grep -cE 'rm -r|worktree remove')" -gt 0 ] && ok "ⓨ 삭제 명령은 delete_copy 안에만" || bad "ⓨ delete_copy 밖 삭제 명령: $(printf '%s' "$OUTSIDE" | head -2 | tr '\n' ' ')"
  printf '%s\n' "$ALLC" | grep -qE '(^|[^_a-z])(rm_copy|recheck)([^_a-z]|$)' && bad "ⓨ 옛 삭제 함수 이름(rm_copy·recheck) 남음" || ok "ⓨ rm_copy·recheck 이름 0"
  NCAP="$(cut -f2- "$T/range" | code | grep -c 'cap ')"
  grep -q '^set -uo pipefail' "$SUT" && [ "$NCAP" -gt 0 ] && ok "ⓨ 전역 pipefail · cap 호출 ${NCAP}곳" || bad "ⓨ pipefail/cap 없음(cap=$NCAP)"
  if [ -n "${FT_CALLTREE_OUT:-}" ]; then
    { echo "# CALLTREE r897 r5 — 지우는 길(출구 게이트 delete_copy 포함) 함수의 외부 출력 받기(cap·gq) 전수 · 자동 생성(test ⓨ · 손 표 0)"; echo
      echo "| 함수 | 줄 | 코드 |"; echo "|---|---|---|"
      awk -F'\t' 'index($3, "cap ") || index($3, "gq "){c=$3; sub(/^[[:space:]]+/, "", c); gsub(/\|/, "\\|", c); printf "| %s | %s | `%s` |\n", $1, $2, c}' "$T/range"; } > "$FT_CALLTREE_OUT"
  fi
fi

# ── ⓙ r996 ①: 장부 둘(ROOT + 원 저장소) — 만들 때 양쪽에 적고, --done·--sweep 이 양쪽을 함께 읽는다 ─────
if want ⓙ; then
  : > "$TSV"; rm -f "$ARMED"; : > "$T/lsof.out"; cwd_rows / 1 zsh
  PK="$T/pack"; git clone -q "$G" "$PK" 2>/dev/null; mkdir -p "$PK/.fable-team/state"
  OTSV="$PK/.fable-team/state/scratch-repos.tsv"; : > "$OTSV"
  OWN=gone-j sc "$SHA" --repo "$PK"; J1="$OUT"
  { [ -d "$J1" ] && grep -qF "$J1	" "$TSV" && grep -qF "$J1	" "$OTSV" && [ "$(grep -c . "$OTSV")" = 1 ] && [ "$(grep -c . "$TSV")" = 1 ]; } \
    && ok "ⓙ 만들 때 두 장부에 «같은 줄» 을 적는다(ROOT + 원 저장소 · 각 1줄)" || bad "ⓙ 두 장부 [$OUT]"
  awk -F'\t' -v p="$J1" '$1!=p' "$TSV" > "$TSV.n" && mv "$TSV.n" "$TSV"   # 한쪽 장부만 남긴다(다른 루트가 만든 사본과 같은 상태)
  OWN=gone-j sc --done "$J1"
  { [ $RC = 0 ] && [ ! -d "$J1" ] && ! grep -qF "$J1	" "$OTSV"; } && ok "ⓙ ROOT 장부에 없는 사본도 원 저장소 장부로 --done(그 줄도 지움)" || bad "ⓙ done rc=$RC [$OUT]"
  : > "$TSV"
  OWN=gone-j sc "$SHA" --repo "$PK"; J2="$OUT"
  awk -F'\t' -v p="$J2" '$1!=p' "$TSV" > "$TSV.n" && mv "$TSV.n" "$TSV"
  awk -F'\t' -v p="$J2" -v t="$(( $(date +%s) - 90000 ))" 'BEGIN{OFS="\t"} $1==p{$3=t} {print}' "$OTSV" > "$OTSV.n" && mv "$OTSV.n" "$OTSV"
  sc --sweep; sc --sweep
  { [ ! -d "$J2" ] && ! grep -qF "$J2	" "$OTSV"; } && ok "ⓙ --sweep 이 ROOT 장부에 없는 사본도 원 저장소 장부로 보고 지운다" || bad "ⓙ sweep [$OUT] J2=$([ -d "$J2" ] && echo 남음 || echo 지움)"
  : > "$TSV"
  OWN=gone-j sc "$SHA" --repo "$PK"; J3="$OUT"
  for f in "$TSV" "$OTSV"; do awk -F'\t' -v p="$J3" -v t="$(( $(date +%s) - 90000 ))" 'BEGIN{OFS="\t"} $1==p{$3=t} {print}' "$f" > "$f.n" && mv "$f.n" "$f"; done
  sc --sweep; sc --sweep; sc --sweep
  { [ ! -d "$J3" ] && ! grep -qF "$J3	" "$TSV" && ! grep -qF "$J3	" "$OTSV"; } && ok "ⓙ 두 장부에 같은 줄 = 한 번만 지우고 양쪽 줄 모두 정리" || bad "ⓙ 중복 [$OUT]"
fi

# ── ⓚ r996 ②: 판정 2720 입구 — 판정 끝 ∧ 주인 없음 = 24시간 없이 지움(첫 1회 목록만 · 게이트 경유) ──
if want ⓚ; then
  : > "$TSV"; rm -f "$ARMED"; : > "$T/lsof.out"; cwd_rows / 1 zsh
  K1="$(mk gone-k1)"
  sc --sweep
  { [ -d "$K1" ] && printf '%s' "$OUT" | grep -q '목록 보고'; } && ok "ⓚ 판정 끝+주인 없음(1분 된 사본) = 첫 회는 목록만(실삭제 0)" || bad "ⓚ 첫회 [$OUT]"
  sc --sweep
  { [ ! -d "$K1" ] && grep -q 'judged' "$SLOG"; } && ok "ⓚ 둘째 회 = 24시간 기다리지 않고 삭제(사유 judged)" || bad "ⓚ 둘째 [$OUT] K1=$([ -d "$K1" ] && echo 남음 || echo 지움)"
  K2="$(mk live-owner)"; sc --sweep; sc --sweep
  { [ -d "$K2" ]; } && ok "ⓚ 주인 세션 살아 있음 = 판정 끝이어도 삭제 0" || bad "ⓚ 주인 있음 [$OUT]"
  BAD=1111111111111111111111111111111111111111
  K3="$(mk gone-k3)"; MAIN="$BAD" sc --sweep; MAIN="$BAD" sc --sweep
  { [ -d "$K3" ]; } && ok "ⓚ 판정 안 끝남 + 1분 = 삭제 0(24시간 기다림)" || bad "ⓚ 판정 안끝 [$OUT]"
  K4="$(mk gone-k4)"; printf '%s\n' "$SHA" > "$K4/.scratch-judged"
  MAIN="$BAD" sc --sweep; MAIN="$BAD" sc --sweep
  { [ ! -d "$K4" ]; } && ok "ⓚ 사본 안 .scratch-judged 표식 = 판정 끝으로 읽어 24시간 없이 지움" || bad "ⓚ 표식 [$OUT]"
  K5="$(mk gone-k5)"; rm -f "$STATE/scratch-ready/${K5##*/}"
  sc --sweep; sc --sweep
  { [ -d "$K5" ]; } && ok "ⓚ 완성 표식 없는 사본 = 24시간 없이 지우기 0" || bad "ⓚ 완성 표식 없이 지움 [$OUT]"
fi

# ── ⓛ r996 ③ ⓗ: 선등록 안전 — «이번 실행이 만든 폴더만» 되돌림 · rm 실패 = 등록 유지 · 재사용은 완성 표식만 ──
if want ⓛ; then
  : > "$TSV"; rm -f "$ARMED"; : > "$T/lsof.out"; cwd_rows / 1 zsh
  BIN2="$T/bin2"; mkdir -p "$BIN2"; cp "$BIN/tmux" "$BIN/lsof" "$BIN2/"
  # 있던 폴더 재현: 같은 pid 로 exec 해 DEST 를 미리 만든다(고정 시각 대역 → 이름 예측 가능)
  cat > "$BIN2/date" <<'EOD'
#!/bin/sh
[ "$1" = +%s ] && { echo 1700000000; exit 0; }
exec /bin/date "$@"
EOD
  cat > "$BIN2/git" <<EOD
#!/bin/sh
for a in "\$@"; do [ "\$a" = add ] && exit 1; done
exec $(command -v git) "\$@"
EOD
  chmod 755 "$BIN2/date" "$BIN2/git"
  D8="$(printf '%.8s' "$SHA")"
  OUT="$(env PATH="$BIN2:$PATH" FT_RES_ROOT="$R" FT_SCRATCH_DIR="$SCR" TMPDIR="$TMPD" FT_SCRATCH_OWNER=live-owner \
    bash -c 'd="$2/repo-'"$D8"'-1700000000-$$"; mkdir -p "$d"; echo keep > "$d/own.txt"; printf "%s\n" "$d" > "$3"; exec bash "$1" "$4" --repo "$5"' \
    _ "$SUT" "$SCR" "$T/dest.txt" "$SHA" "$G" 2>&1)"; RC=$?; PD="$(cat "$T/dest.txt")"
  { [ $RC = 4 ] && [ -d "$PD" ] && [ -f "$PD/own.txt" ] && ! grep -qF "$PD	" "$TSV"; } \
    && ok "ⓛ 있던 폴더(생성 예정 경로) = 되돌림이 지우지 않는다(rm 0 · 등록 줄도 안 남김)" || bad "ⓛ 있던 폴더 rc=$RC PD=$PD [$OUT]"
  # rm 실패 = 등록 유지: worktree add 는 되고 sparse 가 실패 · 지우기도 실패하는 대역
  cat > "$BIN2/git" <<EOD
#!/bin/sh
prev=""
for a in "\$@"; do
  [ "\$prev" = worktree ] && [ "\$a" != add ] && exit 1
  [ "\$a" = sparse-checkout ] && exit 1
  prev="\$a"
done
exec $(command -v git) "\$@"
EOD
  cat > "$BIN2/rm" <<'EOD'
#!/bin/sh
exit 1
EOD
  chmod 755 "$BIN2/git" "$BIN2/rm"
  OUT="$(env PATH="$BIN2:$PATH" FT_RES_ROOT="$R" FT_SCRATCH_DIR="$SCR" TMPDIR="$TMPD" FT_SCRATCH_OWNER=live-owner bash "$SUT" "$SHA" --repo "$G" 2>&1)"; RC=$?
  LR="$(awk -F'\t' '$2=="live-owner"{print $1}' "$TSV" 2>/dev/null | tail -1)"
  { [ $RC = 4 ] && [ -d "$LR" ] && ! ready "$LR" && grep -qF "$LR	" "$TSV" && printf '%s' "$OUT" | grep -q '되돌림 실패' && printf '%s' "$OUT" | grep -q '등록 유지'; } \
    && ok "ⓛ rm 실패 = 사본이 남으면 등록 유지 + ERROR(완성 표식 없음)" || bad "ⓛ rm 실패 rc=$RC LR=$LR [$OUT]"
  rm -f "$BIN2/rm" "$BIN2/git" "$BIN2/date"; : > "$TSV"
  R1="$(mk gone-reuse)"
  { ready "$R1"; } && ok "ⓛ 만들기 끝난 사본 = 완성 표식(scratch-ready) 있음" || bad "ⓛ 완성 표식 없음 $R1"
  rm -f "$STATE/scratch-ready/${R1##*/}"
  R2="$(mk gone-reuse)"
  { [ -n "$R2" ] && [ -d "$R2" ] && [ "$R2" != "$R1" ]; } && ok "ⓛ 완성 표식 없는 사본(미완성·끊긴)은 재사용 0" || bad "ⓛ 미완성 재사용 [$OUT] R2=$R2 R1=$R1"
  R3="$(mk gone-reuse)"
  { [ "$R3" = "$R2" ]; } && ok "ⓛ 완성 표식 있는 같은 sha·같은 주인 = 재사용" || bad "ⓛ 재사용 [$OUT] R3=$R3 R2=$R2"
fi

if want ⓕ; then
  for t in test_scratch_repo.sh test_scratch_judged_r645.sh test_scratch_sweep_live_cwd_r548.sh test_scratch_repo_sparse_auto_done_r891.sh test_scratch_repo_register_on_hook_fail_r845.sh test_scratch_exit_gate_r897.sh; do
    ( cd "$HERE" && bash "./$t" ) > "$T/$t.log" 2>&1; r=$?
    { [ "$r" = 0 ] && grep -q '^ALL PASS' "$T/$t.log"; } && ok "ⓕ 기존 $t = ALL PASS" || bad "ⓕ 기존 $t rc=$r ($(grep -c '^FAIL' "$T/$t.log") FAIL)"
  done
  cmp -s "$REPO/bin/ft-scratch-repo.sh" "$REPO/kit/fable-team/bin/ft-scratch-repo.sh" \
    && ok "ⓕ kit 짝 사본 cmp0" || bad "ⓕ kit 짝 다름"
fi

# ── 변이 5: 하나를 없애면 그 케이스가 빨강이 되는가(변이도 «덜 지우는 쪽» 이 아니라 «더 지우는 쪽») ──
if want M; then
  mut() { # <이름> <sed 식> <케이스> <기대 FAIL 칸 정규식> — r10.5: FAIL 이 전부 «기대한 칸» 일 때만 검출(사본 생성 실패 같은 다른 FAIL = 검출 아님 · DA⑥ r3 반례 4)
    local m="$T/mut-$1.sh" nf nx
    sed "$2" "$SUT" > "$m"
    cmp -s "$SUT" "$m" && { bad "변이 $1 이 안 바뀜"; return; }
    bash -n "$m" 2>/dev/null || { bad "변이 $1 문법 깨짐(가짜 변이)"; return; }
    FT_MUT_CHILD=1 FT_SUT="$m" FT_CASES="$3" bash "${BASH_SOURCE[0]}" > "$T/mut-$1.log" 2>&1; r=$?
    nf="$(grep -c '^FAIL' "$T/mut-$1.log")"; nx="$(grep -cE "^FAIL $4" "$T/mut-$1.log")"
    { [ "$r" != 0 ] && [ "$nf" -gt 0 ] && [ "$nf" = "$nx" ]; } && ok "변이 $1 → $3 기대 칸만 빨강($4 · ${nf}칸)" \
      || bad "변이 $1 이 기대 칸으로 안 잡힘(rc=$r · FAIL $nf · 기대 칸 $nx) $(grep '^FAIL' "$T/mut-$1.log" | head -2 | tr '\n' ' ')"
  }
  mut 1-pwd 's#pwd -P#pwd#' V0 'V0 '
  mut 2-hasline 's#^has_line() {.*#has_line() { return 1; }#' 'ⓑ' 'ⓑ '
  # 변이 3-symbolic·6-rc128(빠른 길 ③ detached 검사)은 r5 에서 뺐다 — 출구 게이트 G7 이 같은 조건을 다시 재서 «그 조건 하나만» 거짓인 입력을 만들 수 없다(고침 11) · 삭제 쪽 증거 = 게이트 시험 변이 g7-detached
  mut 4-gate-owner 's#has_line "\$S" "\$own" \&\& { gfail G6 1#false \&\& { gfail G6 1#' 'ⓓ' 'ⓓ '
  mut 5-owner 's#\[ "\$REG_OWN" = "\$ME" \] || die "주인 아님.*#:#' 'ⓔ' 'ⓔ '   # 첫 칸이 남의 사본을 지우면 뒤 ⓔ 칸이 연쇄로 빨강 — ⓔ 밖 FAIL 은 검출 아님
  mut 7-overbudget 's#^  \[ \$(( now - RBUD )) -gt 0 \]#  return 1#' 'ⓥ' 'ⓥ 마감'
  mut 8-tmo 's#cap S tmux_sessions_tmo "\$r"#cap S tmux_sessions#' 'ⓥ' 'ⓥ el='
  # r10.5 변이: «rc 검사 하나 지우기»(문법 유지) → 그 주입 칸만 빨강(다른 FAIL 섞이면 검출 아님)
  mut 9-mergebase 's#  case "\$rc" in 0) return 0;; 1) ;; \*) echo "WARN ft-scratch-repo judged — merge-base 실패.*#  case "$rc" in 0) return 0;; esac#' 'ⓦ' 'ⓦ mergebase'
  mut 10-logrc 's#\[ "\$rc" = 0 \] || { echo "WARN ft-scratch-repo judged — git log 실패.*#:#' 'ⓦ' 'ⓦ log'
  mut 16-subst 's#^  h="\${BASH_REMATCH\[1\]}"#  h="$(printf %s "${BASH_REMATCH[1]}")"#' 'ⓨ' 'ⓨ 범위 안'
  # r996 변이: 장부 둘·선등록 안전·완성 표식 — 각각의 시험 칸이 빨강이 되는가
  mut 17-dualreg 's#^    for p in "${b%/}"/repo-\*; do#    for p in /nonexistent; do#' 'ⓙ' 'ⓙ ' 
  mut 18-pre 's#^  if \[ "\$PRE" = 0 \]; then#  if true; then#' 'ⓛ' 'ⓛ ' 
  mut 19-ready 's#^  ready_mark "\$p" || return 1#  :#' 'ⓚ' 'ⓚ ' 
fi

[ $fail -eq 0 ] && echo "ALL PASS" || echo "($fail failed)"
exit $fail
