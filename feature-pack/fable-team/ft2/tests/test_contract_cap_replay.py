"""ft2 기록 cap·회전 계약 사례표 시험 (r1548).

사례표가 checker 원자료 관측과 1:1 인지, 그리고 표가 망가지면 검사기가 FAIL 하는지(변이 M1~M3) 본다.
원자료(BYZ `journal-cap-v4-checker/results/*.json`)는 읽기만 한다 — `git show` 로 읽고 복사하지 않는다.
"""
import importlib.util
import json
import os
import shutil

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
FT2 = os.path.dirname(HERE)
CAP = os.path.join(FT2, "contracts", "cap")
CASES = os.path.join(CAP, "cases")

BYZ_DEFAULT = "/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents"

_SPEC = importlib.util.spec_from_file_location("ft2_cap_replay", os.path.join(CAP, "replay_check.py"))
replay = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(replay)

_SOURCES = {}


def sources():
    """원자료를 읽는다 — 없으면 skip 없이 실패한다(no silent fallback)."""
    if "doc" not in _SOURCES:
        repo = os.environ.get("FT20_BYZ_REPO") or BYZ_DEFAULT
        if not os.path.exists(os.path.join(repo, ".git")):
            pytest.fail("원자료 없음: FT20_BYZ_REPO 를 지정해야 한다")
        manifest = replay.read_json(os.path.join(CASES, "_source.json"))
        _SOURCES["doc"] = replay.load_sources(manifest, repo)
    return _SOURCES["doc"]


def results(cases_dir=CASES):
    return {name: (ok, detail) for name, ok, detail in replay.run_checks(cases_dir, sources())}


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


def test_F_word_bound_to_observation():
    ok, detail = results()["F 낱말 결속"]
    assert ok, detail


def test_D_numbers_marked_candidate():
    ok, detail = results()["D 후보값 표식"]
    assert ok, detail


def test_E_no_open_job_delete_expect():
    ok, detail = results()["E 미처리 삭제 0"]
    assert ok, detail


def test_B_literal_names_only_in_source():
    ok, detail = results()["B 칸·결과 낱말"]
    assert ok, detail


def test_checker_rows_are_not_cases():
    assert all(name.endswith(".json") for name in os.listdir(CASES))
    files = [n for n in os.listdir(CASES) if n.endswith(".json") and not n.startswith("_")]
    assert len(files) == replay.CASE_COUNT


def test_cases_md_table_matches_files():
    with open(os.path.join(CAP, "CASES.md"), "rb") as fh:
        text = fh.read().decode("utf-8")
    rows = [line for line in text.splitlines() if line.startswith("| case_")]
    files = [n for n in os.listdir(CASES) if n.endswith(".json") and not n.startswith("_")]
    assert len(rows) == len(files) == replay.CASE_COUNT, (len(rows), len(files))


def test_M1_changed_expect_fails_C(tmp_path):
    def change(folder):
        write_case(folder, "03-full-crash-recover.json",
                   lambda doc: doc["expect"]["관측 대조"][2].update({"관측": 8276931}))

    assert not mutated(tmp_path, change)["C 관측 1:1"][0]


def test_M2_deleted_case_fails_A(tmp_path):
    def drop(folder):
        os.unlink(os.path.join(folder, "02-reclaim-crash-resume.json"))

    assert not mutated(tmp_path, drop)["A 사례 수·id"][0]


def test_M3_open_job_delete_expect_fails_E(tmp_path):
    def word(folder):
        write_case(folder, "01-segment-reclaim.json",
                   lambda doc: doc["expect"].update({"근거 검증": "DROP_OLDEST 로 미처리를 지운다"}))

    assert not mutated(tmp_path, word)["E 미처리 삭제 0"][0]


def test_DA_R1_reject_word_as_success_fails_F(tmp_path):
    """DA R1 변이 — 포화 거절(용량 부족)을 «접수 성공» 으로 바꾸면 결속이 깨져 rc≠0."""
    def word(folder):
        write_case(folder, "03-full-crash-recover.json",
                   lambda doc: doc["expect"].update({"처리 결과": "접수 성공"}))

    assert not mutated(tmp_path, word)["F 낱말 결속"][0]


def test_DA_R1_opposite_direction_also_fails_F(tmp_path):
    def word(folder):
        write_case(folder, "01-segment-reclaim.json",
                   lambda doc: doc["expect"].update({"처리 결과": "용량 부족"}))

    assert not mutated(tmp_path, word)["F 낱말 결속"][0]


def test_missing_table_is_error_not_empty_pass(tmp_path):
    with pytest.raises(replay.TableBroken):
        replay.run_checks(str(tmp_path / "없는폴더"), sources())


def test_missing_case_limit_file_is_error(tmp_path):
    folder = str(tmp_path / "cases")
    shutil.copytree(CASES, folder)
    os.unlink(os.path.join(folder, "_checker.json"))
    with pytest.raises(replay.TableBroken):
        replay.run_checks(folder, sources())
