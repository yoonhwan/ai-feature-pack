#!/usr/bin/env bash
# ft-hil-gate.sh — h 등록 · 진입 파일의 sha 잠금 · 다시 등록 · 걸린 초 보조 (r2078 · 실사건 #309264 GO 뒤 계획 수정 · #309281 70초 넘김). ft-hil.sh 와 진입 파일이 부른다.
#   pre <계획>                 → 판정기 사슬 «앞» sha256(64자) 1줄 · 100000바이트 초과 = REJECT rc 1 · 못 구함 = 판정 불가 rc 3
#   post <계획> <앞 sha>        → 사슬 «뒤» sha 가 다르면 `REJECT 등록 중 계획이 바뀜 — 판정 앞 … ≠ 판정 뒤 …` rc 1
#   write <sha> <h 파일>        → <h>.sha 에 1줄
#   reuse <sha> <h 파일> [대체 번호] → 같은 경로 다시 등록: stdout = 같은 번호 · `<번호>+`(.sha 없음 = 옛 꼴 → 진입 파일 새 꼴로 다시 쓰기)
#                                  · 빈 줄(내용 바뀜 + --supersedes 그 h = 새 번호) · 내용 바뀜 + 대체 없음 = REJECT rc 1
#   read <계획> <h 파일>        → 계획을 «한 번» 읽어 sha 를 <h>.sha 와 견준다 · 같으면 그 바이트 + 끝 표식 1자(.)를 stdout(치환이 끝 개행을 지우지 않게)
#                                  다름 = REJECT 1줄 rc 1 · .sha 없음 · 못 읽음 = 판정 불가 rc 3 (rc 와 바이트는 섞지 않는다 — 진입 파일이 표식만 떼고 bash -c 로 실행)
#                                  ★r2343: .held 확인 바로 뒤 = 보류 쪽지 관문★ 실행 좌석 ∪ 요청 좌석 쪽지함에 «그 h 보류» 쪽지가 미읽음이면 REJECT 1줄 rc 1(계획 바이트 0) · 확인 못 함 = 판정 불가 rc 3
#   seen <h 파일> <seq,…> <까닭> → <h>.seen 에 «seen <epoch> <실행 좌석|-> <seq,…> <까닭>» 1줄(r2343 H6 · 남의 쪽지함 recv 0 · 까닭 빈칸 = REJECT rc 2 쓰기 0) · gate read 가 그 seq 만 빼고 «본 것으로 침 #seq» 1줄
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
# ── r2343 보류 쪽지 관문 — 보류가 쪽지로만 와서 실행과 엇갈린 사고(h8625 · h8627)를 막는다. 자리 = .held 뒤 · .sha 대조 앞(바이트가 나간 뒤엔 못 멈춘다 · M6) ──
hm_seats() {  # <계획> <h 파일> → 좌석 1줄당 1개 · 중복 0 · 실행 좌석(env FT_SEAT) ∪ 요청 좌석(계획 머리 «# ft-hil-request seat=» 최대 3) ∪ <h>.notify seat=
  { printf '%s\n' "${FT_SEAT:-}"
    sed -n 's/^#[[:space:]]*ft-hil-request[[:space:]]*seat=//p' "$1" 2>/dev/null | head -1 | tr ' ' '\n' | head -3
    sed -n 's/^seat=//p' "$2.notify" 2>/dev/null; } | sed '/^$/d' | awk '!s[$0]++' | grep -E '^[A-Za-z0-9._#-]+$'   # 좌석 이름 꼴 밖 = 쪽지함 이름이 될 수 없다(mbox NAME_RE) — 볼 곳 0
}
hm_comm() {  # <계획> <h 파일> → 쪽지함 폴더 · notify comm= 먼저 · 없으면 계획 리포 .fable-team/comm · 빈 값 = 리포 밖(하네스 밖)
  local c r
  c="$(sed -n 's/^comm=//p' "$2.notify" 2>/dev/null | head -1)"; [ -z "$c" ] || { printf '%s' "$c"; return; }
  r="$(perl -e 'alarm 7; exec @ARGV' git -C "$(dirname -- "$1")" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 0
  r="${r%/.git}"; [ -n "$r" ] && printf '%s' "$r/.fable-team/comm"; return 0
}
hm_rows() {  # <쪽지함 폴더> <좌석> <남은 초> → peek --rows(1회 상한 7초 · 하드 룰 12) · rc = peek rc(142 = 시간 넘김)
  local w="$3"; [ "$w" -ge 1 ] || w=1; [ "$w" -gt 7 ] && w=7
  perl -e 'alarm shift; exec @ARGV' "$w" bash "$1/mbox.sh" peek "$2" --rows 2>/dev/null
}
hm_seen() { sed -n 's/^seen [0-9][0-9]* [^ ]* \([0-9][0-9,]*\) .*/\1/p' "$1.seen" 2>/dev/null | tr ',' '\n' | grep -E '^[0-9]+$' | sort -u | paste -sd, -; }  # r2343 H6 — 본 것으로 침 seq 만
hm_pick() {  # <h 번호> <계획 경로> <seen seq,…> ← peek 행(JSON 1줄) → 고른 줄 «seq» 1줄씩 · H3 고르기
  local py; py="$(cat <<'PY'
import json, re, sys
n, plan, seen = sys.argv[1], sys.argv[2].split("/")[-1], {x for x in sys.argv[3].split(",") if x}
kw = ("보류", "멈춤", "중단", "정지", "apply 0", "실행 0")                     # DA 메모 1 — 정지·stop 더함 · 취소 뺌
wrd = re.compile(r"\b(hold|stop)\b", re.I)                                       # ⑯ 영문 낱말 경계(threshold·holder = 아님) · M8 대소문자
hit = re.compile(r"(?<![0-9A-Za-z])h" + n + r"(?![0-9A-Za-z])", re.I)              # ④ 번호 경계 · M2
auto = re.compile(r"^\s*(\[HIL\]\s*h" + n + r"\s*발급|\[완료\s*h" + n + r"\]|\[HIL 미실행\])")   # ③ r1130 자동 쪽지 · M5
for ln in sys.stdin:
    ln = ln.strip()
    if not ln.startswith("{"):
        continue
    try:
        r = json.loads(ln)
    except ValueError:
        continue
    b = re.sub(r"\s+", " ", str(r.get("body", "")))                            # ⑮ 전문(700자 넘는 쪽지 포함) — 잘린 사본을 보지 않는다
    if not b or str(r.get("seq")) in seen or auto.match(b):                    # M7 = seq 대신 h 전체를 뺌
        continue
    if (hit.search(b) or plan in b) and (wrd.search(b) or any(k in b for k in kw)):   # M1 낱말 거름
        print(r.get("seq"))
PY
)"; python3 -c "$py" "$1" "$2" "$3"; }
hm_gate() {  # <계획> <h 파일> → 통과 = 0(침묵) · 미읽음 = REJECT rc 1 · 확인 못 함 = 판정 불가 rc 3 · 계획 바이트 출력 0
  local p="$1" m="$2" n c seen t0 left rc out s x hits=() line=""
  n="${m##*/h}"; [[ "$n" =~ ^[0-9]+$ ]] || return 0
  s="$(hm_seats "$p" "$m")"; [ -n "$s" ] || return 0                                        # 좌석 0 = 볼 쪽지함 0(옛 꼴 계획 = 지금 그대로)
  c="$(hm_comm "$p" "$m")"                                                                  # M4 = 요청 좌석을 빼고 FT_SEAT 만
  [ -n "$c" ] || { echo "INFO 보류 쪽지 확인 건너뜀 — 계획 리포 밖(쪽지함 못 정함 · $p)" >&2; return 0; }
  [ -f "$c/mbox.sh" ] || { echo "판정 불가 — 보류 쪽지 확인 못 함 (쪽지함 도구 없음: $c/mbox.sh · 계획 실행 0)" >&2; return 3; }
  seen="$(hm_seen "$m")"; t0="$(date +%s)"
  while IFS= read -r x; do
    left=$((25 - ($(date +%s) - t0))); [ "$left" -ge 1 ] || { echo "판정 불가 — 보류 쪽지 확인 못 함 (좌석 3개 25초 상한 · 다음 좌석 $x · 계획 실행 0)" >&2; return 3; }
    for _w in 1 2; do out="$(hm_rows "$c" "$x" "$left")"; rc=$?; [ "$rc" = 0 ] && break; [ "$rc" = 142 ] || break; left=$((25 - ($(date +%s) - t0))); [ "$left" -ge 1 ] || break; done   # 1회 7초 + 재시도 1
    [ "$rc" = 0 ] || { echo "판정 불가 — 보류 쪽지 확인 못 함 (peek rc=$rc · 좌석 $x · 계획 실행 0)" >&2; return 3; }   # M3 = 실패를 통과로
    for s in $(printf '%s\n' "$out" | hm_pick "$n" "$p" "$seen"); do hits+=("#$s $x"); done
  done <<< "$s"
  if [ "${#hits[@]}" -ge 1 ]; then
    for s in "${hits[@]}"; do line="$line${line:+ · }$s"; done
    echo "REJECT 보류 쪽지 미읽음 ${#hits[@]} — $line · 읽고 판정한 뒤 다시${seen:+ · 본 것으로 침 #$seen}" >&2; return 1
  fi
  [ -z "$seen" ] || echo "INFO 보류 쪽지 관문 — 본 것으로 침 #$seen (계획 실행)" >&2
  return 0
}
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
    hm_gate "$2" "$3" || exit $?   # r2343 — 보류 쪽지 관문(.held 뒤 · .sha 대조 앞 = ① M6)
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
  seen)  # seen <h 파일> <seq,…> <까닭> — 남의 쪽지함 recv 0 · 까닭 빈칸 = REJECT rc 2(쓰기 0) · H6
    [ -n "${4:-}" ] || { echo "REJECT 까닭이 빈칸 — seen <h 파일> <seq,…> <까닭> (쓰기 0)" >&2; exit 2; }
    case "${3:-}" in ''|*[!0-9,]*) echo "REJECT seq 칸이 «숫자,숫자» 가 아님 — ${3:-} (쓰기 0)" >&2; exit 2 ;; esac
    [ -e "$2" ] || { echo "REJECT h 파일이 없다 — $2 (쓰기 0)" >&2; exit 2; }
    printf 'seen %s %s %s %s\n' "$(date +%s)" "${FT_SEAT:--}" "$3" "$4" >> "$2.seen" || { echo "판정 불가 — .seen 못 씀: $2.seen" >&2; exit 3; } ;;
  *) echo "usage: ft-hil-gate.sh pre|post|write|reuse|read|budget|run-line|seen …" >&2; exit 2 ;;
esac
