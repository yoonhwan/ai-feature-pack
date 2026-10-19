#!/usr/bin/env bash
# test_install_worktree_shim.sh — r512: install.sh --apply --project <공용 루트> 가 공용 루트 LIVE_BIN 전환 «뒤»
#   등록 워크트리 중 bin 이 이미 연결 파일(shim)인 곳마다 같은 설치본 ft-root-bin-shim.sh 를 다시 돌려 LIVE_BIN 갱신 + 새 이름 연결.
#   픽스처 = 임시 리포 C(공용 루트 · shim bin + LIVE_BIN = 가짜 live A) + 워크트리 W1(shim) · W2(옛 통째 사본) · W3(.fable-team 없음)
#   임시 HOME(live B = 이 팩 키트 설치본) · 가짜 launchctl · 외부 호출 0 · GIT_* env 0.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_CEILING_DIRECTORIES
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HARNESS="$(cd "$HERE/.." && pwd -P)"
INST="$HARNESS/install.sh"; SHIM="$HARNESS/kit/fable-team/bin/ft-root-bin-shim.sh"
PREPO="$(git -C "$HARNESS" rev-parse --show-toplevel)"; PREPO="$(cd "$PREPO" && pwd -P)"
KPATH="${HARNESS#"$PREPO"/}/kit/fable-team/bin"
VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$HARNESS/../manifest.json")"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1: -600}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }
rc_is(){ [ "$1" = "$2" ] && ok "$3 (rc=$1)" || bad "$3 — rc=$1 기대=$2"; }
G() { git -c user.email=t@t -c user.name=t "$@"; }

bash -n "$INST" && ok "bash -n install.sh" || bad "bash -n install.sh"

IH="$T/home"; LB="$IH/.claude/fable-team/live/$VERSION/bin"
mkdir -p "$IH/Library/LaunchAgents" "$T/fb"; printf '#!/bin/sh\nexit 0\n' > "$T/fb/launchctl"; chmod 755 "$T/fb/launchctl"
hinst() { local p="$1"; shift; env HOME="$IH" FT_LAUNCHCTL="$T/fb/launchctl" bash "$INST" "$@" --project "$p" --home "$IH" 2>&1; }
NEWNAME=ft-index-move.sh   # live A 에 없고 키트(live B)에 있는 이름 = «새 이름»
# mkfix <폴더> → C · W1 · W2 · W3 · LA(가짜 live A: 키트 이름 2개만)
mkfix() {
  local d="$1"; rm -rf "$d"; mkdir -p "$d"
  C="$d/c"; LA="$d/liveA/bin"; W1="$C/.worktrees/w1"; W2="$C/.worktrees/w2"; W3="$C/.worktrees/w3"
  mkdir -p "$LA"; for n in ft-nano-close.sh ft-root-bin-shim.sh; do printf '#!/usr/bin/env bash\necho A-%s\n' "$n" > "$LA/$n"; done
  git init -q -b main "$C"; G -C "$C" commit -q --allow-empty -m e
  for w in w1 w2 w3; do git -C "$C" worktree add -q -b "$w" "$C/.worktrees/$w" main; done
  mkdir -p "$C/.fable-team/bin" "$W1/.fable-team/bin"
  bash "$SHIM" --root "$C" --live "$LA" --live-root "$C" --ref HEAD --repo "$PREPO" --path "$KPATH" >/dev/null 2>&1
  bash "$SHIM" --root "$W1" --live "$LA" --live-root "$C" --ref HEAD --repo "$PREPO" --path "$KPATH" >/dev/null 2>&1
  mkdir -p "$W2/.fable-team/bin"; printf '#!/usr/bin/env bash\necho old copy\n' > "$W2/.fable-team/bin/ft-nano-close.sh"
  printf '%s\n' "$LA" > "$W2/.fable-team/LIVE_BIN"
}
snap() { (cd "$1" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do cksum "$f"; done); }

mkfix "$T/f1"
[ "$(cat "$W1/.fable-team/LIVE_BIN")" = "$LA" ] && [ -f "$W1/.fable-team/bin/ft-nano-close.sh" ] && [ ! -e "$W1/.fable-team/bin/$NEWNAME" ] \
  && ok "픽스처 W1 = shim bin · LIVE_BIN = A · 새 이름 없음" || bad "픽스처 W1 이상"

# ⓒ dry-run → 쓰기 0 · PLAN wt-shim W1 1줄 · W2 SKIP
s1="$(snap "$W1")"; s2="$(snap "$W2")"; sc="$(snap "$C/.fable-team")"
out="$(hinst "$C" --dry-run)"; rc=$?
rc_is "$rc" 0 "ⓒ dry-run"
has "$out" "PLAN wt-shim $W1 $LA -> $LB" "ⓒ PLAN wt-shim W1 (옛 판 -> 새 판)"
[ "$(printf '%s\n' "$out" | grep -c '^PLAN wt-shim ')" = 1 ] && ok "ⓒ PLAN wt-shim 1줄" || bad "ⓒ PLAN wt-shim 줄 수 ≠ 1"
has "$out" "SKIP wt-shim $W2 (shim 아님)" "ⓒ dry-run W2 SKIP 줄"
{ [ "$s1" = "$(snap "$W1")" ] && [ "$s2" = "$(snap "$W2")" ] && [ "$sc" = "$(snap "$C/.fable-team")" ]; } && ok "ⓒ 쓰기 0(W1·W2·C 바이트 불변)" || bad "ⓒ dry-run 이 썼다"

