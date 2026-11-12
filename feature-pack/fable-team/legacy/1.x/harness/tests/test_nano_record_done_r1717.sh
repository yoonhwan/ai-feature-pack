#!/usr/bin/env bash
# test_nano_record_done_r1717.sh — r1717 묶음 2(A12~A16): D1 일 끝 완료 줄 · D2 세션 기록 1파일 · D3 닫기 요청만(kill·닫기 도구 호출 0 · role=nano 만) · D4 잔여 판정(팀장 몫뿐 = 닫기 요청)
#   D5 닫기 거절 이력(1회 = 나노 · 2회 = 팀장 «[유보]» · 3회부터 0) + 변이 M10·M11·M12·M13(변이마다 원본 대조) + 기준판 D1(팩 103be13029 = 도구 없음)
#   세계 = _nano_record_r1717_fixture.sh(임시 bare remote 2 · 사본 리포 2 · 가짜 명부·mbox·tmux) · 실 명부·실 우편함·실 tmux·네트워크 0 · sleep 0 · 자기 파일 재호출 0
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_nano_record_r1717_fixture.sh"
NN() { printf 'byz-harness-nano-%s#0' "$1"; }
TST='bash tests/t.sh rc=0'
work() { g "$PACK" checkout -q -B "nano/$1" origin/main; echo "$1" > "$PACK/w-$1"; g "$PACK" add -A; g "$PACK" commit -qm "work $1"; WH="$(g "$PACK" rev-parse HEAD)"; }   # 나노 가지 nano/<key> 에 커밋 1개(미커밋 0) → WH
fin() { rec done --seat "$1" --card "$2" --did "도구 추가" --test "$TST" --wt "$PACK" "${@:3}"; }
world

