#!/usr/bin/env bash
# test_nano_record_land_r1717.sh — r1717 착지 꼬리 사례: ① 장부 1줄 + 나노 «[정리 차례]» 1통 · ② 장부 쓰기 실패 = WARN · 착지 rc 불변 · ⑧ mbox 실패 = 착지 rc 불변 · 보낸 기록 0
#   ⑨ 꼬리 남은 시간 0 → 발신 0 · 장부는 남음 → 점검(ft_stall_scan record_notify)이 보냄 · ⑩ 발주문 문장 · 변이 M1(장부 append 삭제 → ① FAIL · 원본 대조) · 기준판 ①(팩 103be13029 = 나노 쪽지 0)
#   ①②⑧ = «실» ft-merge-land.sh(임시 bare origin + clone · 가짜 gh·mbox·tmux — test_landing_note_r1478.sh 꼴) · 실 gh·실 원격·실 쪽지·실 명부 0 · sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # 실 상태 지문 + git 밖 cwd + HIL_DIR 격리(approve-merge 번호표)
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_nano_record_r1717_fixture.sh"; . "$HERE/_merge_fixture.sh"
NN() { printf 'byz-harness-nano-r88%s#0' "$1"; }
ML="$T/ml"; mkdir -p "$ML/state"; mkrepo "$ML"; LEDGER="$W/.fable-team/state/land-record-turn.jsonl"; PRS="1 2 3 4 51 52 6"
export FT_AUTONOMY_STATE_DIR="$ML/state" FT_GH="$ML/gh-stub" FT_GH_WRITE="$ML/gh-stub" STUB_LOG="$ML/gh.log" STUB_JSON="$ML/pr.json" FT_MERGE_DENY_FILE="$ML/deny.txt"
export FT_ROOT="$W" MBOX_DIR="$W/.fable-team/comm"; unset FT_SEAT MBOX_FAIL
printf '# 시험 목록(빈)\n' > "$ML/deny.txt"
cat > "$ML/gh-stub" <<'EOF'
#!/bin/bash
[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }
case "$1" in pr-comment|pr-close) ;; *) echo "BADVERB $*" >> "$STUB_LOG"; exit 2;; esac
echo "$*" >> "$STUB_LOG"
EOF
chmod +x "$ML/gh-stub"
put() { mkdir -p "$(dirname "$W/$1")"; printf '%b\n' "$2" > "$W/$1"; }
put "design/TEAMS.md" '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |'
for p in $PRS; do put "design/harness/indices/진행/r88$p-card.md" "# 인덱스: r88$p-card\n\n## 상태\n- 대기"; done
cm "$W" "base cards"; g "$W" push -q origin main; g "$W" fetch -q origin; printf '.fable-team/\n' >> "$W/.git/info/exclude"
mkdir -p "$W/.fable-team/state" "$MBOX_DIR/bodies"; echo 100 > "$MBOX_DIR/.mbox-seq"; : > "$MBOX_LOG"; : > "$FAKE_SESS"
python3 - "$W/.fable-team/seats-harness.json" "$MASTER" $PRS <<'PY'
import json, sys
d = {"_master": sys.argv[2], "_cards": "design/harness/indices"}
for p in sys.argv[3:]:
    d[f"byz-harness-nano-r88{p}#0"] = {"role": "nano", "agent": "pi", "index": f"design/harness/indices/진행/r88{p}-card.md"}
json.dump(d, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
PY
for p in $PRS; do NN "$p" >> "$FAKE_SESS"; echo >> "$FAKE_SESS"; done
mkpr() {  # mkpr <PR번호> — 제목·본문에 카드 토큰 r88<PR>
  g "$W" fetch -q origin; g "$W" checkout -q -B "doc$1" origin/main; put "design/x/t$1.md" "T$1"; cm "$W" "pr $1"
  g "$W" push -q -f origin "doc$1:refs/pull/$1/head"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"headRefName":sys.argv[2],"title":sys.argv[3],"body":sys.argv[4],"state":"OPEN","baseRefName":"main"},ensure_ascii=False))' \
    "$PRSHA" "doc$1" "docs: r88$1 카드" "본문 r88$1" > "$STUB_JSON"
}
mland() { mkpr "$1"; apv --approve-sha "$PRSHA"; : > "$STUB_LOG"; : > "$MBOX_LOG"; rm -f "$LEDGER" "$W/.fable-team/state/land-record-notified.json"
  OUT="$(bash "$BIN/ft-merge-land.sh" "$1" --approve-sha "$PRSHA" --repo "$W" 2>&1)"; RC=$?; }
