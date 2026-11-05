#!/usr/bin/env bash
# test_nano_close_step_timing_r938_b.sh — r938 단계 시각 줄 시험의 «fetch 상한·실패 경로(ⓑ · ⓙ · ⓛ)» 조각(r1318 나눔 · 원본 = test_nano_close_step_timing_r938.sh 1개).
#   왜 나눴나: r1316 뒤 이 시험이 끝까지 돌며 rc124(70초 초과 · 하드 룰 22) — 단언·변이 집합은 나누기 전과 같다(빼지 않고 옮기기만).
#   공통 준비(임시 리포·가짜 tmux·대역·도우미) = lib/r938_step_timing_fixture.sh · 끝에 finish 로 ALL PASS/FAILED.
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/lib/r938_step_timing_fixture.sh"

echo "== ⓑ fetch 대역 30초 → 상한 8초(지정) + 재시도 1 뒤 «origin/main fetch 실패» · 옛 ref 대조 0 · 총 ≤ 20초"
setup; FEAT=feat/x instant cherry-gate 1   # 게이트 REJECT → origin/main 재대조 = fetch 경로
_now="$(date +%s)"; out="$(FEAT=feat/x FT_CARD_REF=main SLEEP_FETCH=30 FT_FETCH_TIMEOUT_SEC=8 close)"; rc=$?; took="$(elapsed "$_now")"
[ "$rc" -eq 1 ] && has "$out" "origin/main fetch 실패" "$(card ⓑ 'REJECT + «origin/main fetch 실패»')" || bad "ⓑ rc=$rc ← ${out:0:900}"
has "$out" "옛 ref 대조 0" "$(card ⓑ '  └ 옛 ref 대조 0 문구')"
hasnt "$out" "origin/main 기준:" "$(card ⓑ '  └ 두 번째 게이트 호출 0(옛 ref 대조 0)')"
[ "$(grep -c 'CALL cherry-gate' "$V")" = "1" ] && ok "$(card ⓑ '  └ 게이트 대역 1회만')" || bad "게이트 호출 $(grep -c 'CALL cherry-gate' "$V")회"
[ "$took" -le 24 ] && ok "$(card ⓑ '  └ 총 소요 ≤ 24초(상한 8초 + 재시도 1 + 여유 · 기본 25초 값은 r1363 시험 D4 가 잰다)')" || bad "총 소요 ${took}s > 24초"
hasnt "$out" "CLOSED" "$(card ⓑ '  └ CLOSED 0')"; untouched ⓑ


