#!/usr/bin/env bash
# test_proposal_approve_inbox.sh — ft-proposal-approve.sh · ft-proposal-inbox.sh 시험(R77 r1 · 판정 826). 가짜 Tank·가짜 gh·가짜 planner 원장만 — 실 gh 0.
set -uo pipefail
# shellcheck source=_proposal_issue_env.sh
. "$(dirname "${BASH_SOURCE[0]:-$0}")/_proposal_issue_env.sh"
APP="$PROP/ft-proposal-approve.sh"; INB="$PROP/ft-proposal-inbox.sh"
bash -n "$APP" && ok "bash -n approve" || bad "bash -n approve"
bash -n "$INB" && ok "bash -n inbox" || bad "bash -n inbox"

printf '질문: 승인할까요?\n오빠 답: A안 승인\n추가 의견: 모바일도 확인\n' > "$T/interview.txt"
ledger() { printf '%s\n' "$@" > "$T/planner/VERDICTS-planner-1.md"; }
ledger "816 오빠 인터뷰(A안 · Issue https://github.com/test/repo/issues/12): 채택"
app() { out="$(bash "$APP" 12 --verdict 816 --interview "$T/interview.txt" "$@" 2>&1)"; rc=$?; }
setup() { reset; fx 12 "$@"; }   # 변형: 라벨·타임라인은 픽스처가 정한다

ledger "815 오빠 인터뷰(Issue https://github.com/test/repo/issues/12): 다른 판정"
setup; app --approve --apply
[ "$rc" = 1 ] && [ "$(calls)" = 0 ] && ok "1 원장에 「816 오빠 인터뷰」 줄 없음 → rc 1 · Tank 0" || bad "1 rc=$rc 호출=$(calls) $out"
ledger "816 오빠 인터뷰(Issue https://github.com/test/repo/issues/120): 다른 Issue"
setup; app --approve --apply
[ "$rc" = 1 ] && [ "$(calls)" = 0 ] && ok "2 원장 줄에 issues/12 없음(issues/120 는 다른 번호) → rc 1 · Tank 0" || bad "2 rc=$rc 호출=$(calls) $out"
ledger "816 오빠 인터뷰(Issue https://github.com/other/repo/issues/12): 다른 저장소의 12번"
setup noapproved; app --approve --apply
[ "$rc" = 1 ] && [ "$(calls)" = 0 ] && ok "2b ★H2★ 원장 줄이 다른 저장소(other/repo) issues/12 → rc 1 · Tank 0" || bad "2b rc=$rc 호출=$(calls) $out"
ledger "816 오빠 인터뷰(A안 · Issue https://github.com/test/repo/issues/12): 채택"
setup noapproved needsreply; app --approve --apply
[ "$rc" = 1 ] && [ "$(calls)" = 0 ] && echo "$out" | grep -q 'needs-reply' && ok "3 --approve + needs-reply 라벨 → 거부 · Tank 0" || bad "3 rc=$rc 호출=$(calls) $out"
setup noapproved; app --approve --apply
[ "$rc" = 0 ] && echo "$out" | grep -q '^APPROVED #12 판정 816$' && [ "$(n_of comment)" = 1 ] && [ "$(n_of label)" = 1 ] && grep -q '^label 12 --add approved --apply' "$TANK_LOG" && ok "4 정상 --approve → 코멘트 1 + label(approved) 1 · APPROVED" || bad "4 rc=$rc $out :: $(cat "$TANK_LOG")"
[ "$(head -1 "$T/body-1")" = "[인터뷰 판정 816]" ] && grep -q '오빠 답: A안 승인' "$T/body-1" && grep -q '추가 의견: 모바일도 확인' "$T/body-1" && ok "4b 코멘트 = 「[인터뷰 판정 816]」 + 인터뷰 파일 원문(질문·답·추가 의견)" || bad "4b $(cat "$T/body-1")"
# ★H1(b) 2차★ 이미 approved 인 Issue 재승인 → 라벨 제거 후 재부착(새 승인 시각)
setup; app --approve --clear-needs-reply --apply
[ "$rc" = 0 ] && [ "$(n_of label)" = 3 ] && [ "$(sed -n 2p "$TANK_LOG")" = "label 12 --remove needs-reply --apply" ] && [ "$(sed -n 3p "$TANK_LOG")" = "label 12 --remove approved --apply" ] && [ "$(sed -n 4p "$TANK_LOG")" = "label 12 --add approved --apply" ] && ok "4c 이미 approved → --remove approved 뒤 --add approved(재부착 = 새 승인 시각)" || bad "4c rc=$rc $out :: $(cat "$TANK_LOG")"
setup noapproved needsreply; app --approve --clear-needs-reply --apply
[ "$rc" = 0 ] && [ "$(n_of comment)" = 1 ] && [ "$(n_of label)" = 2 ] && [ "$(sed -n 2p "$TANK_LOG" | cut -c1-40)" = "label 12 --remove needs-reply --apply" ] && ok "5 --approve --clear-needs-reply → 코멘트 → needs-reply 제거 → approved 순서" || bad "5 rc=$rc $out :: $(cat "$TANK_LOG")"
setup noapproved rejected; app --approve --apply
[ "$rc" = 1 ] && [ "$(calls)" = 0 ] && ok "6 rejected 라벨 → 승인 거부 · Tank 0" || bad "6 rc=$rc 호출=$(calls) $out"
setup noapproved; python3 - "$T/view-12.json" <<'PY'
import json, sys
p = sys.argv[1]; v = json.load(open(p)); v["labels"] = []; json.dump(v, open(p, "w"))
PY
app --approve --apply
[ "$rc" = 1 ] && [ "$(calls)" = 0 ] && ok "7 proposal 라벨 없는 Issue → 거부 · Tank 0" || bad "7 rc=$rc 호출=$(calls) $out"
setup noapproved; app --apply
[ "$rc" = 0 ] && echo "$out" | grep -q '^COMMENTED #12 판정 816$' && [ "$(n_of comment)" = 1 ] && [ "$(n_of label)" = 0 ] && ok "8 --approve 없음 → 코멘트만 · label 0 · COMMENTED" || bad "8 rc=$rc $out"
setup noapproved; app --approve
[ "$rc" = 0 ] && echo "$out" | grep -q '^DRY' && ! grep -q -- '--apply' "$TANK_LOG" && ok "9 --apply 없음 → Tank dry-run(--apply 인자 0) · DRY" || bad "9 rc=$rc $out :: $(cat "$TANK_LOG")"