prof() { case "$1" in m*) echo "${1#m}1";; o*) echo "${1#o}2";; *) echo "$1";; esac; }   # 변이 대조 꼬리표(m5·o5) → PR 번호(51·52)
fullbin() {  # fullbin <이름> <파일> <옛 글> <새 글> → MB = bin 전체 사본(그 자리만 바꿈 · ft-merge-land 가 같은 폴더 lib 을 읽는다)
  MB="$T/full-$1"; rm -rf "$MB"; cp -R "$SRC" "$MB"; rm -rf "$MB/__pycache__"
  python3 - "$MB/$2" "$3" "$4" <<'PY'
import sys
p, old, new = sys.argv[1:4]; s = open(p, encoding="utf-8").read()
assert s.count(old) == 1, f"변이 자리 {s.count(old)}곳"
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}

step "사전: 문법 · 짝 사본 · 늘린 줄 수"
for f in ft-merge-lib.sh ft-nano-spawn.sh ft_stall_scan.py ft-nano-record.sh; do cmp -s "$SRC/$f" "$KIT/$f" && ok "짝 사본 bin·kit cmp0 $f" || bad "짝 사본 다름 $f"; done
bash -n "$SRC/ft-merge-lib.sh" && /bin/bash -n "$SRC/ft-merge-lib.sh" && bash -n "$SRC/ft-nano-spawn.sh" && /bin/bash -n "$SRC/ft-nano-spawn.sh" && ok "bash -n(/bin/bash 3.2 포함)" || bad "bash -n"

