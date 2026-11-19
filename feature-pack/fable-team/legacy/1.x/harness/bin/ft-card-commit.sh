#!/usr/bin/env bash
# ft-card-commit.sh <가지> "<커밋 글>" <경로>=<로컬 파일> | +<경로>=<덧붙일 파일> | -<경로> …
#   r2278: 카드(design/**) 고침을 worktree · checkout · 작업 폴더 0 으로 커밋 · push 한다(원 리포 index · 작업 폴더 글자 0).
#   fetch 1회 → 임시 GIT_INDEX_FILE 로 origin/<가지> 위 커밋 1개 → push(force 0 · 7초 · 실패면 fetch 뒤 새 끝에서 1회 더).
#   가지 = ops/main-base · docs/* 만(main · 그 밖 = REJECT · 착지 게이트 우회 0) · 경로 = design/** 만 · REJECT = push 0.
#   쓰기 전 검사: .md·.txt·.tsv·.json = UTF-8 · design/**/indices/**.md = ft-index-lint 를 «고치기 전 판» · «바뀐 판» 두 번
#     (입력 = 그 카드 · 원장 · design/TEAMS.md 는 origin/<가지> tree 에서, 팀 env 는 리포 .fable-team/bin-<팀> 에서 임시 git init 폴더로)
#     → 두 사유 목록 diff 의 «새 사유» 0 일 때만 push · 원장을 못 정하거나 가지에 없음 = 판정 불가(거짓 통과 0).
#   출력: 성공 = «PUSHED <sha40> base=<sha40>» + diff --stat · rc 0 성공 · 1 REJECT · 2 usage · 3 «판정 불가 <단계>»(하드 룰 20)
#   env: FT_CARD_LINT = lint 경로(기본 = <리포>/.fable-team/LIVE_BIN 이 가리키는 폴더의 ft-index-lint.sh)
set -uo pipefail
die() { echo "판정 불가 $1"; exit 3; }
rej() { echo "REJECT $1"; exit 1; }
[ $# -ge 3 ] || { echo "usage: $0 <가지> \"<커밋 글>\" <경로>=<파일> | +<경로>=<파일> | -<경로> …" >&2; exit 2; }
B="$1" MSG="$2"; shift 2; SPECS=("$@")
command -v git >/dev/null 2>&1 || die git
t7() { perl -e 'alarm shift @ARGV; exec @ARGV or exit 127' 7 "$@"; }   # 외부 호출 1회 7초(하드 룰 12)
case "$B" in
  ops/main-base) ;;
  docs/?*) git check-ref-format "refs/heads/$B" || rej "가지 이름 꼴 ($B)";;
  *) rej "가지 허용 목록 밖 ($B · 허용 = ops/main-base · docs/*)";;
