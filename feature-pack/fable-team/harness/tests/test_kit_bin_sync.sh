#!/usr/bin/env bash
# test_kit_bin_sync.sh — 추적본 bin 의 모든 파일이 키트 bin 에 있고 바이트·실행 비트가 같은지 본다(재분기 감시).
# 실제 리포 1회 + 음성 대조 3종(없음·바이트 다름·실행 비트 다름)은 mktemp 복사본에서만 — 리포 파일 쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."
TR="${KIT_SYNC_TR:-$ROOT/scripts/fable-team-bin}"
KIT="${KIT_SYNC_KIT:-$ROOT/scripts/harness-install/fable-team/bin}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

mode() { stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1"; }

# check <추적본 dir> <키트 dir> — 어긋난 파일마다 한 줄 출력, 어긋남 수를 종료코드가 아닌 stdout 마지막 줄 N 으로
check() {
  local tr="$1" kit="$2" n=0 f name
  for f in "$tr"/*; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    if [ ! -f "$kit/$name" ]; then echo "MISSING $name"; n=$((n+1)); continue; fi
    cmp -s "$f" "$kit/$name" || { echo "DIFF $name"; n=$((n+1)); }
    [ "$(mode "$f")" = "$(mode "$kit/$name")" ] || { echo "MODE $name $(mode "$f") != $(mode "$kit/$name")"; n=$((n+1)); }
  done
  echo "N=$n"
}

[ -d "$TR" ] && [ -d "$KIT" ] && ok "dirs exist" || { bad "dirs missing: $TR / $KIT"; exit 1; }

out="$(check "$TR" "$KIT")"; n="${out##*N=}"
[ "$n" = 0 ] && ok "tracked bin ⊂ kit bin (bytes+mode)" || bad "drift: $(echo "$out" | grep -v '^N=' | tr '\n' ';')"

# 음성 대조: 복사본에 어긋남을 만들어 이 시험이 잡는지 본다
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/tr" "$T/kit"
printf '#!/bin/sh\necho a\n' > "$T/tr/ft-x.sh"; chmod 755 "$T/tr/ft-x.sh"
cp -p "$T/tr/ft-x.sh" "$T/kit/ft-x.sh"
out="$(check "$T/tr" "$T/kit")"; [ "${out##*N=}" = 0 ] && ok "control: identical → 0" || bad "control identical: $out"

rm "$T/kit/ft-x.sh"
out="$(check "$T/tr" "$T/kit")"; echo "$out" | grep -q '^MISSING ft-x.sh' && ok "control: missing detected" || bad "control missing: $out"

printf '#!/bin/sh\necho b\n' > "$T/kit/ft-x.sh"; chmod 755 "$T/kit/ft-x.sh"
out="$(check "$T/tr" "$T/kit")"; echo "$out" | grep -q '^DIFF ft-x.sh' && ok "control: byte diff detected" || bad "control diff: $out"

cp -p "$T/tr/ft-x.sh" "$T/kit/ft-x.sh"; chmod 644 "$T/kit/ft-x.sh"
out="$(check "$T/tr" "$T/kit")"; echo "$out" | grep -q '^MODE ft-x.sh' && ok "control: mode diff detected" || bad "control mode: $out"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
