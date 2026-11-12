#!/usr/bin/env bash
# test_land_turn_doc_pr_r1782.sh — r1782: 문서만 바꾼 착지(전부 design/·docs/)는 «정리 차례» 쪽지 0 · 구현 착지는 지금 그대로(계약 A1~A4 · 반례 ①~⑦ · 변이 M1~M5 · 기준판 ①②⑤ Red)
#   세계 = _nano_record_r1717_fixture.sh(카드 리포 ROOT + 카드 ref ops/base · 착지 리포 PACK · 가짜 명부·mbox·tmux) · 착지 = PACK 에서 M → Q 를 만들고 fm_land_turn 을 직접 부른다
#   ff(Q = S) · squash(Q = commit-tree S^{tree} -p M) 둘 다 · 실 장부·실 명부·실 mbox·네트워크 0 · sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_nano_record_r1717_fixture.sh"
LEDGER="$STATE/land-record-turn.jsonl"; BY="byz-harness-planner-pi#1"
world
mkland() {  # mkland <ff|sq> <파일…> → M(착지 전 main) · S(PR head) · Q(착지 sha) · PH — PACK 에 파일을 더한 커밋 1개(push 0)
  local how="$1" f; shift; M="$(g "$PACK" rev-parse origin/main)"; g "$PACK" checkout -q -B "w$RANDOM" "$M"
  for f in "$@"; do mkdir -p "$PACK/$(dirname "$f")"; printf '%s\n' "$f" > "$PACK/$f"; done
  g "$PACK" add -A; g "$PACK" commit -qm work; S="$(g "$PACK" rev-parse HEAD)"; PH="$S"
  if [ "$how" = ff ]; then Q="$S"; else Q="$(g "$PACK" commit-tree "$S^{tree}" -p "$M" -m squash)"; fi
}
lturn() {  # lturn <PR> [r토큰…] → OUT(stdout+stderr)·ERR(stderr만) — ft-merge-land 와 같은 셸 변수(M·Q·REPO·TARGET·HEADSHA·FT_SEAT)로 fm_land_turn 1회
  local pr="$1"; shift
  OUT="$( (set +u; . "$BIN/ft-merge-lib.sh"; REPO="$PACK"; TARGET=main; HEADSHA="$PH"; FT_SEAT="$BY"; fm_land_turn "$ROOT" "$pr" "$SECONDS" "$@") 2>"$T/err")"; ERR="$(cat "$T/err")"; OUT="$OUT$ERR"
}
lline() { grep "\"pr\": $1, " "$LEDGER" 2>/dev/null; }
due() { rec due --pr "$1" --no-fetch; }
DOCW="(문서 PR · 구현 착지 아님)"
tg() { case "$1" in m*) echo "${1#m}1";; o*) echo "${1#o}2";; *) echo "$1";; esac; }   # 변이 꼬리표(m3·o3) → 숫자(31·32) · 카드 토큰·PR 번호가 숫자여야 한다
c1() {  # ① 카드 새 파일 + research json(전부 design/) · 명부에 나노 0 → doc_only:true · cards 1 / ② due «끝 … (문서 PR …)» · notify 발신 0
  local s="r911$(tg "$1")" pr="911$(tg "$1")"; fresh; card "$s-x"; seats
  mkland "${HOW:-sq}" "design/teams/planner/indices/대기/$s-x.md" "design/teams/planner/research/$s/a.json"; lturn "$pr" "$s"
  t "① 장부 1줄" [ "$(lline "$pr" | grep -c .)" = 1 ]; t "① doc_only:true" inc "$(lline "$pr")" '"doc_only": true'
  t "① cards 1(추적용 그대로)" inc "$(lline "$pr")" "\"cards\": [\"$ROOT/$IDX/진행/$s-x.md\"]"; t "① doc_err 없음" exc "$(lline "$pr")" doc_err
  t "② notify 발신 0(주인 없음 0)" [ "$(nsent '정리 차례')" = 0 ]
  due "$pr"; t "② due rc0" [ "$RC" = 0 ]; t "② due = 끝 · 문서 PR" [ "$OUT" = "끝 $s-x pr=$pr 착지=${Q:0:10} 좌석=- $DOCW" ]; return $E
}
c3() {  # ③ ①에 legacy/x.sh 1줄 더 → 칸 없음 · due «주인 없음»(지금 그대로)
  local s="r913$(tg "$1")" pr="913$(tg "$1")"; fresh; card "$s-x"; seats
  mkland sq "design/teams/planner/indices/대기/$s-x.md" "design/teams/planner/research/$s/a.json" legacy/x.sh; lturn "$pr" "$s"
  t "③ doc_only 칸 없음" exc "$(lline "$pr")" doc_only; t "③ doc_err 없음" exc "$(lline "$pr")" doc_err; t "③ WARN 0" exc "$ERR" "WARN doc_err"
  t "③ 팀장 «주인 없음» 쪽지 1통" [ "$(nto "$MASTER" "\[정리 차례 · 주인 없음\] $s-x ")" = 1 ]
  due "$pr"; t "③ due = 주인 없음" inc "$OUT" "주인 없음 $s-x 담당=$MASTER "; return $E
}
c4() {  # ④ ①과 같되 index = 그 카드인 살아 있는 나노 → due «차례 <나노>»(A2ⓐ · 지금 그대로)
  local s="r914$(tg "$1")" pr="914$(tg "$1")" n="byz-harness-nano-r914$(tg "$1")#0"; fresh; card "$s-x"; seats "$n|nano|$s-x"
  mkland sq "design/teams/planner/indices/대기/$s-x.md" "design/teams/planner/research/$s/a.json"; lturn "$pr" "$s"
  t "④ doc_only:true" inc "$(lline "$pr")" '"doc_only": true'
  due "$pr"; t "④ due = 차례 그 나노" inc "$OUT" "차례 $n 종류=닫기 빠짐=ⓢⓛⓒ 카드=$s-x pr=$pr "; t "④ 나노 «[정리 차례]» 1통" [ "$(nto "$n" "\[정리 차례\] $s-x ")" = 1 ]; return $E
}
c5() {  # ⑤ 본문에 r번호 없음 · docs/a.md 만 → cards:[] · due «끝 PR#N … (문서 PR …)» · 쪽지 0
  local pr="915$(tg "$1")"; fresh; seats; mkland sq docs/a.md; lturn "$pr"
  t "⑤ cards:[] · doc_only:true" inc "$(lline "$pr")" '"cards": [], "ts": '; t "⑤ doc_only:true" inc "$(lline "$pr")" '"doc_only": true'
  t "⑤ notify 발신 0(카드 없음 0)" [ "$(nsent '정리 차례')" = 0 ]
  due "$pr"; t "⑤ due rc0" [ "$RC" = 0 ]; t "⑤ due = 끝 PR#N · 문서 PR" [ "$OUT" = "끝 PR#$pr pr=$pr 착지=${Q:0:10} 좌석=- $DOCW" ]; return $E
}
c6() {  # ⑥ M 빈 값 → doc_err · stderr WARN 1줄 · due «주인 없음»(구현으로 본다)
  local s="r916$(tg "$1")" pr="916$(tg "$1")"; fresh; card "$s-x"; seats
  mkland sq "design/teams/planner/indices/대기/$s-x.md"; M=""; lturn "$pr" "$s"
  t "⑥ doc_err 칸" inc "$(lline "$pr")" '"doc_err": "'; t "⑥ doc_only 없음" exc "$(lline "$pr")" doc_only
  t "⑥ stderr WARN doc_err 1줄" [ "$(printf '%s\n' "$ERR" | grep -c '^WARN doc_err: ')" = 1 ]
  due "$pr"; t "⑥ due = 주인 없음" inc "$OUT" "주인 없음 $s-x 담당=$MASTER "; return $E
}
c7() {  # ⑦ ff(Q = S) 와 squash(Q = commit-tree -p M) 의 ① 판정이 같다
  local o; E=0
  o="$(HOW=ff c1 "7$1" 2>&1)" && ok "⑦ ff ① 판정 같음" || { echo "  x ⑦ ff :: $o"; E=1; }
  o="$(HOW=sq c1 "8$1" 2>&1)" && ok "⑦ squash ① 판정 같음" || { echo "  x ⑦ squash :: $o"; E=1; }; return $E
}
step "사전: 짝 사본 · 문법"
for f in ft-merge-lib.sh ft_nano_record_due.py; do cmp -s "$SRC/$f" "$KIT/$f" && ok "짝 사본 bin·kit cmp0 $f" || bad "짝 사본 다름 $f"; done
bash -n "$SRC/ft-merge-lib.sh" && /bin/bash -n "$SRC/ft-merge-lib.sh" && ok "bash -n(/bin/bash 3.2 포함)" || bad "bash -n"
step "사례 ①~⑦"
run "①② 문서 착지 = doc_only · 끝 · 쪽지 0" c1; run "③ 구현 파일 섞임 = 지금 그대로" c3; run "④ 카드 쥔 나노 = 차례 그대로" c4
run "⑤ cards:[] 문서 착지 = 끝" c5; run "⑥ M 빈 값 = doc_err · WARN · 주인 없음" c6; run "⑦ ff·squash 같은 판정" c7
step "변이 M1~M5 (bin 전체 사본 · 그 자리만 · 원본 대조)"
fullbin() {  # fullbin <이름> <파일> <옛 글> <새 글> → MB
  MB="$T/full-$1"; rm -rf "$MB"; cp -R "$SRC" "$MB"; rm -rf "$MB/__pycache__"
  python3 - "$MB/$2" "$3" "$4" <<'PY'
import sys
p, old, new = sys.argv[1:4]; s = open(p, encoding="utf-8").read()
assert s.count(old) == 1, f"변이 자리 {s.count(old)}곳: {old[:60]}"
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}
mut() { if fullbin "$@"; then return 0; fi; bad "$1 변이 자리 못 찾음"; return 1; }
mut m1 ft-merge-lib.sh 'a[7] and d.update(doc_only=True);' '' && mutcase M1 c1 1
mut m2 ft-merge-lib.sh "! grep -qvE '^(design|docs)/'" "grep -qE '^(design|docs)/'" && mutcase M2 c3 2
mut m3 ft_nano_record_due.py 'if e.get("doc_only") and not any(k == "닫기" for _s, k, _c in own):' 'if e.get("doc_only"):' && mutcase M3 c4 3
mut m4 ft_nano_record_due.py '{**base, "k": "끝", "why": DOCW} if e.get("doc_only") else ' '' && mutcase M4 c5 4
mut m5 ft-merge-lib.sh 'dk="M·Q 빈 값"' 'dn="docs/x"' && mutcase M5 c6 5
step "기준판 ①②⑤ (팩 4b7c9eb8 = 착지 전 origin/main · Red 기대)"
BASE="$T/base"; mkdir -p "$BASE"
if git -C "$H" archive 4b7c9eb8820a34b846ab10b8941e6119caeb47e6 -- bin 2>/dev/null | tar -x -C "$BASE" 2>/dev/null && [ -f "$BASE/bin/ft-merge-lib.sh" ]; then
  for c in c1 c5; do
    if o="$(BIN="$BASE/bin"; TOOL="$BASE/bin/ft-nano-record.sh"; "$c" 6 2>&1)"; then bad "기준판에서 $c 통과함"; else ok "기준판 $c FAIL(기대) ::$(printf '%s\n' "$o" | grep '^  x ' | sed 's/ :: .*//' | tr -d '\n')"; fi
  done
else bad "기준판 꺼내기 실패 — 팩 리포 밖이거나 얕은 사본"; fi
finish
