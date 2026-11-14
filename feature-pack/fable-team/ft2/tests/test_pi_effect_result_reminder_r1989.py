"""r1989 — ft2_effect 뒤 ft2_result 를 알리는 말 2곳(도구 설명 · effect 성공 응답 끝줄 = 두 번째 content · 첫 content 는 cli JSON 그대로)."""
import json
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_pi_seat_adapter as S  # 같은 가짜 pi·래퍼·격리 루트를 그대로 쓴다

DRIVER = S.DRIVER.replace("text: r.content[0].text", "texts: r.content.map((c) => c.text)")
MUST, NEXT = "ft2_result 1회 필수", f"다음: ft2_result {S.WORK} {S.HOLDER} {S.GEN}"
ERR = "if (run.rc !== 0) return { content: [{ type: \"text\" as const, text }"
MUTANTS = {"M1": ("+ EFFECT_NEXT", ""), "M2": (ERR, ERR + ", ...nextLine(spec.verb, params)")}  # M1 설명 삭제 · M2 모든 결과에 줄


def go(tmp_path, adapter, payload):
    proc = subprocess.run([S.NODE, "--input-type=module", "-e", DRIVER], input=json.dumps(payload), capture_output=True, text=True, check=False,
                          timeout=60, env={"PATH": os.environ["PATH"], "HOME": str(tmp_path), **S.seat(tmp_path, adapter)["env"]})
    assert proc.returncode == 0, proc.stderr[-800:]
    return json.loads(proc.stdout)


def verdict(tmp_path, adapter=None):
    """(① 설명에 필수 문장 · ② effect OK 끝줄 = 다음 ft2_result · ③ 거절·유보·다른 동사엔 그 줄 0)."""
    desc = {t["name"]: t["description"] for t in go(tmp_path, adapter, {"op": "register"})["tools"]}
    S.prepare(root := tmp_path / "root", S.BASE)
    cases = [{"tool": n, "params": S.params(n, root) | kw} for n, kw in (("ft2_claim", {}), ("ft2_start", {}),
             ("ft2_effect", {}), ("ft2_effect", {"gen": 99}), ("ft2_effect", {"effect": "e2"}))]
    rows = go(tmp_path, adapter, {"op": "run", "cwd": str(root), "cases": cases})
    one = MUST in desc["ft2_effect"] and not [n for n, d in desc.items() if n != "ft2_effect" and MUST in d]
    two = rows[2]["isError"] is False and rows[2]["texts"][1:] == [NEXT] and json.loads(rows[2]["texts"][0])["result"] == "접수 성공"
    three = ([len(r["texts"]) for r in rows[:2] + rows[3:]] == [1] * 4 and rows[3]["isError"] and rows[4]["isError"]
             and "낡은 실행권" in rows[3]["texts"][0] and "완료 유보" in rows[4]["texts"][0])
    return one, two, three


def test_effect_reminder_description_ok_line_and_none_on_refused(tmp_path):
    assert verdict(tmp_path) == (True, True, True)


def test_mutants_break_their_cases(tmp_path):
    for name, want in {"M1": (False, True, True), "M2": (True, True, False)}.items():
        (tmp_path / name).mkdir()
        assert verdict(tmp_path / name, S.mutant(tmp_path / name, MUTANTS[name])) == want, name
