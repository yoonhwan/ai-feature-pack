#!/usr/bin/env bash
# ft-branch-candidates.sh [--remote] [--base REF] [--out FILE] [--repo DIR]
#   C18 · 브랜치 정리 «후보 목록»만 만든다(읽기 전용). 브랜치·워크트리·tmux 를 지우거나 바꾸는 명령은 쓰지 않는다 —
#   쓰는 git 은 rev-parse · for-each-ref · worktree list · merge-base --is-ancestor · cherry 뿐. 삭제는 HIL(오빠 승인) 몫이다.
#   기본 = 로컬 브랜치 · --remote = origin/* 원격 브랜치. 산출 = <issues 팀 폴더>/BRANCH-CANDIDATES.md (TEAMS.md 폴더 칸 · --out 으로 변경).
#   exit 0 = 목록 생성 · 2 = usage/저장소 아님. 환경: FT_BRANCH_RECENT_DAYS(기본 7) · FT_BRANCH_PROTECT(보호 정규식) · FT_BRANCH_NOW(시험용 epoch).
set -uo pipefail
REMOTE=0; BASE=""; OUT=""; REPO="."
while [ $# -gt 0 ]; do case "$1" in
  --remote) REMOTE=1; shift;;
  --base|--out|--repo) [ $# -ge 2 ] || { echo "usage: $1 <값>" >&2; exit 2; }
    case "$1" in --base) BASE="$2";; --out) OUT="$2";; --repo) REPO="$2";; esac; shift 2;;
  *) echo "usage: $0 [--remote] [--base REF] [--out FILE] [--repo DIR]" >&2; exit 2;; esac; done
G() { git -C "$REPO" "$@"; }
G rev-parse --git-dir >/dev/null 2>&1 || { echo "REJECT git 저장소 아님: $REPO" >&2; exit 2; }
TOP="$(G rev-parse --show-toplevel)"
if [ -z "$OUT" ]; then   # R382b: issues 팀 폴더는 TEAMS.md 폴더 칸으로 푼다(리터럴 0)
  . "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/ft-team-lib.sh"; _IT="$(ft_team_in "$TOP" issues)" || exit 2; OUT="$_IT/BRANCH-CANDIDATES.md"
fi
if [ -z "$BASE" ]; then G rev-parse --verify -q refs/remotes/origin/main >/dev/null && BASE=origin/main || BASE=main; fi
G rev-parse --verify -q "$BASE^{commit}" >/dev/null || { echo "REJECT 기준 브랜치 없음: $BASE" >&2; exit 2; }
BASE_SHORT="${BASE#origin/}"; BASE_SHA="$(G rev-parse --short=10 "$BASE")"
RECENT="${FT_BRANCH_RECENT_DAYS:-7}"; PROTECT="${FT_BRANCH_PROTECT:-^(main|master|v65)$}"; NOW="${FT_BRANCH_NOW:-$(date +%s)}"
if [ "$REMOTE" -eq 1 ]; then PFX="refs/remotes/origin/"; SCOPE="원격(origin)"; else PFX="refs/heads/"; SCOPE="로컬"; fi
WT_BRANCHES="$(G worktree list --porcelain 2>/dev/null | sed -n 's|^branch refs/heads/||p')"
TAB="$(printf '\t')"; ROWS="$(mktemp)"; REFS="$(mktemp)"; MERGED="$(mktemp)"; CH="$(mktemp)"
trap 'rm -f "$ROWS" "$REFS" "$MERGED" "$CH"' EXIT
JOBS="${FT_BRANCH_JOBS:-8}"; export REPO BASE   # cherry 는 브랜치당 ~1초(main 쪽 패치 수만큼) — 병렬로 돌린다
G for-each-ref --format='%(refname)%09%(committerdate:unix)%09%(committerdate:short)' "$PFX" > "$REFS"
G for-each-ref --merged="$BASE" --format='%(refname)' "$PFX" > "$MERGED"   # 조상(merge-base --is-ancestor 와 같은 판정) 한 번에

# 활동·보호·워크트리로 어차피 KEEP 인 브랜치는 cherry 를 생략한다 — 사유가 비면 KEEP 사유 없음
keep_why() {
  if echo "$1" | grep -Eq "$PROTECT"; then echo "보호 브랜치"
  elif [ "$2" -lt "$RECENT" ]; then echo "최근 활동 ${2}일 전"
  elif [ "$REMOTE" -eq 0 ] && echo "$WT_BRANCHES" | grep -qxF "$1"; then echo "워크트리 사용 중"; fi
}
while IFS="$TAB" read -r ref ct day; do
  name="${ref#"$PFX"}"; [ "$name" = "HEAD" ] || [ "$name" = "$BASE_SHORT" ] && continue
  grep -qxF "$ref" "$MERGED" && continue; [ -n "$(keep_why "$name" $(( (NOW - ct) / 86400 )))" ] && continue
  echo "$ref"
