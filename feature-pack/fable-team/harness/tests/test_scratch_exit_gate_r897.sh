#!/usr/bin/env bash
# test_scratch_exit_gate_r897.sh — r897 r5: ft-scratch-repo.sh 의 «출구 게이트» delete_copy (DESIGN-r897-exit-gate-r5 + DECISION-r897-design-final 고침 11)
#   공통: 모든 칸 끝에 neighbors_alive — 이웃 8(무관 폴더 2 · 살아 있는 주인 사본 · 젊은 사본 · 가지 워크트리 사본 · 젊은 tmp · 베이스 2 · ROOT · 홈 꼴) 전부 그대로
#   Ⓖ --gate 직접(조건 하나씩 깸) · Ⓝ 정상 길 · Ⓑ du 실패 = 표시만 · Ⓓ 중복 등록 · Ⓔ 하위 폴더·이름꼴 · Ⓕ 가지 워크트리 · Ⓗ tmp(git·남의 uid·젊음) · Ⓘ --done · Ⓚ 고침 2·5·7·8(게이트 자기 lsof · inode 다름 · 옛 3칸 줄 · bare 원 저장소)
#   ⓧ 주입 전수: 지우는 길의 외부 명령(git·date·awk·tmux·lsof·cat·stat·pwd · tmp 는 id·find·mv·rm 까지) 호출 자리마다 «N번째만» × «진짜 출력/빈 출력 + rc128» = 삭제 0 ∧ 이웃 생존
#      · 삭제 명령(worktree remove·rm) 은 «호출 전 실패»(진짜 안 부름) = 폴더 생존·ERROR·다음 sweep 삭제 1 · «실행 뒤 실패» = ERROR·등록 줄 유지 · du = 표시만(삭제 판단 불변)
#   변이: 조건 하나만 막는 입력으로(고침 11) — FAIL 이 전부 기대 칸일 때만 검출
# 임시 git 저장소·가짜 tmux/lsof·주입 대역·임시 TMPDIR 만 쓴다 — 실 저장소·실 세션·실 삭제 0(임시 폴더 안만).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/.." && pwd)"
SUT="${FT_SUT:-$REPO/bin/ft-scratch-repo.sh}"
CASES="${FT_CASES:-all}"; XONLY="${FT_XONLY:-}"   # FT_XONLY = ⓧ 칸 이름 정규식(변이 시험이 기대 칸만 돌린다)
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
want() { case "$CASES" in all) return 0;; *"$1"*) return 0;; esac; return 1; }
[ -f "$SUT" ] || { bad "ft-scratch-repo.sh 없음 ($SUT)"; echo "(1 failed)"; exit 1; }

T="$(mktemp -d)"; trap 'chmod -R u+rwX "$T" 2>/dev/null; rm -rf "$T"' EXIT
G="$T/src"; R="$T/R"; SCR="$T/scratch"; TMPD="$T/tmpdir"; BIN="$T/bin"; IBIN="$T/ibin"; HOMEX="$T/home"
mkdir -p "$G" "$SCR" "$TMPD" "$BIN" "$IBIN" "$HOMEX"
cm() { git -C "$1" -c user.name=t -c user.email=t@t commit -q -m "$2"; }
git -C "$G" init -q -b main && echo a > "$G/a.txt" && git -C "$G" add a.txt && cm "$G" c1
SHA="$(git -C "$G" rev-parse HEAD)"
git -C "$G" checkout -q --orphan ybranch; echo y > "$G/y.txt"; git -C "$G" add y.txt; cm "$G" cy; YSHA="$(git -C "$G" rev-parse HEAD)"
git -C "$G" checkout -q --orphan xbranch; echo x > "$G/x.txt"; git -C "$G" add x.txt; cm "$G" cx; XSHA="$(git -C "$G" rev-parse HEAD)"; X8="$(printf '%.8s' "$XSHA")"
git -C "$G" checkout -q main
git clone -q "$G" "$R" && mkdir -p "$R/.fable-team/state"; git -C "$R" fetch -q origin
mkdir -p "$R/design/x"; printf 'verdict %s\n' "$X8" > "$R/design/x/VERDICT.md"; git -C "$R" add design/x/VERDICT.md
GIT_COMMITTER_DATE='2020-01-01T00:00:00' GIT_AUTHOR_DATE='2020-01-01T00:00:00' cm "$R" xdoc; XMAIN="$(git -C "$R" rev-parse HEAD)"
STATE="$R/.fable-team/state"; TSV="$STATE/scratch-repos.tsv"; SLOG="$STATE/scratch-sweep.log"; ARMED="$STATE/scratch-sweep.armed"

