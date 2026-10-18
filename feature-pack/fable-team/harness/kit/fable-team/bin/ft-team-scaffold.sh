#!/usr/bin/env bash
# ft-team-scaffold.sh [--dry-run] <팀>   (R318a · 팀 폴더 빈 틀)
#   design/TEAMS.md 에 있는 팀의 design/<팀>/ 에 «없는 칸만» 만든다(있는 파일·폴더는 건드리지 않음 · 멱등).
#   틀 = 키트 templates/team/ (자리표시 `<팀>` 만 · 프로젝트 기록 0) · 빈 폴더는 .gitkeep.
#   env: FT_REPO_ROOT(기본 git 루트) · FT_TEAM_TEMPLATE_DIR(기본 <키트>/templates/team).
#   exit 0 = 완료 · 1 = REJECT · 2 = usage
set -uo pipefail
DRY=0; TEAM=""
while [ $# -gt 0 ]; do case "$1" in --dry-run) DRY=1; shift;; -*) echo "unknown $1" >&2; exit 2;; *) [ -z "$TEAM" ] && TEAM="$1" || { echo "usage: $0 [--dry-run] <팀>" >&2; exit 2; }; shift;; esac; done
[ -n "$TEAM" ] || { echo "usage: $0 [--dry-run] <팀>" >&2; exit 2; }
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="${FT_REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -n "$ROOT" ] && [ -d "$ROOT/design" ] || { echo "REJECT 리포 루트(design/)를 못 찾았다" >&2; exit 1; }
[[ "$TEAM" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || { echo "REJECT 팀 이름 형식 틀림(소문자·숫자·-·_): $TEAM"; exit 1; }
TEAMS="$ROOT/design/TEAMS.md"
[ -f "$TEAMS" ] || { echo "REJECT design/TEAMS.md 없음 — 팀 명단이 먼저다"; exit 1; }
grep -qE "\|[[:space:]]*\`?design/${TEAM}/\`?[[:space:]]*\|" "$TEAMS" || { echo "REJECT $TEAM 은 design/TEAMS.md 명단에 없는 팀이다 — 명단에 행을 먼저 추가"; exit 1; }
TPL="${FT_TEAM_TEMPLATE_DIR:-}"
[ -n "$TPL" ] || for c in "$HERE/../templates/team" "$ROOT/scripts/harness-install/fable-team/templates/team"; do [ -d "$c" ] && { TPL="$c"; break; }; done
[ -d "$TPL" ] || { echo "REJECT 빈 틀 폴더 없음: ${TPL:-<없음>}"; exit 1; }
# 틀 파일(VERSION 제외) 0 인 폴더는 조용히 «0건 완료» 하지 않는다 — R368 설치가 라이브엔 VERSION 1파일만 복사한 사건(R377 · #0 RULE)
[ -n "$(find "$TPL" -type f ! -name VERSION -print -quit)" ] || { echo "REJECT 틀 파일 0: $TPL (후보: $HERE/../templates/team · $ROOT/scripts/harness-install/fable-team/templates/team)"; exit 1; }
DEST="$ROOT/design/$TEAM"; N=0; VERB=CREATE; [ "$DRY" = 1 ] && VERB=WOULD-CREATE
[ -L "$DEST" ] && { echo "REJECT 팀 폴더가 심볼릭 링크: design/$TEAM"; exit 1; }
RDESIGN="$(cd -P "$ROOT/design" && pwd -P)"
# 만들 경로의 «실제» 위치가 design/<팀>/ 안인가 — 가장 가까운 기존 조상을 realpath 로 푼다(링크 탈출·dangling 링크 차단 · DA⑥ r1 H2)
inside() { local p="$1" r; while [ ! -e "$p" ] && [ ! -L "$p" ]; do p="$(dirname "$p")"; done
  r="$(cd -P "$p" 2>/dev/null && pwd -P)" || return 1
  # design/ 자체는 팀 폴더가 아직 없을 때(조상이 design/ 로 올라간 정상 경우)만 허용 — 팀 폴더가 있는데 design/ 로 풀리면 하위 링크 탈출(r318a DA⑥ r3 H2)
  [ "$r" = "$RDESIGN" ] && [ ! -e "$DEST" ] && return 0
  [ "$r" = "$RDESIGN/$TEAM" ] || case "$r" in "$RDESIGN/$TEAM/"*) return 0;; *) return 1;; esac; }
while IFS= read -r rel; do
  out="$rel"; case "$out" in GOAL-TEAM.md) out="GOAL-$TEAM.md";; GUIDE-TEAM.md) out="GUIDE-$TEAM.md";; esac
  tgt="$DEST/$out"
  if [ -L "$tgt" ]; then echo "SKIP design/$TEAM/$out — 심볼릭 링크라 손대지 않는다"; continue; fi
  [ -e "$tgt" ] && continue
  inside "$(dirname "$tgt")" || { echo "SKIP design/$TEAM/$out — 실제 위치가 design/$TEAM/ 밖(링크)이라 만들지 않는다"; continue; }
  case "$out" in */.gitkeep|.gitkeep) [ -d "$(dirname "$tgt")" ] && [ -n "$(ls -A "$(dirname "$tgt")" 2>/dev/null)" ] && continue;; esac   # 이미 파일이 든 폴더엔 .gitkeep 불필요
  if [ "$DRY" = 0 ]; then
    mkdir -p "$(dirname "$tgt")"
    sed "s/<팀>/$TEAM/g" "$TPL/$rel" > "$tgt"
  fi
  echo "$VERB design/$TEAM/$out"; N=$((N+1))
done < <(cd "$TPL" && find . -type f ! -path ./VERSION | sed 's|^\./||' | LC_ALL=C sort)
[ "$DRY" = 1 ] && echo "OK dry-run would-create=$N" || echo "OK created=$N"
# 틀 버전(templates/team/VERSION)을 명부 _tree_version 에 기록 — ft-team-upgrade.sh 가 부를 땐 스스로 기록하므로 건너뛴다(R368)
if [ "$DRY" = 0 ] && [ -z "${FT_TEAM_NO_STAMP:-}" ] && [ -f "$HERE/ft-team-upgrade.sh" ]; then
  FT_REPO_ROOT="$ROOT" FT_TEAM_TEMPLATE_DIR="$TPL" bash "$HERE/ft-team-upgrade.sh" --stamp "$TEAM" || exit 1
fi
