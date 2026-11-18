#!/usr/bin/env bash
# test_nano_record_wake_r2015.sh — r2015 «[정리 차례]» 깨움 확인: 차례 쪽지 발신의 doorbell=<값> 이 sent 가 아니면 같은 좌석 ring 1회 · ring 도 실패면 팀장 «깨움 실패» 1통(같은 열쇠 1회).
#   T1 doorbell=sent → ring 0 · T2 quiet → ring 1 + WAKE 줄 1 · T3 칸 없음 → ring 1 · T4 ring rc≠0 → 팀장 1통 · 같은 열쇠 다시 = 추가 0 · T5 주인 없음·카드 없음·밀림 = ring 0
#   변이 M1 = ring 호출 삭제 → T2 FAIL · M2 = doorbell 값 무시하고 늘 ring → T1 FAIL
#   세계 = _nano_record_r1717_fixture.sh(가짜 mbox(FT_MBOX) · 가짜 명부 · 가짜 tmux) — 실 우편함·실 tmux·네트워크 0 · sleep 0
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_nano_record_r1717_fixture.sh"; . "$HERE/_nano_record_r1717_close_fixture.sh"
NN() { printf 'byz-harness-nano-%s#0' "$1"; }
RL="$MBOX_LOG.ring"
nring() { [ -f "$RL" ] || { echo 0; return; }; grep -cxF -- "$1" "$RL" || true; }   # 그 좌석에 간 ring 수
nwf() { nto "$MASTER" "\[정리 차례 · 깨움 실패\] $1 "; }   # 팀장이 받은 깨움 실패 수
nreq() { nto "$MASTER" "\[완료·닫기 요청\] $1 "; }
wk() { local s="$1" n="$2" pr="$3"; fresh; rm -f "$RL"; land "$pr"; card "$s"; seats "$n|nano|$s"; turn "$pr" "$s"; }   # 차례 줄 1개 세계

step "사전: 문법 · 짝 사본 · 줄 수"
for f in ft_nano_record_notify.py ft_nano_record_wake.py; do
  cmp -s "$SRC/$f" "$KIT/$f" && ok "짝 사본 bin·kit cmp0 $f" || bad "짝 사본 다름 $f"
  [ -f "$SRC/$f" ] && [ "$(wc -l < "$SRC/$f")" -le 200 ] && ok "≤200줄 $f" || bad "200줄 넘음·없음 $f"
done
world; closebin

t1() {  # T1 doorbell=sent → ring 0 · WAKE 줄 0
  local s="t1$1" n; n="$(NN "t1$1")"; wk "$s" "$n" 1
  MBOX_DB=sent rec notify --pr 1; t "T1 차례 1통" [ "$(nto "$n" "\[정리 차례\] $s ")" = 1 ]; t "T1 ring 0" [ "$(nring "$n")" = 0 ]; t "T1 WAKE 0" exc "$OUT" "WAKE "; return $E
}
t2() {  # T2 doorbell=quiet → ring 1 · WAKE 줄 1 · ring 성공 = 팀장 깨움 실패 0
  local s="t2$1" n; n="$(NN "t2$1")"; wk "$s" "$n" 2
  MBOX_DB=quiet rec notify --pr 2; t "T2 ring 1" [ "$(nring "$n")" = 1 ]
  t "T2 WAKE 줄 1" [ "$(printf '%s\n' "$OUT" | grep -c "^WAKE $n doorbell=quiet → ring rc=0")" = 1 ]; t "T2 깨움 실패 0" [ "$(nwf "$n")" = 0 ]; return $E
}
t3() {  # T3 doorbell 칸 없음 → ring 1
  local s="t3$1" n; n="$(NN "t3$1")"; wk "$s" "$n" 3
  MBOX_DB= rec notify --pr 3; t "T3 ring 1" [ "$(nring "$n")" = 1 ]; t "T3 WAKE 못 읽음" inc "$OUT" "WAKE $n doorbell=못읽음 → ring rc=0"; return $E
}
t4() {  # T4 ring rc≠0 → 팀장 1통 · 같은 열쇠(되풀이 차례) 다시 = 깨움 실패 추가 0 · ring 이 rc0 이어도 주입 0(absent)이면 실패
  local s="t4$1" n; n="$(NN "t4$1")"; wk "$s" "$n" 4
  MBOX_DB=quiet MBOX_RING_RC=7 rec notify --pr 4; t "T4 WAKE rc=7" inc "$OUT" "WAKE $n doorbell=quiet → ring rc=7"; t "T4 깨움 실패 1통" [ "$(nwf "$n")" = 1 ]
  t "T4 본문 카드·seq" [ "$(nto "$MASTER" "깨움 실패\] $n $s seq=[0-9]")" = 1 ]
  MBOX_DB=quiet MBOX_RING_RC=7 FT_LAND_RECORD_NOW=$(( $(date +%s) + 4000 )) rec notify --pr 4
  t "T4 다시 = 차례 2통째 · ring 2" [ "$(nto "$n" "\[정리 차례\] $s ") $(nring "$n")" = "2 2" ]; t "T4 같은 열쇠 = 깨움 실패 추가 0" [ "$(nwf "$n")" = 1 ]
  local s2="t4b$1" n2; n2="$(NN "t4b$1")"; wk "$s2" "$n2" 5
  MBOX_DB=quiet MBOX_RING_DB=absent rec notify --pr 5; t "T4 ring absent = 깨움 실패 1통" [ "$(nwf "$n2")" = 1 ]; return $E
}
t5() {  # T5 주인 없음·카드 없음·닫기 요청 밀림 = ring 0(차례 쪽지만)
  local s="t5$1" n b nb; n="$(NN "t5$1")"; b="t5b$1"; nb="$(NN "t5b$1")"; fresh; rm -f "$RL"; land 6; card "$s"; seats "$n|nano|$s"; dead "$n"; turn 6 "$s"
  MBOX_DB=quiet rec notify --pr 6; t "T5 주인 없음 팀장 1통" [ "$(nto "$MASTER" "주인 없음\] $s ")" = 1 ]
  land 7; TURN_BY="$n" turn 7; MBOX_DB=quiet rec notify --pr 7; t "T5 카드 없음 팀장 1통" [ "$(nto "$MASTER" "카드 없음\] PR #7 ")" = 1 ]
  land 8; card "$b"; seats "$nb|nano|$b"; turn 8 "$b"; MBOX_FAIL_HEAD='[완료·닫기 요청]' rec landed --seat "$nb" --pr 8 --card "$b" --test 'bash t.sh rc=0'
  rec due --pr 8; t "T5 due 밀림" inc "$OUT" "닫기 요청 밀림 $nb 카드=$b"
  MBOX_DB=quiet rec notify --pr 8; t "T5 밀림 → 닫기 요청 1통" [ "$(nreq "$b")" = 1 ]
  t "T5 ring 0" [ ! -s "$RL" ]; t "T5 WAKE 0" exc "$OUT" "WAKE "; return $E
}
run "T1 sent = ring 0" t1; run "T2 quiet = ring 1" t2; run "T3 칸 없음 = ring 1" t3; run "T4 ring 실패 = 팀장 1회" t4; run "T5 차례 쪽지만" t5

step "변이"
mutbin m1 ft_nano_record_wake.py 'rc, out, _e = run(' 'rc, out, _e = (0, "", "") if 1 else run('; mutcase M1 t2 1
mutbin m2 ft_nano_record_wake.py 'if db == "sent":' 'if False:'; mutcase M2 t1 2
finish
