#!/usr/bin/env bash
# test_press_evidence_gate_r1230.sh — r1230(판정 2946): BYZ 배포 경로 착지·배포 = press 증거 묶음(원격 refs/press/<세트>-<run>) 필수
#   반례 R1~R8(카드 동결 집합 앞 절반 · 뒤 절반 R9~R12 = test_press_evidence_gate_b_r1230.sh) · 변이 1(배포 경로 트리 대조 끔 → R5 통과) · 기준판(r1230 직전 팩 main 고정 sha = R2 꼴 착지됨)
#   임시 origin(bare) · BYZ 꼴 URL 은 날 값 + url.insteadOf 로 임시 origin 에 묶는다 · gh 스텁 · 실 gh·실 원격 0 · 자기 재호출은 real_state_guard 재진입 표지 하나뿐
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/_press_evidence_fixture.sh"

# ===== 사전: 문법 · 줄 수 · 짝 사본 · 모드 =====
bash -n "$LAND" && bash -n "$EVT"; ck "bash -n ft-merge-land.sh·ft-press-evidence.sh" $?
[ "$(wc -l < "$LAND" | tr -d ' ')" -le 120 ] && [ "$(wc -l < "$EVT" | tr -d ' ')" -le 200 ]; ck "ft-merge-land.sh ≤ 120줄 · ft-press-evidence.sh ≤ 200줄" $?
for f in ft-merge-land.sh ft-press-evidence.sh press_evidence_verify.py press_evidence_land.py; do cmp -s "$BIN/$f" "$KIT/$f" || { echo "  짝 다름 $f"; false; }; done; ck "짝 사본 bin·kit cmp0 (4파일)" $?
for f in ft-press-evidence.sh press_evidence_verify.py press_evidence_land.py; do [ ! -x "$BIN/$f" ] || { echo "  실행 비트 $f"; false; }; done; ck "새 파일 실행 비트 0(100644)" $?
echo "단계 초: 사전 $((SECONDS - T_START))s"