# ⓐ apply → W1 LIVE_BIN = B · 새 이름 연결 1 · WT-SHIM refreshed=1 skip=1 fail=0
out="$(hinst "$C" --apply)"; rc=$?
rc_is "$rc" 0 "ⓐ apply 공용 루트"
[ "$(cat "$C/.fable-team/LIVE_BIN")" = "$LB" ] && ok "ⓐ 공용 루트 LIVE_BIN = B" || bad "ⓐ 공용 루트 LIVE_BIN=$(cat "$C/.fable-team/LIVE_BIN")"
[ "$(cat "$W1/.fable-team/LIVE_BIN")" = "$LB" ] && ok "ⓐ W1 LIVE_BIN = B" || bad "ⓐ W1 LIVE_BIN 옛 판 그대로: $(cat "$W1/.fable-team/LIVE_BIN")"
head -2 "$W1/.fable-team/bin/$NEWNAME" 2>/dev/null | grep -qF '# ft-root-bin-shim:' && ok "ⓐ W1 새 이름 연결 1($NEWNAME)" || bad "ⓐ W1 새 이름 연결 없음"
[ "$(cat "$W1/.fable-team/LIVE_ROOT")" = "$C" ] && ok "ⓐ W1 LIVE_ROOT 보존(= C)" || bad "ⓐ W1 LIVE_ROOT=$(cat "$W1/.fable-team/LIVE_ROOT")"
has "$out" "WT-SHIM refreshed=1 skip=1 fail=0" "ⓐ WT-SHIM refreshed=1 skip=1 fail=0"
has "$out" "INSTALLED $VERSION · PLIST ok" "ⓐ 끝줄 INSTALLED"
# ⓑ W2 bin 바이트 그대로 · stale 0 · SKIP 줄 · W3 변화 0
has "$out" "SKIP wt-shim $W2 (shim 아님)" "ⓑ SKIP wt-shim W2 (shim 아님)"
[ "$s2" = "$(snap "$W2")" ] && ok "ⓑ W2 바이트 그대로(LIVE_BIN 포함)" || bad "ⓑ W2 가 바뀜"
ls -d "$W2"/.fable-team/bin.stale-* >/dev/null 2>&1 && bad "ⓑ W2 bin.stale-* 생김" || ok "ⓑ W2 bin.stale-* 0"
[ ! -e "$W3/.fable-team" ] && ok "ⓑ W3 변화 0(.fable-team 없음 그대로)" || bad "ⓑ W3 에 .fable-team 생김"
hasnt "$out" "wt-shim $W3" "ⓑ W3 는 대상 아님(줄 0)"

# ⓔ 두 번째 apply → refreshed=0 · W1 쓰기 0 · --project W1(워크트리 설치) → 순회 0
s1="$(snap "$W1")"
out="$(hinst "$C" --apply)"; rc=$?
rc_is "$rc" 0 "ⓔ 두 번째 apply"
has "$out" "WT-SHIM refreshed=0 skip=1 fail=0" "ⓔ refreshed=0(멱등)"
[ "$s1" = "$(snap "$W1")" ] && ok "ⓔ W1 쓰기 0" || bad "ⓔ 두 번째 apply 가 W1 에 썼다"
out="$(hinst "$W1" --apply)"; rc=$?
rc_is "$rc" 0 "ⓔ --project W1 apply"
hasnt "$out" "WT-SHIM" "ⓔ 워크트리 설치 = 순회 0(WT-SHIM 줄 0)"
hasnt "$out" "wt-shim $C/" "ⓔ 워크트리 설치 = wt-shim 줄 0"
# ⓕ 폴더 없는 등록 워크트리(prunable) → SKIP (폴더 없음) · 실패 0
rm -rf "$W3"
out="$(hinst "$C" --apply)"; rc=$?
rc_is "$rc" 0 "ⓕ prunable 있어도 apply"
has "$out" "SKIP wt-shim $W3 (폴더 없음)" "ⓕ SKIP wt-shim W3 (폴더 없음)"
has "$out" "WT-SHIM refreshed=0 skip=2 fail=0" "ⓕ skip=2"

# ⓓ W1 shim 실행 실패(bin 읽기 전용 → 새 이름 못 씀) → ERROR wt-shim W1 + 끝 rc1 · 공용 루트 전환은 끝남
mkfix "$T/f2"; chmod 555 "$W1/.fable-team/bin"
out="$(hinst "$C" --apply)"; rc=$?
chmod 755 "$W1/.fable-team/bin"
rc_is "$rc" 1 "ⓓ W1 실패 → 설치 끝 rc1"
has "$out" "ERROR wt-shim $W1 rc=3" "ⓓ ERROR wt-shim W1 rc=3"
has "$out" "WT-SHIM refreshed=0 skip=1 fail=1" "ⓓ WT-SHIM fail=1"
has "$out" "LIVE_BIN 전환은 끝났다" "ⓓ «LIVE_BIN 전환은 끝났다» 문구"
[ "$(cat "$C/.fable-team/LIVE_BIN")" = "$LB" ] && ok "ⓓ 공용 루트 LIVE_BIN = B(전환 끝)" || bad "ⓓ 공용 루트 전환 안 됨"
hasnt "$out" "INSTALLED $VERSION · PLIST ok" "ⓓ 조용한 통과 0(성공 끝줄 없음)"

echo "fail=$fail"; [ "$fail" = 0 ]
