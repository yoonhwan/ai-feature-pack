#!/usr/bin/env bash
# test_press_evidence_turbopack_row_r1263.sh — r1263: press 증거 묶음 = 4자 표 «| turbopack | build N · runtime N · config N …» 행 필수 · 숫자 = turbopack.txt 원문 판정
#   · 같은 세트에 통과 묶음이 여럿이면 run_id 시각(YYYYMMDD-HHMMSS)이 가장 늦은 것(빚 규칙이 먼저) — 반례 R1~R7.
#   틀 = r1230 픽스처(_press_evidence_fixture.sh · 임시 origin bare · gh 스텁 · 실 원격·실 gh 0) · 착지는 하지 않고 검사(check)·배포 검사(deploy)만.
#   자기 재호출 0(real_state_guard 안 씀 — 상태 폴더는 픽스처가 임시 T 로 묶는다) · 고정 sleep 0 · 네트워크 0.
# 변이: R1263_BIN=<변이 bin 폴더(심볼릭 + 변이 press_evidence_verify.py)> bash <이 파일> → FAIL 이 나와야 한다.
# 사용: timeout 70 bash <이 파일> → 마지막 줄 «== OK ==» · rc 0/1
set -uo pipefail
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/_press_evidence_fixture.sh"
if [ -n "${R1263_BIN:-}" ]; then BIN="$R1263_BIN"; EVT="$BIN/ft-press-evidence.sh"; export CHK_BIN="$BIN"; fi
dep() { out="$(python3 "$BIN/press_evidence_verify.py" deploy --commit "$1" --repo "$REPO" 2>&1)"; rc=$?; }
has() { [[ "$out" == *"$1"* ]]; }

# ===== 사전: 짝 사본 =====
if [ -z "${R1263_BIN:-}" ]; then
  for f in press_evidence_verify.py press_evidence_land.py; do cmp -s "$BIN/$f" "$KIT/$f" || { echo "  짝 다름 $f"; false; }; done; ck "짝 사본 bin·kit cmp0" $?
fi

# ===== R1: 표 turbopack 행 없음(4축·원문 정상) → 거절 «turbopack 칸 없음» · pack 도 거절 =====
mkpr 1 b1 "clients/web/r1.ts=x"; S1="$PRSHA"
pk "$S1" r1p "" "" "" none; [ "$rc" = 1 ] && has "4자 표 turbopack 칸 없음" && [ -z "$(git -C "$ORIGIN" for-each-ref "refs/press/$S1-r1p")" ]; ck "R1 pack 도 행 없음 거절 · ref 0" $?
ev "$T/ev/r1" r1 "" "" "" none; rawpk "$S1" r1; chk "$S1"
[ "$rc" = 1 ] && has "4자 표 turbopack 칸 없음"; ck "R1 행 없음 → 거절 «4자 표 turbopack 칸 없음»" $?

# ===== R2: 행 있음 · 숫자 = 원문 → 통과 · OK 줄 숫자 그대로 =====
mkpr 2 b2 "clients/web/r2.ts=x"; S2="$PRSHA"; pk "$S2" r2; ck "R2 pack rc0" $rc
chk "$S2"; [ "$rc" = 0 ] && has "press 증거 OK 세트 ${S2:0:10} run r2 · ref refs/press/$S2-r2 · turbopack build 0 runtime 1 config 0"; ck "R2 행 = 원문 → 통과 · OK 줄 turbopack 숫자" $?

# ===== R3: 행 있음 · runtime 숫자 다름 → 거절 «숫자 ≠ 원문» =====
mkpr 3 b3 "clients/web/r3.ts=x"; S3="$PRSHA"
ev "$T/ev/r3" r3 "" "" "" "build 0 · runtime 2 · config 0 · 원문 turbopack.txt"; rawpk "$S3" r3; chk "$S3"
[ "$rc" = 1 ] && has "4자 표 turbopack 숫자 ≠ 원문(표 0/2/0 · 원문 0/1/0)"; ck "R3 runtime 다름 → 거절 «숫자 ≠ 원문»" $?
echo "단계 초: R1~R3 $((SECONDS - T_START))s"

# ===== R4: 같은 세트 묶음 둘 — 032437(행 없음) · 035014(행 있음) → 035014 통과 =====
mkpr 4 b4 "clients/web/r4.ts=x"; S4="$PRSHA"
ev "$T/ev/20261101-032437-k9a" 20261101-032437-k9a "" "" "" none; rawpk "$S4" 20261101-032437-k9a; pk "$S4" 20261101-035014-k9a
chk "$S4"; [ "$rc" = 0 ] && has "run 20261101-035014-k9a · ref refs/press/$S4-20261101-035014-k9a"; ck "R4 행 없는 옛 묶음 거절 · 행 있는 늦은 묶음 통과" $?

