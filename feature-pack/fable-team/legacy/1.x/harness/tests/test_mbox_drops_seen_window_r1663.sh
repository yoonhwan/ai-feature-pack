#!/usr/bin/env bash
# test_mbox_drops_seen_window_r1663.sh — r1663: 표식 없는 첫 recv 의 «시작점(24h 창)»·«한 줄 상한(최근 10개·200자)»·«계보 이어받기».
# 사례 1 ⓐ 창(25h 전 3줄 + 1h 전 2줄 → 최근 2줄만 · 표식 = 원장 끝) · 2 ⓑ 상한(30개 → 최근 10개 + (앞 20개 생략) · ≤200자)
# 사례 3 ⓒ 계보(recv 가 넘긴 옛 이름의 표식 값을 이어받아 그 «뒤» 오래된 줄도 보인다) · 4 ⓓ 표식 있음 + 새 줄 0 = 0줄 · 5 ⓔ r1651 rc0
# 사례 6 반례(DA B): 같은 줄기 «동시 현역» 두 좌석은 서로 표식을 잇지 않는다 · 변이 M1 창·M2 상한·M3 이어받기·M4 계보 밖 표식 삭제/추가
# 정본 .py 사본 + 손으로 쓴 mailbox.drops.log 만 — 실 우편함·실 doorbell 쓰기 0(측정 조작 금지).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; SRC="$HERE/../comm"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
ME="byz-x-master-pi#0"; KEY="byz-x-master-pi"; OLD="byz-x-master-claude#0"; SIB="byz-x-da-astra#0"
NOWE="$(python3 -c 'import time;print(int(time.mktime(time.strptime("2026-11-11T12:00:00","%Y-%m-%dT%H:%M:%S"))))')"
ts() { python3 -c "import time;print(time.strftime('%Y-%m-%dT%H:%M:%S',time.localtime($NOWE-($1))))"; }
OLD_TS="$(ts $((25*3600)))"; NEW_TS="$(ts 3600)"
new_env() {   # 격리 우편함 1개 · 빈 원장 · mbox*.py 사본 · 표식 없음
  C="$(mktemp -d "$T/c.XXXXXX")"; cp "$SRC"/mbox*.py "$C/"; : > "$C/mailbox.drops.log"
  if [ -n "${MUT:-}" ]; then "$MUT"; fi
}
line() { printf '%s to=%s dropped=1 oldest_seq=%s seqs=%s\n' "$1" "$2" "$3" "$3" >> "$C/mailbox.drops.log"; }
report() { local me="$1"; shift; FT_MBOX_NOW="$NOWE" python3 -c 'import sys; sys.path.insert(0,sys.argv[1]); import mbox_drops; print(mbox_drops.report(sys.argv[1], sys.argv[2], sys.argv[3:]))' "$C" "$me" "$@"; }
mark() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2],""))' "$C/mailbox.drops.seen.json" "$1" 2>/dev/null; }
mark_set() { python3 -c 'import json,sys;json.dump({sys.argv[1]:int(sys.argv[2])},open(sys.argv[3],"w"))' "$1" "$2" "$C/mailbox.drops.seen.json"; }
nl() { wc -l < "$C/mailbox.drops.log" | tr -d ' '; }
mut_m1() { sed -i '' 's/^    cut = None if last else _now() - SEEN_WINDOW.*$/    cut = None/' "$C/mbox_drops.py"; grep -q '^    cut = None$' "$C/mbox_drops.py"; }
mut_m2() { sed -i '' 's/^    show, omitted = seqs\[-SEEN_MAX:\].*$/    show, omitted = seqs, 0/' "$C/mbox_drops.py"; grep -q '^    show, omitted = seqs, 0$' "$C/mbox_drops.py"; }
mut_m3() { sed -i '' 's/^    return max(olds) if olds else 0$/    return 0/' "$C/mbox_drops.py"; grep -q '^    return 0$' "$C/mbox_drops.py"; }
mut_m4() { sed -i '' 's/^    olds = \[_num(seen.get(role_key(n))) for n in names if role_key(n) != key\]$/    olds = [_num(v) for v in seen.values()]/' "$C/mbox_drops.py"; grep -q '^    olds = \[_num(v) for v in seen.values()\]$' "$C/mbox_drops.py"; }
case1() {   # ⓐ 창 — 25시간 전 3줄은 안 보이고 1시간 전 2줄만 · 표식 = 원장 끝
  new_env; line "$OLD_TS" "$ME" 9001; line "$OLD_TS" "$ME" 9002; line "$OLD_TS" "$ME" 9003
  line "$NEW_TS" "$ME" 9101; line "$NEW_TS" "$ME" 9102
  local out; out="$(report "$ME" "$ME")"
  if [ "$out" = "DROPPED-SEEN 2 #9101,#9102 — 전문 = mailbox.log.jsonl" ] && [ "$(mark "$KEY")" = "$(nl)" ]; then
    ok "ⓐ 창 24h — 최근 2줄만($out) · 표식=$(mark "$KEY")=원장 끝"; return 0
  fi
  bad "ⓐ out=[$out] mark=$(mark "$KEY") lines=$(nl)"; return 1
}
case2() {   # ⓑ 상한 — 30개 → 최근 10개 + 앞 20개 생략 · 200자 이내
  new_env; local i; for i in $(seq 1 30); do line "$NEW_TS" "$ME" "s$i"; done
  local out exp; out="$(report "$ME" "$ME")"
  exp="DROPPED-SEEN 30 최근 #s21,#s22,#s23,#s24,#s25,#s26,#s27,#s28,#s29,#s30 (앞 20개 생략) — 전문 = mailbox.log.jsonl"
  if [ "$out" = "$exp" ] && [ "${#out}" -le 200 ]; then ok "ⓑ 상한 — 30개 중 최근 10개 + (앞 20개 생략) · ${#out}자"; return 0; fi
  bad "ⓑ out=[$out] len=${#out}"; return 1
}
case3() {   # ⓒ 계보 — recv 가 옛 이름(OLD)을 넘기면 그 표식(3)을 이어받아 «그 뒤» 오래된 2줄을 보인다(창이면 최근 3줄이 나왔을 것)
  new_env; mark_set "byz-x-master-claude" 3
  line "$NEW_TS" "$ME" 9001; line "$NEW_TS" "$ME" 9002; line "$NEW_TS" "$ME" 9003
  line "$OLD_TS" "$ME" 9101; line "$OLD_TS" "$ME" 9102
  local out; out="$(report "$ME" "$ME" "$OLD")"
  if [ "$out" = "DROPPED-SEEN 2 #9101,#9102 — 전문 = mailbox.log.jsonl" ]; then ok "ⓒ 계보 — 옛 이름(…-claude#0) 표식 3 이어받아 그 뒤 2줄만"; return 0; fi
  bad "ⓒ out=[$out] mark=$(mark "$KEY")"; return 1
}
case4() {   # ⓓ 표식 있음 + 새 줄 없음 = 0줄 · 두 번째도 0줄
  new_env; line "$NEW_TS" "$ME" 9101; mark_set "$KEY" "$(nl)"
  local a b; a="$(report "$ME" "$ME")"; b="$(report "$ME" "$ME")"
  if [ -z "$a" ] && [ -z "$b" ]; then ok "ⓓ 표식 있음 + 새 줄 0 = 0줄(두 번)"; return 0; fi
  bad "ⓓ a=[$a] b=[$b]"; return 1
}
case5() {   # ⓔ r1651 회귀
  if bash "$HERE/test_mbox_ring_keep_real_reports_r1651.sh" > "$T/r1651.log" 2>&1; then ok "ⓔ r1651 시험 rc0"; return 0; fi
  bad "ⓔ r1651 rc≠0 — $(tail -3 "$T/r1651.log" | tr '\n' ' ')"; return 1
}
case6() {   # 반례(DA B) — 같은 줄기 동시 현역(da-astra#0)의 표식을 «안 잇는다» = 창 모드(최근 3줄). 이름 안 넘기면 계보 아님.
  new_env; mark_set "byz-x-da-astra" 3
  line "$NEW_TS" "$ME" 9201; line "$NEW_TS" "$ME" 9202; line "$NEW_TS" "$ME" 9203
  line "$OLD_TS" "$ME" 9301; line "$OLD_TS" "$ME" 9302
  local out; out="$(report "$ME" "$ME")"
  if [ "$out" = "DROPPED-SEEN 3 #9201,#9202,#9203 — 전문 = mailbox.log.jsonl" ]; then ok "반례 — 동시 현역 $SIB 표식(3) 안 이어받음 · 창 모드 3줄"; return 0; fi
  bad "반례 out=[$out] (기대 = 최근 3줄 · 표식 이어받으면 9301,9302 만 나온다)"; return 1
}
case1; case2; case3; case4; case5; case6
echo "--- 변이 대조(빨강이어야 정상)"
for m in mut_m1 mut_m2 mut_m3 mut_m4; do
  rc=0
  case "$m" in
    mut_m1) ( MUT=$m; case1 ) >/dev/null 2>&1 || rc=$?;;
    mut_m2) ( MUT=$m; case2 ) >/dev/null 2>&1 || rc=$?;;
    mut_m3) ( MUT=$m; case3 ) >/dev/null 2>&1 || rc=$?;;
    mut_m4) ( MUT=$m; case6 ) >/dev/null 2>&1 || rc=$?;;
  esac
  if [ "$rc" != 0 ]; then echo "RED-OK $m"; else echo "RED-MISS $m"; fail=$((fail+1)); fi
done
echo "결과: fail=$fail"
[ "$fail" = 0 ]
