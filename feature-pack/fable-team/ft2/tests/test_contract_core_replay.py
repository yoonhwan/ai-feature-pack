"""ft2 코어 상태 계약 사례표 시험 (r1546).

사례표가 원자료 관측과 1:1 인지, 그리고 표가 망가지면 검사기가 FAIL 하는지(변이 M1~M3) 본다.
원자료(BYZ `judge-output-r3.json`)는 읽기만 한다 — `git show` 로 읽고 복사하지 않는다.
"""
import importlib.util
import json
import os
import shutil

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
FT2 = os.path.dirname(HERE)
CORE = os.path.join(FT2, "contracts", "core")
CASES = os.path.join(CORE, "cases")

BYZ_DEFAULT = "/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents"
RAW_SHA = "db18c453c77868355ffeb813d3b4c49f2047806a"
RAW_PATH = ("design/harness/research/ft-2.0/sim-atomic-json/"
            "checker-r1497/judge-output-r3.json")

_SPEC = importlib.util.spec_from_file_location("ft2_core_replay",
                                               os.path.join(CORE, "replay_check.py"))
replay = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(replay)

_JUDGE = {}


def judge():
    """원자료를 읽는다 — 없으면 skip 없이 실패한다(no silent fallback)."""
    if "doc" not in _JUDGE:
        direct = os.environ.get("FT20_JUDGE_JSON")
        repo = os.environ.get("FT20_BYZ_REPO") or BYZ_DEFAULT
        if direct:
            _JUDGE["doc"] = replay.load_judge(direct)
        elif os.path.exists(os.path.join(repo, ".git")):
            _JUDGE["doc"] = replay.load_judge("git:%s@%s@%s" % (repo, RAW_SHA, RAW_PATH))
        else:
            pytest.fail("원자료 없음: FT20_JUDGE_JSON 또는 FT20_BYZ_REPO 를 지정해야 한다")
    return _JUDGE["doc"]


def results(cases_dir=CASES):
    return {name: (ok, detail) for name, ok, detail in replay.run_checks(cases_dir, judge())}


def write_case(folder, name, mutate):
    path = os.path.join(folder, name)
    with open(path, "rb") as fh:
        doc = json.loads(fh.read().decode("utf-8"))
    mutate(doc)
    with open(path, "wb") as fh:
        fh.write(json.dumps(doc, ensure_ascii=False, indent=2).encode("utf-8"))


def mutated(tmp_path, mutate):
    folder = str(tmp_path / "cases")
    shutil.copytree(CASES, folder)
    mutate(folder)
    return results(folder)


def test_A_case_count_and_ids():
    ok, detail = results()["A 사례 수·id"]
    assert ok, detail


def test_B_columns_and_contract_words():
    ok, detail = results()["B 칸·결과 낱말"]
    assert ok, detail


def test_C_replay_against_raw_observations():
    ok, detail = results()["C 관측 1:1"]
    assert ok, detail


def test_D_nonadopted_marked():
    ok, detail = results()["D 비채택 표시"]
    assert ok, detail


def test_E_literal_names_only_in_source():
    ok, detail = results()["E 의미 이름"]
    assert ok, detail


def test_cases_md_table_matches_files():
    with open(os.path.join(CORE, "CASES.md"), "rb") as fh:
        text = fh.read().decode("utf-8")
    rows = [line for line in text.splitlines() if line.startswith("| case_")]
    files = [n for n in os.listdir(CASES) if n.endswith(".json") and not n.startswith("_")]
    assert len(rows) == len(files) == replay.CASE_COUNT, (len(rows), len(files))


def test_M1_changed_expect_fails_C(tmp_path):
    def change(folder):
        write_case(folder, "02-concurrent-4x300.json",
                   lambda doc: doc["expect"]["관측 대조"][2]["관측"].update({"busy": 1922}))

    assert not mutated(tmp_path, change)["C 관측 1:1"][0]


def test_M2_deleted_case_fails_A(tmp_path):
    def drop(folder):
        os.unlink(os.path.join(folder, "07-effect-crash.json"))

    assert not mutated(tmp_path, drop)["A 사례 수·id"][0]


def test_M3_unknown_result_word_fails_B(tmp_path):
    def word(folder):
        write_case(folder, "01-happy-life.json",
                   lambda doc: doc["expect"].update({"처리 결과": "PARTIAL"}))

    assert not mutated(tmp_path, word)["B 칸·결과 낱말"][0]


def test_missing_table_is_error_not_empty_pass(tmp_path):
    with pytest.raises(replay.TableBroken):
        replay.run_checks(str(tmp_path / "없는폴더"), judge())
