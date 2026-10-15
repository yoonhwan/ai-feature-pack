#!/usr/bin/env bash
# ft-hil.sh — 사람이 `!` 로 칠 계획 파일(*.sh.hil 등)을 짧은 진입 파일 /tmp/h<N> 으로 등록한다 (R83 · 판정 850·853 · R186 판정 1720). 도구·오케가 부른다.
#   ft-hil.sh --add <계획 파일> [--supersedes h<M>]  → stdout `! bash $HIL_DIR/h<N>` 1줄 (클립보드는 보조: pbcopy 가 있고 HIL_CLIP≠0)
#                                  h<M> 을 «대체됨» 으로 적는다 — h<M> 을 치면 `REJECT 대체됨 → h<N>` rc 1 · 계획 실행 0
#   ft-hil.sh --cmd '<명령>'      → 명령 1줄 계획을 $HIL_DIR/hil-cmd/<시각>.sh 로 쓰고 --add 와 같은 처리
#   ft-hil.sh                     → 목록 `h<N>  <대상>  <대상 실재 여부>  <미실행 N분 | 실행 HH:MM rc=n | 대체됨 → h<N>>`
#   ft-hil.sh --pending [--each]  → 미실행·미대체 h 요약 1줄(0개면 출력 없음) · --each 는 `h<N> <분>` 줄만
# h<N> = «실행되면 h<N>.ran(시작 시각 · rc)을 남기고 계획을 그대로 실행하는» 진입 파일. 계획 파일 수정 0 · 실행 권한 변경 0.
# 진입점 폴더 = ${HIL_DIR:-/tmp}(시험만 바꾼다) · 홈($HOME) 아래 쓰기 0 · 등록기 자신의 실행 기능 0(실행은 사람이 `bash /tmp/h<N>`)
# 기존 h<N>(링크·파일) 덮기·지우기 0 · 계획 파일 수정·삭제 0 · eval 0. 옛 링크 h<N> 은 그대로 둔다(표식 없음 · 대체 표시 불가).
# 등록 전 검사(R135a): 같은 폴더 ft_secret_judge.py --plan — 비밀을 화면으로 흘리는 줄이 있으면 `REJECT 계획 파일 비밀 출력 경로 — <줄> <이유>` rc 1(등록 0).
set -uo pipefail
D="${HIL_DIR:-/tmp}"
die() { echo "REJECT $*" >&2; exit 1; }

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

entry_body() {  # $1=계획 절대경로 $2=표식 접두(=진입 파일 경로) — 대체됨이면 거절 · 시작 시각 → 계획 실행 → rc 기록
  printf '#!/usr/bin/env bash\n# ft-hil-entry plan=%s\nP=%q; M=%q\n' "$1" "$1" "$2"
  cat <<'EOS'
[ ! -f "$M.superseded" ] || { echo "REJECT 대체됨 → $(cat "$M.superseded")" >&2; exit 1; }
[ -f "$P" ] || { echo "REJECT 계획 파일이 없다: $P" >&2; exit 1; }
date +%s > "$M.ran"
bash "$P" "$@"; rc=$?
echo "rc=$rc $(date +%s)" >> "$M.ran"; exit "$rc"
EOS
}

age_min() { local t; t="$(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1")"; echo $(( ($(date +%s) - t) / 60 )); }
since_min() {  # 진입 파일 .ran 1행(시작 epoch) 이후 분 — 읽을 수 없으면 파일 mtime 기준
  local s; s="$(sed -n 1p "$1.ran" 2>/dev/null)"; [[ "$s" =~ ^[0-9]+$ ]] || { age_min "$1.ran"; return; }
  echo $(( ($(date +%s) - s) / 60 ))
}
done_rc() { grep -q '^rc=[0-9]* ' "$1.ran" 2>/dev/null; }  # 종료 rc 행이 있나
hhmm() { date -r "$1" +%H:%M 2>/dev/null || date -d "@$1" +%H:%M; }

