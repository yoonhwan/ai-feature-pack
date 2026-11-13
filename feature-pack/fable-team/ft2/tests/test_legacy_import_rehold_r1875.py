"""r1875 held 다시 쓰기(--rehold) 시험 — 카드 반례 ①~⑦ · 변이 M1~M3(사본만).

세계 = r1774 시험의 작은 reconcile(카드 3 · 쪽지 1 · 명부 1) + meta.inventory(카드 수집 sha).
격리 tmp · 실 runtime·실 held·실 원본 0 · sleep·tmux 0.
"""
import importlib.util
import json
import os
from pathlib import Path

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
_SPEC = importlib.util.spec_from_file_location("r1875_base", os.path.join(HERE, "test_legacy_import_r1774.py"))
B = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(B)
KEY, OLD = "card/r1001", "옛 본문\n".encode("utf-8")
REAL5 = ["r1798a-dream-baseline-eval-form", "r1798b-memory-store-core", "r1798c-memory-boot-inject",
         "r1798d-memory-switch-rule-dream", "r1798e-memory-model-dream-eval-round1"]


def _world(tmp, ft2):
    """held 에 옛 사본이 먼저 있는 카드 1행(card/r1001) + 수집 sha = 지금 원본."""
    w = B._world(tmp, ft2)
    data = json.loads(Path(w.rec).read_text(encoding="utf-8"))
    items = [dict(loc=row["loc"], sha256=B._sha((w.cards / row["loc"]).read_bytes()))
             for row in data["rows"] if row["cat"] == "카드"]
    inv = Path(tmp) / "inventory.json"
    inv.write_text(json.dumps({"meta": {}, "items": items}, ensure_ascii=False), encoding="utf-8")
    data["meta"]["inventory"] = str(inv)
    Path(w.rec).write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    w.src = w.cards / B._card(1001, "a")["loc"]
    w.hpath = w.held / "card" / w.src.name
    w.hpath.parent.mkdir(parents=True)
    w.hpath.write_bytes(OLD)
    return w


def _prevs(w):
    return sorted(p.name for p in w.hpath.parent.iterdir() if ".prev-" in p.name)


def _import_sha(w):
    return [rec["sha256"] for rec in B._imports(w.rt) if rec["key"] == KEY]


def case_rehold(tmp, ft2=B.FT2):                                    # ①
    w = _world(tmp, ft2)
    new = w.src.read_bytes()
    rc, last, lines = B._run(w, "--rehold")
    assert rc == 0 and last.startswith("가져온 수 5 "), (rc, lines)
    assert KEY in B._state(w.rt)["imported"] and _import_sha(w) == [B._sha(new)]
    assert len(_prevs(w)) == 1 and (w.hpath.parent / _prevs(w)[0]).read_bytes() == OLD
    assert w.hpath.read_bytes() == new and w.src.read_bytes() == new


def case_changed_after_inventory(tmp, ft2=B.FT2):                   # ④
    w = _world(tmp, ft2)
    w.src.write_bytes(b"changed after inventory\n")
    rc, _last, lines = B._run(w, "--rehold")
    assert rc == 2 and any(l.startswith("판정 불가 %s:" % KEY) for l in lines), (rc, lines)
    assert KEY not in B._state(w.rt)["imported"] and w.hpath.read_bytes() == OLD and _prevs(w) == []


def case_imported_then_changed(tmp, ft2=B.FT2):                     # ⑦
    w = _world(tmp, ft2)
    w.hpath.unlink()
    assert B._run(w)[0] == 0                                        # 지금 원본으로 가져옴
    held = w.hpath.read_bytes()
    w.src.write_bytes(b"changed after import\n")
    data = json.loads(Path(w.rec).read_text(encoding="utf-8"))      # 수집값도 새 원본(M2 로 막히지 않게)
    inv = json.loads(Path(data["meta"]["inventory"]).read_text(encoding="utf-8"))
    for item in inv["items"]:
        item["sha256"] = B._sha(w.src.read_bytes()) if item["loc"] == B._card(1001, "a")["loc"] else item["sha256"]
    Path(data["meta"]["inventory"]).write_text(json.dumps(inv, ensure_ascii=False), encoding="utf-8")
    rc, _last, lines = B._run(w, "--rehold")
    assert "이미 가져옴 %s: 원본 바뀜 = 보존" % KEY in lines, lines
    assert w.hpath.read_bytes() == held and _import_sha(w) == [B._sha(held)] and _prevs(w) == []


def test_c1_rehold_imports_and_keeps_prev(tmp_path):
    case_rehold(tmp_path)


def test_c2_without_flag_unchanged(tmp_path):
    w = _world(tmp_path, B.FT2)
    rc, _last, lines = B._run(w)
    assert rc == 2 and "복구 필요 %s: held 사본 sha 다름 = 그 행 쓰기 0" % KEY in lines
    assert KEY not in B._state(w.rt)["imported"] and w.hpath.read_bytes() == OLD and _prevs(w) == []


def test_c3_twice_no_extra_prev(tmp_path):
    w = _world(tmp_path, B.FT2)
    assert B._run(w, "--rehold")[0] == 0
    rc, last, _ = B._run(w, "--rehold")
    assert rc == 0 and "가져온 수 0 · 건너뜀 5(이미 가져옴 5 · 겹침 0)" in last and len(_prevs(w)) == 1, last


def test_c4_source_changed_after_inventory(tmp_path):
    case_changed_after_inventory(tmp_path)


def test_c5_prev_name_collision_numbered(tmp_path):
    w = _world(tmp_path, B.FT2)
    mod = B._load(w.ft2, "tools", "legacy_import")
    mod._ts = lambda: "20261113T000000"
    taken = w.hpath.parent / (w.hpath.name + ".prev-20261113T000000")
    taken.write_bytes(b"taken")
    rc = mod.main(["--root", w.root, "--team", B.TEAM, "--reconcile", w.rec, "--rehold"], out=B.io.StringIO())
    assert rc == 0 and taken.read_bytes() == b"taken"
    assert (w.hpath.parent / (taken.name + ".1")).read_bytes() == OLD


def test_c6_real_r1798_targets_read(tmp_path):
    mod = B._load(B.FT2, "tools", "legacy_import")
    for slug in REAL5:
        row = {"target_id": "2.0 record: card/" + slug, "loc": "design/harness/indices/대기/%s.md" % slug}
        assert mod._key(row) == ("card/" + slug, "card", slug)


def test_c7_imported_key_held_untouched(tmp_path):
    case_imported_then_changed(tmp_path)


MUTANTS = {
    "M1_prev_move_removed": (case_rehold, "os.link(path, dst)", "pass"),
    "M2_inventory_check_removed": (case_changed_after_inventory, "inv.get(str(row.get(\"loc\"))) != _sha(data)",
                                   "False"),
    "M3_import_check_removed": (case_imported_then_changed, "args.rehold and key in", "False and key in"),
}


@pytest.mark.parametrize("name", sorted(MUTANTS))
def test_mutant_caught(tmp_path, name):
    case, old, new = MUTANTS[name]
    assert B._caught(case, tmp_path, B._mutant(tmp_path, ("tools/legacy_import.py", old, new)))
