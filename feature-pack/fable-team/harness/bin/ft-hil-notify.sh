#!/usr/bin/env bash
# ft-hil-notify.sh — r1117: 오빠 승인 h 의 결과·승인 도착을 기다리는 좌석에 쪽지 1통씩(사람 손 중계 0). 부르는 쪽 rc 는 바꾸지 않는다.
#   done <h 표식 접두> <rc> [쪽지함 폴더] [좌석…]  h<N> 진입 파일 끝(ft-hil.sh entry_body) — `[완료 h<N>] rc=<rc> · <결과 줄> · 계획 <경로>`
#        결과 줄 = <접두>.out 의 마지막 «=== 결과 ===» 줄 · 없으면 마지막 줄 · 200자 절단. 수신 = 좌석들 + 쪽지함 옆 seats-planner.json _master·_desk(같은 좌석 1통)
#        r1517: 끝에 화면 블록 1개(stdout) — `남은 미실행 h N: h2(12분) h3(3분)` + `다음 실행 줄 = ! bash <h 폴더>/h2`(가장 작은 번호 · .ran 있는 중단분 제외 · 남은 0 이면 «남은 미실행 h 0» 1줄) ·
#               쪽지 본문 끝에 ` · 남은 N · 다음 h2` 꼬리(남은 0 이면 꼬리 0). 목록 = 같은 폴더로 ft-hil.sh --pending --each 1회(규칙 변경 0 · 부르기만).
#               목록 읽기 실패 = stderr «판정 불가» 1줄 + 블록·꼬리 0(«0개» 로 쓰지 않는다) · done rc 는 쪽지 결과 그대로(진입 파일 rc = 계획 rc)
#   wait <40hex> <상태 폴더>  ft-merge-land «오빠 승인 파일 없음» 거절 — <상태>/autonomy-merge-wait/<sha> 에 `seat=<FT_SEAT|unknown> epoch=<now>` 1줄(있으면 덧쓰기 0)
#   approved <40hex> <상태 폴더>  approve-merge 끝(ft-autonomy.sh) — <상태>/autonomy-merge-wait/<sha>(ft-merge-land 거절 표식)가 있으면
#        seat= 에 `[승인 도착 <sha10>]` 1통 → 표식을 <sha>.sent 로(두 번 0) · seat=unknown = planner _master 에 «수신자 모름» 1통 · 표식 없음 = 아무것도 안 함
#   issue <h 진입 파일> <계획> <쪽지함> <좌석>  r1130: ft-hil.sh --add --notify 등록 직후 그 좌석에 `[HIL] h<N> 발급 — 실행 줄 = ! bash <h> (자율 ON = desk … · OFF = 오빠께) · 계획 <경로>` 1통(7초 · 재시도 0 · r1142 실행 주체 고정 문구 · 자율 상태 읽기 0)
#   void-scan <상태 폴더> <리포…>  r1200: 기다림 표식 중 어느 리포에도 커밋이 아닌 sha(오타)만 <sha>.void 로 · «VOID <sha> seat=…» 줄 + 끝 줄 «void-scan 끝 바꿈=N 그대로=M»
#   발신자 = ft-hil-h<N> · ft-hil-approve(도구 발신자 = fan-out·속도 가드 면제 · mbox_guard._is_tool_sender) · 쪽지함 생략 = ft_comm_dir · 실패 = stderr «판정 불가» 1줄 + rc1(하드 룰 20)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
die() { echo "ft-hil-notify 판정 불가 — $*" >&2; exit 1; }
comm() { [ -n "${1:-}" ] && { printf '%s\n' "$1"; return; }; . "$HERE/ft-harness-root.sh" && ft_comm_dir "$HERE"; }
seat_of() { python3 -c 'import json,sys;v=json.load(open(sys.argv[1]+"/../seats-planner.json")).get(sys.argv[2]);print(v if isinstance(v,str) else "")' "$1" "$2" 2>/dev/null; }  # r1517: _master·_desk 공용(없거나 문자열 아님 = 빈 값)
send() {  # <쪽지함> <발신자> <본문> <수신…> — 빈 이름·같은 역할(끝 #N 뺀 이름 = mbox_conf.role_key · r1159)은 건너뛴다
  local c="$1" f="$2" b="$3" to k seen=" " bad=0 o="" rc=0; shift 3
  [ -f "$c/mbox.sh" ] || die "쪽지함 도구 없음: $c/mbox.sh"
  for to in "$@"; do k="$to"; [[ "$to" =~ ^(.*)#[0-9]+$ ]] && k="${BASH_REMATCH[1]}"
    [ -n "$to" ] && [[ "$seen" != *" $k "* ]] || continue; seen="$seen$k "
    # r1517(HOLD aifp#796): 실패 이유를 버리지 않는다 — rc + 출력 첫 줄 200자(없으면 빈 자리)
    o="$(bash "$c/mbox.sh" send "$to" "$f" "$b" 2>&1)"; rc=$?
    [ "$rc" = 0 ] || { o="${o%%$'\n'*}"; echo "ft-hil-notify 판정 불가 — mbox send rc=$rc to=$to${o:+ · ${o:0:200}}" >&2; bad=1; }; done
  [ "$seen" != " " ] || die "수신자 0(요청 좌석 표식 없음 · planner _master 없음)"
  return "$bad"
}
pending_block() {  # r1517: <h 폴더> → PB_BLOCK(화면 1~2줄) · PB_TAIL(쪽지 꼬리) · 읽기 실패 = stderr «판정 불가» 1줄 rc1(PB_* 비움)
  local d="$1" out rc name min n=0 items="" next="" num
  PB_BLOCK=""; PB_TAIL=""
  [ -d "$d" ] || { echo "ft-hil-notify 판정 불가 — h 폴더가 없다: $d" >&2; return 1; }
  out="$(HIL_DIR="$d" bash "$HERE/ft-hil.sh" --pending --each 2>/dev/null)"; rc=$?
  [ "$rc" = 0 ] || { echo "ft-hil-notify 판정 불가 — 미실행 h 목록 읽기 실패(rc=$rc): $d" >&2; return 1; }
  while read -r name min; do
    [ -n "$name" ] || continue
    [[ "$name" =~ ^h[0-9]+$ && "$min" =~ ^-?[0-9]+$ ]] || { echo "ft-hil-notify 판정 불가 — 미실행 h 목록 줄 모양이 아니다: «$name $min»" >&2; PB_BLOCK=""; PB_TAIL=""; return 1; }
    n=$((n + 1)); items="$items $name(${min}분)"
    [ ! -e "$d/$name.ran" ] || continue   # 다음 줄 후보 = .ran 없는 h 만(중단·실행 중 제외)
    num="${name#h}"; [ -z "$next" ] || [ "$((10#$num))" -lt "$((10#${next#h}))" ] || continue; next="$name"
  done <<< "$out"
  if [ "$n" -eq 0 ]; then PB_BLOCK="남은 미실행 h 0"; return 0; fi
  PB_BLOCK="남은 미실행 h $n:$items"; PB_TAIL=" · 남은 $n"
  [ -z "$next" ] || { PB_BLOCK="$PB_BLOCK
다음 실행 줄 = ! bash $d/$next"; PB_TAIL="$PB_TAIL · 다음 $next"; }
}
done_mail() {
  local m="$1" rc="$2" c n r b s=0
  c="$(comm "${3:-}")" || die "쪽지함 폴더를 못 풂"; shift 3 2>/dev/null || shift $#
  n="${m##*/}"; r="$(grep '=== 결과 ===' "$m.out" 2>/dev/null | tail -1)"; [ -n "$r" ] || r="$(tail -1 "$m.out" 2>/dev/null)"
  b="[완료 $n] rc=$rc · ${r:0:200} · 계획 $(sed -n 's/^# ft-hil-entry plan=//p' "$m" 2>/dev/null | head -1)"
  pending_block "${m%/*}"   # r1517: 실패 = stderr 1줄 · 쪽지는 꼬리 없이 그대로 나간다
  send "$c" "ft-hil-$n" "$b$PB_TAIL" "$@" "$(seat_of "$c" _master)" "$(seat_of "$c" _desk)" || s=1
  [ -z "$PB_BLOCK" ] || printf '%s\n' "$PB_BLOCK"
  return "$s"
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
  else send "$c" ft-hil-approve "[승인 도착 ${s:0:10}] 수신자 모름(거절 표식 seat=${seat:-빈 값}) — 거절받은 좌석에 ft-merge-land 다시 실행을 전한다" "$(seat_of "$c" _master)"; fi || exit 1
  mv -f "$w" "$w.sent" || die "표식 이름 바꾸기 실패: $w"
}
void_scan() {  # r1200: <상태 폴더> <리포…> — 확장자 없는 40hex 기다림 표식 중 어느 리포에도 커밋이 아닌 것만 <sha>.void 로(지우기 0 · 되돌림 = mv) · 리포 git 실패 = 판정 불가 rc1 · 바꿈 0
  local d="$1/autonomy-merge-wait" r f s n=0 k=0; shift
  for r in "$@"; do git -C "$r" rev-parse --git-dir >/dev/null 2>&1 || die "리포 판정 불가: $r(바꿈 0)"; done
  for f in "$d"/*; do s="${f##*/}"; [[ "$s" =~ ^[0-9a-f]{40}$ ]] && [ -f "$f" ] || continue
    for r in "$@"; do git -C "$r" cat-file -e "$s^{commit}" 2>/dev/null && { k=$((k+1)); continue 2; }; done
    mv -- "$f" "$f.void" || die "표식 이름 바꾸기 실패: $f"; echo "VOID $s seat=$(sed -n 's/^seat=\([^ ]*\).*/\1/p' "$f.void" | head -1)"; n=$((n+1)); done
  echo "void-scan 끝 바꿈=$n 그대로=$k"; }
issue_mail() {  # r1130: <h 진입 파일> <계획> <쪽지함> <좌석> — ft-hil.sh --add --notify 등록 직후 1통 · 7초 · 재시도 0
  local n="${1##*/}" to; to="$(command -v timeout || command -v gtimeout)" || to=""
  [ -f "$3/mbox.sh" ] || die "쪽지함 도구 없음: $3/mbox.sh"
  FT_MBOX_DIR="$3" ${to:+"$to" 7} bash "$3/mbox.sh" send "$4" "ft-hil-$n" "[HIL] $n 발급 — 실행 줄 = ! bash $1 (자율 ON = desk 가 PR head 확인 뒤 실행 · OFF = 오빠께) · 계획 $2" >/dev/null 2>&1 || die "mbox send rc≠0 to=$4"
}
case "${1:-}" in
  done) [ $# -ge 3 ] || die "usage: done <접두> <rc> [쪽지함] [좌석…]"; shift; done_mail "$@" ;;
  issue) [ $# -eq 5 ] || die "usage: issue <h 진입 파일> <계획> <쪽지함> <좌석>"; shift; issue_mail "$@" ;;
  approved|wait) [ $# -eq 3 ] || die "usage: $1 <40hex> <상태 폴더>"; if [ "$1" = wait ]; then wait_mark "$2" "$3"; else approved_mail "$2" "$3"; fi ;;
  void-scan) [ $# -ge 3 ] || die "usage: void-scan <상태 폴더> <리포…>"; shift; void_scan "$@" ;;
  *) die "usage: ft-hil-notify.sh done|wait|approved|issue|void-scan …" ;;
esac
