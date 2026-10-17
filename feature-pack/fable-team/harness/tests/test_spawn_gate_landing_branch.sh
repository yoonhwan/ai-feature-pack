#!/usr/bin/env bash
# test_spawn_gate_landing_branch.sh — R71: spawn ②-0 cherry 게이트 첫 인자 = 랜딩 브랜치(INFO_BASE) — --base 가 sha 여도 «브랜치 없음» 0.
# ft-nano-spawn.sh 의 BASE_BRANCH~②-0 블록만 잘라(마커 기반) mktemp 리포 위에서 실행한다 — spawn 전체·실 브랜치·루트 .fable-team/·카드 쓰기 0.
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1   # R201: 시험은 추적 사본 원본을 직접 부른다(LIVE_BIN 으로 넘기지 않음)
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="${FT_TEST_KIT:-$HERE/../../scripts/fable-team-bin}"   # RED 확인용: 옛 사본 디렉터리를 FT_TEST_KIT 로 준다
SP="$KIT/ft-nano-spawn.sh"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$T/sensors" ok   # R218: 자원 문지기 센서를 가짜로(실 머신 부하·압력 무관)
fail=0; OUT=""; RC=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

# 블록 추출: ^BASE_BRANCH= 부터 «# tmuxc 옵션» 직전까지
s="$(grep -n '^BASE_BRANCH=' "$SP" | head -1 | cut -d: -f1)"; e="$(grep -n '^# tmuxc 옵션' "$SP" | head -1 | cut -d: -f1)"
[ -n "$s" ] && [ -n "$e" ] && [ "$s" -lt "$e" ] || { echo "FAIL 블록 마커 없음 (s=$s e=$e)"; exit 1; }
sed -n "${s},$((e-1))p" "$SP" > "$T/block.sh"

# 가짜 리포: feat/x(c1·c2·c3) + 옛 nano 브랜치(c1 에서 분기·워크트리 없음)
R="$T/repo"; git init -q -b feat/x "$R"
g() { git -C "$R" "$@"; }
printf 'a0\n' > "$R/a.py"; g add -A; g commit -qm c1; SHA1="$(g rev-parse HEAD)"
g checkout -q -b nano/slug; printf 'n1\n' > "$R/n.py"; g add -A; g commit -qm nano; g checkout -q feat/x
printf 'a1\n' > "$R/a.py"; g commit -qam c2; printf 'a2\n' > "$R/a.py"; g commit -qam c3
SHA2="$(g rev-parse HEAD~1)"                                   # feat 의 조상 commit (c2)

# 인자 기록 스텁 게이트
HD="$T/stub"; mkdir -p "$HD"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "%s/args"\necho "PASS stub"\n' "$T" > "$HD/ft-nano-cherry-gate.sh"
: > "$T/idx.md"

# run <게이트 디렉터리> <BASE_REF> <HAVE_CO> [CO_ARGS…]   (FT_NANO_FEAT 는 호출 환경에서)
run() {
  local gd="$1" base="$2" hc="$3"; shift 3
  { echo 'set -uo pipefail'
    echo "ROOT='$R'; WT='$R'; HERE='$gd'; FROM='seat#0'; HAVE_CO=$hc; BASE_REF='$base'; SLUG=slug; BRANCH=nano/slug; WTDIR='$T/nowt'; IDX='$T/idx.md'"
    printf 'CO_ARGS=('; for a in "$@"; do printf '%q ' "$a"; done; echo ')'
    cat "$T/block.sh"; echo 'echo "DONE base=$BASE_BRANCH info=$INFO_BASE"'; } > "$T/run.sh"
  rm -f "$T/args"; OUT="$(bash "$T/run.sh" 2>&1)"; RC=$?
}
arg1() { head -1 "$T/args" 2>/dev/null; }
eq() { # eq <이름> <기대 첫 인자>
  [ "$(arg1)" = "$2" ] && ok "$1" || bad "$1 (첫 인자='$(arg1)' want='$2') :: ${OUT:0:300}"
}

# ① --base sha + FT_NANO_FEAT 없음 → 호출 워크트리 브랜치(feat/x)
run "$HD" "$SHA2" 0;                          eq "①sha·FEAT 없음 → feat/x" "feat/x"
# ② --base sha + FT_NANO_FEAT=feat/y → feat/y
FT_NANO_FEAT=feat/y run "$HD" "$SHA2" 0;      eq "②sha·FEAT=feat/y → feat/y" "feat/y"
# ③ --base 브랜치 → 그 브랜치(현행 동일)
run "$HD" "feat/x" 0;                         eq "③브랜치 → feat/x" "feat/x"
# ④ --base 없음 → 워크트리 브랜치(현행 동일)
run "$HD" "" 0;                               eq "④base 없음 → feat/x" "feat/x"
# ⑤ --cherry-override 동반 → --override <사유> 여전히 전달
run "$HD" "$SHA2" 1 --override "오탐 R71"
[ "$(sed -n '3,4p' "$T/args" | tr '\n' '|')" != "" ] && grep -qx -- '--override' "$T/args" && grep -qx '오탐 R71' "$T/args" \
  && ok "⑤--override 사유 전달" || bad "⑤--override 전달 없음 :: $(tr '\n' '|' < "$T/args" 2>/dev/null)"
eq "⑤첫 인자도 feat/x" "feat/x"

# ⑥ 실 게이트(스텁 아님)로 ①의 저장소 — «브랜치 없음» 0 · 내용 판정(PASS/REJECT)까지 감
run "$KIT" "$SHA2" 0
if printf '%s' "$OUT" | grep -qF '브랜치 없음'; then bad "⑥실 게이트 «브랜치 없음» :: ${OUT:0:300}"; else ok "⑥실 게이트 «브랜치 없음» 0"; fi
printf '%s' "$OUT" | grep -qE 'PASS|REJECT|DONE' && ok "⑥내용 판정까지 감" || bad "⑥판정 출력 없음 :: ${OUT:0:300}"

# ⑦ 기존 cherry 시험 2종 · ⑧ 쌍 cmp · bash -n (RED 확인 시에는 건너뜀)
if [ -z "${FT_TEST_KIT:-}" ]; then
  bash "$HERE/test_cherry_gate_identical_head.sh" >"$T/h.out" 2>&1 && ok "⑦identical_head rc=0" || bad "⑦identical_head 실패 :: $(tail -3 "$T/h.out")"
  bash "$HERE/test_cherry_gate_squash.sh" >"$T/s.out" 2>&1 && ok "⑦squash rc=0" || bad "⑦squash 실패 :: $(tail -3 "$T/s.out")"
  INST="$HERE/../../scripts/harness-install/fable-team/bin"
  cmp -s "$KIT/ft-nano-spawn.sh" "$INST/ft-nano-spawn.sh" && ok "⑧cmp spawn" || bad "⑧cmp spawn 불일치"
  bash -n "$KIT/ft-nano-spawn.sh" && bash -n "$INST/ft-nano-spawn.sh" && ok "⑧bash -n" || bad "⑧bash -n"
fi
echo "---"; [ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED=$fail"; exit 1; }
