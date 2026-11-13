"""r1811 가져오기 이름 열쇠 카드 · 선택 명부 시험 — 카드 반례 ① ①′ ①″ ⑤ · 변이 M1·M5·M7(사본만).

입력 = 이 파일이 만드는 작은 reconcile.json(r1802 meta.team · r1811 meta.seats 꼴)과 임시 runtime(accept 1건).
격리 tmp · 고정 시계 · --dry-run 만(held·import 쓰기 0) · 실 runtime·실 명부·1.x 원본 0 · sleep·tmux 0.
"""
import importlib.util
import io
import json
import os
import shutil
from pathlib import Path

import pytest

FT2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NOW, OK, SEAT = "2026-11-13T00:00:00", "접수 성공", "byz-v65-master-pi#292"
_N = [0]
NAMED = "F-ccu-scale-plan"                       # 이름 열쇠 카드(card_key r1779 = 확장자 뺀 이름 통째)
NUMERIC = (("r1774", "r1774-legacy-import.md"), ("r12", "r12-title.md"))   # canonical 숫자 key(card_key 출력)
BAD = ("card/r12-title", "card/a/b", "card/x.md")  # 숫자 카드 leaf 를 이름으로 · 경로 · 확장자


def _load(ft2, sub, name):
    _N[0] += 1
    spec = importlib.util.spec_from_file_location("r1811_%s_%d" % (name, _N[0]), os.path.join(ft2, sub, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _card(key, leaf, team):
    return {"cat": "카드", "id": leaf[:-3], "loc": "design/teams/%s/indices/대기/%s" % (team, leaf),
            "decision": "옮김", "target_id": "2.0 record: card/" + key}


def _world(tmp, ft2, team, rows, meta_extra=None, seats=None):
    """임시 root(runtime 1건) + 카드 원본 + (선택) 명부 → reconcile.json 경로."""
    root, cards = Path(tmp) / "root", Path(tmp) / "cards"
    os.makedirs(str(root / ".fable-team"))
    assert _load(ft2, "core", "intake").Intake(str(root), team, clock=lambda: NOW).submit(
        "r1811", "hello", "r1811").result == OK
    for row in rows:
        if row["cat"] == "카드":
            os.makedirs(str((cards / row["loc"]).parent), exist_ok=True)
            (cards / row["loc"]).write_text("# %s\n본문\n" % row["id"], encoding="utf-8")
    for name, body in (seats or {}).items():
        (root / ".fable-team" / name).write_text(json.dumps(body, ensure_ascii=False), encoding="utf-8")
    meta = dict({"root": str(root), "cards_root": str(cards), "rules": [], "team": team}, **(meta_extra or {}))
    rec = Path(tmp) / "reconcile.json"
    rec.write_text(json.dumps({"meta": meta, "rows": rows}, ensure_ascii=False), encoding="utf-8")
    return str(root), str(rec)


def _dry(ft2, team, root, rec):
    buf = io.StringIO()
    rc = _load(ft2, "tools", "legacy_import").main(
        ["--root", root, "--team", team, "--reconcile", rec, "--dry-run"], out=buf)
    lines = buf.getvalue().strip().splitlines()
    return rc, lines[-1], lines


def _seat_row(loc):
    return {"cat": "명부", "id": SEAT, "loc": loc, "decision": "옮김", "target_id": "2.0 seat/" + SEAT}


# ---- 사례 (ft2 = 원본 또는 변이 사본) ----

def case_named(tmp, ft2=FT2):                                      # ① 이름 열쇠 카드 → plan 1행 · Skip 0
    rows = [_card(NAMED, NAMED + ".md", "ccu")]
    rc, last, lines = _dry(ft2, "ccu", *_world(tmp, ft2, "ccu", rows))
    assert rc == 0 and last.startswith("가져온 수 1 ") and "누락 0" in last, lines
    assert _load(ft2, "tools", "legacy_import")._key(rows[0])[0] == "card/" + NAMED


def case_numeric(tmp, ft2=FT2):                                    # ①′ canonical 숫자 key 그대로 통과(M7)
    rows = [_card(key, leaf, "ccu") for key, leaf in NUMERIC]
    rc, last, lines = _dry(ft2, "ccu", *_world(tmp, ft2, "ccu", rows))
    assert rc == 0 and last.startswith("가져온 수 2 ") and "누락 0" in last, lines


def case_bad_keys(tmp, ft2=FT2):                                   # ①″ 숫자 leaf 이름 · / · .md → «대상 미상»(M1)
    tool = _load(ft2, "tools", "legacy_import")
    for target in BAD:                                            # 변이가 잡히도록 AssertionError 로만 떨어진다
        try:
            got = tool._key({"target_id": "2.0 record: " + target})
        except tool.Skip as why:
            got = str(why)
        assert got == "대상 미상", (target, got)
    rows = [dict(_card("r12", "r12-title.md", "ccu"), target_id="2.0 record: " + target) for target in BAD]
    rc, last, lines = _dry(ft2, "ccu", *_world(tmp, ft2, "ccu", rows))
    assert rc == 1 and "누락 3" in last and "누락 사유: 대상 미상 3" in lines, lines


def case_meta_seats(tmp, ft2=FT2):                                 # ⑤ meta.seats 명부 = 원본 1 · Skip 0(M5)
    seats = {"seats.json": {"_label": "v65", "_master": SEAT, SEAT: {"role": "master"}}}
    root, rec = _world(tmp, ft2, "v65", [_seat_row(".fable-team/seats.json")], {"seats": "seats.json"}, seats)
    rc, last, lines = _dry(ft2, "v65", root, rec)
    assert rc == 0 and last.startswith("가져온 수 1 ") and "누락 0" in last, lines


def case_default_seats(tmp, ft2=FT2):                              # ⑤ meta.seats 없음 = 지금 그대로(seats-<팀>.json)
    seats = {"seats-cfo.json": {SEAT: {"role": "master"}}}
    rc, last, lines = _dry(ft2, "cfo", *_world(Path(tmp) / "a", ft2, "cfo", [_seat_row(".fable-team/seats-cfo.json")],
                                             None, seats))
    assert rc == 0 and "누락 0" in last, lines
    seats = {"seats.json": {SEAT: {"role": "master"}}}             # meta.seats 없음 + seats.json = 지금처럼 «팀 밖»
    rc, last, lines = _dry(ft2, "cfo", *_world(Path(tmp) / "b", ft2, "cfo", [_seat_row(".fable-team/seats.json")],
                                             None, seats))
    assert rc == 1 and any("팀 밖" in line for line in lines), lines


def case_other_seats(tmp, ft2=FT2):                                # ⑤ meta.seats 와 다른 명부 = «팀 밖»
    seats = {"seats-x.json": {SEAT: {"role": "master"}}}
    root, rec = _world(tmp, ft2, "v65", [_seat_row(".fable-team/seats-x.json")], {"seats": "seats.json"}, seats)
    rc, last, lines = _dry(ft2, "v65", root, rec)
    assert rc == 1 and any("팀 밖" in line for line in lines), lines


@pytest.mark.parametrize("case", [case_named, case_numeric, case_bad_keys, case_meta_seats, case_default_seats,
                                  case_other_seats])
def test_case(tmp_path, case):
    case(str(tmp_path))


def test_source_old_call_keeps_default(tmp_path):                 # h 의 6인자 호출(meta 없음) = 지금 꼴 그대로
    tool = _load(FT2, "tools", "legacy_import")
    root = tmp_path / "root"
    os.makedirs(str(root / ".fable-team"))
    (root / ".fable-team" / "seats-cfo.json").write_text(json.dumps({SEAT: {"role": "m"}}), encoding="utf-8")
    row = _seat_row(".fable-team/seats-cfo.json")
    assert json.loads(tool._source(str(root), str(root), "cfo", row, "seat", SEAT)) == {"role": "m"}


# ---- 변이(사본만 · 변이마다 원본으로 같은 사례 1회 더) ----

def _mutant(tmp, *edits):
    dst = Path(tmp) / "ft2m"
    for sub in ("core", "tools"):
        shutil.copytree(os.path.join(FT2, sub), str(dst / sub), ignore=shutil.ignore_patterns("__pycache__"))
    for rel, old, new in edits:
        text = (dst / rel).read_text(encoding="utf-8")
        assert text.count(old) == 1, (rel, old)
        (dst / rel).write_text(text.replace(old, new), encoding="utf-8")
    return str(dst)


TOOL = "tools/legacy_import.py"
CARD = r"card/(?:r\d+|(?!r\d+[-_]|.*\.md$)[^/\n\t]+)"
MUTANTS = {
    "M1": ([(TOOL, CARD, "card/.+")], case_bad_keys),
    "M5": ([(TOOL, '(meta or {}).get("seats")', "None")], case_meta_seats),
    "M7": ([(TOOL, CARD, r"card/(?:(?!r\d+$)(?!r\d+[-_]|.*\.md$)[^/\n\t]+)")], case_numeric),
}


@pytest.mark.parametrize("name", sorted(MUTANTS))
def test_mutant_caught(tmp_path, name):
    edits, case = MUTANTS[name]
    ft2 = _mutant(tmp_path, *edits)                                  # 변이 자리 없음 = 여기서 FAIL(삼키지 않음)
    with pytest.raises(AssertionError):
        case(str(tmp_path / "m"), ft2)
    case(str(tmp_path / "orig"))                                    # 원본으로 같은 사례 1회 더 = PASS
