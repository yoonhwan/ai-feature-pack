#!/usr/bin/env bash
# test_nano_record_done_new_set_r1936.sh — r1936: done 재실행 때 가지 HEAD ≠ 상태 절 «마지막» 세트 줄 sha 면 새 세트 줄 1개(같으면 0 · ALREADY)
#   반례 ①~⑤ + 변이 M1(«아무» 세트 줄 = 옛 꼴 → ③ FAIL) · M2(«첫» 세트 줄 → ④ FAIL) · ⑥ = 기존 nano_record 시험(따로 돌린다)
#   세계 = _nano_record_r1717_fixture.sh(임시 bare remote · 가짜 명부·mbox·tmux) · 실 카드 0 · sleep 0
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_nano_record_r1717_fixture.sh"
NN() { printf 'byz-harness-nano-%s#0' "$1"; }
TST='bash tests/t.sh rc=0'
work() { g "$PACK" checkout -q -B "nano/$1" origin/main; echo "$1" > "$PACK/w-$1"; g "$PACK" add -A; g "$PACK" commit -qm "work $1"; WH="$(g "$PACK" rev-parse HEAD)"; }
more() { echo "$1" >> "$PACK/w-$1"; g "$PACK" add -A; g "$PACK" commit -qm "merge $1"; WH="$(g "$PACK" rev-parse HEAD)"; }   # 같은 가지에 커밋 1개 더(충돌 해소 merge 세트 꼴)
fin() { rec done --seat "$1" --card "$2" --did "도구 추가" --test "$TST" --wt "$PACK" --pr 7; }
lastset() { ctext "$1" | grep -o '세트: [0-9a-f]\{40\}' | tail -1 | cut -c9-; }
world

c1() {  # ① 세트 줄 없음 → 세트+완료 2줄
  local s="c1$1" n c0; n="$(NN "$s")"; fresh; card "$s"; seats "$n|nano|$s"; work "$s"; c0="$(ncommit)"
  fin "$n" "$s"; t "① DONE" [ "$RC ${OUT%%$'\n'*}" = "0 DONE" ]
  t "① 세트 1 · 완료 1 · 커밋 1" [ "$(nline "$s" "^- 세트: $WH ") $(nline "$s" "@${WH:0:10} ·") $(ncommit)" = "1 1 $((c0 + 1))" ]; return $E
}
c2() {  # ② 마지막 세트 = A · head = A 재실행 → ALREADY · 줄 0
  local s="c2$1" n c0; n="$(NN "$s")"; fresh; card "$s"; seats "$n|nano|$s"; work "$s"; fin "$n" "$s"; c0="$(ncommit)"
  fin "$n" "$s"; t "② ALREADY" [ "$RC ${OUT%%$'\n'*}" = "0 ALREADY" ]; t "② 커밋·쪽지 그대로" [ "$(ncommit) $(nto "$MASTER")" = "$c0 1" ]; return $E
}
c3() {  # ③ 마지막 세트 = A · head = B → 세트 B + 완료 B · 절 마지막 세트 = B
  local s="c3$1" n a; n="$(NN "$s")"; fresh; card "$s"; seats "$n|nano|$s"; work "$s"; a="$WH"; fin "$n" "$s"; more "$s"
  fin "$n" "$s"; t "③ DONE" [ "$RC ${OUT%%$'\n'*}" = "0 DONE" ]
  t "③ 세트 A 1 · 세트 B 1 · 완료 B 1" [ "$(nline "$s" "^- 세트: $a ") $(nline "$s" "^- 세트: $WH ") $(nline "$s" "@${WH:0:10} ·")" = "1 1 1" ]
  t "③ 마지막 세트 = B" [ "$(lastset "$s")" = "$WH" ]; return $E
}
c4() {  # ④ 세트 A → B → A(되돌린 HEAD) → 세트 A 1줄 더함 · 완료 0줄 · 재발신 0
  local s="c4$1" n a c0; n="$(NN "$s")"; fresh; card "$s"; seats "$n|nano|$s"; work "$s"; a="$WH"; fin "$n" "$s"; more "$s"; fin "$n" "$s"
  g "$PACK" reset -q --hard "$a"; c0="$(ncommit)"; fin "$n" "$s"; t "④ DONE" [ "$RC ${OUT%%$'\n'*}" = "0 DONE" ]
  t "④ 세트 A 2 · 완료 A 1 · 커밋 +1" [ "$(nline "$s" "^- 세트: $a ") $(nline "$s" "@${a:0:10} ·") $(ncommit)" = "2 1 $((c0 + 1))" ]
  t "④ 마지막 세트 = A · 쪽지 2통(재발신 0)" [ "$(lastset "$s") $(nto "$MASTER")" = "$a 2" ]; return $E
}
c5() {  # ⑤ 상태 절에 «세트 <sha>»(콜론 없음 · DA 상태 줄 꼴)만 → SET_RX 불일치 → 세트 줄 더함
  local s="c5$1" n; n="$(NN "$s")"; fresh; work "$s"; card "$s" "- 2026-11-14 — DA APPROVE 세트 $WH (DA#10)"; seats "$n|nano|$s"
  fin "$n" "$s"; t "⑤ DONE" [ "$RC ${OUT%%$'\n'*}" = "0 DONE" ]; t "⑤ 세트 줄 1" [ "$(nline "$s" "^- 세트: $WH ")" = 1 ]; return $E
}
step "반례 ①~⑤"; run "① 세트 줄 없음" c1; run "② 같은 HEAD = ALREADY" c2; run "③ 새 HEAD = 새 세트 줄" c3; run "④ A→B→A = 마지막 기준" c4; run "⑤ 콜론 없는 «세트» = 불일치" c5
step "변이 M1·M2 (+원본 대조)"
mutbin m1 ft_nano_record_done.py 'if sets[-1:] == [head]' 'if sets'; mutcase M1 c3 1
mutbin m2 ft_nano_record_done.py 'if sets[-1:] == [head]' 'if sets[:1] == [head]'; mutcase M2 c4 2
finish