# ===== R5: 같은 세트 통과 묶음 둘 → 늦은 run · ref 이름순이 시각과 반대인 꼴도 늦은 run =====
mkpr 5 b5 "clients/web/r5.ts=x"; S5="$PRSHA"; pk "$S5" 20261101-032437-k9a; pk "$S5" 20261101-035014-k9a
chk "$S5"; [ "$rc" = 0 ] && has "run 20261101-035014-k9a ·"; ck "R5 이름순 첫 것(이른 run) 대신 늦은 run" $?
mkpr 51 b51 "clients/web/r51.ts=x"; S51="$PRSHA"; pk "$S51" z-20261101-032437; pk "$S51" a-20261101-035014; pk "$S51" nostamp
chk "$S51"; [ "$rc" = 0 ] && has "run a-20261101-035014 ·"; ck "R5 이름순 = 시각 반대 꼴 · 시각 못 읽는 run 은 맨 뒤 → 늦은 run" $?
echo "단계 초: R4~R5 $((SECONDS - T_START))s"

# ===== R6: 빚 1 — 늦은 쪽만 빚 착지를 조상으로 → 늦은 쪽 · 반대 꼴(이른 쪽만 조상) → 이른 쪽(빚 규칙 우선) =====
adv "docs/r6.md=debt-landing"; D="$(omain)"
DC="$(git -C "$REPO" commit-tree "$(git -C "$REPO" mktree </dev/null)" -m "press-debt landed=$D pr=61 reverted=x owner=o ts=0")"; git -C "$REPO" push -q origin "$DC:refs/press-debt/$D"
mkpr 6 b6 "clients/web/r6.ts=x"; L6="$PRSHA"; E6="$(git -C "$REPO" commit-tree "$L6^{tree}" -p "$D^" -m early-set)"
pk "$E6" 20261101-010000-r6; pk "$L6" 20261101-020000-r6
chk "$L6"; [ "$rc" = 0 ] && has "세트 ${L6:0:10} run 20261101-020000-r6"; ck "R6 늦은 쪽만 빚 조상 → 늦은 쪽" $?
git -C "$ORIGIN" update-ref -d "refs/press-debt-paid/$D" 2>/dev/null; git -C "$REPO" update-ref -d "refs/press-debt-paid/$D" 2>/dev/null
mkpr 62 b62 "clients/web/r62.ts=x"; L62="$PRSHA"; E62="$(git -C "$REPO" commit-tree "$L62^{tree}" -p "$D^" -m early-set2)"
pk "$L62" 20261101-010000-r62; pk "$E62" 20261101-020000-r62
chk "$L62"; [ "$rc" = 0 ] && has "세트 ${L62:0:10} run 20261101-010000-r62"; ck "R6 이른 쪽만 빚 조상 → 이른 쪽(빚 규칙이 순서보다 먼저)" $?
git -C "$ORIGIN" update-ref -d "refs/press-debt-paid/$D" 2>/dev/null; git -C "$REPO" update-ref -d "refs/press-debt-paid/$D" 2>/dev/null
echo "단계 초: R6 $((SECONDS - T_START))s"

# ===== R7: 배포 검사(deploy)도 R1 꼴 거절 · R4 꼴은 늦은 묶음 =====
dep "$S1"; [ "$rc" = 1 ] && has "4자 표 turbopack 칸 없음" && has "배포 ${S1:0:10}"; ck "R7 deploy — 행 없는 묶음만 → 거절" $?
dep "$S4"; [ "$rc" = 0 ] && has "run 20261101-035014-k9a" && has "배포 ${S4:0:10}"; ck "R7 deploy — R4 꼴 → 늦은 묶음 통과" $?

# ===== 격리 =====
[ "$(git -C "$ORIGIN" rev-parse --is-bare-repository)" = true ] && [[ "$ORIGIN" == "$T/"* ]] && ! grep -q BADVERB "$STUB_LOG"; ck "격리: 원격 = 임시 bare 1개(실 원격·실 gh 0)" $?
echo "단계 초: 전체 $((SECONDS - T_START))s"
echo "== $([ "$fail" = 0 ] && echo OK || echo "FAIL $fail") =="
[ "$fail" = 0 ]
