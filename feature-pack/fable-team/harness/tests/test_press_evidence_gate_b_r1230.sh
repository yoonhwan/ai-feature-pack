#!/usr/bin/env bash
# test_press_evidence_gate_b_r1230.sh — r1230(판정 2946): BYZ 배포 경로 착지·배포 = press 증거 묶음(원격 refs/press/<세트>-<run>) 필수
#   반례 R9~R12(카드 동결 집합 뒤 절반 · 앞 절반 = test_press_evidence_gate_r1230.sh) · 변이 1(정확 역변경 patch-id 대조 끔 → R10 섞임 통과)
#   임시 origin(bare) · BYZ 꼴 URL 은 날 값 + url.insteadOf 로 임시 origin 에 묶는다 · gh 스텁 · 실 gh·실 원격 0 · 자기 재호출은 real_state_guard 재진입 표지 하나뿐
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/_press_evidence_fixture.sh"

# ===== R9: docs 만 · design 증거만 · scripts/server 만 → 대상 밖 · 착지 =====
for n in 91:docs/a.md 92:design/t/evidence/a.json 93:scripts/server/run.sh; do
  mkpr "${n%%:*}" "b${n%%:*}" "${n#*:}=z"; land "$LAND" "${n%%:*}" --approve-sha "$PRSHA"
  [ "$rc" = 0 ] && [[ "$out" == *"LANDED pr=${n%%:*} "* ]] && [[ "$out" == *"press 증거 대상 밖(배포 경로 변경 0)"* ]]; ck "R9 ${n#*:} 만 → 대상 밖 · 착지" $?
