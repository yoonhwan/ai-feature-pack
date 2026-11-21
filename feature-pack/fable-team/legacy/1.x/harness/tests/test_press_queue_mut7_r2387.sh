#!/usr/bin/env bash
# test_press_queue_mut7_r2387.sh — r2387 변이 M7: 깨진 묶음 ref 에서 전체를 중단하면 ⑮(그 줄만 판정 불가)가 FAIL 하는가 (하드 룰 22 로 mut2 에서 쪼갬)
#   깨진 묶음 ref 1개 = 부모 없음 · A·C 는 유효 묶음(최신 run 순이라 깨진 ref 앞에서 멈춘다)
#   틀 = _press_queue_r2387_lib.sh · 실 gh·실 원격 0
# 사용: timeout 70 bash <이 파일> → 마지막 줄 «== OK ==» · rc 0/1
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_press_queue_r2387_lib.sh"
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:700}"; fail=$((fail+1)); fi; }
qmut() { : > "$STUB_LOG"; out="$(bash "$1/ft-press-evidence.sh" queue --repo "$REPO" --main "${QMAIN:-origin/main}" 2>&1)"; rc=$?; }
S0=$SECONDS
qreset
qm 111 pr111 40 worker/p111.py=p111
qm 112 pr112 30 worker/p112.py=p112
qm 113 pr113 20 worker/p113.py=p113
vbs "$(setof "$(sha "$REPO" pr111)")" 20261117-151000
vbs "$(setof "$(sha "$REPO" pr113)")" 20261117-150500
bks 0123456789abcdef0123456789abcdef01234567 20261117-150000
mut M7 verify '        except Reject as x:
            r = ("", "판정 불가", " · " + str(x))' '        except Reject as x:
            raise'

# ===== 변이: 깨진 ref 에서 전체 중단 → 다른 줄까지 사라짐 = ⑮ FAIL =====
qmut "$MBIN"
if [ "$rc" = 0 ] && [[ "$out" == *"PR #111 VALID"* ]]; then ck "ⓜM7 깨진 ref 에서 전체 중단 → 다른 줄(#111)까지 사라짐 = ⑮ FAIL" 1; else ck "ⓜM7 깨진 ref 에서 전체 중단 → 다른 줄(#111)까지 사라짐 = ⑮ FAIL" 0; fi
qmut "$BIN"
[ "$rc" = 0 ] && [[ "$out" == *"PR #111 VALID"* ]] && [[ "$out" == *"PR #112 판정 불가"* ]] && [[ "$out" == *"PR #113 VALID"* ]]
ck "ⓜM7 원본 재확인 → ⑮ 통과(깨진 묶음 = 그 줄만 판정 불가 · 같은 사례 1회 더)" $?
git -C "$REPO" update-ref -d refs/press/0123456789abcdef0123456789abcdef01234567-20261117-150000
unref refs/press/0123456789abcdef0123456789abcdef01234567-20261117-150000

# ===== 격리 =====
[ "$(git -C "$ORIGIN" rev-parse --is-bare-repository)" = true ] && [[ "$ORIGIN" == "$T/"* ]]; ck "격리: 원격 = 임시 bare 1개(실 원격·실 gh 0)" $?
echo "단계 초: M7 $((SECONDS - S0))s · 전체 $((SECONDS - S0))s"
echo "== $([ "$fail" = 0 ] && echo OK || echo "FAIL $fail") =="
[ "$fail" = 0 ]
