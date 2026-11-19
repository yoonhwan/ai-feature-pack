"""r2281 승계 끝 구 나노 닫기 변이 M1~M4 (카드 «변이» · 사본 ft2 에서만 · 변이마다 원본으로 같은 사례 1회 더) — 사례 파일과 70초 나눔.
M1 계보 확인 끔 → ② FAIL · M2 조상 확인 끔 → ③ⓑ FAIL · M3 재개 기록을 kill 뒤로 → ⑤′ FAIL(기록 0 인데 kill 1) ·
M4 uuid 고르기 = 가장 늦은 jsonl 1개 → ⑤ⓒ FAIL. (⑤ = jsonl 0 은 C3 턴 끝 근거에서 먼저 걸려 kill 앞 · M3 은 C3 를 지나는 ⑤′ 로 본다.)
"""
import importlib.util
import shutil
from pathlib import Path

import pytest

FT2 = Path(__file__).resolve().parents[1]
_spec = importlib.util.spec_from_file_location("r2281_cases_for_mut", str(FT2 / "tests" / "test_pi_keeper_close_old_r2281.py"))
C = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(C)
KO = "adapters/pi/keeper_close_old.py"
KILL = 'k.call([k.tmux, "kill-session", "-t", "=" + seat])'
MUTANTS = {"M1": ((("or new not in alive or not lineage(seat, new):", "or new not in alive:"),), "②"),
           "M2": ((('if new_tree and k.git(new_tree, "merge-base", "--is-ancestor", head, "HEAD")[0] == 0:', "if True:"),), "③ⓑ"),
           "M3": ((("why = self.resume(seat, new, intent)", "why = (%s, self.resume(seat, new, intent))[1]" % KILL),
                   ("            return k.log(\"판정 불가\", team, \"%s %s 재개 기록 %s — 닫기 0\" % (work, seat, why))\n        " + KILL,
                    "            return k.log(\"판정 불가\", team, \"%s %s 재개 기록 %s — 닫기 0\" % (work, seat, why))\n        None")), "⑤′"),
           "M4": ((("if len(files) != 1 or born is None", "if not files or born is None"), ("log = files[0]", "log = max(files, key=os.path.getmtime)")), "⑤ⓒ")}


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    pairs, label = MUTANTS[name]
    case, kv = C.CASES[label]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / KO).read_text(encoding="utf-8")
    for old, new in pairs:
        assert text.count(old) == 1, (name, old)
        text = text.replace(old, new)
    (tree / KO).write_text(text, encoding="utf-8")
    for sub in ("w1", "w2"):
        (tmp_path / sub).mkdir()
    with pytest.raises(AssertionError):
        case(C.world(tmp_path / "w1", monkeypatch, ft2=tree, **kv))
    case(C.world(tmp_path / "w2", monkeypatch, **kv))   # 원본으로 같은 사례 1회 더 = PASS
