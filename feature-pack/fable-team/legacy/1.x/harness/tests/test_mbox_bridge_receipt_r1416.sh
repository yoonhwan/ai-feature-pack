#!/usr/bin/env bash
# test_mbox_bridge_receipt_r1416.sh — r1416: 다른 루트로 간 쪽지(다리 · 직접 송신)도 보낸 쪽 루트 기록에 영수 1줄(Issue #7802).
#   본문 = tests/scripts/test_mbox_bridge_receipt_r1416.py (B1~B6) · 기준판(origin/main comm) = B1 FAIL
#   + 변이 4종(사본 치환 → 그 시험 FAIL → 복구) + 줄수·설치 감시 목록·모드 644.
# 격리: 실 우편함·실 tmux·실 /tmp 상태 0 — 임시 루트 2 · 가짜 roots.tsv · 가짜 tmux 만.
# ★rc 는 «명령이 낸 값» 을 먼저 변수로 받는다★ (r1309 REWORK r1 반례 2).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
COMM="$HERE/../comm"; BIN="$HERE/../bin"; SC="$HERE/scripts"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; n=0
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
cp -Rp "$COMM" "$T/comm"
run_py() {  # $1 = comm · $2 = -k 식(선택)
  local rc=0; n=$((n + 1))
  ( cd "$SC" && R1416_COMM="$1" R1416_BIN="$BIN" timeout 70 pytest -q -p no:cacheprovider test_mbox_bridge_receipt_r1416.py ${2:+-k "$2"} >"$T/py-$n.log" 2>&1 ); rc=$?
  cp -p "$T/py-$n.log" "$T/py.last.log" || true
  return "$rc"
}

s=$(date +%s); run_py "$T/comm"; rc=$?
ck "B1~B6 rc=$rc · $(grep -Eo '[0-9]+ passed' "$T/py.last.log") $(( $(date +%s) - s ))초" "$rc"

# 기준판 — 고치기 전 comm(git origin/main) = B1 FAIL(실사건 재현)
top="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)"; rel="$(cd "$COMM" && pwd -P)"; rel="${rel#"$(cd "$top" && pwd -P)"/}"
mkdir -p "$T/base"
for f in $(git -C "$top" ls-tree --name-only origin/main "$rel/" 2>/dev/null); do git -C "$top" show "origin/main:$f" >"$T/base/$(basename "$f")"; done
if [ -f "$T/base/mbox.py" ] && [ ! -f "$T/base/mbox_receipt.py" ]; then
  run_py "$T/base"; rc=$?; grep -q 'FAILED.*test_b1_' "$T/py.last.log"; b1=$?
  ck "기준판 B1 FAIL (rc=$rc · $(grep -Eo '[0-9]+ failed' "$T/py.last.log"))" "$([ "$rc" -ne 0 ] && [ "$b1" = 0 ] && echo 0 || echo 1)"
else
  echo "SKIP 기준판 — origin/main 에 이미 mbox_receipt.py 가 있다(착지 뒤)"
fi

mutate() {  # $1 이름 $2 파일 $3 원문 $4 바꿀 글 $5 -k
  python3 - "$T/comm/$2" "$3" "$4" <<'PY' || { echo "FAIL 변이 $1 — 자리 못 찾음"; fail=$((fail+1)); return; }
import sys
p, a, b = sys.argv[1:]
s = open(p, encoding="utf-8").read()
assert s.count(a) == 1, s.count(a)
open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
  run_py "$T/comm" "$5"; rc=$?; [ "$rc" -ne 0 ]; ok=$?
  ck "변이 $1 → $5 FAIL(rc=$rc)" "$ok"
  cp -p "$COMM/$2" "$T/comm/$2"
}
mutate "1 영수 줄 삭제" mbox_roots.py '            mbox_receipt.receipt(comm_of(me),' '            None and mbox_receipt.receipt(comm_of(me),' b1
mutate "2 영수를 큐에 씀" mbox_receipt.py 'open(Path(comm) / "mailbox.log.jsonl", "a"' 'open(Path(comm) / "mailbox.jsonl", "a"' b2
mutate "3 실패 때 영수 씀" mbox_roots.py '        except (OSError, subprocess.SubprocessError, RootsError) as e:
' '        except (OSError, subprocess.SubprocessError, RootsError) as e:
            __import__("mbox_receipt").receipt(comm_of(me), to, frm, body, "x", 0)
' b3
mutate "4 직접 송신 영수 0" mbox_ops.py '    mbox_roots.home_receipt(to, frm, body, seq)' '    None' b6

for f in mbox_roots.py mbox_receipt.py; do [ "$(wc -l <"$COMM/$f")" -le 200 ]; ck "200줄 이하 $f ($(wc -l <"$COMM/$f" | tr -d ' ')줄)" $?; done
grep -q '"mbox_receipt.py|.fable-team/comm/mbox_receipt.py"' "$COMM/check-drift.sh"; ck "설치 감시 목록에 comm/mbox_receipt.py" $?
[ "$(stat -f %Lp "$HERE/test_mbox_bridge_receipt_r1416.sh")" = 644 ]; ck "새 시험 모드 644(셸)" $?
[ "$(stat -f %Lp "$SC/test_mbox_bridge_receipt_r1416.py")" = 644 ]; ck "새 시험 모드 644(py)" $?
[ "$(stat -f %Lp "$COMM/mbox_receipt.py")" = 644 ]; ck "새 모듈 모드 644" $?
echo "FAIL=$fail"; [ "$fail" = 0 ]