# 가짜 tmux(세션 목록 파일) · 가짜 lsof(행 파일)
printf 'live-owner\n' > "$T/sessions"
printf '#!/bin/sh\n[ "$1" = list-sessions ] || exit 0\ncat "%s/sessions"\n' "$T" > "$BIN/tmux"
printf '#!/bin/sh\ncat "%s/lsof.out" 2>/dev/null\nexit 0\n' "$T" > "$BIN/lsof"
chmod 755 "$BIN/tmux" "$BIN/lsof"
cwd_rows() { : > "$T/lsof.out"; while [ "$#" -ge 3 ]; do printf 'p%s\nc%s\nfcwd\nn%s\n' "$2" "$3" "$1" >> "$T/lsof.out"; shift 3; done; }
cwd_rows / 1 zsh
# 주입 대역 하나를 명령 이름으로 깐다: INJ_CMD 가 내 이름이고 « $* » 에 INJ_SPOT 이 있으면 «N번째 맞는 호출» 만
#   INJ_OUT=real(진짜 실행 뒤 rc128) · empty(안 부르고 빈 출력 rc128) · fake(INJ_FAKE 를 찍고 rc0 — «거짓말하는» 명령)
REALS=""; for c in git date awk cut cat du stat id rm mv find; do REALS="$REALS $c=$(command -v "$c")"; done
cat > "$IBIN/inj" <<EOF
#!/bin/sh
me=\${0##*/}; real=""
for kv in $REALS pwd=/bin/pwd tmux=$BIN/tmux lsof=$BIN/lsof; do [ "\${kv%%=*}" = "\$me" ] && real="\${kv#*=}"; done
PATH=/usr/bin:/bin:/usr/sbin:/sbin
printf '%s %s\n' "\$me" "\$*" >> "$T/inj.calls"
if [ "\$me" = "\${INJ_CMD:-}" ]; then
  case " \$* " in *"\${INJ_SPOT:-}"*)
    n=\$(( \$(/bin/cat "$T/inj.n" 2>/dev/null || echo 0) + 1 )); echo "\$n" > "$T/inj.n"
    if [ "\$n" = "\${INJ_N:-1}" ]; then
      printf '%s %s\n' "\$me" "\$*" >> "$T/inj.fired"
      case "\${INJ_OUT:-real}" in
        real) "\$real" "\$@";;
        fake) printf '%s\n' "\${INJ_FAKE:-}"; exit 0;;
      esac
      exit 128
    fi;;
  esac
fi
exec "\$real" "\$@"
EOF
chmod 755 "$IBIN/inj"; for c in git date awk cut cat du stat id rm mv find pwd tmux lsof; do ln -sf inj "$IBIN/$c"; done

sc() { : > "$T/inj.calls"; rm -f "$T/inj.n" "$T/inj.fired"
  OUT="$(env PATH="$IBIN:$PATH" FT_RES_ROOT="$R" FT_SCRATCH_DIR="${SDIR:-$SCR}" TMPDIR="$TMPD" FT_SCRATCH_OWNER="${OWN:-live-owner}" \
    FT_SCRATCH_MAIN="${XM-$XMAIN}" FT_SCRATCH_JUDGE_BUDGET=20 FT_SCRATCH_AGE_MIN=1440 \
    INJ_CMD="${INJ_CMD:-}" INJ_SPOT="${INJ_SPOT:-}" INJ_N="${INJ_N:-1}" INJ_OUT="${INJ_OUT:-real}" INJ_FAKE="${INJ_FAKE:-}" \
    bash "$SUT" "$@" 2>&1)"; RC=$?; }
mk() { OWN="$1" sc "$2" --repo "$G"; printf '%s' "$OUT"; }   # <주인> <sha> → 사본 경로(등록 4칸 · 베이스 = $SCR)
age_reg() { awk -F'\t' -v p="$1" -v t="$(( $(date +%s) - $2 ))" 'BEGIN{OFS="\t"} $1==p{$3=t} {print}' "$TSV" > "$TSV.n" && mv "$TSV.n" "$TSV"; }
gone() { [ ! -e "$1" ]; }
logged_del() { grep -qF "삭제 $1 " "$SLOG" 2>/dev/null; }

# ── 고정 이웃 세트(모든 칸 공통) ─────────────────────────────────────────────────────────
mkdir -p "$SCR/reg" "$SCR/other"
N3="$(mk live-owner "$SHA")"; age_reg "$N3" 90000                       # 살아 있는 주인 사본(25시간)
N4="$(mk gone-n4 "$YSHA")"; git -C "$N4" -c user.name=t -c user.email=t@t commit -q --allow-empty -m n4   # 젊은 사본(커밋 추가 = 빠른 길 아님)
N5="$(mk gone-n5 "$SHA")"; git -C "$N5" checkout -q -b n5side; printf 'd\n' >> "$N5/a.txt"; age_reg "$N5" 90000   # 가지 사본(25시간 · 주인 없음) — r1085: 더러운 가지 사본만 게이트 G7 이 거절한다(깨끗한 가지 사본 삭제 칸 = test_scratch_repo.sh r1085-ⓐ)
N6="$TMPD/tmp.young"; mkdir -p "$N6"                                     # 젊은 tmp
cp "$TSV" "$T/neigh.tsv"
NEIGH="$SCR/reg $SCR/other $N3 $N4 $N5 $N6 $SCR $TMPD $R $HOMEX"
neighbors_alive() { local x miss=""; for x in $NEIGH; do [ -d "$x" ] || miss="$miss $x"; done
  for x in "$N3" "$N4" "$N5"; do [ -e "$x/.git" ] || miss="$miss $x/.git"; done
  [ -z "$miss" ] || { echo "  이웃 사라짐:$miss"; return 1; }; }
