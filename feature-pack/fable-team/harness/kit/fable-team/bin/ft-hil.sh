#!/usr/bin/env bash
# ft-hil.sh — 사람이 `!` 로 칠 계획 파일(*.sh.hil 등)을 짧은 진입 파일 /tmp/h<N> 으로 등록한다 (R83 · 판정 850·853 · R186 판정 1720). 도구·오케가 부른다.
#   ft-hil.sh --add <계획 파일> [--supersedes h<M>] [--notify <좌석> [--notify-comm <쪽지함 폴더>]]  → stdout `! bash $HIL_DIR/h<N>` 1줄 (클립보드는 보조: pbcopy 가 있고 HIL_CLIP≠0)
#                                  ★r718: --notify = «[HIL 미실행] 알림 받을 좌석» 을 h<N>.notify(seat= · comm= 두 줄)에 적는다 — 틱 hil_watch 가 그 쪽지함의 그 좌석으로 보낸다. r1130: 새 h 는 등록 직후에도 `[HIL] h<N> 발급` 1통(ft-hil-notify.sh issue · 실패 = WARN 1줄 · rc 0).
#                                  --notify-comm 생략 = 부른 곳의 공용 루트 쪽지함(ft_comm_dir). 좌석 이름 린트 실패·쪽지함 폴더 없음 = REJECT rc2(등록 0).
#                                  h<M> 을 «대체됨» 으로 적는다 — h<M> 을 치면 `REJECT 대체됨 → h<N>` rc 1 · 계획 실행 0
#   ft-hil.sh --cmd '<명령>'      → 명령 1줄 계획을 $HIL_DIR/hil-cmd/<시각>.sh 로 쓰고 --add 와 같은 처리
#   ft-hil.sh                     → 목록 `h<N>  <대상>  <대상 실재 여부>  <미실행 N분 | 실행 HH:MM rc=n | 대체됨 → h<N>>  <수신=좌석@쪽지함 | 수신=- | 수신=표식 손상>`
#   ft-hil.sh --pending [--each] [--held] → 미실행·미대체·«보류 아님» h 요약 1줄(0개면 출력 없음) · --each 는 `h<N> <분>` 줄만 · --held 는 보류 `h<N> <분> <사유>` 줄(r1236)
#   ft-hil.sh --hold h<N> --why <사유> | --unhold h<N>  → <h>.held 에 `hold|unhold <epoch> <좌석> [사유]` 1줄 이어 쓰기 · 마지막 줄이 hold = 보류 · 없는 h = rc 2 (r1236)
# h<N> = «실행되면 h<N>.ran(시작 시각 · rc)을 남기고 계획을 그대로 실행하는» 진입 파일. 계획 파일 수정 0 · 실행 권한 변경 0.
#   ★r1117: 끝나면 ft-hil-notify.sh 가 `[완료 h<N>] rc=…` 를 계획 머리 `# ft-hil-request seat=<좌석…>`(≤3 · 린트 실패 REJECT rc2 · 없으면 WARN) + planner _master 에 1통씩(stdout 사본 h<N>.out)★
# 진입점 폴더 = ${HIL_DIR:-/tmp}(시험만 바꾼다) · 홈($HOME) 아래 쓰기 0 · 등록기 자신의 실행 기능 0(실행은 사람이 `bash /tmp/h<N>`)
# 기존 h<N>(링크·파일) 덮기·지우기 0 · 계획 파일 수정·삭제 0 · eval 0. 옛 링크 h<N> 은 그대로 둔다(표식 없음 · 대체 표시 불가).
# 등록 전 검사(R135a): 같은 폴더 ft_secret_judge.py --plan — 비밀을 화면으로 흘리는 줄이 있으면 `REJECT 계획 파일 비밀 출력 경로 — <줄> <이유>` rc 1(등록 0) · r1133: ft_traffic_plan_judge.py --plan — 날 update-traffic 줄·--health-url 없는 ft-traffic-switch.sh = REJECT rc 1.
set -uo pipefail
D="${HIL_DIR:-/tmp}"
die() { echo "REJECT $*" >&2; exit 1; }
usage() { echo "usage: ft-hil.sh [--add <계획 파일> [--supersedes h<M>] [--notify <좌석> [--notify-comm <쪽지함 폴더>]] | --cmd '<명령>' | --pending [--each] [--held] | --hold h<N> --why <사유> | --unhold h<N>]" >&2; exit 2; }

