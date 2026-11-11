#!/usr/bin/env bash
# test_nano_autoclose_r1701_pack.sh — r1701 ③: 팩에서 일한 나노의 완료 근거(팩 세트 착지·squash·아카이브 카드)를 읽는다.
#   ⓓ 세트 = 팩 origin/main 조상 → «닫기 차례» 1줄 · 변이 M3(팩 커밋 갈래 삭제) → 제외 · M4(팩 존재 검사 항상 참) → ⓔ 의 «세트≠HEAD» 제외 사라짐
#   ⓓ2 실사건 꼴: pane HEAD 미착지 + 팩 «squash 단일 커밋»(끝줄 «PR #930 (head <세트>)») → 닫기 차례 · 변이 M6(judge squash 파서 끔) → 닫기 차례 0
#   ⓓ3 미착지 팩 세트 + DA APPROVE + 팩 원격 가지 有 → «갈래=승인 set=<세트>» 1줄 · ⓓ4 팩 원격 가지 無 → 갈래 0
#   ⓔ 착지 전 세트(팩 커밋으로만 존재) → 제외 · ⓕ 카드가 ref 의 아카이브/2026-11/ 에만 있음 → 세트 줄을 읽는다 · 변이 M5(아카이브 찾기 삭제) → «카드 파일 없음»
#   ⓖ 세트 sha 가 어느 리포에도 없음 → 제외(근거 0) · 픽스처는 _autoclose_r1701_fixture.sh 공용 · 실 닫기 0 · sleep 0
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/_autoclose_r1701_fixture.sh"
# ⓕ 아카이브 카드 · ⓓ 팩 조상 세트(세트 = S, 팩 origin/main = S)
card "$S"; cd_run "$BIN/ft-nano-close-due.sh"
has "$OUT" "닫기 차례 $SEAT" "ⓕ 카드가 아카이브/2026-11/ 에만 있어도 세트 줄을 읽는다"
hasnt "$OUT" "카드 파일 없음" "ⓕ «카드 파일 없음» 0"
has "$OUT" "닫기 차례 $SEAT" "ⓓ 세트 = 팩 origin/main 조상 → 닫기 차례 1줄"
# ⓔ 착지 전(팩 커밋으로만 존재) → 제외
card "$S2"; cd_run "$BIN/ft-nano-close-due.sh"
hasnt "$OUT" "닫기 차례 $SEAT" "ⓔ 착지 전 세트(팩 커밋으로만) → 닫기 차례 0"
# ⓖ 어느 리포에도 없는 세트 → 제외
card 2222222222222222222222222222222222222222; cd_run "$BIN/ft-nano-close-due.sh"
hasnt "$OUT" "닫기 차례 $SEAT" "ⓖ 세트 sha 가 어느 리포에도 없음 → 제외(근거 0)"
has "$OUT" "≠ HEAD" "ⓖ 제외 사유 = «세트 … ≠ HEAD»"
# ⓓ2 진짜 squash — merge --squash + 끝줄 «PR #930 (head <세트>)» 단일 커밋 · 세트는 조상이 아니다
git -C "$PACK" checkout -q -B sq "$S"; git -C "$PACK" merge -q --squash "$S2" >/dev/null 2>&1 || true
git -C "$PACK" commit -q -m "squash $S2" -m "PR #930 (head $S2)"
git -C "$PACK" update-ref refs/remotes/origin/main "$(git -C "$PACK" rev-parse HEAD)"
git -C "$PACK" merge-base --is-ancestor "$S2" origin/main 2>/dev/null && bad "ⓓ2 픽스처: 세트가 origin/main 조상이다(squash 아님)" "세트 $S2" || ok "ⓓ2 픽스처: 세트는 origin/main 의 조상이 아니다"
card "$S2"; cd_run "$BIN/ft-nano-close-due.sh"
has "$OUT" "닫기 차례 $SEAT" "ⓓ2 세트가 팩 squash 착지(끝줄 PR #930) → 닫기 차례(pane HEAD 미착지여도)"
hasnt "$OUT" "세트 $S2" "ⓓ2 «세트 ≠ HEAD» 제외 0"
# ⓓ3/ⓓ4 미착지 팩 세트 — DA APPROVE + 팩 origin 원격 가지 有/無
git -C "$PACK" update-ref refs/remotes/origin/main "$S"   # ⓓ2 squash 되돌림(미착지 상태로)
git -C "$PACK" update-ref refs/remotes/origin/hold "$S2"
printf '## 판정: APPROVE — DA astra\n\n- 승인 sha: %s\n' "$S2" > "$T/verdict.md"
printf '{"seq": 4242, "ts": "t", "to": "byz-harness-master-pi#203", "from": "%s", "body": "산출 보고 r1701"}\n' "$SEAT" > "$ROOT/.fable-team/comm/mailbox.jsonl"
printf '산출 보고 r1701\n' > "$ROOT/.fable-team/comm/bodies/4242.txt"
card_da "$S2"; cd_run "$BIN/ft-nano-close-due.sh"
has "$OUT" "갈래=승인 set=$S2" "ⓓ3 미착지 팩 세트 + DA APPROVE + 팩 원격 가지 → 갈래=승인 1줄"
git -C "$PACK" update-ref -d refs/remotes/origin/hold
card_da "$S2"; cd_run "$BIN/ft-nano-close-due.sh"
hasnt "$OUT" "갈래=승인" "ⓓ4 팩 원격 가지에 없는 세트 → 갈래=승인 0(제외)"
# R1 — 세트가 팩 «backup/*» 에만 있고 origin/* 에 없으면 origin 미보존으로 제외(DA R1)
git -C "$PACK" update-ref refs/remotes/backup/hold "$S2"; git -C "$PACK" update-ref -d refs/remotes/origin/hold 2>/dev/null
card_da "$S2"; cd_run "$BIN/ft-nano-close-due.sh"
hasnt "$OUT" "갈래=승인" "R1 backup/* 에만 세트 포함 → origin 미보존 제외"
mut3 M7; cd_run "$T/m-M7/ft-nano-close-due.sh"
has "$OUT" "갈래=승인" "M7 origin 만 안 보고 모든 remote 를 보면 R1 이 갈래=승인(변이 잡힘)"
# R2 — 팩 git 조회 실패 = 그 좌석 판정 불가(rc3) · 조용한 제외 0(DA R2)
mkdir -p "$T/notrepo"; card "$S"; cd_run "$BIN/ft-nano-close-due.sh" "$T/notrepo"
{ [ "$RC" = 3 ] && case "$OUT" in *"판정 불가"*) true;; *) false;; esac; } && ok "R2 팩 조회 실패 → 판정 불가 rc3" || bad "R2" "rc=$RC out=$OUT"
mut3 M8; cd_run "$T/m-M8/ft-nano-close-due.sh" "$T/notrepo"
{ [ "$RC" = 0 ] && case "$OUT" in *"판정 불가"*) false;; *) true;; esac; } && ok "M8 실패를 False 로 삼키면 R2 가 rc0 제외(변이 잡힘)" || bad "M8" "rc=$RC out=$OUT"
# 변이 M3~M6 — 사본과 «원본» 을 같은 픽스처로 나란히 돌려 반대 결과까지 본다(헛변이 0)
card "$S"; mut3 M3; cd_run "$T/m-M3/ft-nano-close-due.sh"
hasnt "$OUT" "닫기 차례 $SEAT" "M3 팩 커밋 갈래 삭제 → ⓓ 닫기 차례 0(변이 잡힘)"
card "$S"; cd_run "$BIN/ft-nano-close-due.sh"
has "$OUT" "닫기 차례 $SEAT" "M3 원본 대조: 닫기 차례 1줄"
card 2222222222222222222222222222222222222222; mut3 M4; cd_run "$T/m-M4/ft-nano-close-due.sh"
hasnt "$OUT" "≠ HEAD" "M4(X4 꼴) 팩 존재 검사 항상 참 → ⓖ 의 «세트 … ≠ HEAD» 사유가 사라짐(변이 잡힘)"
card 2222222222222222222222222222222222222222; cd_run "$BIN/ft-nano-close-due.sh"
has "$OUT" "≠ HEAD" "M4 원본 대조: ⓖ 에 «세트 … ≠ HEAD» 사유가 있다"
card "$S"; mut3 M5; cd_run "$T/m-M5/ft-nano-close-due.sh"
has "$OUT" "카드 파일 없음" "M5 아카이브 찾기 삭제 → ⓕ «카드 파일 없음»(변이 잡힘)"
card "$S"; cd_run "$BIN/ft-nano-close-due.sh"
hasnt "$OUT" "카드 파일 없음" "M5 원본 대조: «카드 파일 없음» 0(아카이브에서 읽는다)"
# M6 — squash 상태를 «직전에» 다시 걸고 본다(위 ⓓ3·ⓓ4 가 origin/main 을 S 로 되돌렸다)
git -C "$PACK" checkout -q -B sq2 "$S"; git -C "$PACK" merge -q --squash "$S2" >/dev/null 2>&1 || true
git -C "$PACK" commit -q -m "squash $S2" -m "PR #930 (head $S2)"
git -C "$PACK" update-ref refs/remotes/origin/main "$(git -C "$PACK" rev-parse HEAD)"
git -C "$PACK" merge-base --is-ancestor "$S2" origin/main 2>/dev/null && bad "M6 픽스처: 세트가 조상이다(squash 아님)" "" || ok "M6 픽스처: 세트는 조상이 아니다(squash)"
card "$S2"; mut3 M6; cd_run "$T/m-M6/ft-nano-close-due.sh"
hasnt "$OUT" "닫기 차례 $SEAT" "M6 judge squash 파서 끔 → ⓓ2 닫기 차례 0(변이 잡힘)"
card "$S2"; cd_run "$BIN/ft-nano-close-due.sh"
has "$OUT" "닫기 차례 $SEAT" "M6 원본 대조: squash 착지 → 닫기 차례 1줄"
git -C "$PACK" update-ref refs/remotes/origin/main "$S"   # 되돌림
cmp -s "$BIN/ft-nano-close-due.sh" "$BIN/../kit/fable-team/bin/ft-nano-close-due.sh" && ok "짝 cmp0 ft-nano-close-due.sh" || bad "짝 다름" ""
finish