reset() { cat "$T/neigh.tsv" > "$TSV"; : > "$ARMED"; : > "$SLOG"; cwd_rows / 1 zsh; printf 'live-owner\n' > "$T/sessions"; }
reset_q() { reset; awk -F'\t' -v p="$N5" '$1!=p' "$TSV" > "$TSV.n" && mv "$TSV.n" "$TSV"; }   # r1085: 가지 후보(N5)를 빼고 돌리는 칸 — 주입 «호출 번호» 가 후보 수에 안 흔들리게(폴더는 그대로 두고 등록 줄만 빼서 이웃 검사는 그대로)
cell() { # <칸 이름> <조건 식(문자열)> — 끝에 이웃 생존을 같이 본다
  if eval "$2" && neighbors_alive; then ok "$1"; else bad "$1 [rc=$RC] $(printf '%s' "$OUT" | tail -2 | tr '\n' ' ')"; fi; }
reset

# ── Ⓖ --gate 직접 — 조건 하나씩 깨기(삭제 0) ─────────────────────────────────────────────
if want Ⓖ; then
  reset; A="$(mk gone-g "$SHA")"; age_reg "$A" 90000
  sc --gate "$A"; cell "Ⓖ 전부 참 = GATE ok rc0 · 삭제 0" '[ $RC = 0 ] && [ -d "$A" ] && printf "%s" "$OUT" | grep -q "^GATE ok"'
  sc --gate "reg" --kind reg --owner gone-g; cell "Ⓖ G0 상대 경로 = REFUSED rc3" '[ $RC = 3 ] && printf "%s" "$OUT" | grep -q "^G0 REFUSED"'
  for x in "$R" "$TMPD" "$SCR"; do sc --gate "$x" --kind reg --owner gone-g; cell "Ⓖ G0 보호 경로 $(basename "$x") = rc3" '[ $RC = 3 ] && printf "%s" "$OUT" | grep -q "^G0 REFUSED"'; done
  sc --gate "$HOMEX" --kind tmp; cell "Ⓖ 홈 꼴(베이스 밖) = rc3" '[ $RC = 3 ] && printf "%s" "$OUT" | grep -q "^G1 REFUSED"'
  sc --gate "$SCR/reg" --kind reg --owner gone-g; cell "Ⓖ G5 등록 안 된 폴더 reg/ = rc3" '[ $RC = 3 ] && printf "%s" "$OUT" | grep -q "^G5 REFUSED"'
  sc --gate "$A" --kind reg --owner other; cell "Ⓖ G5 주인 다름 = rc3" '[ $RC = 3 ] && printf "%s" "$OUT" | grep -q "^G5 REFUSED"'
  cwd_rows "$A/sub" 4242 vite; sc --gate "$A"; cell "Ⓖ G4 점유 = HELD rc1" '[ $RC = 1 ] && printf "%s" "$OUT" | grep -q "^G4 HELD"'; cwd_rows / 1 zsh
  printf 'live-owner\ngone-g\n' > "$T/sessions"; sc --gate "$A"; cell "Ⓖ G6 주인 살아 있음 = HELD rc1" '[ $RC = 1 ] && printf "%s" "$OUT" | grep -q "^G6 HELD"'; printf 'live-owner\n' > "$T/sessions"
  INJ_CMD=date INJ_SPOT="+%s" INJ_OUT=empty sc --gate "$A"; cell "Ⓖ G3 시계 못 읽음 = UNREADABLE rc2" '[ $RC = 2 ] && printf "%s" "$OUT" | grep -q "^G3 UNREADABLE"'
  sc --gate "$N5"; cell "Ⓖ G7 가지 워크트리(더러움) = REFUSED rc3" '[ $RC = 3 ] && printf "%s" "$OUT" | grep -q "^G7 REFUSED"'
  Y="$(mk gone-gy "$YSHA")"; sc --gate "$Y"; cell "Ⓖ 자격: 젊음 ∧ 판정 안 끝남 = rc3" '[ $RC = 3 ] && printf "%s" "$OUT" | grep -q "^G6 REFUSED (자격 없음"'
fi

