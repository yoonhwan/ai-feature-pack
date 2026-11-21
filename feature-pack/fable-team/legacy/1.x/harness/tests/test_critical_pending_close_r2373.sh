#!/usr/bin/env bash
# test_critical_pending_close_r2373.sh — r2373: 착지·해결이 밀린 [크리티컬] 줄을 닫고 · drain 은 받는 이마다 바로 «보냄» · 착지 지문에서 잰 초를 뺀다
#   ① --resolved 가 그 PR 밀린 줄만 지움 ② --wrap ft-merge-land rc 0 → 그 PR 밀린 줄 0 ③ SENT 없음 + 밀린 줄 → 정리
#   ④ desk 발신 직후 SIGKILL → 다음 drain = master 만 ⑤ 3줄 중 둘째 뒤 끊김 → SENT 2 · 셋째만 다음 ⑥ 모두 받은 줄은 묶음 끝 전에 빠짐 ⑦ desk 실패 → 다시
#   ⑧ «상한 16s»/«상한 22s» = 같은 지문 · 1통 ⑨ 다른 원인 = 2통 ⑩ 본문 숫자 그대로 · ⑪(회귀) = test_reject_critical_r1718*.sh 따로
#   변이 M1~M7 — 사본에서만 · 변이마다 원본 BIN 으로 같은 사례 1회 더. 기준판 대조 = FT_TEST_BASE_BIN(①·④·⑧ 이 거기서 FAIL).
#   실 명부·실 우편함·실 state·실 원격 0 · 끊김 = 가짜 mbox 가 N번째 부름에서 부모(python)를 SIGKILL · sleep 0 · 70초 안.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/_reject_critical_r1718_fixture.sh"
MAST='byz-planner-master-pi#1'
# 가짜 mbox(이 시험 전용) — 부름마다 MCALLS 1줄(받는 이) · MBOX_KILL_AT=n 번째 부름 = 부모 SIGKILL · MBOX_FAIL_TO=<받는 이> = rc 1 · 성공 = MLOG 1줄
cat > "$T/mbox.sh" <<'EOF'
#!/usr/bin/env bash
echo "$2" >> "$MCALLS"
[ "${MBOX_KILL_AT:-0}" != "$(grep -c . "$MCALLS")" ] || { kill -9 "$PPID"; exit 1; }
[ "${MBOX_FAIL_TO:-}" != "$2" ] || exit 1
n=$(( $(grep -c . "$MLOG") + 501 ))
printf '%s\t%s\t%s\n' "$2" "$3" "$4" >> "$MLOG"; echo "QUEUED seq=$n to=$2"
EOF
git init -q "$T/r" && git -C "$T/r" remote add origin git@github.com:own/rep.git
P7='own/rep PR #7'; P8='own/rep PR #8'
to() { awk -F'\t' -v w="$1" '$1==w' "$MLOG" | grep -c "${2:-.}"; }               # to <받는 이> [글] — 그 이가 받은 통 수
pend_has() { grep -cF "\"target\": \"$1\"" "$PEND" 2>/dev/null || true; }        # 밀린 줄 중 그 대상 줄 수
nlines() { local n; n="$(grep -c . "$1" 2>/dev/null)"; echo "${n:-0}"; }
M() { cn "$@" --what "REJECT w (착지 0)" --next n --where w; }                    # M <bin> <도구> <대상> --event e — 알림 1건
land() { local b="$1"; shift; FAKE_HEAD=h1 FAKE_RC="$RC_" wrap "$b" ft-merge-land 7 --repo "$T/r" "$@"; }