clip() {  # 클립보드 실패는 출력을 막지 않는다
  [ "${HIL_CLIP:-1}" != 0 ] && command -v pbcopy >/dev/null 2>&1 || return 0
  printf '%s' "$1" | pbcopy || echo "WARN 클립보드 복사 실패 — 위 줄을 손으로 치면 된다" >&2
}

rp() {  # 절대경로(실재하면 realpath 폴더 기준) — 대상 비교용
  local x="$1"; [[ "$x" = /* ]] || x="$D/$x"
  if [ -e "$x" ]; then echo "$(cd "$(dirname "$x")" && pwd -P)/$(basename "$x")"; else echo "$x"; fi
}

max_n() {  # $D/h<숫자> (링크·파일·깨진 링크 모두) 중 최대 번호 — 손 선례(/tmp/h1·h2)와 겹치지 않게
  local f n m=0
  for f in "$D"/h[0-9]*; do
    [ -e "$f" ] || [ -L "$f" ] || continue
    n="${f##*/h}"; [[ "$n" =~ ^[0-9]+$ ]] || continue
    [ "$((10#$n))" -le "$m" ] || m="$((10#$n))"
  done
  echo "$m"
}

plan_of() {  # $1=h 파일 → 계획 절대경로(진입 파일 표식 줄 · 옛 링크). 둘 다 아니면 빈 값
  if [ -L "$1" ]; then rp "$(readlink "$1")"
  elif [ -f "$1" ]; then sed -n 's/^# ft-hil-entry plan=//p' "$1" | head -1
  fi
}

entry_body() {  # $1=계획 $2=표식 접두(=진입 파일) $3=쪽지함 $4=요청 좌석(공백) — 대체됨 거절 · 시작 시각 → 계획 실행(stdout 사본 .out) → rc 기록 → r1117 결과 쪽지(실패해도 rc 그대로)
  # r1126 진입 머리: 계획 리포 공용 루트로 cd + FT_ROOT unset(리졸버 = 그 리포 LIVE_ROOT = 착지가 읽는 폴더) · 리포 밖(--cmd·시험) = 지금처럼 + INFO · 리포 안 ∧ LIVE_ROOT 없음 = 판정 불가 rc3(계획 실행 0)
  printf '#!/usr/bin/env bash\n# ft-hil-entry plan=%s\nP=%q; M=%q; N=%q; C=%q; S=%q\n' "$1" "$1" "$2" "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/ft-hil-notify.sh" "$3" "$4"
  cat <<'EOS'
[ ! -f "$M.superseded" ] || { echo "REJECT 대체됨 → $(cat "$M.superseded")" >&2; exit 1; }
[ -f "$P" ] || { echo "REJECT 계획 파일이 없다: $P" >&2; exit 1; }
date +%s >> "$M.ran"
( umask 077; : > "$M.out" )
rc=""; R="$(git -C "$(dirname "$P")" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; R="${R%/.git}"
if [ -z "$R" ]; then echo "INFO 리포 밖 계획 — cd 0 ($P)" >&2; elif [ ! -f "$R/.fable-team/LIVE_ROOT" ]; then echo "판정 불가 — 계획 $P 의 리포($R)에 .fable-team/LIVE_ROOT 없음" | tee "$M.out" >&2; rc=3
elif cd "$R"; then unset FT_ROOT; else echo "판정 불가 — 계획 리포 루트로 cd 실패: $R" | tee "$M.out" >&2; rc=3; fi
[ -n "$rc" ] || { bash "$P" "$@" | tee "$M.out"; rc=${PIPESTATUS[0]}; }
echo "rc=$rc $(date +%s)" >> "$M.ran"
bash "$N" done "$M" "$rc" "$C" $S || echo "WARN 결과 쪽지 실패 — h rc 는 그대로($rc)" >&2
exit "$rc"
EOS
}
# .ran = 실행마다 «시작 epoch» + «rc=<n> <epoch>» 이어 쓰기(r1124) — 읽기는 마지막 시작 줄·마지막 줄 기준
age_min() { local t; t="$(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1")"; echo $(( ($(date +%s) - t) / 60 )); }
last_start() { sed -n '/^[0-9][0-9]*$/h; ${x;p;}' "$1.ran" 2>/dev/null; }
last_rc() { tail -n 1 "$1.ran" 2>/dev/null | sed -n 's/^rc=\([0-9]*\) .*/\1/p'; }  # 마지막 줄이 rc 행일 때만(= 마지막 실행이 끝남)
since_min() { local s; s="$(last_start "$1")"; [[ "$s" =~ ^[0-9]+$ ]] || { age_min "$1.ran"; return; }; echo $(( ($(date +%s) - s) / 60 )); }  # 읽을 수 없으면 mtime 기준
done_rc() { [ -n "$(last_rc "$1")" ]; }
hhmm() { date -r "$1" +%H:%M 2>/dev/null || date -d "@$1" +%H:%M; }

lint() {  # <계획> <판정기> <검사 이름> <REJECT 머리> — R135a 비밀 출력 경로 · r1133 날 트래픽 전환. 걸리면 등록 0(rc 1). 판정기 없음은 경고만 · 판정기 실행 실패는 ERROR 등록 0(R170)
  local j="$2" out rc l first=1
  [ -f "$j" ] || { echo "WARN $3 검사를 건너뛴다(판정기 없음)" >&2; return 0; }
  out="$(python3 "$j" --plan "$1" 2>/dev/null)"; rc=$?
  [ "$rc" != 0 ] || return 0
  case "$out" in reject*) ;; *) echo "ERROR ft-hil 판정기 실행 실패(rc=$rc): $j — 등록 0" >&2; return 1;; esac  # reject 글 없는 rc≠0 = 판정기가 죽은 것(빈 사유 REJECT 금지 · #0 RULE)
  while IFS= read -r l; do
    if [ "$first" = 1 ]; then echo "REJECT $4${l#reject }" >&2; first=0; else echo "  — ${l#reject }" >&2; fi
  done <<< "$out"
  return 1
}
seat_lint() {  # R718: 좌석 이름 = P6 문법(ft-name-lint.sh) — 실패면 REJECT rc2(등록 0)
  local l="$(dirname "${BASH_SOURCE[0]}")/ft-name-lint.sh" why
  if [ -f "$l" ]; then
    why="$(bash "$l" "$1" 2>&1)" || { echo "REJECT 좌석 이름 린트 실패: ${why:-$1}" >&2; return 1; }
  else
    case "$1" in ''|*[!A-Za-z0-9._#-]*) echo "REJECT 좌석 이름 모양이 아니다: $1" >&2; return 1;; esac
  fi
  return 0
}
comm_default() {  # 부른 곳의 공용 루트 쪽지함(ft_comm_dir · 못 풀면 빈 줄 rc1)
  local b; b="$(dirname "${BASH_SOURCE[0]}")"
  . "$b/ft-harness-root.sh"
  ft_comm_dir "$b"
}

add() {
  local f="${1:-}" sup="${2:-}" ns="${3:-}" nc="${4:-}" t l n="" i=0 m="" rq=() rc_c="" new=""
  [ -f "$f" ] || die "계획 파일이 없다: $f"
  read -ra rq <<< "$(sed -n 's/^# ft-hil-request seat=//p' "$f" | head -1)"   # r1117: 결과 쪽지 받을 요청 좌석(최대 3) — 린트 실패 = REJECT rc2(등록 0)
  [ "${#rq[@]}" -le 3 ] || { echo "REJECT 요청 좌석은 3개까지: ${rq[*]}" >&2; exit 2; }
  for l in ${rq[@]+"${rq[@]}"}; do seat_lint "$l" || exit 2; done
  [ "${#rq[@]}" -gt 0 ] || echo "WARN 요청 좌석 표식 없음 — planner 에만 알린다(# ft-hil-request seat=<좌석>)" >&2
  rc_c="$(comm_default 2>/dev/null)" || echo "WARN 쪽지함 폴더를 못 풂 — 결과 쪽지는 실행 때 다시 푼다" >&2
  [ -z "$sup" ] || { [[ "$sup" =~ ^h[0-9]+$ ]] || die "--supersedes 값은 h<번호> 꼴이다: $sup"; m="$((10#${sup#h}))"; }
  if [ -n "$ns" ]; then  # 표식 검사는 등록 «전» — 실패면 h 파일을 만들지 않는다
    seat_lint "$ns" || exit 2
    [ -n "$nc" ] || nc="$(comm_default)" || { echo "REJECT 쪽지함 폴더를 못 풂 — --notify-comm <폴더> 를 줘라" >&2; exit 2; }
    [ -d "$nc" ] || { echo "REJECT 쪽지함 폴더가 없다: $nc" >&2; exit 2; }
  fi
  l="$(dirname "${BASH_SOURCE[0]}")"; lint "$f" "${FT_SECRET_JUDGE:-$l/ft_secret_judge.py}" "비밀 출력 경로" "계획 파일 비밀 출력 경로 — " && lint "$f" "${FT_TRAFFIC_JUDGE:-$l/ft_traffic_plan_judge.py}" "트래픽 전환" "" && lint "$f" "${FT_SCOPE_JUDGE:-$l/ft_scope_plan_judge.py}" "범위 승인 경로" "" || exit 1
  t="$(rp "$(cd "$(dirname "$f")" && pwd -P)/$(basename "$f")")"
  case "$t" in *[[:cntrl:]]*) die "계획 경로에 개행·제어문자가 있다(진입 파일 주입 방지): ${t//[[:cntrl:]]/?}";; esac
  mkdir -p "$D" || die "진입점 폴더를 못 만들었다: $D"
  until mkdir "$D/.hil.lock" 2>/dev/null; do
    i=$((i + 1)); [ "$i" -le 100 ] || die "락 선점 중: $D/.hil.lock"; sleep 0.1
  done
  trap 'rmdir "$D/.hil.lock" 2>/dev/null' EXIT
  for l in "$D"/h[0-9]*; do  # 같은 계획의 기존 h<N> 재사용 — 이미 대체된 것은 되살리지 않는다
    [ -e "$l" ] || [ -L "$l" ] || continue
    [[ "${l##*/h}" =~ ^[0-9]+$ ]] && [ ! -e "$l.superseded" ] && [ "$(plan_of "$l")" = "$t" ] && { n="${l##*/h}"; break; }
  done
  if [ -n "$m" ]; then
    [ -e "$D/h$m" ] || [ -L "$D/h$m" ] || die "대체할 h$m 이 없다: $D/h$m"
    [ ! -L "$D/h$m" ] && [ -n "$(plan_of "$D/h$m")" ] || die "h$m 은 옛 링크·손 파일이라 대체 표시를 못 한다(거절 장치 없음)"
    [ ! -e "$D/h$m.superseded" ] || die "h$m 은 이미 대체됨 → $(cat "$D/h$m.superseded")"
    [ "$m" != "$n" ] || die "h$m 자신을 대체할 수 없다"
  fi
  if [ -z "$n" ]; then
    n="$(($(max_n) + 1))"
    [ ! -e "$D/h$n" ] && [ ! -L "$D/h$n" ] && ( set -C; entry_body "$t" "$D/h$n" "$rc_c" "${rq[*]-}" > "$D/h$n" ) 2>/dev/null || die "등록 실패(이미 있는 이름은 덮지 않는다): $D/h$n"; new=1
  fi
  [ -z "$m" ] || echo "h$n" > "$D/h$m.superseded" || die "대체 표시를 못 썼다: $D/h$m.superseded"
  [ -z "$ns" ] || printf 'seat=%s\ncomm=%s\n' "$ns" "$nc" > "$D/h$n.notify" || die "수신자 표식을 못 썼다: $D/h$n.notify"
  rmdir "$D/.hil.lock"; trap - EXIT
  [ -z "$ns" ] || [ -z "$new" ] || bash "$(dirname "${BASH_SOURCE[0]}")/ft-hil-notify.sh" issue "$D/h$n" "$t" "$nc" "$ns" 2>/dev/null || echo "WARN [HIL] 쪽지 실패 — h$n 은 등록됨 · 틱 30분 알림이 남는다(to=$ns comm=$nc)" >&2   # r1130: 새 h 만 1통
  echo "! bash $D/h$n"
  clip "bash $D/h$n"
}

