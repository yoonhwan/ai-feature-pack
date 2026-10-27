#!/usr/bin/env bash
# ft-team-lib.sh — 팀 경로 단일 출처 (R382 · source 전용)
#   TEAMS.md «폴더» 칸 3꼴을 한 곳에서 푼다 — 도구는 `design/$TEAM` 을 조립하지 않고 ft_team_root 만 부른다.
#     꼴1 `design/<팀>/`  ·  꼴2 `design/teams/<팀>/`  ·  꼴3 `$FT_HARNESS_ROOT/design/<팀>/`(env 치환 · 하네스 팩 분리 뒤)
#   ft_team_names [<TEAMS.md>]      : 팀 이름 목록(칸 첫 일치 순서)
#   ft_team_root <팀> [--alt]       : 팀 폴더 절대경로 · --alt = 쌍둥이 경로(꼴1↔꼴2 · 꼴3 은 쌍둥이 없음 = rc1·출력 0)
#   ft_team_rel <팀>                : 칸에 적힌 원문 경로(치환 전) — 이동 도구의 before/after 줄용
#   env: FT_REPO_ROOT(기본 git 루트) · FT_TEAMS_MD(기본 <루트>/design/TEAMS.md) · FT_HARNESS_ROOT(꼴3 치환값 · 없으면 꼴3 팀은 ERROR rc1)
#   ft_from_current <값> [<명부>]   : 보내는 사람 이름의 «명부 현역» 해석 — 송신 from 단일 출처 (r730)
#   ft_sparse_patterns <팀> [경로…] : sparse-checkout --no-cone 패턴(자기 팀 design + 추가 경로) — ft-wt-add.sh (r835)
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
#   ft_card_stage_ref <루트> <IDX> [<ref>] : 카드 «단계» 를 ref 트리로 정한다(r842 · 뒤처진 루트 체크아웃의 옛 단계 사본이 ref 에서 이미 옮긴 카드를 가리지 않게) —
#     IDX(design/[teams/]<팀>/indices/<단계>/<파일>) 와 ft_index_twin 쌍둥이의 <indices 뿌리>/{진행,완성,대기}/<파일> 을 ref 에서 직접 본다 · 명부(TEAMS.md)·ft_team_cands_ref 안 씀 · 디스크 안 봄 · 읽기만
#     stdout 첫 줄 = «STAGE <단계>» rc0 · «ABSENT» rc0(ref 풀림 + 모든 후보 ls-tree 성공 + 전부 없음) · 그 밖(빈 출력 포함) = stderr ERROR rc1
#     — 조회 실패(ref·ls-tree·쌍둥이 계산)가 «카드 없음» 으로 읽히지 않게 세 갈래를 글자로 가른다(DA⑥ r2 반례: 명부 없음 = 빈 출력 rc0 → 옛 진행/ 후퇴)
ft_card_stage_ref() { local r="$1" idx="$2" ref="${3:-${FT_CARD_REF:-origin/main}}" base tw d out hits="" rc roots=()
  case "$idx" in */indices/*/*) ;; *) echo "ERROR 카드 단계 idx 꼴 아님(…/indices/<단계>/<파일>): $idx" >&2; return 1;; esac
  base="${idx%%/indices/*}"; roots=("$base")
  if declare -F ft_index_twin >/dev/null; then tw="$(ft_index_twin "$idx" 2>/dev/null)" || { echo "ERROR 카드 단계 쌍둥이 계산 실패: $idx" >&2; return 1; }
    [ -z "$tw" ] || roots+=("${tw%%/indices/*}"); fi
  git -C "$r" rev-parse --verify -q "$ref^{commit}" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] || { echo "ERROR 카드 단계 ref($ref)를 못 읽음(rc=$rc · ref 없음·리포 아님): $r" >&2; return 1; }
  :   # r842-mut:teams
  for base in "${roots[@]}"; do
    for d in 진행 완성 대기; do
      out="$(git -C "$r" ls-tree --name-only "$ref" -- "$base/indices/$d/${idx##*/}" 2>/dev/null)"; rc=$?
      [ "$rc" -eq 0 ] || { echo "ERROR 카드 단계 ls-tree 실패(rc=$rc): $ref:$base/indices/$d/${idx##*/}" >&2; return 1; }
      [ -z "$out" ] || case " $hits " in *" $d "*) ;; *) hits="${hits:+$hits }$d";; esac
    done; done
  case "$hits" in *' '*) echo "ERROR ${idx##*/} 카드가 $ref 에 여러 단계($hits) — 정확히 1단계여야 한다" >&2; return 1;; esac
  [ -n "$hits" ] && { echo "STAGE $hits"; return 0; }
  echo ABSENT; }
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
#   r839 r5: ref 읽기 규칙(ref_read · 존재 확인 · 명단 조회 · 예산 70초 · 빈 답 재시도 1회)은 «파이썬 한 벌»(같은 폴더 ft_team_lib.py)뿐이다.
#     셸은 호출 한 줄만 — 재시도·예산·오류 문구 로직 0(두 벌이 있는 한 매 회차 «다른 자리» 가 나온다 · DA⑥ r4 반례 5 중 4건).
#     stdout·rc 그대로 넘긴다(본문/오류 문구는 파이썬이 만든다 — 기준판 바이트).
_FT_TEAM_LIB_PY="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/ft_team_lib.py"
#   ref_read <리포> <git 인자…>              : ref 조회 1회 규칙(7초 상한 · 빈 값이면 1회 재시도 · 빈 값 2번 = rc4 «빈 응답 2회» · rc≠0 = rc4 · 예산 소진 = rc4)
ref_read() { python3 "$_FT_TEAM_LIB_PY" ref-read "$@"; }
#   _ft_ref_present <리포> <ref:경로>        : rc0 있음 · rc1 없음(stderr «does not exist in» 로만) · 그 밖 = rc4 «판정 불가»
_ft_ref_present() { python3 "$_FT_TEAM_LIB_PY" present "$1" "$2"; }
#   ft_team_doc_ref_only <루트> <팀> <파일> [<ref>] : 정본 문서 «ref 본문만»(데몬용 · 디스크 0 · 실패 = ERROR 1줄 rc1) — 임시 파일 경로 출력(ft_team_doc_tmp 로 판별 · 정리 = 부르는 쪽)
ft_team_doc_ref_only() { python3 "$_FT_TEAM_LIB_PY" doc-ref "$@"; }
#   ft_planner_queue_ref <루트>             : 오빠 큐 «읽기» 본문(r557 ft-queue.sh ft_queue_ref 를 옮김 · 디스크 0 · FT_TEAMS_REF/FT_LEDGER_REPO 그대로) — 임시 파일 경로 출력 · 실패 = 기준판 문구 1줄 rc1
ft_planner_queue_ref() { python3 "$_FT_TEAM_LIB_PY" queue-ref "$@"; }
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
# r835: sparse 체크아웃 패턴 단일 출처 — ft-nano-spawn 424행과 같은 3줄(남의 팀 design 제외) + 추가 경로마다 `/<경로>` 1줄(끝 / 는 그대로)
ft_sparse_patterns() { local t="$1" p; shift
  printf '/*\n!/design/teams/*/\n/design/teams/%s/\n' "$t"
  for p in "$@"; do printf '/%s\n' "${p#/}"; done; }