c1() { local b="$1"; fresh
  MBOX_FAIL_TO="$DESK" M "$b" ft-merge-land "$P7" --event e1 2>/dev/null; MBOX_FAIL_TO="$DESK" M "$b" ft-merge-land "$P7" --event e2 2>/dev/null
  MBOX_FAIL_TO="$DESK" M "$b" ft-merge-land "$P8" --event e3 2>/dev/null
  eqn "$(pend_has "$P7")/$(pend_has "$P8")/$(nsent)" 2/1/0 "밀린 줄 PR7 2 · PR8 1 · 발신 0" || return 1
  cn "$b" --resolved ft-merge-land "$P7" 2>"$T/err"; eqn $? 0 "rc" || return 1
  eqn "$(pend_has "$P7")/$(pend_has "$P8")" 0/1 "PR7 줄 0 · PR8 그대로" && inc "$(cat "$T/err")" "RESOLVED ft-merge-land $P7 pending 2" "stderr 1줄" || return 1
  cn "$b" --drain 2>/dev/null; eqn "$(grep -c 'PR #7' "$MLOG")" 0 "drain 의 PR7 발신 0"; }
c2() { local b="$1"; fresh; printf 'LANDED pr=7\n' > "$FAKE_OUT"
  MBOX_FAIL_TO="$DESK" M "$b" ft-merge-land "$P7" --event e1 2>/dev/null; eqn "$(pend_has "$P7")" 1 "밀린 줄 1" || return 1
  RC_=0 land "$b" >/dev/null 2>&1; eqn $? 0 "착지 rc 0" && eqn "$(pend_has "$P7")" 0 "착지 뒤 PR7 밀린 줄 0" || return 1
  cn "$b" --drain 2>/dev/null; eqn "$(nsent)" 0 "drain 발신 0"; }
c3() { local b="$1"; fresh
  MBOX_FAIL_TO="$DESK" M "$b" ft-merge-land "$P7" --event e1 2>/dev/null; rm -f "$SENT"; [ ! -e "$SENT" ] && eqn "$(pend_has "$P7")" 1 "SENT 없음 · 밀린 1" || return 1
  cn "$b" --resolved ft-merge-land "$P7" 2>/dev/null; eqn $? 0 "rc" && eqn "$(pend_has "$P7")" 0 "PEND 정리"; }
c4() { local b="$1"; fresh
  MBOX_KILL_AT=2 M "$b" ft-merge-land "$P7" --event e1 2>/dev/null
  eqn "$(to "$DESK")/$(to "$MAST")" 1/0 "끊김 전 desk 1 · master 0" || return 1
  cn "$b" --drain 2>/dev/null; eqn "$(to "$DESK")/$(to "$MAST")/$(npend)" 1/1/0 "다음 drain = master 만 · pending 0"; }
c5() { local b="$1"; fresh; roster ""; local i; for i in 1 2 3; do M "$b" ft-x "t$i" --event "e$i" 2>/dev/null; done; roster "$DESK"
  MBOX_KILL_AT=3 cn "$b" --drain 2>/dev/null
  eqn "$(nsent)/$(nlines "$SENT")" 2/2 "둘째까지 발신 · SENT 줄 2" || return 1
  cn "$b" --drain 2>/dev/null; eqn "$(nsent)/$(to "$DESK" 't3 ')/$(to "$DESK" 't1 ')" 3/1/1 "다음 drain = 셋째만" && eqn "$(npend)" 0 "pending 0"; }
c6() { local b="$1"; fresh; roster ""; M "$b" ft-x t1 --event e1 2>/dev/null; M "$b" ft-x t2 --event e2 2>/dev/null; roster "$DESK"
  MBOX_KILL_AT=2 cn "$b" --drain 2>/dev/null
  eqn "$(nsent)/$(pend_has t1)/$(pend_has t2)" 1/0/1 "모두 받은 t1 은 끊김 전에 PEND 에서 빠짐"; }
c7() { local b="$1"; fresh
  MBOX_FAIL_TO="$DESK" M "$b" ft-x t1 --event e1 2>/dev/null
  eqn "$(nsent)/$(npend)/$(python3 -c 'import json,sys;print(json.loads(open(sys.argv[1]).read().strip()).get("sent") or [])' "$PEND")" "0/1/[]" "desk 실패 = sent 빈 값" || return 1
  cn "$b" --drain 2>/dev/null; eqn "$(to "$DESK")/$(npend)" 1/0 "다음 drain 다시 1통"; }