done
# ===== R10: 정확 역변경 → 통과 + 빚 · 역변경 + 새 worker 줄 섞임(제목 Revert) → REJECT =====
mkpr 100 b100 "worker/l.py=L"; pk "$PRSHA" r100; land "$LAND" 100 --approve-sha "$PRSHA"; L="$(omain)"; [ "$rc" = 0 ]; ck "R10 준비: worker 착지 L" $?
brn b101; git -C "$W" revert --no-edit "$L" >/dev/null && printf 'NEW\n' >> "$W/worker/l.py" && git -C "$W" commit -q --amend -a --no-edit && TITLE="[harness] Revert ${L:0:10}" pushpr 101 b101
M10="$(omain)"; land "$LAND" 101 --approve-sha "$PRSHA"; rejected "press 증거 없음" "$M10"; ck "R10 역변경 + 새 worker 줄(제목 Revert) → REJECT" $?
MUTB="$T/mut-rev"; mkdir -p "$MUTB"; for f in "$BIN"/*; do ln -s "$f" "$MUTB/$(basename "$f")"; done; rm -f "$MUTB/press_evidence_land.py"
python3 - "$BIN/press_evidence_land.py" "$MUTB/press_evidence_land.py" 'and pid(repo, h, h + "^") == want' '' <<'PY' || { echo "FAIL 변이 대상 없음"; exit 1; }
import sys
s = open(sys.argv[1], encoding="utf-8").read(); assert sys.argv[3] in s
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(sys.argv[3], sys.argv[4], 1))
PY
CHK_BIN="$MUTB" chk "$PRSHA" 0000000000000000000000000000000000000001 "Revert"; [ "$rc" = 0 ] && [[ "$out" == *"정확 역변경"* ]]; ck "ⓜ변이 2(patch-id 대조 끔) → R10 섞임 통과 = 계약 깨짐 재현" $?
git -C "$ORIGIN" update-ref -d refs/press-debt/0000000000000000000000000000000000000001
brn b102; git -C "$W" revert --no-edit "$L" >/dev/null && TITLE="[harness] Revert ${L:0:10}" pushpr 102 b102
land "$LAND" 102 --approve-sha "$PRSHA"; Q10="$(omain)"
[ "$rc" = 0 ] && [[ "$out" == *"press 증거 면제 — 정확 역변경(되돌린 ${L:0:10}) · 빚 refs/press-debt/${Q10:0:10} · 담당 byz-harness-master-claude#9"* ]] && [[ "$out" == *"LANDED pr=102 "* ]] \
  && git -C "$ORIGIN" log -1 --format=%B "refs/press-debt/$Q10" | grep -q "pr=102 reverted=$L owner=byz-harness-master-claude#9" && tail -n1 "$T/state/merge-gate.log" | grep -q " press=revert:${L:0:10}$"
ck "R10 정확 역변경 → 통과 · 원격 빚 ref(PR·되돌린 sha·담당) · merge-gate.log press=revert" $?
echo "단계 초: R9~R10 $((SECONDS - T_START))s"

# ===== R11: 다른 머신 사본에서 빚 조회 · 조상 아닌 세트 → REJECT «press 빚» · 조상 세트 → 통과 + 상환 ref · fetch 실패 → 판정 불가 =====
W2="$T/w2"; git clone -q "$ORIGIN" "$W2" && git -C "$W2" config user.name t && git -C "$W2" config user.email t@t && git -C "$W2" config commit.gpgsign false && byz "$W2"; REPO="$W2"
[ -z "$(git -C "$W2" for-each-ref refs/press-debt/)" ]; ck "R11 사본 리포: 빚 ref 로컬 0(원격에만)" $?
mkpr 110 b110 "worker/n.py=n"; S11="$PRSHA"; E11="$(git -C "$W2" commit-tree "$S11^{tree}" -p "$L" -m stale-set)"; pk "$E11" r110old
land "$LAND" 110 --approve-sha "$S11"; rejected "press 빚 PR #102(착지 ${Q10:0:10}) — 담당 byz-harness-master-claude#9 · 복구 뒤 press 1회" "$Q10"; ck "R11 세트가 빚 착지를 조상으로 안 가짐 → REJECT «press 빚»" $?
pk "$S11" r110; land "$LAND" 110 --approve-sha "$S11"
[ "$rc" = 0 ] && [[ "$out" == *"press 증거 OK 세트 ${S11:0:10} run r110"*"빚 상환 1"* ]] && [ "$(sha "$ORIGIN" "refs/press-debt-paid/$Q10")" = "$(sha "$ORIGIN" "refs/press/$S11-r110")" ]
ck "R11 조상 세트 묶음 → 통과 · 원격 refs/press-debt-paid = 갚은 묶음" $?
mv "$ORIGIN" "$ORIGIN.off"; CHK_MAIN="$Q10" chk "$S11"; mv "$ORIGIN.off" "$ORIGIN"; [ "$rc" = 1 ] && [[ "$out" == *"판정 불가: git fetch 실패(7 s + 재시도 1)"* ]]; ck "R11 fetch 실패 → 판정 불가 REJECT" $?
echo "단계 초: R11 $((SECONDS - T_START))s"

# ===== R12: 배포 직전 검사(press_evidence_verify.py deploy) =====
dep() { out="$(python3 "$BIN/press_evidence_verify.py" deploy --commit "$1" --repo "$W2" 2>&1)"; rc=$?; }
git -C "$W2" fetch -q origin; git -C "$W2" checkout -q -B d1 origin/main; put worker/d.py d; cm "$W2" "worker no bundle"; DW="$(sha "$W2" HEAD)"
dep "$DW"; [ "$rc" = 1 ] && [[ "$out" == *"press 증거 없음/틀림"*"배포 ${DW:0:10}"* ]]; ck "R12 묶음 없는 worker 커밋 → 실패(배포 0)" $?
put docs/d.md d; cm "$W2" "doc on top"; dep "$(sha "$W2" HEAD)"; [ "$rc" = 1 ]; ck "R12 묶음 없는 worker 위 문서 커밋 → 실패" $?
dep "$S11"; [ "$rc" = 0 ] && [[ "$out" == *"press 증거 OK 세트 "*"배포 ${S11:0:10}"* ]]; ck "R12 묶음 있는 세트 → 통과" $?
git -C "$W2" checkout -q -B d2 "$S11"; put docs/e.md e; cm "$W2" "doc on bundle"; dep "$(sha "$W2" HEAD)"; [ "$rc" = 0 ]; ck "R12 묶음 있는 세트 위 문서 커밋 → 통과" $?
git -C "$ORIGIN" update-ref -d "refs/press-debt-paid/$Q10"; E12="$(git -C "$W2" commit-tree "$Q10^{tree}" -p "$L" -m stale-q10)"; pk "$E12" r12; dep "$Q10"; [ "$rc" = 1 ] && [[ "$out" == *"press 빚 PR #102"* ]]; ck "R12 미상환 빚 착지 위 배포(상환 묶음 0) → 실패" $?

# ===== 격리 =====
[ "$(git -C "$ORIGIN" rev-parse --is-bare-repository)" = true ] && [[ "$ORIGIN" == "$T/"* ]] && ! grep -q BADVERB "$STUB_LOG"; ck "격리: 원격 = 임시 bare 1개(실 원격·실 gh 0)" $?
echo "단계 초: 전체 $((SECONDS - T_START))s"
echo "== $([ "$fail" = 0 ] && echo OK || echo "FAIL $fail") =="
[ "$fail" = 0 ]
