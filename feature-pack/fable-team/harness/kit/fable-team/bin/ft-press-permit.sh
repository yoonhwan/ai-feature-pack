#!/usr/bin/env bash
# ft-press-permit.sh — C7 시험 허가 2종 (오디오 장치는 1개뿐 → 세트는 병렬로 두되 소리 시험은 한 번에 하나)
#   ①세트 허가  set-<세트>.json = {held, owner, members[]}  — 같은 세트에 참여하는 시험(멤버) 수 상한 FT_PERMIT_MAX_MEMBERS(기본 1)
#   ②장치 허가  device.json     = {held, member}            — 오디오 장치 1개
#   한 바퀴: join → device-acquire → device-release → leave. 허가 파일 조작만 한다(마이크·오디오 실행 없음).
#   set-acquire <세트> <owner> | set-release <세트> | join <세트> <멤버> | leave <세트> <멤버>
#   device-acquire <멤버> | device-release <멤버> | status
#   허가 디렉터리 FT_PERMIT_DIR(기본 <리포>/.fable-team/state/permits/ — 시험은 mktemp) · JSON 은 임시파일 뒤 mv 로 원자 갱신.
#   exit 0 = 성공 · 1 = REJECT(사유 stdout) · 2 = usage
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
DIR="${FT_PERMIT_DIR:-$HERE/../../.fable-team/state/permits}"
MAX="${FT_PERMIT_MAX_MEMBERS:-1}"
usage() { echo "usage: $0 set-acquire <세트> <owner> | set-release <세트> | join <세트> <멤버> | leave <세트> <멤버> | device-acquire <멤버> | device-release <멤버> | status" >&2; exit 2; }
reject() { echo "REJECT $*"; exit 1; }
need() { [ "$1" -eq "$2" ] || usage; }  # need <실제 인자 수> <필요 수>
[[ "$MAX" =~ ^[1-9][0-9]*$ ]] || usage
command -v jq >/dev/null || { echo "jq 필요" >&2; exit 2; }
mkdir -p "$DIR"

setfile() { echo "$DIR/set-$1.json"; }
devfile() { echo "$DIR/device.json"; }
write() { # write <파일> <JSON> — 임시파일 뒤 mv
  local tmp; tmp="$(mktemp "$DIR/.tmp.XXXXXX")" && printf '%s\n' "$2" >"$tmp" && mv "$tmp" "$1"
}
members_of() { jq -r '.members | length' "$(setfile "$1")"; }
has_member() { jq -e --arg m "$2" '.members | index($m) != null' "$(setfile "$1")" >/dev/null; }
any_set_has() { # 멤버가 어느 세트에든 가입했나
  local f
  for f in "$DIR"/set-*.json; do
    [ -e "$f" ] || continue
    jq -e --arg m "$1" '.members | index($m) != null' "$f" >/dev/null && return 0
  done
  return 1
}
need_set() { [ -e "$(setfile "$1")" ] || reject "세트 $1 허가 없음 — set-acquire 먼저"; }

cmd="${1:-}"; [ -n "$cmd" ] && shift || usage
case "$cmd" in
  set-acquire)
    need $# 2; s="$1"; owner="$2"
    [ -e "$(setfile "$s")" ] && reject "세트 $s 이미 held (owner=$(jq -r .owner "$(setfile "$s")"))"
    write "$(setfile "$s")" "$(jq -nc --arg o "$owner" '{held:true,owner:$o,members:[]}')"
    echo "OK set-acquire $s owner=$owner max_members=$MAX" ;;
  set-release)
    need $# 1; s="$1"; need_set "$s"
    n="$(members_of "$s")"
    [ "$n" -eq 0 ] || reject "세트 $s 에 멤버 ${n}명 남음($(jq -r '.members|join(",")' "$(setfile "$s")")) — leave 먼저"
    rm -f "$(setfile "$s")"
    echo "OK set-release $s" ;;
  join)
    need $# 2; s="$1"; m="$2"; need_set "$s"
    has_member "$s" "$m" && reject "멤버 $m 이미 세트 $s 에 가입됨"
    n="$(members_of "$s")"
    [ "$n" -lt "$MAX" ] || reject "세트 $s 멤버 상한 ${MAX} 도달($(jq -r '.members|join(",")' "$(setfile "$s")")) — 두 번째 가입 거부"
    write "$(setfile "$s")" "$(jq -c --arg m "$m" '.members += [$m]' "$(setfile "$s")")"
    echo "OK join $s $m members=$((n+1))/$MAX" ;;
  leave)
    need $# 2; s="$1"; m="$2"; need_set "$s"
    has_member "$s" "$m" || reject "멤버 $m 은 세트 $s 에 없음"
    [ -e "$(devfile)" ] && [ "$(jq -r .member "$(devfile)")" = "$m" ] && reject "멤버 $m 이 장치 허가를 쥔 채 탈퇴 불가 — device-release 먼저"
    write "$(setfile "$s")" "$(jq -c --arg m "$m" '.members -= [$m]' "$(setfile "$s")")"
    echo "OK leave $s $m" ;;
  device-acquire)
    need $# 1; m="$1"
    any_set_has "$m" || reject "멤버 $m 은 어느 세트에도 가입 안 됨 — join 먼저"
    [ -e "$(devfile)" ] && reject "장치 허가 이미 held (member=$(jq -r .member "$(devfile)")) — 두 번째 장치 요청 거부"
    write "$(devfile)" "$(jq -nc --arg m "$m" '{held:true,member:$m}')"
    echo "OK device-acquire $m" ;;
  device-release)
    need $# 1; m="$1"
    [ -e "$(devfile)" ] || reject "장치 허가 없음"
    [ "$(jq -r .member "$(devfile)")" = "$m" ] || reject "장치 허가는 $(jq -r .member "$(devfile)") 가 쥠 — $m 이 해제 불가"
    rm -f "$(devfile)"
    echo "OK device-release $m" ;;
  status)
    need $# 0
    echo "dir=$DIR max_members=$MAX"
    for f in "$DIR"/set-*.json; do [ -e "$f" ] && echo "set $(basename "$f" .json | sed 's/^set-//') $(jq -c . "$f")"; done
    if [ -e "$(devfile)" ]; then echo "device $(jq -c . "$(devfile)")"; else echo "device free"; fi ;;
  *) usage ;;
esac
