#!/usr/bin/env bash
# test_proposal_ledger_table_row.sh — 승인 도구(proposal_issue_lib.py ledger)가 게이트(ft-proposal-gate.sh)와 «같은 원장 줄 꼴» 을 읽는가(r765).
#   ⓐ~ⓖ 는 임시 원장 1줄 + 가짜 gh 로만(실 gh 0) · ⓗ 두 도구 대조 · ⓘ 변이 · ⓙ 기존 승인 시험 · ⓚ 격리.
set -uo pipefail
# shellcheck source=_proposal_issue_env.sh
. "$(dirname "${BASH_SOURCE[0]:-$0}")/_proposal_issue_env.sh"
LIB="$PROP/proposal_issue_lib.py"; GATE="$HERE/../bin/ft-proposal-gate.sh"

ledger() { printf '%s\n' "$@" > "$T/planner/VERDICTS-planner-1.md"; }
lib() { out="$(python3 "$LIB" ledger --dir "$T/planner" --repo test/repo "$@" 2>&1)"; rc=$?; }   # --verdict N --issue M
gate() { reset; fx 12 b; out="$(bash "$GATE" --issue 12 2>&1)"; rc=$?; }                          # 같은 원장을 게이트가 읽는다(가짜 gh 픽스처 ⓑ)

# ── ⓐ(빨강 먼저) 표 행 · 인덱스 실측 꼴 ──
ledger '| 2651 | 강의 … (오빠 인터뷰 10-23 · https://github.com/test/repo/issues/2657)'
lib --verdict 2651 --issue 2657
[ "$rc" = 0 ] && ok "ⓐ 표 행(| 2651 | … (오빠 인터뷰 … issues/2657)) → rc 0" || bad "ⓐ rc=$rc $out"

# ── ⓑ 정답 표 행(816/12 · 게이트 대조에 쓰는 같은 입력) ──
ledger '| 816 | 표 행 승인 (오빠 인터뷰 10-23 · Issue https://github.com/test/repo/issues/12): 채택'
lib --verdict 816 --issue 12
[ "$rc" = 0 ] && ok "ⓑ 표 행 「| 816 | … (오빠 인터뷰 … issues/12」 → rc 0" || bad "ⓑ rc=$rc $out"

# ── ⓒ 줄머리 꼴은 그대로 ──
ledger '816 오빠 인터뷰(A안 · Issue https://github.com/test/repo/issues/12): 채택'
lib --verdict 816 --issue 12
[ "$rc" = 0 ] && ok "ⓒ 줄머리 「816 오빠 인터뷰 … issues/12」 → rc 0(그대로)" || bad "ⓒ rc=$rc $out"

# ── ⓓ 표 행인데 «(오빠 인터뷰» 없음 ──
ledger '| 816 | 승인 (인터뷰 10-23 · https://github.com/test/repo/issues/12): 채택'
lib --verdict 816 --issue 12
[ "$rc" = 1 ] && ok "ⓓ 표 행에 «(오빠 인터뷰» 없음 → rc 1" || bad "ⓓ rc=$rc $out"

# ── ⓔ 표 행 번호 다름 ──
ledger '| 8160 | 승인 (오빠 인터뷰 10-23 · https://github.com/test/repo/issues/12): 채택'
lib --verdict 816 --issue 12
[ "$rc" = 1 ] && ok "ⓔa 표 행 번호 8160 ≠ 816 → rc 1" || bad "ⓔa rc=$rc $out"
ledger '| 81 | 승인 (오빠 인터뷰 10-23 · https://github.com/test/repo/issues/12): 채택'
lib --verdict 816 --issue 12
[ "$rc" = 1 ] && ok "ⓔb 표 행 번호 81 ≠ 816 → rc 1" || bad "ⓔb rc=$rc $out"

# ── ⓕ 이슈 번호 뒤 숫자 ──
ledger '| 816 | 승인 (오빠 인터뷰 10-23 · https://github.com/test/repo/issues/121): 채택'
lib --verdict 816 --issue 12
[ "$rc" = 1 ] && ok "ⓕ issues/121 은 issues/12 가 아니다 → rc 1" || bad "ⓕ rc=$rc $out"

# ── ⓖ 다른 저장소 ──
ledger '| 816 | 승인 (오빠 인터뷰 10-23 · https://github.com/other/repo/issues/12): 채택'
lib --verdict 816 --issue 12
[ "$rc" = 1 ] && ok "ⓖ other/repo issues/12 → rc 1" || bad "ⓖ rc=$rc $out"

