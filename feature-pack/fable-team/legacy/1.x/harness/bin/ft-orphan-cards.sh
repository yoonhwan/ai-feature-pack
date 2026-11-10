#!/usr/bin/env bash
# ft-orphan-cards.sh — 진행/ 카드 중 tmux 세션이 없는 «고아 카드» 목록(읽기 전용 · 이동 0 · 삭제 0 · kill 0)
#   출력(stdout) = 팀<TAB>카드<TAB>기대 세션 패턴 — 고아 1건당 1행. 요약은 stderr 1줄(팀별 고아/전체).
#   카드 ↔ 세션: 카드 파일명(slug)이 세션명에 «-<slug>#» 로 들어 있으면 살아 있는 것(대소문자 무시 · 접두사는 팀마다 다르다).
#   스캔 대상: <리포 루트>/design/*/indices/진행 + FT_ORPHAN_EXTRA_DIRS(공백 구분 «팀=경로») — cfo 카드는 루트가 아니라 c-level-planning 워크트리에 있다.
#   tmux 실패는 «서버 없음(rc=1 · no server running)» 만 세션 0개로 인정, 그 외는 FAIL exit 1(#0 RULE — 조회 실패를 고아로 읽지 않는다).
set -u
WT="$(git rev-parse --show-toplevel)" || { echo "FAIL ft-orphan-cards — git 루트 확인 실패" >&2; exit 1; }
ROOT="$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir | sed 's|/\.git$||')"
# R383: cfo 카드 폴더 기본값 = c-level-planning 워크트리의 cfo 팀 폴더(그 워크트리의 design/TEAMS.md · 팀 이름 글자 0). 워크트리가 없으면 «없음» 을 ERROR 로 한 줄 알리고 EXTRA 비움(기본 스캔은 계속)
if [ "${FT_ORPHAN_EXTRA_DIRS+set}" = set ]; then EXTRA="$FT_ORPHAN_EXTRA_DIRS"
else . "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/ft-team-lib.sh" || { echo "FAIL ft-orphan-cards — ft-team-lib.sh 를 못 읽었다" >&2; exit 1; }
  if _cfo="$(ft_team_in "$ROOT/.worktrees/c-level-planning" cfo)"; then EXTRA="cfo=$_cfo/indices/진행"; else EXTRA=""; echo "ERROR cfo 카드 폴더를 못 풀었다($ROOT/.worktrees/c-level-planning/design/TEAMS.md) — cfo 진행 카드는 이번 스캔에서 빠진다" >&2; fi; fi

err="$(tmux ls -F '#{session_name}' 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then
  case "$err" in *"no server running"*) err="";; *) echo "FAIL ft-orphan-cards — tmux ls 실패(rc=$rc): $err" >&2; exit 1;; esac
fi
sessions="$(printf '%s\n' "$err" | tr '[:upper:]' '[:lower:]')"

dirs=""
for d in "$ROOT"/design/*/indices/진행 "$ROOT"/design/teams/*/indices/진행; do [ -d "$d" ] && dirs="$dirs $(basename "$(dirname "$(dirname "$d")")")=$d"; done   # R382: design/teams/<팀>/ 꼴도 센다
dirs="$dirs $EXTRA"

summary=""
for ent in $dirs; do
  team="${ent%%=*}"; dir="${ent#*=}"
  [ -d "$dir" ] || { echo "WARN ft-orphan-cards — $team 진행 디렉터리 없음: $dir" >&2; continue; }
  total=0; orphan=0
  for card in "$dir"/*.md; do
    [ -f "$card" ] || continue
    slug="$(basename "$card" .md)"; total=$((total+1))
    key="-$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]')#"
    printf '%s\n' "$sessions" | grep -qF -- "$key" && continue
    orphan=$((orphan+1)); printf '%s\t%s\t*%s*\n' "$team" "$slug.md" "$key"
  done
  summary="$summary $team=$orphan/$total"
done
echo "ORPHANS (팀=고아/진행카드)${summary}" >&2
