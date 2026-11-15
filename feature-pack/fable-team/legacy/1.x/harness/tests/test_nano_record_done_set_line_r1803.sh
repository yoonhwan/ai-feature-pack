#!/usr/bin/env bash
# test_nano_record_done_set_line_r1803.sh — r1803: 보정 커밋 뒤 done 재실행 = 상태 절에 새 세트 줄 «덧붙임»(옛 줄 그대로) · 읽는 쪽(marks ⓢ · last_set)도 마지막 = 새 HEAD
#   반례 ①~④(카드 동결 번호) + 변이 M1(«아무» 세트 줄 → ① FAIL) · M2(옛 세트 줄 지움 → ① FAIL) · M3(같은 head 에도 덧붙임 → ③ FAIL) · ⑤ = 기존 nano_record 시험(따로 돌린다)
#   세계 = _nano_record_r1717_fixture.sh(임시 bare remote · 가짜 명부·mbox·tmux) · 실 카드 0 · sleep 0
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_nano_record_r1717_fixture.sh"
NN() { printf 'byz-harness-nano-%s#0' "$1"; }
TST='bash tests/t.sh rc=0'
work() { g "$PACK" checkout -q -B "nano/$1" origin/main; echo "$1" > "$PACK/w-$1"; g "$PACK" add -A; g "$PACK" commit -qm "work $1"; WH="$(g "$PACK" rev-parse HEAD)"; }
more() { echo "$1" >> "$PACK/w-$1"; g "$PACK" add -A; g "$PACK" commit -qm "fix $1"; WH="$(g "$PACK" rev-parse HEAD)"; }   # DA 보정·모드 커밋 1개 더
fin() { rec done --seat "$1" --card "$2" --did "도구 추가" --test "$TST" --wt "$PACK" --pr 7; }
sets() { ctext "$1" | sed -n 's/^- 세트: \([0-9a-f]\{40\}\) .*/\1/p' | tr '\n' ' ' | sed 's/ $//'; }   # 상태 절 세트 줄 sha 를 순서대로
marks_s() {  # marks_s <stem> <좌석> — ft_nano_record.marks 의 ⓢ(마지막 세트 줄) sha
  ctext "$1" > "$T/c-$1.md"; PYTHONPATH="$BIN" python3 -c '
import sys
from ft_nano_record import SET_RX, marks, section
lines, st, en = section(open(sys.argv[1], encoding="utf-8").read())
m = SET_RX.search(marks(lines[st + 1:en], sys.argv[2], "0" * 40)["s"]); print(m.group(1) if m else "-")' "$T/c-$1.md" "$2"
}
refkey() {  # refkey <stem> — 보낸 기록 «refused» 키(stem|좌석|원인|last_set)의 마지막 칸
  python3 -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8")).get("refused", {})
print(" ".join(k.rsplit("|", 1)[1] for k in d if k.startswith(sys.argv[2] + "|")))' "$STATE/land-record-notified.json" "$1"
}
two() { work "$1"; H1="$WH"; fin "$2" "$1"; more "$1"; fin "$2" "$1"; }   # done(H1) → 커밋 1개 더(H2 = WH) → done(H2)
world

c1() {  # ① done(H1) → H2 → done(H2) → 세트 줄 2개(H1 다음 H2) · 마지막 = H2
  local s="c1$1" n; n="$(NN "$s")"; fresh; card "$s"; seats "$n|nano|$s"; two "$s" "$n"
  t "① 두 번째 done = DONE" [ "$RC ${OUT%%$'\n'*}" = "0 DONE" ]
  t "① 세트 줄 = H1 H2(옛 줄 그대로 · 덧붙임)" [ "$(sets "$s")" = "$H1 $WH" ]; return $E
}
c2() {  # ② ① 뒤 읽는 쪽 «마지막 세트» = H2 — marks ⓢ(ft_nano_record.py) · last_set(refused 키)
  local s="c2$1" n; n="$(NN "$s")"; fresh; card "$s"; seats "$n|nano|$s"; two "$s" "$n"
  t "② marks ⓢ = H2" [ "$(marks_s "$s" "$n")" = "$WH" ]
  rec refused --seat "$n" --cause "REJECT ⑥ 세트 ≠ HEAD"; t "② refused 1회째" inc "$OUT" "REFUSED $n 1회째"
  t "② last_set = H2" [ "$(refkey "$s")" = "$WH" ]; return $E
}
c3() {  # ③ ① 뒤 done(H2) 다시 → ALREADY · 커밋·쪽지 수 그대로
  local s="c3$1" n c0 m0; n="$(NN "$s")"; fresh; card "$s"; seats "$n|nano|$s"; two "$s" "$n"; c0="$(ncommit)"; m0="$(nto "$MASTER")"
  fin "$n" "$s"; t "③ ALREADY" [ "$RC ${OUT%%$'\n'*}" = "0 ALREADY" ]
  t "③ 커밋·쪽지 그대로 · 세트 줄 그대로" [ "$(ncommit) $(nto "$MASTER") $(sets "$s")" = "$c0 $m0 $H1 $WH" ]; return $E
}
c4() {  # ④ done(H1) → H2 → done(H2) → H1 으로 되돌림 → done → 세트 줄 H1 H2 H1 · 마지막 = H1(지우기 0)
  local s="c4$1" n h2; n="$(NN "$s")"; fresh; card "$s"; seats "$n|nano|$s"; two "$s" "$n"; h2="$WH"
  g "$PACK" reset -q --hard "$H1"; fin "$n" "$s"; t "④ DONE" [ "$RC ${OUT%%$'\n'*}" = "0 DONE" ]
  t "④ 세트 줄 = H1 H2 H1" [ "$(sets "$s")" = "$H1 $h2 $H1" ]; t "④ marks ⓢ = H1" [ "$(marks_s "$s" "$n")" = "$H1" ]; return $E
}
step "반례 ①~④"; run "① 보정 뒤 새 세트 줄 덧붙임" c1; run "② 읽는 쪽 마지막 = H2" c2; run "③ 같은 HEAD = ALREADY" c3; run "④ H1→H2→H1 = 마지막 기준" c4
step "변이 M1~M3 (+원본 대조)"
mutbin m1 ft_nano_record_done.py 'if sets[-1:] == [head]' 'if sets'; mutcase M1 c1 1
mutbin m2 ft_nano_record_write.py '        new = "\n".join(lines[:k] + add + lines[k:])' \
  '        new = "\n".join([x for x in lines[:k] if not (add[0].startswith("- 세트:") and x.startswith("- 세트:"))] + add + lines[k:])'; mutcase M2 c1 2
mutbin m3 ft_nano_record_done.py 'if sets[-1:] == [head]' 'if False'; mutcase M3 c3 3
finish
