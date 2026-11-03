"""r1238 단계 A 변이 시험 — 사본 bin 에 한 줄씩 어긋나게 넣고 «그 칸이 무너지는지» 본다 (pytest 가 모으지 않는 이름 · 손으로 돌린다).

    python3 tests/scripts/mutate_stall_a_r1238a.py            # 전 변이
    python3 tests/scripts/mutate_stall_a_r1238a.py V-a16      # 하나만

변이마다: kit bin 사본 한 벌 → 파일 한두 곳 치환 → 그 변이가 무너뜨려야 할 칸만 pytest -k 로 돌림 → FAIL(rc≠0)이면 «잡았다» · PASS 면 «놓침»(rc 1).
치환 문장이 사본에 없으면 «변이 대상 줄 없음» 으로 즉시 실패(조용한 통과 0). 자기 재호출 방지: 환경 R1238A_MUTATING=1 이면 바로 끝낸다. 실 상태 0 · 임시 폴더만.
"""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

if os.environ.get("R1238A_MUTATING") == "1":
    print("SKIP 재진입(이미 도는 변이 시험)")
    sys.exit(0)

HERE = Path(__file__).resolve().parent
KIT = HERE.parents[1] / "kit/fable-team/bin"
TEST = HERE / "test_stall_a_gates_r1238a.py"
SCAN, DETECT = "ft_stall_scan.py", "ft_stall_detect.py"

# 변이 이름 → (파일, [(원문, 치환)...], 무너져야 할 칸 -k 식)
MUTANTS: dict[str, tuple[str, list[tuple[str, str]], str]] = {
    "V-a1 gate 호출 삭제": (SCAN, [("rc = card_gate(self.root, f[\"team\"], self.flow)", "rc = 0")], "s_cap1_s_cap5"),
    "V-a5 스위치 무시": (DETECT, [('if [ "${FT_CARD_FLOW:-1}" = 0 ] || [ "${FT_CARD_CAP:-1}" = 0 ]; then exit 0; fi', ":")], "s_cap4"),
    "V-a9 --gate → --warn": (DETECT, [('--team "$3" --root "$4" --gate', '--team "$3" --root "$4" --warn')], "s_cap2"),
    "V-a17 gate 실패를 ok 로": (SCAN, [("            if rc == 0:\n                kept.append(f)", "            if rc != 4:\n                kept.append(f)")], "s_cap3"),
    "V-a3 waiting 검사 삭제": (DETECT, [('row["state"] != "waiting" or row.get("reason") in LEGACY', "True")], "s_wait1_s_wait11"),
    "V-a4 꼴 검사 삭제": (DETECT, [('        raise RefUnavailable(f"배정 원장 꼴 위반 {stem}")', "        pass")], "s_wait7"),
    "V-a8 디스크 길에만 적용": (DETECT, [("    if verdicts is None:\n        d = cards / \"대기\"", "    disk_only = verdicts is None\n    if verdicts is None:\n        d = cards / \"대기\""),
                                       ("    if root is not None and now is not None:", "    if root is not None and now is not None and disk_only:")], "s_wait9 and ref"),
    "V-a13 2시간 창 삭제(모든 waiting 뺌)": (DETECT, [("    return now - max(float(row[\"updated\"]), last or 0.0) < NUDGE_WINDOW_S", "    return True")], "s_wait10"),
    "V-a14 사람도 2시간 창": (DETECT, [("    if row[\"reason\"] in HUMAN_WAIT:\n        return True", "    if False:\n        return True")], "s_wait1_s_wait11"),
    "V-a15 a_card_nudged 무시": (DETECT, [("    last = nudged.get(stem)", "    last = None")], "s_rep1"),
    "V-a16 gate 를 판정 단계 안으로": (SCAN, [("        stm.judge_done()  # r1282 — 판정 끝 기한 검사(넘으면 처리 0 · 저장 0) · 이후는 처리 단계(호출별 timeout 만)\n        found, unknown = self.gate_a(found, unknown)",
                                                "        found, unknown = self.gate_a(found, unknown)\n        stm.judge_done()")], "s_dl3"),
    "V-a18 trig 를 gate 거르기 전에 계산": (SCAN, [("        found, unknown = self.gate_a(found, unknown)", "        self._pre = found\n        found, unknown = self.gate_a(found, unknown)"),
                                              ("keys = {f\"{f['kind']}:{f['seat']}\": f for f in found if f[\"kind\"] != \"h\"}", "keys = {f\"{f['kind']}:{f['seat']}\": f for f in self._pre if f[\"kind\"] != \"h\"}")], "s_pen1 and not control"),
    "V-a19 save 에 a_card_nudged 안 넣음": (SCAN, [("self.st[\"seats\"], self.nudged, self.now)", "self.st[\"seats\"], None, self.now)")], "s_st1"),
    "V-a20 send rc 무시하고 기록": (SCAN, [("            if rc != 0:  # r1238 A-r4b-2", "            if False:  # r1238 A-r4b-2")], "s_snd1"),
    "V-a21 미래 updated 를 그대로": (DETECT, [("    if upd > now + CLOCK_SKEW_S:", "    if False:")], "s_fut1"),
    "V-a22 미래 재촉 기록 그대로": (DETECT, [("    if last is not None and last > now + CLOCK_SKEW_S:", "    if False:")], "s_fut2"),
    "V-a23 후보 밖이면 기록 지움": (SCAN, [("self.st[\"seats\"], self.nudged, self.now)", "self.st[\"seats\"], {k: v for k, v in self.nudged.items() if v == self.now}, self.now)")], "s_st3"),
}


def main(argv: list[str]) -> int:
    want = argv[0] if argv else ""
    pick = {k: v for k, v in MUTANTS.items() if want in k}
    if not pick:
        print(f"변이 없음: {want!r}")
        return 2
    tmp = Path(tempfile.mkdtemp(prefix="r1238a-mut-"))
    work = tmp / "bin"
    _ = shutil.copytree(KIT, work)
    missed = 0
    env = {**os.environ, "R1238A_BIN": str(work), "R1238A_MUTATING": "1"}
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
        _ = path.write_text(orig, encoding="utf-8")  # 다음 변이를 위해 되돌림
    shutil.rmtree(tmp, ignore_errors=True)
    print(f"RESULT 변이 {len(pick)}개 · 놓침 {missed}")
    return 1 if missed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
