#!/usr/bin/env bash
# test_cherry_gate_identical_head.sh — R70: tip 내용이 feat HEAD 와 바이트 동일한 경로는 PASS + spawn --cherry-override 패스스루.
# mktemp 리포(가짜 feat·nano 브랜치)만 쓴다 — 실 브랜치·루트 .fable-team/·원장 쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../../scripts/fable-team-bin"
G="${FT_TEST_GATE:-$KIT/ft-nano-cherry-gate.sh}"          # RED 확인용: 옛 사본 경로를 FT_TEST_GATE 로 준다
SP="$KIT/ft-nano-spawn.sh"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; R=""; OUT=""; RC=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
g()  { git -C "$R" "$@"; }
cm() { g add -A && g commit -qm "$1"; }
w()  { mkdir -p "$(dirname "$R/$1")"; printf '%s\n' "$2" > "$R/$1"; }
mk() { R="$T/$1"; git init -q -b main "$R"; w app/a.py a0; w design/card.md c0; cm base; }
gate() { OUT="$(FT_CHERRY_OVERRIDE_LEDGER="$T/ledger" bash "$G" main nano/x --repo "$R" "$@" 2>&1)"; RC=$?; }
chk() { # chk <이름> <기대 rc> <있어야 할 문구…>
  local name="$1" want="$2" pat; shift 2
  [ "$RC" -eq "$want" ] || { bad "$name (rc=$RC want=$want) :: ${OUT:0:400}"; return; }
  for pat in "$@"; do printf '%s' "$OUT" | grep -qF -- "$pat" || { bad "$name (문구 없음: $pat) :: ${OUT:0:600}"; return; }; done
  ok "$name"
}
lacks() { printf '%s' "$OUT" | grep -qF -- "$2" && bad "$1 (있으면 안 되는 문구: $2)" || ok "$1"; }

# ① 이번 오탐 — nano 가 코드 P 를 바꿨다 되돌림 + design/ 카드 양쪽 수정(merge-tree 충돌) → PASS · 사유 content_identical_to_feat_head
mk t1; g checkout -q -b nano/x
w app/a.py a1; w design/card.md nano; cm "nano change"; w app/a.py a0; cm "nano revert"
g checkout -q main; w design/card.md feat; w app/m.py m; cm "feat moved"
gate; chk "①오탐 재현 → PASS" 0 "content_identical_to_feat_head" "feat HEAD 와 동일 1개"

# ② DA 599 H1 회귀 — 분기 전 옛 blob(X)으로 롤백한 브랜치 · feat 는 분기 뒤 Y → REJECT 유지
R="$T/t2"; git init -q -b main "$R"; w app/a.py X; cm c1; w app/a.py W; cm base
g checkout -q -b nano/x; w app/a.py X; cm "nano rollback to X"
g checkout -q main; w app/a.py Y; cm "feat Y"
gate; chk "②옛 blob 롤백 → REJECT" 1 "REJECT"; lacks "②사유 토큰 없음" "content_identical_to_feat_head"

# ③ 기존 superseded — tip 내용이 분기 뒤 feat 구간의 새 blob(이후 feat 는 더 고침) → PASS · 기존 사유 그대로
mk t3; g checkout -q -b nano/x; w app/a.py a1; cm "nano a1"
g checkout -q main; w app/a.py zz; cm "feat zz"; w app/a.py a1; cm "feat a1"; w app/a.py a2; cm "feat a2"
gate; chk "③superseded → PASS" 0 "content_landed_then_superseded"; lacks "③동일 토큰 없음" "content_identical_to_feat_head"

# ④ nano 가 P 를 feat HEAD 와 다른 새 내용으로 → REJECT
mk t4; g checkout -q -b nano/x; w app/a.py nanonew; w design/card.md nano; cm "nano new"
g checkout -q main; w design/card.md feat; cm "feat card"
gate; chk "④새 내용 → REJECT" 1 "REJECT"

# ⑤ mode 만 다름(100644 vs 100755 같은 blob) → REJECT
mk t5; g checkout -q -b nano/x; chmod +x "$R/app/a.py"; w design/card.md nano; cm "nano chmod"
g checkout -q main; w design/card.md feat; cm "feat card"
gate; chk "⑤mode 만 다름 → REJECT" 1 "REJECT"

# ⑥ spawn --cherry-override — 빈 사유 exit 2 · 사유 있으면 파싱 통과(인덱스 없음 단계까지 감) · 패스스루 줄 존재
mkdir -p "$T/sp" && git init -q -b main "$T/sp"
sp() { OUT="$(cd "$T/sp" && bash "$SP" "$T/no-such-index.md" "$@" 2>&1)"; RC=$?; }
sp --cherry-override "";    chk "⑥빈 사유 → exit 2" 2 "cherry-override"
sp --cherry-override "   "; chk "⑥공백 사유 → exit 2" 2 "cherry-override"
sp --cherry-override "오탐 R70"; chk "⑥사유 있음 → 파싱 통과" 1 "인덱스 없음"
sp;                          chk "⑥인자 없음 → 현행 그대로" 1 "인덱스 없음"
call="$(grep -n 'ft-nano-cherry-gate.sh' "$SP" | grep -v '^[0-9]*:#' | head -1)"
printf '%s' "$call" | grep -q 'CO_ARGS' && ok "⑥게이트 호출에 CO_ARGS 패스스루" || bad "⑥게이트 호출에 CO_ARGS 없음 :: $call"
grep -q 'export FT_SEAT="\$FROM"' "$SP" && ok "⑥FT_SEAT=\$FROM 지정" || bad "⑥FT_SEAT=\$FROM 지정 없음"
grep -q -- '--override "\$CO"' "$SP" && ok "⑥--override 사유 전달" || bad "⑥--override \"\$CO\" 없음"

# ⑦ 기존 squash 시험 · ⑧ 쌍 cmp · bash -n · 줄 수 (게이트 사본이 기본 경로일 때만 — RED 확인 시에는 건너뜀)
if [ -z "${FT_TEST_GATE:-}" ]; then
  bash "$HERE/test_cherry_gate_squash.sh" >"$T/squash.out" 2>&1 && ok "⑦squash 시험 rc=0" || bad "⑦squash 시험 실패 :: $(tail -3 "$T/squash.out")"
  INST="$HERE/../../scripts/harness-install/fable-team/bin"
  for f in ft-nano-cherry-gate.sh ft-nano-spawn.sh; do
    cmp -s "$KIT/$f" "$INST/$f" && ok "⑧cmp $f" || bad "⑧cmp $f 불일치"
    bash -n "$KIT/$f" && bash -n "$INST/$f" && ok "⑧bash -n $f" || bad "⑧bash -n $f"
  done
  n="$(wc -l < "$KIT/ft-nano-cherry-gate.sh")"; [ "$n" -le 200 ] && ok "⑧게이트 ${n}줄 ≤ 200" || bad "⑧게이트 ${n}줄 > 200"
fi
echo "---"; [ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED=$fail"; exit 1; }