rj() { printf 'REJECT own/rep PR #7 — %s (착지 0)\n' "$1" > "$FAKE_OUT"; RC_=1 land "$2" >/dev/null 2>&1; }    # rj <원인 글> <bin>
c8() { local b="$1"; fresh; rj "gate 가 상한 16s 를 다 씀" "$b"; rj "gate 가 상한 22s 를 다 씀" "$b"
  eqn "$(to "$DESK")" 1 "같은 원인 · 다른 초 = desk 1통"; }
c9() { local b="$1"; fresh; rj "gate 가 상한 16s 를 다 씀" "$b"; rj "push 1단위 14s > 남은 13s" "$b"
  eqn "$(to "$DESK")" 2 "다른 원인 = 2통"; }
c10() { local b="$1"; fresh; rj "gate 가 상한 16.5s · 3초 를 다 씀" "$b"
  inc "$(cut -f3 "$MLOG")" "상한 16.5s · 3초 를 다 씀" "본문 숫자 원문 그대로"; }

for f in ft-critical-notify.sh; do cmp -s "$BIN/$f" "$KIT/$f" && ok "짝 cmp0 $f" || bad "짝 다름 $f"; done
tc "① --resolved = 그 PR 밀린 줄만 지움 · drain 발신 0" c1; basefail "①" c1; tc "② 착지 rc 0 → 그 PR 밀린 줄 0" c2; tc "③ SENT 없음 + 밀린 줄 → 정리" c3; step ①②③
tc "④ desk 뒤 끊김 → 다음 drain master 만" c4; basefail "④" c4; tc "⑤ 3줄 중 둘째 뒤 끊김 → 셋째만" c5; tc "⑥ 모두 받은 줄 즉시 빠짐" c6; tc "⑦ desk 실패 → 다시" c7; step ④~⑦
tc "⑧ 같은 원인 · 다른 초 = 1통" c8; basefail "⑧" c8; tc "⑨ 다른 원인 = 2통" c9; tc "⑩ 본문 숫자 원문" c10; step ⑧~⑩

NT=ft-critical-notify.sh
mut $NT 'keep = [p for p in pend if (p.get("tool"), p.get("target")) != (tool, target)]   # r2373-mut:pendclose' 'keep = pend' && killed "M1 resolve 의 PEND 정리 지움" c1
mut $NT 'keep = [p for p in pend if (p.get("tool"), p.get("target")) != (tool, target)]   # r2373-mut:pendclose' 'keep = []' && killed "M2 PEND 정리를 대상 무관 전부로" c1
mut $NT 'if not (os.path.isfile(SENT) or os.path.isfile(PEND)): return   # r2373-mut:nosent' 'if not os.path.isfile(SENT): return' && killed "M3 SENT 없으면 바로 return" c3
mut $NT '    for r in batch:' $'    done = []\n    for r in batch:' '; record(r, {' '; done.append((r, {' '"to": to})   # r2373-mut:each' '"to": to}))' \
  '    with Lock():   # r2373-mut:end' $'    for x in done: record(*x)\n    with Lock():   #' && killed "M4 받는 이마다 기록을 묶음 끝으로" c4
mut $NT 'if w["to"] and all(t in w["sent"] for t in w["to"]): continue   # r2373-mut:alldone' 'pass' \
  'save(PEND, pend)   # r2373-mut:endsave' 'save(PEND, [w for w in pend if not (w.get("to") and all(t in (w.get("sent") or []) for t in w["to"]))])' && killed "M5 모두 받은 줄을 묶음 끝에서만 뺌" c6
mut $NT $'"Ns", "\\n".join(ls[i:j + 1]))' $'"Ns", "\\n".join(ls[i:j + 1])) and "\\n".join(ls[i:j + 1])' && killed "M6 숫자 바꿈 지움" c8
mut $NT 'ls[i], nexts(LAND_NEXT' $'re.sub(r"\\d+(?:\\.\\d+)?(?:s|초)", "Ns", ls[i]), nexts(LAND_NEXT' && killed "M7 숫자를 본문에서도 바꿈" c10
step 변이
finish
