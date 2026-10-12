#!/usr/bin/env bash
# test_nano_evidence_red.sh — 카드 r-nano-evidence-red-first: 증거 줄 «RED(가름) 의도» 형식 (선언 ∧ 선언 rc 일치 ∧ 시험 경로만 — 셋 다일 때만 통과)
# 임시 git 리포(원장 wt + 나노 wt)만 쓴다 — 실 명부·실 워크트리·실 카드 쓰기 0 · 외부 호출 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../scripts/fable-team-bin"; MIR="$HERE/../../scripts/harness-install/fable-team/bin"
EV="$SRC/ft-nano-evidence-check.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:400}";; esac; }

bash -n "$EV" && ok "bash -n" || bad "bash -n"
cmp -s "$EV" "$MIR/ft-nano-evidence-check.sh" && ok "미러 cmp 0" || bad "미러 불일치"
[ "$(wc -l < "$EV")" -le 80 ] && ok "≤80줄" || bad "80줄 초과: $(wc -l < "$EV")"

L="$T/ledger"; D=design/harness/indices/진행
LG() { git -C "$L" -c user.email=t@t -c user.name=t "$@"; }
git init -q -b main "$L"; echo base > "$L/a.txt"; LG add a.txt; LG commit -q -m init
DECL='- 의도 결과: RED rc=1 — 시험이 빨강이어야 한다'
mkcard() { mkdir -p "$L/$D"; printf '## 완료 조건\n%s\n' "$2" > "$L/$D/$1.md"; LG add "$D/$1.md"; LG commit -q -m "card $1"; }
mkcard with "$DECL"; mkcard none "(선언 없음)"; mkcard late "(선언 없음)"
printf '%s\n' "$DECL" >> "$L/$D/late.md"; LG add "$D/late.md"; LG commit -q -m "late decl"   # 선언이 뒤 커밋에서만 생김
NW="$T/nano"; LG worktree add -q "$NW" -b nano/x main
NG() { git -C "$NW" -c user.email=t@t -c user.name=t "$@"; }
mkdir -p "$NW/tests"; echo ':' > "$NW/tests/x.sh"; NG add tests/x.sh; NG commit -q -m "A test only"
A="$(NG rev-parse HEAD)"
card() { echo "$L/$D/$1.md"; }
setline() { LG checkout -q -- "$D/$1.md"; printf -- '- %s\n' "$2" >> "$L/$D/$1.md"; }   # setline <카드> <증거 줄>
chk() { bash "${BIN:-$EV}" "$(card "$1")" --repo "$NW" --feat main 2>&1; }

echo "== ⓐ 선언 ∧ rc 일치 ∧ 시험 경로만 → OK"
setline with "세트: $A · 시험: bash tests/x.sh rc=1 RED · 이슈: 0"; out="$(chk with)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "RED rc=1" "ⓐ OK 출력에 RED rc=1" || bad "ⓐ rc=$rc ← ${out:0:300}"
echo "== ⓑ 카드에 선언 없음 → 기존 rc≠0 REJECT 문구"
setline none "세트: $A · 시험: bash tests/x.sh rc=1 RED · 이슈: 0"; out="$(chk none)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "시험 rc=1 (0 아님)" "ⓑ 36행 문구" || bad "ⓑ rc=$rc ← ${out:0:300}"
echo "== ⓑ' 선언이 첫 판엔 없고 뒤 커밋에만 → REJECT"
setline late "세트: $A · 시험: bash tests/x.sh rc=1 RED · 이슈: 0"; out="$(chk late)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "선언이 spawn 뒤 추가됨" "ⓑ' 문구" || bad "ⓑ' rc=$rc ← ${out:0:300}"
echo "== ⓒ 선언 rc=1 · 증거 rc=127 → REJECT"
setline with "세트: $A · 시험: bash nope.sh rc=127 RED · 이슈: 0"; out="$(chk with)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "선언 rc=1 ≠ 증거 rc=127" "ⓒ 문구" || bad "ⓒ rc=$rc ← ${out:0:300}"
echo "== ⓕ RED 토큰인데 rc=0 → REJECT"
setline with "세트: $A · 시험: bash tests/x.sh rc=0 RED · 이슈: 0"; out="$(chk with)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "RED 인데 rc=0 — 빨강이 아니다" "ⓕ 문구" || bad "ⓕ rc=$rc ← ${out:0:300}"
echo "== ⓔ 기존 rc=0 형식 → 결과 변경 0"
setline none "세트: $A · 시험: bash tests/x.sh rc=0 · 이슈: 0"; out="$(chk none)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "OK 증거 줄 — 세트 HEAD ${A:0:9} · 시험 rc=0 · 이슈 0" "ⓔ rc=0 출력 꼴" || bad "ⓔ rc=$rc ← ${out:0:300}"

