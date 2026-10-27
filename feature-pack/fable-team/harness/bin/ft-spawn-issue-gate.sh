#!/usr/bin/env bash
# ft-spawn-issue-gate.sh <카드.md> — «착수 = 열린 깃 이슈» 게이트 (r823 · 오빠 발주 «시작시 깃 이슈 기반으로 작업 시작»)
#   ft-nano-spawn 이 대기/ 카드를 착수할 때 ① lint 뒤 · 부작용 전에 부른다. 새 카드·옛 카드 판별 0 · 면제 0(proposal-*·템플릿 카드도 같다).
#   판독 = 머리(첫 «## » 전) `- Issue:` 줄 값의 «맨 앞 #숫자» 하나(r2 · 그 뒤 같은 줄 글자 무시 · 본문 다른 곳 `#숫자` 무시)
#          · 맨 앞이 #숫자가 아니면(`[#7](링크)`·주소·`owner/repo#N`·`GH-7`·`#7a`·`없음 …`) = 꼴 오류 REJECT · gh 호출 0.
#          · r3: 번호 = 0 으로 시작하지 않는 1~7자리 10진(`#012`·`#12345678` = 꼴 오류) · gh 응답 number 는 JSON 정수로만 정수 비교(글자 비교 0).
#   조회 = gh issue view 1회(`timeout -s KILL 7` · 상수) · 재시도 = 첫 시도 «출력 0»(stdout·stderr 둘 다 빈 것)일 때만 1회 · 출력이 조금이라도 있으면 재시도 0.
#          · 게이트 전체 마감 = 상수 15 s — 넘으면 판정 불가 REJECT. 시간 값은 바깥(env·인자)에서 바꾸지 못한다(r3).
#   출력 `OK #N 열린 이슈` rc0 · `REJECT <사유>` rc1(판정 불가도 통과 0 · #0 RULE) · usage rc2.
# 시험용 env: FT_GH_READ(가짜 gh · ft-proposal-gate.sh 와 같은 이름) · GH_REPO
# r984: 카드 «계약↔시험 대표」 게이트는 이 게이트 «전» 단계(ft-index-lint.sh ⑫ · ft_card_map_lint.py) 소관 — 여기 새 분기는 0(대응표 없는 새 카드는 lint 가 먼저 REJECT).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
[ $# -eq 1 ] && [ -f "$1" ] || { echo "usage: $0 <카드.md>" >&2; exit 2; }
CARD="$1"; REPO="${GH_REPO:-SecondWindStudio/byz-agents}"
LIM=7
DEADLINE=15
MAKE="만들기: bash $HERE/ft-issue-create-pair.sh <제목> <본문파일> --apply → 카드 머리 「- Issue: #N」"
TO="$(command -v timeout || command -v gtimeout)" || { echo "REJECT 판정 불가(통과 0) — timeout(coreutils) 없음 · 7초 룰"; exit 1; }

val="$(awk '/^##[[:space:]]/{exit} {print}' "$CARD" | sed -nE 's/^[[:space:]]*[-*][[:space:]]*Issue:[[:space:]]*(.*)$/\1/p' | head -1)"
[ -n "$(awk '/^##[[:space:]]/{exit} {print}' "$CARD" | grep -E '^[[:space:]]*[-*][[:space:]]*Issue:')" ] \
  || { echo "REJECT 착수 = 열린 깃 이슈 번호 필수 — 카드 머리에 「- Issue:」 줄 없음 · $MAKE"; exit 1; }
RE='^#([1-9][0-9]{0,6})([[:space:]]|$)'   # r2: 값 맨 앞이 «#숫자» 그 자체 · r3: 0 시작·8자리 이상 = 꼴 오류
[[ "$val" =~ $RE ]] || { echo "REJECT 착수 = 열린 깃 이슈 번호 필수 — Issue 줄 꼴 오류 — 머리 «- Issue: #N» (맨 앞 #숫자 · 링크·주소·owner/repo#N 0) · 지금: ${val:0:60} · $MAKE"; exit 1; }
N="${BASH_REMATCH[1]}"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
T0=$SECONDS
for TRY in 1 2; do
  # shellcheck disable=SC2086
  "$TO" -s KILL "$LIM" ${FT_GH_READ:-gh} issue view "$N" --repo "$REPO" --json number,state,url >"$T/o" 2>"$T/e"; RC=$?
  { [ -s "$T/o" ] || [ -s "$T/e" ]; } && break     # 출력이 조금이라도 있으면 재시도 0 (rc 무관)
done
OUT="$(cat "$T/o")"; ERR="$(cat "$T/e")"
EL=$((SECONDS - T0))
[ "$EL" -le "$DEADLINE" ] || { echo "REJECT 판정 불가(통과 0) — gh issue view #$N 전체 마감 ${DEADLINE}초 넘음(${EL}초 · 시도 ${TRY}회)"; exit 1; }
if [ "$RC" != 0 ]; then
  case "$OUT$ERR" in *"Could not resolve to an issue"*|*"Could not resolve to an Issue"*) echo "REJECT 없는 이슈 #$N ($REPO) — $MAKE"; exit 1;; esac
  [ -n "$OUT$ERR" ] && why="rc=$RC: $(printf '%s' "$ERR$OUT" | tr '\n' ' ' | cut -c1-120)" || why="rc=$RC 출력 0(시간 초과 ${LIM}초 또는 응답 없음 · 시도 ${TRY}회)"
  echo "REJECT 판정 불가(통과 0) — gh issue view #$N $why"; exit 1
fi
st="$(printf '%s' "$OUT" | python3 -c '
import json, sys
try:
    v = json.load(sys.stdin)
except ValueError:
    print("BAD JSON 아님"); sys.exit()
num = v.get("number") if isinstance(v, dict) else None
ok = type(num) is int and num == int(sys.argv[1])
if not ok:
    print("BAD 번호 불일치(JSON 정수 아님 또는 다른 번호)"); sys.exit()
if "/issues/" not in str(v.get("url") or ""):
    print("BAD 이슈 아님(PR 이거나 url 없음)"); sys.exit()
print(str(v.get("state") or ""))' "$N")"
case "$st" in
  OPEN) echo "OK #$N 열린 이슈 ($REPO)";;
  CLOSED) echo "REJECT 닫힌 이슈 #$N — 착수는 열린 이슈만 · 다시 열거나(ft-issue-reopen.sh) 새 이슈 · $MAKE"; exit 1;;
  BAD*) echo "REJECT 판정 불가(통과 0) — gh 응답 ${st#BAD }"; exit 1;;
  *) echo "REJECT 판정 불가(통과 0) — 이슈 #$N 상태 «${st}»"; exit 1;;
esac
