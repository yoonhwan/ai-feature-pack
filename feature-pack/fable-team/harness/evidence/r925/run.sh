#!/usr/bin/env bash
# r925 증거 재현 — 빨강(고치기 전) → 초록(고친 뒤) → 변이 7종(구현 r1 3 + DA⑥ r1 반례 4).
#   사용: bash feature-pack/fable-team/harness/evidence/r925/run.sh   (팩 워크트리 루트에서)
#   base = origin/main 사본(siblings 필요 → bin 폴더를 통째로 복사한 뒤 그 파일만 갈아 끼운다).
set -uo pipefail
R="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/../../../.." && pwd)"   # = feature-pack
OUT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
INJ="$R/tmuxc/test/test_tmuxc_inject_ready_submit.sh"
SO="$R/fable-team/harness/tests/test_successor_open.sh"

# --- base 사본 ---
cp -R "$R/fable-team/harness/kit/fable-team/bin/." "$T/bin/"
git -C "$R/.." show origin/main:feature-pack/fable-team/harness/bin/ft-successor-open.sh > "$T/bin/ft-successor-open.sh"
git -C "$R/.." show origin/main:feature-pack/tmuxc/core/bin/tmuxc > "$T/tmuxc"

{
  echo "### RED — 고치기 전(origin/main) tmuxc inject_message"; echo "\$ FT_TMUXC_PATH=<base> bash $INJ"
  FT_TMUXC_PATH="$T/tmuxc" bash "$INJ"; echo "rc=$?"
} > "$OUT/red-before-inject.txt" 2>&1

{
  echo "### RED — 고치기 전(origin/main) ft-successor-open.sh 이어가기"; echo "\$ FT_SO_PATH=<base> bash $SO"
  FT_SO_PATH="$T/bin/ft-successor-open.sh" bash "$SO"; echo "rc=$?"
} > "$OUT/red-before-successor.txt" 2>&1

{ echo "### GREEN — 고친 뒤 tmuxc"; bash "$INJ"; echo "rc=$?"; } > "$OUT/green-inject.txt" 2>&1
{ echo "### GREEN — 고친 뒤 ft-successor-open"; bash "$SO"; echo "rc=$?"; } > "$OUT/green-successor.txt" 2>&1

{ echo "### 변이 1 — 옛 거동(준비 확인 0 + 확인 없는 Enter 1번) → ⓐ 빨강이어야 한다"; FT_MUTATE=1 bash "$INJ"; echo "rc=$?"; } > "$OUT/mutate-1-old-behaviour.txt" 2>&1
{ echo "### 변이 2 — 재전송 무한(for try in 1..1000) → ⓒ 빨강(멈추지 않음)이어야 한다"; FT_MUTATE=2 bash "$INJ"; echo "rc=$?"; } > "$OUT/mutate-2-unbounded-retry.txt" 2>&1
{ echo "### 변이 3 — 이어가기 Enter 를 아무 글자에나 → ⓡ2' 빨강이어야 한다"; FT_SO_MUTATE=1 bash "$SO"; echo "rc=$?"; } > "$OUT/mutate-3-enter-on-any-text.txt" 2>&1
{ echo "### 변이 4 — 빈 입력줄 검사 끔 → ⓕ 빨강이어야 한다(DA⑥ r1 반례 1)"; FT_MUTATE=4 bash "$INJ"; echo "rc=$?"; } > "$OUT/mutate-4-no-empty-check.txt" 2>&1
{ echo "### 변이 5 — «흐린 글자» 검사 끔 → ⓡ3 빨강이어야 한다(DA⑥ r1 반례 1)"; FT_SO_MUTATE=2 bash "$SO"; echo "rc=$?"; } > "$OUT/mutate-5-no-faint-check.txt" 2>&1
{ echo "### 변이 6 — 재전송 전 재확인 끔 → ⓘ 빨강이어야 한다(DA⑥ r1 반례 2)"; FT_MUTATE=6 bash "$INJ"; echo "rc=$?"; } > "$OUT/mutate-6-no-recheck.txt" 2>&1
{ echo "### 변이 7 — 판독 실패를 «제출됨» 으로 되돌림 → ⓙ 빨강이어야 한다(DA⑥ r1 반례 3)"; FT_MUTATE=7 bash "$INJ"; echo "rc=$?"; } > "$OUT/mutate-7-unreadable-is-submitted.txt" 2>&1

{
  echo "# r925 파일 — 짝 사본 cmp0"
  cmp "$R/fable-team/harness/bin/ft-successor-open.sh" "$R/fable-team/harness/kit/fable-team/bin/ft-successor-open.sh" && echo "cmp0 OK feature-pack/fable-team/harness/bin/ft-successor-open.sh ≡ kit/fable-team/bin/ft-successor-open.sh"
  sha256sum "$R/tmuxc/core/bin/tmuxc" "$R/fable-team/harness/bin/ft-successor-open.sh" | sed 's|'"$R"'/|feature-pack/|'
  echo "# 바뀐 파일: feature-pack/tmuxc/core/bin/tmuxc · feature-pack/fable-team/harness/bin/ft-successor-open.sh(+kit 짝) · 시험 2개 · 증거"
} > "$OUT/files.txt" 2>&1

echo "wrote: $(ls "$OUT")"
