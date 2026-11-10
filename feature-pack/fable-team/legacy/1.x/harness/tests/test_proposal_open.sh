#!/usr/bin/env bash
# test_proposal_open.sh — ft-proposal-open.sh 시험(R77 r1 · 판정 826): 필수 칸 빔 → Tank 0 · 정상 → create 1 + label 1 · 같은 ID 원격 있음 → create 0(채택) · 60,000자 초과 → 분할 코멘트.
set -uo pipefail
# shellcheck source=_proposal_issue_env.sh
. "$(dirname "${BASH_SOURCE[0]:-$0}")/_proposal_issue_env.sh"
OPEN="$PROP/ft-proposal-open.sh"
bash -n "$OPEN" && ok "bash -n" || bad "bash -n"

mkdir -p "$T/design/feature"; P="$T/design/feature/PROPOSAL-foo-20261010.md"
mkp() {  # mkp [제안 칸 본문 · 기본 제안 내용.] — 필수 6칸 제안서
  { echo '# 제안서 — 줄바꿈 CSS'; echo '- 상태: 컨펌 대기'; echo
    for k in 결론 "오빠가 결정할 것" 배경 제안 되돌림 근거; do echo "## $k"; if [ "$k" = 제안 ]; then printf '%b\n' "${1-제안 내용.}"; else echo "$k 본문 8b64a2d"; fi; echo; done; } > "$P"; }
run() { out="$(bash "$OPEN" "$P" "$@" 2>&1)"; rc=$?; }
MARK='<!-- byz-proposal-id: feature/foo -->'

