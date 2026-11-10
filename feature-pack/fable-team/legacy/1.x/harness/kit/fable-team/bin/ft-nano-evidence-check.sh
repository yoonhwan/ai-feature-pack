#!/usr/bin/env bash
# ft-nano-evidence-check.sh <카드> --repo <나노 워크트리>
#   나노 생애 ③④ 증거 줄 검사 (M7 범위 1 · REVIEW arch141 §2-2 · single_set_testing §3): 카드 «## 상태» 에 정확히 이 1줄 —
#     세트: <나노 HEAD 40-hex> · 시험: <명령> rc=<n> · 이슈: 0 | <카드 경로>
#   문서 전용 카드(시험할 코드 0) 형식: 세트: <나노 HEAD 40-hex> · 시험: 없음(문서) — <이유 1줄> · 이슈: 0 | <카드 경로>   (rc= 없음)
#     통과 조건 추가 = merge-base(feat, HEAD)..HEAD 가 건드린 경로가 전부 design/ · docs/ · *.md (코드 1개라도 있으면 REJECT — 코드 카드가 «문서» 로 우회 못 한다).
#   RED(가름) 형식 — 산출이 빨강 시험인 나노(single_set_testing §3): 세트: <40-hex> · 시험: <명령> rc=<n> RED · 이슈: 0 | <카드 경로>
#     통과 = ①카드 `- 의도 결과: RED rc=<n> — …` 가 카드가 원장 git 에 «처음 들어간 판»에 있다(나노가 뒤에 넣은 줄 무효) ②n≠0 ∧ 선언 rc 와 같다 ③변경 경로가 전부 tests/ · design/ · docs/ · *.md. 하나라도 빠지면 REJECT(override 0).
#     feat = --feat <브랜치> 또는 FT_NANO_FEAT(기본 feat/v6-realtime-live). ref 가 없으면 REJECT(값 추론 금지).
#   통과 = 줄 존재 ∧ 세트 HEAD == 현재 나노 HEAD(git rev-parse HEAD) ∧ rc=0 ∧ 이슈 칸이 `0` 또는 실재 경로. 값 추론 금지 — 줄이 없으면 REJECT.
#   ★r1071★ 세트 HEAD ≠ 현재 HEAD 여도 그 차이가 main 병합뿐이고 자기 변경이 같으면(ft-approval-equiv EQUIV) 통과 — 출력에 «세트 <9> + main 병합뿐(EQUIV merges=N) → HEAD <9>». 일반 커밋·손댄 병합·판정기 없음 = 지금대로 REJECT. 이때 경로 검사(문서·RED)의 tip 은 세트 sha 로 둔다(병합으로 들어온 남의 코드를 «내 변경» 으로 세지 않음).
#   --ancestor-of <ref> (공유 워크트리 좌석 · ft-nano-close --shared-wt): «세트 HEAD == 현재 HEAD» 대신 «세트 sha 가 <ref>(--repo 기준) 의 조상» — 공유 HEAD 는 다른 세션이 계속 옮긴다. 문서 전용·RED 경로 검사도 현재 HEAD 가 아니라 그 세트 sha 까지의 변경만 본다. 인자 없으면 지금 동작.
#   루트(feat HEAD) 포함 검사는 여기 없다 — ft-nano-cherry-gate.sh --mode land 가 맡는다. ft-nano-close.sh 가 호출한다.
#   exit 0 = 통과 · 1 = REJECT(사유 stdout) · 2 = usage
set -uo pipefail
CARD="${1:-}"; shift 2>/dev/null || { echo "usage: $0 <카드> --repo <나노 워크트리> [--feat <브랜치>] [--ancestor-of <ref>]" >&2; exit 2; }
REPO=""; FEAT="${FT_NANO_FEAT:-feat/v6-realtime-live}"; ANC=""
while [ $# -gt 0 ]; do case "$1" in --repo) REPO="${2:-}"; shift 2 2>/dev/null || shift ;; --feat) FEAT="${2:-}"; shift 2 2>/dev/null || shift ;; --ancestor-of) ANC="${2:-}"; shift 2 2>/dev/null || shift ;; *) echo "usage: $0 <카드> --repo <나노 워크트리> [--feat <브랜치>] [--ancestor-of <ref>]" >&2; exit 2 ;; esac; done
[ -n "$CARD" ] && [ -n "$REPO" ] || { echo "usage: $0 <카드> --repo <나노 워크트리>" >&2; exit 2; }
[ -f "$CARD" ] || { echo "REJECT 증거 줄 — 카드 없음: $CARD"; exit 1; }
FORMAT='세트: <나노 HEAD 40-hex> · 시험: <명령> rc=<n> · 이슈: 0 | <카드 경로>  (문서 전용: 시험: 없음(문서) — <이유> · RED 가름: rc=<n> RED)'
head_now="$(git -C "$REPO" rev-parse HEAD 2>/dev/null)" || { echo "REJECT 증거 줄 — 나노 HEAD 조회 실패: $REPO"; exit 1; }
line="$(grep -E '세트:' "$CARD" | tail -1)"
[ -n "$line" ] || { echo "REJECT 증거 줄 — 카드 «## 상태» 에 증거 줄 없음. 형식: $FORMAT ($CARD)"; exit 1; }
re_code='세트:[[:space:]]*([0-9a-f]{40})[[:space:]]*·[[:space:]]*시험:[[:space:]]*(.+)[[:space:]]+rc=([0-9]+)[[:space:]]*·[[:space:]]*이슈:[[:space:]]*([^[:space:]].*[^[:space:]]|[^[:space:]])[[:space:]]*$'
re_doc='세트:[[:space:]]*([0-9a-f]{40})[[:space:]]*·[[:space:]]*시험:[[:space:]]*없음\(문서\)[[:space:]]*—[[:space:]]*([^·]*[^·[:space:]])[[:space:]]*·[[:space:]]*이슈:[[:space:]]*([^[:space:]].*[^[:space:]]|[^[:space:]])[[:space:]]*$'
re_red='세트:[[:space:]]*([0-9a-f]{40})[[:space:]]*·[[:space:]]*시험:[[:space:]]*(.+)[[:space:]]+rc=([0-9]+)[[:space:]]+RED[[:space:]]*·[[:space:]]*이슈:[[:space:]]*([^[:space:]].*[^[:space:]]|[^[:space:]])[[:space:]]*$'
DOC=0; RED=0
if [[ "$line" =~ $re_doc ]]; then DOC=1; set_head="${BASH_REMATCH[1]}"; rc=0; issue="${BASH_REMATCH[3]}"
elif [[ "$line" =~ $re_red ]]; then RED=1; set_head="${BASH_REMATCH[1]}"; rc="${BASH_REMATCH[3]}"; issue="${BASH_REMATCH[4]}"
elif [[ "$line" =~ $re_code ]]; then set_head="${BASH_REMATCH[1]}"; rc="${BASH_REMATCH[3]}"; issue="${BASH_REMATCH[4]}"
else echo "REJECT 증거 줄 — 형식 불일치(40-hex HEAD·rc·이슈 칸 필요 · 문서 전용은 «시험: 없음(문서) — 이유»). 형식: $FORMAT · 받은 줄: ${line:0:160}"; exit 1; fi
if [ -n "$ANC" ]; then
  git -C "$REPO" merge-base --is-ancestor "$set_head" "$ANC" 2>/dev/null \
    || { echo "REJECT 증거 줄 — 세트 ${set_head:0:9} 가 $ANC(${head_now:0:9}) 의 조상이 아니다(없는 커밋이거나 다른 가지 — 시험한 커밋이 이 워크트리에 들어와 있어야 한다)"; exit 1; }
elif [ "$set_head" != "$head_now" ]; then   # 세트 뒤가 main 병합뿐 + 자기 변경 같으면(ft-approval-equiv EQUIV) 통과 · 일반 커밋·손댄 병합은 REJECT · 판정기 없음 = REJECT
  EQ="$(dirname -- "${BASH_SOURCE[0]:-$0}")/ft-approval-equiv.sh"
  [ -f "$EQ" ] || { echo "REJECT 증거 줄 — 세트 HEAD ${set_head:0:9} != 현재 나노 HEAD ${head_now:0:9} · 동일성 판정기 없음: $EQ"; exit 1; }
  EQUIV="$(bash "$EQ" "$set_head" "$head_now" --repo "$REPO" 2>&1)" || { echo "REJECT 증거 줄 — 세트 HEAD ${set_head:0:9} != 현재 나노 HEAD ${head_now:0:9} (시험 뒤 커밋이 생김 — 다시 시험하고 줄을 갱신) · 판정기: $(printf '%s' "$EQUIV" | head -1)"; exit 1; }
  MERGED=1
fi
tip="$set_head"
scope() {  # scope <허용 경로 정규식> — merge-base(feat, $tip)..$tip 변경 경로 중 허용 밖 → $code (feat 없음·git 실패는 그 자리에서 REJECT)
  git -C "$REPO" rev-parse --verify -q "refs/heads/$FEAT" >/dev/null || git -C "$REPO" rev-parse --verify -q "refs/remotes/$FEAT" >/dev/null \
    || { echo "REJECT 증거 줄 — 문서 전용 검증용 feat 브랜치 없음: $FEAT (refs/heads/ · refs/remotes/ · --feat)"; exit 1; }
  mb="$(git -C "$REPO" merge-base "$FEAT" "$tip" 2>/dev/null)" || { echo "REJECT 증거 줄 — merge-base($FEAT, $tip) 실패"; exit 1; }
  paths="$(git -C "$REPO" -c core.quotepath=off diff --name-only "$mb" "$tip")" || { echo "REJECT 증거 줄 — git diff 실패(경로 검증)"; exit 1; }
  code="$(printf '%s\n' "$paths" | grep -vE "$1" | grep . || true)"
}
decl() { sed -nE 's/^- 의도 결과: RED rc=([0-9]+).*/\1/p' | head -1; }
red_gate() {  # RED 가름 — 선언(처음 들어간 판) ∧ 선언 rc 일치 ∧ 시험 경로만, 셋 다일 때만 통과 (못 읽으면 REJECT · 값 추론 0)
  [ $((10#$rc)) -ne 0 ] || { echo "REJECT 증거 줄 — RED 인데 rc=0 — 빨강이 아니다(초록이면 rc=0 형식으로 쓴다)"; exit 1; }
  local cdir bn c1 d1 dn; cdir="$(dirname "$CARD")"; bn="$(basename "$CARD")"
  c1="$(git -C "$cdir" log --diff-filter=A -1 --format=%H -- "$bn" 2>/dev/null)"
  [ -n "$c1" ] || { echo "REJECT 증거 줄 — RED 선언을 읽지 못함(카드가 원장 git 에 커밋돼 있지 않다): $CARD"; exit 1; }
  dn="$(decl < "$CARD")"
  d1="$(git -C "$cdir" show "$c1:./$bn" 2>/dev/null | decl)"   # RED-①
  [ -n "$d1$dn" ] || { echo "REJECT 증거 줄 — 시험 rc=$rc (0 아님)"; exit 1; }
  [ -n "$d1" ] || { echo "REJECT 증거 줄 — RED 선언이 spawn 뒤 추가됨(카드 첫 판에 «- 의도 결과: RED rc=<n> — …» 가 있어야 한다)"; exit 1; }
  [ $((10#$d1)) -eq $((10#$rc)) ] || { echo "REJECT 증거 줄 — 선언 rc=$d1 ≠ 증거 rc=$rc"; exit 1; }
  scope '^(tests/|design/|docs/)|\.md$'
  [ -z "$code" ] || { echo "REJECT 증거 줄 — RED 가름인데 코드 변경 있음(예 $(printf '%s' "$code" | head -1)) — 수정은 다음 나노"; exit 1; }   # RED-③
}
if [ "$RED" = 1 ]; then red_gate; else [ "$rc" = "0" ] || { echo "REJECT 증거 줄 — 시험 rc=$rc (0 아님)"; exit 1; }; fi
if [ "$DOC" = 1 ]; then
  scope '^(design/|docs/)|\.md$'
  [ -z "$code" ] || { echo "REJECT 증거 줄 — «시험: 없음(문서)» 인데 코드 경로 변경이 있음(예 $(printf '%s' "$code" | head -1)) — 시험하고 rc= 형식으로 쓴다"; exit 1; }
fi
if [ "$issue" != "0" ]; then
  [ -f "$issue" ] || [ -f "$REPO/$issue" ] || { echo "REJECT 증거 줄 — 이슈 칸이 0 도 실재 카드 경로도 아님: $issue"; exit 1; }
fi
how="시험 rc=0"; [ "$DOC" = 1 ] && how="시험 없음(문서)"; [ "$RED" = 1 ] && how="시험 RED rc=$rc(선언 일치 · 시험 경로만)"
M=""; [ "${MERGED:-0}" = 1 ] && M=" — 증거 EQUIV: 세트 ${set_head:0:9} + main 병합뿐($(printf '%s' "$EQUIV" | sed -nE 's/.*(merges=[0-9]+).*/\1/p' | head -1)) → HEAD ${head_now:0:9}"
echo "OK 증거 줄 — 세트 HEAD ${head_now:0:9}${M} · $how · 이슈 $issue"
exit 0