cmdplan() {
  local f
  [ -n "${1:-}" ] || die "--cmd 에는 명령 문자열이 필요하다"
  mkdir -p "$D/hil-cmd" || die "진입점 폴더를 못 만들었다: $D/hil-cmd"
  f="$D/hil-cmd/$(date +%Y%m%d-%H%M%S)-$$.sh"
  printf '#!/usr/bin/env bash\n%s\n' "$1" > "$f" || die "계획 파일을 못 썼다: $f"
  add "$f"
}

state_of() {  # $1=h 파일 → 대체됨 → h<N> | 실행 HH:MM rc=<n> | 미실행 <분>분 | 옛 링크(표식 없음) | -
  local f="$1" s e r
  [ -L "$f" ] && { echo "옛 링크(표식 없음)"; return; }
  [ -n "$(plan_of "$f")" ] || { echo "-"; return; }
  [ ! -e "$f.superseded" ] || { echo "대체됨 → $(cat "$f.superseded")"; return; }
  [ -e "$f.ran" ] || { echo "미실행 $(age_min "$f")분"; return; }
  s="$(last_start "$f")"; r="$(last_rc "$f")"
  [ -n "$r" ] || { echo "중단/실행 중 $(since_min "$f")분"; return; }  # rc 행 없음 = 끝났는지 모른다(완료로 세지 않는다)
  echo "실행 $(hhmm "$s") rc=$r"
}
marker_of() {  # $1=h 파일 → `수신=<좌석>@<쪽지함>` | `수신=표식 손상` | `수신=-` (r718)
  local nf="$1.notify" s c
  [ -e "$nf" ] || { echo "수신=-"; return; }
  s="$(sed -n 's/^seat=//p' "$nf" 2>/dev/null | head -1)"; c="$(sed -n 's/^comm=//p' "$nf" 2>/dev/null | head -1)"
  [ -n "$s" ] && [ -n "$c" ] || { echo "수신=표식 손상"; return; }
  echo "수신=$s@$c"
}
list() {
  local i l any=0 m; m="$(max_n)"
  for ((i = 1; i <= m; i++)); do
    l="$D/h$i"; { [ -e "$l" ] || [ -L "$l" ]; } || continue
    any=1
    printf 'h%s  %s  %s  %s  %s\n' "$i" "$(p="$(plan_of "$l")"; echo "${p:-(링크 아님)}")" "$([ -e "$l" ] && echo 실재 || echo 없음)" "$(state_of "$l")" "$(marker_of "$l")"
  done
  [ "$any" = 1 ] || echo "(등록 없음)"
}