# ── inbox ──
inbox_json() {  # <마지막 코멘트 작성자> [라벨 JSON 목록]
  python3 -c 'import json,sys;print(json.dumps([{"number":12,"labels":[{"name":x} for x in sys.argv[2:]],"comments":[{"author":{"login":"byz-tank"},"body":"[인터뷰 판정 816]","createdAt":"2026-10-10T01:00:00Z"},{"author":{"login":sys.argv[1]},"body":"여기 수정해 주세요\n둘째 줄","createdAt":"2026-10-10T02:00:00Z"}]}],ensure_ascii=False))' "$@" > "$T/list-inbox.json"; }
reset; inbox_json yoonhwan proposal; out="$(bash "$INB" 2>&1)"; rc=$?
[ "$rc" = 0 ] && echo "$out" | grep -q '^#12 · yoonhwan · 2026-10-10T02:00:00Z · 여기 수정해 주세요$' && echo "$out" | grep -q '1건' && [ "$(calls)" = 0 ] && ok "10 마지막 코멘트가 오빠 → 목록 1건 · --apply 없으면 Tank 0" || bad "10 rc=$rc $out"
reset; inbox_json yoonhwan proposal; out="$(bash "$INB" --apply 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$(n_of label)" = 1 ] && grep -q '^label 12 --add needs-reply --apply' "$TANK_LOG" && ok "11 --apply → needs-reply 라벨 1" || bad "11 rc=$rc $out :: $(cat "$TANK_LOG")"
reset; inbox_json byz-tank proposal; out="$(bash "$INB" --apply 2>&1)"; rc=$?
[ "$rc" = 0 ] && echo "$out" | grep -q '0건' && [ "$(calls)" = 0 ] && ok "12 마지막 코멘트가 byz-tank → 목록 0 · Tank 0" || bad "12 rc=$rc $out"
reset; inbox_json yoonhwan proposal needs-reply; out="$(bash "$INB" --apply 2>&1)"; rc=$?
[ "$rc" = 0 ] && echo "$out" | grep -q 'needs-reply 있음' && [ "$(calls)" = 0 ] && ok "13 이미 needs-reply → 목록에 표시 · 라벨 중복 0" || bad "13 rc=$rc $out"
reset; out="$(GH_FAIL=1 bash "$INB" 2>&1)"; rc=$?
[ "$rc" = 1 ] && ok "14 gh 읽기 실패 → rc 1" || bad "14 rc=$rc $out"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
