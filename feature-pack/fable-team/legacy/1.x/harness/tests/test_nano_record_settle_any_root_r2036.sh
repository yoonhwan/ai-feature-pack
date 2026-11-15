#!/usr/bin/env bash
# test_nano_record_settle_any_root_r2036.sh — r2036: ft-nano-record settle 이 좌석 팀 폴더 밖 카드를 카드 루트 표(directive-roots.tsv) 전 행에서 찾는다.
#   반례 ①~⑦(카드 r2036 «반례 집합») + ⑧ 회귀(r1717 시험 rc0) + 변이 M1~M3(변이마다 원본 대조) · 기준판(R2036_BASE_BIN) 이면 ①②③ Red 를 기대.
#   세계 = _nano_record_r1717_fixture.sh(임시 bare remote · 사본 리포) + 카드 ref 2개(origin/main = design/teams/{planner,knowledge,v65}/indices · origin/ops/base = design/harness/indices)
#   임시 표·임시 명부(seats-planner·seats-knowledge·seats.json)·임시 장부 — 실 리포·실 좌석 0 · sleep 0
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_nano_record_r1717_fixture.sh"
PL="byz-planner-master-pi#314"; KN="byz-knowledge-master-pi#20"; TAB="$STATE/directive-roots.tsv"
mcard() {  # mcard <팀> <단계> <stem> — origin/main 카드 ref 에 카드 1장(design/teams/<팀>/indices/<단계>/<stem>.md)
  local d="$ROOT/design/teams/$1/indices/$2"; mkdir -p "$d"; printf '# 인덱스: %s\n\n## 상태\n- 대기\n' "$3" > "$d/$3.md"
  g "$ROOT" add -A; g "$ROOT" commit -qm "card $3"; g "$ROOT" push -q origin main
}
tabset() { printf '*\t.\torigin/main\tdesign/teams/*/indices\nharness\t.\torigin/ops/base\t%s\n' "$IDX" > "$TAB"; }
lastcards() { tail -n 1 "$STATE/land-record-turn.jsonl" | python3 -c 'import json,sys;print(" ".join(json.loads(sys.stdin.read()).get("cards") or []))'; }
nled() { wc -l < "$STATE/land-record-turn.jsonl" | tr -d ' '; }
step "사전: 문법 · 짝 사본 · 줄 수 · 세계"
for f in ft_nano_record.py ft_nano_record_due.py; do
  cmp -s "$SRC/$f" "$KIT/$f" && ok "짝 사본 bin·kit cmp0 $f" || bad "짝 사본 다름 $f"
  [ "$(wc -l < "$SRC/$f")" -le 200 ] && ok "≤200줄 $f" || bad "200줄 넘음 $f"
done
world; tabset
python3 - "$ROOT/.fable-team" "$PL" "$KN" <<'PY'
import json, sys
d, pl, kn = sys.argv[1:4]
for f, doc in (("seats-planner.json", {"_master": pl, "_arch": "", "_cards": "design/teams/planner/indices", pl: {"role": "master"}}),
               ("seats-knowledge.json", {"_master": kn, "_arch": "", "_cards": "design/teams/knowledge/indices", kn: {"role": "master"}}),
               ("seats.json", {"_master": "", "_arch": "", "_cards": "design/teams/v65/indices"})):
    json.dump(doc, open(f"{d}/{f}", "w", encoding="utf-8"), ensure_ascii=False)
PY

