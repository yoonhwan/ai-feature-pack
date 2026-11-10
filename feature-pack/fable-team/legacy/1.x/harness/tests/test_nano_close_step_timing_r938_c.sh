#!/usr/bin/env bash
# test_nano_close_step_timing_r938_c.sh — r938 단계 시각 줄 시험의 «검사 상한·배수(ⓒ · ⓓ · ⓘ · ⓚ)» 조각(r1318 나눔 · 원본 = test_nano_close_step_timing_r938.sh 1개).
#   왜 나눴나: r1316 뒤 이 시험이 끝까지 돌며 rc124(70초 초과 · 하드 룰 22) — 단언·변이 집합은 나누기 전과 같다(빼지 않고 옮기기만).
#   공통 준비(임시 리포·가짜 tmux·대역·도우미) = lib/r938_step_timing_fixture.sh · 끝에 finish 로 ALL PASS/FAILED.
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/lib/r938_step_timing_fixture.sh"

echo "== ⓒ 검사 대역 90초 → 상한 뒤 REJECT(걸린/상한 초·배수·다시 하는 길) · 명부·원장·세션 변경 0"
setup; slow evidence-check
_now="$(date +%s)"; out="$(close)"; rc=$?; took="$(elapsed "$_now")"
[ "$rc" -eq 1 ] && has "$out" "⑥증거 검사 시간 초과" "$(card ⓒ '⑥ 증거 검사 상한 → REJECT')" || bad "ⓒ⑥ rc=$rc ← ${out:0:900}"
has "$out" "· 배수 1 — 다시: 같은 명령" "$(card ⓒ '  └ 배수·다시 하는 길 1줄')"
has "$out" "arch 에 증거 검사" "$(card ⓒ '  └ 계속이면 arch 보고 안내')"
[ "$took" -le 25 ] && ok "$(card ⓒ '  └ 총 소요 ≤ 25초(상한 8초 · 멈춤 0)')" || bad "총 소요 ${took}s"
hasnt "$out" "CLOSED" "$(card ⓒ '  └ CLOSED 0')"; untouched ⓒ⑥
setup; FEAT=feat/x slow cherry-gate
_now="$(date +%s)"; out="$(close)"; rc=$?; took="$(elapsed "$_now")"
[ "$rc" -eq 1 ] && has "$out" "⑤cherry 게이트 시간 초과" "$(card ⓒ '⑤ cherry 상한 → REJECT')" || bad "ⓒ⑤ rc=$rc ← ${out:0:900}"
case "$(steps_of "$(cat "$T/err")")" in *freshness*) bad "상한 초과인데 freshness 단계가 돎";; *) ok "$(card ⓒ '  └ 상한 초과 → freshness 단계 0')";; esac
[ "$took" -le 25 ] && ok "$(card ⓒ '  └ 총 소요 ≤ 25초')" || bad "총 소요 ${took}s"
hasnt "$out" "CLOSED" "$(card ⓒ '  └ CLOSED 0')"; untouched ⓒ⑤
setup; FEAT=feat/x; instant cherry-gate 1; slow freshness
_now="$(date +%s)"; out="$(close)"; rc=$?; took="$(elapsed "$_now")"
[ "$rc" -eq 1 ] && has "$out" "⑤-생애 freshness 시간 초과" "$(card ⓒ 'freshness 상한 → REJECT')" || bad "ⓒfr rc=$rc ← ${out:0:900}"
[ "$took" -le 35 ] && ok "$(card ⓒ '  └ 총 소요 ≤ 35초')" || bad "총 소요 ${took}s"
hasnt "$out" "CLOSED" "$(card ⓒ '  └ CLOSED 0')"; untouched ⓒfr


echo "== ⓓ 정상 대역(모두 즉시) → 지금과 같은 결과(닫힘)"
setup; instant cherry-gate 0
out="$(FEAT=feat/x close)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED " "$(card ⓓ '즉시 대역 → CLOSED')" || bad "ⓓ rc=$rc ← ${out:0:900}"
has "$out" "SLOTS" "$(card ⓓ '  └ 마지막 slots 단계까지 감')"; hasnt "$out" "시간 초과" "$(card ⓓ '  └ 시간 초과 0')"
has "$(cat "$LEDGER")" "닫힘(ft-nano-close)" "$(card ⓓ '  └ 원장 닫힘 행 1줄')"
has "$(cat "$T/tlog")" "kill-session" "$(card ⓓ '  └ 세션 kill')"


