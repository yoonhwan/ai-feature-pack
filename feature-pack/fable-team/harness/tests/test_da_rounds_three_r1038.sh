#!/usr/bin/env bash
# test_da_rounds_three_r1038.sh — r1038: 팩의 DA 문서 두 곳이 «카드당 DA 3회» 로 일치하는지 보는 정적 시험.
#   계약: ⓐ 두 파일에 «상한 = 3»(또는 «상한 3») 과 «3회 HOLD 뒤 = 인터뷰» 가 있다
#         ⓑ 옛 문구(«HOLD 상한 = 2» · «상한 2회» · «보류 2회 뒤» · «DA HOLD | 2회») 가 두 파일에 0
#         ⓒ da-counterexample.md 에 «③은 ①② 동결 반례 안에서만 · 새 반례는 [범위 밖]» 문장이 있다
#         ⓓ 이 카드 밖 문구 불변(converge-loop.md 나노 spawn 카드당 2회 · D2·D4·D5 문장)
#   변이: 복사본에서 «상한 = 3» 을 «상한 = 2» 로 되돌리면 ⓐ 가 FAIL(rc≠0) 이어야 한다.
# 격리: 두 문서 파일의 글자만 읽는다(실행·네트워크·tmux·redis 0). 고정 sleep 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REF="${FT_REF_DIR:-$HERE/../../skill/references}"      # 변이 사본을 넣어 이 시험 자체를 다시 돌릴 자리
DA="$REF/da-counterexample.md"
CV="$REF/converge-loop.md"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { grep -qF -- "$2" "$1"; }
for f in "$DA" "$CV"; do [ -f "$f" ] || { bad "파일 없음 $(basename "$f")"; }; done
[ "$fail" -eq 0 ] || { echo "—— 실패 $fail 건"; exit 1; }

# ── ⓐ 상한 3 · «3회 HOLD 뒤» ──
for f in "$DA" "$CV"; do
  n="$(basename "$f")"
  { has "$f" "상한 = 3" || has "$f" "상한 = **3**" || has "$f" "상한 3"; } && ok "ⓐ 상한 3 있음 $n" || bad "ⓐ 상한 3 없음 $n"
  has "$f" "3회 HOLD 뒤" && ok "ⓐ 3회 HOLD 뒤 있음 $n" || bad "ⓐ 3회 HOLD 뒤 없음 $n"
done
# 두 파일의 상한 숫자가 같음(D1·D3 문구의 «3회» 와 표의 «3회» 가 같은 수)
dn="$(grep -o 'HOLD` 상한 = \*\*[0-9]*\*\*' "$DA" | grep -o '[0-9]' | head -1)"
cn="$(grep -o 'DA `HOLD` | [0-9]*회' "$CV" | grep -o '[0-9]' | head -1)"
[ -n "$dn" ] && [ "$dn" = "$cn" ] && ok "ⓐ 두 파일 상한 같음($dn)" || bad "ⓐ 두 파일 상한 불일치(da=$dn cv=$cn)"

# ── ⓑ 옛 문구 0 ──
for f in "$DA" "$CV"; do
  n="$(basename "$f")"
  hit="$(grep -nF -e 'HOLD 상한 = 2' -e '상한 2회' -e '보류 2회 뒤' -e 'DA `HOLD` | 2회' -e '3회째 = 오빠 인터뷰' "$f")"
  [ -z "$hit" ] && ok "ⓑ 옛 문구 0 $n" || bad "ⓑ 옛 문구 남음 $n → $hit"
done

# ── ⓒ 동결 반례 문장 ──
has "$DA" "③은 ①② 동결 반례 안에서만" && has "$DA" "새 반례는 [범위 밖]" && ok "ⓒ 동결 반례 문장" || bad "ⓒ 동결 반례 문장 없음"

# ── ⓓ 범위 밖 문구 불변 ──
has "$CV" '| 나노 spawn | 카드당 2회 (1차 + 고침 1회) |' && ok "ⓓ 나노 spawn 카드당 2회 그대로" || bad "ⓓ 나노 spawn 줄 바뀜"
has "$CV" "D2 카드 APPROVE = [수용] 반례 0 ∧ 미시험 기준 0" && ok "ⓓ D2 그대로" || bad "ⓓ D2 바뀜"
has "$CV" "D4 카드 크기 게이트 = 구현 범위 ≤3항목" && ok "ⓓ D4 그대로" || bad "ⓓ D4 바뀜"
has "$CV" "D5 리서치 나노 시점·모델 상향은 하드 룰 14 옛 문장 그대로" && ok "ⓓ D5 그대로" || bad "ⓓ D5 바뀜"

# ── 변이: 복사본에서 «상한 = 3» → «상한 = 2» 면 ⓐ FAIL ──
if [ "${FT_NO_MUTATE:-0}" = 1 ]; then echo "SKIP 변이(중첩 실행)"; echo "—— 실패 $fail 건"; exit "$fail"; fi
M="$(mktemp -d)"; trap 'rm -rf "$M"' EXIT
cp "$DA" "$CV" "$M"/
sed -i.bak 's/상한 = \*\*3\*\*/상한 = **2**/; s/상한 = 3/상한 = 2/; s/| 3회 (3회 HOLD 뒤/| 2회 (3회째/' "$M/da-counterexample.md" "$M/converge-loop.md"
FT_REF_DIR="$M" FT_NO_MUTATE=1 bash "${BASH_SOURCE[0]:-$0}" >/dev/null 2>&1; mrc=$?
[ "$mrc" -ne 0 ] && ok "변이(상한 3→2) FAIL rc=$mrc" || bad "변이 통과해 버림(rc=$mrc)"

echo "—— 실패 $fail 건"
[ "$fail" -eq 0 ]