c1() {  # ① planner 팀장 · v65/대기 카드 → SETTLED · 장부 = 실제 경로
  local s="v65-c1$1"; fresh; mcard v65 대기 "$s"; land 81; turn 81
  rec settle --seat "$PL" --pr 81 --card "$s"; t "① rc0" [ "$RC" = 0 ]; t "① SETTLED" inc "$OUT" "SETTLED PR #81 카드 $s"
  t "① 장부 = v65/대기 실제 경로" [ "$(lastcards)" = "$ROOT/design/teams/v65/indices/대기/$s.md" ]
  return $E
}
c2() {  # ② knowledge 팀장 · 같은 꼴 → SETTLED 같은 경로
  local s="v65-c2$1"; fresh; mcard v65 대기 "$s"; land 82; turn 82
  rec settle --seat "$KN" --pr 82 --card "$s"; t "② rc0" [ "$RC" = 0 ]; t "② SETTLED" inc "$OUT" "SETTLED PR #82 카드 $s"
  t "② 장부 = v65/대기 실제 경로" [ "$(lastcards)" = "$ROOT/design/teams/v65/indices/대기/$s.md" ]
  return $E
}
c3() {  # ③ harness 루트(origin/ops/base) 카드 · planner 팀장 → SETTLED(행마다 그 ref)
  local s="h-c3$1"; fresh; card "$s"; land 83; turn 83
  rec settle --seat "$PL" --pr 83 --card "$s"; t "③ rc0" [ "$RC" = 0 ]; t "③ SETTLED" inc "$OUT" "SETTLED PR #83 카드 $s"
  t "③ 장부 = harness/진행 경로" [ "$(lastcards)" = "$ROOT/$IDX/진행/$s.md" ]
  return $E
}
c4() {  # ④ 좌석 팀 폴더 카드 → 지금과 같은 결과 · 장부 = 실제 단계(진행 · 완성)
  local s="pl-c4$1" w="pl-c4w$1"; fresh; mcard planner 진행 "$s"; mcard planner 완성 "$w"; land 84; turn 84
  rec settle --seat "$PL" --pr 84 --card "$s"; t "④ rc0" [ "$RC" = 0 ]; t "④ SETTLED" inc "$OUT" "SETTLED PR #84 카드 $s"
  t "④ 장부 = planner/진행" [ "$(lastcards)" = "$ROOT/design/teams/planner/indices/진행/$s.md" ]
  rec settle --seat "$PL" --pr 84 --card "$w"; t "④ 완성 rc0" [ "$RC" = 0 ]
  t "④ 장부 = planner/완성(실제 단계)" [ "$(lastcards)" = "$ROOT/design/teams/planner/indices/완성/$w.md" ]
  return $E
}
c5() {  # ⑤ 같은 stem 이 v65·knowledge 두 폴더 → REJECT 모호 · rc1 · 장부 그대로
  local s="dup-c5$1" l0; fresh; mcard v65 대기 "$s"; mcard knowledge 진행 "$s"; land 85; turn 85; l0="$(nled)"
  rec settle --seat "$PL" --pr 85 --card "$s"; t "⑤ rc1" [ "$RC" = 1 ]; t "⑤ REJECT 모호" inc "$OUT" "REJECT 카드 모호 — "
  t "⑤ 두 경로 다 보임" inc "$OUT" "design/teams/v65/indices/대기/$s.md"; t "⑤ knowledge 경로" inc "$OUT" "design/teams/knowledge/indices/진행/$s.md"
  t "⑤ 장부 줄 수 그대로" [ "$(nled)" = "$l0" ]
  return $E
}
c6() {  # ⑥ 어느 루트에도 없음 → «카드 ref 에 카드 없음» 판정 불가 그대로
  local l0; fresh; land 86; turn 86; l0="$(nled)"
  rec settle --seat "$PL" --pr 86 --card "none-c6$1"; t "⑥ rc3" [ "$RC" = 3 ]; t "⑥ 카드 없음 판정 불가" inc "$OUT" "판정 불가 카드 ref 에 카드 없음"
  t "⑥ 장부 그대로" [ "$(nled)" = "$l0" ]
  return $E
}
c7() {  # ⑦ 표 없음·깨짐 → «판정 불가 — 카드 루트 표» 1줄 · 장부 쓰기 0
  local s="v65-c7$1" l0; fresh; mcard v65 대기 "$s"; land 87; turn 87; l0="$(nled)"
  rm -f "$TAB"; rec settle --seat "$PL" --pr 87 --card "$s"
  t "⑦ 표 없음 rc3" [ "$RC" = 3 ]; t "⑦ 표 없음 판정 불가 줄" inc "$OUT" "판정 불가 — 카드 루트 표"; t "⑦ 1줄" [ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = 1 ]
  printf 'garbage\n' > "$TAB"; rec settle --seat "$PL" --pr 87 --card "$s"
  t "⑦ 표 깨짐 rc3" [ "$RC" = 3 ]; t "⑦ 표 깨짐 판정 불가 줄" inc "$OUT" "판정 불가 — 카드 루트 표"
  printf '*\t.\torigin/main\tdesign/teams/*/indices\nharness\t.\t\t%s\n' "$IDX" > "$TAB"; rec settle --seat "$PL" --pr 87 --card "$s"   # DA #306598 R1: 빈 ref 행 = 깨짐(origin/main 대체 0)
  t "⑦ 빈 ref 행 rc3" [ "$RC" = 3 ]; t "⑦ 빈 ref 행 판정 불가 줄" inc "$OUT" "판정 불가 — 카드 루트 표"
  tabset; t "⑦ 장부 그대로" [ "$(nled)" = "$l0" ]
  return $E
}

if [ -n "${R2036_BASE_BIN:-}" ]; then   # 기준판 — ①②③ 이 FAIL 이어야 한다(Red)
  BIN="$R2036_BASE_BIN"; TOOL="$BIN/ft-nano-record.sh"; step "기준판 ①②③ Red 기대"
  for c in c1 c2 c3; do ( $c base ) >/dev/null 2>&1 && bad "기준판에서 $c 통과(Red 아님)" || ok "기준판 $c FAIL(기대)"; done
  finish
fi
step "사례 ①~⑦"
run "① planner 팀장 · v65 카드" c1; run "② knowledge 팀장 · v65 카드" c2; run "③ harness 루트 카드" c3; run "④ 좌석 팀 폴더 · 실제 단계" c4
run "⑤ 모호 REJECT" c5; run "⑥ 어디에도 없음" c6; run "⑦ 표 없음·깨짐" c7
step "변이 M1~M3(사본 · 원본 대조)"
mutbin m1 ft_nano_record_due.py 'hits = ctx.root_hits(stem) if' 'hits = {} if'; mutcase M1 c1 1; mutcase M1 c2 1; mutcase M1 c3 1
mutbin m2 ft_nano_record_due.py 'if not hits or len(hits) > 1:' 'if not hits:'; mutcase M2 c5 2
mutbin m3 ft_nano_record.py '            raise Unjudged(f"— 카드 루트 표' '            return {}  # (f"— 카드 루트 표'; mutcase M3 c7 3
step "⑧ 회귀 — r1717 시험(settle 권한·--no-card·due)"
if o="$(bash "$HERE/test_nano_record_r1717.sh" 2>&1)"; then ok "⑧ test_nano_record_r1717.sh rc0 ($(printf '%s\n' "$o" | grep -c '^PASS') PASS)"; else bad "⑧ r1717 회귀" "$(printf '%s\n' "$o" | grep -E '^FAIL|FAILED' | head -5)"; fi
finish
