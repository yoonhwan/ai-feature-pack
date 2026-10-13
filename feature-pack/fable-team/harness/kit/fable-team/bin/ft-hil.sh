#!/usr/bin/env bash
# ft-hil.sh — 사람이 `!` 로 칠 계획 파일(*.sh.hil 등)을 짧은 링크 /tmp/h<N> 으로 등록한다 (R83 · 판정 850·853). 도구·오케가 부른다.
#   ft-hil.sh --add <계획 파일>   → stdout `! bash $HIL_DIR/h<N>` 1줄 (클립보드는 보조: pbcopy 가 있고 HIL_CLIP≠0)
#   ft-hil.sh --cmd '<명령>'      → 명령 1줄 계획을 $HIL_DIR/hil-cmd/<시각>.sh 로 쓰고 --add 와 같은 처리
#   ft-hil.sh                     → 목록 `h<N>  <대상>  <대상 실재 여부>`
# 진입점 폴더 = ${HIL_DIR:-/tmp}(시험만 바꾼다) · 홈($HOME) 아래 쓰기 0 · 실행 기능 0(실행은 사람이 `bash /tmp/h<N>`)
# 기존 h<N>(링크·파일) 덮기·지우기 0 · 계획 파일 수정·삭제 0 · eval 0.
# 등록 전 검사(R135a): 같은 폴더 ft_secret_judge.py --plan — 비밀을 화면으로 흘리는 줄이 있으면 `REJECT 계획 파일 비밀 출력 경로 — <줄> <이유>` rc 1(등록 0).
set -uo pipefail
D="${HIL_DIR:-/tmp}"
die() { echo "REJECT $*" >&2; exit 1; }

clip() {  # 클립보드 실패는 출력을 막지 않는다
  [ "${HIL_CLIP:-1}" != 0 ] && command -v pbcopy >/dev/null 2>&1 || return 0
  printf '%s' "$1" | pbcopy || echo "WARN 클립보드 복사 실패 — 위 줄을 손으로 치면 된다" >&2
}

rp() {  # 절대경로(실재하면 realpath 폴더 기준) — 링크 대상 비교용
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

lint() {  # R135a: 계획 파일의 비밀 출력 경로 검사 — 걸리면 등록 0(rc 1). 판정기 없음·내부 오류는 경고만(fail-open)
  local j="${FT_SECRET_JUDGE:-$(dirname "${BASH_SOURCE[0]}")/ft_secret_judge.py}" out rc l first=1
  [ -f "$j" ] || { echo "WARN 비밀 출력 경로 검사를 건너뛴다(판정기 없음)" >&2; return 0; }
  out="$(python3 "$j" --plan "$1" 2>/dev/null)"; rc=$?
  [ "$rc" != 0 ] || return 0
  [ "$rc" = 1 ] || { echo "WARN 비밀 출력 경로 검사 실패(rc=$rc) — 검사 없이 등록한다" >&2; return 0; }
  while IFS= read -r l; do
    if [ "$first" = 1 ]; then echo "REJECT 계획 파일 비밀 출력 경로 — ${l#reject }" >&2; first=0; else echo "  — ${l#reject }" >&2; fi
  done <<< "$out"
  return 1
}

add() {
  local f="${1:-}" t l n="" i=0
  [ -f "$f" ] || die "계획 파일이 없다: $f"
  lint "$f" || exit 1
  t="$(rp "$(cd "$(dirname "$f")" && pwd -P)/$(basename "$f")")"
  mkdir -p "$D" || die "진입점 폴더를 못 만들었다: $D"
  until mkdir "$D/.hil.lock" 2>/dev/null; do
    i=$((i + 1)); [ "$i" -le 100 ] || die "락 선점 중: $D/.hil.lock"; sleep 0.1
  done
  trap 'rmdir "$D/.hil.lock" 2>/dev/null' EXIT
  for l in "$D"/h[0-9]*; do
    [ -L "$l" ] && [ "$(rp "$(readlink "$l")")" = "$t" ] && { n="${l##*/h}"; break; }
  done
  if [ -z "$n" ]; then
    n="$(($(max_n) + 1))"
    [ ! -e "$D/h$n" ] && [ ! -L "$D/h$n" ] && ln -s "$t" "$D/h$n" || die "등록 실패(이미 있는 이름은 덮지 않는다): $D/h$n"
  fi
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

list() {
  local i l any=0 m; m="$(max_n)"
  for ((i = 1; i <= m; i++)); do
    l="$D/h$i"; { [ -e "$l" ] || [ -L "$l" ]; } || continue
    any=1
    printf 'h%s  %s  %s\n' "$i" "$([ -L "$l" ] && readlink "$l" || echo '(링크 아님)')" "$([ -e "$l" ] && echo 실재 || echo 없음)"
  done
  [ "$any" = 1 ] || echo "(등록 없음)"
}

case "${1:-}" in
  "") list ;;
  --add) add "${2:-}" ;;
  --cmd) cmdplan "${2:-}" ;;
  *) echo "usage: ft-hil.sh [--add <계획 파일> | --cmd '<명령>']" >&2; exit 2 ;;
esac