esac
parse() {  # $1=spec → OP P F
  local r; OP="="; r="$1"
  case "$1" in -*) OP=-; r="${1#-}";; +*) OP=+; r="${1#+}";; esac
  P="$r" F=""
  if [ "$OP" != - ]; then
    [[ "$r" == *=* ]] || rej "꼴 ($1 · <경로>=<파일>)"
    P="${r%%=*}" F="${r#*=}"; [ -f "$F" ] || rej "로컬 파일 없음 ($F)"
  fi
  case "/$P/" in *//*|*/./*|*/../*) rej "경로 꼴 ($P)";; esac
  case "$P" in design/?*) ;; *) rej "경로 design/** 밖 ($P)";; esac
}
for s in "${SPECS[@]}"; do parse "$s"; done
COMMON="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || die repo
MAIN_ROOT="${COMMON%/.git}"
LINT="${FT_CARD_LINT:-$(cat "$MAIN_ROOT/.fable-team/LIVE_BIN" 2>/dev/null)/ft-index-lint.sh}"
T="$(mktemp -d)" || die mktemp; trap 'rm -rf "$T"' EXIT
fetch() {
  { t7 git fetch -q origin "+refs/heads/$B:refs/remotes/origin/$B" || t7 git fetch -q origin "+refs/heads/$B:refs/remotes/origin/$B"; } >/dev/null 2>&1 || die fetch
  BASE="$(git rev-parse -q --verify "refs/remotes/origin/$B^{commit}")" || die fetch
}
run_lint() {  # $1=카드 판 파일 $2=사유 목록 파일 (LW · LP · LED 사용)
  local out rc
  mkdir -p "$LW/$(dirname "$LP")" && cp "$1" "$LW/$LP" || die lint-copy
  out="$(cd "$LW" && FT_GOAL_LEDGER="$LED" bash "$LINT" "$LP" 2>&1)"; rc=$?   # rc 를 따로 받는다(파이프 뒤 && 0)
  [ "$rc" -le 1 ] || die "lint rc=$rc ($LP)"
  printf '%s\n' "$out" | sed -n 's/^  - //p' | sort -u > "$2"
}
lint_card() {  # $1=경로 $2=바뀐 판 파일 → 새 사유 0 이면 돌아옴 · 아니면 REJECT
  local t="" e x new om
  [ -f "$LINT" ] || die "lint 없음 ($LINT)"
  LP="$1" LW="$T/lint"; rm -rf "$LW"; git init -q "$LW" >/dev/null 2>&1 || die lint-init
  printf '%s\n' "$COMMON/objects" > "$LW/.git/objects/info/alternates" || die lint-alternates   # 원 리포 객체를 빌려 본다(복사 · fetch 0)
  om="$(git rev-parse -q --verify refs/remotes/origin/main)" && { git -C "$LW" update-ref refs/remotes/origin/main "$om" || die lint-origin-main; }   # 카드 번호 검사 · origin/main tree 폴백이 원 리포와 같은 판을 본다(DA#29 H1)
  case "$LP" in */indices/*) t="${LP%/indices/*}"; t="${t##*/}";; esac
  e="$MAIN_ROOT/.fable-team/bin-$t/$t-env.sh"
  LED="$(grep -oE '<!-- *ledger: *[^ >]+ *-->' "$2" | head -1 | sed -E 's/<!-- *ledger: *([^ >]+) *-->/\1/')"
  [ -n "$LED" ] || LED="$( [ -f "$e" ] && . "$e" >/dev/null 2>&1; printf '%s' "${FT_GOAL_LEDGER:-}" )"
  [ -n "$LED" ] || die "lint-원장 (카드 머리 ledger · 팀 env FT_GOAL_LEDGER 둘 다 없음 · $LP)"
  [ ! -f "$e" ] || { mkdir -p "$LW/.fable-team/bin-$t" && cp "$e" "$LW/.fable-team/bin-$t/"; } || die lint-env
  for x in "$LED" design/TEAMS.md; do
    git cat-file -e "$BASE:$x" 2>/dev/null || { [ "$x" = design/TEAMS.md ] && continue; die "lint-원장 ($LED · origin/$B 에 없음)"; }
    mkdir -p "$LW/$(dirname "$x")" && git cat-file blob "$BASE:$x" > "$LW/$x" || die lint-input
  done
  : > "$T/r0"
  if git cat-file -e "$BASE:$LP" 2>/dev/null; then git cat-file blob "$BASE:$LP" > "$T/before" || die lint-input; run_lint "$T/before" "$T/r0"; fi
  run_lint "$2" "$T/r1"
  new="$(comm -13 "$T/r0" "$T/r1")"
  [ -z "$new" ] || { echo "REJECT lint 새 사유 ($LP)"; printf '%s\n' "$new" | sed 's/^/  - /'; exit 1; }
}
build() {  # origin/<가지> 끝(BASE) 위 커밋 1개 → NEW · TREE
  local idx="$T/index" n=0 s c blob
  rm -f "$idx"; GIT_INDEX_FILE="$idx" git read-tree "$BASE" || die read-tree
  for s in "${SPECS[@]}"; do
    parse "$s"; n=$((n+1))
    case "$OP" in
      -) git cat-file -e "$BASE:$P" 2>/dev/null || rej "지울 경로가 origin/$B 에 없음 ($P)"
         GIT_INDEX_FILE="$idx" git update-index --force-remove -- "$P" || die update-index; continue;;
      +) c="$T/c$n"; { git cat-file blob "$BASE:$P" 2>/dev/null; cat "$F"; } > "$c";;
      *) c="$F";;
    esac
    case "$P" in *.md|*.txt|*.tsv|*.json)
      python3 -c 'import sys; sys.stdin.buffer.read().decode("utf-8")' < "$c" 2>/dev/null || rej "UTF-8 아님 ($P)";; esac
    case "$P" in design/*/indices/*.md) lint_card "$P" "$c";; esac
    blob="$(git hash-object -w -- "$c")" || die hash-object
    GIT_INDEX_FILE="$idx" git update-index --add --cacheinfo "100644,$blob,$P" || die update-index
  done
  TREE="$(GIT_INDEX_FILE="$idx" git write-tree)" || die write-tree
  NEW="$(printf '%s\n' "$MSG" | git commit-tree "$TREE" -p "$BASE")" || die commit-tree
}
push() { t7 git push -q origin "$NEW:refs/heads/$B" >/dev/null 2>&1; }
fetch; build
[ "$TREE" != "$(git rev-parse "$BASE^{tree}")" ] || { echo "NOCHANGE base=$BASE"; exit 0; }
if ! push; then
  OLD="$BASE"; fetch
  [ "$BASE" = "$OLD" ] || build   # 원격이 앞섬 → 새 끝 위에 다시(검사 포함)
  push || die push
fi
echo "PUSHED $NEW base=$BASE"
git diff --stat "$BASE" "$NEW"
