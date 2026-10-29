#!/usr/bin/env bash
# ft-hil-notify.sh — r1117: 오빠 승인 h 의 결과·승인 도착을 기다리는 좌석에 쪽지 1통씩(사람 손 중계 0). 부르는 쪽 rc 는 바꾸지 않는다.
#   done <h 표식 접두> <rc> [쪽지함 폴더] [좌석…]  h<N> 진입 파일 끝(ft-hil.sh entry_body) — `[완료 h<N>] rc=<rc> · <결과 줄> · 계획 <경로>`
#        결과 줄 = <접두>.out 의 마지막 «=== 결과 ===» 줄 · 없으면 마지막 줄 · 200자 절단. 수신 = 좌석들 + 쪽지함 옆 seats-planner.json _master(같은 좌석 1통)
#   wait <40hex> <상태 폴더>  ft-merge-land «오빠 승인 파일 없음» 거절 — <상태>/autonomy-merge-wait/<sha> 에 `seat=<FT_SEAT|unknown> epoch=<now>` 1줄(있으면 덧쓰기 0)
#   approved <40hex> <상태 폴더>  approve-merge 끝(ft-autonomy.sh) — <상태>/autonomy-merge-wait/<sha>(ft-merge-land 거절 표식)가 있으면
#        seat= 에 `[승인 도착 <sha10>]` 1통 → 표식을 <sha>.sent 로(두 번 0) · seat=unknown = planner _master 에 «수신자 모름» 1통 · 표식 없음 = 아무것도 안 함
#   issue <h 진입 파일> <계획> <쪽지함> <좌석>  r1130: ft-hil.sh --add --notify 등록 직후 그 좌석에 `[HIL] h<N> 발급 — 실행 줄 = ! bash <h> (자율 ON = desk … · OFF = 오빠께) · 계획 <경로>` 1통(7초 · 재시도 0 · r1142 실행 주체 고정 문구 · 자율 상태 읽기 0)
#   발신자 = ft-hil-h<N> · ft-hil-approve(도구 발신자 = fan-out·속도 가드 면제 · mbox_guard._is_tool_sender) · 쪽지함 생략 = ft_comm_dir · 실패 = stderr «판정 불가» 1줄 + rc1(하드 룰 20)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
die() { echo "ft-hil-notify 판정 불가 — $*" >&2; exit 1; }
comm() { [ -n "${1:-}" ] && { printf '%s\n' "$1"; return; }; . "$HERE/ft-harness-root.sh" && ft_comm_dir "$HERE"; }
master_of() { python3 -c 'import json,sys;m=json.load(open(sys.argv[1])).get("_master");print(m if isinstance(m,str) else "")' "$1/../seats-planner.json" 2>/dev/null; }
send() {  # <쪽지함> <발신자> <본문> <수신…> — 빈 이름·같은 좌석은 건너뛴다
  local c="$1" f="$2" b="$3" to seen=" " bad=0; shift 3
  [ -f "$c/mbox.sh" ] || die "쪽지함 도구 없음: $c/mbox.sh"
  for to in "$@"; do [ -n "$to" ] && [[ "$seen" != *" $to "* ]] || continue; seen="$seen$to "
    bash "$c/mbox.sh" send "$to" "$f" "$b" >/dev/null 2>&1 || { echo "ft-hil-notify 판정 불가 — mbox send rc≠0 to=$to" >&2; bad=1; }; done
  [ "$seen" != " " ] || die "수신자 0(요청 좌석 표식 없음 · planner _master 없음)"
  return "$bad"
}
done_mail() {
  local m="$1" rc="$2" c n r
  c="$(comm "${3:-}")" || die "쪽지함 폴더를 못 풂"; shift 3 2>/dev/null || shift $#
  n="${m##*/}"; r="$(grep '=== 결과 ===' "$m.out" 2>/dev/null | tail -1)"; [ -n "$r" ] || r="$(tail -1 "$m.out" 2>/dev/null)"
  send "$c" "ft-hil-$n" "[완료 $n] rc=$rc · ${r:0:200} · 계획 $(sed -n 's/^# ft-hil-entry plan=//p' "$m" 2>/dev/null | head -1)" "$@" "$(master_of "$c")"
}
wait_mark() {  # <40hex> <상태 폴더> — 이미 있으면 덧쓰기 0 · stdout « · 기다림 등록 <경로>»(REJECT 줄 끝에 붙는다)
  local w="$2/autonomy-merge-wait/$1" s; s="$(printf '%s' "${FT_SEAT:-unknown}" | tr -cd 'A-Za-z0-9#._-')"
  { mkdir -p "${w%/*}" && { [ -e "$w" ] || ( set -C; printf 'seat=%s epoch=%s\n' "${s:-unknown}" "$(date +%s)" > "$w" ); }; } 2>/dev/null || die "기다림 표식 쓰기 실패: $w(승인 도착 알림 0)"
  printf ' · 기다림 등록 %s' "$w"; }
approved_mail() {
  local s="$1" w="$2/autonomy-merge-wait/$1" seat c
  [ -f "$w" ] || return 0
  seat="$(sed -n 's/^seat=\([^ ]*\).*/\1/p' "$w" | head -1)"; c="$(comm)" || die "쪽지함 폴더를 못 풂"
  if [ -n "$seat" ] && [ "$seat" != unknown ]; then send "$c" ft-hil-approve "[승인 도착 ${s:0:10}] approve-merge 끝 — ft-merge-land 다시 실행" "$seat"
  else send "$c" ft-hil-approve "[승인 도착 ${s:0:10}] 수신자 모름(거절 표식 seat=${seat:-빈 값}) — 거절받은 좌석에 ft-merge-land 다시 실행을 전한다" "$(master_of "$c")"; fi || exit 1
  mv -f "$w" "$w.sent" || die "표식 이름 바꾸기 실패: $w"
}
issue_mail() {  # r1130: <h 진입 파일> <계획> <쪽지함> <좌석> — ft-hil.sh --add --notify 등록 직후 1통 · 7초 · 재시도 0
  local n="${1##*/}" to; to="$(command -v timeout || command -v gtimeout)" || to=""
  [ -f "$3/mbox.sh" ] || die "쪽지함 도구 없음: $3/mbox.sh"
  FT_MBOX_DIR="$3" ${to:+"$to" 7} bash "$3/mbox.sh" send "$4" "ft-hil-$n" "[HIL] $n 발급 — 실행 줄 = ! bash $1 (자율 ON = desk 가 PR head 확인 뒤 실행 · OFF = 오빠께) · 계획 $2" >/dev/null 2>&1 || die "mbox send rc≠0 to=$4"
}
case "${1:-}" in
  done) [ $# -ge 3 ] || die "usage: done <접두> <rc> [쪽지함] [좌석…]"; shift; done_mail "$@" ;;
  issue) [ $# -eq 5 ] || die "usage: issue <h 진입 파일> <계획> <쪽지함> <좌석>"; shift; issue_mail "$@" ;;
  approved|wait) [ $# -eq 3 ] || die "usage: $1 <40hex> <상태 폴더>"; if [ "$1" = wait ]; then wait_mark "$2" "$3"; else approved_mail "$2" "$3"; fi ;;
  *) die "usage: ft-hil-notify.sh done|wait|approved …" ;;
esac