echo "== ⓘ 배수 = 커밋 수 — 커밋 12 · 커밋당 1초 대역은 «정상 느림» 이라 통과(거짓 거절 0)"
setup
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do echo "$i" > "$NW/c$i.txt"; git -C "$NW" add "c$i.txt"; git -C "$NW" commit -q -m "c$i"; done
HEAD12="$(git -C "$NW" rev-parse HEAD)"
printf '# 인덱스: ns\n## 상태\n- 세트: %s · 시험: bash tests/x.sh (1 passing) rc=0 · 이슈: 0\n' "$HEAD12" > "$CARD"
git -C "$REPO" add -A >/dev/null 2>&1; git -C "$REPO" -c user.email=t@t -c user.name=t commit -q -m card12 >/dev/null 2>&1 || true
cat > "$T/bin/ft-nano-cherry-gate.sh" <<'EOF'
#!/bin/sh
n=$(git -C "$REPO_DIR" rev-list --count "feat/x..nano/ns" 2>/dev/null || echo 0)
echo "CALL cherry-gate commits=$n" >> "$CALLS"
sleep "$n"
echo "OK cherry 게이트 대역 commits=$n"
exit 0
EOF
chmod +x "$T/bin/ft-nano-cherry-gate.sh"
_now="$(date +%s)"; out="$(FEAT=feat/x close)"; rc=$?; took="$(elapsed "$_now")"
[ "$rc" -eq 0 ] && has "$out" "commits=12" "$(card ⓘ '커밋 12 · 커밋당 1초 → 배수 12 상한 안 → 통과(rc0)')" || bad "$(card ⓘ "rc=$rc ← ${out:0:600}")"
[ "$took" -ge 10 ] && ok "$(card ⓘ "  └ 대역이 실제로 ${took}초 걸렸다(느림 재현)")" || bad "$(card ⓘ "  └ 대역이 ${took}s — 느림 재현 실패")"


echo "== ⓚ 상한식 = min(고정비 + 7×배수, 70) · 600/300초 0 · 무상한 fetch 0"
CA="$(bash -c 'nf_cap(){ f="${1:-1}"; m="${2:-1}"; awk -v f="$f" -v m="$m" "BEGIN{t=f+7*m; if(t>70)t=70; if(t<7)t=7; printf \"%d\\n\", t}"; }; nf_cap 1 1; nf_cap 1 2; nf_cap 2 12; nf_cap 1 20')"
[ "$CA" = "$(printf '8\n15\n70\n70')" ] && ok "$(card ⓚ '배수 1→8 · 2→15 · 12→70(상한)')" || bad "nf_cap 값: $(printf '%s' "$CA" | tr '\n' ' ')"
NEWL="$(grep -nE 'r938|nf_cap|nf_bound|nf_fetch|nf_again|nf_fixed|nf_mult|step ' "$SRC/ft-nano-close.sh")"
hasnt "$(printf '%s\n' "$NEWL" | grep -E '(^|[^0-9])(600|300)([^0-9]|$)')" ":" "$(card ⓚ '600/300 숫자 0')"
hasnt "$(printf '%s\n' "$NEWL" | grep -E 'curl|wget|https?://|nc ')" ":" "$(card ⓚ '외부 호출 0')"
[ "$(grep -c 'fetch -q' "$SRC/ft-nano-close.sh")" = "0" ] && ok "$(card ⓚ '무상한 git fetch 0(전부 nf_fetch 경유)')" || bad "fetch -q 잔존 $(grep -c 'fetch -q' "$SRC/ft-nano-close.sh")줄"
awk '/ft-sheet-events.sh" key/{k=NR} /^trap .*abort/{a=NR} /^nf_bound .*ft-sheet-events.sh" prepare/{p=NR} END{exit !(a>k && a<p)}' "$SRC/ft-nano-close.sh" \
  && ok "$(card ⓚ 'abort trap 이 prepare 전에 등록(N1)')" || bad "trap 위치가 prepare 뒤"


finish