echo "== ⓖ rc 는 숫자로 비교 — 0패딩(DA⑥ H1)"
mkcard d00 '- 의도 결과: RED rc=00 — 0패딩 선언'; mkcard d01 '- 의도 결과: RED rc=01 — 0패딩 선언'
setline d00 "세트: $A · 시험: bash tests/x.sh rc=00 RED · 이슈: 0"; out="$(chk d00)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "RED 인데 rc=0" "ⓖ rc=00 RED(선언 00) → REJECT" || bad "ⓖ rc=$rc ← ${out:0:300}"
setline d01 "세트: $A · 시험: bash tests/x.sh rc=1 RED · 이슈: 0"; out="$(chk d01)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "RED rc=1" "ⓖ' 선언 rc=01 · 증거 rc=1 → 숫자 같음 OK" || bad "ⓖ' rc=$rc ← ${out:0:300}"
setline none "세트: $A · 시험: bash tests/x.sh rc=00 · 이슈: 0"; out="$(chk none)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "시험 rc=00 (0 아님)" "ⓖ'' 기존 rc= 형식 rc=00 → 기존 동작 유지" || bad "ⓖ'' rc=$rc ← ${out:0:300}"

mkdir -p "$NW/worker"; echo 'x = 1' > "$NW/worker/x.py"; NG add worker/x.py; NG commit -q -m "B code"
B="$(NG rev-parse HEAD)"
echo "== ⓓ 선언 OK · 코드 경로 변경 → REJECT"
setline with "세트: $B · 시험: bash tests/x.sh rc=1 RED · 이슈: 0"; out="$(chk with)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "코드 변경 있음" "ⓓ 문구" && has "$out" "worker/x.py" "ⓓ 예시 경로" || bad "ⓓ rc=$rc ← ${out:0:300}"
echo "== ⓔ' 기존 rc=0 형식은 코드 경로가 있어도 OK · 문서 형식은 그대로 REJECT"
setline none "세트: $B · 시험: bash tests/x.sh rc=0 · 이슈: 0"; out="$(chk none)"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓔ' rc=0 형식 OK" || bad "ⓔ' rc=$rc ← ${out:0:300}"
setline none "세트: $B · 시험: 없음(문서) — 이유 · 이슈: 0"; out="$(chk none)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "코드 경로 변경이 있음" "ⓔ' 문서 형식 REJECT 유지" || bad "ⓔ'' rc=$rc ← ${out:0:300}"

echo "== 변이 대조 — 검사 한 줄을 지우면 해당 케이스가 «통과해 버린다» (= 시험이 그 검사를 잡고 있다)"
sed '/# RED-③/d' "$EV" > "$T/m3.sh"; BIN="$T/m3.sh"
setline with "세트: $B · 시험: bash tests/x.sh rc=1 RED · 이슈: 0"; out="$(chk with)"; rc=$?
[ "$rc" -eq 0 ] && ok "변이 ③ 경로 검사 제거 → ⓓ 가 통과(빨강)" || bad "변이 ③: 검사가 없는데도 REJECT rc=$rc ← ${out:0:200}"
# 첫 판 대신 «지금 카드» 에서 선언을 읽도록 바꾼다(= 첫 판 검사 제거)
sed '/# RED-①/s/.*/  d1="$dn"/' "$EV" > "$T/m1.sh"; BIN="$T/m1.sh"
git -C "$NW" reset -q --hard "$A"; setline late "세트: $A · 시험: bash tests/x.sh rc=1 RED · 이슈: 0"; out="$(chk late)"; rc=$?
[ "$rc" -eq 0 ] && ok "변이 ① 첫 판 검사 제거 → ⓑ' 가 통과(빨강)" || bad "변이 ①: 검사가 없는데도 REJECT rc=$rc ← ${out:0:200}"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
