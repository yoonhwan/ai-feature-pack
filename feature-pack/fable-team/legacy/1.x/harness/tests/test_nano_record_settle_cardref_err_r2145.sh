#!/usr/bin/env bash
# test_nano_record_settle_cardref_err_r2145.sh — r2145 장부의 cards_err 줄도 settle --no-card(사람 판정)가 있으면 «끝»(D1) · settle 없는 cards_err 는 «판정 불가 카드 ref» rc3(D2) · 그 밖 갈래 불변(D3)
#   사례 ①~④ + 변이 M1·M2(변이마다 원본 대조) + 기준판 ① Red · ②~④ Green · ⑤(D3) = 기존 시험 따로 재실행
#   인자 = 부분(cases 기본 | mut | base) — 시험 1개 70초 상한(하드 룰 22)
#   세계 = _nano_record_r1717_fixture.sh · 장부(land-record-turn.jsonl) 직접 · settle 덧줄 직접 · 실 장부·실 우편함·네트워크 0 · sleep 0
PART="${1:-cases}"; case "$PART" in cases|mut|base) ;; *) echo "usage: $0 [cases|mut|base]" >&2; exit 2;; esac
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_nano_record_r1717_fixture.sh"
BASE_SHA=5e96efca37d12ea35dd9ed6ebacffab7847e2d1b   # 기준판 = 이 카드 전 팩 origin/main
du() { OUT="$(cd "$T" && bash "$1" due --no-fetch 2>&1)"; RC=$?; }   # du <도구> → OUT·RC
BT() { printf '%s/ft-nano-record.sh' "$BB"; }   # 기준판 도구
nl() { printf '%s\n' "$OUT" | grep -c -- "$1" || true; }   # OUT 에서 그 글로 시작하는 줄 수(^ 포함 패턴)
HR="harness|origin/ops/base|$IDX"
roots() { printf '%s\t.\t%s\t%s\n' "${1%%|*}" "$(echo "$1" | cut -d'|' -f2)" "${1##*|}" > "$STATE/directive-roots.tsv"; }
jl() { python3 -c 'import json,sys;print(json.dumps(json.loads(sys.argv[1]),ensure_ascii=False))' "$1" >> "$STATE/land-record-turn.jsonl"; }   # 장부 1줄
cerr() {  # cerr <pr> [<landed 40자>] — 착지 때 카드 ref 를 못 읽은 장부 줄(cards_err · 카드 0)
  jl "{\"pr\":$1,\"repo\":\"p\",\"target\":\"main\",\"landed\":\"${2:-$(printf '%040x' "$1")}\",\"pr_head\":\"$(printf '%040d' 0)\",\"by\":\"byz-x-fix3\",\"cards\":[],\"cards_err\":\"카드 토큰 fix3 풀이 실패\",\"ts\":\"t\"}"
}
nocard() { jl "{\"pr\":$1,\"settle\":\"no-card\",\"cards\":[],\"why\":\"$2\",\"by\":\"$MASTER\",\"ts\":\"t\"}"; }   # settle --no-card 덧줄
cf() { mkdir -p "$OPS/$IDX/진행"; printf '# 인덱스: %s\n\n## 상태\n- 2026-11-12 대기\n' "$1" > "$OPS/$IDX/진행/$1.md"; }   # 기록 없는 카드 1장
opsh() { (cd "$OPS" && git add -A && git commit -qm c && git pull -q --rebase origin ops/base 2>/dev/null; git push -q origin ops/base); }

step "사전: 기준판 · 짝 사본 · 줄 수 · 세계"
BB="$T/base/bin"; mkdir -p "$T/base"
git -C "$H" archive "$BASE_SHA" -- bin 2>/dev/null | tar -x -C "$T/base" 2>/dev/null && [ -f "$BB/ft-nano-record.sh" ] && ok "기준판 꺼냄($BASE_SHA)" || bad "기준판 꺼내기 실패 — 팩 리포 밖이거나 얕은 사본"
cmp -s "$SRC/ft_nano_record_due.py" "$KIT/ft_nano_record_due.py" && ok "짝 사본 bin·kit cmp0" || bad "짝 사본 다름"
[ "$(wc -l < "$SRC/ft_nano_record_due.py")" -le 200 ] && ok "≤200줄" || bad "200줄 넘음"
world