# ===== 기준판: r1230 직전 팩 main 판 = worker 변경 + 묶음 없음도 착지(게이트 0 재현) =====
BASE_SHA=13fd93322fe99bf1e52a99390932733ba087c6c9
TOP="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)" && TOP="$(cd "$TOP" && pwd -P)"; PFX="$(cd "$HERE/.." && pwd -P)"; PFX="${PFX#$TOP/}"; mkdir -p "$T/red"
if [ -n "$TOP" ] && git -C "$TOP" cat-file -e "$BASE_SHA^{commit}" 2>/dev/null; then
  for f in "$BIN"/*; do ln -s "$f" "$T/red/$(basename "$f")"; done; rm -f "$T/red/ft-merge-land.sh"
  git -C "$TOP" show "$BASE_SHA:$PFX/bin/ft-merge-land.sh" > "$T/red/ft-merge-land.sh" && [ -s "$T/red/ft-merge-land.sh" ] || { echo "FAIL 기준판을 못 꺼냄"; exit 1; }
  mkpr 20 b20 "worker/base.py=x"; land "$T/red/ft-merge-land.sh" 20 --approve-sha "$PRSHA"
  [ "$rc" = 0 ] && [[ "$out" == *"LANDED pr=20 "* ]] && [[ "$out" != *"press 증거"* ]]; ck "기준판: worker 변경 · 묶음 0 → 그대로 착지(검사 0 재현)" $?
else echo "SKIP 기준판 칸 — base_sha $BASE_SHA 객체 없음"; fi

# ===== R1: clients/web 변경 + 묶음(세트 = S) → OK 1줄 · 착지 · 기록 3곳 =====
mkpr 1 b1 "clients/web/a.ts=x"; A1="$PRSHA"; pk "$A1" r1; ck "R1 pack rc0" $rc
land "$LAND" 1 --approve-sha "$A1"
[ "$rc" = 0 ] && [[ "$out" == *"press 증거 OK 세트 ${A1:0:10} run r1 · ref refs/press/$A1-r1 · turbopack build 0 runtime 1 config 0"* ]] && [[ "$out" == *"LANDED pr=1 "* ]] \
  && tail -n1 "$T/state/merge-gate.log" | grep -q " press=ok:${A1:0:10}:r1$" && grep -q "press 증거 OK 세트 ${A1:0:10}" "$STUB_LOG"
ck "R1 → OK 줄 · 착지 · merge-gate.log press=ok · PR 코멘트" $?
# ===== R2·R3: worker · pyproject.toml 만 + 묶음 없음 → REJECT =====
mkpr 2 b2 "worker/x.py=y"; A2="$PRSHA"; M2="$(omain)"; land "$LAND" 2 --approve-sha "$A2"
rejected "press 증거 없음/틀림: 묶음 없음" "$M2"; ck "R2 worker · 묶음 0 → REJECT(main 불변)" $?
mkpr 3 b3 "pyproject.toml=[p]"; land "$LAND" 3 --approve-sha "$PRSHA"; rejected "press 증거 없음/틀림" "$M2"; ck "R3 pyproject.toml 만 → REJECT(표 = cd-dev.yml)" $?
# ===== R4: 다른 리포(cwd = 팩 꼴 리포)에서 --repo BYZ 로 검사 → 리포로 판정 = REJECT =====
mkdir -p "$T/pack" && git -C "$T/pack" init -q && out="$(cd "$T/pack" && bash "$EVT" check --repo "$W" --main "$M2" --head "$A2" --landing "$A2" --pr 2 2>&1)"; rc=$?
[ "$rc" = 1 ] && [[ "$out" == *"press 증거 없음"* ]]; ck "R4 CROSS(cwd 다른 리포) → REJECT" $?
echo "단계 초: 기준판+R1~R4 $((SECONDS - T_START))s"

# ===== R5: AP 묶음 + S = AP 위 main 병합 · main 쪽 worker → REJECT · docs 만 → OK =====
mkpr 5 b5 "clients/web/b5.ts=x"; A5="$PRSHA"; pk "$A5" r5; adv "worker/m5.py=main"; M5="$(omain)"
git -C "$W" checkout -q b5 && git -C "$W" merge -q --no-edit origin/main && pushpr 5 b5; S5="$PRSHA"
land "$LAND" 5 --approve-sha "$A5"; rejected "press 증거 없음/틀림: 묶음 없음" "$M5"; ck "R5 main 쪽 worker 병합 → REJECT(배포 경로 트리 다름)" $?
MUTA="$T/mut-tree"; mkdir -p "$MUTA"; for f in "$BIN"/*; do ln -s "$f" "$MUTA/$(basename "$f")"; done; rm -f "$MUTA/press_evidence_verify.py"
python3 - "$BIN/press_evidence_verify.py" "$MUTA/press_evidence_verify.py" 'if not same(repo, git(repo, "rev-parse", c + "^").strip(), target, specs):' 'if False:' <<'PY' || { echo "FAIL 변이 대상 없음"; exit 1; }
import sys
s = open(sys.argv[1], encoding="utf-8").read(); assert sys.argv[3] in s
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(sys.argv[3], sys.argv[4], 1))
PY
CHK_BIN="$MUTA" chk "$S5"; [ "$rc" = 0 ]; ck "ⓜ변이 1(배포 경로 트리 대조 끔) → R5 통과 = 계약 깨짐 재현" $?
mkpr 6 b5d "clients/web/b5d.ts=x"; A5D="$PRSHA"; pk "$A5D" r5d; adv "docs/m5.md=doc"
git -C "$W" checkout -q b5d && git -C "$W" merge -q --no-edit origin/main && pushpr 6 b5d
land "$LAND" 6 --approve-sha "$A5D"; [ "$rc" = 0 ] && [[ "$out" == *"press 증거 OK 세트 ${A5D:0:10} run r5d"* ]] && [[ "$out" == *"LANDED pr=6 "* ]]; ck "R5 main 쪽 docs 만 → OK · 착지" $?
# ===== R6·R7·R8: 결속·칸 틀린 묶음 → REJECT(pack 도 거절) =====
mkpr 7 b7 "clients/web/c7.ts=x"; A7="$PRSHA"; M7="$(omain)"
pk "$A7" r6 '{"axis":"conn","epoch_ms":1,"run_id":"other"}'; [ "$rc" = 1 ] && [ -z "$(git -C "$ORIGIN" for-each-ref "refs/press/$A7-r6")" ]; ck "R6 pack 도 run_id 다름 거절 · ref 0" $?
rawpk "$A7" r6; land "$LAND" 7 --approve-sha "$A7"; rejected "poller 1줄 run_id other ≠ 묶음 r6" "$M7"; ck "R6 poller run_id 다름 → REJECT" $?; unref "refs/press/$A7-r6"
ev "$T/ev/r6b" r6b '{}'; rawpk "$A7" r6b; land "$LAND" 7 --approve-sha "$A7"; rejected "poller 1줄 필수 칸(axis·epoch_ms) 빔" "$M7"; ck "R6 poller 첫 줄 {} → REJECT" $?; unref "refs/press/$A7-r6b"
ev "$T/ev/r7" r7 "" "-"; rawpk "$A7" r7; land "$LAND" 7 --approve-sha "$A7"; rejected "4자 표 칸 빔: 로그" "$M7"; ck "R7 로그 칸 «-» → REJECT" $?; unref "refs/press/$A7-r7"
ev "$T/ev/r8" r8; rawpk "$A7" r8 turbopack.txt; land "$LAND" 7 --approve-sha "$A7"; rejected "turbopack.txt 없음" "$M7"; ck "R8 turbopack.txt 없음 → REJECT" $?; unref "refs/press/$A7-r8"
ev "$T/ev/r8b" r8b "" "" "build 0 runtime 0 config 0"; rawpk "$A7" r8b; land "$LAND" 7 --approve-sha "$A7"; rejected "turbopack 원문 없음" "$M7"; ck "R8 건수 줄만(원문 없음) → REJECT" $?; unref "refs/press/$A7-r8b"
echo "단계 초: R5~R8 $((SECONDS - T_START))s"

# ===== 격리 =====
[ "$(git -C "$ORIGIN" rev-parse --is-bare-repository)" = true ] && [[ "$ORIGIN" == "$T/"* ]] && ! grep -q BADVERB "$STUB_LOG"; ck "격리: 원격 = 임시 bare 1개(실 원격·실 gh 0)" $?
echo "단계 초: 전체 $((SECONDS - T_START))s"
echo "== $([ "$fail" = 0 ] && echo OK || echo "FAIL $fail") =="
[ "$fail" = 0 ]
