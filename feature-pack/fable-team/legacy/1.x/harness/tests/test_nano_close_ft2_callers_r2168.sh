#!/usr/bin/env bash
# test_nano_close_ft2_callers_r2168.sh — 카드 r2168 T5 ⓑ ⓒ: 자동 닫기 호출자 2곳이 «rc 5 ∧ FT2-SEAT 줄» 을 «1.x 닫기 대상 아님» 으로 읽는다.
#   ⑫ ft_nano_record_auto.land_close(run · alert 대역) ⑬ ft_stall_scan.Scan.auto_close 승인 갈래(run · block 대역) — 함수 단위 · 실 닫기 · 실 우편함 · 실 장부 0.
# 기준판 = BASE 커밋의 같은 파일(기준판 Red) · 원본 대조 = 새 판에서 FT2-SEAT 줄 없는 rc 5 · rc 1 REJECT · rc 0 CLOSED · rc 3 WAIT 가 기준판 그대로.
# R2168_BIN=<bin 폴더> = 시험 대상 bin(변이 사본 대조용 · 기본 = 키트 사본).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BASE=02fb965c1492bd7a6ae80dc43db87aee79764e2e
KREL=feature-pack/fable-team/legacy/1.x/harness/kit/fable-team/bin
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
mkdir -p "$T/froot/.fable-team/comm" && git -C "$T/froot" init -q; bash "$HERE/lib/kit_bin_copy.sh" "$T/new" >/dev/null || { echo "FAIL kit_bin_copy"; exit 1; }
[ -n "${R2168_BIN:-}" ] && for f in ft_nano_record_auto.py ft_stall_scan.py; do cp "$R2168_BIN/$f" "$T/new/$f"; done
bash "$HERE/lib/kit_bin_copy.sh" "$T/base" >/dev/null || { echo "FAIL kit_bin_copy"; exit 1; }
for f in ft_nano_record_auto.py ft_stall_scan.py; do git -C "$HERE" show "$BASE:$KREL/$f" > "$T/base/$f" || { echo "FAIL 기준판 $f"; exit 1; }; done

