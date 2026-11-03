"""r1238 단계 B 변이 시험 — 사본 bin 에 한 줄씩 어긋나게 넣고 «그 칸이 무너지는지» 본다 (pytest 가 모으지 않는 이름 · 손으로 돌린다).

    python3 tests/scripts/mutate_stall_scan_outage_hold_r1238.py          # 전 변이
    python3 tests/scripts/mutate_stall_scan_outage_hold_r1238.py V-B3     # 이름에 든 것만

변이마다: kit bin 사본 → 파일 한두 곳 치환 → 무너져야 할 칸만 pytest -k → FAIL(rc≠0)이면 «잡았다» · 통과하면 «놓침»(rc 1).
치환 문장이 없으면 즉시 실패(조용한 통과 0). 자기 재호출 방지: 환경 R1238B_MUTATING=1 이면 바로 끝낸다. 임시 폴더만 쓴다.
"""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

if os.environ.get("R1238B_MUTATING") == "1":
    print("SKIP 재진입(이미 도는 변이 시험)")
    sys.exit(0)

HERE = Path(__file__).resolve().parent
KIT = HERE.parents[1] / "kit/fable-team/bin"
TEST = HERE / "test_stall_scan_outage_hold_r1238.py"
SCAN, DETECT = "ft_stall_scan.py", "ft_stall_detect.py"

MUTANTS: dict[str, tuple[str, list[tuple[str, str]], str]] = {
    "V-B1 장애 문 끔": (SCAN, [('hold = ob["since"] is not None', "hold = False")], "r1_outage_holds or r1_outage_sends or r1b or r1c or r6"),
    "V-B2 RECOVERED 의 released 무시": (DETECT, [('        elif st.get("released"):', '        elif status == "OK" and st.get("released"):')], "r2_r2b and RECOVERED"),
    "V-B3 mtime 검사 삭제": (DETECT, [("        if now - mt > OUTAGE_FRESH_S:", "        if False:")], "r5b or r5d"),
    "V-B4 seats.json 하나만 읽음": (DETECT, [('d.glob("seats*.json")', 'd.glob("seats.json")')], "r1b"),
    "V-B5 끝 뒤 유예 삭제": (SCAN, [("0 <= self.now - rel < lead_heartbeat_min() * 60 else None", "False else None")], "r2_r2b or r3b"),
    "V-B6 깨진 파일을 판정에서 안 뺌(노트 삭제)": (DETECT, [('            out["notes"].append(f"장애 상태 판정 불가 {p.name}")\n            continue\n        status', '            continue\n        status')], "r5_broken"),
    "V-B7 보류분이 out 에 들어감(penalty 재료)": (SCAN, [("                        supp[\"b\"].add(s)\n", "                        supp[\"b\"].add(s)\n                        out.append(dict(kind=\"b\", seat=s, team=t[\"team\"], age=age, why=\"x\"))\n")], "b4_held"),
    "V-B8 감시기 로그 증거 줄 삭제": (SCAN, [('n.startswith(("보류 — API 장애", "유예 — API 장애"))', "False")], "r1_outage_sends"),
    "V-B9 f 에 보류 문 없음": (SCAN, [("                        if hold or lag is not None and min(", "                        if False and hold or lag is not None and min(")], "r1_outage_holds"),
}


def main(argv: list[str]) -> int:
    want = argv[0] if argv else ""
    pick = {k: v for k, v in MUTANTS.items() if want in k}
    if not pick:
        print(f"변이 없음: {want!r}")
        return 2
    tmp = Path(tempfile.mkdtemp(prefix="r1238b-mut-"))
    work = tmp / "bin"
    _ = shutil.copytree(KIT, work)
    missed = 0
    env = {**os.environ, "R1238B_BIN": str(work), "R1238B_MUTATING": "1"}
    for name, (fname, pairs, expr) in pick.items():
        path = work / fname
        orig = (KIT / fname).read_text(encoding="utf-8")
        text = orig
        for a, b in pairs:
            if a not in text:
                print(f"FAIL {name} — 변이 대상 줄 없음: {a[:70]!r}")
                missed += 1
                break
            text = text.replace(a, b, 1)
        else:
            _ = path.write_text(text, encoding="utf-8")
            r = subprocess.run([sys.executable, "-m", "pytest", "-q", "-p", "no:cacheprovider", "-k", expr, str(TEST)], cwd="/", env=env, capture_output=True, text=True, timeout=120)
            tail = (r.stdout.strip().splitlines() or ["?"])[-1]
            if r.returncode != 0:
                print(f"PASS 잡음 {name} → 칸 «{expr}» FAIL ({tail})")
            else:
                print(f"FAIL 놓침 {name} → 칸 «{expr}» 가 통과해 버림 ({tail})")
                missed += 1
        _ = path.write_text(orig, encoding="utf-8")
    shutil.rmtree(tmp, ignore_errors=True)
    print(f"RESULT 변이 {len(pick)}개 · 놓침 {missed}")
    return 1 if missed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
