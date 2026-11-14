#!/usr/bin/env bash
# ft-event-check.sh — r1474: 사건(h 실행 끝 · 나노 열림 · 나노 닫힘)이 생긴 «그 실행» 안에서 1회 재측정한다(STRATEGY-monitoring-event-driven §2 · DA APPROVE #274598).
#   hil   <h 진입 파일> <원 rc> <.out>  계획 머리 `# ft-hil-expect <대상> <running|exited0|absent|cmp0>` 줄마다 대조 · 원 rc≠0 이어도 돈다
#         running = launchctl print 의 `state = running` + pid 둘 다(loaded + last exit 0 만으로 OK 0 · DA 반례1) · exited0 = last exit code = 0
#         absent = 미적재 · cmp0 = LIVE_BIN/<대상> ↔ 팩 bin/<대상> cmp(팩 없음 = 판정 불가)
#         expect 줄 0개 = 실패(expect 없음) · 미적재·불일치 = 실패 · 조회 실패·시간 초과 = 판정 불가 · 재시도 0(최초 미준비 = 실패 · OK 치환 0)
#   spawn <좌석> <카드> <wt>    tmux 세션 실재 · 카드 «- 배정: 좌석 <좌석>» · wt HEAD ⊇ origin/main
#   close <좌석> <카드> [계획]  세션 0 · 카드 «- 상태:» 줄 · 워크트리 정리 계획 유무(기록 요약에만 · 판정 밖)
#   ready 는 아직 없다 — I-1(ready 계보 끝 결속) 착지 뒤(REVIEW-post-landing I-9).
#   stdout 1줄 `재측정: OK|실패|판정 불가 · 대상 N 중 실패 M · 불가 K[ — 사유]` · rc 0 OK · 1 실패 · 3 판정 불가 · 2 usage
#   기록 = <상태>/events/<YYYY-MM-DD>.tsv 1줄 `ts\t사건\t대상\t결과\trc=N\t요약≤120자` · 그날 첫 쓰기에 14일 지난 파일 삭제 · 실패 = stderr «판정 불가(기록)» 1줄(칸은 그대로)
#   부른 쪽 rc 불변(훅은 출력만 칸에 넣는다) · 주기 0 · 데몬 0 · 쪽지 0 · launchctl·tmux 변경 0 · 항목 7초 · 전체 25초(FT_EVENT_BUDGET)
#   env(시험·이식): FT_EVENT_LAUNCHCTL · FT_EVENT_TMUX · FT_EVENT_UID · FT_EVENT_NOW · FT_EVENT_BUDGET · FT_EVENT_DIR(events 폴더) · FT_EVENT_COMM(쪽지함 → <그 옆>/state/events) · FT_EVENT_LIVE_BIN · FT_EVENT_PACK_BIN
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
LC="${FT_EVENT_LAUNCHCTL:-launchctl}"
TMUXC="${FT_EVENT_TMUX:-tmux}"
UIDN="${FT_EVENT_UID:-$(id -u)}"
NOW="${FT_EVENT_NOW:-$(date +%s)}"
BUDGET="${FT_EVENT_BUDGET:-25}"
START="$(date +%s)"
. "$HERE/ft-harness-root.sh" 2>/dev/null || :   # ft_comm_dir · ft_harness_root(없으면 그 칸만 판정 불가·기록 불가)

to() {  # to <초> <명령…> — ft-now.sh 와 같은 꼴(timeout · gtimeout · perl alarm)
  local s="$1"; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$s" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$s" "$@"
  else perl -e 'alarm shift; exec @ARGV' "$s" "$@" 2>/dev/null; fi
}
X() {  # X <명령…> — 항목 7초 + 전체 예산 둘 다 · 시간 초과 = 124
  local l t t0 r; l=$(( BUDGET - ( $(date +%s) - START ) ))
  [ "$l" -ge 1 ] || return 124
  t=$(( l > 7 ? 7 : l )); t0="$(date +%s)"
  to "$t" "$@"; r=$?
  if [ "$r" -ge 124 ] && [ $(( $(date +%s) - t0 )) -ge "$t" ]; then return 124; fi
  return "$r"
}
N=0; NF=0; NN=0; WHY=()
_verdict() {  # ★3값 함수 하나★(ft-now.sh _verdict 꼴 복사) <대상> <OK|FAIL|NA> [사유] [rc]
  local i="$1" k="$2" w="${3:-}" rc="${4:-}"
  N=$((N+1))
  case "$k" in
    OK) ;;
    FAIL) NF=$((NF+1)); WHY+=("$i 실패${w:+($w)}");;
    *) NN=$((NN+1))
       if [ "$rc" = 124 ]; then WHY+=("$i 판정 불가(시간 초과)")
       elif [ -n "$rc" ]; then WHY+=("$i 판정 불가 rc=$rc${w:+($w)}")
       else WHY+=("$i 판정 불가${w:+($w)}"); fi;;
  esac
}

