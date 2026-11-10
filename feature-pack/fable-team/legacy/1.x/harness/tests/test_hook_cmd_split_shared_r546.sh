#!/usr/bin/env bash
# test_hook_cmd_split_shared_r546.sh — 실행 전 Bash 훅 4 + 공용 모듈 1 (r546 · r532 합치기 제안 2 · 1단계)
# 왜: op-vault-develop-gate·tracked-bin-call-gate 가 «명령 조각내기» 사본을, autonomy 2 가 «env argv 분해» 사본을 각자 들고 있었다.
#     한 곳을 고치면 나머지 사본은 옛 판으로 남는다 — 글자까지 같은 사본만 공용 모듈 merge_cmd.py 의 함수 하나로 모았다(막는 기준 변경 0).
# ⓐ 바꾸기 전 판정 원문(픽스처 = 4훅×30명령×자율 off/on=240줄) ⓑ 바꾼 판정 == 그 원문(diff 0) ⓒ segments 등가 ⓓ env_split 등가
# ⓔ 모듈 없음 = rc2 + «merge_cmd 없음»(조용히 통과 0) ⓕ 기존 시험 5종 base 대조(새 FAIL 0)
# 격리: 임시 HOME·임시 루트·임시 훅 폴더 · 외부 호출 0 · 실 settings·실 상태 파일 쓰기 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."; KIT="$ROOT/harness/kit"; HK="$KIT/fable-team/templates/hooks"; FX="$HERE/fixtures/r546_hook_cmd_split"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:240}"; fail=$((fail+1)); fi; }

T="$(cd -- "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home" "$T/nomod"

# ===== ⓐ 바꾸기 전 판정 원문 — 4훅 × 30명령 × 자율 off/on = 240줄 =====
[ "$(wc -l < "$FX/base_verdicts.tsv" | tr -d ' ')" = 240 ]; ck "ⓐ base 판정 원문 240줄($FX/base_verdicts.tsv)" $?
[ "$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))))' "$FX/commands.json")" = 30 ]; ck "ⓐ 명령 묶음 30개(따옴표·\$(·백틱·;&|·줄바꿈·env -S 섞음)" $?
for h in op-vault-develop-gate.sh tracked-bin-call-gate.sh autonomy-merge-guard.sh autonomy-state-guard.sh; do
  [ "$(awk -F'\t' -v h="$h" '$1==h' "$FX/base_verdicts.tsv" | wc -l | tr -d ' ')" = 60 ] && [ "$(awk -F'\t' -v h="$h" '$1==h && $5!="allow"' "$FX/base_verdicts.tsv" | wc -l | tr -d ' ')" -gt 0 ]
  ck "ⓐ $h 원문 60줄 + 막는 판정 1개 이상" $?
done

# ===== ⓑ 바꾼 판정 == 바꾸기 전 원문 =====
python3 "$HERE/lib/r546_verdicts.py" "$KIT/hooks" "$HK" > "$T/now.tsv"; rc=$?
ck "ⓑ 기록기 실행(설치 꼴 임시 폴더 · 훅4+모듈1)" "$rc"
[ "$(wc -l < "$T/now.tsv" | tr -d ' ')" = 240 ]; ck "ⓑ 지금 판정 240줄" $?
cmp -s "$T/now.tsv" "$FX/base_verdicts.tsv"; ck "ⓑ 4훅×30명령×off/on 판정 base 대조 diff 0(rc·종류·stderr 첫 줄)" $?

# ===== ⓒ segments · ⓓ env_split 등가(옛 사본 원문 = fixtures/base_functions.py) =====
python3 - "$KIT/hooks" "$FX" <<'PY'
import json, os, shlex, sys
sys.path.insert(0, sys.argv[1]); sys.path.insert(0, sys.argv[2])
import base_functions as base, merge_cmd as mc
cmds = json.load(open(os.path.join(sys.argv[2], "commands.json"), encoding="utf-8"))
bad = [i for i, c in enumerate(cmds) if mc.segments(c) != base.segments(c)]
print(f"ⓒ segments 불일치 {len(bad)}/{len(cmds)} {bad}")
bad2 = []
for i, c in enumerate(cmds):
    for args in (["-S", c], ["--split-string=" + c], ["-S" + c]):
        prog = os.path.basename(args[0])
        if mc.env_split(prog, args) != base.env_split(prog, args):
            bad2.append(i)
print(f"ⓓ env_split 불일치 {len(bad2)}/{3 * len(cmds)} {bad2}")
sys.exit(0 if not bad and not bad2 else 1)
PY
rc=$?
ck "ⓒ segments 30개 · ⓓ env_split 90개 출력 동일" "$rc"

# ===== ⓔ 모듈 없음 = 막음(rc2 + «merge_cmd 없음») — 조용히 통과 0 =====
for h in op-vault-develop-gate.sh tracked-bin-call-gate.sh autonomy-merge-guard.sh autonomy-state-guard.sh; do
  src="$KIT/hooks/$h"; [ -f "$src" ] || src="$HK/$h"
  cp "$src" "$T/nomod/$h"
  out="$(printf '%s' '{"tool_name":"Bash","cwd":"/tmp","tool_input":{"command":"ls"}}' | HOME="$T/home" bash "$T/nomod/$h" 2>"$T/err")"; rc=$?
  [ "$rc" = 2 ] && grep -q 'merge_cmd 없음' "$T/err" && ! grep -q '"deny"' <<<"$out"; ck "ⓔ $h 모듈 없음 → rc2 + stderr «merge_cmd 없음»" $?
done

# ===== ⓕ 기존 시험 5종 — base 대조(FAIL 수를 늘리지 않았다 · base 값 = 2026-10-20 r546 착수 시점) =====
#   r546 이전에도 test_tracked_bin_call_gate 는 25 FAIL(ⓖ live-entry 계열 · 이 카드와 무관) — 0 이 아니라 «그 값 그대로» 가 기준이다.
for pair in test_op_vault_develop_gate:0 test_tracked_bin_call_gate:25 test_autonomy_hooks:0 test_autonomy_merge_equiv:0 test_merge_head_gate:0; do
  t="${pair%%:*}"; max="${pair#*:}"
  bash "$HERE/$t.sh" > "$T/$t.txt" 2>/dev/null; rc=$?
  n="$(grep -c '^FAIL' "$T/$t.txt")"
  [ "$n" -le "$max" ]; ck "ⓕ $t FAIL $n ≤ base $max" $?
done

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