# ── Ⓝ 정상 길 — 주인 없는 25시간 사본 + 24시간 지난 tmp + 판정 끝 1분 사본 = 셋 삭제 · 이웃 생존 ──
if want Ⓝ; then
  reset; rm -f "$ARMED"; A="$(mk gone-n1 "$SHA")"; age_reg "$A" 90000; F="$(mk gone-n2 "$XSHA")"
  TO="$TMPD/tmp.old1"; mkdir -p "$TO"; touch -t 202001010000 "$TO"
  sc --sweep; cell "Ⓝ 첫 sweep = 목록만 · 삭제 0" '[ -d "$A" ] && [ -d "$F" ] && [ -d "$TO" ] && printf "%s" "$OUT" | grep -q "목록 보고"'
  sc --sweep; cell "Ⓝ 둘째 sweep = 셋 삭제 · swept=3 · 등록 줄 빠짐" 'gone "$A" && gone "$F" && gone "$TO" && grep -q "swept=3" "$SLOG" && ! grep -qF "$A" "$TSV" && ! grep -qF "$F" "$TSV"'
  cell "Ⓝ 가지 워크트리(더러움) = gate refused(G7) 줄 · 그 항목만 건너뜀" 'printf "%s" "$OUT" | grep -q "gate refused $N5 (G7"'
  [ -z "$(ls -A "$TMPD/.reaping" 2>/dev/null)" ] && ok "Ⓝ 격리 폴더 비었음(이동한 tmp 는 지워짐)" || bad "Ⓝ .reaping 잔존 $(ls -A "$TMPD/.reaping")"
fi

# ── Ⓑ du 실패 = 표시만(삭제 판단 불변 · 빈 칸 0 = 열 밀림 0) ────────────────────────────────
if want Ⓑ; then
  for mode in empty real; do
    reset; A="$(mk gone-b "$SHA")"; age_reg "$A" 90000
    INJ_CMD=du INJ_SPOT="" INJ_N=1 INJ_OUT="$mode" sc --sweep
    cell "Ⓑ du $mode+rc128 = 대상 판정 그대로(삭제) · reg/ 생존" '[ -s "$T/inj.fired" ] && gone "$A"'
  done
fi

# ── Ⓓ 같은 경로 등록 2줄 = 그 항목만 건너뜀(G5 «정확히 1줄») ─────────────────────────────────
if want Ⓓ; then
  reset; A="$(mk gone-d "$SHA")"; age_reg "$A" 90000; grep -F "$A" "$TSV" > "$T/dup"; cat "$T/dup" >> "$TSV"
  B="$(mk gone-d2 "$SHA")"; age_reg "$B" 90000
  sc --sweep; cell "Ⓓ 중복 등록 = 삭제 0 · gate refused(G5) · 뒤 항목은 삭제" '[ -d "$A" ] && gone "$B" && printf "%s" "$OUT" | grep -q "gate refused $A (G5"'
fi

# ── Ⓔ 사본 하위 폴더 · 이름꼴 아닌 사본 · 베이스 밖 사본(조건 하나만 거짓 — 고침 11) ────────────
if want Ⓔ; then
  reset; A="$(mk gone-e "$SHA")"; age_reg "$A" 90000; mkdir -p "$A/sub"
  printf '%s\t%s\t%s\t%s\n' "$A/sub" gone-e1 "$(( $(date +%s) - 90000 ))" "$SCR" >> "$TSV"
  XE="$SCR/repo-$X8-1-1-extra"; git -C "$G" worktree add -q --detach "$XE" "$SHA" >/dev/null 2>&1
  printf '%s\t%s\t%s\t%s\n' "$XE" gone-e2 "$(( $(date +%s) - 90000 ))" "$SCR" >> "$TSV"
  OUTS="$T/outside"; mkdir -p "$OUTS"; O="$(SDIR="$OUTS" mk gone-e3 "$SHA")"; age_reg "$O" 90000
  awk -F'\t' -v p="$O" -v b="$SCR" 'BEGIN{OFS="\t"} $1==p{$4=b} {print}' "$TSV" > "$TSV.n" && mv "$TSV.n" "$TSV"   # 등록 베이스를 SCR 로 — G1 만 거짓
  awk -F'\t' -v p="$A" 'BEGIN{OFS="\t"} $1==p{$2="live-owner"} {print}' "$TSV" > "$TSV.n" && mv "$TSV.n" "$TSV"   # 사본 자체는 주인 살림(하위 폴더 칸만 본다)
  sc --sweep
  cell "Ⓔ 사본/sub 등록 = 거절(G1 깊이) · 사본 생존" '[ -d "$A/sub" ] && [ -d "$A" ] && printf "%s" "$OUT" | grep -q "gate refused $A/sub (G1"'
  cell "Ⓔ 이름꼴 아님(-extra · 25시간 · git 참) = 거절(G2)" '[ -d "$XE" ] && printf "%s" "$OUT" | grep -q "gate refused $XE (G2"'
  cell "Ⓔ 베이스 밖(등록 베이스 SCR · 나머지 참) = 거절(G1)" '[ -d "$O" ] && printf "%s" "$OUT" | grep -q "gate refused $O (G1"'
