#!/usr/bin/env bash
# test_nano_record_ownerless_r1805.sh — r1805 «주인 없음» 착지 카드를 카드 팀 팀장이 landed 로 닫는 길: 사례 ①·①′·②·③·④·④b·④c·⑤ + 변이 M1~M4(변이마다 원본 대조) + 기준판 ①①′④④b Red.
#   세계 = _nano_record_r1717_fixture.sh(임시 bare remote 2 · 사본 리포 2 · 가짜 명부·mbox·tmux) + planner 팀(가짜 명부 seats-planner.json · 카드 루트 design/teams/planner/indices)
#   실 장부·실 명부·실 우편함·실 tmux·네트워크 0 · sleep 0 · 사례 = 하위 셸 1개(사례마다 새 카드 stem) · ⑥ = 기존 r1717·r1743·r1782 시험 파일
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_nano_record_r1717_fixture.sh"
NN() { printf 'byz-harness-nano-%s#0' "$1"; }
PM="byz-planner-master-pi#7"; PDESK="byz-planner-desk-pi#1"; PIDX="design/teams/planner/indices"
TST='bash tests/t.sh rc=0'; HOLE='<그 세트에서 돌린 시험 명령>'
ends() { case "$1" in *"$2") return 0;; esac; return 1; }
landed() { rec landed --seat "$1" --pr "$2" --card "$3" "${@:4}"; }
BASE_SHA=9c3818d7277382851247b6dc9e296267a86c5f6f   # 기준판 = 이 카드 전 origin/main

step "사전: 문법 · 짝 사본 · 줄 수"
for f in ft_nano_record_write.py ft_nano_record_notify.py ft_nano_record_due.py; do
  cmp -s "$SRC/$f" "$KIT/$f" && ok "짝 사본 bin·kit cmp0 $f" || bad "짝 사본 다름 $f"
  [ "$(wc -l < "$SRC/$f")" -le 200 ] && ok "≤200줄 $f" || bad "200줄 넘음 $f"
done
world
printf 'planner\t.\torigin/ops/base\t%s\n' "$PIDX" >> "$STATE/directive-roots.tsv"
python3 - "$ROOT/.fable-team/seats-planner.json" "$PM" "$PDESK" "$PIDX" <<'PY'
import json, sys
p, m, d, idx = sys.argv[1:5]
json.dump({"_master": m, "_cards": idx, m: {"role": "master"}, d: {"role": "desk"}}, open(p, "w", encoding="utf-8"), ensure_ascii=False)
PY

