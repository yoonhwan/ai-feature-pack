#!/usr/bin/env bash
# test_scratch_unknown_r1090s2.sh — ft-scratch-repo.sh r1090 단계 2: 사본 1개 «재확인 못 읽음»(rc2)이 회차 전체를 멈추지 않는다
#   S1 정상·rc2·정상 = 1·3 처리 · 2 는 «판정 불가» 1줄 · 끝 줄 unknown=1 / S1b 떨어진 rc2 셋 = 멈춤 0
#   S2 rc2 연속 3개 = 3번째에서 멈춤 + «남은 항목 삭제 0» / S3 더러움(rc3) = 지금 그대로 REFUSED / S4 시계 못 읽음 = 지금 그대로 전체 정지
#   임시 repo·가짜 git/date/tmux 만 쓴다(실 저장소·실 세션 0) · 변이 2종: FT_CASES=M (rc2 갈래 되돌림 → S1 FAIL · 연속 3 상한 끔 → S2 FAIL)
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
G="$T/src"; R="$T/R"; SCR="$T/scratch"; TMPD="$T/tmpdir"; mkdir -p "$G" "$R/.fable-team/state" "$SCR" "$TMPD" "$T/bin" "$T/gbin"
git -C "$G" init -q && echo a > "$G/a.txt" && git -C "$G" add a.txt && git -C "$G" -c user.name=t -c user.email=t@t commit -q -m c1
SHA="$(git -C "$G" rev-parse HEAD)"; SH8="${SHA:0:8}"
printf '#!/bin/sh\n[ "$1" = list-sessions ] && cat "%s/sessions" 2>/dev/null\nexit 0\n' "$T" > "$T/bin/tmux"; chmod 755 "$T/bin/tmux"
printf 'live-owner\n' > "$T/sessions"
# 가짜 git: GBAD(공백 목록) 사본의 «rev-parse --show-toplevel» 은 128 로 실패(= 그 사본만 git 깨짐) · GMARK 사본의 같은 호출은 표지 파일을 만든다(시계 주입 시점용)
GITREAL="$(command -v git)"; GB4="$T/gbin4"; mkdir -p "$GB4"
cat > "$GB4/git" <<EOF
#!/bin/sh
case "\$*" in
  *"rev-parse --show-toplevel"*)
    p=""; prev=""; for a in "\$@"; do [ "\$prev" = -C ] && p="\$a"; prev="\$a"; done
    b="\${p##*/}"
    for x in \${GBAD:-}; do [ "\$b" = "\$x" ] && { echo "fatal: not a git repository" >&2; exit 128; }; done
    [ -z "\${GMARK:-}" ] || [ "\$b" != "\$GMARK" ] || : > "$T/datefail";;
esac
exec "$GITREAL" "\$@"
EOF
cat > "$GB4/date" <<EOF
#!/bin/sh
if [ -e "$T/datefail" ]; then for a in "\$@"; do [ "\$a" = "+%s" ] && exit 1; done; fi
exec /bin/date "\$@"
EOF
chmod 755 "$GB4/git" "$GB4/date"
sc() { OUT="$(env PATH="$GB4:$T/gbin:$T/bin:$PATH" FT_RES_ROOT="$R" FT_SCRATCH_DIR="$SCR" TMPDIR="$TMPD" FT_SCRATCH_OWNER="live-owner" \
  GBAD="${GBAD:-}" GMARK="${GMARK:-}" bash "$SUT" "$@" 2>&1)"; RC=$?; }
TSV="$R/.fable-team/state/scratch-repos.tsv"; ARM="$R/.fable-team/state/scratch-sweep.armed"; SLOG="$R/.fable-team/state/scratch-sweep.log"
arm() { date +%s > "$ARM"; }
mkcopy() { # <번호> → detached 사본 + 등록 줄(주인 죽음 · 25시간 전)
  local p="$SCR/repo-$SH8-9-$1"
  git -C "$G" worktree add -q --detach "$p" "$SHA" >/dev/null 2>&1
  printf '%s\t%s\t%s\n' "$p" gone-rd "$(( $(date +%s) - 90000 ))" >> "$TSV"
  printf '%s' "$p"
}
base() { printf 'repo-%s-9-%s' "$SH8" "$1"; }
drop() { local p; for p in "$@"; do rm -rf "$p"; awk -F'\t' -v a="$p" '$1!=a' "$TSV" > "$TSV.n" && mv "$TSV.n" "$TSV"; done; git -C "$G" worktree prune 2>/dev/null; }
# lsof 는 다른 프로세스가 사라지는 순간 rc≠0 을 낼 수 있다 — 시험은 «lsof 때문에» 판정 불가가 낀 회차만 다시 잰다(같은 조건 3회까지)
scs() { local i; for i in 1 2 3; do sc "$@"; printf '%s' "$OUT" | grep -q 'rc=2 · G4 lsof' || return 0; done; }
cnt() { sed -n 's/.*'"$1"'=\([0-9][0-9]*\).*/\1/p' <<<"$2"; }   # <키> <끝줄> → 수
lastline() { grep 'swept=' "$SLOG" | tail -1; }
want() { case "${FT_CELLS:-all}" in all) return 0;; *"$1"*) return 0;; esac; return 1; }

