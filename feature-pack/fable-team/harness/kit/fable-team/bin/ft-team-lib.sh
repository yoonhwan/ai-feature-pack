#!/usr/bin/env bash
# ft-team-lib.sh — 팀 경로 단일 출처 (R382 · source 전용)
#   TEAMS.md «폴더» 칸 3꼴을 한 곳에서 푼다 — 도구는 `design/$TEAM` 을 조립하지 않고 ft_team_root 만 부른다.
#     꼴1 `design/<팀>/`  ·  꼴2 `design/teams/<팀>/`  ·  꼴3 `$FT_HARNESS_ROOT/design/<팀>/`(env 치환 · 하네스 팩 분리 뒤)
#   ft_team_names [<TEAMS.md>]      : 팀 이름 목록(칸 첫 일치 순서)
#   ft_team_root <팀> [--alt]       : 팀 폴더 절대경로 · --alt = 쌍둥이 경로(꼴1↔꼴2 · 꼴3 은 쌍둥이 없음 = rc1·출력 0)
#   ft_team_rel <팀>                : 칸에 적힌 원문 경로(치환 전) — 이동 도구의 before/after 줄용
#   env: FT_REPO_ROOT(기본 git 루트) · FT_TEAMS_MD(기본 <루트>/design/TEAMS.md) · FT_HARNESS_ROOT(꼴3 치환값 · 없으면 꼴3 팀은 ERROR rc1)
#   실패는 stderr `ERROR …` + rc1 — 옛 `design/<팀>/` 으로 되돌아가지 않는다(#0 RULE).
ft_team_repo_root() { local r="${FT_REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null)}"
  [ -n "$r" ] || { echo "ERROR 리포 루트를 못 찾았다(FT_REPO_ROOT 또는 git 안에서 실행)" >&2; return 1; }; printf '%s\n' "$r"; }
ft_team_teams_md() { local m="${FT_TEAMS_MD:-}" r
  [ -n "$m" ] || { r="$(ft_team_repo_root)" || return 1; m="$r/design/TEAMS.md"; }
  [ -f "$m" ] || { echo "ERROR 팀 명단 없음: $m" >&2; return 1; }; printf '%s\n' "$m"; }
# 명단 한 행 → «팀<TAB>원문경로» (경로가 3꼴 중 하나인 행만)
_ft_team_rows() { local m; m="${1:-$(ft_team_teams_md)}" || return 1
  awk -F'|' '/^\|/ { p=$3; gsub(/[[:space:]`]/,"",p)
    if (p ~ /^(\$FT_HARNESS_ROOT\/|\$\{FT_HARNESS_ROOT\}\/)?design\/(teams\/)?[a-z0-9][a-z0-9_-]*\/$/) { n=p; sub(/\/$/,"",n); sub(/.*\//,"",n); print n "\t" p } }' "$m"; }
ft_team_names() { _ft_team_rows "$@" | cut -f1; }
ft_team_rels() { _ft_team_rows | cut -f2; }   # 칸 원문 경로 전부(전환 검사용)
ft_team_rel() { local row; row="$(_ft_team_rows | awk -F'\t' -v t="$1" '$1==t{print $2; exit}')"
  [ -n "$row" ] || { echo "ERROR $1 은 팀 명단(TEAMS.md)에 없다" >&2; return 1; }; printf '%s\n' "$row"; }
ft_team_root() { local t="$1" alt=0 rel root out; [ "${2:-}" = --alt ] && alt=1
  rel="$(ft_team_rel "$t")" || return 1; root="$(ft_team_repo_root)" || return 1
  case "$rel" in
    '$FT_HARNESS_ROOT/'*|'${FT_HARNESS_ROOT}/'*)
      [ "$alt" = 1 ] && return 1
      [ -n "${FT_HARNESS_ROOT:-}" ] && [ -d "$FT_HARNESS_ROOT" ] || { echo "ERROR $t 폴더가 \$FT_HARNESS_ROOT 꼴인데 env 가 없거나 폴더가 아니다: ${FT_HARNESS_ROOT:-<없음>}" >&2; return 1; }
      out="${FT_HARNESS_ROOT%/}/${rel#*/}";;
    design/teams/*) if [ "$alt" = 1 ]; then out="$root/${rel/design\/teams\//design/}"; else out="$root/$rel"; fi;;
    design/*)       if [ "$alt" = 1 ]; then out="$root/design/teams/$t/"; else out="$root/$rel"; fi;;
    *) echo "ERROR $t 폴더 칸을 풀지 못했다: $rel" >&2; return 1;;
  esac
  printf '%s\n' "${out%/}"; }
#   ft_index_twin <경로>            : 카드·파일 경로의 쌍둥이(design/teams/<t>/… ↔ design/<t>/…) — 첫 `design/` 구간만 바꾼다 · design/ 아래가 아니면 출력 0 rc1 (전환 기간 역호환 후보 · 린트가 전환 끝나면 제거 요구)
ft_index_twin() { local p="$1"
  case "$p" in
    *design/teams/*/*) printf '%s\n' "${p/design\/teams\//design/}";;
    *design/*/*)       printf '%s\n' "${p/design\//design/teams/}";;
    *) return 1;;
  esac; }
#   ft_team_in <루트> <팀>          : 그 «루트(워크트리 포함)» 의 design/TEAMS.md 로 푼 팀 폴더 절대경로 — 워크트리마다 이동 상태가 다를 수 있으니 도구가 읽는 루트의 명단을 쓴다. 명단·팀 없음 = ERROR rc1(옛 design/<팀>/ 후퇴 0)
ft_team_in() { ( unset FT_TEAMS_MD; export FT_REPO_ROOT="$1"; ft_team_root "$2" ); }