c1() {  # ① 착지 1건 · 카드 1장 · 현역 나노
  local p n; p="$(prof "$1")"; n="$(NN "$p")"; E=0; mland "$p"
  t "① 착지 rc0 · LANDED" [ "$RC" = 0 ]; t "① LANDED 줄" inc "$OUT" "LANDED pr=$p sha="
  t "① 장부 1줄(pr·카드·40hex 둘)" [ "$(grep -c "\"pr\": $p, .*\"landed\": \"[0-9a-f]\{40\}\", \"pr_head\": \"$PRSHA\".*r88$p-card.md\"\]" "$LEDGER" 2>/dev/null)" = 1 ]
  t "① 나노 우편함 «[정리 차례]» 1통" [ "$(nto "$n" "\[정리 차례\] r88$p-card 착지 ")" = 1 ]
  t "① 본문에 landed 명령 1줄" [ "$(nto "$n" "ft-nano-record.sh landed --seat $n --pr $p --card r88$p-card ")" = 1 ]
  t "① 착지 쪽지([착지] → 팀장)는 그대로 1통" [ "$(nto "$MASTER" "\[착지\] pr=$p ")" = 1 ]; return $E
}
c2() {  # ② 장부 쓰기 실패(쓰기 자리 오류 주입) → WARN 1줄 · rc·LANDED 줄 그대로
  E=0; fullbin w2 ft-merge-lib.sh '${cd[@]+"${cd[@]}"} >>"$f"; }' '${cd[@]+"${cd[@]}"} >>"/dev/null/x"; }'; BIN="$MB"; mland 2
  t "② 착지 rc 불변" [ "$RC" = 0 ]; t "② WARN 1줄" [ "$(printf '%s\n' "$OUT" | grep -c '^WARN 착지 차례 장부 쓰기 실패')" = 1 ]
  t "② LANDED 줄 꼴 그대로" [ "$(printf '%s\n' "$OUT" | grep -cE "^LANDED pr=2 sha=[0-9a-f]{40} main_before=[0-9a-f]{40} head=$PRSHA tree=[0-9a-f]{40}$")" = 1 ]
  t "② 장부 0" [ ! -s "$LEDGER" ]; return $E
}
c8() {  # ⑧ mbox 실패 → WARN · 보낸 기록 0 · 착지 rc 불변 → 다음 notify 가 보냄
  local n; n="$(NN 3)"; E=0; MBOX_FAIL=5 mland 3
  t "⑧ 착지 rc 불변 · LANDED" [ "$RC" = 0 ]; t "⑧ LANDED 줄" inc "$OUT" "LANDED pr=3 sha="; t "⑧ WARN 줄(정리 차례 쪽지)" inc "$OUT" "WARN 쪽지 발신 실패 → $n"
  t "⑧ 장부는 남음" [ "$(grep -c . "$LEDGER")" = 1 ]; t "⑧ 보낸 기록 0" [ ! -s "$W/.fable-team/state/land-record-notified.json" ]
  rec notify --pr 3 --no-fetch; t "⑧ 다음 호출이 다시 보냄" [ "$(nto "$n" "\[정리 차례\] r883-card ")" = 1 ]; return $E
}
c9() {  # ⑨ 꼬리에 남은 시간 0(시작 시각을 7초 앞으로 주입) → 발신 0 · 장부 1줄 → 점검 사본의 notify 가 1통
  local n q; n="$(NN 4)"; q="$(sha "$ORIGIN" refs/heads/main)"; E=0; : > "$MBOX_LOG"; rm -f "$LEDGER" "$W/.fable-team/state/land-record-notified.json"
  OUT="$(set +u; . "$BIN/ft-merge-lib.sh"; REPO="$W"; TARGET=main; Q="$q"; HEADSHA="$M0"; fm_land_turn "$W" 4 "$((SECONDS - 7))" r884 2>&1)"
  t "⑨ 장부 1줄은 남음" [ "$(grep -c '"pr": 4, ' "$LEDGER" 2>/dev/null)" = 1 ]; t "⑨ 꼬리 발신 0" [ "$(nsent .)" = 0 ]
  scan notify "$BIN" "$W"; t "⑨ 점검(stall-scan 사본) notify 가 1통" [ "$(nto "$n" "\[정리 차례\] r884-card ")" = 1 ]; t "⑨ 점검 로그 줄 0(rc 0)" [ -z "$OUT" ]
  scan notify "$BIN" "$W"; t "⑨ 한 번 더 = 0통" [ "$(nsent .)" = 1 ]; return $E
}
c10() {  # ⑩ 발주문에 «[정리 차례]» 문장 정확히 1회(추적본·키트 · spawn --dry-run 은 BODY 를 내지 않아 정의 줄·BODY 줄을 읽는다 — test_nano_spawn_body_press.sh 꼴)
  local f d r; E=0
  for f in "$SRC/ft-nano-spawn.sh" "$KIT/ft-nano-spawn.sh"; do
    t "⑩ _RTX 정의 1개" [ "$(grep -c '^_RTX="' "$f")" = 1 ]; d="$(grep '^_RTX="' "$f")"
    t "⑩ 문장 1" inc "$d" "[정리 차례] 쪽지를 받으면 그 쪽지의 명령 1줄을 그대로 실행한다 — 카드 파일을 손으로 고치지 않는다"
    t "⑩ «[정리 차례]» 정확히 1회" [ "$(printf '%s\n' "$d" | grep -o '\[정리 차례\]' | grep -c .)" = 1 ]
    t "⑩ 문장 2(done)" inc "$d" "1줄을 실행한다 — 카드 증거 줄을 손으로 쓰지 않는다"
    t "⑩ BODY+ echo 1개" [ "$(grep -c '^echo "BODY+${_RTX}"$' "$f")" = 1 ]; t "⑩ BODY= 에 1회" [ "$(grep '^BODY=' "$f" | grep -o '${_RTX}' | grep -c .)" = 1 ]
    r="$(ROOT=/r HERE=/h NAME=byz-harness-nano-x#0 IDX=/c/진행/r1-x.md; eval "$d"; printf '%s' "$_RTX")"
    t "⑩ 펼친 done 명령" inc "$r" 'FT_ROOT=/r bash /h/ft-nano-record.sh done --seat byz-harness-nano-x#0 --card r1-x --did "<한 일 1줄>" --test "<돌린 시험 명령> rc=0"'
  done; return $E
}
step "사례 ①②⑧⑨⑩"; run "① 착지 → 장부 1줄 + 나노 쪽지 1통" c1 1; run "② 장부 쓰기 실패 = WARN · rc 불변" c2; run "⑧ mbox 실패 = 착지 rc 불변" c8; run "⑨ 꼬리 시간 0 → 점검이 보냄" c9; run "⑩ 발주문 문장" c10
step "변이 M1 (장부 append 삭제 → ① FAIL · 원본 대조)"
fullbin m1 ft-merge-lib.sh '${cd[@]+"${cd[@]}"} >>"$f"; }' '${cd[@]+"${cd[@]}"} >/dev/null; }'; mutcase M1 c1 5
step "기준판 ① (팩 103be13029fc16eb35fb0a305defcbad6c46ce10 — 나노 쪽지 0)"
BASE="$T/base"; mkdir -p "$BASE"
if git -C "$H" archive 103be13029fc16eb35fb0a305defcbad6c46ce10 -- bin 2>/dev/null | tar -x -C "$BASE" 2>/dev/null && [ -f "$BASE/bin/ft-merge-land.sh" ]; then
  if o="$(BIN="$BASE/bin"; c1 6)"; then bad "기준판에서 ① 이 통과함"; else ok "기준판 ① FAIL(기대)"; inc "$o" "나노 우편함 «[정리 차례]» 1통" && ok "기준판 ① 사유 = 나노 쪽지 0" || bad "기준판 ① 사유가 다름" "$o"; fi
else bad "기준판 꺼내기 실패 — 팩 리포 밖이거나 얕은 사본"; fi
finish
