#!/usr/bin/env bash
# test_nano_close_step_timing_r938_d.sh — r938 단계 시각 줄 시험의 «상한이 묶음째 끝냄·쓰기 0(ⓕ · ⓖ · ⓗ)» 조각(r1318 나눔 · 원본 = test_nano_close_step_timing_r938.sh 1개).
#   왜 나눴나: r1316 뒤 이 시험이 끝까지 돌며 rc124(70초 초과 · 하드 룰 22) — 단언·변이 집합은 나누기 전과 같다(빼지 않고 옮기기만).
#   공통 준비(임시 리포·가짜 tmux·대역·도우미) = lib/r938_step_timing_fixture.sh · 끝에 finish 로 ALL PASS/FAILED.
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/lib/r938_step_timing_fixture.sh"

echo "== ⓕ 상한 REJECT 시 쓰기 0 — .prepared 0 · 명부·원장 바이트 불변(DA⑥ r1 반례 1)"
setup; slow evidence-check
seats_before="$(shasum -a1 "$REPO/.fable-team/seats-planner.json" | cut -d' ' -f1)"; : > "$LEDGER"
out="$(close)"; rc=$?
[ "$rc" -eq 1 ] && ok "$(card ⓕ '상한 REJECT(증거 검사 대역)')" || bad "ⓕ rc=$rc ← ${out:0:400}"
[ ! -e "$PEND" ] || [ -z "$(ls -A "$PEND" 2>/dev/null)" ] && ok "$(card ⓕ '  └ .prepared 0')" || bad "ⓕ .prepared 남음: $(ls -A "$PEND" 2>/dev/null | tr '\n' ' ')"
[ "$(shasum -a1 "$REPO/.fable-team/seats-planner.json" | cut -d' ' -f1)" = "$seats_before" ] && ok "$(card ⓕ '  └ 명부 바이트 불변')" || bad "ⓕ 명부 바뀜"
[ ! -s "$LEDGER" ] && ok "$(card ⓕ '  └ 원장 바이트 불변')" || bad "ⓕ 원장 바뀜"
# ⓕ2 prepare «자체» 가 상한에 잘려도 .prepared 0 — abort trap 이 prepare 전에 등록돼 있어야 한다
setup
cat > "$T/bin/ft-sheet-events.sh" <<'EOF'
#!/bin/sh
p="$FT_SHEET_ROOT/.fable-team/state/sheet-events.pending"
case "$1" in
  key) printf 'k-%s' "$3";;
  prepare) mkdir -p "$p"; : > "$p/$2.prepared"; sleep 60;;
  abort) rm -f "$p/$2.prepared";;
  commit) ;;
esac
EOF
chmod +x "$T/bin/ft-sheet-events.sh"
out="$(FT_NANO_CAP_S=1 close)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "사건 원장 prepared 실패" "$(card ⓕ 'prepare 상한 → REJECT')" || bad "ⓕ2 rc=$rc ← ${out:0:500}"
has "$out" "시간 초과" "$(card ⓕ '  └ «시간 초과» 표기')"
[ -z "$(ls -A "$PEND" 2>/dev/null)" ] && ok "$(card ⓕ '  └ prepare 잘린 뒤 .prepared 0(trap 이 prepare 전)')" || bad "ⓕ2 .prepared 남음: $(ls -A "$PEND" 2>/dev/null | tr '\n' ' ')"
# ⓕ3(r3 · astra r2 반례 N1): 앞 검사가 이미 bad(증거 검사 상한) + --cherry-override → 우회 원장 쓰기 0 · 대조군: bad 0 이면 override 그대로(원장 1행)
codecommit() {   # 코드 «+» 커밋 1개(cherry REJECT 거리) + 카드 증거 줄을 새 HEAD 로
  echo x > "$NW/code.sh"; git -C "$NW" add code.sh; git -C "$NW" commit -q -m code
  printf '# 인덱스: ns\n## 상태\n- 세트: %s · 시험: bash tests/x.sh (1 passing) rc=0 · 이슈: 0\n' "$(git -C "$NW" rev-parse HEAD)" > "$CARD"
  git -C "$REPO" add -A >/dev/null 2>&1; git -C "$REPO" -c user.email=t@t -c user.name=t commit -q -m cardc >/dev/null 2>&1 || true
}
setup; codecommit; slow evidence-check; : > "$T/cherry.log"
out="$(close --cherry-override dummy)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "⑥증거 검사 시간 초과" "$(card ⓕ 'bad(증거 검사 상한) + --cherry-override → REJECT')" || bad "$(card ⓕ "override rc=$rc ← ${out:0:500}")"
[ ! -s "$T/cherry.log" ] && ok "$(card ⓕ '  └ 우회 원장(cherry override) 행 0')" || bad "$(card ⓕ "  └ 우회 원장에 행 생김: $(head -1 "$T/cherry.log")")"
has "$out" "⑤REJECT cherry 게이트" "$(card ⓕ '  └ cherry 는 읽기 전용 판정(REJECT 줄)')"
untouched ⓕ
setup; codecommit; : > "$T/cherry.log"
out="$(close --cherry-override dummy)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(grep -c . "$T/cherry.log")" = "1" ] && ok "$(card ⓕ '  └ 대조군: bad 0 이면 override 전달 · 원장 1행 · CLOSED')" || bad "$(card ⓕ "  └ 대조군 rc=$rc 원장 $(grep -c . "$T/cherry.log")행 ← ${out:0:500}")"


