"""r1930 나노 산출을 팀 DA 에 직접 — 첫 본문(launch_plan.first_body) 반례 ①~⑥ · 변이 M1~M3.
명부는 임시 root 의 `.fable-team/seats-<팀>.json` 뿐 · 실 명부·실 좌석·바깥 호출 0 · sleep 0.
변이는 launch_plan.py 사본에서만 · 변이마다 원본으로 같은 사례 1회 더(⑤ 기존 launch·role 시험은 묶음 실행으로 본다).
"""
import importlib.util, json  # noqa: E401
from pathlib import Path
import pytest

SRC = Path(__file__).resolve().parents[1] / "adapters" / "pi" / "launch_plan.py"
DA, NANO, ROW = "byz-harness-da-codex#10", "byz-harness-nano-x#1", ("/r", "origin/main", "design/harness/indices")
BAN = ("병합", "착지", "설치", "가지 삭제")
OLD = "산출·막힘은 팀 master 에 mbox"

def load(path=SRC, name="lp_r1930"):
    spec = importlib.util.spec_from_file_location(name, str(path))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

def body(tmp, roster, lp=None):
    root = tmp / "root"
    (root / ".fable-team").mkdir(parents=True, exist_ok=True)
    if roster is not None:
        (root / ".fable-team" / "seats-harness.json").write_text(roster, encoding="utf-8")
    env = {"FT2_ROOT": str(root), "FT2_TEAM": "harness", "FT2_WORK": "r9", "FT2_ATTEMPT": "a1", "FT2_HOLDER": NANO}
    mark, text = (lp or load()).first_body(env, ROW)
    assert mark == "[발주] ft2 harness r9@a1" and text.startswith(mark + " 좌석 " + NANO), text   # body_mark·머리 유지
    return str(root), text

def c1(tmp, lp=None):   # ① _da 있음 → DA 좌석 이름 · PR 열기 · 막힘 = 팀 master · 5칸 이름 · 옛 master 산출 구 0
    _, text = body(tmp, json.dumps({"_da": DA, "_master": "m#1"}), lp)
    for need in ("팀 DA " + DA, "PR 열기", "막힘 = 팀 master", "대상 동결", "판정 기준", "상한", "종료 조건", "다음 수", "PR 번호"):
        assert need in text, need
    assert OLD not in text and "master 보고까지" not in text and "DA 좌석 못 읽음" not in text, text

@pytest.mark.parametrize("roster", [None, "{}", json.dumps({"_da": ""}), json.dumps({"_da": 7}), "{깨짐"])
def c2(tmp_path, roster, lp=None):   # ② _da 없음·빈 값·글자 아님·명부 없음·깨짐 → 지금 구 + «DA 좌석 못 읽음» · 무명 DA 0
    _, text = body(tmp_path, roster, lp)
    assert OLD in text and "DA 좌석 못 읽음" in text and "master 보고까지" in text and "팀 DA" not in text, text

def c3(tmp, lp=None):   # ③ 금지 목록 낱말은 두 길 모두 그대로 · claim → start 선행 유지
    for roster in (json.dumps({"_da": DA}), None):
        _, text = body(tmp, roster, lp)
        assert all(word in text for word in BAN) and "ft2_claim → ft2_start" in text and text.endswith("이 좌석에 적용 0"), text

def c4(tmp, lp=None):   # ④ HOLD 3 이면 직접 요청 0
    assert "HOLD 줄이 3 이면 DA 요청 0" in body(tmp, json.dumps({"_da": DA}), lp)[1]

def c6(tmp, lp=None):   # ⑥ root·work·gen 3구 · work 값에 «@» 0(@aN 은 attempt 칸)
    root, text = body(tmp, json.dumps({"_da": DA}), lp)
    assert "root = %s · work = r9 · gen = " % root in text and "work = r9@" not in text, text

test_c1 = lambda tmp_path: c1(tmp_path)  # noqa: E731
test_c2 = c2
test_c3 = lambda tmp_path: c3(tmp_path)  # noqa: E731
test_c4 = lambda tmp_path: c4(tmp_path)  # noqa: E731
test_c6 = lambda tmp_path: c6(tmp_path)  # noqa: E731
