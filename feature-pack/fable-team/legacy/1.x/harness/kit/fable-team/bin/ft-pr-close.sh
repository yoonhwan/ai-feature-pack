#!/usr/bin/env bash
# ft-pr-close.sh <slug> <PR> <본문 파일> — r1987: 사람 실행 h 의 PR 코멘트+닫기 = 착지 도구와 같은 쓰기 신원 표(ft-merge-lib.sh fm_pr_close 그대로)
#   slug 가 FT_PR_CLOSE_AS_USER(기본 yoonhwan/ai-feature-pack)에 있으면 사람 gh(GH_TOKEN·GITHUB_TOKEN 비움) · 그 밖은 ft-gh-as-tank.sh · 시도당 7초 + 재시도 1
#   rc0 = 닫음 · 실패 = fm_pr_close rc 그대로 + stderr «ERROR …» 1줄(갈아타기 0) · usage(인자·PR 번호·본문 파일) rc2 · gh 호출 0 · FT_GH/FT_GH_WRITE = 시험 주입
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
[ $# = 3 ] && [ -n "$1" ] && [[ "$2" =~ ^[0-9]+$ ]] && [ -f "$3" ] || { echo "usage: ft-pr-close.sh <slug> <PR 번호> <본문 파일>" >&2; exit 2; }
. "$HERE/ft-merge-lib.sh" || { echo "ERROR ft-merge-lib.sh 못 읽음 — 닫기 0" >&2; exit 1; }
o="$(fm_pr_close "$1" "$2" "$3" "${FT_GH_WRITE:-$HERE/ft-gh-as-tank.sh}" 2>&1)"; rc=$?
[ "$rc" = 0 ] && { printf '%s\n' "$o"; exit 0; }
echo "ERROR PR #$2 닫기 실패 rc=$rc($1) — $(printf '%s' "$o" | tail -n1 | cut -c1-160)" >&2
exit "$rc"
