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
      # 꼴3 순서(r386 r3): ①env FT_HARNESS_ROOT ②ft_harness_root(설치본 bin/../HARNESS_ROOT 지도 · 팩 체크아웃 꼴) ③ERROR
      local hr="${FT_HARNESS_ROOT:-}" d
      if [ -z "$hr" ]; then d="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
        [ -f "$d/ft-harness-root.sh" ] && hr="$(. "$d/ft-harness-root.sh" && ft_harness_root "$d")"; fi
      [ -n "$hr" ] && [ -d "$hr" ] || { echo "ERROR $t 폴더가 \$FT_HARNESS_ROOT 꼴인데 env 가 없거나 폴더가 아니다: ${FT_HARNESS_ROOT:-<없음>}" >&2; return 1; }
      out="${hr%/}/${rel#*/}";;
    design/teams/*) if [ "$alt" = 1 ]; then out="$root/${rel/design\/teams\//design/}"; else out="$root/$rel"; _ft_team_twin_warn "$root/${rel/design\/teams\//design/}" "$t"; fi;;
    design/*)       if [ "$alt" = 1 ]; then out="$root/design/teams/$t/"; else out="$root/$rel"; fi;;
    *) echo "ERROR $t 폴더 칸을 풀지 못했다: $rel" >&2; return 1;;
  esac
  printf '%s\n' "${out%/}"; }
# r447: 명단 새 꼴인데 옛 꼴 폴더에 파일이 남았으면(쌍둥이 공존) 새 꼴을 돌려주고 stderr WARN 1줄 — 옛 꼴로 되돌아가지 않는다
#   FT_TEAM_TWIN_WARN=0 = 끔 — 쌍둥이를 일부러 둘 다 세는 ft_team_cands* 와 stderr 를 값으로 받는 호출처(map-lint)만
_ft_team_twin_warn() { local old="${1%/}" n; [ "${FT_TEAM_TWIN_WARN:-1}" != 0 ] && [ -d "$old" ] || return 0
  n="$(find "$old" -type f 2>/dev/null | wc -l | tr -d ' ')"; [ "$n" -gt 0 ] || return 0
  echo "WARN 옛 꼴 잔존 ${n}파일 — ft-team-move.sh --apply $2 (옛 폴더 $old)" >&2; }
#   ft_old_form_team <경로>         : 경로의 첫 `design/<이름>/` 구간(teams 아님)이 «명단 새 꼴(design/teams/<팀>/) 팀» 이면 팀 이름 출력 rc0 · 옛 꼴 팀·꼴3·명단 밖·design 밖 = rc1 · 명단 못 읽음 = rc2 (r447)
ft_old_form_team() { local t rel
  [[ "$1" =~ (^|/)design/([a-z0-9][a-z0-9_-]*)/ ]] || return 1; t="${BASH_REMATCH[2]}"; [ "$t" != teams ] || return 1
  ft_team_teams_md >/dev/null 2>&1 || return 2
  rel="$(ft_team_rel "$t" 2>/dev/null)" || return 1
  case "$rel" in design/teams/*) printf '%s\n' "$t";; *) return 1;; esac; }
#   ft_card_location_ok <카드>      : 카드가 «명단 새 꼴 팀» 의 옛 꼴 폴더에 있으면 stdout `REJECT 카드 위치 옛 경로 …` + rc1 (r447) · 명단 = 카드가 든 리포의 design/TEAMS.md(FT_TEAMS_MD 가 있으면 그것)
#                                    명단 없는 리포·리포 밖 = 판정 생략 rc0(위치만 보는 검사 · 전환 전 리포는 동작 변경 0)
ft_card_location_ok() { local d r t
  d="$(cd -- "$(dirname -- "$1")" 2>/dev/null && pwd -P)" || return 0
  r="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)" || return 0
  t="$(FT_REPO_ROOT="$r" ft_old_form_team "${d#"$r"/}/")" || return 0
  echo "REJECT 카드 위치 옛 경로 — ft-team-move.sh --apply $t 뒤 다시: $1 (명단의 $t 폴더 = design/teams/$t/)"; return 1; }
#   ft_old_form_added <리포> <base> <head> : merge-base(base,head)..head 에 «새로 생긴» 파일 중 옛 꼴 위치(명단 새 꼴 팀의 design/<팀>/…) 목록 — 있으면 stdout 사유 1줄 + rc1 (r447 · 명단 = <head>:design/TEAMS.md · 없으면 rc0)
ft_old_form_added() { ( r="$1"; md="$(mktemp)" || exit 1; trap 'rm -f "$md"' EXIT
  git -C "$r" show "$3:design/TEAMS.md" > "$md" 2>/dev/null || exit 0
  export FT_TEAMS_MD="$md" FT_REPO_ROOT="$r"; bad=""
  while IFS= read -r -d '' p; do [ -n "$p" ] && ft_old_form_team "$p" >/dev/null && bad="$bad $p"; done < <(git -C "$r" diff -z --name-only --no-renames --diff-filter=A "$2...$3")   # -z: 한글 경로 따옴표·8진수 감싸기(core.quotePath) 없이 원문
  [ -z "$bad" ] || { echo "가지에 옛 꼴 경로 새 파일 $(echo $bad | wc -w | tr -d ' ')개 — design/teams/<팀>/ 로 옮긴다(ft-team-move.sh --apply <팀>):$bad"; exit 1; } ); }
#   ft_index_twin <경로>            : 카드·파일 경로의 쌍둥이(design/teams/<t>/… ↔ design/<t>/…) — 첫 `design/` 구간만 바꾼다 · design/ 아래가 아니면 출력 0 rc1 (전환 기간 역호환 후보 · 린트가 전환 끝나면 제거 요구)
ft_index_twin() { local p="$1"
  case "$p" in
    *design/teams/*/*) printf '%s\n' "${p/design\/teams\//design/}";;
    *design/*/*)       printf '%s\n' "${p/design\//design/teams/}";;
    *) return 1;;
  esac; }
#   ft_team_in <루트> <팀>          : 그 «루트(워크트리 포함)» 의 design/TEAMS.md 로 푼 팀 폴더 절대경로 — 워크트리마다 이동 상태가 다를 수 있으니 도구가 읽는 루트의 명단을 쓴다. 명단·팀 없음 = ERROR rc1(옛 design/<팀>/ 후퇴 0)
ft_team_in() { ( unset FT_TEAMS_MD; export FT_REPO_ROOT="$1"; ft_team_root "$2" ); }
#   ft_team_cands <루트> <팀>       : 그 루트에서 팀 폴더 «후보» 절대경로 줄마다 — 명단 꼴 먼저 · 쌍둥이(--alt)가 있으면 뒤에(꼴3 은 쌍둥이 0). 이동 «전·후 둘 다 찾는» 도구용(R383 · 팀 이름 글자 0). 명단·팀 없음 = ERROR rc1
ft_team_cands() { ( unset FT_TEAMS_MD; export FT_REPO_ROOT="$1" FT_TEAM_TWIN_WARN=0; ft_team_root "$2" || exit 1; ft_team_root "$2" --alt 2>/dev/null; exit 0 ); }
#   ft_team_cands_ref <루트> <팀> [<ref>] : «명단 = ref · 폴더 = 루트»(R400 r3) — 명단은 `git show <ref>:design/TEAMS.md`(기본 origin/main · 워크트리 사본이 옛 명단이어도 무관), 후보 폴더는 그 루트 아래(명단 꼴 먼저 · 쌍둥이 뒤 · 꼴3 은 쌍둥이 0). ref 못 읽음 = `ERROR … 못 읽음` · 팀 없음 = ERROR(ft_team_rel) · 둘 다 rc1
ft_team_cands_ref() { ( r="$1"; t="$2"; ref="${3:-origin/main}"; md="$(mktemp)" || exit 1; trap 'rm -f "$md"' EXIT
  git -C "$r" show "$ref:design/TEAMS.md" > "$md" 2>/dev/null || { echo "ERROR $t 명단($ref:design/TEAMS.md)을 못 읽음: $r" >&2; exit 1; }
  export FT_TEAMS_MD="$md" FT_REPO_ROOT="$r" FT_TEAM_TWIN_WARN=0; ft_team_root "$t" || exit 1; ft_team_root "$t" --alt 2>/dev/null; exit 0 ); }
#   ft_team_file_ref <루트> <팀> <파일> [<ref>] : ft_team_cands_ref 후보 폴더 중 <파일> 이 «실재하는 정확히 1개» 의 절대경로(R406 · 기본 ref = FT_TEAMS_REF 또는 origin/main) — 명단 못 읽음·팀 없음·실재 0·2+ = stderr ERROR(ref·후보 경로) rc1 · 추측·옛 경로 후퇴 0
ft_team_file_ref() { local r="$1" t="$2" f="$3" ref="${4:-${FT_TEAMS_REF:-origin/main}}" cands c hits=()
  cands="$(ft_team_cands_ref "$r" "$t" "$ref")" || return 1
  while IFS= read -r c; do [ -n "$c" ] && [ -f "$c/$f" ] && hits+=("$c/$f"); done <<< "$cands"
  [ "${#hits[@]}" = 1 ] || { echo "ERROR $t $f 실재 후보 ${#hits[@]}개 — 정확히 1개여야 한다(명단 $ref:design/TEAMS.md · 후보 $(printf '%s ' $cands))" >&2; return 1; }
  printf '%s\n' "${hits[0]}"; }
#   ft_team_doc_ref <루트> <팀> <파일> [<ref>] : 정본 문서 «읽기» 경로(r459 · 자리 규칙 «정본 = ref origin/main») — 후보 폴더 중 실재 정확히 1개면 그 경로 ·
#                                    실재 0 이면 `git show <ref>:<명단 꼴 폴더>/<파일>` 본문을 임시 파일로 쓰고 그 경로(정리 = 부르는 쪽 · ft_team_doc_tmp 로 판별) ·
#                                    명단 못 읽음·팀 없음·실재 2+·ref 에도 없음 = stderr ERROR rc1(추측·옛 경로 후퇴 0) · 읽기 전용 — 원장처럼 «쓰는» 파일엔 ft_team_file_ref
ft_team_doc_ref() { local r="$1" t="$2" f="$3" ref="${4:-${FT_TEAMS_REF:-origin/main}}" cands c first="" hits=() tmp rel
  cands="$(ft_team_cands_ref "$r" "$t" "$ref")" || return 1
  while IFS= read -r c; do [ -n "$c" ] || continue; [ -n "$first" ] || first="$c"; [ -f "$c/$f" ] && hits+=("$c/$f"); done <<< "$cands"
  case "${#hits[@]}" in
    1) printf '%s\n' "${hits[0]}"; return 0;;
    0) ;;
    *) echo "ERROR $t $f 실재 후보 ${#hits[@]}개 — 정확히 1개여야 한다(명단 $ref:design/TEAMS.md · 후보 $(printf '%s ' $cands))" >&2; return 1;;
  esac
  rel="${first#"$r"/}"; tmp="$(mktemp "$(_ft_team_doc_dir)/ft-team-doc.XXXXXX")" || return 1
  git -C "$r" show "$ref:$rel/$f" > "$tmp" 2>/dev/null && [ -s "$tmp" ] || { rm -f "$tmp"; echo "ERROR $t $f 실재 0 · $ref:$rel/$f 도 없음(명단 $ref:design/TEAMS.md · 후보 $(printf '%s ' $cands))" >&2; return 1; }
  printf '%s\n' "$tmp"; }
#   ft_team_doc_tmp <경로>          : ft_team_doc_ref 가 만든 임시 본문이면 rc0(부르는 쪽이 rm) · 루트 실재 파일이면 rc1
_ft_team_doc_dir() { local d="${TMPDIR:-/tmp}"; printf '%s\n' "${d%/}"; }
ft_team_doc_tmp() { case "$1" in "$(_ft_team_doc_dir)"/ft-team-doc.*) return 0;; esac; return 1; }
#   ft_team_has_ref <루트> <팀> <경로> [<하위>] [<ref>] : ft_team_has 를 «ref 명단» 으로(R406) — rc 는 ft_team_has 와 같다(ref 못 읽음 = rc2)
ft_team_has_ref() { ( r="$1"; ref="${5:-${FT_TEAMS_REF:-origin/main}}"; md="$(mktemp)" || exit 2; trap 'rm -f "$md"' EXIT
  git -C "$r" show "$ref:design/TEAMS.md" > "$md" 2>/dev/null || { echo "ERROR 명단($ref:design/TEAMS.md)을 못 읽음: $r" >&2; exit 2; }
  export FT_TEAMS_MD="$md" FT_REPO_ROOT="$r"; ft_team_has "$2" "$3" "${4:-}" ); }
#   ft_team_has <팀> <경로> [<하위>] : 경로가 그 팀 폴더(<하위> 가 있으면 그 아래) 안인가 — 명단 꼴·쌍둥이 둘 다 본다(상대·절대경로 모두 · 꼴3 은 FT_HARNESS_ROOT 절대경로). rc0 안 · rc1 밖(명단에 없는 팀도 «밖») · rc2 명단을 못 읽음/꼴3 env 없음(ERROR)
ft_team_has() { local t="$1" p="$2" sub="${3:-}" rel c md
  md="$(ft_team_teams_md)" || return 2
  ft_team_names "$md" | grep -qxF -- "$t" || return 1
  rel="$(ft_team_rel "$t")" || return 2
  case "$rel" in
    '$FT_HARNESS_ROOT/'*|'${FT_HARNESS_ROOT}/'*) c="$(ft_team_root "$t")" || return 2; case "$p" in "$c/$sub"*) return 0;; esac; return 1;;
  esac
  case "$p" in *"$rel$sub"*) return 0;; esac
  c="$(ft_index_twin "$rel")" && case "$p" in *"$c$sub"*) return 0;; esac
  return 1; }
