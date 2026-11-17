#!/usr/bin/env bash
# test_nano_record_budget_r2175.sh — r2175 notify 실행 예산 · 단계 표식 · stall-scan «멎은 곳».
#   ① 몰린 줄 8 · +5초/발신 → 3통 · 미룸 5 · rc 0   ② 이어 보냄 3 · 2   ③ 예산 안 = 기준판 stdout   ④ 발신 없는 줄 = 미룸 0 · 앞 6줄만 기록 = 미룸 2
#   ⑤ 밀림 줄 + 시계 20 = drift 0 · 닫기 요청 0 · 미룸 1 (⑤b 버린 seq = 미룸 1 · 다음 실행 재발신 1)   ⑥ 판정불가 줄 그대로 · rc 3
#   ⑦ 표식(둘째 발신 · ring 직전 · 끝)   ⑧ stall-scan 로그 «멎은 곳»(a 새 표식 · b 옛 표식 · c rc 0 · 경계 epoch)   확인② due 시간 포함(시계 15 · 단조 시계)
#   ⑤c·⑤d (DA R1) drift 캐시 DRIFT + [설치 먼저] 기록 = 외부 호출 0 줄은 예산 밖 · 기록 없음 = 미룸 · M7 = 밀림 줄 예산을 무조건
#   변이 M1~M7 = 사본에서만 · 원본 대조 1회씩 · 세계 = _nano_record_r1717_fixture.sh(가짜 mbox·명부·tmux · 시계 파일) — 실 우편함·실 tmux·네트워크 0 · sleep 0
#   기준판 Red = R1717_BIN=<앞 판 bin> R2175_NO_MUT=1 bash <이 파일>
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_nano_record_r1717_fixture.sh"
NN() { printf 'byz-harness-nano-%s#0' "$1"; }
CLKF="$T/clock"; CM="$T/cmbox.sh"; SF="$STATE/land-record-notify-step.txt"; CP="$T/stepcopy"; DL="$T/drift.log"
cat > "$CM" <<'EOF'
#!/usr/bin/env bash
# 시계 우편함 — 부를 때마다 표식 파일을 STEP_COPY 에 1줄 복사 · send 면 시계 파일에 CLK_ADD 초를 더한 뒤 가짜 우편함으로 넘긴다
{ cat "$STEP_FILE" 2>/dev/null || echo "(없음)"; } | head -n1 | sed "s/^/$1 /" >> "$STEP_COPY"
[ "$1" != send ] || [ -z "${CLK_ADD:-}" ] || awk -v a="$(cat "$CLK_FILE" 2>/dev/null || echo 0)" -v b="$CLK_ADD" 'BEGIN{print a+b}' > "$CLK_FILE.n" && mv "$CLK_FILE.n" "$CLK_FILE"
exec bash "$INNER_MBOX" "$@"
EOF
cat > "$T/fdrift.sh" <<'EOF'
#!/usr/bin/env bash
# 가짜 drift 검사 — 부를 때마다 DRIFT_LOG 1줄 · DRIFT_ADD 초를 시계에 더함 · DRIFT_RC=1 이면 «DIFF ft_x.py» 1줄
echo "$*" >> "$DRIFT_LOG"
[ -z "${DRIFT_ADD:-}" ] || awk -v a="$(cat "$CLK_FILE" 2>/dev/null || echo 0)" -v b="$DRIFT_ADD" 'BEGIN{print a+b}' > "$CLK_FILE.n" && mv "$CLK_FILE.n" "$CLK_FILE"
[ "${DRIFT_RC:-0}" != 1 ] || echo "DIFF ft_x.py"
exit "${DRIFT_RC:-0}"
EOF
export STEP_FILE="$SF" STEP_COPY="$CP" CLK_FILE="$CLKF" INNER_MBOX="$FK/mbox.sh" DRIFT_LOG="$DL"
nt() { echo "$1" > "$CLKF"; : > "$CP"; CLK_ADD="$2" FT_LAND_RECORD_CLOCK="$CLKF" FT_MBOX="$CM" FT_DRIFT_CHECK="$T/fdrift.sh" rec notify "${@:3}"; }   # nt <시계 시작> <발신당 +초> [인자…]
norm() { printf '%s\n' "$1" | sed -E 's/ #[0-9]+$/ #N/'; }
nown() { nto "$MASTER" "주인 없음\]"; }
nstore() { python3 -c 'import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: d={}
print(sum(1 for k in d.get("sent",{}) if k.endswith("|"+sys.argv[2])))' "$STATE/land-record-notified.json" "$1"; }   # 보낸 기록 sent 칸 중 그 종류 열쇠 수
nreq() { nto "$MASTER" "\[완료·닫기 요청\] $1 "; }
own() {  # own <꼬리표> <PR> <n> — «주인 없음» 열린 줄 n개(카드 n장 · 좌석 n개 모두 죽음 · 장부 1줄)
  local i s st=() rw=(); fresh; land "$2"
  for i in $(seq 1 "$3"); do s="o$1x$i"; cardf "$s"; st+=("$s"); rw+=("$(NN "$s")|nano|$s"); done; cpush
  seats "${rw[@]}"; : > "$FAKE_SESS"; turn "$2" "${st[@]}"
}
OK8="$(for i in 1 2 3 4 5 6 7 8; do echo "NOTIFIED 주인없음 → $MASTER #N"; done)"

step "사전: 문법 · 짝 사본 · 줄 수"
for f in ft_nano_record_budget.py ft_nano_record_notify.py ft_stall_scan.py; do
  [ -f "$BIN/$f" ] && python3 -m py_compile "$BIN/$f" && ok "문법 $f" || bad "없음·문법 $f"
  cmp -s "$SRC/$f" "$KIT/$f" && ok "짝 사본 bin·kit cmp0 $f" || bad "짝 사본 다름 $f"
done
for f in ft_nano_record_budget.py ft_nano_record_notify.py; do [ -f "$BIN/$f" ] && [ "$(wc -l < "$BIN/$f")" -le 200 ] && ok "≤200줄 $f" || bad "200줄 넘음·없음 $f"; done
world

c1() {  # ① 8줄 · 시계 0 · +5 → 3통(0·5·10) · 기록 3 · 미룸 5 · rc 0
  own "c1$1" 21 8; nt 0 5
  t "① 발신 3" [ "$(nown)" = 3 ]; t "① 보낸 기록 3" [ "$(nstore 주인없음)" = 3 ]; t "① rc 0" [ "$RC" = 0 ]
  t "① 끝 줄" [ "$(printf '%s\n' "$OUT" | tail -n1)" = "미룸 5줄 — 실행 예산 12초 · 다음 실행이 이어 보냄" ]; return $E
}
c2() {  # ② ① 뒤 시계 0 → 다음 3통 · 재발신 0 · 미룸 2 → 한 번 더 2통 · 미룸 줄 없음
  own "c2$1" 22 8; nt 0 5; nt 0 5
  t "② 둘째 = 누적 6" [ "$(nown)" = 6 ]; t "② 미룸 2" inc "$OUT" "미룸 2줄 — 실행 예산 12초"
  t "② 카드마다 1통" [ "$(awk -F'\t' '$1 != "FAIL"' "$MBOX_LOG" | grep -o "주인 없음\] [^ ]*" | sort | uniq -d | wc -l | tr -d ' ')" = 0 ]
  nt 0 5; t "② 셋째 = 누적 8" [ "$(nown)" = 8 ]; t "② 미룸 줄 없음" exc "$OUT" "미룸"; t "② 기록 8" [ "$(nstore 주인없음)" = 8 ]; return $E
}
c3() {  # ③ 2줄 · +1 → 2통 · stdout = 기준판 꼴(미룸 줄 없음)
  own "c3$1" 23 2; nt 0 1
  t "③ stdout 기준판" [ "$(norm "$OUT")" = "$(printf '%s\n' "$OK8" | head -n2)" ]; t "③ 기록 2" [ "$(nstore 주인없음)" = 2 ]; t "③ rc 0" [ "$RC" = 0 ]; return $E
}
c4() {  # ④ 8줄 모두 기록 있음 · 시계 20 → 발신 0 · stdout 빈 값 · 앞 6줄만 기록 → 미룸 2
  own "c4$1" 24 8; nt 0 0; t "④ 준비 8통" [ "$(nown)" = 8 ]
  nt 20 5; t "④ 발신 추가 0" [ "$(nown)" = 8 ]; t "④ stdout 빈 값(기준판)" [ -z "$OUT" ]; return $E
}
c4b() {  # ④b 앞 6줄만 기록 있음 · 시계 20 → 발신 0 · 미룸 2
  own "c4b$1" 25 8; nt 0 2   # 6통(0·2·…·10) 뒤 12 ≥ 12 → 미룸 2
  t "④b 준비 6통 · 미룸 2" [ "$(nown) $(printf '%s\n' "$OUT" | grep -c '^미룸 2줄')" = "6 1" ]
  nt 20 5; t "④b 발신 0" [ "$(nown)" = 6 ]; t "④b 미룸 2" [ "$OUT" = "미룸 2줄 — 실행 예산 12초 · 다음 실행이 이어 보냄" ]; return $E
}
mil() {  # mil <꼬리표> <PR> — «닫기 요청 밀림» 줄 1개(세션 기록 있음) → SM = 그 좌석 · SS = stem
  SS="m$1"; SM="$(NN "m$1")"; fresh; land "$2"; card "$SS"; seats "$SM|nano|$SS"; turn "$2" "$SS"
  MBOX_FAIL_HEAD='[완료·닫기 요청]' rec landed --seat "$SM" --pr "$2" --card "$SS" --test 'bash t.sh rc=0'; : > "$DL"
}
c5() {  # ⑤ 밀림 + 시계 20 → drift 0 · 닫기 요청 0 · 미룸 1 · 시계 0 → drift 1 · 요청 1
  mil "c5$1" 26; rec due --pr 26; t "⑤ due 밀림" inc "$OUT" "닫기 요청 밀림 $SM"
  nt 20 5; t "⑤ drift 0" [ ! -s "$DL" ]; t "⑤ 닫기 요청 0" [ "$(nreq "$SS")" = 0 ]; t "⑤ 미룸 1" inc "$OUT" "미룸 1줄 — 실행 예산 12초"; t "⑤ rc 0" [ "$RC" = 0 ]
  nt 0 5; t "⑤ 대조 drift 1" [ "$(wc -l < "$DL" | tr -d ' ')" = 1 ]; t "⑤ 대조 요청 1" [ "$(nreq "$SS")" = 1 ]; t "⑤ 대조 미룸 0" exc "$OUT" "미룸"; return $E
}
c5b() {  # ⑤b 전달한 seq 가 drops log 에 있음 → 시계 20 = 미룸 1 · 재발신 0 → 시계 0 = 재발신 1 → 다시 = 0
  mil "c5b$1" 27; nt 0 0; t "⑤b 첫 요청 1" [ "$(nreq "$SS")" = 1 ]
  local sq; sq="$(awk -F'\t' -v s="$SS" '$1 != "FAIL" && index($4, "[완료·닫기 요청] " s " ") {print $1}' "$MBOX_LOG" | tail -n1)"
  echo "2026-11-17T00:00:00 to=$MASTER dropped=1 oldest_seq=$sq seqs=$sq" > "$COMM/mailbox.drops.log"
  nt 20 5; t "⑤b 미룸 1" inc "$OUT" "미룸 1줄"; t "⑤b 재발신 0" [ "$(nreq "$SS")" = 1 ]
  nt 0 5; t "⑤b 다음 실행 재발신 1" [ "$(nreq "$SS")" = 2 ]; t "⑤b 미룸 0" exc "$OUT" "미룸"
  nt 0 5; t "⑤b 또 = 0" [ "$(nreq "$SS")" = 2 ]; rm -f "$COMM/mailbox.drops.log"; return $E
}
mil2() {  # mil2 <꼬리표> <PR> — 같은 장부 줄의 «밀림» 2줄(SA·SB · 좌석 NA·NB · 세션 기록 있음)
  SA="ma$1"; SB="mb$1"; NA="$(NN "$SA")"; NB="$(NN "$SB")"; fresh; land "$2"; card "$SA"; card "$SB"; seats "$NA|nano|$SA" "$NB|nano|$SB"; turn "$2" "$SA" "$SB"
  MBOX_FAIL_HEAD='[완료·닫기 요청]' rec landed --seat "$NA" --pr "$2" --card "$SA" --test 'bash t.sh rc=0'
  MBOX_FAIL_HEAD='[완료·닫기 요청]' rec landed --seat "$NB" --pr "$2" --card "$SB" --test 'bash t.sh rc=0'; : > "$DL"
}
ninst() { nto "$MASTER" "\[설치 먼저\]"; }
c5c() {  # ⑤c (DA R1) 밀림 2줄 · [설치 먼저] 기록 둘 다 · 시계 11 · drift 1회 +7 = DRIFT → 둘째 줄 = 캐시·기록 = 외부 호출 0 → 미룸 0 · 두 줄 다 «닫기 요청 미룸»(기준판과 같음)
  mil2 "c5c$1" 32; storeset install "$SA|$Q" '{"seq": 1}'; storeset install "$SB|$Q" '{"seq": 2}'
  DRIFT_RC=1 DRIFT_ADD=7 nt 11 5; t "⑤c drift 1회" [ "$(wc -l < "$DL" | tr -d ' ')" = 1 ]; t "⑤c 미룸 0" exc "$OUT" "줄 — 실행 예산"
  t "⑤c 닫기 요청 미룸 2줄" [ "$(printf '%s\n' "$OUT" | grep -c '^닫기 요청 미룸 ')" = 2 ]; t "⑤c 발신 0" [ "$(nreq "$SA") $(nreq "$SB") $(ninst)" = "0 0 0" ]; t "⑤c rc 0" [ "$RC" = 0 ]; return $E
}
c5d() {  # ⑤d 같은 입력 · 둘째 줄 [설치 먼저] 기록 없음 = 발신 필요 → 시계 18 ≥ 12 = 미룸 1 · 설치 먼저 0통
  mil2 "c5d$1" 33; storeset install "$SA|$Q" '{"seq": 1}'
  DRIFT_RC=1 DRIFT_ADD=7 nt 11 5; t "⑤d drift 1회" [ "$(wc -l < "$DL" | tr -d ' ')" = 1 ]; t "⑤d 미룸 1" inc "$OUT" "미룸 1줄 — 실행 예산 12초"
  t "⑤d 닫기 요청 미룸 1줄" [ "$(printf '%s\n' "$OUT" | grep -c '^닫기 요청 미룸 ')" = 1 ]; t "⑤d 설치 먼저 0" [ "$(ninst)" = 0 ]; return $E
}
c6() {  # ⑥ ① + 판정불가 줄 1 → 그 줄 그대로 · 미룸 5 · rc 3
  own "c6$1" 28 8; printf '{"pr":99,"repo":"%s","target":"main","landed":"%s","pr_head":"%s","by":"","cards":["bogus.md"],"ts":"t"}\n' "$PACK" "$Q" "$PH" >> "$STATE/land-record-turn.jsonl"
  nt 0 5; t "⑥ rc 3" [ "$RC" = 3 ]; t "⑥ 판정 불가 줄 1" [ "$(printf '%s\n' "$OUT" | grep -c '^판정 불가 .*카드 경로 꼴 rc=1')" = 1 ]
  t "⑥ 발신 3" [ "$(nown)" = 3 ]; t "⑥ 끝 줄 미룸 5" [ "$(printf '%s\n' "$OUT" | tail -n1)" = "미룸 5줄 — 실행 예산 12초 · 다음 실행이 이어 보냄" ]; return $E
}
c7() {  # ⑦ 둘째 발신 때 표식 = «<epoch> send <받는 이> 경과=5 보냄=1 남음=6» · 끝 = «끝» · ring 직전 = 경과 18 · 보냄 1
  own "c7$1" 29 8; nt 0 5
  t "⑦ 둘째 발신 표식" [ "$(sed -n 2p "$CP" | sed -E 's/^send [0-9]+\.[0-9]{6} /send E /')" = "send E send $MASTER 경과=5 보냄=1 남음=6" ]
  t "⑦ 끝 표식" [ "$(cut -d' ' -f2,3 "$SF")" = "끝 -" ]; return $E
}
c7r() {  # ⑦r 재촉 줄 ring 직전 표식 = 경과 18 · 보냄 1(시계 11 에서 차례 쪽지 +7)
  local s n; s="c7r$1"; n="$(NN "$s")"; fresh; land 30; card "$s"; seats "$n|nano|$s"; turn 30 "$s"
  MBOX_DB=quiet nt 11 7; t "⑦ ring 1" inc "$(cat "$MBOX_LOG.ring" 2>/dev/null)" "$n"
  t "⑦ ring 직전 표식" [ "$(grep '^ring ' "$CP" | head -n1 | cut -d' ' -f1,3-)" = "ring ring $n 경과=18 보냄=1 남음=0" ]; return $E
}
c8() {  # ⑧ stall-scan — a 새 표식 rc 99 · b 옛 표식 rc 99 · c rc 0
  mkdir -p "$STATE"
  cat > "$T/fnr-a.sh" <<'EOF'
#!/usr/bin/env bash
echo "$(python3 -c 'import time; print(f"{time.time():.6f}")') send X 경과=17 보냄=3 남음=5" > "$FT_ROOT/.fable-team/state/land-record-notify-step.txt"
exit 99
EOF
  printf '#!/usr/bin/env bash\nexit "${FNR_RC:-99}"\n' > "$T/fnr-b.sh"
  FT_NANO_RECORD="$T/fnr-a.sh" scan notify; t "⑧a 멎은 곳" [ "$OUT" = "T 판정 불가 record-notify rc=99 — 멎은 곳: send X 경과=17 보냄=3 남음=5" ]
  echo "$(( $(date +%s) - 100 )).000000 send Y 경과=3 보냄=0 남음=1" > "$SF"
  FT_NANO_RECORD="$T/fnr-b.sh" scan notify; t "⑧b 표식 없음" [ "$OUT" = "T 판정 불가 record-notify rc=99 — 멎은 곳: 표식 없음" ]
  rm -f "$SF"; FT_NANO_RECORD="$T/fnr-b.sh" scan notify; t "⑧b 파일 없음 = 표식 없음" [ "$OUT" = "T 판정 불가 record-notify rc=99 — 멎은 곳: 표식 없음" ]
  FNR_RC=0 FT_NANO_RECORD="$T/fnr-b.sh" scan notify; t "⑧c rc 0 = 로그 0" [ -z "$OUT" ]; return $E
}
c8e() {  # 확인④ 경계 — 표식 epoch = 시작 → 붙임 · 1µs 앞 → 표식 없음 · 같은 정수초 안의 앞 소수 → 표식 없음(정수초 절삭 0)
  mkdir -p "$STATE"; OUT="$(fxpy "$ROOT" <<'PY'
import sys
from ft_nano_record_budget import STEP, stop_trace
from pathlib import Path
p = Path(sys.argv[1]) / STEP
p.write_text("1763380000.123456 send Z 경과=1 보냄=0 남음=0\n", encoding="utf-8")
print(stop_trace(sys.argv[1], "1763380000.123456")); print(stop_trace(sys.argv[1], "1763380000.123457")); print(stop_trace(sys.argv[1], "1763380000.9"))
PY
)"; t "확인④ 경계" [ "$OUT" = "$(printf 'send Z 경과=1 보냄=0 남음=0\n표식 없음\n표식 없음')" ]; return $E
}
c9() {  # 확인② due 가 쓴 초 포함 — 시계 15(due 15초 모델) = 발신 0 · 미룸 2 · 단조 시계 + 예산 0.001초 = 발신 0 · 미룸 2
  own "c9$1" 31 2; nt 15 5; t "확인② 시계 15 발신 0" [ "$(nown)" = 0 ]; t "확인② 미룸 2" inc "$OUT" "미룸 2줄"
  : > "$CP"; FT_LAND_RECORD_BUDGET_S=0.001 FT_MBOX="$CM" rec notify; t "확인② 단조 시계 발신 0" [ "$(nown)" = 0 ]; t "확인② 단조 미룸 2" inc "$OUT" "미룸 2줄 — 실행 예산 0.001초"; return $E
}
step "사례"
run "① 몰린 줄 = 3통 · 미룸 5" c1; run "② 이어 보냄" c2; run "③ 예산 안 = 기준판" c3; run "④ 발신 없는 줄" c4; run "④b 앞 6줄만 기록" c4b
run "⑤ 밀림 줄 예산" c5; run "⑤b 버린 seq 미룸 → 재발신" c5b; run "⑤c 캐시·기록 = 예산 밖" c5c; run "⑤d 설치 먼저 필요 = 미룸" c5d; run "⑥ 판정불가 + 미룸 = rc 3" c6; run "⑦ 단계 표식" c7; run "⑦r ring 직전 표식" c7r
run "⑧ stall-scan 멎은 곳" c8; run "확인④ epoch 경계" c8e; run "확인② due 포함 시계" c9