if want rs2 && { [ "${FT_CASES:-all}" != M ] || [ -n "${FT_MUT_CHILD:-}" ]; }; then   # 변이 회차(FT_CASES=M)의 부모는 green 을 다시 돌리지 않는다(green 은 따로 1회 — 하드 룰 22)
  # ── S1: 정상 · rc2(git 깨짐) · 정상 → 1·3 지움 · 2 남음 · 판정 불가 1줄 · unknown=1 ──
  arm; A="$(mkcopy 11)"; B="$(mkcopy 12)"; C="$(mkcopy 13)"
  GBAD="$(base 12)" scs --sweep; L="$(lastline)"
  { [ ! -d "$A" ] && [ ! -d "$C" ] && [ -d "$B" ] && grep -qF "판정 불가 $B" "$SLOG" && printf '%s' "$OUT" | grep -q '이 항목만 건너뜀'; } \
    && ok "S1 정상·rc2·정상 = 1·3 삭제 · 2 남음 · 로그 «판정 불가 <경로>» · 이 항목만 건너뜀" || bad "S1 rc=$RC A=$([ -d "$A" ] && echo 남음) B=$([ -d "$B" ] && echo 남음) C=$([ -d "$C" ] && echo 남음) [$OUT]"
  [ "$(cnt unknown "$L")" = 1 ] && ok "S1 끝 줄 unknown=1 [$L]" || bad "S1 끝 줄 [$L]"   # swept 수는 단언하지 않는다: lsof 흔들림으로 scs 가 다시 돌면 남은 사본만 센다
  drop "$A" "$B" "$C"
  # ── S1b: rc2 가 «떨어져» 셋(rc2·정상·rc2·정상·rc2) = 연속 아님 → 멈춤 0 · 정상 둘 지움 · unknown=3 ──
  arm; P1="$(mkcopy 21)"; P2="$(mkcopy 22)"; P3="$(mkcopy 23)"; P4="$(mkcopy 24)"; P5="$(mkcopy 25)"
  GBAD="$(base 21) $(base 23) $(base 25)" scs --sweep; L="$(lastline)"
  { [ ! -d "$P2" ] && [ ! -d "$P4" ] && [ -d "$P1" ] && [ -d "$P3" ] && [ -d "$P5" ] && [ "$(cnt unknown "$L")" = 3 ]; } \
    && ok "S1b 떨어진 rc2 셋 = 멈춤 0 · 사이 정상 둘 삭제 · unknown=3" || bad "S1b 끝 줄 [$L] [$OUT]"
  drop "$P1" "$P2" "$P3" "$P4" "$P5"
  # ── S2: rc2 연속 3개 → 3번째에서 멈춤 · 4번째(정상)는 지우지 않음 · 지금 꼴(남은 항목 삭제 0) ──
  arm; Q1="$(mkcopy 31)"; Q2="$(mkcopy 32)"; Q3="$(mkcopy 33)"; Q4="$(mkcopy 34)"
  GBAD="$(base 31) $(base 32) $(base 33)" scs --sweep; L="$(lastline)"
  { [ -d "$Q4" ] && [ -d "$Q1" ] && [ -d "$Q2" ] && [ -d "$Q3" ] && [ "$(cnt unknown "$L")" = 3 ] && [ "$(cnt swept "$L")" = 0 ] \
    && grep -q '재확인 못 읽음 연속 3 — 남은 항목 삭제 0' "$SLOG" && printf '%s' "$OUT" | grep -q '남은 항목 전부 삭제 0'; } \
    && ok "S2 rc2 연속 3개 = 3번째에서 멈춤 · 4번째 정상도 삭제 0 · 끝 줄 unknown=3 swept=0" || bad "S2 끝 줄 [$L] Q4=$([ -d "$Q4" ] && echo 남음 || echo 지움) [$OUT]"
  drop "$Q1" "$Q2" "$Q3" "$Q4"
  # ── S3: 더러움(rc3) = 지금 그대로 REFUSED · unknown 에 안 센다 · 뒤 정상은 지운다 ──
  arm; D1="$(mkcopy 41)"; printf 'z\n' >> "$D1/a.txt"; D2="$(mkcopy 42)"
  scs --sweep; L="$(lastline)"
  { [ -d "$D1" ] && [ ! -d "$D2" ] && grep -q "REFUSED $D1" "$SLOG" && [ "$(cnt refused-dirty "$L")" = 1 ] && [ "$(cnt unknown "$L")" = 0 ]; } \
    && ok "S3 더러움 = REFUSED 그대로 · refused-dirty=1 unknown=0 · 뒤 정상 삭제" || bad "S3 끝 줄 [$L] [$OUT]"
  drop "$D1" "$D2"
  # ── S4: 시계 못 읽음 = 지금 그대로 전체 정지(첫 항목의 git 조회 때 date +%s 가 죽기 시작) ──
  arm; E1="$(mkcopy 51)"; E2="$(mkcopy 52)"; E3="$(mkcopy 53)"; rm -f "$T/datefail"
  GMARK="$(base 51)" scs --sweep; rm -f "$T/datefail"
  { [ -d "$E2" ] && [ -d "$E3" ] && printf '%s' "$OUT" | grep -q '시계 못 읽음 · 남은 항목 삭제 0'; } \
    && ok "S4 시계 못 읽음 = 남은 항목 삭제 0 으로 전체 정지(지금 그대로)" || bad "S4 E2=$([ -d "$E2" ] && echo 남음 || echo 지움) E3=$([ -d "$E3" ] && echo 남음 || echo 지움) [$OUT]"
  drop "$E1" "$E2" "$E3"