# ── ⓗ 두 도구 대조: 같은 입력 ⓑ~ⓖ 에서 게이트와 승인 도구가 같은 답 ──
#   게이트는 ⓑ 픽스처(byz-tank approved + 코멘트 「[인터뷰 판정 816]」)로 원장만 갈아 끼워 읽는다.
same() {  # <이름> <원장줄…> — lib rc 와 gate rc 를 비교
  local name="$1"; shift
  ledger "$@"; lib --verdict 816 --issue 12; local lrc="$rc" lout="$out"
  gate; local grc="$rc" gout="$out"
  [ "$lrc" = "$grc" ] && ok "ⓗ $name 두 도구 같은 답 rc=$lrc" || bad "ⓗ $name lib rc=$lrc($lout) ≠ gate rc=$grc($gout)"
}
same "ⓑ 표 행" '| 816 | 표 행 승인 (오빠 인터뷰 10-23 · Issue https://github.com/test/repo/issues/12): 채택'
same "ⓒ 줄머리" '816 오빠 인터뷰(A안 · Issue https://github.com/test/repo/issues/12): 채택'
same "ⓓ (오빠 인터뷰 없음" '| 816 | 승인 (인터뷰 10-23 · https://github.com/test/repo/issues/12): 채택'
same "ⓔ 표 행 번호 81" '| 81 | 승인 (오빠 인터뷰 10-23 · https://github.com/test/repo/issues/12): 채택'
same "ⓕ issues/121" '| 816 | 승인 (오빠 인터뷰 10-23 · https://github.com/test/repo/issues/121): 채택'
same "ⓖ other/repo" '| 816 | 승인 (오빠 인터뷰 10-23 · https://github.com/other/repo/issues/12): 채택'
ledger '816 오빠 인터뷰(A안 · Issue https://github.com/test/repo/issues/12): 채택'
gate
[ "$rc" = 0 ] && echo "$out" | grep -q '^OK #12 승인 ⓑ 판정 816$' && ok "ⓗz 대조 전제 — 픽스처 원장으로 게이트가 승인 통과(ⓑ 판정 816)" || bad "ⓗz rc=$rc $out"

# ── ⓘ 변이: 표 행 분기 삭제 → ⓑ FAIL ──
python3 - "$LIB" "$T/mut.py" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
new = src.replace('|\\|\\s*{re.escape(a.verdict)}\\s*\\|.*?\\(오빠 인터뷰)', '')
if new == src:
    print("MUT-NOT-APPLIED"); sys.exit(1)
open(sys.argv[2], "w", encoding="utf-8").write(new)
PY
[ $? = 0 ] || bad "ⓘ 변이 적용 실패(정규식 자리 못 찾음)"
ledger '| 816 | 표 행 승인 (오빠 인터뷰 10-23 · Issue https://github.com/test/repo/issues/12): 채택'
mout="$(python3 "$T/mut.py" ledger --dir "$T/planner" --repo test/repo --verdict 816 --issue 12 2>&1)"; mrc=$?
[ "$mrc" = 1 ] && ok "ⓘ 변이(표 행 분기 삭제) → ⓑ FAIL(rc 1) = 이 시험이 고침을 잡는다" || bad "ⓘ 변이 rc=$mrc $mout"
rm -f "$T/mut.py"

# ── ⓙ 기존 승인 시험 그대로 PASS ──
jout="$(bash "$HERE/test_proposal_approve_inbox.sh" 2>&1)"; jrc=$?
[ "$jrc" = 0 ] && echo "$jout" | grep -q '^ALL PASS$' && ok "ⓙ test_proposal_approve_inbox.sh ALL PASS rc 0" || bad "ⓙ 기존 시험 rc=$jrc :: $(echo "$jout" | tail -3)"

# ── ⓚ 격리: 가짜 gh 호출 0 · 임시 폴더만 ──
reset; ledger '| 816 | 표 행 승인 (오빠 인터뷰 10-23 · Issue https://github.com/test/repo/issues/12): 채택'
lib --verdict 816 --issue 12
[ "$rc" = 0 ] && [ "$(calls)" = 0 ] && [ "$(find "$T/planner" -type f | wc -l | tr -d ' ')" = 1 ] && ok "ⓚ 임시 폴더 원장만으로 판정 · 가짜 gh(Tank) 호출 0" || bad "ⓚ rc=$rc 호출=$(calls) $out"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