# ── r978 r2 — «바뀐 경로 목록» 읽기 «한 곳» (리서치 닫기 ft-nano-close.sh · 완성 판정 ft_doc_card_landed 가 같이 부른다)
#   반송 r1(DA HOLD 3)의 원인 하나: 세 자리가 git 경로 출력을 «그대로» 읽어 ①이름 변경의 옛 경로를 건너뛰고 ②인용된(quotePath) 경로를 원래 글자와 비교했다.
#   r2 반송 r2(DA r2 HOLD 3): `-c core.quotePath=false` 로도 git 은 «따옴표·역슬래시 든 경로» 와 «공백 든 미추적 경로» 를 따옴표로 감싼다 → 인용 해제 코드 0 을 위해 `-z`(NUL 구분)로 받는다.
#     bash 명령치환은 NUL 을 지우므로 임시 파일 1개 경유(mktemp + RETURN trap 정리 — 정상·조기 return 두 길 모두 남는 파일 0)
#   ft_changed_paths <리포> <기준> <끝> [--commits]
#     기본 = «끝 커밋» 이 기준 대비 바꿔 경로(diff --name-status -z --no-renames · 이름 변경 = 삭제 옛경로 + 추가 새경로 «둘 다») — 완성 판정이 쓴다
#     --commits = 기준..끝 사이 «비병합» 커밋들이 바꾸는 경로 — 리서치 닫기가 쓴다(머리 맞춤 병합이 끌어온 경로는 셈 밖 = 종전 동작 불변)
#   ft_changed_paths_wt <리포>           → 미커밋(추적 변경·미추적) `XY<TAB>경로` 1줄 1개(status --porcelain -z) · 이름 변경·복사(R·C)는 원경로·새경로 «둘 다»
#   rc = git 조회 rc(0 = 읽음 · 경로 0 이어도 0) · 그 밖 = 조회 실패(부르는 쪽이 «셀 수 없다» 로 REJECT)
_FT_GIT_QP=(-c core.quotePath=false)   # r978-mut:quotepath
_FT_GIT_NOREN=(--no-renames)   # r978-mut:norenames — 이름 변경을 «삭제+추가» 로 편다(DA r1 반례 1)
_FT_GIT_Z=(-z)   # r978-mut:zsep — 경로 목록을 NUL 로 받는다(인용 0 · DA r2 반례 3)
ft_changed_paths() { local repo="${1:-}" base="${2:-}" head="${3:-HEAD}" mode="${4:-}" t="" rc=0 st p
  [ -n "$repo" ] && [ -n "$base" ] || return 2
  t="$(mktemp)" || return 2; trap 'rm -f "$t"' RETURN
  if [ "$mode" = --commits ]; then
    ft_git_capped 7 "$repo" "${_FT_GIT_QP[@]}" -c diff.ignoreSubmodules=none log --no-merges --ignore-submodules=none "${_FT_GIT_NOREN[@]}" --no-ext-diff --name-status "${_FT_GIT_Z[@]}" --format= "$base..$head" > "$t" 2>/dev/null || rc=$?
  else
    ft_git_capped 7 "$repo" "${_FT_GIT_QP[@]}" -c diff.ignoreSubmodules=none diff --ignore-submodules=none "${_FT_GIT_NOREN[@]}" --no-ext-diff --name-status "${_FT_GIT_Z[@]}" "$base" "$head" > "$t" 2>/dev/null || rc=$?
  fi
  if [ "$rc" -eq 0 ]; then   # -z: «status\0경로\0» 쌍(이름 변경은 --no-renames 라 R 행이 없다)
    while IFS= read -r -d '' st; do IFS= read -r -d '' p || break; printf '%s\n' "$p"; done < "$t" | sort -u
  fi
  rm -f "$t"
  return "$rc"; }
