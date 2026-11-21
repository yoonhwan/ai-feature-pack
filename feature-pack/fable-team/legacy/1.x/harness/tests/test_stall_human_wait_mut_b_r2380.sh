#!/usr/bin/env bash
# test_stall_human_wait_mut_b_r2380.sh — r2380 변이 나(카드 고정): 사본 bin 한 곳을 무력화하면 그 시험이 FAIL 해야 한다(하드 룰 22 로 두 파일).
#   M9 확인 줄 무시 → c10 · M10 풀림 1통 지움 → c12 · M11 git 실패 = 경보로 → c17 · M12 트리 못 읽음 = 줄 없음 → c15
#   실 파일은 안 건드린다(사본만) · 끝에 실 파일 sha 무변경 확인 · 변이는 그 칸(-k)만 돈다.
# 형제 시험: test_stall_human_wait_mut_r2380.sh(앞 반) · _mut_record(M13·M14) · _r2380(신판) · _base · _regress
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team/bin"; TRK="$HERE/../bin"; SC="$HERE/scripts"; PACK="$(git -C "$HERE" rev-parse --show-toplevel)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; R2380_T0=$SECONDS
. "$SC/_r2380_stall_lib.sh"
cp -Rp "$KIT" "$T/bin"
sha_before="$(shasum "$TRK/ft_stall_detect.py" "$KIT/ft_stall_detect.py" "$KIT/ft_stall_scan.py" | awk '{print $1}' | tr '\n' ' ')"
py_for() {  # 반 갈래 파일 — 15 시험을 한 파일에 두면 70초를 넘는다(하드 룰 22)
  case "$1" in c06|c07|c08|c09|c10|c11|c12|c13) echo test_stall_human_wait_r2380.py;; *) echo test_stall_human_wait_b_r2380.py;; esac
}
mutate() {  # $1 이름 $2 파일 $3 원문(고정 문자열 · 1곳) $4 바꿀 글 $5 -k 시험
  cp -p "$KIT/$2" "$T/bin/$2"
  python3 -I - "$T/bin/$2" "$3" "$4" <<'PY' || { echo "FAIL 변이 $1 — 자리 못 찾음"; fail=$((fail+1)); return; }
import sys
p, a, b = sys.argv[1:]
s = open(p, encoding="utf-8").read()
assert s.count(a) == 1, s.count(a)
open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
  run_py "$T/bin" "$(py_for "$5")" "$5"; [ $? -ne 0 ]; ck "변이 $1 → $5 FAIL" $?
  cp -p "$KIT/$2" "$T/bin/$2"
}
mutate "M9 확인 줄 무시" ft_stall_detect.py 'cands = [x for x in (at, stamp) if x is not None]' 'cands = [x for x in (at,) if x is not None]' c10
mutate "M10 풀림 1통 지움" ft_stall_scan.py '            self.human_done.append({"key": key, "team": team, "card": card, "ts": str(rec.get("ts") or "")})' '            _ = 0' c12
mutate "M11 git 실패 = 경보로" ft_stall_detect.py '    if rc != 0:
        return None, f"git log rc={rc} {err[-40:]}"' '    if rc != 0:
        return 0.0, ""' c17
mutate "M12 트리 못 읽음 = 줄 없음" ft_stall_scan.py '                self.human_unread += 1' '                self.human_unread += 1
                seen[t["team"]] = {}' c15
sha_after="$(shasum "$TRK/ft_stall_detect.py" "$KIT/ft_stall_detect.py" "$KIT/ft_stall_scan.py" | awk '{print $1}' | tr '\n' ' ')"
[ "$sha_before" = "$sha_after" ]; ck "변이 뒤 실 파일 무변경(사본만)" $?
lap 변이
echo "FAIL=$fail"; [ "$fail" -eq 0 ]