echo "== ⓖ 상한이 프로세스 묶음째 끝냄 — 자식이 분리돼도 REJECT 뒤 자식 쓰기 0"
setup
cat > "$T/bin/ft-nano-evidence-check.sh" <<'EOF'
#!/bin/sh
( sleep 3; echo late > "$REPO_DIR/late-write.txt" ) &      # 분리된 자식 — 상한이 묶음째 끝내야 한다
echo "CALL evidence" >> "$CALLS"
sleep 90
EOF
chmod +x "$T/bin/ft-nano-evidence-check.sh"
rm -f "$REPO/late-write.txt"
out="$(FT_NANO_CAP_S=1 close)"; rc=$?; sleep 3
[ "$rc" -eq 1 ] && has "$out" "⑥증거 검사 시간 초과" "$(card ⓖ '상한 → REJECT')" || bad "$(card ⓖ "rc=$rc ← ${out:0:400}")"
[ ! -e "$REPO/late-write.txt" ] && ok "$(card ⓖ '  └ REJECT 뒤 3초 자식 쓰기 0')" || bad "$(card ⓖ '  └ 자식이 늦게 씀(묶음째 kill 실패)')"
pgrep -f "sleep 90" >/dev/null 2>&1 && bad "$(card ⓖ '  └ 상한 뒤 살아 있는 대역 프로세스 있음')" || ok "$(card ⓖ '  └ 그 묶음 생존 0')"
# ⓖ-손자(r3 · astra r2 반례 N2): 자식이 setsid 로 새 세션 손자를 띄우고(출력 fd 물려받음) 4초 뒤 쓰기 → nf_bound 1 은 ≤ 3초 반환 · 반환 뒤 5초 쓰기 0 · 손자 생존 0
awk '/^nf_fixed\(\) \{/{p=1} /^if \[ "\$REPLAN" -eq 0 \]/{p=0} p' "$T/bin/ft-nano-close.sh" > "$T/fn.sh"
GC="$T/gc"; rm -f "$GC.pid" "$GC.late"
cat > "$T/gc.sh" <<'EOF'
#!/bin/sh
python3 - "$1" <<'PY' &
import os, sys, time
os.setsid()
open(sys.argv[1] + ".pid", "w").write(str(os.getpid()))
time.sleep(4)
open(sys.argv[1] + ".late", "w").write("late")
PY
echo started
sleep 90
EOF
_now="$(date +%s)"; out="$(bash -c '. "$1"; nf_bound 1 sh "$2" "$3"; echo "rc=$?"' _ "$T/fn.sh" "$T/gc.sh" "$GC")"; took="$(elapsed "$_now")"
has "$out" "rc=124" "$(card ⓖ 'setsid 손자 대역 · 상한 1초 → rc 124')"
[ "$took" -le 3 ] && ok "$(card ⓖ "  └ ${took}초에 반환(≤3초 · 손자가 출력 fd 를 물고 있어도)")" || bad "$(card ⓖ "  └ 반환 ${took}s > 3초(손자 fd 기다림)")"
sleep 5
[ ! -e "$GC.late" ] && ok "$(card ⓖ '  └ 반환 뒤 5초 손자 쓰기 0')" || bad "$(card ⓖ '  └ 손자가 반환 뒤에 씀(새 세션 손자 회수 실패)')"
gpid="$(cat "$GC.pid" 2>/dev/null)"
[ -n "$gpid" ] && ! kill -0 "$gpid" 2>/dev/null && ok "$(card ⓖ "  └ 손자 pid ${gpid} 생존 0")" || { bad "$(card ⓖ "  └ 손자 pid ${gpid:-<없음>} 살아 있음/기록 없음")"; [ -z "$gpid" ] || kill -9 "$gpid" 2>/dev/null; }
# ⓖ2·ⓖ3(r5 계약 · astra r3 반례): 총(nf_bound 호출부터 rc 까지) ≤ 상한 + 4초 — ps 가 안 돌아와도 · 대상이 TERM 을 무시해도 · 손자가 출력 fd 를 물고 있어도 그 안에 rc(상한 = 124)를 돌려준다
#   시험 단언 ≤ 4.9초(상한 1초) < 계약 상한 5.0초 = 의도
#   PATH 앞 ps 대역 — ⓖ2 는 0.7초 잠든 뒤 진짜 ps · ⓖ3 는 5초 잠듦(조회 상한 1초에 잘림 · exec 로 대역 = 한 프로세스 = 진짜 ps 가 멈춘 꼴)
timed() {  # timed <ps 대역 폴더> — nf_bound 1 /bin/sleep 10 의 «rc 걸린초» (소수 3자리)
  PATH="$1:$PATH" python3 -c 'import subprocess,sys,time
t=time.time(); r=subprocess.run(["bash","-c",". \"$1\"; nf_bound 1 /bin/sleep 10","_",sys.argv[1]])
print(r.returncode, "%.3f" % (time.time()-t))' "$T/fn.sh"
}
mkdir -p "$T/ps07" "$T/ps5"
printf '#!/bin/sh\nsleep 0.7\nexec /bin/ps "$@"\n' > "$T/ps07/ps"; printf '#!/bin/sh\nexec /bin/sleep 5\n' > "$T/ps5/ps"; chmod +x "$T/ps07/ps" "$T/ps5/ps"
for g in ⓖ2:ps07 ⓖ3:ps5; do
  nm="${g%%:*}"; r="$(timed "$T/${g#*:}")"; rrc="${r%% *}"; sec="${r#* }"
  [ "$rrc" = "124" ] && ok "$(card ⓖ "$nm ps 대역(${g#*:}) · nf_bound 1 /bin/sleep 10 → rc 124")" || bad "$(card ⓖ "$nm rc=$rrc ← $r")"
  awk -v s="$sec" 'BEGIN{exit !(s <= 4.9)}' && ok "$(card ⓖ "  └ $nm ${sec}초 ≤ 4.9초(시험 단언 · 계약 상한 1 + 4 = 5.0초)")" || bad "$(card ⓖ "  └ $nm ${sec}초 > 4.9초(시험 단언 밖)")"
  pgrep -f '^/bin/sleep 10$' >/dev/null 2>&1 && bad "$(card ⓖ "  └ $nm 대상 /bin/sleep 10 살아 있음")" || ok "$(card ⓖ "  └ $nm 대상 /bin/sleep 10 생존 0")"
done
pgrep -f '^/bin/sleep 5$' >/dev/null 2>&1 && bad "$(card ⓖ '  └ ⓖ3 대역 ps(sleep 5) 살아 있음')" || ok "$(card ⓖ '  └ ⓖ3 대역 ps(sleep 5) 생존 0(조회 상한 1초에 잘림)')"


echo "== ⓗ TERM 무시 대역 · 상한 1초 → 3초 안에 끝남(KILL 유예 1초)"
setup
cat > "$T/bin/ft-nano-evidence-check.sh" <<'EOF'
#!/bin/sh
trap '' TERM
echo "CALL evidence" >> "$CALLS"
sleep 90
EOF
chmod +x "$T/bin/ft-nano-evidence-check.sh"
awk '/^nf_fixed\(\) \{/{p=1} /^if \[ "\$REPLAN" -eq 0 \]/{p=0} p' "$T/bin/ft-nano-close.sh" > "$T/fn.sh"
_now="$(date +%s)"; bash "$T/fn.sh" 2>/dev/null; out="$(bash -c '. "$1"; nf_bound 1 sh -c "trap \"\" TERM; sleep 90"; echo "rc=$?"' _ "$T/fn.sh")"; took="$(elapsed "$_now")"
has "$out" "rc=124" "$(card ⓗ 'TERM 무시 대역 · 상한 1초 → rc 124')"
[ "$took" -le 3 ] && ok "$(card ⓗ "  └ 상한+유예 = ${took}초(≤3초 · KILL 유예 1초)")" || bad "ⓗ took=${took}s > 3초 ← $out"
pgrep -f "sleep 90" >/dev/null 2>&1 && bad "ⓗ TERM 무시 대역이 살아 있음" || ok "$(card ⓗ '  └ 그 묶음 생존 0')"


finish