reset; mkp ""; run --apply
[ "$rc" = 1 ] && [ "$(calls)" = 0 ] && echo "$out" | grep -q '제안' && ok "1 필수 칸(제안) 비어 있음 → rc 1 · Tank 0" || bad "1 rc=$rc 호출=$(calls) $out"
reset; mkp; run --apply
[ "$rc" = 0 ] && echo "$out" | grep -q '^OPENED #901$' && [ "$(n_of create)" = 1 ] && [ "$(n_of label)" = 1 ] && grep -q '^label 901 --add proposal --apply' "$TANK_LOG" && ok "2 정상 → create 1 + label(proposal) 1 · OPENED #901" || bad "2 rc=$rc $out :: $(cat "$TANK_LOG")"
[ "$(head -1 "$T/body-1")" = "$MARK" ] && grep -q '^## 근거$' "$T/body-1" && grep -q '제안 내용\.' "$T/body-1" && ok "2b 본문 첫 줄 = 숨은 표식 · 제안서 전문 탑재(링크만 0)" || bad "2b 본문 $(head -3 "$T/body-1")"
reset; mkp; printf '[{"number":55,"body":"%s\\n제안서 전문"}]' "$MARK" > "$T/list-find.json"; run --apply
[ "$rc" = 0 ] && echo "$out" | grep -q '^OPENED #55 (채택)$' && [ "$(n_of create)" = 0 ] && [ "$(n_of label)" = 1 ] && ok "3 같은 표식 원격 있음 → create 0 · label 1 · 채택 #55" || bad "3 rc=$rc $out :: $(cat "$TANK_LOG")"
reset; mkp; printf '[{"number":56,"body":"<!-- byz-proposal-id: feature/other -->\\nx"}]' > "$T/list-find.json"; run --apply
[ "$rc" = 0 ] && [ "$(n_of create)" = 1 ] && ok "3b 다른 표식은 채택하지 않는다 → create 1" || bad "3b rc=$rc $out"
reset; mkp "$(python3 -c 'print("제안 줄 " * 12000)')"; run --apply
big="$(wc -m < "$T/body-1" | tr -d ' ')"; chunks="$(ls "$T"/body-* | wc -l | tr -d ' ')"
[ "$rc" = 0 ] && [ "$(n_of create)" = 1 ] && [ "$(n_of comment)" -ge 1 ] && [ "$big" -le 60000 ] && head -1 "$T/body-2" | grep -q '^(이어서 2/' && ok "4 60,000자 초과 → 첫 조각 ≤ 60,000자(문자 수) + 분할 코멘트 $(n_of comment)개 · OPENED" || bad "4 rc=$rc create=$(n_of create) comment=$(n_of comment) first=$big $out"
reset; mkp; run
[ "$rc" = 0 ] && echo "$out" | grep -q '^DRY' && [ "$(n_of create)" = 1 ] && ! grep -q -- '--apply' "$TANK_LOG" && [ "$(n_of label)" = 0 ] && ok "5 --apply 없음 → Tank create dry-run 만 · label 0" || bad "5 rc=$rc $out :: $(cat "$TANK_LOG")"
reset; mkp; printf '[{"number":55,"body":"%s\\nx"}]' "$MARK" > "$T/list-find.json"; fx 55 noapproved; run --apply --revision r1
[ "$rc" = 0 ] && echo "$out" | grep -q '^REVISED #55 r1$' && grep -q '^edit 55 --body-file .* --apply' "$TANK_LOG" && [ "$(n_of comment)" = 1 ] && grep -q 'r1 변경' "$T/body-2" && ok "6 --revision r1 → Tank edit(--body-file) 1 + 'r1 변경' 코멘트 1" || bad "6 rc=$rc $out :: $(cat "$TANK_LOG")"
# ★H1(b)★ 본문을 고친 뒤 기존 approved 는 무효 — 승인 라벨이 있으면 edit → 코멘트 → label --remove approved 순서
reset; mkp; printf '[{"number":55,"body":"%s\\nx"}]' "$MARK" > "$T/list-find.json"; fx 55
[ "$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))["labels"]))' "$T/view-55.json")" = 2 ] || bad "6c 픽스처 라벨(proposal+approved) 아님"
run --apply --revision r1
[ "$rc" = 0 ] && echo "$out" | grep -q '^REVISED #55 r1$' && [ "$(n_of label)" = 1 ] && [ "$(sed -n 1p "$TANK_LOG")" = "label 55 --remove approved --apply" ] && [ "$(sed -n 2p "$TANK_LOG" | cut -c1-7)" = "edit 55" ] && ok "6c 승인된 Issue --revision → label --remove approved 1 «먼저» → edit 1 → 코멘트 1" || bad "6c rc=$rc $out :: $(cat "$TANK_LOG")"
# ★H1(a) 2차★ 본문 변경 뒤 중간(코멘트) 실패여도 승인은 이미 제거 — fail-closed
reset; mkp; printf '[{"number":55,"body":"%s\\nx"}]' "$MARK" > "$T/list-find.json"; fx 55; TANK_FAIL_COMMENT=1 run --apply --revision r1
[ "$rc" = 1 ] && [ "$(sed -n 1p "$TANK_LOG")" = "label 55 --remove approved --apply" ] && [ "$(n_of edit)" = 1 ] && ok "6f edit 성공·코멘트 실패 → rc 1 이지만 approved 는 edit «전에» 이미 제거됨" || bad "6f rc=$rc $out :: $(cat "$TANK_LOG")"
reset; mkp; printf '[{"number":55,"body":"%s\\nx"}]' "$MARK" > "$T/list-find.json"; fx 55; TANK_FAIL_LABEL=1 run --apply --revision r1
[ "$rc" = 1 ] && [ "$(n_of edit)" = 0 ] && ok "6g approved 제거 실패 → edit 0(본문을 고치지 않는다)" || bad "6g rc=$rc $out :: $(cat "$TANK_LOG")"
reset; mkp; printf '[{"number":55,"body":"%s\\nx"}]' "$MARK" > "$T/list-find.json"; fx 55 noapproved; run --apply --revision r1
[ "$rc" = 0 ] && [ "$(n_of label)" = 0 ] && ok "6d approved 없는 Issue --revision → label 호출 0(제거할 승인 없음)" || bad "6d rc=$rc $out :: $(cat "$TANK_LOG")"
reset; mkp; printf '[{"number":55,"body":"%s\\nx"}]' "$MARK" > "$T/list-find.json"; run --apply --revision r1   # view-55.json 없음 = 라벨 조회 실패
[ "$rc" = 1 ] && [ "$(calls)" = 0 ] && ok "6e 승인 라벨 조회 실패 → rc 1 · Tank 0(edit 전에 확인 — 조용한 승인 잔존 0)" || bad "6e rc=$rc 호출=$(calls) $out"
reset; mkp; run --apply --revision r1
[ "$rc" = 1 ] && [ "$(calls)" = 0 ] && ok "6b --revision 인데 열린 Issue 없음 → rc 1 · Tank 0" || bad "6b rc=$rc 호출=$(calls) $out"
reset; mkp; GH_FAIL=1 run --apply
[ "$rc" = 1 ] && [ "$(calls)" = 0 ] && ok "7 원격 조회 실패 → rc 1 · Tank 0(조용한 create 0)" || bad "7 rc=$rc 호출=$(calls) $out"
reset; mkp; TANK_FAIL_CREATE=1 run --apply
[ "$rc" = 1 ] && [ "$(n_of label)" = 0 ] && ok "8 create 실패 → label 0" || bad "8 rc=$rc $out"
cp "$P" "$T/design/feature/notes.md"; out="$(bash "$OPEN" "$T/design/feature/notes.md" --apply 2>&1)"; rc=$?
[ "$rc" = 1 ] && ok "9 파일 이름이 PROPOSAL-<slug>-YYYYMMDD.md 아님 → rc 1" || bad "9 rc=$rc $out"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
