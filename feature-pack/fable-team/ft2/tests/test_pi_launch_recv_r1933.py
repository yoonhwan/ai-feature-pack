"""r1933 ⑩ — 2.0 나노 첫 본문(launch_plan.first_body)에 recv 1구 + r1930 승인 문구 그대로 · 변이 M6(recv 구 삭제 → FAIL).
임시 root 명부뿐 · 바깥 호출 0 · sleep 0.
"""
import importlib.util, json  # noqa: E401
from pathlib import Path
import pytest
SRC = Path(__file__).resolve().parents[1] / "adapters" / "pi" / "launch_plan.py"
NANO, DA = "byz-harness-nano-x#1", "byz-harness-da-codex#10"
def load(path=SRC, name="lp_r1933"):
    spec = importlib.util.spec_from_file_location(name, str(path))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod
def c10(tmp, lp=None):
    root = tmp / "root"
    (root / ".fable-team").mkdir(parents=True)
    (root / ".fable-team" / "seats-harness.json").write_text(json.dumps({"_da": DA}), encoding="utf-8")
    env = {"FT2_ROOT": str(root), "FT2_TEAM": "harness", "FT2_WORK": "r9", "FT2_ATTEMPT": "a1", "FT2_HOLDER": NANO}
    text = (lp or load()).first_body(env, ("/r", "origin/main", "design/harness/indices"))[1]
    recv = "쪽지 = bash %s/.fable-team/comm/mbox.sh recv %s · " % (root, NANO)
    assert text.count(recv) == 1 and text.index("gen = ft2_claim 이 돌려준 값 · " + recv) < text.index("ft2_claim → ft2_start"), text
    for need in ("팀 DA " + DA, "PR 열기", "HOLD 줄이 3 이면 DA 요청 0", "병합", "가지 삭제"):
        assert need in text, need
    assert text.endswith("이 좌석에 적용 0"), text
def test_c10(tmp_path):
    c10(tmp_path)
def test_m6(tmp_path):
    text, old = SRC.read_text(encoding="utf-8"), '    tail = RECV % (env.get("FT2_ROOT"), env["FT2_HOLDER"]) + tail'
    assert text.count(old) == 1
    (tmp_path / "launch_plan.py").write_text(text.replace(old, ""), encoding="utf-8")
    with pytest.raises(AssertionError):
        c10(tmp_path / "m", load(tmp_path / "launch_plan.py", "lp_m6"))
    c10(tmp_path / "o")
