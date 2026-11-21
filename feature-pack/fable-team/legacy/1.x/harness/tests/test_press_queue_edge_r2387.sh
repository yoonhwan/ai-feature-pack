#!/usr/bin/env bash
# test_press_queue_edge_r2387.sh — r2387 ⑭⑮⑯⑰: queue 의 «판정 불가» 길과 «다른 길 그대로» (K4·K5)
#   ⑭ 가짜 gh 8초 멈춤 2회 → «판정 불가 PR 목록» 1줄 rc 3 · 호출 2회 · 15초 안 ⑮ 깨진 묶음 ref 1개 = 그 PR 줄만 «판정 불가» · 다른 줄 그대로 · NEXT 는 판정 불가를 건너뛴다
#   ⑯ queue 전후 refs/press* · refs/press-debt* · 작업 트리 · 허가 파일 바이트 같음(쓰기 0) ⑰ 착지 판정 · deploy 판정 · pack 거절 출력이 기준판과 바이트 같음(press_evidence_land.py = 큰 글자 같음)
#   틀 = _press_queue_r2387_lib.sh · 실 gh·실 원격 0
# 사용: timeout 70 bash <이 파일> → 마지막 줄 «== OK ==» · rc 0/1
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_press_queue_r2387_lib.sh"
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc el=${el:-0}s out=${out:0:700}"; fail=$((fail+1)); fi; }
S0=$SECONDS
NB="$(git -C "$ORIGIN" hash-object -t blob -w /dev/null 2>/dev/null)"   # 그냥 객체 1개(아무 뜻 없음)

# ===== ⑭: 가짜 gh 8초 멈춤 2회 → «판정 불가 PR 목록» 1줄 rc 3 · 호출 2회 · 15초 안 =====
qreset; qm 141 pr141 "$(tmn 10)" worker/p141.py=p141
el=$SECONDS; GH_SLEEP=8 qrun; el=$((SECONDS - el))
[ "$rc" = 3 ] && [ "$(printf '%s\n' "$out" | grep -c .)" = 1 ] && [[ "$out" == "판정 불가 PR 목록 — gh pr list 실패("* ]] && [ "$(qgl)" = 2 ] && [ "$el" -le 15 ]
ck "⑭ gh 8초 멈춤 2회 → «판정 불가 PR 목록» 1줄 rc 3 · 호출 2회 · ${el}초(<15)" $?
echo "단계 초: ⑭ ${el}s"

# ===== ⑮: 깨진 묶음 ref 1개 = 그 PR 줄만 «판정 불가» · A·C 줄 그대로 · NEXT 는 판정 불가를 건너뛴다 =====
qreset
qm 111 pr111 "$(tmn 40)" worker/p111.py=p111
qm 112 pr112 "$(tmn 30)" worker/p112.py=p112
qm 113 pr113 "$(tmn 20)" worker/p113.py=p113
vbs "$(setof "$(sha "$REPO" pr111)")" 20261117-121000     # A = 유효 묶음(최신 run)
vbs "$(setof "$(sha "$REPO" pr113)")" 20261117-120500     # C = 유효 묶음(둘째)
bks 0123456789abcdef0123456789abcdef01234567 20261117-120000   # B 앞에 깨진 묶음(부모 없음 · 셋 중 가장 이른 run)
qrun
[ "$rc" = 0 ] && [[ "$out" == *"PR #111 VALID"* ]] && [[ "$out" == *"PR #113 VALID"* ]] && [[ "$out" == *"PR #112 판정 불가 · "* ]] \
  && [[ "$(qnext)" == "대기(VALID PR 111 착지 뒤 · "* ]]; ck "⑮ 깨진 묶음 = #112 줄만 판정 불가 · #111·#113 VALID 그대로 · NEXT 대기(111)" $?
unref refs/press/0123456789abcdef0123456789abcdef01234567-20261117-120000   # 깨진 묶음은 ⑮ 몫 — 다음 사례에서 지운다
qreset
qm 121 pr121 "$(tmn 30)" worker/p121.py=p121
qm 122 pr122 "$(tmn 20)" worker/p122.py=p122
python3 - "$PLIST" <<'PY'   # 121 의 head 를 «로컬에 없는 sha» 로 바꾼다(그 줄만 판정 불가)
import json, sys
p = sys.argv[1]; rows = json.load(open(p))
rows[0]["headRefOid"] = "1234567890abcdef1234567890abcdef12345678"
json.dump(rows, open(p, "w"))
PY
qrun
[ "$rc" = 0 ] && [[ "$out" == *"PR #121 판정 불가 · head 객체 없음"* ]] && [ "$(qnext)" = 122 ]; ck "⑮b 판정 불가 줄은 NEXT 후보가 아니다 — NEXT 122(121 건너뜀)" $?
echo "단계 초: ⑮ $((SECONDS - S0))s"