fi

# ── Ⓕ 더러운 가지 사본 — 여러 번 sweep 해도 거절만(이웃 N5 가 매 칸 본다 · 여기선 명시) ──────────────
if want Ⓕ; then
  reset; sc --sweep; sc --sweep
  cell "Ⓕ 가지 워크트리(더러움) = sweep 2회 뒤에도 생존 · REFUSED 로그" '[ -d "$N5" ] && grep -q "REFUSED $N5 (G7" "$SLOG"'
fi

# ── Ⓗ tmp: git 폴더 · 남의 uid · find 가 틀림(젊은데 «오래됨») ───────────────────────────────
if want Ⓗ; then
  reset; TG="$TMPD/tmp.git"; mkdir -p "$TG/.git"; touch -t 202001010000 "$TG"
  sc --sweep; cell "Ⓗ tmp 안에 .git = 거절(G5) · 생존" '[ -d "$TG/.git" ] && printf "%s" "$OUT" | grep -q "gate refused $TG (G5"'
  reset; TU="$TMPD/tmp.uid"; mkdir -p "$TU"; touch -t 202001010000 "$TU"
  INJ_CMD=stat INJ_SPOT="tmp.uid" INJ_OUT=fake INJ_FAKE=0 sc --sweep
  cell "Ⓗ 남의 uid(stat 이 0 이라 함) = 거절(G6) · 생존" '[ -s "$T/inj.fired" ] && [ -d "$TU" ] && printf "%s" "$OUT" | grep -q "gate refused $TU (G6 내 소유 아님"'
  reset; TY="$TMPD/tmp.fresh"; mkdir -p "$TY"
  INJ_CMD=find INJ_SPOT="tmp.*" INJ_OUT=fake INJ_FAKE="$TY" sc --sweep
  cell "Ⓗ find 가 젊은 폴더를 «오래됨» 이라 함 = 거절(G6 나이 재측정) · 생존" '[ -s "$T/inj.fired" ] && [ -d "$TY" ] && printf "%s" "$OUT" | grep -q "gate refused $TY (G6"'
  rm -rf "$TG" "$TU" "$TY"
fi

# ── Ⓘ --done: 등록 밖 · 남의 사본 · 정상 ────────────────────────────────────────────────
if want Ⓘ; then
  reset; A="$(mk live-owner "$XSHA")"   # 같은 sha·주인 = 이웃 N3 재사용(r444) — 다른 sha 로
  OWN=live-owner sc --done "$SCR/reg"; cell "Ⓘ --done 등록 밖 폴더 = rc2 · 삭제 0" '[ $RC = 2 ] && [ -d "$SCR/reg" ]'
  OWN=other sc --done "$A"; cell "Ⓘ --done 남의 사본 = rc2" '[ $RC = 2 ] && [ -d "$A" ]'
  OWN=live-owner sc --done "$A"; cell "Ⓘ --done 정상 = DONE · 등록 줄 빠짐" '[ $RC = 0 ] && gone "$A" && ! grep -qF "$A" "$TSV"'
fi