own0() {  # own0 <stem> <PR> — harness 카드 · 나노 없음 · 장부 by = planner desk
  fresh; land "$2"; card "$1"; seats; TURN_BY="$PDESK" turn "$2" "$1"
}
c1() {  # ① harness 팀장 landed --test → DONE · 세트·착지 1커밋(r1814 A1: 팀장 갈래 = 완료 줄 0)
  local s="c1$1" c0; own0 "$s" 31; c0="$(ncommit)"
  landed "$MASTER" 31 "$s" --test "$TST"; t "① DONE" inc "$OUT" "DONE"; t "① rc0" [ "$RC" = 0 ]
  t "① 1커밋" [ "$(ncommit)" = "$((c0 + 1))" ]; t "① 세트 줄" [ "$(nline "$s" "^- 세트: $PH · 시험: $TST")" = 1 ]
  t "① 착지 줄" [ "$(nline "$s" "^- 착지: $Q ")" = 1 ]; t "① 완료 줄 0(r1814 A1)" [ "$(nline "$s" "^- 완료:")" = 0 ]
  return $E
}
c1b() {  # ①′ 같은 입력에 --test 없음 → «세트 줄 없음 — --test 필요» REJECT · 쓰기 0
  local s="c1b$1" c0; own0 "$s" 32; c0="$(ncommit)"
  landed "$MASTER" 32 "$s"; t "①′ REJECT rc1" [ "$RC" = 1 ]; t "①′ 사유" inc "$OUT" "세트 줄 없음 — --test 필요"; t "①′ 쓰기 0" [ "$(ncommit)" = "$c0" ]
  return $E
}
c2() {  # ② 같은 줄에서 planner 팀장(장부 by 팀) landed → REJECT
  local s="c2$1" c0; own0 "$s" 33; c0="$(ncommit)"
  landed "$PM" 33 "$s" --test "$TST"; t "② REJECT rc1" [ "$RC" = 1 ]; t "② 사유" inc "$OUT" "차례 좌석이 아님"; t "② 쓰기 0" [ "$(ncommit)" = "$c0" ]
  return $E
}
c3() {  # ③ 나노 차례 좌석이 있는 카드 → 팀장 landed REJECT(가로채기 0)
  local s="c3$1" n c0; n="$(NN "c3$1")"; fresh; land 34; card "$s"; seats "$n|nano|$s"; TURN_BY="$PDESK" turn 34 "$s"; c0="$(ncommit)"
  landed "$MASTER" 34 "$s" --test "$TST"; t "③ REJECT rc1" [ "$RC" = 1 ]; t "③ 사유" inc "$OUT" "차례 좌석이 아님(지금 차례 = $n)"; t "③ 쓰기 0" [ "$(ncommit)" = "$c0" ]
  return $E
}
c4() {  # ④ due 담당 = harness 팀장(회귀) · notify 수신 = harness 팀장 · 끝 = landed 명령 + --test 꼬리
  local s="c4$1" b; own0 "$s" 35
  rec due --pr 35; t "④ due 주인 없음 담당 = harness 팀장" inc "$OUT" "주인 없음 $s 담당=$MASTER 빠짐=ⓢⓛ"
  rec notify --pr 35; t "④ 팀장 1통" [ "$(nto "$MASTER" "\[정리 차례 · 주인 없음\] $s ")" = 1 ]; t "④ planner 팀장 0통" [ "$(nto "$PM")" = 0 ]
  b="$(awk -F'\t' -v to="$MASTER" '$1 != "FAIL" && $2 == to {print $4}' "$MBOX_LOG" | tail -1)"
  t "④ 끝 = landed … --test 꼬리" ends "$b" "ft-nano-record.sh landed --seat $MASTER --pr 35 --card $s --test \"$HOLE rc=0\""
  return $E
}
c4b() {  # ④b 쪽지 끝 명령을 그대로 · <…> 자리만 실제 rc0 시험으로 채워 실행 → DONE · 다음 due = 끝
  local s="c4b$1" b cmd; own0 "$s" 36; rec notify --pr 36
  b="$(awk -F'\t' -v to="$MASTER" '$1 != "FAIL" && $2 == to {print $4}' "$MBOX_LOG" | tail -1)"; cmd="${b##*닫는 길 = }"
  t "④b 명령 머리 FT_ROOT=" inc "$cmd" "FT_ROOT="; cmd="${cmd//$HOLE/bash tests/t.sh}"
  OUT="$(cd "$T" && bash -c "$cmd" 2>&1)"; RC=$?; t "④b DONE" inc "$OUT" "DONE"; t "④b rc0" [ "$RC" = 0 ]
  rec due --pr 36; t "④b 다음 due = 끝" inc "$OUT" "끝 $s pr=36"; t "④b 주인 없음 0" exc "$OUT" "주인 없음"
  return $E
}
c4c() {  # ④c planner 폴더 카드 · by = planner desk · 나노 없음 → 담당 = planner 팀장(r1774 꼴 · 회귀)
  local s="c4c$1"; fresh; land 37; IDX="$PIDX" card "$s"; seats; TURN_BY="$PDESK" IDX="$PIDX" turn 37 "$s"
  rec due --pr 37; t "④c 담당 = planner 팀장" inc "$OUT" "주인 없음 $s 담당=$PM 빠짐=ⓢⓛ"
  return $E
}
c5() {  # ⑤ 카드 팀 명부 읽기 실패 → rc3 · 쓰기 0 · 쪽지 0
  local s="c5$1" c0 sj="$ROOT/.fable-team/seats-harness.json"; own0 "$s" 38; c0="$(ncommit)"; mv "$sj" "$sj.off"
  landed "$MASTER" 38 "$s" --test "$TST"; t "⑤ landed rc3" [ "$RC" = 3 ]; t "⑤ 판정 불가 줄" inc "$OUT" "판정 불가 명부 읽기(harness)"
  rec notify --pr 38; t "⑤ notify rc3" [ "$RC" = 3 ]; mv "$sj.off" "$sj"
  t "⑤ 쓰기 0" [ "$(ncommit)" = "$c0" ]; t "⑤ 쪽지 0" [ "$(nmsg .)" = 0 ]
  return $E
}
step "사례 ①·①′·②·③·④·④b·④c·⑤"
run "① 팀장 landed DONE" c1; run "①′ --test 없음 REJECT" c1b; run "② planner 팀장 REJECT" c2; run "③ 나노 있는 카드 REJECT" c3
run "④ 담당·쪽지 끝 명령" c4; run "④b 쪽지 명령 실행 → 끝" c4b; run "④c planner 카드 담당(회귀)" c4c; run "⑤ 명부 실패 rc3" c5
step "변이 M1~M4 (+원본 대조)"
W='        own = own or {s: ("팀장", stem) for s in [doc.get("_master")] if s and s == a.seat}   # r1805 A1 · r1814 A1'
mutbin m1 ft_nano_record_write.py "$W" '        own = own | {s: ("팀장", stem) for s in [doc.get("_master")] if s and s == a.seat}'; mutcase M1 c3 1
mutbin m2 ft_nano_record_write.py "$W" '        own = own or {s: ("팀장", stem) for s in [ctx.seats((str(e.get("by") or "").split("-") + ["", ""])[1]).get("_master")] if s and s == a.seat}'; mutcase M2 c1 2; mutcase M2 c2 2
mutbin m3 ft_nano_record_write.py '    doc, info = ctx.seats(team), {}' '    try:
        doc = ctx.seats(team)
    except Unjudged:
        doc = {}
    info = {}'; mutcase M3 c5 3
mutbin m4 ft_nano_record_notify.py "{r['stem']}{test}\"" "{r['stem']}\""; mutcase M4 c4 4; mutcase M4 c4b 4
step "기준판 ①①′④④b Red · ②③④c 통과(회귀) (팩 $BASE_SHA)"
BASE="$T/base"; mkdir -p "$BASE"
if git -C "$H" archive "$BASE_SHA" -- bin 2>/dev/null | tar -x -C "$BASE" 2>/dev/null && [ -f "$BASE/bin/ft-nano-record.sh" ]; then
  for c in c1 c1b c4 c4b; do ( BIN="$BASE/bin"; TOOL="$BIN/ft-nano-record.sh"; "$c" base ) >/dev/null 2>&1 && bad "기준판에서 $c 통과함" || ok "기준판 $c FAIL(기대 Red)"; done
  for c in c2 c3 c4c; do ( BIN="$BASE/bin"; TOOL="$BIN/ft-nano-record.sh"; "$c" base ) >/dev/null 2>&1 && ok "기준판 $c 통과(회귀)" || bad "기준판 $c FAIL"; done
else bad "기준판 꺼내기 실패 — 팩 리포 밖이거나 얕은 사본"; fi
finish
