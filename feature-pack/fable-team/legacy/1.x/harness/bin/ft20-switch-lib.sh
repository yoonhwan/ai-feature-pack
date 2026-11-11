#!/usr/bin/env bash
# r1675 — 팀 2.0 전환 표식 가드. 1.x 쓰기 입구가 «쓰기 전»에 부른다.
#   표식 = <데이터 루트>/.fable-team/state/ft20-switch/<팀>.json · mark/unmark/status = 같은 폴더 ft-team-switch.sh
#   표식 없음 = 지금 동작 그대로(rc0) · 못 읽는 표식(깨진 JSON·권한) = «판정 불가» rc3(쓰기 0 · 하드 룰 20).
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
ft20_team_of_seat() {    # <루트> <좌석> [<명부파일>] → 팀 · 명부를 못 정하면 빈 값(팀 판정 불가)
  local root="${1%/}" seat="${2:-}" f="${3:-}" t="" n=0
  if [ -n "$f" ]; then ft20_team_of_file "$f"; return; fi
  for f in "$root/.fable-team"/seats*.json; do
    [ -f "$f" ] || continue
    python3 -c 'import json,sys;d=json.load(open(sys.argv[1],encoding="utf-8"));sys.exit(0 if isinstance(d,dict) and sys.argv[2] in d else 1)' "$f" "$seat" 2>/dev/null || continue
    t="$(ft20_team_of_file "$f")" || continue; n=$((n+1))
  done
  [ "$n" -eq 1 ] && printf '%s' "$t"
}
# <루트> <좌석> [<명부파일>] → 그 좌석 행을 가진 명부들의 팀(줄바꿈) · rc 0=찾음 · 4=어느 명부에도 없음 · 3=명부 못 읽음(깨진 JSON·권한 = 판정 불가)
ft20_teams_of_seat() {
  local root="${1%/}" seat="${2:-}" f="${3:-}" out="" t="" bad=0
  if [ -n "$f" ]; then ft20_team_of_file "$f"; return; fi
  for f in "$root/.fable-team"/seats*.json; do
    [ -f "$f" ] || continue
    python3 -c 'import json,sys
try: d=json.load(open(sys.argv[1],encoding="utf-8"))
except Exception: sys.exit(3)
sys.exit(0 if isinstance(d,dict) and sys.argv[2] in d else 1)' "$f" "$seat" 2>/dev/null
    case $? in 0) t="$(ft20_team_of_file "$f")" && out="${out}${out:+
}$t";; 3) bad=1;; esac
  done
  [ "$bad" = 0 ] || return 3
  [ -n "$out" ] || return 4
  printf '%s\n' "$out"
}
# <루트> <좌석> [<명부파일>] → 이 좌석을 쓰게 될 명부들의 팀 — 행이 있는 명부 + 그 좌석을 가리키는 `_*` 칸이 있는 명부(r465 같은 폴더 다른 명부도 쓴다) · rc 0/4/3
ft20_teams_writing_seat() {
  local root="${1%/}" seat="${2:-}" f="${3:-}" out="" t="" bad=0
  if [ -n "$f" ]; then ft20_team_of_file "$f"; return; fi
  for f in "$root/.fable-team"/seats*.json; do
    [ -f "$f" ] || continue
    python3 -c 'import json,sys
try: d=json.load(open(sys.argv[1],encoding="utf-8"))
except Exception: sys.exit(3)
if not isinstance(d,dict): sys.exit(1)
sys.exit(0 if (sys.argv[2] in d or any(isinstance(k,str) and k.startswith("_") and v==sys.argv[2] for k,v in d.items())) else 1)' "$f" "$seat" 2>/dev/null
    case $? in 0) t="$(ft20_team_of_file "$f")" && out="${out}${out:+
}$t";; 3) bad=1;; esac
  done
  [ "$bad" = 0 ] || return 3
  [ -n "$out" ] || return 4
  printf '%s\n' "$out"
}
# ft20_switch_guard_multi <루트> <팀...> → 0 통과 · 3 하나라도 전환됨/판정 불가(쓰기 0)
ft20_switch_guard_multi() {
  local root="${1:-}" t; shift || true
  for t in "$@"; do [ -n "$t" ] || continue; ft20_switch_guard "$root" "$t" || return $?; done
  return 0
}
# ft20_guard_retire <루트> <좌석> [<명부파일>] — 명부 쓰기 입구(은퇴·승계)용. 0 통과 · 3 전환됨/판정 불가
ft20_guard_retire() {
  local root="${1:-}" seat="${2:-}" f="${3:-}" teams rc
  teams="$(ft20_teams_writing_seat "$root" "$seat" "$f")"; rc=$?
  case "$rc" in
    4) echo "INFO 팀 판정 불가 — $seat 이 어느 명부에도 없음 · 2.0 전환 표식 검사 건너뜀" >&2; return 0;;
    3) echo "REJECT 명부 못 읽음 — $seat 의 쓰기 대상 팀 판정 불가(깨진 JSON·권한) · 1.x 쓰기 0" >&2; return 3;;
  esac
  ft20_switch_guard_multi "$root" $teams
}
# ft20_guard_seat <루트> <좌석> [본문] [보낸좌석] — 우편함 입구용. 0 통과(명부에 없음 = 팀 없음) · 3 전환됨/판정 불가
ft20_guard_seat() {
  local root="${1%/}" seat="${2:-}" body="${3:-}" from="${4:-seat}" teams rc
  teams="$(ft20_teams_of_seat "$root" "$seat")"; rc=$?
  case "$rc" in
    4) echo "INFO 팀 판정 불가 — $seat 이 어느 명부에도 없음 · 2.0 전환 표식 검사 건너뜀" >&2; return 0;;
    3) echo "REJECT 명부 못 읽음 — $seat 의 팀 판정 불가(깨진 JSON·권한) · 1.x 쓰기 0" >&2; return 3;;
  esac
  if [ "$(printf '%s\n' "$teams" | grep -c .)" -gt 1 ]; then
    echo "REJECT $seat 이 명부 2개 이상에 있음($(printf '%s' "$teams" | paste -sd, -)) — 팀 판정 불가 · 1.x 쓰기 0" >&2; return 3
  fi
  ft20_switch_guard "$root" "$teams" "$body" "$from"
}
# ft20_switch_guard <데이터루트> <팀> [보류본문] [보낸좌석] → 0 통과 · 3 전환됨/판정 불가(쓰기 0)
ft20_switch_guard() {
  local root="${1:-}" team="${2:-}" body="${3:-}" from="${4:-seat}" m info hd held=""
  [ -n "$root" ] && [ -n "$team" ] || { echo "INFO 팀 판정 불가 — 2.0 전환 표식 검사 건너뜀(표식 없는 팀으로 본다)" >&2; return 0; }
  m="$(ft20_switch_marker "$root" "$team")"; [ -e "$m" ] || return 0
  info="$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1],encoding="utf-8"));print(str(d.get("switched_at") or "?"),str(d.get("h") or "?"))' "$m" 2>/dev/null)" \
    || { echo "REJECT 팀 $team 전환 표식 판정 불가 — $m 못 읽음(깨진 JSON·권한) · 1.x 쓰기 0" >&2; return 3; }
  if [ -n "$body" ]; then
    hd="$(ft20_switch_dir "$root")/$team.held"
    held="$hd/$(date +%Y%m%dT%H%M%S)-$(printf '%s' "$from" | tr -c 'A-Za-z0-9._#-' '_').txt"
    mkdir -p "$hd" && printf '%s' "$body" > "$held" \
      || { echo "REJECT 팀 $team 은 2.0 전환됨(${info% *} · h${info#* }) — 1.x 쓰기 0 · 보류 실패(보류 폴더 쓰기 0): $hd" >&2; return 3; }
    held=" · 보류 $held"
  fi
  echo "REJECT 팀 $team 은 2.0 전환됨(${info% *} · h${info#* }) — 1.x 쓰기 0$held" >&2
  return 3
}
