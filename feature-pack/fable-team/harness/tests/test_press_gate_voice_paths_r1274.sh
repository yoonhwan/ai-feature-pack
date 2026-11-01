#!/usr/bin/env bash
# test_press_gate_voice_paths_r1274.sh — r1274: press 증거 게이트 대상 = BYZ 정본 «음성 경로 목록»(docs/rules/press_voice_paths.md «## 목록») 만 · 배포 경로(cd-dev.yml) 아님
#   반례 R1~R9(카드 동결 집합) · 변이 1~5(변이마다 바꾼 verify.py 사본으로 같은 입력을 돌려 «계약 깨짐»이 재현되는지 본다)
#   임시 origin(bare) · BYZ 꼴 URL 은 날 값 + url.insteadOf · gh 스텁 · 실 gh·실 원격 0 · 네트워크 0 · 자기 재호출은 real_state_guard 재진입 표지 하나뿐
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/_press_evidence_fixture.sh"

A='gateway/routes/v5/**'; B='clients/web/src/domains/realtime/**'   # 목록 글롭 둘 · A 경로 파일 = gateway/routes/v5/*.py · B 경로 파일 = clients/web/src/domains/realtime/*.ts
LIST=docs/rules/press_voice_paths.md; VP="$BIN/press_evidence_verify.py"
list_md() { printf '# 음성 경로 목록(시험)\n## 목록\n<!-- 한 줄에 글롭 하나 -->\n'; for g in "$@"; do printf -- '- `%s`\n' "$g"; done; }
mut() {  # mut <사본 폴더> <바꿀 줄> <새 줄> [<바꿀 줄 2> <새 줄 2>] — bin 을 심링크로 깔고 verify.py 만 바꾼 사본
  local d="$1"; mkdir -p "$d"; for f in "$BIN"/*; do ln -s "$f" "$d/$(basename "$f")"; done; rm -f "$d/press_evidence_verify.py"
  python3 - "$VP" "$d/press_evidence_verify.py" "${@:2}" <<'PY' || { echo "FAIL 변이 대상 없음 $d"; exit 1; }
import sys
s = open(sys.argv[1], encoding="utf-8").read(); a = sys.argv[3:]
for o, n in zip(a[0::2], a[1::2]):
    assert o in s, o
    s = s.replace(o, n, 1)
open(sys.argv[2], "w", encoding="utf-8").write(s)
PY
}
outside() { [ "$rc" = 0 ] && [[ "$out" == *"press 증거 대상 밖(음성 경로 변경 0)"* ]]; }   # chk 결과가 «대상 밖» 통과
landed_out() { [ "$rc" = 0 ] && [[ "$out" == *"LANDED pr=$1 "* ]] && [[ "$out" == *"press 증거 대상 밖(음성 경로 변경 0)"* ]]; }

# ===== 사전: 문법 · 짝 사본 · 줄 수 · 모드 =====
python3 -m py_compile "$VP" "$BIN/press_evidence_land.py"; ck "py_compile verify·land" $?
for f in press_evidence_verify.py press_evidence_land.py ft-press-evidence.sh; do cmp -s "$BIN/$f" "$KIT/$f" || { echo "  짝 다름 $f"; false; }; done; ck "짝 사본 bin·kit cmp0" $?
[ "$(wc -l < "$VP" | tr -d ' ')" -le 300 ]; ck "verify.py ≤ 300줄" $?
[ ! -x "$HERE/$(basename "${BASH_SOURCE[0]:-$0}")" ]; ck "이 시험 파일 모드 100644(실행 비트 0)" $?
echo "단계 초: 사전 $((SECONDS - T_START))s"

# ===== 준비: main 목록 = A·B =====
adv "$LIST=$(list_md "$A" "$B")"; M0="$(omain)"; [ -n "$M0" ]; ck "준비: main 목록 A·B" $?

# ===== R1·R2·R3: 음성 경로 밖 PR(위 5건 꼴) → «대상 밖» 착지 =====
mkpr 1 b1 "clients/web/src/components/credit/a.tsx=x"; land "$LAND" 1 --approve-sha "$PRSHA"; landed_out 1; ck "R1 graphics 5625 꼴(components/credit) → 대상 밖 · 착지" $?
mkpr 2 b2 "gateway/domains/credit/a.py=x" "gateway/infrastructure/repositories/pg_org_subscription_x.py=x" "gateway/routes/api/v1/profile_location.py=x" "clients/web/src/components/admin/credits/a.tsx=x"
land "$LAND" 2 --approve-sha "$PRSHA"; landed_out 2; ck "R2 cfo 5667·ops 5399·5688 꼴(gateway credit·profile · admin/credits) → 대상 밖 · 착지" $?
brn b3; printf '\n# r3\n' >> "$REPO/.github/workflows/cd-dev.yml"; put tests/ops/t3.py x; cm "$REPO" "pr 3"; pushpr 3 b3
land "$LAND" 3 --approve-sha "$PRSHA"; landed_out 3; ck "R3 ops 5615 꼴(cd-dev.yml · tests/ops) → 대상 밖 · 착지" $?
# 변이 1: 목록 대신 cd-dev.yml 유지 → R1 꼴 PR 이 막힘(대상 밖 계약 깨짐)
mkpr 11 b11 "clients/web/src/components/credit/m.tsx=m"; P11="$PRSHA"; chk "$P11"; outside; ck "R1 꼴 새 PR(직접 chk) → 대상 밖" $?
mut "$T/mut1" 'if os.environ.get("FT_PRESS_SCOPE") == "deploy":' 'if True:'; CHK_BIN="$T/mut1" chk "$P11"; [ "$rc" = 1 ] && [[ "$out" == *"press 증거 없음/틀림"* ]]; ck "ⓜ변이 1(목록 대신 cd-dev.yml 유지) → R1 꼴 REJECT = 계약 깨짐 재현" $?
echo "단계 초: R1~R3·변이 1 $((SECONDS - T_START))s"

# ===== R4: 음성 경로 파일 + 묶음 없음 → REJECT(지금 그대로) · 묶음 있으면 OK =====
mkpr 4 b4 "clients/web/src/domains/realtime/x.ts=x"; P4="$PRSHA"; M4="$(omain)"; land "$LAND" 4 --approve-sha "$P4"
rejected "press 증거 없음/틀림: 묶음 없음" "$M4"; ck "R4 음성 경로 파일 · 묶음 0 → REJECT(main 불변)" $?
pk "$P4" r4; ck "R4 pack rc0" $rc; land "$LAND" 4 --approve-sha "$P4"
[ "$rc" = 0 ] && [[ "$out" == *"press 증거 OK 세트 ${P4:0:10} run r4"* ]] && [[ "$out" == *"LANDED pr=4 "* ]]; ck "R4 같은 PR + 통과 묶음 → 묶음 검사 OK · 착지" $?

# ===== R5: 목록 파일 없음 · 빈 목록 → 판정 불가 REJECT =====
brn b50; git -C "$REPO" rm -q "$LIST"; put clients/web/src/domains/realtime/n.ts x; cm "$REPO" "pr 50"; pushpr 50 b50; P50="$PRSHA"
chk "$P50"; [ "$rc" = 1 ] && [[ "$out" == *"판정 불가: 음성 경로 목록 없음("*":$LIST)"* ]]; ck "R5 목록 파일 없음 → REJECT «판정 불가: 음성 경로 목록 없음»" $?
mkpr 51 b51 "$LIST=$(list_md)" "clients/web/src/domains/realtime/n2.ts=x"; chk "$PRSHA"; [ "$rc" = 1 ] && [[ "$out" == *"판정 불가: 음성 경로 목록 없음("* ]]; ck "R5 빈 목록(주석뿐) → REJECT «판정 불가: 음성 경로 목록 없음»" $?
mut "$T/mut2" 'if not patterns(repo, revs[0]):' 'if False:' 'set().union(*(patterns(repo, r) for r in revs))' 'patterns(repo, revs[0])' 'rc, _ = run(repo, "diff", "--quiet", a, b, "--", *specs)' 'rc, _ = (0, 0) if not specs else run(repo, "diff", "--quiet", a, b, "--", *specs)'
CHK_BIN="$T/mut2" chk "$P50"; outside; ck "ⓜ변이 2(목록 없음 = 빈 목록 통과) → R5 «대상 밖» 통과 = 계약 깨짐 재현" $?
echo "단계 초: R4·R5·변이 2 $((SECONDS - T_START))s"

# ===== R6: PR 이 목록에서 A 만 지우고 A 경로 코드를 바꿈 → main 목록 ∪ head 목록 = 대상 → REJECT =====
mkpr 6 b6 "$LIST=$(list_md "$B")" "gateway/routes/v5/a6.py=x"; P6="$PRSHA"; M6="$(omain)"; land "$LAND" 6 --approve-sha "$P6"
rejected "press 증거 없음/틀림" "$M6"; ck "R6 목록에서 A 지우고 A 경로 변경 → REJECT(main 목록 ∪ head 목록)" $?
mkpr 66 b66 "$LIST=$(list_md "$A" "$B" 'worker/new/**')" "worker/new/x.py=x"; chk "$PRSHA"; [ "$rc" = 1 ] && [[ "$out" == *"press 증거 없음/틀림"* ]]; ck "R6 PR 이 목록에 새 글롭 추가 + 그 경로 변경 → 대상(합집합) → REJECT" $?
mut "$T/mut3" 'set().union(*(patterns(repo, r) for r in revs))' 'patterns(repo, revs[0])'; CHK_BIN="$T/mut3" chk "$P6"; outside; ck "ⓜ변이 3(합집합 대신 head 목록만) → R6 «대상 밖» 통과 = 계약 깨짐 재현" $?

# ===== R7: env FT_PRESS_SCOPE=deploy → 옛 cd-dev.yml 범위(R1 꼴이 지금처럼 REJECT) =====
export FT_PRESS_SCOPE=deploy; chk "$P11"; unset FT_PRESS_SCOPE; [ "$rc" = 1 ] && [[ "$out" == *"press 증거 없음/틀림"* ]]; ck "R7 FT_PRESS_SCOPE=deploy → R1 꼴 REJECT(옛 범위)" $?
echo "단계 초: R6·R7·변이 3 $((SECONDS - T_START))s"

# ===== R9: 묶음 세트 E 목록 = A·B · 배포 커밋 C 가 목록에서 A 만 지우고 A 경로 코드 변경 → deploy·land 둘 다 REJECT =====
mkpr 9 b9 "clients/web/src/domains/realtime/e9.ts=e"; E9="$PRSHA"; pk "$E9" r9; ck "R9 준비: 세트 E 묶음 pack rc0" $rc
git -C "$REPO" checkout -q -B bc9 "$E9"; put "$LIST" "$(list_md "$B")"; put gateway/routes/v5/c9.py c; cm "$REPO" "deploy C"; C9="$(sha "$REPO" HEAD)"
out="$(python3 "$VP" deploy --commit "$C9" --repo "$REPO" 2>&1)"; rc=$?; [ "$rc" = 1 ] && [[ "$out" == *"press 증거 없음/틀림"* ]]; ck "R9 deploy: C 가 A 지움 + A 경로 변경 → REJECT(비교 목록 = C 목록 ∪ E 목록)" $?
chk "$C9"; [ "$rc" = 1 ] && [[ "$out" == *"press 증거 없음/틀림"* ]]; ck "R9 같은 입력 land(check) → REJECT" $?
mut "$T/mut5" 'both = sorted(set(specs).union({":(glob)" + p for p in patterns(repo, e)}))' 'both = sorted(set(specs))'
out="$(python3 "$T/mut5/press_evidence_verify.py" deploy --commit "$C9" --repo "$REPO" 2>&1)"; rc=$?; [ "$rc" = 0 ] && [[ "$out" == *"press 증거 OK"* ]]; ck "ⓜ변이 5(pick 의 E 목록 합집합 제거) → R9 deploy 통과 = 계약 깨짐 재현" $?
echo "단계 초: R9·변이 5 $((SECONDS - T_START))s"

# ===== R8: 목록에 정상 «- `B`» 줄 + 닫는 백틱 빠진 «- `A» 줄 · A 경로 코드 변경 → 판정 불가 REJECT (main 목록 = B 만) =====
adv "$LIST=$(list_md "$B")"
mkpr 8 b8 "$LIST=$(list_md "$B"; printf -- '%s\n' '- `gateway/routes/v5/**')" "gateway/routes/v5/a8.py=x"; P8="$PRSHA"
chk "$P8"; [ "$rc" = 1 ] && [[ "$out" == *"판정 불가: 음성 경로 목록 꼴 틀림("*":"[0-9]*")"* ]]; ck "R8 꼴 틀린 줄(닫는 백틱 없음) → REJECT «판정 불가: 음성 경로 목록 꼴 틀림(<rev>:<줄>)»" $?
mut "$T/mut4" 'raise Reject("판정 불가: 음성 경로 목록 꼴 틀림(%s:%d)" % (rev[:10], n))' 'continue'; CHK_BIN="$T/mut4" chk "$P8"; outside; ck "ⓜ변이 4(꼴 틀린 줄 건너뜀) → R8 «대상 밖» 통과 = 계약 깨짐 재현" $?
echo "단계 초: R8·변이 4 $((SECONDS - T_START))s"

# ===== 격리 =====
[ "$(git -C "$ORIGIN" rev-parse --is-bare-repository)" = true ] && [[ "$ORIGIN" == "$T/"* ]] && ! grep -q BADVERB "$STUB_LOG"; ck "격리: 원격 = 임시 bare 1개(실 원격·실 gh 0)" $?
echo "단계 초: 전체 $((SECONDS - T_START))s"
echo "== $([ "$fail" = 0 ] && echo OK || echo "FAIL $fail") =="
[ "$fail" = 0 ]
