#!/usr/bin/env bash
# ft-team-lib.sh — 팀 경로 단일 출처 (R382 · source 전용)
#   TEAMS.md «폴더» 칸 3꼴을 한 곳에서 푼다 — 도구는 `design/$TEAM` 을 조립하지 않고 ft_team_root 만 부른다.
#     꼴1 `design/<팀>/`  ·  꼴2 `design/teams/<팀>/`  ·  꼴3 `$FT_HARNESS_ROOT/design/<팀>/`(env 치환 · 하네스 팩 분리 뒤)
#   ft_team_names [<TEAMS.md>]      : 팀 이름 목록(칸 첫 일치 순서)
#   ft_team_root <팀> [--alt]       : 팀 폴더 절대경로 · --alt = 쌍둥이 경로(꼴1↔꼴2 · 꼴3 은 쌍둥이 없음 = rc1·출력 0)
#   ft_team_rel <팀>                : 칸에 적힌 원문 경로(치환 전) — 이동 도구의 before/after 줄용
#   env: FT_REPO_ROOT(기본 git 루트) · FT_TEAMS_MD(기본 <루트>/design/TEAMS.md) · FT_HARNESS_ROOT(꼴3 치환값 · 없으면 꼴3 팀은 ERROR rc1)
#   ft_from_current <값> [<명부>]   : 보내는 사람 이름의 «명부 현역» 해석 — 송신 from 단일 출처 (r730)
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
    design/teams/*) if [ "$alt" = 1 ]; then out="$root/${rel/design\/teams\//design/}"; else out="$root/$rel"; _ft_team_twin_warn "$root/${rel/design\/teams\//design/}" "$t" "$root"; fi;;
    design/*)       if [ "$alt" = 1 ]; then out="$root/design/teams/$t/"; else out="$root/$rel"; fi;;
    *) echo "ERROR $t 폴더 칸을 풀지 못했다: $rel" >&2; return 1;;
  esac
  case "$alt$rel" in 0design/*) _ft_team_sparse_check "$root" "${rel%/}" || return 1;; esac
  printf '%s\n' "${out%/}"; }
# r486: 폴더가 tracked 인데 sparse 체크아웃(r444 · 나노 = 자기 팀 design 만)으로 디스크에 없으면 stderr `SPARSE-HIDDEN <경로> …` + rc1 — 일반 «없음» 과 가른다(파이썬 SparseHidden 과 같은 글자)
#   전체 체크아웃·untracked·디스크에 있음 = 통과 · FT_TEAM_SPARSE_CHECK=0 = 끔(후보를 «실재 여부 무관» 으로 세는 ft_team_cands* 만)
_ft_team_sparse_check() { [ "${FT_TEAM_SPARSE_CHECK:-1}" != 0 ] && [ ! -e "$1/$2" ] || return 0
  [ "$(git -C "$1" config --bool core.sparseCheckout 2>/dev/null)" = true ] || return 0
  git -C "$1" ls-files --error-unmatch -- "$2" >/dev/null 2>&1 || return 0
  echo "SPARSE-HIDDEN $2 — 이 워크트리는 자기 팀 폴더만 체크아웃(r444) · 전체 사본 = ft-scratch-repo.sh <base> 에서 돌려라" >&2; return 1; }
# r447: 명단 새 꼴인데 옛 꼴 폴더에 파일이 남았으면(쌍둥이 공존) 새 꼴을 돌려주고 stderr WARN 1줄 — 옛 꼴로 되돌아가지 않는다
#   r926: 루트 가지가 origin/main 을 품는지 먼저 본다(rev-list --count HEAD..origin/main 1회 · 7초 상한) — 안 품으면(데이터 루트 = 한참 뒤진 작업 폴더) «이동하라» 대신 «이동 0 · 원장은 ref 정본» 이라고 말한다(그 안내대로 하면 뒤진 가지에 이동 커밋이 생긴다)
#   FT_TEAM_TWIN_WARN=0 = 끔 — 쌍둥이를 일부러 둘 다 세는 ft_team_cands* 와 stderr 를 값으로 받는 호출처(map-lint)만
#   _ft_team_branch_state <루트> → stdout `contains|behind:<N>|unknown` rc0 — git 조회 1회 · 7초 상한(넘김·git 실패 = unknown = 가지를 못 물어봤다)
#     `rev-list --count HEAD..origin/main` 한 번으로 둘 다 된다(0 = main 을 품었다 · N>0 = N 뒤 · 실패 = 못 물어봄) — 7초 상한도 한 번에 건다
#     r926 r2: timeout·gtimeout 이 둘 다 없으면 git 을 부르지 않고 unknown — 7초 상한 없는 git 호출 금지(DA⑥ r1 반례 2)
_ft_team_branch_state() { local r="$1" to n
  to="$(command -v timeout || command -v gtimeout || true)"
  [ -n "$to" ] || { echo unknown; return 0; }
  n="$("$to" 7 git -C "$r" rev-list --count HEAD..origin/main 2>/dev/null)"
  case "$n" in ''|*[!0-9]*) echo unknown;; 0) echo contains;; *) echo "behind:$n";; esac; }
_ft_team_twin_warn() { local old="${1%/}" t="${2:-}" root="${3:-${FT_REPO_ROOT:-}}" n st; [ "${FT_TEAM_TWIN_WARN:-1}" != 0 ] && [ -d "$old" ] || return 0
  n="$(find "$old" -type f 2>/dev/null | wc -l | tr -d ' ')"; [ "$n" -gt 0 ] || return 0
  st=unknown; [ -n "$root" ] && st="$(_ft_team_branch_state "$root")"
  case "$st" in
    behind:*) echo "WARN 옛 꼴 잔존 ${n}파일 — 데이터 루트 가지가 main 보다 ${st#behind:} 뒤 · 이동 0 · 원장은 ref 정본 (옛 폴더 $old)" >&2;;
    contains) echo "WARN 옛 꼴 잔존 ${n}파일 — ft-team-move.sh --apply $t (옛 폴더 $old)" >&2;;
    *) echo "WARN 옛 꼴 잔존 ${n}파일 — ft-team-move.sh --apply $t (옛 폴더 $old) · 가지 확인 못 함" >&2;;
  esac; }
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
ft_team_cands() { ( unset FT_TEAMS_MD; export FT_REPO_ROOT="$1" FT_TEAM_TWIN_WARN=0 FT_TEAM_SPARSE_CHECK=0; ft_team_root "$2" || exit 1; ft_team_root "$2" --alt 2>/dev/null; exit 0 ); }
#   ft_team_cands_ref <루트> <팀> [<ref>] : «명단 = ref · 폴더 = 루트»(R400 r3) — 명단은 `git show <ref>:design/TEAMS.md`(기본 origin/main · 워크트리 사본이 옛 명단이어도 무관), 후보 폴더는 그 루트 아래(명단 꼴 먼저 · 쌍둥이 뒤 · 꼴3 은 쌍둥이 0). ref 못 읽음 = `ERROR … 못 읽음` · 팀 없음 = ERROR(ft_team_rel) · 둘 다 rc1
ft_team_cands_ref() { ( r="$1"; t="$2"; ref="${3:-origin/main}"; md="$(mktemp)" || exit 1; trap 'rm -f "$md"' EXIT
  git -C "$r" show "$ref:design/TEAMS.md" > "$md" 2>/dev/null || { echo "ERROR $t 명단($ref:design/TEAMS.md)을 못 읽음: $r" >&2; exit 1; }
  export FT_TEAMS_MD="$md" FT_REPO_ROOT="$r" FT_TEAM_TWIN_WARN=0 FT_TEAM_SPARSE_CHECK=0; ft_team_root "$t" || exit 1; ft_team_root "$t" --alt 2>/dev/null; exit 0 ); }
#   ft_team_in_ref <루트> <팀> [<ref>] : 파이썬 team_in_ref 와 같은 규칙(r495) — ft_team_cands_ref 후보 중 실재 1개 = 그것 · 쌍둥이 2개 = ref 트리(ls-tree -d)에 있는 쪽 + stderr `WARN TWIN-STALE <버린 후보> …` ·
#                                    ref 에 둘 다 = 명단 꼴 + `WARN TWIN-BOTH …` · ref 에 둘 다 없음·실재 0 = stderr ERROR rc1(실재 0 은 SPARSE-HIDDEN 먼저 · FT_TEAM_SPARSE_CHECK=0 = 끔) · stdout 폴더 1줄 · 읽기만(폴더 이동·쓰기 0)
ft_team_in_ref() { local r="$1" t="$2" ref="${3:-${FT_TEAMS_REF:-origin/main}}" cands c hits=() on=() n
  cands="$(ft_team_cands_ref "$r" "$t" "$ref")" || return 1
  while IFS= read -r c; do [ -n "$c" ] && [ -d "$c" ] && hits+=("$c"); done <<< "$cands"
  case "${#hits[@]}" in
    1) printf '%s\n' "${hits[0]}"; return 0;;
    0) while IFS= read -r c; do case "$c" in "$r"/*) _ft_team_sparse_check "$r" "${c#"$r"/}" || return 1;; esac; done <<< "$cands"
       echo "ERROR $t 폴더 실재 후보 0개 — 정확히 1개여야 한다(명단 $ref:design/TEAMS.md · 후보 ${cands//$'\n'/ })" >&2; return 1;;
  esac
  for c in "${hits[@]}"; do [ -n "$(git -C "$r" ls-tree -d "$ref" -- "${c#"$r"/}" 2>/dev/null)" ] && on+=("$c"); done
  case "${#on[@]}" in
    1) n="$(git -C "$r" rev-list --count "HEAD..$ref" 2>/dev/null)" || n=""
       for c in "${hits[@]}"; do [ "$c" = "${on[0]}" ] || echo "WARN TWIN-STALE $c (ref 에 없음 · 체크아웃 ref 뒤 ${n:-?}커밋)" >&2; done
       printf '%s\n' "${on[0]}";;
    2) echo "WARN TWIN-BOTH ${hits[0]} ${hits[1]} (ref 에 둘 다 · 명단 꼴 ${hits[0]})" >&2; printf '%s\n' "${hits[0]}";;
    *) echo "ERROR $t 폴더 실재 후보 2개 — 정확히 1개여야 한다(명단 $ref:design/TEAMS.md · 후보 ${cands//$'\n'/ }) (ref 에 둘 다 없음)" >&2; return 1;;
  esac; }
#   ft_planner_queue <루트>         : 오빠 큐(AUTONOMY-QUEUE.md) 경로 1줄(r515 · 대리·자율 상태·결정 셈이 같이 쓰는 단일 출처 · 파이썬 planner_queue 와 같은 규칙) — FT_PLANNER_DIR 있으면 그 폴더 ·
#                                    없으면 ref(FT_TEAMS_REF · 기본 origin/main) 명단 꼴 planner 폴더가 루트에 실재하면 그 폴더 · 실재 0(이동 전 가지 체크아웃)이면 공용 루트 .fable-team/state/planner ·
#                                    ref 명단 못 읽음·공용 루트 못 풂 = stderr ERROR rc1(옛 체크아웃 꼴 후퇴 0) · 쓰기 0(폴더는 쓰는 쪽이 만든다)
ft_planner_queue() { local c g
  if [ -n "${FT_PLANNER_DIR:-}" ]; then printf '%s\n' "${FT_PLANNER_DIR%/}/AUTONOMY-QUEUE.md"; return 0; fi
  c="$(ft_team_cands_ref "$1" planner "${FT_TEAMS_REF:-origin/main}")" || return 1; c="${c%%$'\n'*}"
  if [ -d "$c" ]; then printf '%s\n' "$c/AUTONOMY-QUEUE.md"; return 0; fi
  g="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" && [ -n "$g" ] || { echo "ERROR planner 큐 자리를 못 풂 — 명단 꼴 폴더 없음($c) · 공용 루트(git common dir) 못 읽음: $1" >&2; return 1; }
  printf '%s\n' "${g%/.git}/.fable-team/state/planner/AUTONOMY-QUEUE.md"; }
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
#   ft_ref_git_out <리포> <git 인자…> : ref 읽기 전용 git 1회 — «시도당 7초»(FT_REF_GIT_SEC · 시험 전용) 상한. 넘으면 프로세스 그룹 TERM → 0.5초 뒤 KILL(자식까지 · ft_git_capped.run_cmd 재사용) 후
#     rc 124 = «판정 불가» — 재시도 0(시간 초과는 다시 걸지 않는다 · 7초 룰 · DA⑥ r1 반례 «8초 지연 git show 가 9초 넘게 진행»). 재시도는 첫 시도가 «출력 0»(rc0 · 빈 본문) 일 때만 1회.
#     stdout = git stdout 그대로 · rc = git 종료코드(상한 초과 124 · 실행 실패 128) — 부르는 쪽이 «디스크 본문으로 후퇴» 하지 않는다(#0 RULE)
ft_ref_git_out() { local repo="$1" lim="${FT_REF_GIT_SEC:-7}" out rc
  out="$(PYTHONPATH="$(dirname -- "${_FT_GITCAP_PY:-$_FT_GITCAP_PY_DEFAULT}")" python3 - "$repo" "$lim" "${@:2}" <<'PY'
import sys
import ft_git_capped as g
repo, lim, args = sys.argv[1], float(sys.argv[2]), sys.argv[3:]
cmd = ["git", "-C", repo, *args]
rc, out = g.run_cmd(cmd, lim)          # 시도 1 — 재시도 0
if rc == 0 and not out.strip():        # 첫 시도 «출력 0» 만 1회
    rc, out = g.run_cmd(cmd, lim)
sys.stdout.buffer.write(out)
sys.exit(rc)
PY
)"; rc=$?; printf '%s' "$out"; return "$rc"; }
#   _ft_ref_cands <루트> <팀> [<ref>] : ref 명단(design/TEAMS.md) 으로 푼 그 팀 폴더 후보 줄마다(명단 꼴 먼저 · 쌍둥이 뒤 · 꼴3 은 쌍둥이 0 · 실재 여부 무관) — 명단 = «ref 본문»(디스크 0 · 상한 7초)
#     명단 못 읽음·상한 초과·팀 없음 = stderr ERROR rc1 — ft_team_cands_ref(디스크 본문 읽기 · 상한 0)를 데몬 경로가 쓰지 않게 하는 짝
_ft_ref_cands() { local r="$1" t="$2" ref="${3:-${FT_TEAMS_REF:-origin/main}}" md body rc
  body="$(ft_ref_git_out "$r" show "$ref:design/TEAMS.md")" || { echo "ERROR $t 명단($ref:design/TEAMS.md)을 못 읽음: $r" >&2; return 1; }
  md="$(mktemp "$(_ft_team_doc_dir)/ft-team-ref.XXXXXX")" || return 1
  printf '%s\n' "$body" > "$md"
  ( unset FT_TEAMS_MD; export FT_TEAMS_MD="$md" FT_REPO_ROOT="$r" FT_TEAM_TWIN_WARN=0 FT_TEAM_SPARSE_CHECK=0
    ft_team_root "$t" || exit 1; ft_team_root "$t" --alt 2>/dev/null; exit 0 ); rc=$?
  rm -f "$md"; return "$rc"; }
#   ft_team_doc_ref_only <루트> <팀> <파일> [<ref>] : 정본 문서 «ref 본문만»(r839 · 데몬용 — 루트 체크아웃이 뒤처지거나 더러워도 옛 본문 0) — ref 명단 후보(명단 꼴 먼저)마다
#                                    `<ref>:<후보>/<파일>` 이 ref 트리에 있으면 그 본문을 임시 파일로 쓰고 경로(ft_team_doc_tmp 로 판별 · 정리 = 부르는 쪽) · 디스크 0 · git 호출마다 시도당 7초 상한 ·
#                                    명단 못 읽음·팀 없음·리포 밖 후보·ref 에 없음·show 실패·상한 초과 = stderr ERROR rc1 — 나노 워크트리 안 호출자(자기 디스크가 맞음)는 ft_team_doc_ref 그대로
ft_team_doc_ref_only() { local r="$1" t="$2" f="$3" ref="${4:-${FT_TEAMS_REF:-origin/main}}" cands c rel tmp body
  cands="$(_ft_ref_cands "$r" "$t" "$ref")" || return 1
  while IFS= read -r c; do [ -n "$c" ] || continue
    case "$c" in "$r"/*) rel="${c#"$r"/}";; *) echo "ERROR $t 폴더가 리포 밖($c) — ref 문서 읽기 대상 아님" >&2; return 1;; esac
    body="$(ft_ref_git_out "$r" show "$ref:$rel/$f")" && [ -n "$body" ] || { grc=$?; [ "$grc" = 124 ] && { echo "ERROR $t $f 못 읽음 — 상한 ${FT_REF_GIT_SEC:-7}s 초과($ref:$rel/$f · 디스크 후퇴 0)" >&2; return 1; }; continue; }
    tmp="$(mktemp "$(_ft_team_doc_dir)/ft-team-doc.XXXXXX")" || return 1
    printf '%s\n' "$body" > "$tmp"; printf '%s\n' "$tmp"; return 0
  done <<< "$cands"
  echo "ERROR $t $f 가 $ref 에 없거나 못 읽었다(상한 ${FT_REF_GIT_SEC:-7}s · 디스크 0 · 명단 $ref:design/TEAMS.md · 후보 $(printf '%s ' $cands))" >&2; return 1; }
#   ft_planner_queue_ref <루트>     : 오빠 큐 «읽기» 본문(r557 ft-queue.sh ft_queue_ref 를 옮김 · r839) — ref(FT_TEAMS_REF · 기본 origin/main) 명단 꼴 planner 후보의
#                                    `git show <ref>:<후보>/AUTONOMY-QUEUE.md` 를 임시 파일로(정리 = 부르는 쪽) · 읽을 리포 = FT_LEDGER_REPO(기본 루트) · 디스크 0 · git 호출마다 시도당 7초 상한 ·
#                                    못 읽음·ref 에 없음·상한 초과 = stderr ERROR rc1(빈 본문도 ERROR — 조용한 0 후퇴 금지)
ft_planner_queue_ref() { local r="$1" ref="${FT_TEAMS_REF:-origin/main}" repo="${FT_LEDGER_REPO:-$1}" c rel t body
  c="$(_ft_ref_cands "$r" planner "$ref")" || return 1; c="${c%%$'\n'*}"
  case "$c" in "$r"/*) rel="${c#"$r"/}/AUTONOMY-QUEUE.md";; *) rel="${c%/}/AUTONOMY-QUEUE.md";; esac
  body="$(ft_ref_git_out "$repo" show "$ref:$rel")" || { echo "ERROR 오빠 큐 origin/main 판을 못 읽음: $ref:$rel" >&2; return 1; }
  [ -n "$body" ] || { echo "ERROR 오빠 큐 origin/main 판을 못 읽음: $ref:$rel" >&2; return 1; }
  t="$(mktemp "${TMPDIR:-/tmp}/ft-queue-ref.XXXXXX")" || return 1
  printf '%s\n' "$body" > "$t"; printf '%s\n' "$t"; }
#   ft_team_has_ref <루트> <팀> <경로> [<하위>] [<ref>] : ft_team_has 를 «ref 명단» 으로(R406) — rc 는 ft_team_has 와 같다(ref 못 읽음 = rc2)
ft_team_has_ref() { ( r="$1"; ref="${5:-${FT_TEAMS_REF:-origin/main}}"; md="$(mktemp)" || exit 2; trap 'rm -f "$md"' EXIT
  git -C "$r" show "$ref:design/TEAMS.md" > "$md" 2>/dev/null || { echo "ERROR 명단($ref:design/TEAMS.md)을 못 읽음: $r" >&2; exit 2; }
  export FT_TEAMS_MD="$md" FT_REPO_ROOT="$r"; ft_team_has "$2" "$3" "${4:-}" ); }
#   ft_team_has <팀> <경로> [<하위>] : 경로가 그 팀 폴더(<하위> 가 있으면 그 아래) 안인가 — 명단 꼴·쌍둥이 둘 다 본다(상대·절대경로 모두 · 꼴3 은 FT_HARNESS_ROOT 절대경로). rc0 안 · rc1 밖(명단에 없는 팀도 «밖») · rc2 명단을 못 읽음/꼴3 env 없음(ERROR)
#   ft_from_current <값> [<명부>]   : 보내는 사람 이름을 «명부 현역» 으로 (r730) — 팀장 승계로 명부 `_master` 는 바뀌는데 팀 env 의 FT_SEND_FROM 은 옛 세대 글자 그대로라
#     나노 발주문이 «산출을 옛 팀장에게» 라고 적히고 송신 from 이 죽은 좌석으로 가던 사고(r730 · 챗봇 나노 보고 5통 유실)를 한 곳에서 푼다.
#     계보 = 이름에서 끝 `#<숫자>` 를 뺀 글자 · 명부 = [<명부>] 또는 env FT_SEATS_JSON, 없으면 <루트>/.fable-team/seats-<FT_TEAM 또는 v65>.json 의 `_master`
#     ★계보가 같을 때만★ 바꾼다(같은 계보 안 #N 교체) — 계보가 다르면(역할 다름·옛 이름) 그대로.
#     stdout = 값 1줄(언제나) · rc0 · stderr = 바꿨으면 `INFO FT_SEND_FROM 옛 세대(#N) → 명부 현역(#M)` 1줄 ·
#     명부 못 읽음/`_master` 없음/이름 lint 실패 = 그대로 + `WARN …` 1줄(안전 쪽 — 실패한다고 발신을 막지 않는다)
_ft_from_gen() { case "$1" in *'#'*) printf '%s\n' "${1##*#}";; *) printf '\n';; esac; }
_ft_from_lineage() { case "$1" in *'#'*) printf '%s\n' "${1%#*}";; *) printf '%s\n' "$1";; esac; }
ft_from_current() { local v="${1:-}" seats="${2:-}" m d lint r
  [ -n "$v" ] || { printf '\n'; return 0; }
  if [ -z "$seats" ]; then
    seats="${FT_SEATS_JSON:-}"
    if [ -z "$seats" ]; then r="$(ft_team_repo_root 2>/dev/null)" || r=""
      [ -n "$r" ] || { echo "WARN FT_SEND_FROM 현역 해석 못 함 — 리포 루트를 못 찾았다 (값 그대로: $v)" >&2; printf '%s\n' "$v"; return 0; }
      seats="$r/.fable-team/seats-${FT_TEAM:-v65}.json"; fi
  fi
  [ -f "$seats" ] || { echo "WARN FT_SEND_FROM 현역 해석 못 함 — 명부 없음: $seats (값 그대로: $v)" >&2; printf '%s\n' "$v"; return 0; }
  m="$(grep -o '"_master"[[:space:]]*:[[:space:]]*"[^"]*"' "$seats" 2>/dev/null | head -1 | sed -e 's/^"[^"]*"[[:space:]]*:[[:space:]]*"//' -e 's/"$//')"
  [ -n "$m" ] || { echo "WARN FT_SEND_FROM 현역 해석 못 함 — 명부에 _master 없음: $seats (값 그대로: $v)" >&2; printf '%s\n' "$v"; return 0; }
  d="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
  if [ -f "$d/ft-name-lint.sh" ] && ! lint="$(bash "$d/ft-name-lint.sh" "$m" 2>&1)"; then
    echo "WARN FT_SEND_FROM 현역 해석 못 함 — 명부 _master 이름 lint 실패($lint) (값 그대로: $v)" >&2; printf '%s\n' "$v"; return 0; fi
  [ "$(_ft_from_lineage "$v")" = "$(_ft_from_lineage "$m")" ] || { printf '%s\n' "$v"; return 0; }
  [ "$v" = "$m" ] || echo "INFO FT_SEND_FROM 옛 세대(#$(_ft_from_gen "$v")) → 명부 현역(#$(_ft_from_gen "$m"))" >&2
  printf '%s\n' "$m"; }
#   ft_landed_repo <sha> <카드 리포> [<팩 리포>] [<판정문 표식 줄>] : 착지 sha 의 «진짜 리포» 1곳 판정 (r937 ⓐ · 설치·정본·close-landed 세 게이트가 같은 값을 쓴다)
#     stdout = `<리포 절대경로><TAB><full sha>` rc0 · 실패 = stdout `REJECT <사유>` rc1(부르는 쪽이 그 줄을 게이트 거절문으로 쓴다)
#     순서: ①두 리포 rev-parse(7초 상한) ②한 곳에만 = 그 리포 ③둘 다 = 표식 줄(main(팩) = 팩 · main = 카드 리포 · 표식 없으면 팩 — 카드 리포가 팩 객체를 fetch 해 두는 실사건 · r581)
#           ④둘 다 없음 = REJECT «어느 리포에서도 못 찾음» · 표식과 실제가 어긋나면 REJECT(표식 오기 숨김 0 · ⓒ)
#     앞자리(7~39자)는 그 리포에서 유일해야 인정 · 같은 앞자리가 두 리포의 «다른» 커밋이면 표식 필수(없으면 REJECT) · 팩 리포가 빈 값이면 카드 리포만 본다
#   r959: 표식 «main» 인데 sha 가 팩에만 있으면 «표식 오기(팩 착지)» WARN 1줄 + 팩 리포 결과(기본 동작 — 부르는 쪽마다 따로 보정하지 않는다). 표식 «main(팩)» 어긋남은 보정하지 않는다(숨김 0)
#   ft_git_capped <초> <리포> <git 인자…> : git 조회 1회를 «초» 상한으로 감싼다(r937 r2 T1 · 7초 상한 없는 git 호출 금지).
#     r3: python 실행기 1개(ft_git_capped.py) — git 을 새 프로세스 그룹에서 돌리고 시간 초과면 그룹 SIGTERM → 0.5초 뒤 SIGKILL(자식까지) → 재시도 1회 실제 수행 →
#     또 초과면 rc 124. timeout/gtimeout·bash 버전과 무관 · rc·stdout 은 git 그대로 · 실행 실패 rc 128 · 총 ≤ 2회(재시도는 실행기 안에서 끝난다 — 부르는 쪽이 또 감싸지 않는다)
_FT_GITCAP_PY_DEFAULT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/ft_git_capped.py"
_FT_GITCAP_PY="$_FT_GITCAP_PY_DEFAULT"
ft_git_capped() { python3 "$_FT_GITCAP_PY" "$@" 2>/dev/null; }
_ft_git_retry() { ft_git_capped "$@"; }   # 옛 이름 — 재시도가 실행기로 들어갔다(r937 r3)
#   rc 규약(r937 r2 T2): 0 = 있음 · 1 = «그 리포에 없음» · 그 밖(124 시간 초과 · 128 실행 실패) = «조회 실패» — 없음으로 읽지 않는다
_ft_landed_git() { _ft_git_retry 7 "$1" rev-parse --verify -q "${2}^{commit}"; }
ft_landed_repo() { local sha="$1" cr="${2:-}" pr="${3:-}" mk="${4:-}" cs="" ps="" want=""
  case "$sha" in ''|*[!0-9a-f]*) printf 'REJECT 착지 sha 가 40/앞자리 hex 가 아니다: %s\n' "$sha"; return 1;; esac
  [ "${#sha}" -ge 7 ] || { printf 'REJECT 착지 sha 가 7자 미만이다: %s\n' "$sha"; return 1; }
  [ -n "$cr" ] && [ -d "$cr" ] || { printf 'REJECT 카드 리포가 폴더가 아니다: %s\n' "${cr:-<없음>}"; return 1; }
  local rc=0
  cs="$(_ft_landed_git "$cr" "$sha")" || rc=$?
  case "$rc" in 0) rc=0;; 1) cs="";; *) printf 'REJECT %s 조회 실패(rc=%s · 시간 초과 포함) — 리포 판정 안 함(통과 0)\n' "$cr" "$rc"; return 1;; esac
  if [ -n "$pr" ] && [ -d "$pr" ]; then
    rc=0
    ps="$(_ft_landed_git "$pr" "$sha")" || rc=$?
    case "$rc" in 0) rc=0;; 1) ps="";; *) printf 'REJECT %s 조회 실패(rc=%s · 시간 초과 포함) — 리포 판정 안 함(통과 0)\n' "$pr" "$rc"; return 1;; esac
  fi
  case "$mk" in *닫힘*|*CLOSE*)
    if printf '%s' "$mk" | grep -qE 'main[[:space:]]*\([[:space:]]*팩[[:space:]]*\)'; then want=pack
    elif printf '%s' "$mk" | grep -qE 'main'; then want=card; fi;; esac
  if [ -z "$cs" ] && [ -z "$ps" ]; then
    printf 'REJECT 착지 sha 를 어느 리포에서도 못 찾음: %s (카드 %s · 팩 %s)\n' "$sha" "$cr" "${pr:-<못 풂>}"; return 1; fi
  if [ -n "$cs" ] && [ -n "$ps" ] && [ "$cs" != "$ps" ]; then   # 같은 앞자리가 두 리포의 다른 커밋 = 표식 없이는 못 정한다
    case "$want" in pack) printf '%s\t%s\n' "$pr" "$ps"; return 0;; card) printf '%s\t%s\n' "$cr" "$cs"; return 0;; esac
    printf 'REJECT 착지 sha 앞자리가 두 리포의 다른 커밋을 가리킨다 — 판정문 표식(main / main(팩)) 필요: %s (%s ≠ %s)\n' "$sha" "${cs:0:12}" "${ps:0:12}"; return 1; fi
  case "$want" in
    pack) [ -n "$ps" ] || { printf 'REJECT 판정문 표식 main(팩) 인데 팩 리포에 그 sha 가 없다 — 표식 오기(숨김 0): %s\n' "$sha"; return 1; }
          printf '%s\t%s\n' "$pr" "$ps"; return 0;;
    card) [ -n "$cs" ] || {   # r959: 표식 «main» 인데 sha 가 팩에만 = 표식 오기(팩 착지) → WARN 1줄 + 팩 리포. 보정은 «이 함수의 기본 동작» — 정본·설치·DA 보류 가드·close-landed 네 호출이 부르는 쪽마다 보정을 붙이다 두 번 샜다(DA⑥ r1·r2)
            printf 'WARN\t표식 오기(팩 착지) — 판정문 표식 «main» 인데 sha 가 팩 리포에만 있다 — 팩 리포로 검사한다(카드에 «main(팩)» 로 적으면 이 경고가 사라진다): %s\n' "$sha" >&2
            printf '%s\t%s\n' "$pr" "$ps"; return 0; }
          printf '%s\t%s\n' "$cr" "$cs"; return 0;;
  esac
  if [ -n "$ps" ]; then printf '%s\t%s\n' "$pr" "$ps"; else printf '%s\t%s\n' "$cr" "$cs"; fi; }
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