done < "$REFS" | xargs -P "$JOBS" -I{} bash -c 'printf "%s\t%s\n" "{}" "$(git -C "$REPO" cherry "$BASE" "{}" | grep -c "^+")"' > "$CH"

while IFS="$TAB" read -r ref ct day; do
  name="${ref#"$PFX"}"; [ "$name" = "HEAD" ] || [ "$name" = "$BASE_SHORT" ] && continue
  if grep -qxF "$ref" "$MERGED"; then landed="조상(main 에 있음)"; un=0
  else plus="$(awk -F'\t' -v r="$ref" '$1==r{print $2}' "$CH")"
    if [ -n "$plus" ]; then un="$plus"; [ "$un" -eq 0 ] && landed="내용 동일(cherry)" || landed="미랜딩"
    else un="$(G rev-list --count "$BASE..$ref")"; landed="미랜딩(cherry 생략)"; fi; fi
  age=$(( (NOW - ct) / 86400 )); w="$(keep_why "$name" "$age")"
  if [ -n "$w" ]; then cls=KEEP; why="$w"
  elif [ "$un" -gt 0 ]; then cls=KEEP; why="미랜딩 커밋 $un"
  elif [ "$landed" = "조상(main 에 있음)" ]; then cls=SAFE; why="main 조상 · 미랜딩 0 · ${age}일 무활동"
  else cls=REVIEW; why="조상은 아니나 cherry 상 내용 동일(재작성/스쿼시 의심) · 사람 확인"; fi
  case "$cls" in SAFE) o=1;; REVIEW) o=2;; *) o=3;; esac
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$o" "$cls" "$name" "$landed" "$un" "$day" "$why" "$ct"
done < "$REFS" | sort -t "$TAB" -k1,1n -k8,8nr > "$ROWS"

cnt() { awk -F'\t' -v c="$1" '$2==c' "$ROWS" | wc -l | tr -d ' '; }
TOTAL="$(wc -l < "$ROWS" | tr -d ' ')"; mkdir -p "$(dirname "$OUT")"
{
  echo "# 브랜치 정리 후보 목록 ($SCOPE) — 읽기 전용 · 삭제 0"
  echo
  echo "분류 기준 3줄:"
  echo "- **SAFE** = main 에 내용 있음(조상) + 미랜딩 커밋 0 + 최근 ${RECENT}일 활동 없음 + 워크트리 미사용"
  echo "- **KEEP** = 미랜딩 커밋 있음 · 최근 ${RECENT}일 활동 · 워크트리 사용 중 · 보호 브랜치(\`$PROTECT\`)"
  echo "- **REVIEW** = 그 외(미랜딩 0 이나 조상이 아님 — 리베이스·재작성 가능성, 사람이 본다)"
  echo
  echo "기준 = \`$BASE\` @ $BASE_SHA · 생성 $(date -u -r "$NOW" +%FT%TZ 2>/dev/null || date -u +%FT%TZ) · 분모 **$TOTAL** (SAFE $(cnt SAFE) · REVIEW $(cnt REVIEW) · KEEP $(cnt KEEP))"
  echo
  echo "| 브랜치 | 랜딩 여부 | 미랜딩 커밋 수 | 마지막 커밋 | 분류 | 근거 |"
  echo "|---|---|---|---|---|---|"
  awk -F'\t' '{printf "| `%s` | %s | %s | %s | %s | %s |\n", $3, $4, $5, $6, $2, $7}' "$ROWS"
  echo
  echo "## 사람이 실행할 명령 — SAFE 만 (이 스크립트는 실행하지 않는다 · 오빠 승인 후 사람이 실행)"
  echo '```'
  if [ "$REMOTE" -eq 1 ]; then awk -F'\t' '$2=="SAFE"{printf "git push origin --delete \047%s\047\n", $3}' "$ROWS"
  else awk -F'\t' '$2=="SAFE"{printf "git branch -d \047%s\047\n", $3}' "$ROWS"; fi
  echo '```'
} > "$OUT"
echo "WROTE $OUT total=$TOTAL SAFE=$(cnt SAFE) REVIEW=$(cnt REVIEW) KEEP=$(cnt KEEP)"
