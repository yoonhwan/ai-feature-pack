#!/usr/bin/env bash
# test_kit_exec_modes.sh — R245 범위 추가: 직접 실행되는 키트 도구는 git 모드 100755 여야 한다(라이브 Permission denied 방지).
#   ft-merge-land.sh 가 $GH_W(기본 ft-gh-as-tank.sh)를 «직접» 실행하고, launchd plist 는 __FT_BIN__/<도구> 를 «직접» 실행한다.
#   읽기만(git ls-files -s) — 라이브·원격 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
SRC=scripts/fable-team-bin; KIT=scripts/harness-install/fable-team/bin; PL=scripts/harness-install/launchd
fail=0; ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
mode_of() { git -C "$ROOT" ls-files -s -- "$1" | awk '{print $1}'; }

# ① ft-merge-land.sh 의 기본 $GH_W 도구
GHW="$(sed -nE 's|.*GH_W="\$\{FT_GH_WRITE:-\$HERE/([^"}]+)\}".*|\1|p' "$ROOT/$SRC/ft-merge-land.sh" | head -1)"
[ -n "$GHW" ]; ck "ft-merge-land.sh 의 기본 쓰기 도구 이름을 읽음($GHW)" $?
for d in "$SRC" "$KIT"; do [ "$(mode_of "$d/$GHW")" = 100755 ]; ck "$d/$GHW 모드 100755" $?; done

# ② launchd plist 가 직접 실행하는 __FT_BIN__/<도구> 전부 100755 (src·키트 사본 모두)
n=0
for t in $(grep -hoE '__FT_BIN__/[A-Za-z0-9_.-]+' "$ROOT/$PL"/*.plist.template | sed 's|__FT_BIN__/||' | sort -u); do
  n=$((n+1)); for d in "$SRC" "$KIT"; do [ "$(mode_of "$d/$t")" = 100755 ]; ck "plist 직접 실행 $d/$t 모드 100755" $?; done
done
[ "$n" -gt 0 ]; ck "plist 에서 직접 실행 도구를 1개 이상 찾음($n)" $?

# ③ src 와 키트 사본의 모드가 같다(두 사본이 갈리면 라이브 대조가 흔들린다)
[ "$(mode_of "$SRC/$GHW")" = "$(mode_of "$KIT/$GHW")" ]; ck "$GHW src·키트 모드 일치" $?

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