fi

# ── 변이 2종: 조건 하나만 끄는 패치로 기대 칸만 빨강일 때만 검출(FT_CASES=M) ──
if [ "${FT_CASES:-all}" = M ] && [ -z "${FT_MUT_CHILD:-}" ]; then
  mut() { # <이름> <sed 식> <기대 FAIL 정규식> — FT_MUTS 로 그 이름만(시험 1개 70초 · 하드 룰 22)
    case "${FT_MUTS:-}" in ''|*"$1"*) ;; *) return 0;; esac
    local m="$T/mut-$1" nf nx r
    mkdir -p "$m"; cp "$SUT" "$m/ft-scratch-repo.sh"
    for f in _scratch_keep.sh ft-heavy-slot-lib.sh ft-harness-root.sh ft-bg-finite.sh; do cp "$(dirname -- "$SUT")/$f" "$m/$f" 2>/dev/null || { bad "변이 $1 곁 파일 $f 없음"; return; }; done   # r1286 뒤 bin 은 곁 파일 4개를 source 한다
    sed -i '' -e "$2" "$m/ft-scratch-repo.sh" 2>/dev/null || { bad "변이 $1 sed 실패"; return; }
    cmp -s "$SUT" "$m/ft-scratch-repo.sh" && { bad "변이 $1 이 안 바뀜"; return; }
    bash -n "$m/ft-scratch-repo.sh" 2>/dev/null || { bad "변이 $1 문법 깨짐(가짜 변이)"; return; }
    FT_MUT_CHILD=1 FT_CELLS=rs2 FT_CASES=none FT_SUT="$m/ft-scratch-repo.sh" bash "${BASH_SOURCE[0]}" > "$T/mut-$1.log" 2>&1; r=$?
    nf="$(grep -c '^FAIL' "$T/mut-$1.log")"; nx="$(grep -cE "^FAIL ($3)" "$T/mut-$1.log")"
    { [ "$r" != 0 ] && [ "$nf" -gt 0 ] && [ "$nf" = "$nx" ]; } && ok "변이 $1 → 기대 칸만 빨강($3 · ${nf}칸)" \
      || bad "변이 $1 이 기대 칸으로 안 잡힘(rc=$r · FAIL $nf · 기대 $nx) $(grep '^FAIL' "$T/mut-$1.log" | head -2 | tr '\n' ' ')"
  }
  mut rc2-star 's#^      2) UNK=\$((UNK+1))#      9) UNK=$((UNK+1))#' 'S1|S1b|S2|S4'   # S4 도 갈린다: 옛 갈래는 첫 항목 rc2 에서 먼저 멈춰 «시계 못 읽음 · 남은 항목 삭제 0» 문구(루프 첫머리 시계)에 이르지 못한다
  mut cons3-off 's#\[ "\$URUN" -ge 3 \]#[ "$URUN" -ge 999 ]#' 'S2'
fi

[ $fail -eq 0 ] && echo "ALL PASS" || echo "($fail failed)"
exit $fail
