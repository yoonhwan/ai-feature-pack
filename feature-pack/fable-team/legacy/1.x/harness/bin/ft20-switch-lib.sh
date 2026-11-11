#!/usr/bin/env bash
# r1675 — 팀 2.0 전환 표식 가드. 1.x 쓰기 입구가 «쓰기 전»에 부른다.
#   표식 = <데이터 루트>/.fable-team/state/ft20-switch/<팀>.json · mark/unmark/status = 같은 폴더 ft-team-switch.sh
#   표식 없음 = 지금 동작 그대로(rc0) · 못 읽는 표식(깨진 JSON·권한) = «판정 불가» rc3(쓰기 0 · 하드 룰 20).
#   입구는 «호출 1줄»만 쓴다 — 팀 판정은 ft20_guard_* 함수가 맡는다(arch #3922 ③).
FT20_SWITCH_REL=".fable-team/state/ft20-switch"
ft20_root_of() {   # <경로> → .fable-team 이 있는 리포 루트 · FT_FT20_ROOT 가 이긴다(시험용 임시 루트)
  if [ -n "${FT_FT20_ROOT:-}" ]; then printf '%s' "$FT_FT20_ROOT"; return 0; fi
  local r; r="$(git -C "${1:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  printf '%s' "${r%/.git}"
}
ft20_switch_dir() { printf '%s/%s' "${1%/}" "$FT20_SWITCH_REL"; }
ft20_switch_marker() { printf '%s/%s.json' "$(ft20_switch_dir "$1")" "$2"; }
ft20_switch_active() {   # 표식이 하나라도 있나 — 없으면 팀 판정(명부 스캔)을 건너뛴다
  local d; d="$(ft20_switch_dir "$1")"; [ -d "$d" ] || return 1
  compgen -G "$d/*.json" >/dev/null 2>&1
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
# ft20_guard_retire <루트> <좌석> [<명부파일>] — 명부 쓰기 입구(은퇴·승계). 쓰기 대상 명부 «전부» 검사 · 0 통과 · 3 전환됨/판정 불가
ft20_guard_retire() {
  local root="${1:-}" seat="${2:-}" teams rc
  teams="$(ft20_teams_writing_seat "$root" "$seat" "${3:-}")"; rc=$?
  case "$rc" in
    4) echo "INFO 팀 판정 불가 — $seat 이 어느 명부에도 없음 · 2.0 전환 표식 검사 건너뜀" >&2; return 0;;
    3) echo "REJECT 명부 못 읽음 — $seat 의 쓰기 대상 팀 판정 불가(깨진 JSON·권한) · 1.x 쓰기 0" >&2; return 3;;
  esac
  ft20_switch_guard_multi "$root" $teams
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
  ft20_switch_guard_multi "$root" ${teams[@]+"${teams[@]}"}
}
# ft20_guard_roster <루트> <명부파일> — 역할 좌석 개설·틱 승계처럼 «그 명부 한 장»에 쓰는 입구
ft20_guard_roster() { ft20_switch_guard "${1:-}" "$(ft20_team_of_file "${2:-}")"; }