lc_one() {  # <라벨> <running|exited0|absent>
  local l="$1" k="$2" o rc st pid ex
  o="$(X "$LC" print "gui/$UIDN/$l" 2>&1 </dev/null)"; rc=$?
  if [ "$rc" -ne 0 ]; then
    if [ "$rc" = 124 ]; then _verdict "$l" NA "" 124
    elif [ "$rc" = 113 ] || [[ "$o" == *"Could not find service"* ]]; then
      if [ "$k" = absent ]; then _verdict "$l" OK; else _verdict "$l" FAIL 미적재; fi
    else _verdict "$l" NA "" "$rc"; fi
    return
  fi
  st="$(printf '%s\n' "$o" | sed -n 's/^[[:space:]]*state = //p' | head -1)"
  pid="$(printf '%s\n' "$o" | sed -n 's/^[[:space:]]*pid = //p' | head -1)"
  ex="$(printf '%s\n' "$o" | sed -n 's/^[[:space:]]*last exit code = //p' | head -1)"
  case "$k" in
    absent) _verdict "$l" FAIL 적재됨;;
    running) if [ "$st" = running ] && [ -n "$pid" ] && [ "$pid" != 0 ]; then _verdict "$l" OK; else _verdict "$l" FAIL "state=${st:-없음},pid=${pid:-없음}"; fi;;
    exited0) if [ "$ex" = 0 ]; then _verdict "$l" OK; else _verdict "$l" FAIL "exit=${ex:-없음}"; fi;;
  esac
}
cmp_one() {  # <bin 안 파일 이름> — LIVE_BIN ↔ 팩 bin
  local f="$1" lb="${FT_EVENT_LIVE_BIN:-}" pb="${FT_EVENT_PACK_BIN:-}" c r rc
  case "$f" in */*|.|..) _verdict "$f" FAIL "이름 꼴(경로 금지)"; return;; esac
  [ -n "$lb" ] || { c="$(comm_dir)" && lb="${c%/*}/bin"; }
  [ -n "$pb" ] || { r="$(ft_harness_root "$HERE" 2>/dev/null)" && pb="$r/bin"; }
  [ -n "$lb" ] && [ -n "$pb" ] || { _verdict "$f" NA "LIVE_BIN·팩 bin 못 풂"; return; }
  [ -f "$pb/$f" ] || { _verdict "$f" NA "팩 파일 없음"; return; }
  [ -f "$lb/$f" ] || { _verdict "$f" FAIL "LIVE 없음"; return; }
  cmp -s "$lb/$f" "$pb/$f"; rc=$?
  case "$rc" in 0) _verdict "$f" OK;; 1) _verdict "$f" FAIL 불일치;; *) _verdict "$f" NA cmp "$rc";; esac
}
sess() {  # <좌석> <있어야 1|없어야 0>
  local o rc
  o="$(X "$TMUXC" has-session -t "=$1" 2>&1 </dev/null)"; rc=$?
  if [ "$rc" = 0 ]; then
    if [ "$2" = 1 ]; then _verdict 세션 OK; else _verdict 세션 FAIL 남음; fi
  elif [ "$rc" = 1 ] && [[ "$o" == *"can't find session"* || "$o" == *"no server running"* || "$o" == *"error connecting"* ]]; then
    if [ "$2" = 1 ]; then _verdict 세션 FAIL 없음; else _verdict 세션 OK; fi
  else _verdict 세션 NA "" "$rc"; fi
}
card_head() {  # <카드> → 첫 «## » 앞 머리 줄들
  awk '/^##[[:space:]]/{exit} {print}' "$1"
}

comm_dir() {  # FT_EVENT_COMM(h 진입 파일에 박힌 쪽지함) > ft_comm_dir
  if [ -n "${FT_EVENT_COMM:-}" ]; then [ -d "$FT_EVENT_COMM" ] && printf '%s\n' "$FT_EVENT_COMM"; else declare -F ft_comm_dir >/dev/null && ft_comm_dir "$HERE" 2>/dev/null; fi; }
rec() {  # <사건> <대상> <결과> <rc> <요약>
  local LC_ALL=en_US.UTF-8 d="${FT_EVENT_DIR:-}" c="" day f cut x s
  [ -n "$d" ] || { c="$(comm_dir)" && d="${c%/*}/state/events"; }
  day="$(date -r "$NOW" +%F 2>/dev/null || date -d "@$NOW" +%F)"; f="$d/$day.tsv"
  s="$(printf '%s' "$5" | tr '\t\n' '  ')"; s="${s:0:120}"
  { [ -n "$d" ] && mkdir -p "$d" && if [ ! -f "$f" ]; then   # 그날 첫 쓰기 = 닫는 사건(14일 지난 파일 삭제)
      cut="$(date -r $((NOW - 14*86400)) +%F 2>/dev/null || date -d "@$((NOW - 14*86400))" +%F)"
      for x in "$d"/????-??-??.tsv; do [ -f "$x" ] || continue; [[ "${x##*/}" < "$cut.tsv" ]] && rm -f -- "$x"; done; true
    fi && printf '%s\t%s\t%s\t%s\trc=%s\t%s\n' "$(date -r "$NOW" +%FT%T 2>/dev/null || date +%FT%T)" "$1" "$2" "$3" "$4" "$s" >> "$f"; } 2>/dev/null \
    || echo "ft-event-check 판정 불가(기록) — ${d:+$f}${d:-events 폴더 못 풂(쪽지함 루트 없음)}" >&2
}
fin() {  # <사건> <대상> <요약 머리> [결과 고정]
  local k rc line why=""
  if [ -n "${4:-}" ]; then k="$4"; rc=1
  elif [ "$NF" -gt 0 ]; then k=실패; rc=1
  elif [ "$NN" -gt 0 ]; then k="판정 불가"; rc=3
  else k=OK; rc=0; fi
  [ "${#WHY[@]}" -eq 0 ] || why="$(printf '%s, ' "${WHY[@]}")"; why="${why%, }"
  line="재측정: $k · 대상 $N 중 실패 $NF · 불가 $NN${why:+ — $why}"
  rec "$1" "$2" "$k" "$rc" "$3${why:+ · $why}"
  printf '%s\n' "$line"; exit "$rc"
}
usage() { echo "재측정: 판정 불가(사용법) — ft-event-check.sh hil <h 진입 파일> <원 rc> <.out> | spawn <좌석> <카드> <wt> | close <좌석> <카드> [계획]"; exit 2; }