c1() {  # ① (D1) cards_err 줄 + settle --no-card «사유A» → «끝 … 카드 없음 확정 · 사유A» · 카드 ref 줄 0 · rc0
  fresh; roots "$HR"; seats; cerr 91; nocard 91 "사유A"; du "$TOOL"
  t "① 끝 줄" [ "$(nl '^끝 PR#91 pr=91 .*(카드 없음 확정 · 사유A)$')" = 1 ]; t "① 카드 ref 줄 0" [ "$(nl '^판정 불가 카드 ref ')" = 0 ]; t "① rc0" [ "$RC" = 0 ]
  return $E
}
c2() {  # ② (D2) cards_err 줄 · settle 없음 → «판정 불가 카드 ref …» · rc3
  fresh; roots "$HR"; seats; cerr 91; du "$TOOL"
  t "② 카드 ref 줄" [ "$(nl '^판정 불가 카드 ref 카드 토큰 fix3 풀이 실패 pr=91 ')" = 1 ]; t "② 끝 0" [ "$(nl '^끝 ')" = 0 ]; t "② rc3" [ "$RC" = 3 ]
  return $E
}
c3() {  # ③ (D2) ① 다음 같은 PR 에 새 착지 줄(cards_err) → 새 줄 = 카드 ref 줄 · rc3
  fresh; roots "$HR"; seats; cerr 91; nocard 91 "사유A"; cerr 91 "$(printf 'b%.0s' {1..40})"; du "$TOOL"
  t "③ 새 줄 카드 ref" [ "$(nl '^판정 불가 카드 ref .* pr=91 착지=bbbbbbbbbb$')" = 1 ]
  t "③ rc3" [ "$RC" = 3 ]
  return $E
}
c4() {  # ④ (D3) 카드 2장 PR(cards_err 없음) + settle --card X = 기준판 같은 줄 · cards_err 없는 카드 0 줄 + settle --no-card = 기준판 같은 «끝»
  local s="c4$1" o r; fresh; roots "$HR"; cf "${s}x"; cf "${s}y"; opsh; seats
  jl "{\"pr\":95,\"repo\":\"p\",\"target\":\"main\",\"landed\":\"$(printf '%040x' 95)\",\"pr_head\":\"$(printf '%040d' 0)\",\"by\":\"\",\"cards\":[\"$ROOT/$IDX/진행/${s}x.md\",\"$ROOT/$IDX/진행/${s}y.md\"],\"ts\":\"t\"}"
  jl "{\"pr\":95,\"settle\":\"card\",\"cards\":[\"$ROOT/$IDX/진행/${s}x.md\"],\"why\":\"\",\"by\":\"$MASTER\",\"ts\":\"t\"}"
  jl "{\"pr\":96,\"repo\":\"p\",\"target\":\"main\",\"landed\":\"$(printf '%040x' 96)\",\"pr_head\":\"$(printf '%040d' 0)\",\"by\":\"\",\"cards\":[],\"ts\":\"t\"}"; nocard 96 "사유B"
  du "$TOOL"; o="$OUT"; r="$RC"; t "④ 카드 X 줄" inc "$o" "${s}x"; t "④ 카드 Y 줄 0" exc "$o" "${s}y"; t "④ 96 끝" [ "$(nl '^끝 PR#96 pr=96 .*(카드 없음 확정 · 사유B)$')" = 1 ]
  du "$(BT)"; t "④ = 기준판 줄" [ "$OUT" = "$o" ]; t "④ = 기준판 rc" [ "$RC" = "$r" ]
  return $E
}
echo "부분 = $PART (세 부분 = cases · mut · base)"
if [ "$PART" = cases ]; then step "사례 ①~④"
run "① settle 이 cards_err 보다 먼저" c1; run "② settle 없는 cards_err = 판정 불가" c2; run "③ settle 뒤 새 착지 줄 = 판정 불가" c3; run "④ 카드 갈래·cards_err 없는 settle 불변" c4; fi
if [ "$PART" = mut ]; then step "변이 M1·M2 (+원본 대조)"
mutbin m1 ft_nano_record_due.py 'if e.get("cards_err") and not e["nocard"]:' 'if e.get("cards_err"):'; mutcase M1 c1 1
mutbin m2 ft_nano_record_due.py 'if e.get("cards_err") and not e["nocard"]:' 'if False:'; mutcase M2a c2 2; mutcase M2b c3 3; fi
if [ "$PART" = base ]; then step "기준판 ① Red · ②~④ Green (팩 $BASE_SHA)"
o="$( ( BIN="$BB"; TOOL="$BIN/ft-nano-record.sh"; c1 base ) 2>&1 )" && bad "기준판에서 c1 통과함" || ok "기준판 c1 FAIL(기대 Red)"; printf '%s\n' "$o" | grep '^  x ' | head -3
for c in c2 c3 c4; do o="$( ( BIN="$BB"; TOOL="$BIN/ft-nano-record.sh"; "$c" base ) 2>&1 )" && ok "기준판 $c 통과(지키는 칸)" || bad "기준판 $c FAIL" "$o"; done; fi
finish
