#!/usr/bin/env bash
# r1675 — 팀 2.0 전환 표식 가드. 1.x 쓰기 입구가 «쓰기 전»에 부른다.
#   표식 = <데이터 루트>/.fable-team/state/ft20-switch/<팀>.json · mark/unmark/status = 같은 폴더 ft-team-switch.sh
#   표식 없음 = 지금 동작 그대로(rc0) · 못 읽는 표식(깨진 JSON·권한) = «판정 불가» rc3(쓰기 0 · 하드 룰 20).
#   입구는 «호출 1줄»만 쓴다 — 팀 판정은 ft20_guard_* 함수가 맡는다(arch #3922 ③).
FT20_SWITCH_REL=".fable-team/state/ft20-switch"
ft20_root_of() {   # <경로> → .fable-team 이 있는 리포 루트 · FT_FT20_ROOT 가 이긴다(시험용 임시 루트)
  if [ -n "${FT_FT20_ROOT:-}" ]; then printf '%s' "$FT_FT20_ROOT"; return 0; fi
  local p="${1:-.}" r
  [ -f "$p" ] && p="$(dirname -- "$p")"   # r1767 A1 — 카드 «파일» 경로면 그 폴더
  while [ ! -e "$p" ]; do p="$(dirname -- "$p")"; done   # r1767 A1 — 아직 없는 경로(쌍둥이 경로)는 존재하는 가장 가까운 상위
  r="$(git -C "$p" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  printf '%s' "${r%/.git}"
}
ft20_switch_dir() { printf '%s/%s' "${1%/}" "$FT20_SWITCH_REL"; }
ft20_switch_marker() { printf '%s/%s.json' "$(ft20_switch_dir "$1")" "$2"; }
ft20_switch_active() {   # 표식이 하나라도 있나 — 없으면 팀 판정(명부 스캔)을 건너뛴다
  local d; d="$(ft20_switch_dir "$1")"; [ -d "$d" ] || return 1
  compgen -G "$d/*.json" >/dev/null 2>&1
}
FT20_HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"   # 같은 폴더 도구(ft-name-lint.sh) 찾기용
ft20_team_of_name() {    # <좌석이름> → 그 이름이 쓰게 될 팀(R282② 와 같은 규칙 = `-` 둘째 토큰 · byz-<팀>-<역할>-<에이전트>#N)
  local t; t="$(printf '%s' "${1%%#*}" | cut -d- -f2)"; [ -n "$t" ] || return 1; printf '%s' "$t"
}
ft20_team_of_file() {    # <명부파일> → 팀 (seats.json=v65 · seats-<팀>.json=<팀>)
  local b; b="$(basename "${1:-}")"
  case "$b" in seats.json) printf v65;; seats-*.json) b="${b#seats-}"; printf '%s' "${b%.json}";; *) return 1;; esac
}
# <명부파일> <좌석> <mode: row|write> → rc 0 = 대상 · 1 = 아님 · 3 = 못 읽음(판정 불가)
_ft20_seat_in() {
  python3 -c 'import json,sys
try: d=json.load(open(sys.argv[1],encoding="utf-8"))
except Exception: sys.exit(3)
if not isinstance(d,dict): sys.exit(1)
seat, mode = sys.argv[2], sys.argv[3]
hit = seat in d or (mode == "write" and any(isinstance(k,str) and k.startswith("_") and v == seat for k, v in d.items()))
sys.exit(0 if hit else 1)' "$1" "$2" "${3:-row}" 2>/dev/null
}
_ft20_scan() {   # <루트> <좌석> <mode> [<명부파일추가>] → 그 좌석을 가진/쓸 명부들의 팀(줄바꿈 · 중복 0) · rc 0=1개+ · 4=없음 · 3=못 읽음
  local root="${1%/}" seat="${2:-}" mode="${3:-row}" extra="${4:-}" g t out="" seen=" " bad=0
  for g in "$root/.fable-team"/seats*.json ${extra:+"$extra"}; do
    [ -f "$g" ] || continue
    _ft20_seat_in "$g" "$seat" "$mode"; case $? in
      0) t="$(ft20_team_of_file "$g")" || continue
         case "$seen" in *" $t "*) ;; *) out="${out}${out:+
}$t"; seen="$seen$t ";; esac;;
      3) bad=1;;
    esac
  done
  [ "$bad" = 0 ] || return 3
  [ -n "$out" ] || return 4
  printf '%s\n' "$out"
}
ft20_teams_of_seat() { _ft20_scan "$1" "$2" row ""; }                    # 좌석 «행» 이 있는 명부 팀
ft20_teams_writing_seat() { _ft20_scan "$1" "$2" write "${3:-}"; }    # 그 좌석을 «쓰게 될» 명부 팀 전부(r465 `_*` 칸 포함 · 명시 명부도 «더한다»)
# ft20_switch_guard <데이터루트> <팀> [보류본문] [보낸좌석] → 0 통과 · 3 전환됨/판정 불가(쓰기 0)
ft20_switch_guard() {
  local root="${1:-}" team="${2:-}" body="${3:-}" from="${4:-seat}" m info hd base held="" n=0
  [ -n "$root" ] && [ -n "$team" ] || { echo "INFO 팀 판정 불가 — 2.0 전환 표식 검사 건너뜀(표식 없는 팀으로 본다)" >&2; return 0; }
  m="$(ft20_switch_marker "$root" "$team")"; [ -e "$m" ] || return 0
  info="$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1],encoding="utf-8"));print(str(d.get("switched_at") or "?"),str(d.get("h") or "?"))' "$m" 2>/dev/null)" \
    || { echo "REJECT 팀 $team 전환 표식 판정 불가 — $m 못 읽음(깨진 JSON·권한) · 1.x 쓰기 0" >&2; return 3; }
  if [ -n "$body" ]; then
    hd="$(ft20_switch_dir "$root")/$team.held"; base="$hd/$(date +%Y%m%dT%H%M%S)-$(printf '%s' "$from" | tr -c 'A-Za-z0-9._#-' '_')"
    # ★덮어쓰기 0★ — 같은 초·같은 보낸 좌석 2통이면 순번이 붙는다(noclobber = 경합에서도 한 쪽만 성공 · arch #3922 ①)
    mkdir -p "$hd" || { echo "REJECT 팀 $team 은 2.0 전환됨(${info% *} · h${info#* }) — 1.x 쓰기 0 · 보류 실패(보류 폴더 쓰기 0): $hd" >&2; return 3; }
    until [ -n "$held" ]; do
      n=$((n+1)); ( set -C; printf '%s' "$body" > "$base-$(printf '%02d' "$n").txt" ) 2>/dev/null && held="$base-$(printf '%02d' "$n").txt"
      [ "$n" -lt 100 ] || break
    done
    [ -n "$held" ] || { echo "REJECT 팀 $team 은 2.0 전환됨(${info% *} · h${info#* }) — 1.x 쓰기 0 · 보류 실패(순번 100개 참) : $hd" >&2; return 3; }
    held=" · 보류 $held"
  fi
  echo "REJECT 팀 $team 은 2.0 전환됨(${info% *} · h${info#* }) — 1.x 쓰기 0$held" >&2
  return 3
}
# ft20_switch_guard_multi <루트> <팀...> → 0 통과 · 3 하나라도 전환됨/판정 불가(쓰기 0)
ft20_switch_guard_multi() {
  local root="${1:-}" t; shift || true
  for t in "$@"; do [ -n "$t" ] || continue; ft20_switch_guard "$root" "$t" || return $?; done
  return 0
}
# ── 입구별 «호출 1줄»용 판정 함수 ─────────────────────────────────────────────
# ft20_guard_seat <루트> <좌석> [본문] [보낸좌석] — 우편함 입구. 0 통과(명부에 없음 = 팀 없음) · 3 전환됨/판정 불가
ft20_guard_seat() {
  local root="${1%/}" seat="${2:-}" teams rc
  teams="$(ft20_teams_of_seat "$root" "$seat")"; rc=$?
  case "$rc" in
    4) echo "INFO 팀 판정 불가 — $seat 이 어느 명부에도 없음 · 2.0 전환 표식 검사 건너뜀" >&2; return 0;;
    3) echo "REJECT 명부 못 읽음 — $seat 의 팀 판정 불가(깨진 JSON·권한) · 1.x 쓰기 0" >&2; return 3;;
  esac
  if [ "$(printf '%s\n' "$teams" | grep -c .)" -gt 1 ]; then
    echo "REJECT $seat 이 명부 2개 이상에 있음($(printf '%s' "$teams" | paste -sd, -)) — 팀 판정 불가 · 1.x 쓰기 0" >&2; return 3
  fi
  ft20_switch_guard "$root" "$teams" "${3:-}" "${4:-seat}"
}
# ft20_guard_retire <루트> <옛좌석> [<명부파일>] [<후계이름>] — 명부 쓰기 입구(은퇴·승계)
#   쓰기 대상 명부 «전부» + ★R282② 가 새 행을 만들 이름의 팀 명부★(명부에 행이 없어도 그 팀에 쓴다 · DA R1)
#   옛 이름이 lint 실패면 R282② 는 «후계 이름»의 팀을 쓴다 → 그때만 후계 팀을 더한다(과차단 0)
#   r1777(R336) — 표식이 «없는» 교대 창이면 보관본(unmarked-<ts>)의 h 로 같은 자율 조건을 본다(ft20_window_guard).
ft20_guard_retire() {
  local root="${1:-}" seat="${2:-}" f="${3:-}" new="${4:-}" teams rc t src
  teams="$(ft20_teams_writing_seat "$root" "$seat" "$f")"; rc=$?
  [ "$rc" != 3 ] || { echo "REJECT 명부 못 읽음 — $seat 의 쓰기 대상 팀 판정 불가(깨진 JSON·권한) · 1.x 쓰기 0" >&2; return 3; }
  src="$seat"
  if [ -n "$new" ] && [ -f "$FT20_HERE/ft-name-lint.sh" ] && ! bash "$FT20_HERE/ft-name-lint.sh" "$seat" >/dev/null 2>&1; then src="$new"; fi
  t="$(ft20_team_of_name "$src")" && teams="${teams}${teams:+
}$t"
  [ -n "$teams" ] || { echo "INFO 팀 판정 불가 — $seat 이 어느 명부에도 없고 이름에서 팀도 못 뽑음 · 2.0 전환 표식 검사 건너뜀" >&2; return 0; }
  ft20_switch_guard_multi "$root" $teams || return $?
  ft20_window_guard "$root" $teams
}
# r1874 — ft20_guard_handover <루트> <구> <후계> [<명부파일>] — 2.0 표식 아래 «같은 계보 역할 좌석» 승계만 표식 유지 통과(rc0 + INFO 1줄)
#   ⓐ 두 이름 lint ⓑ 계보(#N 앞) 같음 ⓒ 후계 번호 > 구 번호 ⓓ 역할 ≠ nano(DA r1874 R1) ⓔ 쓰기 팀 = 이름 팀 1개(남의 명부 `_*` 0) ⓕ 표식 판독 OK
#   하나라도 거짓 = ft20_guard_retire 그대로(완화 0 · 표식 없음·깨짐·교대 창 판정은 그쪽이 한다)
ft20_guard_handover() {
  local root="${1:-}" old="${2:-}" new="${3:-}" f="${4:-}" lint="$FT20_HERE/ft-name-lint.sh" team teams m h on nn
  if [ -n "$root" ] && [ -n "$new" ] && [ -f "$lint" ] \
     && bash "$lint" "$old" >/dev/null 2>&1 && bash "$lint" "$new" >/dev/null 2>&1 \
     && [ "${old%#*}" = "${new%#*}" ] \
     && on="${old##*#}" && nn="${new##*#}" && [ "$((10#$nn))" -gt "$((10#$on))" ] \
     && [ "$(printf '%s' "${old%#*}" | cut -d- -f3)" != nano ] \
     && team="$(ft20_team_of_name "$old")" \
     && teams="$(ft20_teams_writing_seat "$root" "$old" "$f")" && [ "$teams" = "$team" ] \
     && m="$(ft20_switch_marker "$root" "$team")" && [ -f "$m" ] && h="$(ft20_marker_h "$m")"; then
    echo "INFO 2.0 표식 아래 같은 계보 승계 허용 팀 $team h$h" >&2; return 0
  fi
  ft20_guard_retire "$root" "$old" "$f" "$new"
}
# ft20_guard_move <루트> <카드경로> — 카드 이동(카드 경로 팀 우선 · 경로로 못 풀 때만 FT_TEAM · arch #3917 ②)
ft20_guard_move() {
  local t=""; case "${2:-}" in */indices/*) t="${2%/indices/*}"; t="${t##*/}";; esac
  ft20_switch_guard "${1:-}" "${t:-${FT_TEAM:-}}"
}
# ft20_guard_spawn <루트> <카드경로> [<명부파일>] — 좌석 개설(명부 = env 팀·명부 파일 팀 · 카드 §상태 = 경로 팀 · 전부 검사)
ft20_guard_spawn() {
  local root="${1:-}" card="${2:-}" teams=() t
  [ -z "${FT_TEAM:-}" ] || teams+=("$FT_TEAM")
  case "$card" in */indices/*) t="${card%/indices/*}"; teams+=("${t##*/}");; esac
  [ -z "${3:-}" ] || { t="$(ft20_team_of_file "$3")" && teams+=("$t"); }
  [ -n "$root" ] || [ "${#teams[@]}" -eq 0 ] || { echo "REJECT 데이터 루트 판정 불가 — 2.0 전환 표식 검사 못 함 · 1.x 쓰기 0" >&2; return 3; }   # r1767 A3 — spawn 입구만(하드 룰 20)
  ft20_switch_guard_multi "$root" ${teams[@]+"${teams[@]}"}
}
# ft20_guard_roster <루트> <명부파일> — 역할 좌석 개설·틱 승계처럼 «그 명부 한 장»에 쓰는 입구
ft20_guard_roster() { ft20_switch_guard "${1:-}" "$(ft20_team_of_file "${2:-}")"; }

