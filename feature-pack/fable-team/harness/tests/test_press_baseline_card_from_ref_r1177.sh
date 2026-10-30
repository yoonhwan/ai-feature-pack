#!/usr/bin/env bash
# test_press_baseline_card_from_ref_r1177.sh — r1177 press 기준선 검사: 작업 트리(세트 sha)에 카드 없음 → FT_CARD_REF(기본 origin/main) 판으로 검사.
#   계기: feature #202777 — press 카드가 세트 sha 뒤에 main 착지 → 게이트 ⑥ «카드: 파일 없음» → tester 가 사본으로 우회.
#   입력: 임시 git 리포(A = 세트 · B = A + press 카드 · refs/remotes/origin/main = B · 작업 트리 = A detached) · 실 리포·press 0.
#   반례 R1~R5(카드 «반례 집합») + 변이 1(ref 분기 삭제 → R1 BLOCK = FAIL). 자기 파일 재호출 0(guard 재실행은 RSG_ACTIVE 표지).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"
CHK="$BIN/ft-press-baseline-check.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
bash -n "$CHK" && ok "bash -n baseline-check" || bad "bash -n baseline-check"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
R="$T/repo"; mkdir -p "$R/worker" "$R/design/v65/baselines" "$R/cards" "$T/tmp"
export TMPDIR="$T/tmp"   # 임시 카드 잔류 검사를 이 시험 폴더로 좁힌다(동시 좌석 파일 0)
git -C "$R" init -q && git -C "$R" config user.email t@t && git -C "$R" config user.name t
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| v65 | `design/v65/` | x | 현역 |\n' > "$R/design/TEAMS.md"
printf '| key | 기본값 | OFF 값 | 읽는 자리 |\n|---|---|---|---|\n| `V65_TOGGLE_A` | `1` | `0` | worker/a.py:1 |\n' > "$R/design/v65/baselines/FLAGS.md"
echo 'x = 1' > "$R/worker/a.py"
git -C "$R" add -A && git -C "$R" commit -qm set
A="$(git -C "$R" rev-parse HEAD)"
card() { # 파일 [빼거나 바꿀 줄: 키=값 | -키] → 기준선 self 카드
  local f="$1"; shift
  local -A v=([기준선]=self [종류]=기준선 [회차]=1 [실험]=없음 [프로필]=default-3bubble)
  local a; for a in "$@"; do case "$a" in -*) v[${a#-}]="__DROP__" ;; *) v[${a%%=*}]="${a#*=}" ;; esac; done
  mkdir -p "$(dirname "$f")"; : > "$f"; local k; for k in 기준선 종류 회차 실험 프로필; do [ "${v[$k]}" = "__DROP__" ] || echo "$k: ${v[$k]}" >> "$f"; done
}
commit_card() { # 이름 [card 인자…] → 그 카드를 A 위에 커밋한 sha (작업 트리는 다시 A)
  local name="$1"; shift
  git -C "$R" checkout -q --detach "$A" && card "$R/cards/press.md" "$@" && git -C "$R" add -A && git -C "$R" commit -qm "$name" && git -C "$R" rev-parse HEAD
}
B="$(commit_card good)"; C="$(commit_card bad-exp 실험=V65_TOGGLE_A=0)"; D="$(commit_card no-base -기준선)"
for c in "$B" "$C" "$D"; do [[ "$c" =~ ^[0-9a-f]{40}$ ]] || { bad "fixture: 카드 커밋 못 만듦($c)"; exit 1; }; done
git -C "$R" update-ref refs/remotes/origin/main "$B"
git -C "$R" checkout -q --detach "$A"
[ ! -e "$R/cards/press.md" ] && ok "fixture: 작업 트리(A)에 카드 없음" || bad "fixture: 작업 트리에 카드가 남음"

run() { OUT="$(env "$@" bash "$CHK_RUN" --card "$CARD_IN" --repo "${REPO_IN:-$R}" 2>&1)"; RC=$?; }
has() { printf '%s\n' "$OUT" | grep -qF -- "$1"; }
CHK_RUN="$CHK"; CARD_IN="$R/cards/press.md"

# R1 feature 꼴: 작업 트리에 없음 · origin/main 에 있음 → INFO 출처 + OK rc0
run -u FT_CARD_REF
{ [ "$RC" -eq 0 ] && has "INFO 카드 출처 = origin/main:cards/press.md" && has "OK 기준선 self"; } && ok "R1 ref 판 통과 rc0" || bad "R1 rc=$RC: $OUT"
# R1b 상대 경로(cwd = 리포 밖)도 같은 rel 로 ref 판을 찾는다
CARD_IN="cards/press.md"; run -u FT_CARD_REF
{ [ "$RC" -eq 0 ] && has "INFO 카드 출처 = origin/main:cards/press.md"; } && ok "R1b 상대 경로 rc0" || bad "R1b rc=$RC: $OUT"
CARD_IN="$R/cards/press.md"
# R1c --repo 끝 슬래시(DA① r1177) → 리포 안 절대 경로로 읽혀 ref 판 통과
REPO_IN="$R/"; run -u FT_CARD_REF; REPO_IN=""
{ [ "$RC" -eq 0 ] && has "INFO 카드 출처 = origin/main:cards/press.md"; } && ok "R1c --repo 끝 슬래시 rc0" || bad "R1c rc=$RC: $OUT"
# R2작업 트리에 카드 있음 · ref 판은 머리줄 다름 → 작업 트리 판 판정 · INFO 줄 0
card "$R/cards/press.md"; run FT_CARD_REF="$C"
{ [ "$RC" -eq 0 ] && ! has "INFO 카드 출처"; } && ok "R2 작업 트리 판 우선 rc0 · INFO 0" || bad "R2 rc=$RC: $OUT"
rm -f "$R/cards/press.md"
# R3 둘 다 없음 → BLOCK «에도 없음» rc1
CARD_IN="$R/cards/none.md"; run -u FT_CARD_REF
{ [ "$RC" -eq 1 ] && has "BLOCK 카드: 파일 없음($R/cards/none.md) · origin/main 에도 없음"; } && ok "R3 둘 다 없음 rc1" || bad "R3 rc=$RC: $OUT"
CARD_IN="$R/cards/press.md"
# R4 ref 판 카드 머리줄 틀림(기준선 줄 없음) → 같은 검사로 BLOCK rc1
run FT_CARD_REF="$D"
{ [ "$RC" -eq 1 ] && has "INFO 카드 출처 = $D:cards/press.md" && has "BLOCK 카드 기준선: 머리줄 없음"; } && ok "R4 ref 판도 같은 검사 rc1" || bad "R4 rc=$RC: $OUT"
# R5 없는 ref → BLOCK rc1 · 침묵 통과 0
run FT_CARD_REF=refs/remotes/origin/nope
{ [ "$RC" -eq 1 ] && has "refs/remotes/origin/nope 에도 없음" && ! has "OK "; } && ok "R5 없는 ref rc1" || bad "R5 rc=$RC: $OUT"
# 임시 카드 파일이 남지 않는다
ls "${TMPDIR:-/tmp}"/ft-press-card.* >/dev/null 2>&1 && bad "임시 카드 파일 잔류" || ok "임시 카드 파일 0"

# 변이: ref 분기 삭제(옛 줄로 되돌림) → R1 이 BLOCK 이어야 시험이 그 분기를 잡는다
M="$T/mbin"; mkdir -p "$M"; cp "$BIN/ft-team-lib.sh" "$M/"
sed 's/^\[ -f "\$CARD" \] || card_from_ref$/[ -f "$CARD" ] || { block "카드: 파일 없음($CARD)"; finish ""; }/' "$CHK" > "$M/ft-press-baseline-check.sh"
if cmp -s "$CHK" "$M/ft-press-baseline-check.sh"; then bad "변이: 치환 0(대상 줄 못 찾음)"; else
  CHK_RUN="$M/ft-press-baseline-check.sh"; run -u FT_CARD_REF
  [ "$RC" -ne 0 ] && ok "변이 ref 분기 삭제 → R1 막힘(rc=$RC) = 시험이 잡음" || bad "변이 살아남음: $OUT"
fi

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
