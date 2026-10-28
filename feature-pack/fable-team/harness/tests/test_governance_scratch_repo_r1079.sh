#!/usr/bin/env bash
# test_governance_scratch_repo_r1079.sh — r1079: main-team-governance.md §16 «검토·격리 사본 = ft-scratch-repo» 문장 시험.
#   계약↔시험: ① 절 머리 ⓐ · ② 금지 문장 ⓑ · ③ 만들기·닫기 명령 ⓒ(각 1).
#   문서 grep 만 · 실 좌석·tmux·우편함·git 사본 0 · 자기 재호출 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
DOC="${FT_R1079_DOC:-$HERE/../../../fable-team/skill/references/main-team-governance.md}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

[ -f "$DOC" ] && ok "문서 실재: $DOC" || { bad "문서 없음: $DOC"; echo "FAILED 1"; exit 1; }

# ── ⓐ R1 절 머리 ──
[ "$(grep -cF '## 16. 검토·격리 사본 = ft-scratch-repo' "$DOC")" = 1 ] \
  && ok "ⓐ §16 절 머리 1줄" || bad "ⓐ §16 절 머리 $(grep -cF '## 16. 검토·격리 사본 = ft-scratch-repo' "$DOC")줄"

# ── ⓑ R2 금지 문장 ──
[ "$(grep -cF '세션 scratchpad 안에 git 사본을 만들지 않는다' "$DOC")" = 1 ] \
  && ok "ⓑ 금지 문장 1줄" || bad "ⓑ 금지 문장 $(grep -cF '세션 scratchpad 안에 git 사본을 만들지 않는다' "$DOC")줄"

# ── ⓒ R3 만들기·닫기 명령 ──
for p in 'ft-scratch-repo.sh <sha> [--repo <저장소>]' 'ft-scratch-repo.sh --done <경로>'; do
  n="$(grep -cF "$p" "$DOC")"
  [ "$n" = 1 ] && ok "ⓒ «${p}» 1줄" || bad "ⓒ «${p}» ${n}줄"
done

# ── 범위 밖 절 문구 불변: 기존 절 머리 14개 그대로 + §16 이 마지막 절 ──
[ "$(grep -c '^## ' "$DOC")" = 15 ] && ok "절 머리 총 15개(기존 14 + §16)" || bad "절 머리 $(grep -c '^## ' "$DOC")개"
LAST="$(grep '^## ' "$DOC" | tail -1)"
case "$LAST" in
  '## 16. 검토·격리 사본 = ft-scratch-repo '*) ok "§16 이 마지막 절" ;;
  *) bad "마지막 절 = $LAST" ;;
esac

# ── 명령이 실제로 있는 도구인가(사용법 머리와 글자 대조) ──
TOOL="${FT_R1079_TOOL:-$HERE/../bin/ft-scratch-repo.sh}"
if [ -f "$TOOL" ]; then
  for p in 'ft-scratch-repo.sh <sha|ref> [--repo <저장소>]' 'ft-scratch-repo.sh --done <경로>'; do
    grep -qF "$p" "$TOOL" && ok "도구 사용법에 «${p}» 실재" || bad "도구 사용법에 «${p}» 없음"
  done
else
  bad "도구 없음: $TOOL"
fi

# ── 변이: §16 절을 지운 사본으로 이 시험을 다시 돌린다(재귀 0 — 문서 사본만 만든다) ──
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
if [ -z "${FT_R1079_DOC:-}" ]; then
  awk '/^## 16\. 검토·격리 사본/ { exit } { print }' "$DOC" > "$T/doc-no16.md"
  [ "$(grep -cF '## 16. 검토·격리 사본' "$T/doc-no16.md")" = 0 ] || { bad "변이 문서 만들기 실패"; }
  [ -z "${FT_R1079_DOC:-}" ] || exit 0   # 재진입 표지(자식은 변이 칸을 다시 돌지 않는다 · r1041)
  [ "$(FT_R1079_DOC="$T/doc-no16.md" bash "$0" 2>&1 | grep -c '^FAIL')" -ge 1 ] \
    && ok "변이: §16 삭제 → FAIL" || bad "변이: §16 을 지워도 통과"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