d1() {  # D1 (A12) 착지 전 done → 세트·완료 줄 · 팀장 1통(네 칸) · 같은 세트 재실행 = ALREADY
  local s="d1$1" n c0; n="$(NN "d1$1")"; fresh; card "$s"; seats "$n|nano|$s"; work "$s"
  fin "$n" "$s" --pr 7; t "D1 DONE rc0" [ "$RC ${OUT%%$'\n'*}" = "0 DONE" ]
  t "D1 카드 ref 판에 세트 줄" [ "$(nline "$s" "^- 세트: $WH · 시험: $TST · 이슈: 0$")" = 1 ]
  t "D1 완료 줄(병합 상태 착지 전)" [ "$(nline "$s" "^- 완료: $n · 한 일: 도구 추가 · 산출: nano/$s@${WH:0:10} · 병합 상태: 착지 전(PR #7) · 남은 일: 없음$")" = 1 ]
  t "D1 팀장 «[완료…]» 1통 · 네 칸" [ "$(nto "$MASTER" "\[완료.*\] $n $s · 한 일: 도구 추가 · 산출: nano/$s@${WH:0:10} · 병합 상태: 착지 전(PR #7) · 남은 일: 없음 ")" = 1 ]
  c0="$(ncommit)"; fin "$n" "$s" --pr 7; t "D1 같은 세트 재실행 = ALREADY" [ "$RC ${OUT%%$'\n'*}" = "0 ALREADY" ]; t "D1 커밋·쪽지 그대로" [ "$(ncommit) $(nto "$MASTER")" = "$c0 1" ]; return $E
}
d2() {  # D2 (A13) 세션 기록 쓰기 실패 = 판정 불가 rc 3 · 닫기 요청 0 → 정상 = 파일 1개 6칸 · HANDOFF 가 있으면 경로만
  local s="d2$1" n f keep; n="$(NN "d2$1")"; f="$STATE/seat-record/$n.md"; fresh; card "$s"; seats "$n|nano|$s"; work "$s"
  keep="$TOOL"; MUTSRC="$BIN" mutbin "d2w$1" ft_nano_record_notify.py "${WFAIL[@]}"; TOOL="$MB/ft-nano-record.sh"; fin "$n" "$s"; TOOL="$keep"
  t "D2 쓰기 실패 = rc 3" [ "$RC" = 3 ]; t "D2 판정 불가 줄" inc "$OUT" "판정 불가 세션 기록 쓰기"; t "D2 닫기 요청 0" [ "$(nto "$MASTER")" = 0 ]; t "D2 파일 0" [ ! -e "$f" ]
  fin "$n" "$s"; t "D2 정상 = 파일 1개" [ "$(ls "$STATE/seat-record" | grep -c .)" = 1 ]
  t "D2 6칸" [ "$(grep -c -e '^- 카드: ' -e '^- 한 일: ' -e '^- 산출: ' -e '^- 남은 일: ' -e '^- 다시 열 때 먼저 읽을 것: ' -e '^- 받은 쪽지 seq: ' "$f") $(grep -c '^- ' "$f")" = "6 6" ]
  t "D2 산출 칸(가지·세트·PR·착지)" inc "$(cat "$f")" "- 산출: 가지 nano/$s · 세트 $WH · PR - · 착지 전"; t "D2 정상 = 닫기 요청 1통" [ "$(nto "$MASTER")" = 1 ]
  echo "# 인계서" > "$T/HANDOFF-$s.md"; fin "$n" "$s" --handoff "$T/HANDOFF-$s.md"; t "D2 HANDOFF 있으면 경로만(두 벌 0)" [ "$(grep -c '^- ' "$f") $(grep -c "^- 인계서: $T/HANDOFF-$s.md$" "$f")" = "1 1" ]; return $E
}
d3() {  # D3 (A14) done·landed 동안 tmux kill·ft-nano-close·ft-seat-close 호출 0 · role=arch 좌석 = REJECT · 쓰기 0
  local s="d3$1" u="d3u$1" n a c0 f; n="$(NN "d3$1")"; a="byz-harness-arch-d3$1#1"; fresh; cardf "$s"; cardf "$u"; cpush; seats "$n|nano|$s" "$a|arch|$u"; work "$s"
  MUTSRC="$BIN" mutbin "d3k$1"; for f in ft-nano-close.sh ft-seat-close.sh; do printf '#!/bin/sh\necho "%s $*" >> "%s"\n' "$f" "$NC_LOG" > "$MB/$f"; done; TOOL="$MB/ft-nano-record.sh"
  fin "$n" "$s"; t "D3 done DONE" inc "$OUT" "DONE"; land 43; turn 43 "$s"; rec landed --seat "$n" --pr 43 --card "$s"; t "D3 landed DONE" inc "$OUT" "DONE"
  t "D3 tmux kill 0" [ "$(grep -c 'kill' "$TMUX_LOG")" = 0 ]; t "D3 닫기 도구 호출 0" [ ! -s "$NC_LOG" ]
  c0="$(ncommit)"; work "$u"; fin "$a" "$u"; t "D3 arch 좌석 done = REJECT" [ "$RC" = 1 ]; t "D3 사유" inc "$OUT" "REJECT done 은 명부 role=nano 좌석만 — $a"
  turn 43 "$u"; rec landed --seat "$a" --pr 43 --card "$u" --test "$TST"; t "D3 arch 좌석 landed = REJECT" [ "$RC" = 1 ]; t "D3 쓰기 0" [ "$(ncommit)" = "$c0" ]; return $E
}
d4() {  # D4 (A15) 남은 일이 팀장 몫뿐 = «[완료·닫기 요청]» + 승인 갈래 문장 · 배정 줄 그대로 · 나노 몫 = REJECT
  local s="d4$1" u="d4u$1" n m b0 c0; n="$(NN "d4$1")"; m="$(NN "d4u$1")"; fresh; cardf "$s"; cardf "$u"; cpush; seats "$n|nano|$s" "$m|nano|$u"; work "$s"; b0="$(ctext "$s" | sed '/^## 상태/,$d')"
  fin "$n" "$s" --left "설치=팀장 착지=팀장"; t "D4 DONE" inc "$OUT" "DONE"
  t "D4 머리 «[완료·닫기 요청]» + 남은 일" [ "$(nto "$MASTER" "\[완료·닫기 요청\] $n $s · .* · 남은 일: 설치=팀장 착지=팀장 · 세션 기록 ")" = 1 ]
  t "D4 승인 갈래 문장" [ "$(nto "$MASTER" "닫는 길 = 승인 갈래(DA APPROVE · 인수 · 원격 보존 — r1670 조건 그대로)$")" = 1 ]
  t "D4 카드 «- 배정:» 줄 바이트 같음(상태 절 앞 전부)" [ "$(ctext "$s" | sed '/^## 상태/,$d')" = "$b0" ]; t "D4 배정 줄 1개" [ "$(nline "$s" "^- 배정: 좌석 x$")" = 1 ]
  c0="$(ncommit)"; work "$u"; fin "$m" "$u" --left "보정=나노"; t "D4 나노 몫 = REJECT" [ "$RC" = 1 ]; t "D4 사유" inc "$OUT" "REJECT 남은 일에 나노 몫 — 끝낸 뒤 다시"; t "D4 쓰기 0" [ "$(ncommit) $(nto "$MASTER")" = "$c0 1" ]; return $E
}
d5() {  # D5 (A16) refused 1회 = 나노 1통 · 2회 = 팀장 «[유보]» · 3회 = 0 · sha 만 다름 = 같은 키 · 다른 원인 = 새 키 · 사유 여러 줄 전부
  local s="d5$1" n c1 c2; n="$(NN "d5$1")"; fresh; card "$s"; seats "$n|nano|$s"
  c1="REJECT $n"$'\n'"  - ⑥--landed-pr 카드 «세트:» 40-hex 줄이 없다: abc1234def"$'\n'"  - ③워크트리에 0분 내 편집"; c2="${c1/abc1234def/9998887776}"
  rec refused --seat "$n" --cause "$c1"; t "D5 1회째" inc "$OUT" "REFUSED $n 1회째"; t "D5 나노 «[정리 차례 · 닫기 거절]» 1통" [ "$(nto "$n" "\[정리 차례 · 닫기 거절\] 원인: ")" = 1 ]
  t "D5 사유 여러 줄 = 본문에 전부" [ "$(nto "$n" "«세트:» 40-hex 줄이 없다: abc1234def / - ③워크트리에 0분 내 편집 — 고친 뒤 landed 또는 done 을 다시")" = 1 ]
  rec refused --seat "$n" --cause "$c1"; t "D5 2회 = 나노 0 · 팀장 «[유보]» 1통" [ "$(nto "$n") $(nto "$MASTER" "\[유보\] $n $s 원인: ")" = "1 1" ]
  rec refused --seat "$n" --cause "$c1"; t "D5 3회 = 발신 0(새 프로세스에서도 셈 유지)" [ "$(nsent .) ${OUT##* }" = "2 3회째" ]
  rec refused --seat "$n" --cause "$c2"; t "D5 원인 글의 sha 만 다름 = 같은 키" [ "$(nsent .) ${OUT##* }" = "2 4회째" ]
  rec refused --seat "$n" --cause "REJECT $n"$'\n'"  - ①결과 경로 없음"; t "D5 다른 원인 = 새 키 1회째" [ "$(nto "$n") ${OUT##* }" = "2 1회째" ]; return $E
}
step "사례 D1~D5"; run "D1 일 끝 완료 줄(A12)" d1; run "D2 세션 기록 1파일(A13)" d2; run "D3 닫기 요청만(A14)" d3; run "D4 잔여 판정(A15)" d4; run "D5 닫기 거절 이력(A16)" d5
step "변이 M10·M11·M12·M13 (+원본 대조)"
mutbin m10 ft_nano_record_done.py '    if not path:   # r1717-mut:seatrec' '    if False:'; mutcase M10 d2 10
mutbin m11 ft_nano_record_done.py '    if not isinstance(row, dict) or row.get("role") != "nano":   # r1717-mut:role' '    if not isinstance(row, dict):'; mutcase M11 d3 11
mutbin m12 ft_nano_record_done.py '    if not left_free(left, master):   # r1717-mut:left' '    if False:'; mutcase M12 d4 12
mutbin m13 ft_nano_record_done.py '    n = int(ctx.store()["refused"].get(rk) or 0) + 1   # r1717-mut:count' '    n = 1'; mutcase M13 d5 13
step "기준판 D1 (팩 103be13029fc16eb35fb0a305defcbad6c46ce10 — 도구 없음)"
BASE="$T/base"; mkdir -p "$BASE"
if git -C "$H" archive 103be13029fc16eb35fb0a305defcbad6c46ce10 -- bin/ft-team-lib.sh bin/ft-merge-lib.sh 2>/dev/null | tar -x -C "$BASE" 2>/dev/null && [ -f "$BASE/bin/ft-merge-lib.sh" ]; then
  [ ! -e "$BASE/bin/ft-nano-record.sh" ] && ok "기준판에 도구 없음" || bad "기준판에 도구가 있다"
  if o="$(BIN="$BASE/bin"; TOOL="$BIN/ft-nano-record.sh"; d1 base)"; then bad "기준판에서 D1 이 통과함"; else ok "기준판 D1 FAIL(기대) ::$(printf '%s\n' "$o" | grep -m1 '^  x ' | sed 's/ :: .*//')"; fi
else bad "기준판 꺼내기 실패 — 팩 리포 밖이거나 얕은 사본"; fi
finish
