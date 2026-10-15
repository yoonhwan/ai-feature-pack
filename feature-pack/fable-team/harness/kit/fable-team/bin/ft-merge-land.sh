#!/usr/bin/env bash
# ft-merge-land.sh <PR번호> --approve-sha <40hex> [--repo <dir>] [--remote origin] [--target main]   (R230 교정 2 H1 · 오빠 판정 1875 «로컬 착지 강제»)
#   main 병합 = 이 도구뿐(gh pr merge·ft-gh-as-tank.sh pr merge 는 훅이 막는다). 검사한 트리 == 실제로 main 에 놓이는 트리 — 틈은 git 서버의 non-FF 거절이 닫는다.
#   ① 오빠 승인 값(--approve-sha = PR head sha · 없거나 다르면 실행 0) ② PR OPEN·base main·head sha 결속 ③ PR head fetch(pull/N/head) ④ ft-merge-gate(main 포함·줄 계약)
#   ⑤ Q = commit-tree <S^{tree}> -p <M>(squash 1커밋 · 메시지 = PR 제목·본문 + PR #N) ⑥ git push origin Q:refs/heads/main (force 0 · non-FF = 착지 0)
#   ⑦ PR 에 착지 sha 코멘트 + 닫기. 7초 룰: gh·fetch·push 각 7 s + 재시도 1(push 는 «서버 거절 아님» 일 때만) · 총 마감 70 s.
#   자율 ON/tamper/상태 못 읽음 = 승인 파일(autonomy-merge-approved/<sha> + autonomy.log 한 줄)도 필요(autonomy-merge-guard 와 같은 결속).
#   exit 0 = 착지+정리 · 1 = REJECT(착지 0) · 2 = usage·승인 없음 · 3 = 착지 성공 · PR 코멘트/닫기 실패(수동). FT_GH/FT_GH_WRITE = 시험 주입.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/ft-merge-lib.sh"
PR=""; AP=""; REPO=""; REMOTE="origin"; TARGET="main"; T0=$SECONDS
GH_R="${FT_GH:-gh}"; GH_W="${FT_GH_WRITE:-$HERE/ft-gh-as-tank.sh}"
usage() { echo "usage: $0 <PR번호> --approve-sha <40hex> [--repo <dir>] [--remote origin] [--target main]" >&2; exit 2; }
while [ $# -gt 0 ]; do case "$1" in
  --approve-sha) [ $# -ge 2 ] || usage; AP="$2"; shift 2;;
  --repo) [ $# -ge 2 ] || usage; REPO="$2"; shift 2;;
  --remote) [ $# -ge 2 ] || usage; REMOTE="$2"; shift 2;;
  --target) [ $# -ge 2 ] || usage; TARGET="$2"; shift 2;;
  -*) usage;; *) [ -z "$PR" ] || usage; PR="$1"; shift;; esac; done
printf '%s' "$PR" | grep -Eq '^[0-9]+$' || usage
printf '%s' "$AP" | grep -Eq '^[0-9a-f]{40}$' || { echo "REJECT 오빠 병합 승인 값(--approve-sha <PR head 40hex>) 없음 — 실행 0"; exit 2; }
[ -n "$REPO" ] || REPO="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "REJECT repo 를 찾을 수 없음"; exit 1; }
G() { git -C "$REPO" "$@"; }
rej() { echo "REJECT $* (착지 0)"; exit 1; }
ROOT="${FT_ROOT:-$(dirname "$(G rev-parse --path-format=absolute --git-common-dir)")}"; STATE="${FT_AUTONOMY_STATE_DIR:-$ROOT/.fable-team/state}"
deadline() { [ $((SECONDS - T0)) -lt 70 ] || rej "총 마감 70 s 초과"; }

AUT="$HERE/ft-autonomy.sh"; MODE="off"
if [ -f "$AUT" ]; then MODE="$(bash "$AUT" mode 2>/dev/null)"; [ "$MODE" = off ] || MODE="on"; fi   # off 가 아니면(on·tamper·못 읽음) 승인 파일 필요
if [ "$MODE" != off ]; then
  AF="$STATE/autonomy-merge-approved/$AP"
  [ "$(wc -l < "$AF" 2>/dev/null | tr -d ' ')" = 1 ] && grep -q "^approve-merge $AP " "$AF" && grep -qxF "$(head -n1 "$AF")" "$STATE/autonomy.log" 2>/dev/null \
    || { echo "REJECT 자율 상태 on/tamper/불명 — approve-merge $AP 승인 파일·로그 한 줄 없음 — 실행 0"; exit 2; }