lint() {  # R135a: 계획 파일의 비밀 출력 경로 검사 — 걸리면 등록 0(rc 1). 판정기 없음은 경고만 · 판정기 실행 실패는 ERROR 등록 0(R170)
  local j="${FT_SECRET_JUDGE:-$(dirname "${BASH_SOURCE[0]}")/ft_secret_judge.py}" out rc l first=1
  [ -f "$j" ] || { echo "WARN 비밀 출력 경로 검사를 건너뛴다(판정기 없음)" >&2; return 0; }
  out="$(python3 "$j" --plan "$1" 2>/dev/null)"; rc=$?
  [ "$rc" != 0 ] || return 0
  case "$out" in reject*) ;; *) echo "ERROR ft-hil 판정기 실행 실패(rc=$rc): $j — 등록 0" >&2; return 1;; esac  # reject 글 없는 rc≠0 = 판정기가 죽은 것(빈 사유 REJECT 금지 · #0 RULE)
  while IFS= read -r l; do
    if [ "$first" = 1 ]; then echo "REJECT 계획 파일 비밀 출력 경로 — ${l#reject }" >&2; first=0; else echo "  — ${l#reject }" >&2; fi
  done <<< "$out"
  return 1
}

add() {
  local f="${1:-}" sup="${2:-}" t l n="" i=0 m=""
  [ -f "$f" ] || die "계획 파일이 없다: $f"
  [ -z "$sup" ] || { [[ "$sup" =~ ^h[0-9]+$ ]] || die "--supersedes 값은 h<번호> 꼴이다: $sup"; m="$((10#${sup#h}))"; }
  lint "$f" || exit 1
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
    [ ! -e "$D/h$n" ] && [ ! -L "$D/h$n" ] && ( set -C; entry_body "$t" "$D/h$n" > "$D/h$n" ) 2>/dev/null || die "등록 실패(이미 있는 이름은 덮지 않는다): $D/h$n"
  fi
  [ -z "$m" ] || echo "h$n" > "$D/h$m.superseded" || die "대체 표시를 못 썼다: $D/h$m.superseded"
  rmdir "$D/.hil.lock"; trap - EXIT
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
  s="$(sed -n 1p "$f.ran")"; r="$(sed -n 's/^rc=\([0-9]*\) .*/\1/p' "$f.ran" | tail -1)"
  [ -n "$r" ] || { echo "중단/실행 중 $(since_min "$f")분"; return; }  # rc 행 없음 = 끝났는지 모른다(완료로 세지 않는다)
  echo "실행 $(hhmm "$s") rc=$r"
}

list() {
  local i l any=0 m; m="$(max_n)"
  for ((i = 1; i <= m; i++)); do
    l="$D/h$i"; { [ -e "$l" ] || [ -L "$l" ]; } || continue
    any=1
    printf 'h%s  %s  %s  %s\n' "$i" "$(p="$(plan_of "$l")"; echo "${p:-(링크 아님)}")" "$([ -e "$l" ] && echo 실재 || echo 없음)" "$(state_of "$l")"
  done
  [ "$any" = 1 ] || echo "(등록 없음)"
}

pending() {  # 진입 파일만 센다(옛 링크는 실행 여부를 모른다) · 미실행 + 중단/실행 중(.ran 에 rc 행 없음) · $1=--each 면 `h<N> <분>` 줄만
  local f n k=0 old=0 a r=0
  for f in "$D"/h[0-9]*; do
    n="${f##*/h}"; [[ "$n" =~ ^[0-9]+$ ]] || continue
    [ -f "$f" ] && [ ! -L "$f" ] && [ -n "$(plan_of "$f")" ] && [ ! -e "$f.superseded" ] || continue
    if [ -e "$f.ran" ]; then done_rc "$f" && continue; a="$(since_min "$f")"; r=$((r + 1)); else a="$(age_min "$f")"; fi
    k=$((k + 1)); [ "$a" -le "$old" ] || old="$a"
    [ "${1:-}" != --each ] || echo "h$n $a"
  done
  [ "${1:-}" = --each ] || [ "$k" -eq 0 ] || echo "미실행 h ${k}개${r:+$([ "$r" -gt 0 ] && echo " (중단/실행 중 ${r}개 포함)")} · 가장 오래된 ${old}분"
}

case "${1:-}" in
  "") list ;;
  --add) { [ -z "${3:-}" ] || { [ "$3" = --supersedes ] && [ -n "${4:-}" ]; }; } || { echo "usage: ft-hil.sh --add <계획 파일> [--supersedes h<M>]" >&2; exit 2; }
         add "${2:-}" "${4:-}" ;;
  --cmd) cmdplan "${2:-}" ;;
  --pending) pending "${2:-}" ;;
  *) echo "usage: ft-hil.sh [--add <계획 파일> [--supersedes h<M>] | --cmd '<명령>' | --pending [--each]]" >&2; exit 2 ;;
esac