# ── r1777(R336) 교대 창 = unmark → retire → remark 를 Slack 질문 0 으로 ─────────
#   표식 h 가 `A<N>`(자율 사건)이면 «자율 정합 ON ∧ 레벨 full ∧ A<N> = 지금 이벤트» 일 때만 받는다.
#   숫자 h 길은 손대지 않는다(옛 1.x 손 승계 그대로 · 하드 룰 16 «느슨하게 하지 않는다» 는 mark·unmark 에 그대로).
#   도구 자리 = FT20_AUTONOMY_BIN → 같은 폴더 ft-autonomy.sh (시험은 사본 경로를 준다)
ft20_autonomy_bin() { printf '%s' "${FT20_AUTONOMY_BIN:-$FT20_HERE/ft-autonomy.sh}"; }
ft20_autonomy_level() {   # 레벨 칸(ft-autonomy-level.sh 의 jfield level 과 같은 기본값 = full · 못 읽으면 빈 값)
  local d; d="$(bash "$(ft20_autonomy_bin)" state-dir 2>/dev/null)" || { printf 'full'; return 0; }
  python3 -c 'import json,sys
try: d=json.load(open(sys.argv[1],encoding="utf-8"))
except Exception: print(""); raise SystemExit(0)
print(str(d.get("level") or "full"))' "$d/autonomy.json" 2>/dev/null
}
# ft20_autonomy_ok <h> → 0 허용 · 2 거절(사유 1줄 stderr · 쓰기 0)
ft20_autonomy_ok() {
  local h="${1:-}" s m ev l
  s="$(ft20_autonomy_bin)"
  [ -f "$s" ] || { echo "REJECT 자율 상태 도구 없음($s) — 교대 창 h=$h 판정 불가 · 1.x 쓰기 0" >&2; return 2; }
  ev="$(bash "$s" event 2>/dev/null)"
  if [ "$ev" != "$h" ]; then echo "REJECT 교대 창 h=$h 는 지금 이벤트(${ev:-없음})가 아님 — 지난 사건이거나 자율 OFF · 1.x 쓰기 0" >&2; return 2; fi
  m="$(bash "$s" mode 2>/dev/null)"
  if [ "$m" != on ]; then echo "REJECT 교대 창 h=$h — 자율이 ON 이 아님(mode=${m:-?} · 위변조 포함) · 1.x 쓰기 0" >&2; return 2; fi
  l="$(ft20_autonomy_level)"
  if [ "$l" != full ]; then echo "REJECT 교대 창 h=$h — 자율 레벨이 full 이 아님(${l:-?}) · 1.x 쓰기 0" >&2; return 2; fi
  return 0
}
# ft20_window_backup <루트> <팀> → 가장 새 보관본 1줄 · 없으면 rc1
ft20_window_backup() {
  local d dst; d="$(ft20_switch_dir "${1%/}")"; [ -d "$d" ] || return 1
  dst="$(printf '%s\n' "$d/${2:-}.json.unmarked-"* | grep -v '\.window$' | sort -r | head -1)"   # 사건 쏙파일(<보관분>.window)은 보관본이 아니다
  [ -f "$dst" ] || return 1
  printf '%s' "$dst"
}
# ft20_marker_h <표식·보관본·쪽파일 경로> → h 칸 1줄(없으면 빈 줄) · 못 읽으면 rc1
ft20_marker_h() {
  python3 - "${1:-}" <<'PYH' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    sys.exit(1)
print(str((d or {}).get("h") or ""))
PYH
}
# ft20_window_mark <보관본 경로> <h> — A<N> 로 연 교대에만 «승인 사건» 쪽파일(<보관분>.window)을 남긴다
#   원표식 JSON 은 손대지 않는다 — 숫자 원표식(h=8260) 팀을 A17 로 열어도 restore 가 원문 그대로 되살린다(DA #292018)
#   숫자 h 로 연 옛 교대 = 쪽파일 0(지금 동작 그대로) · 쓰기 실패 = rc1(부르는 쪽이 표식을 되돌린다)
ft20_window_mark() {
  local dst="${1:-}" h="${2:-}" t
  case "$h" in A[0-9]*) ;; *) return 0;; esac
  [ -n "$dst" ] || return 1
  t="$(date +%Y%m%dT%H%M%S)"
  { printf '{"h":"%s","at":"%s"}\n' "$h" "$t" > "$dst.window.tmp.$$" && mv "$dst.window.tmp.$$" "$dst.window"; } || { rm -f "$dst.window.tmp.$$"; return 1; }
}
# ft20_window_event <보관본 경로> → 그 창을 연 자율 사건 A<N> 1줄 · 쪽파일 없음/숫자 교대 = 빈 줄 · 쪽파일 깨짐 = rc1
ft20_window_event() {
  local dst="${1:-}" h
  [ -f "$dst.window" ] || return 0
  h="$(ft20_marker_h "$dst.window")" || return 1
  printf '%s' "$h"
}
# ft20_window_guard <루트> <팀...> → 0 통과 · 2 자율 조건 불일치 · 3 보관본 판정 불가 (전부 «1.x 쓰기 0»)
#   교대 창 = 표식 없음 ∧ 보관본 있음 · 조건을 보는 h = ⓐ 쪽파일의 사건 A<N>(A<N> 로 연 교대) ⓑ 없으면 보관본 자산의 h 가 A<N> 꼴
#   숫자 h 보관본이고 쪽파일도 없으면 = 옛 손 승계 그대로 통과
ft20_window_guard() {
  local root="${1:-}" t dst h; shift || true
  [ -n "$root" ] || return 0
  for t in "$@"; do
    [ -n "$t" ] || continue
    [ ! -e "$(ft20_switch_marker "$root" "$t")" ] || continue
    dst="$(ft20_window_backup "$root" "$t")" || continue
    h="$(ft20_window_event "$dst")" \
      || { echo "REJECT 팀 $t 교대 창 사건 쪽파일 판정 불가 — $dst.window 못 읽음(깨진 JSON) · 1.x 쓰기 0" >&2; return 3; }
    [ -n "$h" ] || h="$(ft20_marker_h "$dst")" \
      || { echo "REJECT 팀 $t 교대 창 보관본 판정 불가 — $dst 못 읽음(깨진 JSON·권한) · 1.x 쓰기 0" >&2; return 3; }
    case "$h" in A[0-9]*) ft20_autonomy_ok "$h" || return 2;; esac
  done
  return 0
}
# ft20_switch_window <루트> <팀> <h> [명령...] — 교대 창 1회: unmark → 명령(retire 등) → remark
#   unmark 실패 = 아무것도 안 바꿨으니 되돌림 0 · retire·remark 중 하나라도 rc≠0 이면 «그 자리에서» restore(보관본 → 표식)
#   남는 것 = 표식 원래 내용 그대로 · 1.x writer 는 다시 rc3
ft20_switch_window() {
  local root="${1:-}" team="${2:-}" h="${3:-}" tool rc=0; shift 3 || return 2
  tool="$FT20_HERE/ft-team-switch.sh"
  bash "$tool" unmark "$team" --h "$h" --root "$root" >/dev/null || { rc=$?; echo "REJECT 교대 창 열기 실패(unmark $team · h=$h · rc=$rc) — 표식 그대로" >&2; return "$rc"; }
  [ $# -eq 0 ] || { "$@" >&2 || rc=$?; }
  if [ "$rc" = 0 ]; then bash "$tool" mark "$team" --h "$h" --root "$root" >/dev/null || rc=$?; fi   # remark
  if [ "$rc" != 0 ]; then bash "$tool" restore "$team" --root "$root" >&2 || echo "WARN 교대 창 되돌림(restore $team) 실패 rc=$? — 보관본에서 손으로 되살린다" >&2; return "$rc"; fi
  return 0
}