if [ -z "${R2175_NO_MUT:-}" ]; then
  step "변이"
  mutbin m1 ft_nano_record_budget.py 'if self.elapsed() < self.b:' 'if True:'; mutcase M1 c1 1
  mutbin m2 ft_nano_record_notify.py '    ent = ctx.store()["sent"].get(key)
' '    ent = ctx.store()["sent"].get(key)
    if __import__("ft_nano_record_budget").over(ctx):
        return
'; mutcase M2 c4 2
  mutbin m3 ft_nano_record_notify.py 'if close_over(ctx, r):   # r2175 N1 — 밀림 줄의 첫 외부 호출(drift·발신) 앞 · 호출 0 = 예산 밖' 'if False:'; mutcase M3 c5 3
  mutbin m4 ft_nano_record_budget.py 'return 3 if any(' 'return 3 if self.deferred or any('; mutcase M4 c1 4
  mutbin m5 ft_nano_record_budget.py '        bud.mark(step, target)
    rc, out, err = run(cmd, env=dict(os.environ))' '        pass
    rc, out, err = run(cmd, env=dict(os.environ))
    bud and bud.mark(step, target)'; mutcase M5 c7 5
  mutbin m7 ft_nano_record_notify.py 'if close_over(ctx, r):' 'if over(ctx):'; mutcase M7 c5c 7
  mutbin m6 ft_nano_record_budget.py 'if float(ep) >= float(start):' 'if True:'; mutcase M6 c8 6
fi
finish
