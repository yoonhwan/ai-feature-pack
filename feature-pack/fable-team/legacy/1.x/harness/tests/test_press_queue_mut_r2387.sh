#!/usr/bin/env bash
# test_press_queue_mut_r2387.sh — r2387 변이 M1~M4: 계약이 깨지면 그 사례가 FAIL 하는가(변이 = 사본에서 글자 1곳 · 변이마다 원본으로 같은 사례 1회 더)
#   M1 승인 표식 확인 지움 → ② FAIL   M2 NEXT = 첫 PR(대기 규칙 지움) → ⑥ FAIL   M3 같음 비교를 PR 바뀐 파일만으로 → ⑦ FAIL   M4 음성 경로 아닌 착지도 STALE(트리 전체 비교) → ⑧ FAIL
#   틀 = _press_queue_r2387_lib.sh · 실 gh·실 원격 0
# 사용: timeout 70 bash <이 파일> → 마지막 줄 «== OK ==» · rc 0/1
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_press_queue_r2387_lib.sh"
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:700}"; fail=$((fail+1)); fi; }
S0=$SECONDS
qmut() { : > "$STUB_LOG"; out="$(bash "$1/ft-press-evidence.sh" queue --repo "$REPO" --main "${QMAIN:-origin/main}" 2>&1)"; rc=$?; }
mutfail() {  # mutfail <설명> <기대 부분문자열> — 변이 판이 그 기대를 «못 내면» PASS(계약 깨짐 재현)
  local why="$1" want="$2"; qmut "$MBIN"
  if [ "$rc" = 0 ] && [[ "$out" == *"$want"* ]]; then echo "FAIL $why :: 변이가 기대와 같음 out=${out:0:200}"; fail=$((fail+1)); else echo "PASS $why"; fi
}
oksrc() { local why="$1" want="$2"; qmut "$BIN"; if [ "$rc" = 0 ] && [[ "$out" == *"$want"* ]]; then echo "PASS $why"; else echo "FAIL $why :: 원본이 기대 못 냄 rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi }

# ===== M1: 승인 표식 확인 지움 → ② FAIL =====
qreset
qm 41 pr41 "" worker/p41.py=p41
qm 42 pr42 "$(tmn 20)" worker/p42.py=p42
mut M1 verify '    if not at:
        return "", "승인 전", ""
' ''
mutfail "ⓜM1 승인 표식 확인 지움 → «승인 전» 줄 0 = ② FAIL" "PR #41 승인 전"
oksrc "ⓜM1 원본 재확인 → ② 통과(같은 사례 1회 더)" "PR #41 승인 전"
echo "단계 초: M1 $((SECONDS - S0))s"

# ===== M2: NEXT = 첫 PR(대기 규칙 지움) → ⑥ FAIL =====
qreset
qm 71 pr71 "$(tmn 30)" worker/p71.py=p71
qm 72 pr72 "$(tmn 20)" worker/p72.py=p72
qm 73 pr73 "$(tmn 10)" worker/p73.py=p73
vbs "$(setof "$(sha "$REPO" pr71)")" 20261117-141500
mut M2 verify '    valid = [r for r in rows if r[2] == "VALID"]
    if valid:   # 줄 어디든 VALID 면 NEXT 는 «대기»(DA#53 H1) — VALID 둘 이상이면 승인 순 첫 것
        print("NEXT 대기(VALID PR %d 착지 뒤 · %d분째)" % (valid[0][1], max(0, int((now - (epoch(valid[0][0]) or now)) // 60))))
    else:
        nxt = next((r for r in rows if r[2] in ("STALE", "NONE")), None)   # 판정 불가 줄은 건너뛴다
        print("NEXT %d" % nxt[1] if nxt else "NEXT 없음")' '    valid = []
    nxt = next((r for r in rows), None)
    print("NEXT %d" % nxt[1] if nxt else "NEXT 없음")'
mutfail "ⓜM2 NEXT = 첫 PR(대기 규칙 지움) → ⑥ 의 «대기(VALID …)» 0 = FAIL" "NEXT 대기(VALID PR 71 착지 뒤"
oksrc "ⓜM2 원본 재확인 → ⑥ 통과" "NEXT 대기(VALID PR 71 착지 뒤"
echo "단계 초: M2 $((SECONDS - S0))s"

# ===== M3: 같음 비교를 PR 바뀐 파일만으로 → ⑦ FAIL =====
qreset
qm 74 pr74 "$(tmn 20)" worker/p74.py=p74
vbs "$(setof "$(sha "$REPO" pr74)")" 20261117-142000
adv worker/aa74.py=landed74
mut M3 verify 'pick(repo, merge_tree(repo, main, head), specs, upto=main)' 'pick(repo, head, specs, upto=main)'
mutfail "ⓜM3 비교 대상을 «지금 main + PR» 이 아니라 PR 단독으로(planner 보기 ⓑ 꼴) → ⑦ 이 VALID 로 보인다 = FAIL" "PR #74 STALE"
oksrc "ⓜM3 원본 재확인 → ⑦ STALE 통과" "PR #74 STALE"
echo "단계 초: M3 $((SECONDS - S0))s"

# ===== M4: 음성 경로 아닌 착지도 STALE(트리 전체 비교) → ⑧ FAIL =====
qreset
qm 81 pr81 "$(tmn 20)" worker/p81.py=p81
vbs "$(setof "$(sha "$REPO" pr81)")" 20261117-143000
adv docs/nonvoice.md=nnn
mut M4 verify 'rc, _ = run(repo, "diff", "--quiet", a, b, "--", *specs)' 'rc, _ = run(repo, "diff", "--quiet", a, b)'
mutfail "ⓜM4 같음 비교에서 음성 경로 글롭을 뺌(음성 경로 아닌 착지도 무효) → ⑧ VALID 0 = FAIL" "PR #81 VALID"
oksrc "ⓜM4 원본 재확인 → ⑧ VALID 통과" "PR #81 VALID"
echo "단계 초: M4 $((SECONDS - S0))s"

# ===== 격리 =====
[ "$(git -C "$ORIGIN" rev-parse --is-bare-repository)" = true ] && [[ "$ORIGIN" == "$T/"* ]]; ck "격리: 원격 = 임시 bare 1개(실 원격·실 gh 0)" $?
echo "단계 초: 전체 $((SECONDS - S0))s"
echo "== $([ "$fail" = 0 ] && echo OK || echo "FAIL $fail") =="
[ "$fail" = 0 ]