# ── Ⓚ 고침 칸(DECISION 고침 2·5·7·8 각 1칸 — 1·3·4·6 은 Ⓖ 자격 · Ⓓ/변이 rc2-continue · r10 ⓥ 마감 · Ⓝ 등록 줄 빠짐) ──────
if want Ⓚ; then
  # 고침 2: 게이트는 «자기» lsof 를 판정에 쓴다 — orphans 의 lsof 는 깨끗하고 게이트의 lsof(3번째: orphans·N5·대상)만 점유를 보인다
  reset_q; A="$(mk gone-k2 "$SHA")"; age_reg "$A" 90000
  INJ_CMD=lsof INJ_SPOT="-d cwd" INJ_N=3 INJ_OUT=fake INJ_FAKE="$(printf 'p4242\ncvite\nfcwd\nn%s/sub' "$A")" sc --sweep
  cell "Ⓚ 고침2 게이트 자기 lsof 가 점유 = 붙잡음 · 삭제 0" '[ -s "$T/inj.fired" ] && [ -d "$A" ] && printf "%s" "$OUT" | grep -q "재확인에서 쓰는 중"'
  # 고침 5: 확인한 객체 = 지운 객체 — 제거 직전 장치·inode 가 다르면 삭제 0(등록 사본 · tmp 이동 뒤)
  reset_q; A="$(mk gone-k5 "$SHA")"; age_reg "$A" 90000; KB="${A##*/}"
  INJ_CMD=stat INJ_SPOT="$KB" INJ_N=2 INJ_OUT=fake INJ_FAKE="1:1" sc --sweep
  cell "Ⓚ 고침5 reg 제거 직전 inode 다름 = 삭제 0(G8)" '[ -s "$T/inj.fired" ] && [ -d "$A" ] && printf "%s" "$OUT" | grep -q "G8 제거 직전 장치·inode"'
  reset_q; TK="$TMPD/tmp.k5"; mkdir -p "$TK"; touch -t 202001010000 "$TK"
  INJ_CMD=stat INJ_SPOT=".reaping/tmp.k5" INJ_N=1 INJ_OUT=fake INJ_FAKE="1:1" sc --sweep
  cell "Ⓚ 고침5 tmp 이동 뒤 inode 다름 = 원위치 복원 · 삭제 0" '[ -s "$T/inj.fired" ] && [ -d "$TK" ] && printf "%s" "$OUT" | grep -q "원위치 복원"'
  rm -rf "$TK"
  # 고침 7: 옛 3칸 등록 줄(베이스 칸 없음) = 기본 TMPDIR·지금 FT_SCRATCH_DIR 아래면 통과
  reset_q; A="$(mk gone-k7 "$SHA")"; age_reg "$A" 90000
  awk -F'\t' -v p="$A" 'BEGIN{OFS="\t"} $1==p{NF=3} {print}' "$TSV" > "$TSV.n" && mv "$TSV.n" "$TSV"
  sc --sweep; cell "Ⓚ 고침7 옛 3칸 줄(지금 FT_SCRATCH_DIR 아래) = 삭제" 'gone "$A" && logged_del "$A"'
  # 고침 8: bare 원 저장소의 사본도 연결 워크트리로 인정(경로 글자 */.git/worktrees/* 가정 0)
  reset_q; BARE="$T/bare.git"; [ -d "$BARE" ] || git clone -q --bare "$G" "$BARE"
  OWN=gone-k8 sc "$SHA" --repo "$BARE"; A="$OUT"; age_reg "$A" 90000
  sc --sweep; cell "Ⓚ 고침8 bare 원 저장소 사본 = 삭제" '[ -n "$A" ] && gone "$A" && logged_del "$A"'
fi

