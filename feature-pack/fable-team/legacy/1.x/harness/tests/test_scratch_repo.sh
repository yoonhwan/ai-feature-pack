#!/usr/bin/env bash
# test_scratch_repo.sh — ft-scratch-repo.sh (R246): 등록형 저장소 사본(git worktree --detach) · --done 정리 · --report 주인 없는 사본.
# 임시 git 저장소·가짜 tmux·임시 TMPDIR 만 쓴다 — 실 저장소·실 세션·실 TMPDIR 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"
SUT="${FT_SUT:-$REPO/harness/bin/ft-scratch-repo.sh}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
[ -f "$SUT" ] || { bad "ft-scratch-repo.sh 없음"; echo "(1 failed)"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
G="$T/src"; R="$T/R"; SCR="$T/scratch"; TMPD="$T/tmpdir"; mkdir -p "$G" "$R/.fable-team/state" "$SCR" "$TMPD" "$T/bin"
git -C "$G" init -q && echo a > "$G/a.txt" && git -C "$G" add a.txt && git -C "$G" -c user.name=t -c user.email=t@t commit -q -m c1
SHA="$(git -C "$G" rev-parse HEAD)"
printf '#!/bin/sh\n[ -f "%s/tmuxfail" ] && { echo "no server running" >&2; exit 1; }\n[ "$1" = list-sessions ] && cat "%s/sessions" 2>/dev/null\nexit 0\n' "$T" "$T" > "$T/bin/tmux"; chmod 755 "$T/bin/tmux"
printf 'live-owner\n' > "$T/sessions"
sc() { OUT="$(env PATH="${GPRE:+$GPRE:}$T/gbin:$T/bin:$PATH" FT_RES_ROOT="$R" FT_SCRATCH_DIR="$SCR" TMPDIR="$TMPD" FT_SCRATCH_OWNER="${OWN:-live-owner}" \
  FT_SCRATCH_KEEP_DIRTY="${KEEP_ON:-}" FT_SCRATCH_KEEP_MAX_MB="${KEEP_MAX:-}" \
  GS_AT="${GS_AT:-0}" GS_FAIL="${GS_FAIL:-}" GS_SLEEP="${GS_SLEEP:-}" GS_DIRTY="${GS_DIRTY:-}" \
  GT_AT="${GT_AT:-0}" GT_DIRTY="${GT_DIRTY:-}" GT_TAR_EXTRA="${GT_TAR_EXTRA:-}" GT_LS_SLEEP="${GT_LS_SLEEP:-}" bash "$SUT" "$@" 2>&1)"; RC=$?; }
TSV="$R/.fable-team/state/scratch-repos.tsv"
age_reg() { awk -F'\t' -v p="$1" -v t="$(( $(date +%s) - $2 ))" 'BEGIN{OFS="\t"} $1==p{$3=t} {print}' "$TSV" > "$TSV.n" && mv "$TSV.n" "$TSV"; }   # 등록 시각을 <초> 전으로

sc "$SHA" --repo "$G"; P="$OUT"
{ [ $RC = 0 ] && [ -f "$P/a.txt" ] && [ "$(dirname "$P")" = "$SCR" ] && grep -q "^$P	live-owner	" "$TSV"; } \
  && ok "ⓐ 사본 생성(detach worktree) · 경로 출력 · 등록 줄(경로·주인·시각)" || bad "ⓐ rc=$RC out=$OUT tsv=$(cat "$TSV" 2>/dev/null)"
[ "$(git -C "$P" rev-parse HEAD)" = "$SHA" ] && ok "ⓐ 요청한 sha 그대로" || bad "ⓐ sha 불일치"
sc --report;            { [ $RC = 0 ] && ! echo "$OUT" | grep -q "$P"; } && ok "ⓑ 주인 세션 살아 있으면 보고 대상 아님" || bad "ⓑ $OUT"
OWN=gone-owner sc "$SHA" --repo "$G"; P2="$OUT"; age_reg "$P2" 90000
sc --report;            { echo "$OUT" | grep -q "$P2" && ! echo "$OUT" | grep -q "$P	"; } && ok "ⓒ 주인 세션 없는 사본만 보고" || bad "ⓒ $OUT"
sc --report --summary;  echo "$OUT" | grep -q '^주인 없는 임시 사본 1개 ' && ok "ⓓ --summary 한 줄" || bad "ⓓ [$OUT]"
mkdir -p "$TMPD/tmp.old1" "$TMPD/tmp.new1"; echo x > "$TMPD/tmp.old1/f"; touch -t 202001010000 "$TMPD/tmp.old1"
sc --report;            { echo "$OUT" | grep -q 'tmp.old1' && ! echo "$OUT" | grep -q 'tmp.new1'; } && ok "ⓔ TMPDIR tmp.* 는 24h 지난 것만" || bad "ⓔ $OUT"
sc --report --summary;  echo "$OUT" | grep -q '^주인 없는 임시 사본 2개 ' && ok "ⓔ 요약에 합산(2개)" || bad "ⓔ [$OUT]"
[ -d "$TMPD/tmp.old1" ] && [ -d "$P2" ] && ok "ⓕ --report 는 삭제 0" || bad "ⓕ 삭제됨"
sc --done "$P";         { [ $RC = 0 ] && [ ! -d "$P" ] && ! grep -q "^$P	" "$TSV"; } && ok "ⓖ --done = worktree 제거 + 등록 줄 삭제" || bad "ⓖ rc=$RC $OUT"
git -C "$G" worktree list | grep -q "$P" && bad "ⓖ git worktree 목록에 남음" || ok "ⓖ git worktree 목록에서도 제거"
sc --done "$G";         { [ $RC != 0 ] && [ -d "$G" ]; } && ok "ⓗ 등록 안 된 경로는 --done 거부" || bad "ⓗ rc=$RC"
rm -f "$TSV"; sc --report; echo "$OUT" | grep -q 'No such file' && bad "ⓙ 등록 파일 없을 때 --report 에러" || ok "ⓙ 등록 파일 없어도 --report 정상"
# --sweep (판정 1920): 첫 1회 = 목록 보고만(실삭제 0) · 그 뒤부터 자동 삭제 · 주인 있는 사본·24h 안 tmp.* 는 건드리지 않는다
sc "$SHA" --repo "$G"; L="$OUT"; OWN=gone-owner sc "$SHA" --repo "$G"; D1="$OUT"; age_reg "$D1" 90000
mkdir -p "$TMPD/tmp.old2"; echo y > "$TMPD/tmp.old2/f"; touch -t 202001010000 "$TMPD/tmp.old2"
sc --sweep
{ [ $RC = 0 ] && echo "$OUT" | grep -q '목록 보고' && echo "$OUT" | grep -q '실삭제 0' && [ -d "$D1" ] && [ -d "$TMPD/tmp.old1" ] && [ -d "$TMPD/tmp.old2" ]; } \
  && ok "ⓚ 첫 --sweep = 목록 보고만 · 실삭제 0" || bad "ⓚ rc=$RC out=$OUT"
sc --sweep
{ [ $RC = 0 ] && echo "$OUT" | grep -q '자동 삭제' && [ ! -d "$D1" ] && [ ! -d "$TMPD/tmp.old1" ] && [ ! -d "$TMPD/tmp.old2" ]; } \
  && ok "ⓛ 둘째 --sweep = 주인 없는 사본·24h 지난 tmp.* 삭제" || bad "ⓛ rc=$RC out=$OUT"
{ [ -d "$L" ] && [ -d "$TMPD/tmp.new1" ]; } && ok "ⓜ 주인 살아 있는 사본·새 tmp.* 는 남음" || bad "ⓜ 지워짐"
git -C "$G" worktree list | grep -q "$D1" && bad "ⓛ worktree 목록에 남음" || ok "ⓛ git worktree 목록에서도 제거"
sc --sweep; { printf '%s\n' "$OUT" | grep -q '^swept=0 owner-dead=0 tmp=0 ' && [ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = 1 ]; } && ok "ⓝ 지울 것 없으면 끝 줄 1줄만(R8 · r1090 DA②)" || bad "ⓝ [$OUT]"
# DA⑥ HOLD3: ①tmux 목록 실패 ≠ 세션 0 ②주인 '-' 등록 거부 · ③(r444) 등록 사본은 나이 문턱 0 — 주인이 죽으면 즉시 후보
OWN=gone-owner sc "$SHA" --repo "$G"; Y="$OUT"; age_reg "$Y" 90000
sc --report; echo "$OUT" | grep -q "$Y" && ok "ⓞ 주인 없음+등록 25시간 → 후보(판정 1920 · r548 이 r444 문턱 0 을 되돌림)" || bad "ⓞ 주인 없음 25시간 후보 아님 $OUT"
touch "$T/tmuxfail"; sc --report
{ ! echo "$OUT" | grep -q "$Y" && echo "$OUT" | grep -q 'ERROR tmux 목록 실패 — 등록 사본 판정 생략'; } && ok "ⓟ tmux 목록 실패 → 등록 사본 후보 0 + ERROR" || bad "ⓟ $OUT"
mkdir -p "$TMPD/tmp.old3"; touch -t 202001010000 "$TMPD/tmp.old3"; sc --report; echo "$OUT" | grep -q 'tmp.old3' && ok "ⓟ tmux 실패여도 tmp.* 판정은 계속" || bad "ⓟ tmp.* 판정 중단 $OUT"
sc --sweep; { [ -d "$Y" ] && [ -d "$TMPD/tmp.old3" ] && echo "$OUT" | grep -q '^ERROR tmux unreadable'; } && ok "ⓟ tmux 실패 중 --sweep = ERROR 1줄(stdout) + 삭제 0(tmp.* 포함 · r444)" || bad "ⓟ sweep tmux 실패 [$OUT]"
rm -f "$T/tmuxfail"
before="$(git -C "$G" worktree list | wc -l)"; OWN=- sc "$SHA" --repo "$G"
{ [ $RC != 0 ] && [ "$(git -C "$G" worktree list | wc -l)" = "$before" ] && echo "$OUT" | grep -q '주인'; } && ok "ⓠ 주인 '-' → 등록 거부 rc≠0 · worktree 0" || bad "ⓠ rc=$RC out=$OUT"
sc "nosuchref" --repo "$G"; [ $RC != 0 ] && ok "ⓘ 없는 ref → 실패 rc≠0(조용한 성공 0)" || bad "ⓘ rc=$RC"

# ── r1085: 사본 안에서 만든 «가지 사본» — 깨끗할 때만 지운다 · 더러우면 지금처럼 거절 · 가지 ref 는 남긴다 ──────
#   ⓐ 깨끗한 가지 사본 삭제·ref 남김(R1) ⓑ 더러움 거절(R2·R3) ⓒ detached 길 불변(R4) ⓓ status 못 읽음(R5 · G7·G8 두 자리)
#   ⓔ 지우기 직전 더러워짐 = G8 거절(R6) ⓕ 주인 살아 있음(R7) ⓖ bin·kit 같은 내용 · 변이 3종(FT_CASES=M)
want() { case "${FT_CELLS:-all}" in all) return 0;; *"$1"*) return 0;; esac; return 1; }
if want r1085; then
  ARM="$R/.fable-team/state/scratch-sweep.armed"
  GITBIN="$(command -v git)"; mkdir -p "$T/gbin"
  # 가짜 git: «깨끗함 검사 --untracked-files=normal» 호출만 N번째를 실패·지연·늦은 수정으로 바꾼다(나머지는 진짜 git 그대로) — 사본 생성 때의 status 호출과 섞이지 않게 이 자국만 센다
  cat > "$T/gbin/git" <<EOF
