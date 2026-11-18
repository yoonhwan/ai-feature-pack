#!/usr/bin/env bash
# ft-hil-gate.sh — h 등록 · 진입 파일의 sha 잠금 · 다시 등록 · 걸린 초 보조 (r2078 · 실사건 #309264 GO 뒤 계획 수정 · #309281 70초 넘김). ft-hil.sh 와 진입 파일이 부른다.
#   pre <계획>                 → 판정기 사슬 «앞» sha256(64자) 1줄 · 100000바이트 초과 = REJECT rc 1 · 못 구함 = 판정 불가 rc 3
#   post <계획> <앞 sha>        → 사슬 «뒤» sha 가 다르면 `REJECT 등록 중 계획이 바뀜 — 판정 앞 … ≠ 판정 뒤 …` rc 1
#   write <sha> <h 파일>        → <h>.sha 에 1줄
#   reuse <sha> <h 파일> [대체 번호] → 같은 경로 다시 등록: stdout = 같은 번호 · `<번호>+`(.sha 없음 = 옛 꼴 → 진입 파일 새 꼴로 다시 쓰기)
#                                  · 빈 줄(내용 바뀜 + --supersedes 그 h = 새 번호) · 내용 바뀜 + 대체 없음 = REJECT rc 1
#   read <계획> <h 파일>        → 계획을 «한 번» 읽어 sha 를 <h>.sha 와 견준다 · 같으면 그 바이트 + 끝 표식 1자(.)를 stdout(치환이 끝 개행을 지우지 않게)
#                                  다름 = REJECT 1줄 rc 1 · .sha 없음 · 못 읽음 = 판정 불가 rc 3 (rc 와 바이트는 섞지 않는다 — 진입 파일이 표식만 떼고 bash -c 로 실행)
#   budget <계획|-> <h 파일> [시작 끝] → 선언 초(`# ft-hil-budget: <초>` · - = stdin 의 실행한 바이트 · 없으면 70)와 .ran 마지막 시작 줄 · rc 줄 시각 차(시험은 인자로 주입)
#                                  넘으면 `[상한 초과] …` 1줄을 stderr 와 <h>.out 끝에 · 늘 rc 0(계획 rc 는 진입 파일이 그대로)
#   run-line <h 파일>           → r2161: 실행 줄 1줄(앞 «! » 없음) · 계획(«# ft-hil-entry plan=»)의 주석 아닌 줄에 `$HIL_APPROVED` · `${HIL_APPROVED` 읽기가 있으면
#                                  «bash <h> · 승인값 필요(사람 · 변수 HIL_APPROVED · 오빠 ! 줄로만)» · 아니면(옛 링크 · 계획 없음 · 못 읽음 포함) «bash <h>» · 늘 rc 0 · 승인값 «=1» 은 찍지 않는다
#                                  r2164: 그 표지일 때 계획에 «# ft-hil-oppa-ask: <질문 ts>» 1줄 + <h>.sha 64자 → ft_oppa_slack_check --plan-sha 1회(7초 + 재시도 1) · SLACK-OK 면
#                                  «… · 오빠 승인 reply=<ts> · desk 값 넣기 가능 · 실행 줄에 ts 기록» · 그 밖(ask 0 제외) = r2161 표지 + « · <사유>» · ask 0 = r2161 표지 그대로
set -uo pipefail
MAXB=100000
sha256() {  # stdin → sha256 64자(못 구하면 rc 3 · 판정 불가 1줄)
  local s
  if command -v shasum >/dev/null 2>&1; then s="$(shasum -a 256)"; else s="$(sha256sum)"; fi
  s="${s%% *}"; [[ "$s" =~ ^[0-9a-f]{64}$ ]] || { echo "판정 불가 — 계획 sha256 을 못 구함: ${1:-}" >&2; return 3; }
  echo "$s"
}
fsha() { [ -f "$1" ] && [ -r "$1" ] || { echo "판정 불가 — 계획 파일을 못 읽음: $1" >&2; return 3; }; sha256 "$1" < "$1"; }
old() { head -1 "$1.sha" 2>/dev/null; }
desk_tag() {  # r2164 <h> <계획> → 승인값 표지 꼬리 1개 · 계획에 적힌 ts 만으로는 열지 않는다(확인기가 질문 글의 그 64자 + 오빠 승인 답글을 봐야 열림)
  local a n s o rc=142 r
  a="$(grep -E '^[[:space:]]*#[[:space:]]*ft-hil-oppa-ask:' "$2" 2>/dev/null)"; n="$(printf '%s' "$a" | grep -c .)"
  [ "$n" != 0 ] || { echo "$TAG_R"; return; }
  [ "$n" = 1 ] || { echo "$TAG_R · ask 줄 여럿"; return; }
  a="$(printf '%s\n' "$a" | head -1)"; a="${a#*:}"; a="${a//[[:space:]]/}"; s="$(old "$1")"
  [[ "$s" =~ ^[0-9a-fA-F]{64}$ ]] || { echo "$TAG_R · sha 없음"; return; }
  for _ in 1 2; do  # 하드 룰 12 · 1회 7초(alarm · rc 142) + 재시도 1
    [ "$rc" = 142 ] || break
    o="$(perl -e 'alarm 7; exec @ARGV' python3 "$(dirname -- "${BASH_SOURCE[0]}")/ft_oppa_slack_check.py" "$a" --plan-sha "$s" 2>/dev/null)"; rc=$?
  done
  r="${o##* reply=}"
  if [ "$rc" = 0 ] && [ "$o" = "SLACK-OK $s parent=${a#*:} reply=$r" ] && [[ "$r" =~ ^[0-9]+\.[0-9]{6}$ ]]; then
    echo " · 승인값 필요(변수 HIL_APPROVED) · 오빠 승인 reply=$r · desk 값 넣기 가능 · 실행 줄에 ts 기록"; return
  fi
  case "$rc:$o" in 3:*|2:*"답글 없음"*) r="답글 없음";; 2:*"판정 불가"*) r="판정 불가";; "2:REJECT "*) r="거절";; *) r="판정 불가";; esac
  echo "$TAG_R · $r"; }