fi

JSON="$(fm_t7 "$GH_R" pr view "$PR" --json headRefOid,title,body,state,baseRefName)" || rej "gh pr view $PR 실패(7 s + 재시도 1)"; deadline
pf() { printf '%s' "$JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin).get(sys.argv[1]) or "")' "$1"; }
[ "$(pf state)" = OPEN ] || rej "PR #$PR 가 OPEN 아님($(pf state))"
[ "$(pf baseRefName)" = "$TARGET" ] || rej "PR #$PR base 가 $TARGET 아님($(pf baseRefName))"
HEADSHA="$(pf headRefOid)"; [ "$HEADSHA" = "$AP" ] || rej "PR head($HEADSHA) != 승인 sha($AP) — 승인 뒤 head 가 움직였다"
fm_t7 git -C "$REPO" fetch --quiet "$REMOTE" "pull/$PR/head" || rej "PR head fetch 실패"; deadline
S="$(G rev-parse --verify -q FETCH_HEAD^{commit})" && [ "$S" = "$HEADSHA" ] || rej "fetch 한 head($S) != PR head($HEADSHA)"

GOUT="$(bash "$HERE/ft-merge-gate.sh" "$S" --repo "$REPO" --remote "$REMOTE" --target "$TARGET")" || rej "게이트: ${GOUT#DENY }"; deadline
M="$(G rev-parse --verify -q "refs/remotes/$REMOTE/$TARGET^{commit}")" || rej "main 확인 실패"
MSG="$(printf '%s\n\n%s\n\nPR #%s (head %s)' "$(pf title)" "$(pf body)" "$PR" "$S")"
Q="$(G commit-tree "$S^{tree}" -p "$M" -m "$MSG")" || rej "commit-tree 실패"
[ "$(G rev-parse "$Q^{tree}")" = "$(G rev-parse "$S^{tree}")" ] && G merge-base --is-ancestor "$M" "$Q" || rej "착지 후보 tree != 검사 tree 이거나 main 이 조상 아님"

TB="$(fm_timeout_bin)" || rej "timeout 도구 없음"
for i in 1 2; do
  deadline; POUT="$("$TB" 7 git -C "$REPO" push "$REMOTE" "$Q:refs/heads/$TARGET" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] && break
  printf '%s' "$POUT" | grep -qE 'rejected|non-fast-forward|fetch first|stale info' && rej "서버가 non-FF 로 거절 — 검사 뒤 main 이 움직였다(트리 어긋남 방지 · 다시 최신화): $(printf '%s' "$POUT" | tail -n1)"
  [ "$i" -eq 2 ] && rej "push 실패(rc=$rc): $(printf '%s' "$POUT" | tail -n1)"
done
mkdir -p "$STATE" && printf '%s repo=%s main=%s head=%s method=ft-merge-land tree=%s landed=%s pr=%s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$(basename "$ROOT")" "$M" "$S" "$(G rev-parse "$S^{tree}")" "$Q" "$PR" >> "$STATE/merge-gate.log"
echo "LANDED pr=$PR sha=$Q main_before=$M head=$S tree=$(G rev-parse "$Q^{tree}")"
# R243: 착지 성공 «뒤»에만 기준 헤드를 Q 로 원자 교체(옛 값이 Q 의 조상일 때만 전진) + 뒤처진 팀 알림(실패해도 착지 rc 불변)
BH="$ROOT/.fable-team/state/base-head"; OLD="$(head -n1 "$BH" 2>/dev/null | tr -d '[:space:]')"
if [ -z "$OLD" ] || G merge-base --is-ancestor "$OLD" "$Q" 2>/dev/null; then
  { mkdir -p "$(dirname "$BH")" && printf '%s\n' "$Q" > "$BH.$$" && mv -f "$BH.$$" "$BH"; } || echo "WARN 기준 헤드 갱신 실패($BH) — 손으로 기록"
fi
FT_ROOT="$ROOT" bash "$HERE/ft-head-lag.sh" --event --repo "$REPO" --base "$REMOTE/$TARGET" || echo "WARN ft-head-lag --event 실패(rc=$?) — 착지는 성공"
fm_t7 "$GH_W" pr comment "$PR" --body "착지 sha $Q (ft-merge-land · 검사 트리 == 착지 트리 · 판정 1875)" && fm_t7 "$GH_W" pr close "$PR" \
  || { echo "WARN 착지는 성공 — PR #$PR 코멘트/닫기 실패: 손으로 처리(착지 sha $Q)"; exit 3; }