#!/bin/sh
case "\$*" in
  *"--untracked-files=normal"*)
    n=\$(( \$(/bin/cat "$T/gs.n" 2>/dev/null || echo 0) + 1 )); echo "\$n" > "$T/gs.n"
    if [ "\$n" = "\${GS_AT:-0}" ]; then
      p=""; prev=""; for a in "\$@"; do [ "\$prev" = -C ] && p="\$a"; prev="\$a"; done
      [ -z "\${GS_DIRTY:-}" ] || { [ -n "\$p" ] && printf 'late\\n' > "\$p/\${GS_DIRTY}"; }
      [ -z "\${GS_FAIL:-}" ] || exit "\$GS_FAIL"
      [ -z "\${GS_SLEEP:-}" ] || sleep "\$GS_SLEEP"
    fi;;
esac
exec "$GITBIN" "\$@"
EOF
  chmod 755 "$T/gbin/git"
  arm() { mkdir -p "$R/.fable-team/state"; date +%s > "$ARM"; }   # 실삭제 단계로(첫 sweep 의 목록 보고만 건너뜀)
  gsrst() { rm -f "$T/gs.n"; }   # 주입 호출 번호를 0 에서 시작
  drop_tr() { awk -F'\t' -v p="$1" '$1!=p' "$TSV" > "$TSV.n" && mv "$TSV.n" "$TSV"; }
  brreg() { # <주인> <가지 이름> → 사본 경로 · 사본 안에서 가지를 만들고 등록 시각을 25시간 전으로
    OWN="$1" sc "$SHA" --repo "$G"; local p="$OUT"
    git -C "$p" checkout -q -b "$2" >/dev/null 2>&1
    age_reg "$p" 90000; printf '%s' "$p"; }
  # ⓐ R1: 깨끗한 가지 사본 = 삭제 · 가지 ref 남음 · 등록 줄 삭제
  BA="$(brreg gone-ba brAlpha)"; arm; sc --sweep
  { [ $RC = 0 ] && [ -n "$BA" ] && [ ! -d "$BA" ] && git -C "$G" show-ref --verify --quiet refs/heads/brAlpha && ! grep -qF "$BA" "$TSV"; } \
    && ok "r1085-ⓐ 깨끗한 가지 사본 = 삭제 · 가지 ref 그대로 · 등록 줄 삭제" || bad "r1085-ⓐ rc=$RC out=$OUT 남음=$([ -d "$BA" ] && echo y) ref=$(git -C "$G" show-ref refs/heads/brAlpha 2>&1)"
  # ⓑ R2·R3: 추적 파일 1줄 수정 / 추적 안 한 새 파일 = 거절(G7 가지 사본 더러움) · 폴더·등록 줄 그대로
  BB="$(brreg gone-bb brBeta)"; arm; printf 'z\n' >> "$BB/a.txt"
  sc --sweep
  { [ -d "$BB" ] && grep -qF "$BB" "$TSV" && printf '%s' "$OUT" | grep -q '가지 사본 더러움'; } \
    && ok "r1085-ⓑ 추적 파일 수정 = 거절 · 폴더·등록 줄 그대로" || bad "r1085-ⓑ rc=$RC [$OUT]"
  BB2="$(brreg gone-bb2 brBeta2)"; arm; printf 'u\n' > "$BB2/new.txt"
  sc --sweep
  { [ -d "$BB2" ] && printf '%s' "$OUT" | grep -q '가지 사본 더러움'; } \
    && ok "r1085-ⓑ 추적 안 한 새 파일 = 거절" || bad "r1085-ⓑ2 rc=$RC [$OUT]"
  drop_tr "$BB"; drop_tr "$BB2"; rm -rf "$BB" "$BB2"
  # ⓒ R4: detached 길 불변
  OWN=gone-bc sc "$SHA" --repo "$G"; BC="$OUT"; age_reg "$BC" 90000; arm; sc --sweep
  { [ ! -d "$BC" ] && ! grep -qF "$BC" "$TSV"; } && ok "r1085-ⓒ detached 사본 = 지금처럼 삭제" || bad "r1085-ⓒ rc=$RC [$OUT]"
  # ⓓ R5: status 못 읽음 = rc2 · 삭제 0 (G7 자리 / G8 자리)
  BD="$(brreg gone-bd brDelta)"; arm; gsrst; GS_AT=1 GS_FAIL=128 sc --sweep
  { [ $RC = 0 ] && [ -d "$BD" ] && printf '%s' "$OUT" | grep -q 'G7 status 못 읽음'; } \
    && ok "r1085-ⓓ status 못 읽음(G7 자리) = 거절 rc2 · 삭제 0" || bad "r1085-ⓓ1 rc=$RC [$OUT]"
  arm; gsrst; GS_AT=2 GS_FAIL=128 sc --sweep
  { [ -d "$BD" ] && printf '%s' "$OUT" | grep -q '삭제 직전 status 못 읽음'; } \
    && ok "r1085-ⓓ status 못 읽음(G8 자리) = 거절 rc2 · 삭제 0" || bad "r1085-ⓓ2 rc=$RC [$OUT]"
  # ⓔ R6: G7 통과 뒤 · 지우기 직전 더러워짐 = G8 거절 · 삭제 0
  arm; gsrst; GS_AT=2 GS_DIRTY=late.txt sc --sweep
  { [ -d "$BD" ] && printf '%s' "$OUT" | grep -q '삭제 직전 가지 사본 더러움'; } \
    && ok "r1085-ⓔ 지우기 직전 더러워짐 = G8 거절 · 삭제 0" || bad "r1085-ⓔ rc=$RC [$OUT]"
  drop_tr "$BD"; rm -rf "$BD"
  # ⓕ R7: 주인 세션 살아 있음 = G6 거절(가지 판정까지 안 감)
  BF="$(brreg live-owner brZeta)"
  sc --sweep; { [ -d "$BF" ] && grep -qF "$BF" "$TSV"; } && ok "r1085-ⓕ 주인 살아 있음 = 삭제 0" || bad "r1085-ⓕ rc=$RC [$OUT]"
  rm -rf "$BF"; drop_tr "$BF"
  # ⓖ bin·kit 같은 내용
  cmp -s "$REPO/harness/bin/ft-scratch-repo.sh" "$REPO/harness/kit/fable-team/bin/ft-scratch-repo.sh" \
    && ok "r1085-ⓖ bin·kit 같은 내용(cmp0)" || bad "r1085-ⓖ bin·kit 다름"
  # 변이 3종 — 조건 하나만 끄는 패치로 기대 칸만 빨강일 때만 검출(FT_CASES=M 일 때만 돈다)
  if [ "${FT_CASES:-all}" = M ]; then
    mut() { # <이름> <sed 식> <기대 FAIL 정규식> — FT_MUTS 를 주면 그 이름만 돈다(시험 1개 70초 · 하드 룰 22)
      case "${FT_MUTS:-}" in ''|*"$1"*) ;; *) return 0;; esac
      local m="$T/mut-$1.sh" nf nx r
      sed "$2" "$SUT" > "$m"
      cmp -s "$SUT" "$m" && { bad "변이 $1 이 안 바뀜"; return; }
      bash -n "$m" 2>/dev/null || { bad "변이 $1 문법 깨짐(가짜 변이)"; return; }
      FT_MUT_CHILD=1 FT_CELLS=r1085 FT_CASES=none FT_SUT="$m" bash "${BASH_SOURCE[0]}" > "$T/mut-$1.log" 2>&1; r=$?
      nf="$(grep -c '^FAIL' "$T/mut-$1.log")"; nx="$(grep -cE "^FAIL ($3)" "$T/mut-$1.log")"
      { [ "$r" != 0 ] && [ "$nf" -gt 0 ] && [ "$nf" = "$nx" ]; } && ok "변이2 $1 → 기대 칸만 빨강($3 · ${nf}칸)" \
        || bad "변이 $1 이 기대 칸으로 안 잡힘(rc=$r · FAIL $nf · 기대 $nx) $(grep '^FAIL' "$T/mut-$1.log" | head -2 | tr '\n' ' ')"
    }
    mut clean-off 's#\[ "\$ST" = 0 \] || { gfail G7 3#: || { gfail G7 3#;s#\[ "\$ST" = 0 \] || { gfail G8 3#: || { gfail G8 3#' 'r1085-ⓑ|r1085-ⓔ'
    mut g8-off 's#^      \[ "\$ST" = 0 \] || { gfail G8 3#      : || { gfail G8 3#' 'r1085-ⓔ'
    mut newpath-off 's#^      0) cap r remtmo; \[ "\$r" -gt 0 \] || { gfail G7 2 "예산 소진"; return; }#      0) gfail G7 3 "가지 워크트리(detached 아님)"; return;#' 'r1085-ⓐ|r1085-ⓑ|r1085-ⓓ|r1085-ⓔ'
  fi
fi


[ $fail -eq 0 ] && echo "ALL PASS" || echo "($fail failed)"
exit $fail