case "${1:-}" in
  pre)
    b="$(wc -c < "$2" 2>/dev/null | tr -d ' ')"; [[ "$b" =~ ^[0-9]+$ ]] || { echo "판정 불가 — 계획 크기를 못 구함: $2" >&2; exit 3; }
    [ "$b" -le "$MAXB" ] || { echo "REJECT 계획이 너무 큼 — $b > $MAXB" >&2; exit 1; }
    fsha "$2" ;;
  post)
    s="$(fsha "$2")" || exit 3
    [ "$s" = "$3" ] || { echo "REJECT 등록 중 계획이 바뀜 — 판정 앞 ${3:0:16} ≠ 판정 뒤 ${s:0:16}" >&2; exit 1; } ;;
  write) echo "$2" > "$3.sha" || { echo "판정 불가 — sha 표식을 못 씀: $3.sha" >&2; exit 3; } ;;
  reuse)
    n="${3##*/h}"; o="$(old "$3")"
    if [ ! -f "$3.sha" ]; then echo "$n+"
    elif [ "$2" = "$o" ]; then echo "$n"
    elif [ "${4:-}" = "$n" ]; then echo ""
    else echo "REJECT 계획이 바뀜 — h$n 등록 ${o:0:16} ≠ 지금 ${2:0:16} · --supersedes h$n 을 붙여 다시 등록" >&2; exit 1; fi ;;
  read)
    [ ! -e "$3.held" ] || { l="$(sed -n '/[^[:space:]]/h; ${x;p;}' "$3.held")" || { echo "판정 불가 — ${3##*/}.held 못 읽음(계획 실행 0)" >&2; exit 3; }; case "$l" in "hold "*) l="${l#hold }"; echo "REJECT 보류 중 — ${l#* } · 풀기 = ft-hil.sh --unhold ${3##*/}" >&2; exit 1;; esac; }   # r2130 K1: 마지막 비지 않은 줄이 hold = 보류 · 계획 바이트 0
    [ -f "$3.sha" ] || { echo "판정 불가 — ${3##*/}.sha 없음(새 꼴 진입 파일 · 계획 실행 0)" >&2; exit 3; }
    [ -f "$2" ] && b="$(cat -- "$2" && printf .)" || { echo "판정 불가 — 계획 파일을 못 읽음: $2" >&2; exit 3; }
    s="$(printf '%s' "${b%.}" | sha256 "$2")" || exit 3; o="$(old "$3")"
    [ "$s" = "$o" ] || { echo "REJECT 계획이 등록 뒤 바뀜 — 등록 ${o:0:16} ≠ 지금 ${s:0:16} · 다시 등록(--add $2 --supersedes ${3##*/})" >&2; exit 1; }
    printf '%s' "$b" ;;
  budget)
    if [ "$2" = - ]; then src="$(cat)"; else src="$(cat -- "$2" 2>/dev/null)"; fi
    d="$(printf '%s\n' "$src" | sed -n 's/^[[:space:]]*#[[:space:]]*ft-hil-budget:[[:space:]]*\([0-9][0-9]*\)[[:space:]]*$/\1/p' | head -1)"; d="$((10#${d:-70}))"
    st="${4:-$(sed -n '/^[0-9][0-9]*$/h; ${x;p;}' "$3.ran" 2>/dev/null)}"
    en="${5:-$(tail -n 1 "$3.ran" 2>/dev/null | sed -n 's/^rc=[0-9]* \([0-9][0-9]*\)$/\1/p')}"
    [[ "$st" =~ ^[0-9]+$ && "$en" =~ ^[0-9]+$ ]] || exit 0
    e=$((en - st)); [ "$e" -gt "$d" ] || exit 0
    l="[상한 초과] ${3##*/} ${e}초 > ${d}초 — 묶음을 줄여 다시 등록"
    echo "$l" >&2; echo "$l" >> "$3.out" ;;
  run-line)
    t=""; TAG_R=" · 승인값 필요(사람 · 변수 HIL_APPROVED · 오빠 ! 줄로만)"; p="$(sed -n 's/^# ft-hil-entry plan=//p' "${2:-}" 2>/dev/null | head -1)"
    [ -L "${2:-}" ] || [ -z "$p" ] || ! awk '!/^[[:space:]]*#/ && (/\$HIL_APPROVED/ || /\$[{]HIL_APPROVED/) {f=1} END {exit !f}' "$p" 2>/dev/null || t="$TAG_R"
    [ -z "$t" ] || t="$(desk_tag "$2" "$p")"   # r2164
    echo "bash ${2:-}$t"; exit 0 ;;
  *) echo "usage: ft-hil-gate.sh pre|post|write|reuse|read|budget|run-line …" >&2; exit 2 ;;
esac
