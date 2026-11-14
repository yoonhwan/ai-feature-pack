#!/usr/bin/env bash
# test_oppa_approve_first_word_tail_r1950.sh — 끝: 첫 조각 첫 토막 ∈ {네,예,승인} ∧ 덧말 ≤3토막 ∧ 덧말 거절·부정 어간 0 ∧ «?» 0 → SLACK-OK (카드 r1950-oppa-approve-first-word-tail)
#   ①② 승인 · ③④⑤⑦⑧ 승인 0 · bin·kit cmp0 · 변이 M1~M5 · ⑥ 기존 시험(r1606·r1696·r1857)은 따로 돌린다(시험 1개 70초)
# 격리: 임시 루트 · 가짜 슬랙 조회(FT_SLACK_REPLIES_CMD) · 실 Slack 0 · 네트워크 0 · 고정 sleep 0 · 안전선 ulimit -u(현재+64) · timeout 70
NPROC=$(ulimit -u 2>/dev/null || echo 3000); ulimit -u $((NPROC + 64)) 2>/dev/null || true
TO=70
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/autonomy_scope_setup.sh"
CHECK="$BIN/ft_oppa_slack_check.py"; P=1793500000.500000; A1=1793500001.000000; OPPA=U0AC2JF0M7D; X="$(sha 71)"
export FT_SLACK_REPLIES_CMD="cat $T/replies.json"
say() { printf '{"ok":true,"messages":[{"ts":"%s","user":"UBOT1","text":"승인 요청 %s"},{"ts":"%s","user":"%s","text":"%s"}]}' "$P" "$X" "$A1" "$OPPA" "$1" > "$T/replies.json"; }
yes_() { local f=$1; shift; local bad=0 w; for w in "$@"; do say "$w"; run timeout $TO python3 "$f" "$P" "$X"; { [ "$rc" = 0 ] && grep -q "^SLACK-OK $X parent=$P reply=$A1$" <<<"$out"; } || { bad=1; echo "  승인 아님: «${w}» rc=$rc ${out:0:100}"; }; done; return $bad; }
no_() { local f=$1; shift; local bad=0 w; for w in "$@"; do say "$w"; run timeout $TO python3 "$f" "$P" "$X"; { [ "$rc" = 2 ] && ! grep -q "^SLACK-OK" <<<"$out"; } || { bad=1; echo "  승인 0 아님: «${w}» rc=$rc ${out:0:100}"; }; done; return $bad; }
any_ok() { local f=$1; shift; local w; for w in "$@"; do say "$w"; run timeout $TO python3 "$f" "$P" "$X"; grep -q '^SLACK-OK' <<<"$out" && return 0; done; return 1; }
S3=('승인 안 함' '네? 왜요' '확정 보류' '아니오 그래도 승인'); S4=('네 말고 다른 걸로' '예 하지만 보류' '승인 못 해요' '네 /보류' '네 넓혀요(보류)'); S5=('넓혀요 네' '확정 넓혀요')
S7=('네 하지 마세요' '예 보류해 주세요' '승인 취소합니다' '네 멈춰주세요'); S8=('네 이걸로 좀 더 넓혀요' '네 넓혀요?')

yes_ "$CHECK" '네 넓혀요'; ck "① «네 넓혀요» → SLACK-OK" $?
yes_ "$CHECK" '예 그렇게 해요' '승인 진행해 주세요' '네 넓혀 주세요'; ck "②⑧ «예 그렇게 해요»·«승인 진행해 주세요»·«네 넓혀 주세요» → SLACK-OK" $?
no_ "$CHECK" "${S3[@]}"; ck "③ «승인 안 함»·«네? 왜요»·«확정 보류»·«아니오 그래도 승인» → 승인 0" $?
no_ "$CHECK" "${S4[@]}"; ck "④ «네 말고 다른 걸로»·«예 하지만 보류»·«승인 못 해요»·«네 /보류»·«네 넓혀요(보류)» → 승인 0" $?
no_ "$CHECK" "${S5[@]}"; ck "⑤ «넓혀요 네»·«확정 넓혀요» → 승인 0" $?
no_ "$CHECK" "${S7[@]}"; ck "⑦ 활용형 거절 넷 → 승인 0" $?
no_ "$CHECK" "${S8[@]}"; ck "⑧ 덧말 4토막·«?» → 승인 0" $?
cmp -s "$CHECK" "$ROOT/harness/kit/fable-team/bin/ft_oppa_slack_check.py"; ck "bin·kit cmp0" $?

mut() {  # mut <이름> <바꿀 글> <바꾼 글> → $MUT · 안 먹으면 FAIL
  MUT="$T/mut-$1.py"; cp "$CHECK" "$MUT"
  python3 - "$MUT" "$2" "$3" <<'PY' || { rc=1; out="변이 미적용: $1"; ck "변이 적용($1)" 1; }
import pathlib, sys
p = pathlib.Path(sys.argv[1]); t = p.read_text(encoding="utf-8")
assert sys.argv[2] in t, sys.argv[2]
p.write_text(t.replace(sys.argv[2], sys.argv[3], 1), encoding="utf-8")
PY
}
mut M1 'not any(s.startswith(TAIL_NO) for w in tail for s in re.split(r"\W+", w))' 'True'; any_ok "$MUT" "${S3[0]}" "${S4[@]}"; ck "M1 부정 어간 검사 삭제 → ③«승인 안 함»·④ 승인됨(= 시험이 잡음)" $?
mut M2 'fc[0] in FIRST_OK' 'any(w in FIRST_OK for w in fc)'; any_ok "$MUT" "${S5[0]}"; ck "M2 첫 토막 → 아무 토막 → ⑤«넓혀요 네» 승인됨(= 시험이 잡음)" $?
mut M3 ' or [t for t, _, fc in said if first_word_tail_ok(fc)]' ''; ! any_ok "$MUT" '네 넓혀요' '예 그렇게 해요'; ck "M3 새 규칙 삭제 → ①② 승인 0(= 시험이 잡음)" $?
mut M4 's.startswith(TAIL_NO)' 's in TAIL_NO'; any_ok "$MUT" "${S7[@]}"; ck "M4 어간 접두 → 정확 일치 → ⑦ 승인됨(= 시험이 잡음)" $?
mut M5 'len(tail) <= 3' 'True'; any_ok "$MUT" "${S8[0]}"; ck "M5 토막 수 상한 삭제 → ⑧«네 이걸로 좀 더 넓혀요» 승인됨(= 시험이 잡음)" $?

echo "단계 합계 ${SECONDS}s"; [ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILURES: $fail"; exit 1; }