echo "== ⓙ 원격 없음 + 캐시 origin/main → fetch 실패 REJECT · cherry 통과 줄 0(DA⑥ r1 반례 3)"
setup; FEAT=origin/main
git -C "$REPO" remote remove origin; git -C "$REPO" update-ref refs/remotes/origin/main "$BASE"   # 원격 없음 + 캐시 ref 남음
out="$(FEAT=origin/main close)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "origin/main fetch 실패" "$(card ⓙ 'fetch 실패 → 그 자리 REJECT')" || bad "ⓙ rc=$rc ← ${out:0:700}"
hasnt "$out" "전부 origin/main 에 있" "$(card ⓙ '  └ cherry 통과 줄 0')"
has "$out" "옛 ref 대조 0" "$(card ⓙ '  └ 옛 ref 대조 0 문구')"
git -C "$REPO" remote add origin "$T/origin.git"
untouched ⓙ
# ⓙ2(r3 · astra r2 반례 N4): --research · 원격 없음 + 캐시 origin/main · FT_NANO_FEAT=main → 리서치 fetch 실패 = 그 자리 REJECT(병합 대조 0)
#   리서치 «미커밋 0» 을 맞추려고 대역 .worktree-info.json 을 제외 목록에 둔다(아래 대조군 뒤 원복) — 거절 사유가 fetch 하나뿐이게
EXCL="$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)/info/exclude"; mkdir -p "$(dirname "$EXCL")"; cp "$EXCL" "$T/exclude.bak" 2>/dev/null || : > "$T/exclude.bak"
echo ".worktree-info.json" >> "$EXCL"
setup
git -C "$REPO" remote remove origin; git -C "$REPO" update-ref refs/remotes/origin/main "$BASE"
out="$(FEAT=main close --research)"; rc=$?
[ "$rc" -eq 1 ] && ok "$(card ⓙ '--research fetch 실패 → rc1')" || bad "$(card ⓙ "--research rc=$rc ← ${out:0:700}")"
[ "$(printf '%s\n' "$out" | grep -c '⑥리서치 origin/main fetch 실패')" = "1" ] && ok "$(card ⓙ '  └ «⑥리서치 origin/main fetch 실패» 1줄')" || bad "$(card ⓙ "  └ 리서치 fetch 실패 줄 $(printf '%s\n' "$out" | grep -c '⑥리서치 origin/main fetch 실패')개")"
hasnt "$out" "RESEARCH-OK" "$(card ⓙ '  └ 리서치 통과 줄 0(옛 ref 병합 대조 0)')"
hasnt "$out" "CLOSED" "$(card ⓙ '  └ CLOSED 0')"
evi j-research-fetch-fail "$out"
git -C "$REPO" remote add origin "$T/origin.git"
untouched ⓙ
setup; out="$(FEAT=main close --research)"; rc=$?   # 대조군: 원격 있음 → 같은 인자 꼴이 리서치 통과(거절 사유가 fetch 하나뿐임을 보인다)
evi j-research-control "$out"
[ "$rc" -eq 0 ] && has "$out" "RESEARCH-OK" "$(card ⓙ '  └ 대조군: 원격 있음 → RESEARCH-OK · rc0')" || bad "$(card ⓙ "  └ 대조군 rc=$rc ← ${out:0:700}")"
cp "$T/exclude.bak" "$EXCL"


echo "== ⓛ 첫 cherry 즉시 REJECT · fetch 성공 · 둘째 cherry(origin/main) 6초 · 상한 1초 → 그 자리 REJECT · freshness 0(astra r2 반례 N3)"
setup
cat > "$T/bin/ft-nano-cherry-gate.sh" <<'EOF'
#!/bin/sh
echo "CALL cherry-gate $1" >> "$CALLS"
case "$1" in origin/main) sleep 6; echo "OK 늦은 통과"; exit 0;; esac
echo "REJECT cherry 게이트 대역($1)"; exit 1
EOF
chmod +x "$T/bin/ft-nano-cherry-gate.sh"
out="$(FEAT=feat/x FT_NANO_CAP_S=1 close)"; rc=$?
[ "$rc" -eq 1 ] && ok "$(card ⓛ 'rc1')" || bad "$(card ⓛ "rc=$rc ← ${out:0:700}")"
[ "$(grep -c 'CALL cherry-gate origin/main' "$V")" = "1" ] && ok "$(card ⓛ '  └ 둘째 cherry(origin/main) 호출 1회(fetch 성공 경로)')" || bad "$(card ⓛ "  └ 둘째 cherry 호출 $(grep -c 'CALL cherry-gate origin/main' "$V")회")"
[ "$(printf '%s\n' "$out" | grep -cE 'cherry 게이트\(origin/main\) 시간 초과 [0-9]+s/1s · 배수 [0-9]+ — 다시:')" = "1" ] && ok "$(card ⓛ '  └ «cherry 게이트(origin/main) 시간 초과 <초>s/<상한>s · 배수 <n> — 다시:» 1줄')" || bad "$(card ⓛ "  └ 둘째 cherry 상한 줄 없음 ← ${out:0:700}")"
hasnt "$out" "origin/main 기준: " "$(card ⓛ '  └ 빈 «origin/main 기준:» 줄 0')"
case "$(steps_of "$(cat "$T/err")")" in *freshness*) bad "$(card ⓛ '  └ 상한 초과인데 freshness STEP 줄 있음')";; *) ok "$(card ⓛ '  └ freshness STEP 줄 0')";; esac
hasnt "$out" "CLOSED" "$(card ⓛ '  └ CLOSED 0')"; untouched ⓛ

echo

finish