case "${1:-}" in
  hil)
    [ $# -eq 4 ] || usage; m="$2"; orc="$3"; h="${m##*/}"
    p="$(sed -n 's/^# ft-hil-entry plan=//p' "$m" 2>/dev/null | head -1)"
    [ -n "$p" ] && [ -f "$p" ] || { _verdict 계획 NA "진입 파일·계획 못 읽음"; fin hil "$h" "원 rc=$orc"; }
    ex="$(grep '^# ft-hil-expect ' "$p" 2>/dev/null)"
    [ -n "$ex" ] || fin hil "$h" "원 rc=$orc · expect 줄 0" "실패(expect 없음)"
    while read -r _ _ t k _; do
      case "$k" in running|exited0|absent) lc_one "$t" "$k";; cmp0) cmp_one "$t";; *) _verdict "${t:-?}" FAIL "expect 꼴(${k:-없음})";; esac
    done <<< "$ex"
    fin hil "$h" "원 rc=$orc";;
  spawn)
    [ $# -eq 4 ] || usage; s="$2"; cd_="$3"; w="$4"
    sess "$s" 1
    if [ ! -f "$cd_" ]; then _verdict 카드 FAIL "카드 없음"
    elif card_head "$cd_" | sed 's/[[:space:]]*$//' | grep -qxF -- "- 배정: 좌석 $s"; then _verdict 배정 OK
    else _verdict 배정 FAIL "배정 줄 ≠ 좌석"; fi
    if [ ! -d "$w" ]; then _verdict wt FAIL "wt 없음"
    else X git -C "$w" merge-base --is-ancestor origin/main HEAD >/dev/null 2>&1 </dev/null; r=$?
      case "$r" in 0) _verdict wt OK;; 1) _verdict wt FAIL "HEAD ⊉ origin/main";; *) _verdict wt NA "" "$r";; esac; fi
    fin spawn "$s" "wt=$w";;
  close)
    [ $# -ge 3 ] && [ $# -le 4 ] || usage; s="$2"; cd_="$3"; pl="${4:-}"
    sess "$s" 0
    if [ -z "$cd_" ]; then _verdict 카드 NA "카드 경로 없음"
    elif [ ! -f "$cd_" ]; then _verdict 카드 FAIL "카드 없음"
    elif card_head "$cd_" | grep -q '^- 상태:'; then _verdict 상태줄 OK
    else _verdict 상태줄 FAIL "«- 상태:» 줄 없음"; fi
    fin close "$s" "정리 계획 ${pl:+있음 $pl}${pl:-없음}";;
  *) usage;;
esac
