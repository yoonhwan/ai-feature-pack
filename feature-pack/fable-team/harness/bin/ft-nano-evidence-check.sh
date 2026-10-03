#!/usr/bin/env bash
# ft-nano-evidence-check.sh <카드> --repo <나노 워크트리>
#   나노 생애 ③④ 증거 줄 검사 (M7 범위 1 · REVIEW arch141 §2-2 · single_set_testing §3): 카드 «## 상태» 에 정확히 이 1줄 —
#     세트: <나노 HEAD 40-hex> · 시험: <명령> rc=<n> · 이슈: 0 | <카드 경로>
#   문서 전용 카드(시험할 코드 0) 형식: 세트: <나노 HEAD 40-hex> · 시험: 없음(문서) — <이유 1줄> · 이슈: 0 | <카드 경로>   (rc= 없음)
#     통과 조건 추가 = merge-base(feat, HEAD)..HEAD 가 건드린 경로가 전부 design/ · docs/ · *.md (코드 1개라도 있으면 REJECT — 코드 카드가 «문서» 로 우회 못 한다).
#     feat = --feat <브랜치> 또는 FT_NANO_FEAT(기본 feat/v6-realtime-live). ref 가 없으면 REJECT(값 추론 금지).
#   통과 = 줄 존재 ∧ 세트 HEAD == 현재 나노 HEAD(git rev-parse HEAD) ∧ rc=0 ∧ 이슈 칸이 `0` 또는 실재 경로. 값 추론 금지 — 줄이 없으면 REJECT.
#   루트(feat HEAD) 포함 검사는 여기 없다 — ft-nano-cherry-gate.sh --mode land 가 맡는다. ft-nano-close.sh 가 호출한다.
#   exit 0 = 통과 · 1 = REJECT(사유 stdout) · 2 = usage
set -uo pipefail
CARD="${1:-}"; shift 2>/dev/null || { echo "usage: $0 <카드> --repo <나노 워크트리> [--feat <브랜치>]" >&2; exit 2; }
REPO=""; FEAT="${FT_NANO_FEAT:-feat/v6-realtime-live}"
while [ $# -gt 0 ]; do case "$1" in --repo) REPO="${2:-}"; shift 2 2>/dev/null || shift ;; --feat) FEAT="${2:-}"; shift 2 2>/dev/null || shift ;; *) echo "usage: $0 <카드> --repo <나노 워크트리> [--feat <브랜치>]" >&2; exit 2 ;; esac; done
[ -n "$CARD" ] && [ -n "$REPO" ] || { echo "usage: $0 <카드> --repo <나노 워크트리>" >&2; exit 2; }
[ -f "$CARD" ] || { echo "REJECT 증거 줄 — 카드 없음: $CARD"; exit 1; }
FORMAT='세트: <나노 HEAD 40-hex> · 시험: <명령> rc=<n> · 이슈: 0 | <카드 경로>  (문서 전용: 시험: 없음(문서) — <이유>)'
head_now="$(git -C "$REPO" rev-parse HEAD 2>/dev/null)" || { echo "REJECT 증거 줄 — 나노 HEAD 조회 실패: $REPO"; exit 1; }
line="$(grep -E '세트:' "$CARD" | tail -1)"
[ -n "$line" ] || { echo "REJECT 증거 줄 — 카드 «## 상태» 에 증거 줄 없음. 형식: $FORMAT ($CARD)"; exit 1; }
re_code='세트:[[:space:]]*([0-9a-f]{40})[[:space:]]*·[[:space:]]*시험:[[:space:]]*(.+)[[:space:]]+rc=([0-9]+)[[:space:]]*·[[:space:]]*이슈:[[:space:]]*([^[:space:]].*[^[:space:]]|[^[:space:]])[[:space:]]*$'
re_doc='세트:[[:space:]]*([0-9a-f]{40})[[:space:]]*·[[:space:]]*시험:[[:space:]]*없음\(문서\)[[:space:]]*—[[:space:]]*([^·]*[^·[:space:]])[[:space:]]*·[[:space:]]*이슈:[[:space:]]*([^[:space:]].*[^[:space:]]|[^[:space:]])[[:space:]]*$'
DOC=0
if [[ "$line" =~ $re_doc ]]; then DOC=1; set_head="${BASH_REMATCH[1]}"; rc=0; issue="${BASH_REMATCH[3]}"
elif [[ "$line" =~ $re_code ]]; then set_head="${BASH_REMATCH[1]}"; rc="${BASH_REMATCH[3]}"; issue="${BASH_REMATCH[4]}"
else echo "REJECT 증거 줄 — 형식 불일치(40-hex HEAD·rc·이슈 칸 필요 · 문서 전용은 «시험: 없음(문서) — 이유»). 형식: $FORMAT · 받은 줄: ${line:0:160}"; exit 1; fi
[ "$set_head" = "$head_now" ] || { echo "REJECT 증거 줄 — 세트 HEAD ${set_head:0:9} != 현재 나노 HEAD ${head_now:0:9} (시험 뒤 커밋이 생김 — 다시 시험하고 줄을 갱신)"; exit 1; }
[ "$rc" = "0" ] || { echo "REJECT 증거 줄 — 시험 rc=$rc (0 아님)"; exit 1; }
if [ "$DOC" = 1 ]; then
  git -C "$REPO" rev-parse --verify -q "refs/heads/$FEAT" >/dev/null || { echo "REJECT 증거 줄 — 문서 전용 검증용 feat 브랜치 없음: $FEAT (--feat)"; exit 1; }
  mb="$(git -C "$REPO" merge-base "$FEAT" HEAD 2>/dev/null)" || { echo "REJECT 증거 줄 — merge-base($FEAT, HEAD) 실패"; exit 1; }
  paths="$(git -C "$REPO" -c core.quotepath=off diff --name-only "$mb" HEAD)" || { echo "REJECT 증거 줄 — git diff 실패(문서 전용 검증)"; exit 1; }
  code="$(printf '%s\n' "$paths" | grep -vE '^(design/|docs/)|\.md$' | grep . || true)"
  [ -z "$code" ] || { echo "REJECT 증거 줄 — «시험: 없음(문서)» 인데 코드 경로 변경이 있음(예 $(printf '%s' "$code" | head -1)) — 시험하고 rc= 형식으로 쓴다"; exit 1; }
fi
if [ "$issue" != "0" ]; then
  [ -f "$issue" ] || [ -f "$REPO/$issue" ] || { echo "REJECT 증거 줄 — 이슈 칸이 0 도 실재 카드 경로도 아님: $issue"; exit 1; }
fi
echo "OK 증거 줄 — 세트 HEAD ${head_now:0:9} · $([ "$DOC" = 1 ] && echo "시험 없음(문서)" || echo "시험 rc=0") · 이슈 $issue"
exit 0
