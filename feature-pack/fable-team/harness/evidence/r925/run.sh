#!/usr/bin/env bash
# r925 r3 증거 재현 — 빨강(origin/main · r2 8d6a4756) → 초록 → 변이 5종(J·P·C·E·S) → /bin/bash 3.2 → 짝 사본 cmp0.
#   사용: bash feature-pack/fable-team/harness/evidence/r925/run.sh   (팩 워크트리 루트에서)
#   옛 사본 = git show 로 임시 폴더에(siblings 필요 → kit bin 폴더를 통째로 복사한 뒤 그 파일만 갈아 끼운다).
set -uo pipefail
R="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/../../../.." && pwd)"   # = feature-pack
OUT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
INJ="$R/tmuxc/test/test_tmuxc_inject_ready_submit.sh"
SO="$R/fable-team/harness/tests/test_successor_open.sh"
R2=8d6a4756

old_copies() { # old_copies <ref> <폴더>
  mkdir -p "$2/bin"; cp -R "$R/fable-team/harness/kit/fable-team/bin/." "$2/bin/"
  git -C "$R/.." show "$1:feature-pack/fable-team/harness/bin/ft-successor-open.sh" > "$2/bin/ft-successor-open.sh"
  git -C "$R/.." show "$1:feature-pack/tmuxc/core/bin/tmuxc" > "$2/tmuxc"
}
old_copies origin/main "$T/base"; old_copies "$R2" "$T/r2"

for v in base r2; do
  ref="origin/main"; [ "$v" = r2 ] && ref="$R2"
  { echo "### RED — 고치기 전($ref) tmuxc"; echo "\$ FT_TMUXC_PATH=<$ref> bash $INJ"
    FT_TMUXC_PATH="$T/$v/tmuxc" bash "$INJ"; echo "rc=$?"; } > "$OUT/red-$v-inject.txt" 2>&1
  { echo "### RED — 고치기 전($ref) ft-successor-open.sh 이어가기"; echo "\$ FT_SO_PATH=<$ref> bash $SO"
    FT_SO_PATH="$T/$v/bin/ft-successor-open.sh" bash "$SO"; echo "rc=$?"; } > "$OUT/red-$v-successor.txt" 2>&1
done

{ echo "### GREEN — 고친 뒤 tmuxc"; bash "$INJ"; echo "rc=$?"; } > "$OUT/green-inject.txt" 2>&1
{ echo "### GREEN — 고친 뒤 ft-successor-open"; bash "$SO"; echo "rc=$?"; } > "$OUT/green-successor.txt" 2>&1
{ echo "### GREEN — /bin/bash 3.2 (macOS 기본 셸)"; /bin/bash --version | head -1
  /bin/bash "$INJ"; echo "inject rc=$?"; /bin/bash "$SO"; echo "successor rc=$?"; } > "$OUT/green-bash32.txt" 2>&1

{ echo "### 변이 J — 기록 판정 → 화면 판정(입력줄 빔 ∧ 위 화면에 앞 30자) 복귀 → ⓐ 빨강이어야 한다"; FT_MUTATE=J bash "$INJ"; echo "rc=$?"; } > "$OUT/mutate-J-screen-judgment.txt" 2>&1
{ echo "### 변이 P — 재전송 판정에 접두 인정 복귀 → ⓑ 빨강이어야 한다"; FT_MUTATE=P bash "$INJ"; echo "rc=$?"; } > "$OUT/mutate-P-prefix-accept.txt" 2>&1
{ echo "### 변이 C — capture-pane rc 무시 → ⓓ 빨강이어야 한다"; FT_MUTATE=C bash "$INJ"; echo "rc=$?"; } > "$OUT/mutate-C-capture-rc-ignored.txt" 2>&1
{ echo "### 변이 E — boot-enter 판독 불가 rc0 복귀 → ⓔ 빨강이어야 한다"; FT_MUTATE=E bash "$INJ"; echo "rc=$?"; } > "$OUT/mutate-E-unreadable-rc0.txt" 2>&1
{ echo "### 변이 S — ft-successor-open 이 boot-enter rc≠0 를 무시 → ⓡ2'·ⓡ3 빨강이어야 한다"; FT_SO_MUTATE=S bash "$SO"; echo "rc=$?"; } > "$OUT/mutate-S-successor-ignores-rc.txt" 2>&1

{
  echo "# r925 r3 파일 — 짝 사본 cmp0"
  cmp "$R/fable-team/harness/bin/ft-successor-open.sh" "$R/fable-team/harness/kit/fable-team/bin/ft-successor-open.sh" && echo "cmp0 OK feature-pack/fable-team/harness/bin/ft-successor-open.sh ≡ kit/fable-team/bin/ft-successor-open.sh"
  shasum -a 256 "$R/tmuxc/core/bin/tmuxc" "$R/fable-team/harness/bin/ft-successor-open.sh" | sed 's|'"$R"'/|feature-pack/|'
  echo "# 바뀐 파일: feature-pack/tmuxc/core/bin/tmuxc · feature-pack/fable-team/harness/bin/ft-successor-open.sh(+kit 짝) · 시험 2개 · 증거"
} > "$OUT/files.txt" 2>&1

echo "wrote: $(ls "$OUT" | tr '\n' ' ')"
