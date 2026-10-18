#!/usr/bin/env bash
# ft-index-lint-install.sh <카드> — ft-index-lint.sh ⑩ (R245 병합 ≠ 끝): design/harness/indices/ 카드의 `- 설치: 있음|없음` 줄 검사.
#   exit 0 = OK(또는 범위 밖: 다른 팀 indices) · 1 = REJECT(사유 1줄 stdout). 구현 범위가 키트·도구를 건드리는데 «없음» 이면 REJECT.
set -uo pipefail
F="${1:-}"; [ -f "$F" ] || exit 0
# R383: 하네스 팀 카드 판정 = 팀 폴더 명단(ft_team_has · 쌍둥이 둘 다) · 명단은 카드가 있는 워크트리의 것 · 못 읽으면 «범위 밖» 으로 후퇴하지 않고 REJECT
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/ft-team-lib.sh" || { echo "ft-team-lib.sh 를 못 읽었다 — 하네스 카드 판정 불가"; exit 1; }
FT_REPO_ROOT="$(git -C "$(dirname "$F")" rev-parse --show-toplevel 2>/dev/null)" ft_team_has harness "$(cd "$(dirname "$F")" && pwd)/" indices/; _hrc=$?
case "$_hrc" in 0) ;; 1) exit 0;; *) echo "하네스 팀 폴더를 못 풀었다(design/TEAMS.md) — 카드 종류 판정 불가"; exit 1;; esac
val="$(sed -nE 's/^[[:space:]]*-[[:space:]]*설치:[[:space:]]*(.*)$/\1/p' "$F" | head -1)"
case "$val" in
  있음*) exit 0;;
  없음*) ;;
  *) echo "「- 설치: 있음|없음」 줄 없음 또는 값 오류 (R245 병합 ≠ 끝 — 하네스 키트·도구·훅·데몬을 바꾸면 있음)"; exit 1;;
esac
if awk 'index($0,"## 구현 범위")==1{f=1;next} /^## /{f=0} f' "$F" | grep -qE 'scripts/harness-install/|fable-team-bin/'; then
  echo "설치: 없음인데 구현 범위가 scripts/harness-install/ 또는 fable-team-bin/ 를 건드린다 — 「설치: 있음」으로"; exit 1
fi