# py <bin 판> <사례> → stdout «lines=<json> alert=<n> block=<n> calls=<n> tried=<json>»
py() { ( cd "$T" && env -i HOME="$T" PATH="$PATH" FT_ROOT="$T/froot" PYTHONDONTWRITEBYTECODE=1 FT_NANO_AUTO_CLOSE=1 python3 - "$T/$1" "$2" "$T/state-$1-$2" <<'PY'
import json, sys
from pathlib import Path
b, case, st = sys.argv[1:4]
sys.path.insert(0, b)
SEAT = "byz-harness-nano-k#0"
FT2 = f"INFO drift-check 건너뜀\nFT2-SEAT {SEAT} — 1.x 닫기 대상 아님 · 닫는 길 = ft2 keeper(카드에 «- 남은 범위» 줄 → complete → 세션 닫기) · 워크트리=/x/.fable-team/teams/t/worktrees/k@a1"
OUT = {"ft2": (5, FT2), "rc5": (5, "INFO x\n표식 없음"), "rej": (1, f"REJECT {SEAT}\n  - ⑥x"), "ok": (0, f"INFO x\nCLOSED {SEAT} (명부 삭제)"), "wait": (3, f"WAIT {SEAT} 계보 세션 살아 있음")}[case.split("-")[1]]
calls, alerts, blocks = [], [], []
def run(cmd, env, cap, cwd=None):
    calls.append(cmd)
    if cmd[-1] == "--all":
        return 0, f"닫기 차례 {SEAT} 갈래=승인 set=h1 — bash ft-nano-close.sh {SEAT} --approved /x/v.md"
    return OUT
if case.startswith("land"):
    import ft_nano_record_auto as m
    class C:
        def __init__(self, root): pass
        def seats(self, team): return {SEAT: {"role": "nano"}, "_master": "byz-harness-master#0"}
    m.Ctx, m.ancestor = C, (lambda ctx, seat, rec: "")
    m.alert = lambda *a: alerts.append(a)
    tried = {}
    ln = f"닫기 차례 {SEAT} 갈래=착지기록 set=s1 rec=9 — bash ft-nano-close.sh {SEAT} --landed-pr 5 --result x --recv 9"
    lines = m.land_close(ln, tried, "T0", "/x/ft-nano-close.sh", run, None)
    n1 = len(calls); again = m.land_close(ln, tried, "T1", "/x/ft-nano-close.sh", run, None)
    print(json.dumps({"lines": lines, "alert": len(alerts), "calls": n1, "again_calls": len(calls) - n1, "again": again, "tried": tried}, ensure_ascii=False))
else:
    import ft_stall_scan as m
    m.run = run
    m.block = lambda *a: blocks.append(a)
    s = m.Scan.__new__(m.Scan); s.root = None; s.state_dir = Path(st); s.now = 0
    lines = s.auto_close(); n1 = len(calls); blocks1 = len(blocks)
    again = s.auto_close()
    tried = json.loads((Path(st) / "nano-auto-close.json").read_text(encoding="utf-8"))
    print(json.dumps({"lines": [x.split(" ", 1)[1] for x in lines], "block": blocks1, "calls": n1, "again_calls": len(calls) - n1 - 1, "again": again, "tried": tried}, ensure_ascii=False))
PY
) 2>&1; }
chk() {  # <이름> <json> <파이썬 식(d = 결과)>
  if python3 -c 'import json,sys; d=json.loads(sys.argv[1]); sys.exit(0 if eval(sys.argv[2]) else 1)' "$2" "$3" 2>/dev/null; then echo "PASS $1"; else echo "FAIL $1 ← ${2:0:400}"; fail=$((fail+1)); fi
}
S='byz-harness-nano-k#0'
echo "== ⑫ land_close"
d="$(py new land-ft2)"
chk "⑫ (5, FT2-SEAT) → «auto-close 대상 아님 … ft2 갈래=착지기록 — keeper» 1줄" "$d" "d['lines']==['T0 auto-close 대상 아님 $S ft2 갈래=착지기록 — keeper']"
chk "⑫ alert 0 · tried[좌석] = 열쇠" "$d" "d['alert']==0 and d['tried']=={'$S':'s1|9'}"
chk "⑫ 같은 줄 2번째 = run 0 · 줄 0" "$d" "d['again_calls']==0 and d['again']==[]"
d="$(py base land-ft2)"; chk "⑫ 기준판 Red = auto-close 실패 rc=5 + alert 1" "$d" "d['lines'][0].startswith('T0 auto-close 실패 $S rc=5') and d['alert']==1"
for b in new base; do
  d="$(py $b land-rc5)"; chk "⑫ 대조[$b] (5, 표식 없음) → auto-close 실패 rc=5 + alert 1" "$d" "d['lines'][0].startswith('T0 auto-close 실패 $S rc=5') and d['alert']==1"
  d="$(py $b land-rej)"; chk "⑫ 대조[$b] (1, REJECT) → auto-close 실패 · alert 0" "$d" "d['lines'][0].startswith('T0 auto-close 실패 $S rc=1') and d['alert']==0"
  d="$(py $b land-ok)";  chk "⑫ 대조[$b] (0, CLOSED) → auto-close CLOSED" "$d" "d['lines']==['T0 auto-close CLOSED $S (명부 삭제) 갈래=착지기록 rec=9'] and d['tried']=={}"
done
echo "== ⑬ ft_stall_scan 승인 갈래"
d="$(py new scan-ft2)"
chk "⑬ (5, FT2-SEAT) → «auto-close 대상 아님 … ft2 — keeper» 1줄 · 실패 줄 0" "$d" "d['lines']==['auto-close 대상 아님 $S ft2 — keeper']"
chk "⑬ block raise 0 · tried[좌석] = head" "$d" "d['block']==0 and d['tried']=={'$S':'h1'}"
chk "⑬ 다음 판 닫기 run 0" "$d" "d['again_calls']==0 and d['again']==[]"
d="$(py base scan-ft2)"; chk "⑬ 기준판 Red = auto-close 실패 + block raise 1" "$d" "d['lines'][0].startswith('auto-close 실패 $S rc=5') and d['block']==1"
for b in new base; do
  d="$(py $b scan-wait)"; chk "⑬ 대조[$b] (3, WAIT) → auto-close 실패 1줄 + raise 1" "$d" "d['lines']==['auto-close 실패 $S rc=3 — WAIT $S 계보 세션 살아 있음'] and d['block']==1"
  d="$(py $b scan-rc5)";  chk "⑬ 대조[$b] (5, 표식 없음) → auto-close 실패 + raise 1" "$d" "d['lines'][0].startswith('auto-close 실패 $S rc=5') and d['block']==1"
done
echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
