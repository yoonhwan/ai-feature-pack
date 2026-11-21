#!/usr/bin/env bash
# test_stall_human_wait_mut_record_r2380.sh — r2380 변이(기록 칸): 점검 기록의 «6시간마다 다시»와 «풀림까지 유지»(F2)를 무력화하면 c16 이 FAIL 해야 한다.
#   M14 기록 있으면 늘 건너뜀(DA H1 되돌림 = 30시간에 1통) → c16 · M13 기록을 6시간 창에 지움(DA F2 되돌림 = 풀림 1통 0) → c16
#   실 파일은 안 건드린다(사본만) · 끝에 실 파일 sha 무변경 확인 · 변이는 그 칸(-k)만 돈다(c16 = 실행 5회라 이 파일로 뺐다).
# 형제 시험: test_stall_human_wait_mut_r2380.sh(M4b·M5~M12) · _r2380(신판) · _base · _regress
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
mutate "M14 기록 있으면 늘 건너뜀(DA H1 되돌림)" ft_stall_scan.py '        return 0 <= self.now - float(at) < HUMAN_ALERT_S' '        return True' c16
mutate "M13 기록을 6시간 창에 지움" ft_stall_scan.py '        rec = rec_raw if isinstance(rec_raw, dict) else {}' '        rec = {k: v for k, v in (rec_raw or {}).items() if isinstance(v, dict) and isinstance(v.get("at"), (int, float)) and self.now - float(v["at"]) <= 6 * 3600}' c16
sha_after="$(shasum "$TRK/ft_stall_detect.py" "$KIT/ft_stall_detect.py" "$KIT/ft_stall_scan.py" | awk '{print $1}' | tr '\n' ' ')"
[ "$sha_before" = "$sha_after" ]; ck "변이 뒤 실 파일 무변경(사본만)" $?
lap 변이
echo "FAIL=$fail"; [ "$fail" -eq 0 ]
