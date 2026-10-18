#!/bin/bash
# R67 — 추적 사본 mbox-v2.sh 는 옆에 mbox.py 가 없으면 «설치용 사본» 안내 1줄 + exit 2.
# 임시 폴더만 쓴다(루트 .fable-team/·홈·tmux 쓰기 0).
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
A="$ROOT/scripts/fable-team-bin/mbox-v2.sh"
B="$ROOT/scripts/harness-install/fable-team/bin/mbox-v2.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
ok() { echo "ok   $1"; }
ng() { echo "FAIL $1"; fail=1; }

for f in "$A" "$B"; do
  bash -n "$f" && ok "bash -n $f" || ng "bash -n $f"
done
cmp -s "$A" "$B" && ok "두 사본 cmp 동일" || ng "두 사본 cmp 동일"

for f in "$A" "$B"; do
  d="$TMP/$(basename "$(dirname "$(dirname "$f")")")-noyp"
  mkdir -p "$d" && cp "$f" "$d/mbox-v2.sh"
  out="$(bash "$d/mbox-v2.sh" peek x 2>&1 >/dev/null)"; rc=$?
  [ "$rc" -eq 2 ] && ok "mbox.py 없음 → exit 2 ($f)" || ng "mbox.py 없음 → exit 2, rc=$rc ($f)"
  case "$out" in *"설치용 사본"*) ok "안내문 '설치용 사본'";; *) ng "안내문 '설치용 사본'";; esac
  case "$out" in *".fable-team/comm/mbox.sh"*) ok "안내문 '.fable-team/comm/mbox.sh'";; *) ng "안내문 '.fable-team/comm/mbox.sh'";; esac
  case "$out" in *Traceback*|*"can't open file"*) ng "파이썬 트레이스백 0";; *) ok "파이썬 트레이스백 0";; esac

  s="$TMP/$(basename "$(dirname "$(dirname "$f")")")-stub"
  mkdir -p "$s" && cp "$f" "$s/mbox-v2.sh"
  printf 'import sys\nprint("STUB", *sys.argv[1:])\n' > "$s/mbox.py"
  out="$(bash "$s/mbox-v2.sh" peek x 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] && [ "$out" = "STUB peek x" ] && ok "가짜 mbox.py → 스텁 출력·exit 0 ($f)" || ng "가짜 mbox.py → rc=$rc out=$out ($f)"
done

[ "$fail" -eq 0 ] && echo "ALL OK" || echo "FAILED"
exit "$fail"