pending() {  # 진입 파일만 센다 · 미실행 + 중단/실행 중 · r521 파이썬 1회 훑기(읽기 실패 = rc 3) · r1236 --hold/--unhold 도 같은 본체 · $@ = --each/--held 또는 --hold h<N> --why <사유>
  python3 "$(dirname "${BASH_SOURCE[0]}")/ft_hil_pending.py" "$D" "$@"
}

case "${1:-}" in
  "") list ;;
  --add) shift; af=""; as=""; an=""; ac=""
         while [ $# -gt 0 ]; do
           case "$1" in
             --supersedes) [ -n "${2:-}" ] || { usage; }; as="$2"; shift 2 ;;
             --notify) [ -n "${2:-}" ] || { usage; }; an="$2"; shift 2 ;;
             --notify-comm) [ -n "${2:-}" ] || { usage; }; ac="$2"; shift 2 ;;
             -*) usage ;;
             *) [ -z "$af" ] || usage; af="$1"; shift ;;
           esac
         done
         [ -n "$af" ] || usage
         [ -z "$ac" ] || [ -n "$an" ] || { echo "usage: --notify-comm 은 --notify 와 함께 쓴다" >&2; exit 2; }
         add "$af" "$as" "$an" "$ac" ;;
  --cmd) cmdplan "${2:-}" ;;
  --pending|--hold|--unhold) [ "$1" != --pending ] || shift; pending "$@" ;;
  *) usage ;;
esac