ft_changed_paths_wt() { local repo="${1:-}" t="" rc=0 e p
  [ -n "$repo" ] || return 2
  t="$(mktemp)" || return 2; trap 'rm -f "$t"' RETURN
  ft_git_capped 7 "$repo" "${_FT_GIT_QP[@]}" status --porcelain=v1 "${_FT_GIT_Z[@]}" --untracked-files=all > "$t" 2>/dev/null || rc=$?
  if [ "$rc" -eq 0 ]; then   # -z: «XY 경로\0» · 이름 변경·복사는 «XY 새경로\0원경로\0» — 원경로도 센다
    while IFS= read -r -d '' e; do
      [ -n "$e" ] || continue
      printf '%s\t%s\n' "${e:0:2}" "${e:3}"
      case "${e:0:2}" in *R*|*C*) IFS= read -r -d '' p && printf '%s\t%s\n' "${e:0:2}" "$p";; esac   # r978-mut:renames
    done < "$t"
  fi
  rm -f "$t"
  return "$rc"; }
# ── r978 고침 2 — «코드 0 문서 카드» 의 완성 인정 판정 «한 곳» (ft-finished-check.sh · ft-index-move-canon.sh 가 같이 부른다)
#   ft_doc_card_landed <리포> <착지 sha> <카드파일>  → rc0 = 인정(stdout «인정 ref <ref> · 파일 <N>») · rc1 = 불인정(stdout 사유) · rc2 = 판정 불가(stdout 사유)
#   조건 셋 «전부» 일 때만: ① 카드에 «- 설치: 없음» ② sha 가 문서 가지 ref(FT_DOC_LAND_REF · 기본 origin/ops/main-base)의 조상 ③ sha 가 바꾼 경로가 전부 design/**.md(코드·설정·시험 0)
#   하나라도 아니면 부르는 쪽은 «origin/main 조상» 만 인정하던 지금 동작으로 돌아간다(동작 불변 · 승인 게이트 확대 0 — r741 ⓑ 안 씀).
ft_doc_card_landed() { local repo="$1" sha="$2" card="$3" ref="${FT_DOC_LAND_REF:-origin/ops/main-base}" rc=0 p n=0
  [ -n "$repo" ] && [ -n "$sha" ] && [ -n "$card" ] || { printf '판정 불가 — 인자 없음(리포·sha·카드)\n'; return 2; }
  [ -f "$card" ] || { printf '판정 불가 — 카드 파일 없음: %s\n' "$card"; return 2; }
  grep -qE '^[[:space:]]*-[[:space:]]*설치:[[:space:]]*없음[[:space:]]*$' "$card" || { printf '카드가 «- 설치: 없음» 이 아니다\n'; return 1; }   # r978-mut:setup
  ft_git_capped 7 "$repo" rev-parse --verify -q "${ref}^{commit}" >/dev/null 2>&1 || rc=$?
  case "$rc" in 0) ;; *) printf '문서 가지 ref 없음·조회 실패(rc=%s): %s\n' "$rc" "$ref"; return 2;; esac
  ft_git_capped 7 "$repo" merge-base --is-ancestor "$sha" "$ref" >/dev/null 2>&1 || rc=$?
  case "$rc" in 0) ;; 1) printf '착지 %s 가 %s 조상 아님\n' "${sha:0:12}" "$ref"; return 1;; *) printf '판정 불가 — 조상 검사 실패(rc=%s)\n' "$rc"; return 2;; esac
  local par; par="$(ft_git_capped 7 "$repo" rev-parse --verify -q "${sha}^1")" || { printf '판정 불가 — %s 첫 부모 없음\n' "${sha:0:12}"; return 2; }
  local names; names="$(ft_changed_paths "$repo" "$par" "$sha")" \
    || { printf '판정 불가 — 바꾼 경로 조회 실패 %s\n' "${sha:0:12}"; return 2; }
  [ -n "$names" ] || { printf '바꾼 경로 0 — 문서 착지 아님: %s\n' "${sha:0:12}"; return 1; }
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in design/*.md) ;; *) printf 'design/**.md 밖 경로: %s\n' "$p"; return 1;; esac
    n=$((n+1))
  done <<< "$names"
  printf '인정 ref %s · 파일 %s\n' "$ref" "$n"; return 0; }
