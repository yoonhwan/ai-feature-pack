#!/usr/bin/env bash
# test_merge_land_dry_press_r1986.sh — r1986 보정(DA#10 HOLD R1 #303171 · arch #303180): 실제 press 도구(스텁 0)로 같은 snapshot dry→land 판정 일치
#   R1a 정확 역변경(빚 기록 push 갈래) · R1b 빚 상환(상환 ref push 갈래) — 각각 dry ALLOW «dry · push 0» ∧ 원격 ref 불변 ∧ 이어서 land LANDED + 원격 ref 생김
#   변이 Mp: press 의 dry 신호 끔 → R1a dry DENY(hook 안전망이 push 를 막아 판정 불일치 재현)
#   임시 origin(bare) · BYZ 꼴 URL(insteadOf) · gh 스텁 · 실 gh·실 원격 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/_press_evidence_fixture.sh"
export FT_CRITICAL_OFF=1
cd "$T" || exit 1   # cwd = 임시 루트(실 리포 cwd 면 대상 URL 판정이 바뀐다 — DA 재현 메모)
oref() { git -C "$ORIGIN" for-each-ref --format='%(refname) %(objectname)'; }
dline() { printf '%s\n' "$out" | grep -m1 -E '^DRY (ALLOW|DENY) '; }
mutp() {  # press_evidence_land.py 의 dry 신호를 끈 bin 사본
  local d="$T/mut-press"; mkdir -p "$d"; for f in "$BIN"/*; do ln -s "$f" "$d/$(basename "$f")"; done; rm -f "$d/press_evidence_land.py"
  sed 's/os.environ.get("FT_LAND_DRY") == "1"/False/' "$BIN/press_evidence_land.py" > "$d/press_evidence_land.py"
  grep -q 'FT_LAND_DRY' "$d/press_evidence_land.py" && { echo "FAIL 변이 대상 없음"; exit 1; }; printf '%s' "$d"
}

python3 -I -c "import ast;ast.parse(open('$BIN/press_evidence_land.py').read())"; ck "py 구문 press_evidence_land" $?
cmp -s "$BIN/press_evidence_land.py" "$KIT/press_evidence_land.py" && cmp -s "$LAND" "$KIT/ft-merge-land.sh"; ck "짝 사본 bin·kit cmp0(press_evidence_land · ft-merge-land)" $?

# ===== 준비: worker 변경 L 착지(통과 묶음) =====
mkpr 100 b100 "worker/l.py=L"; pk "$PRSHA" r100; land "$LAND" 100 --approve-sha "$PRSHA"; L="$(omain)"; [ "$rc" = 0 ]; ck "준비: worker 착지 L" $?

# ===== R1a: 정확 역변경 PR → dry ALLOW(push 0) · 원격 불변 → land LANDED + 빚 ref =====
brn b102; git -C "$W" revert --no-edit "$L" >/dev/null && TITLE="[harness] Revert ${L:0:10}" pushpr 102 b102; A102="$PRSHA"
MP="$(mutp)"; B="$(oref)"; land "$MP/ft-merge-land.sh" 102 --approve-sha "$A102" --dry
[ "$rc" = 1 ] && [[ "$(dline)" == "DRY DENY "*"push"* ]] && [ "$(oref)" = "$B" ]; ck "Mp 변이(press dry 신호 끔) → dry DENY(hook 안전망 · 원격 불변) = R1 불일치 재현" $?
B="$(oref)"; land "$LAND" 102 --approve-sha "$A102" --dry
[ "$rc" = 0 ] && [[ "$out" == *"press 증거 면제 — 정확 역변경(되돌린 ${L:0:10})"*"dry · push 0"* ]] && [[ "$(dline)" == "DRY ALLOW pr=102 "* ]] && [ "$(oref)" = "$B" ]
ck "R1a 정확 역변경 → dry ALLOW «dry · push 0» · 원격 ref 불변(빚 ref 0)" $?
land "$LAND" 102 --approve-sha "$A102"; Q10="$(omain)"
[ "$rc" = 0 ] && [[ "$out" == *"LANDED pr=102 "* ]] && [[ "$out" != *"dry · push 0"* ]] && git -C "$ORIGIN" rev-parse -q --verify "refs/press-debt/$Q10" >/dev/null
ck "R1a 같은 입력 land → LANDED · 원격 refs/press-debt/<착지> 생김(판정 일치)" $?

# ===== R1b: 빚 상환 갈래 → dry ALLOW(상환 push 0) · 원격 불변 → land LANDED + 상환 ref =====
mkpr 110 b110 "worker/n.py=n"; S11="$PRSHA"; pk "$S11" r110
B="$(oref)"; land "$LAND" 110 --approve-sha "$S11" --dry
[ "$rc" = 0 ] && [[ "$out" == *"press 증거 OK 세트 ${S11:0:10} run r110"*"빚 상환 1"*"dry · push 0"* ]] && [[ "$(dline)" == "DRY ALLOW pr=110 "* ]] && [ "$(oref)" = "$B" ]
ck "R1b 빚 상환 → dry ALLOW «dry · push 0» · 원격 ref 불변(상환 ref 0)" $?
land "$LAND" 110 --approve-sha "$S11"
[ "$rc" = 0 ] && [[ "$out" == *"LANDED pr=110 "* ]] && [ "$(sha "$ORIGIN" "refs/press-debt-paid/$Q10")" = "$(sha "$ORIGIN" "refs/press/$S11-r110")" ]
ck "R1b 같은 입력 land → LANDED · 원격 refs/press-debt-paid = 갚은 묶음(판정 일치)" $?

[ "$(git -C "$ORIGIN" rev-parse --is-bare-repository)" = true ] && [[ "$ORIGIN" == "$T/"* ]]; ck "격리: 원격 = 임시 bare 1개(실 원격·실 gh 0)" $?
echo "단계 초: 전체 $((SECONDS - T_START))s"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