# ── ⓧ 주입 전수 — 등록 사본(빠른 길: 1분 · 판정 끝) ∧ tmp(24시간 지남) · 각 칸 삭제 0 ∧ 이웃 생존 ─────
xwant() { [ -z "$XONLY" ] || printf '%s\n' "$1" | grep -qE "$XONLY"; }
cnt() { awk -v c="$1" -v s="$2" '$1==c && (s=="" || index(" " substr($0, length(c)+2) " ", s)){n++} END{print n+0}' "$T/inj.calls.ctl"; }
if want ⓧ; then
  xi=0
  xmk() { xi=$((xi+1)); reset_q; if [ "$1" = reg ]; then CP="$(mk "gone-x$xi" "$XSHA")"; else CP="$TMPD/tmp.x$xi"; mkdir -p "$CP"; touch -t 202001010000 "$CP"; fi; CB="${CP##*/}"; }
  xrun() { # <reg|tmp> <명령> <자리> <N> <모드> <칸 이름>
    xwant "$6" || return 0
    xmk "$1"; [ -d "$CP" ] || { bad "ⓧ $6 대상 생성 실패"; return; }
    INJ_CMD="$2" INJ_SPOT="${3//@B@/$CB}" INJ_N="$4" INJ_OUT="$5" sc --sweep
    if [ ! -s "$T/inj.fired" ]; then bad "ⓧ $6 주입이 안 걸림(빈 칸)"; return; fi
    cell "ⓧ $6 = 삭제 0" '[ -d "$CP" ] && ! logged_del "$CP"'
  }
  for kind in reg tmp; do
    xmk "$kind"; sc --sweep; cp "$T/inj.calls" "$T/inj.calls.ctl"
    cell "ⓧ $kind 대조(주입 0) = 지운다" 'gone "$CP" && logged_del "$CP"'
    CTLB="$CB"
    if [ "$kind" = reg ]; then
      # r1085: 후보가 «더러운 가지 사본» 이면 게이트마다 git status 를 한 번 더 부른다 — 주입 자리는 «대상 사본 + 인자 꼬리» 로 좁혀 다른 후보·전역 호출(원 저장소 장부 찾기)의 호출 수에 안 흔들리게 한다
      SPOTS=("git|@B@ rev-parse HEAD" "git|@B@ symbolic-ref" "git|@B@ rev-parse --path-format=absolute --git-dir" "git|@B@ rev-parse --show-toplevel" "git|@B@ rev-parse --path-format=absolute --git-common-dir" "git|merge-base" "git|grep -F" "git|log -1" \
             "date|+%s" "tmux|list-sessions" "lsof|-d cwd" "awk|/^p/" "cat|scratch-repos.tsv" "stat|@B@" "pwd|")
      [ "$(cnt cut "")" = 0 ] && ok "ⓧ cut = 지우는 길에서 호출 0" || bad "ⓧ cut 호출 $(cnt cut "")회"
    else
      SPOTS=("date|+%s" "tmux|list-sessions" "lsof|-d cwd" "awk|/^p/" "cat|scratch-repos.tsv" "id|" "find|tmp.*" "stat|@B@" "pwd|")
    fi
    for row in "${SPOTS[@]}"; do
      c="${row%%|*}"; s="${row#*|}"
      k="$(cnt "$c" "${s//@B@/$CTLB}")"
      [ "$k" -gt 0 ] || { bad "ⓧ $kind $c:$s 대조에서 호출 0(시험 자리 틀림)"; continue; }
      n=1; while [ "$n" -le "$k" ]; do
        for mode in real empty; do xrun "$kind" "$c" "$s" "$n" "$mode" "$kind $c:${s//@B@/<사본>}#$n $mode"; done
        n=$((n+1))
      done
    done
  done
  # 삭제 명령 실패: «호출 전 실패»(진짜 안 부름) = 생존·ERROR·다음 sweep 삭제 1 · «실행 뒤 실패» = ERROR·등록 줄 유지(폴더 상태 무관)
  if xwant "reg git:worktree remove"; then
    xmk reg; INJ_CMD=git INJ_SPOT="worktree remove" INJ_OUT=empty sc --sweep
    cell "ⓧ reg git:worktree remove 호출 전 실패 = 생존 · 등록 줄 유지 · ERROR(rm 후퇴 0)" '[ -s "$T/inj.fired" ] && [ -d "$CP" ] && grep -qF "$CP" "$TSV" && printf "%s" "$OUT" | grep -q "ERROR 삭제 실패: $CP"'
    : > "$SLOG"; sc --sweep; cell "ⓧ reg git:worktree remove 다음 sweep(주입 0) = 삭제 1" 'gone "$CP" && logged_del "$CP"'
    xmk reg; INJ_CMD=git INJ_SPOT="worktree remove" INJ_OUT=real sc --sweep
    cell "ⓧ reg git:worktree remove 실행 뒤 실패 = ERROR · 등록 줄 유지" '[ -s "$T/inj.fired" ] && grep -qF "$CP" "$TSV" && printf "%s" "$OUT" | grep -q "ERROR 삭제 실패: $CP"'
  fi
  if xwant "tmp rm:"; then
    xmk tmp; INJ_CMD=rm INJ_SPOT=".reaping" INJ_OUT=empty sc --sweep
    cell "ⓧ tmp rm: 호출 전 실패 = 원위치 생존 · ERROR" '[ -s "$T/inj.fired" ] && [ -d "$CP" ] && printf "%s" "$OUT" | grep -q "ERROR 삭제 실패: $CP"'
    : > "$SLOG"; sc --sweep; cell "ⓧ tmp rm: 다음 sweep(주입 0) = 삭제 1" 'gone "$CP" && logged_del "$CP"'
    xmk tmp; INJ_CMD=rm INJ_SPOT=".reaping" INJ_OUT=real sc --sweep
    cell "ⓧ tmp rm: 실행 뒤 실패 = ERROR" '[ -s "$T/inj.fired" ] && printf "%s" "$OUT" | grep -q "ERROR 삭제 실패: $CP"'
  fi
  for mode in real empty; do
    xwant "tmp mv:$mode" || continue
    xmk tmp; INJ_CMD=mv INJ_SPOT="$CB" INJ_OUT="$mode" sc --sweep
    cell "ⓧ tmp mv:$mode 격리 이동 실패 = 원위치 생존 · ERROR" '[ -s "$T/inj.fired" ] && [ -d "$CP" ] && printf "%s" "$OUT" | grep -q "ERROR 삭제 실패: $CP"'
  done
  # origin/main 확인: rc1(정말 없음)일 때만 main — rc128 = 판정 안 끝남
  if xwant "verify"; then
    git -C "$R" update-ref -d refs/remotes/origin/main
    XM="" xmk reg; XM="" sc --sweep; cell "ⓧ verify 대조(origin/main 없음 rc1) = main 기준 삭제" 'gone "$CP"'
    for mode in real empty; do
      XM="" xmk reg; XM="" INJ_CMD=git INJ_SPOT="--verify origin/main" INJ_OUT="$mode" sc --sweep
      cell "ⓧ verify origin/main rc128 $mode = main 으로 후퇴 0 · 삭제 0" '[ -s "$T/inj.fired" ] && [ -d "$CP" ]'
    done
    git -C "$R" update-ref refs/remotes/origin/main "$SHA"
  fi
fi

# ── 변이(고침 11 — 조건 하나만 막는 입력 · 기대 칸만 빨강일 때 검출) ─────────────────────────────
if want M; then
  mut() { # <이름> <sed 식> <케이스> <기대 FAIL 정규식> [<FT_XONLY>]
    local m="$T/mut-$1.sh" nf nx
    sed "$2" "$SUT" > "$m"
    cmp -s "$SUT" "$m" && { bad "변이 $1 이 안 바뀜"; return; }
    bash -n "$m" 2>/dev/null || { bad "변이 $1 문법 깨짐(가짜 변이)"; return; }
    FT_MUT_CHILD=1 FT_SUT="$m" FT_CASES="$3" FT_XONLY="${5:-}" bash "${BASH_SOURCE[0]}" > "$T/mut-$1.log" 2>&1; r=$?
    nf="$(grep -c '^FAIL' "$T/mut-$1.log")"; nx="$(grep -cE "^FAIL $4" "$T/mut-$1.log")"
    { [ "$r" != 0 ] && [ "$nf" -gt 0 ] && [ "$nf" = "$nx" ]; } && ok "변이 $1 → $3 기대 칸만 빨강($4 · ${nf}칸)" \
      || bad "변이 $1 이 기대 칸으로 안 잡힘(rc=$r · FAIL $nf · 기대 칸 $nx) $(grep '^FAIL' "$T/mut-$1.log" | head -2 | tr '\n' ' ')"
  }
  mut g1 's#^  gfail G1 3 "베이스 바로 아래 아님"#  GB="${P%/*}"; return 0#' 'Ⓔ' 'Ⓔ (사본/sub|베이스 밖)'
  mut g2 's,\[\[ \${P##\*/} =~ \$re \]\] || { gfail G2 3,[[ x =~ x ]] || { gfail G2 3,' 'Ⓔ' 'Ⓔ 이름꼴'
  mut g5-count 's#\[ "\$n" = 1 \] || { gfail G5 3#[ "$n" -ge 1 ] || { gfail G5 3#' 'Ⓓ' 'Ⓓ '
  mut g7-dirty 's#\[ "\$ST" = 0 \] || { gfail G7 3 "가지 사본 더러움#: || { gfail G7 3 "가지 사본 더러움#' 'Ⓕ' 'Ⓕ '
  mut g6t-age 's#\[ \$(( now - M )) -ge \$((AGE\*60)) \] || { gfail G6 3#: || { gfail G6 3#' 'Ⓗ' 'Ⓗ find'
  mut g6t-uid 's#isnum "\$U" \&\& isnum "\$ME" \&\& \[ "\$U" = "\$ME" \] || { gfail G6 3#: || { gfail G6 3#' 'Ⓗ' 'Ⓗ 남의 uid'
  mut g5t-git 's#\[ ! -e "\$P/.git" \] || { gfail G5 3#: || { gfail G5 3#' 'Ⓗ' 'Ⓗ tmp 안에'
  mut g6-owner 's#has_line "\$S" "\$own" \&\& { gfail G6 1#false \&\& { gfail G6 1#' 'Ⓖ' 'Ⓖ G6'
  mut rm-fallback 's#git -C "\$P" worktree remove --force "\$P" >/dev/null 2>\&1 ||#{ git -C "$P" worktree remove --force "$P" >/dev/null 2>\&1 || rm -r -f "$P"; } ||#' 'ⓧ' 'ⓧ reg git:worktree remove' 'worktree remove'
  # r996: 등록부 읽기 = r996 reg_rows 의 `cap rows cat` (장부 둘) — rc 를 안 보는 `$(cat)` 로 바꾸면 그 주입 칸이 빨강
  mut cat-procsub 's#^    cap rows cat -- "\$f" || { REG_BAD=1; continue; }#    rows="$(cat "$f" 2>/dev/null)"#' 'ⓧ' 'ⓧ reg cat:scratch-repos.tsv#1 real' 'reg cat:scratch-repos.tsv#1'
  mut awk-orphans 's#cap CWDROWS cwd_parse "\$RAW" || LSOF_OK=0#cap CWDROWS cwd_parse "$RAW"#' 'ⓧ' 'ⓧ (reg|tmp) awk:/\^p/#1 ' '(reg|tmp) awk:/\^p/#1 '
  mut judged-sha 's#cap sha git -C "\$1" rev-parse HEAD 2>/dev/null || return 1; h8=#cap sha git -C "$1" rev-parse HEAD 2>/dev/null; h8=#' 'ⓧ' 'ⓧ reg git:<사본> rev-parse HEAD#[0-9]+ real' 'reg git:<사본> rev-parse HEAD'
  mut mainref 's#\*) echo "WARN ft-scratch-repo judged — origin/main 확인 실패.*#*) printf -v "$1" "%s" main;;#' 'ⓧ' 'ⓧ verify origin' 'verify'
  mut rc2-continue 's#      \*) RSTOP=1; printf#      *) printf#' 'ⓧ' 'ⓧ reg [a-z]+:' 'reg (date|tmux|lsof):'
fi

[ $fail -eq 0 ] && echo "ALL PASS" || echo "($fail failed)"
exit $fail