# ===== ⑯: queue 전후 refs/press* · refs/press-debt* · 작업 트리 · 허가 파일 바이트 같음(쓰기 0) =====
mkdir -p "$T/permits"; printf '{"held":false,"member":""}\n' > "$T/permits/device.json"
qreset
qm 131 pr131 "$(tmn 20)" worker/p131.py=p131
vbs "$(setof "$(sha "$REPO" pr131)")" 20261117-122000
debt "$(sha "$REPO" origin/main)" 61
qrun >/dev/null 2>&1                                  # 1회차 = refs/press 를 로컬로 받아 둔다(그 뒤가 «전후 같음» 의 기준)
snap() { git -C "$REPO" for-each-ref --format='%(refname) %(objectname)' refs/press refs/press-debt refs/press-debt-paid
         git -C "$REPO" status --porcelain; git -C "$REPO" ls-files -s; sha "$REPO" HEAD
         cat "$REPO/docs/rules/press_voice_paths.md"; cat "$T/permits/device.json"; }
B16="$(snap | git hash-object --stdin)"
qrun
A16="$(snap | git hash-object --stdin)"
[ "$A16" = "$B16" ] && [ "$rc" = 0 ]; ck "⑯ queue 전후 refs/press* · press-debt* · 작업 트리 · 허가 파일 바이트 같음(쓰기 0)" $?

# ===== ⑰: 착지 판정 · deploy 판정 · pack 거절 출력 = 기준판과 바이트 같음 =====
cmp -s "$QBB/press_evidence_land.py" "$BIN/press_evidence_land.py"; ck "⑰a press_evidence_land.py(pack·착지·빚) = 기준판과 같은 글자" $?
H131="$(sha "$REPO" pr131)"
landat "$QBB" "$H131"; bout="$out"; brc="$rc"; landat "$BIN" "$H131"
[ "$out" = "$bout" ] && [ "$rc" = "$brc" ]; ck "⑰b 착지 판정 = 기준판과 바이트 같음(rc=$rc)" $?
dpy() { out="$(python3 "${1}/press_evidence_verify.py" deploy --commit "$H131" --repo "$REPO" 2>&1)"; rc=$?; }
dpy "$QBB"; bout="$out"; brc="$rc"; dpy "$BIN"
[ "$out" = "$bout" ] && [ "$rc" = "$brc" ]; ck "⑰c deploy 판정 = 기준판과 바이트 같음(rc=$rc)" $?
pkx() {  # pkx <bin 폴더> — 같은 입력으로 pack 1회(거절이면 push 0) → 같은 글자여야
  ev "$T/evb2" 20261117-123000 "" "worker 줄" "" none >/dev/null 2>&1 || true
  out="$(TERM=dumb bash "${1}/ft-press-evidence.sh" pack "$(sha "$REPO" pr131)" --run 20261117-123000 --poller "$T/evb2/poller_dom.jsonl" --table "$T/evb2/table.md" --turbopack "$T/evb2/turbopack.txt" --repo "$REPO" --remote origin 2>&1)"; rc=$?
}
pkx "$QBB"; bout="$out"; brc="$rc"; pkx "$BIN"
[ "$out" = "$bout" ] && [ "$rc" = "$brc" ]; ck "⑰d pack 거절 출력 = 기준판과 바이트 같음(rc=$rc)" $?

# ===== 격리 =====
[ "$(git -C "$ORIGIN" rev-parse --is-bare-repository)" = true ] && [[ "$ORIGIN" == "$T/"* ]]; ck "격리: 원격 = 임시 bare 1개(실 원격·실 gh 0)" $?
echo "단계 초: ⑯⑰ $((SECONDS - S0))s · 전체 $((SECONDS - S0))s"
echo "== $([ "$fail" = 0 ] && echo OK || echo "FAIL $fail") =="
[ "$fail" = 0 ]
