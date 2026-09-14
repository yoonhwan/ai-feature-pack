#!/usr/bin/env bash
# ★런타임 사본은 git 추적 밖이다 — 실전은 <워크트리>/.fable-team/bin/ 의 사본으로 돌린다. 이 파일이 팩 SSOT(Seatbelt 1.0.0).★
# ft-index-lint.sh <indices/…/X.md> [more…] — Seatbelt 0.3 · 인덱스 파일이 «누가 읽어도 착수 가능»한지 검사.
#   exit 0 = OK · 1 = REJECT(사유 stdout) · 2 = usage
# 검사 (SEATBELT-README §5): ①골 3줄 바이트 일치 ②필수 6절 ③골좌표의 닫는 증거가 GOAL-LEDGER 에 실재(20자+ 복붙)
#   ④배경 절 정본 인용 ≤4 ⑤구현 범위·완료 조건 절이 비어 있지 않음.
# ★판정기가 아니다★ — 내용의 옳고 그름은 보지 않는다. «형식이 갖춰졌나»만 답한다(#0 RULE: 조용한 통과 없음).
set -uo pipefail
[ $# -ge 1 ] || { echo "usage: $0 <index.md> [more…]" >&2; exit 2; }
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
DEFAULT_LEDGER="$ROOT/${FT_GOAL_LEDGER:-design/v65/GOAL-LEDGER-v65.md}"
# 하네스 자체 작업(Seatbelt 단위)은 제품 골 원장에 행이 없다. 파일 머리에 `<!-- ledger: <경로> -->` 를 «선언»하면
# 그 문서를 닫는 증거의 정본으로 쓴다 — 예외 목록이 아니라 파일이 스스로 밝히고, 결과 줄에 어느 정본을 봤는지 찍는다.
ledger_for() { local d; d="$(grep -oE '<!-- *ledger: *[^ >]+ *-->' "$1" | head -1 | sed -E 's/<!-- *ledger: *([^ >]+) *-->/\1/')"; [ -n "$d" ] && printf '%s' "$ROOT/$d" || printf '%s' "$DEFAULT_LEDGER"; }
# 골 3줄 — FT_GOAL_LINES_FILE(3행 텍스트)이 있으면 그 파일, 비어 있으면 v65 3줄(예시).
if [ -n "${FT_GOAL_LINES_FILE:-}" ] && [ -f "$FT_GOAL_LINES_FILE" ]; then
  GOAL1="$(sed -n 1p "$FT_GOAL_LINES_FILE")"; GOAL2="$(sed -n 2p "$FT_GOAL_LINES_FILE")"; GOAL3="$(sed -n 3p "$FT_GOAL_LINES_FILE")"
else
  GOAL1='목표는 빠른 유용 원문, 실시간 교정, N언어의 병렬·독립 발행, 소실·비의도 중복 없는 최종 말풍선이다.'
  GOAL2='LST ON 우선이며 LST OFF/전환과 기존 M0–M7·통합 조건도 남긴다.'
  GOAL3='단순히 실패 사례를 많이 모았다는 이유로 실험을 닫지 않는다.'
fi
SECTIONS=('골 원문' '골좌표' '배경' '구현 범위' '완료 조건' '상태')
MAX_CITES="${FT_INDEX_MAX_CITES:-4}"
rc=0
section_body() {  # $1=file $2=heading-prefix → 그 절 본문(다음 ## 전까지)
  awk -v h="## $2" 'index($0,h)==1{f=1;next} /^## /{f=0} f' "$1"
}
# ★정규화★ — 정본(GOAL-LEDGER)은 강조 `**…**` 가 섞여 있고, 인덱스 파일은 「…」 안에서 줄을 바꾼다.
#   바이트 그대로 대조하면 «복붙인데 불일치»가 난다(실측 2026-09-14: M5 「…20초 초과…」 hit 0 —
#   정본이 `**20초 초과**`). 줄바꿈→공백, `**` 제거, 연속 공백 1개. 그 뒤 F 매칭.
norm() { tr '\n' ' ' | sed -e 's/\*\*//g' -e 's/  */ /g'; }
for f in "$@"; do
  bad=()
  [ -f "$f" ] || { echo "REJECT $f — 파일 없음"; rc=1; continue; }
  LEDGER="$(ledger_for "$f")"
  [ -f "$LEDGER" ] || { echo "REJECT $f — 선언된 정본 없음: $LEDGER"; rc=1; continue; }
  LEDGER_N="$(norm < "$LEDGER")"
  grep -qxF -- "$GOAL1" "$f" || bad+=("골 1줄 불일치")
  grep -qxF -- "$GOAL2" "$f" || bad+=("골 2줄 불일치")
  grep -qxF -- "$GOAL3" "$f" || bad+=("골 3줄 불일치")
  for s in "${SECTIONS[@]}"; do grep -qE "^## $s" "$f" || bad+=("절 없음: $s"); done
  # ③ 닫는 증거: 「…」 안 문구 중 하나라도 GOAL-LEDGER 에 실재해야 한다.
  coords="$(section_body "$f" '골좌표' | norm)"
  hit=0
  while IFS= read -r q; do
    q="$(printf '%s' "$q" | sed 's/^ *//;s/ *$//')"
    [ "${#q}" -ge 20 ] || continue
    case "$LEDGER_N" in *"$q"*) hit=1; break;; esac
  done < <(printf '%s\n' "$coords" | grep -oE '「[^」]+」' | sed 's/^「//;s/」$//')
  [ "$hit" = 1 ] || bad+=("골좌표: 20자+ 닫는 증거 「…」 가 GOAL-LEDGER 에 없다(복붙이 아니다)")
  # ④ 배경 인용 수 — «정본 문서» 수만 센다(.md 경로). 백틱 코드 식별자는 읽을 문서가 아니다.
  n="$(section_body "$f" '배경' | grep -oE '[A-Za-z0-9_./\-]+\.md' | sort -u | wc -l | tr -d ' ')"
  [ "$n" -le "$MAX_CITES" ] || bad+=("배경 인용 문서 ${n}개 > ${MAX_CITES} — 이 좌석이 못 읽는다")
  # ⑤ 비어 있지 않은가
  for s in '구현 범위' '완료 조건'; do
    [ -n "$(section_body "$f" "$s" | grep -v '^\s*$')" ] || bad+=("절 비어 있음: $s")
  done
  # ⑥ 구현 범위의 파일 경로 중 «하나 이상 실재» (pm#3 #13080 — 경로가 틀리면 나노가 그 자리에서 막힌다).
  #   후보 = 백틱 안 경로(확장자 있는 것) + 맨 경로. 인덱스가 있는 워크트리 루트 기준으로 존재 확인.
  paths="$(section_body "$f" '구현 범위' | grep -oE '[A-Za-z0-9_./-]+/[A-Za-z0-9_.-]+\.[a-z]{1,5}' | sort -u)"
  if [ -n "$paths" ]; then
    ok=0; while IFS= read -r p; do [ -e "$ROOT/$p" ] || [ -e "$p" ] && { ok=1; break; }; done <<< "$paths"
    [ "$ok" = 1 ] || bad+=("구현 범위: 인용한 파일 경로가 하나도 실재하지 않는다 ($(printf '%s' "$paths" | head -3 | tr '\n' ' '))")
  fi
  if [ "${#bad[@]}" -eq 0 ]; then echo "OK $f (ledger=${LEDGER#$ROOT/})"; else printf 'REJECT %s (ledger=%s)\n' "$f" "${LEDGER#$ROOT/}"; printf '  - %s\n' "${bad[@]}"; rc=1; fi
done
exit $rc
