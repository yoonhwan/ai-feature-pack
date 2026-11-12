"""r1774 1.x→2.0 가져오기 시험 — 카드 반례 ①~⑦ · DESIGN §8 ⑧~⑪ · 변이 M1~M8(사본만).

입력 = 이 파일이 만드는 작은 reconcile.json(카드 3 · 쪽지 1 · 명부 1)과 core 시험 꼴 r1767(accept + claim).
contracts 사례표가 아니다. 실제 BYZ 원자료는 FT20_BYZ_REPO 의 reconcile.json 줄 길이 확인 1건만 읽는다(쓰기 0).
격리 tmp · 고정 시계 · 실 runtime·실 held·1.x 원본 0 · sleep·tmux 0. 중단 = on_step 예외(Boom).
"""
import hashlib
import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

FT2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEAM, NOW, HOLDER, SEAT = "harness", "2026-11-13T00:00:00", "byz-harness-nano-x#0", "byz-harness-arch-pi#9"
OK, FULL = "접수 성공", "용량 부족"
BYZ = os.environ.get("FT20_BYZ_REPO", "/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents")
REAL = "origin/ops/main-base:design/harness/research/ft-2.0/migrate-harness-r1676/reconcile.json"
Boom = type("Boom", (RuntimeError,), {})
_N = [0]


def _load(ft2, sub, name):
    _N[0] += 1
    spec = importlib.util.spec_from_file_location("r1774_%s_%d" % (name, _N[0]), os.path.join(ft2, sub, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _sha(data):
    return hashlib.sha256(data).hexdigest()


def _card(n, slug):
    return {"cat": "카드", "id": "r%d-%s" % (n, slug), "loc": "design/harness/indices/대기/r%d-%s.md" % (n, slug),
            "decision": "옮김", "target_id": "2.0 record: card/r%d" % n}


def _world(tmp, ft2=FT2, team=None, r1767=True, seats="seats-harness.json", extra=()):
    root, cards = Path(tmp) / "root", Path(tmp) / "cards"
    os.makedirs(str(root / ".fable-team" / "comm"))
    if r1767:
        intake, execution = _load(ft2, "core", "intake"), _load(ft2, "core", "execution")
        assert intake.Intake(str(root), TEAM, clock=lambda: NOW).submit("r1767", "hello", "r1767").result == OK
        assert execution.Execution(str(root), TEAM, clock=lambda: NOW).claim("r1767", HOLDER).result == OK
    rows = [_card(1001, "a"), _card(1002, "b"), _card(1003, "c")] + list(extra)
    for row in rows:
        os.makedirs(str((cards / row["loc"]).parent), exist_ok=True)
        (cards / row["loc"]).write_text("# %s\n본문\n" % row["id"], encoding="utf-8")
    lines = [{"seq": 40, "to": "a", "body": "x"}, {"seq": 41, "to": "byz-harness-da-codex#5", "body": "미처리"}]
    (root / ".fable-team" / "comm" / "mailbox.jsonl").write_text(
        "".join(json.dumps(line, ensure_ascii=False) + "\n" for line in lines), encoding="utf-8")
    (root / ".fable-team" / seats).write_text(json.dumps({"_name": TEAM, SEAT: {"role": "arch"}}), encoding="utf-8")
    rows += [{"cat": "미처리 쪽지", "id": "41", "loc": ".fable-team/comm/mailbox.jsonl#seq=41", "decision": "옮김",
              "target_id": "2.0 intake: mbox/41"},
             {"cat": "명부", "id": SEAT, "loc": ".fable-team/" + seats, "decision": "옮김", "target_id": "2.0 seat/" + SEAT},
             {"cat": "원장", "id": "x", "loc": "x.md", "decision": "참조", "target_id": "원문 참조: x.md"}]
    meta = dict({"root": str(root), "cards_root": str(cards), "rules": []}, **({"team": team} if team else {}))
    rec = Path(tmp) / "reconcile.json"
    rec.write_text(json.dumps({"meta": meta, "rows": rows}, ensure_ascii=False), encoding="utf-8")
    rt = root / ".fable-team" / "teams" / TEAM / "runtime"
    held = root / ".fable-team" / "state" / "ft20-switch" / (TEAM + ".held")
    return SimpleNamespace(root=str(root), rec=str(rec), rt=rt, held=held, cards=cards, ft2=ft2)


def _run(w, *extra, caps=None, on_step=None):
    buf = io.StringIO()
    rc = _load(w.ft2, "tools", "legacy_import").main(["--root", w.root, "--team", TEAM, "--reconcile", w.rec]
                                                     + list(extra), caps=caps, on_step=on_step, out=buf)
    lines = buf.getvalue().strip().splitlines()
    return rc, lines[-1], lines


def _journal(rt):
    paths = sorted(rt.glob("journal.*.jsonl"), key=lambda p: int(p.name.split(".")[1])) + [rt / "journal.jsonl"]
    return [json.loads(line) for p in paths if p.exists() for line in p.read_text(encoding="utf-8").splitlines() if line]


def _imports(rt):
    return [rec for rec in _journal(rt) if rec["kind"] == "import"]


def _state(rt):
    return json.loads((rt / "state.json").read_text(encoding="utf-8"))


def _saturate(w, slack=2000):
    usage = _load(w.ft2, "core", "journal").Journal(str(w.rt)).usage()
    return dict(total_cap=usage + slack)


def _cli(w, *args):
    proc = subprocess.run([sys.executable, os.path.join(w.ft2, "core", "cli.py")] + list(args)
                          + ["--root", w.root, "--team", TEAM], capture_output=True, text=True, timeout=25,
                          env=dict(os.environ, FT_NOW=NOW))
    return proc.returncode, json.loads(proc.stdout)


# ---- 사례 (ft2 = 원본 또는 변이 사본) ----

def case_missing(tmp, ft2=FT2):                                     # ①
    w = _world(tmp, ft2)
    os.unlink(str(w.cards / _card(1002, "b")["loc"]))
    rc, last, _ = _run(w)
    assert rc == 1 and "누락 1" in last and last.startswith("가져온 수 4 "), (rc, last)


def case_idempotent(tmp, ft2=FT2):                                  # ②
    w = _world(tmp, ft2)
    proc = subprocess.run([sys.executable, os.path.join(ft2, "tools", "legacy_import.py"), "--root", w.root,
                           "--team", TEAM, "--reconcile", w.rec], capture_output=True, text=True, timeout=25)
    assert proc.returncode == 0 and proc.stdout.strip().splitlines()[-1].startswith("가져온 수 5 "), proc.stdout
    count = len(_journal(w.rt))
    rc, last, _ = _run(w)
    assert rc == 0 and "가져온 수 0 · 건너뜀 5(이미 가져옴 5 · 겹침 0)" in last, last
    assert len(_journal(w.rt)) == count


def case_saturated(tmp, ft2=FT2):                                   # ② 보태기(R2)
    w = _world(tmp, ft2)
    assert _run(w)[0] == 0
    count, caps = len(_journal(w.rt)), _saturate(w)
    core = _load(ft2, "core", "legacy_import")
    row = dict(key="card/r1001", body="card/r1001-a.md", src="x", sha256="0" * 64, bytes=1)
    out = core.LegacyImport(w.root, TEAM, clock=lambda: NOW, caps=caps).put(row)
    assert (out.result, out.written) == (OK, False), out
    data = json.loads(Path(w.rec).read_text(encoding="utf-8"))
    data["rows"].append(_card(1004, "d"))
    (w.cards / _card(1004, "d")["loc"]).write_text("d", encoding="utf-8")
    Path(w.rec).write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    rc, last, _ = _run(w, caps=caps)
    assert rc == 1 and "이미 가져옴 5" in last and "용량 거절 1" in last, last
    assert len(_journal(w.rt)) == count


def case_sha(tmp, ft2=FT2):                                         # ③
    w = _world(tmp, ft2)
    path, seen = w.cards / _card(1003, "c")["loc"], []

    def step(name):
        if name == "after_state" and not seen:
            seen.append(name)
            path.write_text("바뀜", encoding="utf-8")
    rc, last, _ = _run(w, on_step=step)
    assert rc == 1 and "원본 sha 변화 1" in last, last


def case_team(tmp, ft2=FT2):                                        # ④
    w = _world(Path(tmp) / "a", ft2, team="feature")
    before = (w.rt / "journal.jsonl").read_bytes()
    rc, last, _ = _run(w)
    assert rc == 1 and "접수 거부" in last and (w.rt / "journal.jsonl").read_bytes() == before, last
    assert not w.held.exists()
    w = _world(Path(tmp) / "b", ft2, seats="seats-feature.json")
    rc, last, lines = _run(w)
    assert rc == 1 and "누락 1" in last and "seat/" + SEAT not in _state(w.rt)["imported"], lines
    assert any("팀 밖" in line for line in lines), lines
    w = _world(Path(tmp) / "c", ft2, r1767=False)
    rc, last, _ = _run(w)
    assert rc == 2 and not w.rt.exists(), last


def _snapshot(w):
    st = _state(w.rt)
    return {"journal": (w.rt / "journal.jsonl").read_text(encoding="utf-8").splitlines(),
            "owners": st.get("owners"), "generations": st.get("generations"), "pending": st.get("pending")}


def _preserved(before, after, imported):
    """기존 2.0 상태 보존 판정(카드 계약 6) — 문제 목록. 빈 목록 = 보존."""
    out = []
    if after["journal"][:len(before["journal"])] != before["journal"]:
        out.append("기존 journal 줄 바뀜")
    if len(after["journal"]) != len(before["journal"]) + imported:
        out.append("행 수 %d != %d + %d" % (len(after["journal"]), len(before["journal"]), imported))
    for name in ("owners", "generations", "pending"):
        if after[name] != before[name]:
            out.append(name + " 바뀜")
    if not [line for line in after["journal"] if '"kind": "claim"' in line and '"r1767"' in line]:
        out.append("claim 줄 없음")
    return out


def case_preserve(tmp, ft2=FT2, checker=_preserved):                # ⑤
    w = _world(tmp, ft2)
    before = _snapshot(w)
    assert _run(w)[0] == 0
    problems = checker(before, _snapshot(w), 5)
    assert not problems, problems
    for rec in _imports(w.rt):                                      # held 사본 sha = 원본 sha = 줄 sha256
        assert _sha((w.held / rec["body"]).read_bytes()) == rec["sha256"], rec


def case_overlap(tmp, ft2=FT2):                                     # ⑦ + 보태기(R2·R3)
    w = _world(Path(tmp) / "a", ft2, extra=[_card(1767, "x")])
    owners = _state(w.rt)["owners"]
    rc, last, _ = _run(w)
    assert rc == 0 and "가져온 수 5 · 건너뜀 1(이미 가져옴 0 · 겹침 1)" in last, last
    assert "card/r1767" not in _state(w.rt)["imported"] and _state(w.rt)["owners"] == owners
    count = len(_journal(w.rt))
    rc, last, _ = _run(w, caps=_saturate(w))
    assert rc == 0 and "겹침 1" in last and len(_journal(w.rt)) == count, last
    w = _world(Path(tmp) / "b", ft2, r1767=False)
    os.makedirs(str(w.rt))
    receipts = {"mbox/41": "mbox/41#a1"}
    (w.rt / "state.json").write_text(json.dumps({"schema": 1, "revision": 7, "pending": ["mbox/41"],
                                                 "attempts": {"mbox/41": 1}, "journal_base": {
                                                     "upto": 7, "count": 7, "receipts": receipts, "proj": {}}}))
    rc, last, _ = _run(w)
    assert "겹침 1" in last and "intake/mbox/41" not in _state(w.rt)["imported"], last
    assert [rec["key"] for rec in _imports(w.rt) if rec["key"].startswith("intake/")] == []
    assert json.dumps(_state(w.rt)["journal_base"]["receipts"]) == json.dumps(receipts)


def _raw(seq, key):
    return {"schema": 1, "team": TEAM, "seq": seq, "kind": "import", "command": "import", "attempt": "import",
            "at": NOW, "body": key, "work": None, "goal": None, "holder": None, "gen": None, "key": key,
            "src": "x", "sha256": "0" * 64, "bytes": 1}


def _put_lines(path, recs, mode="w"):
    with open(str(path), mode, encoding="utf-8") as handle:
        handle.write("".join(json.dumps(rec, ensure_ascii=False, sort_keys=True) + "\n" for rec in recs))


def case_reclaim(tmp, ft2=FT2):                                     # ⑧ 회수(R1)
    keys = ["card/r1", "card/r2", "intake/mbox/3", "seat/s4"]
    root = Path(tmp) / "root"
    rt = root / ".fable-team" / "teams" / TEAM / "runtime"
    intake, execution = _load(ft2, "core", "intake"), _load(ft2, "core", "execution")
    intake.Intake(str(root), TEAM, clock=lambda: NOW)
    _put_lines(rt / "journal.1.jsonl", [_raw(1, keys[0]), _raw(2, keys[1])])
    _put_lines(rt / "journal.2.jsonl", [_raw(3, keys[2]), _raw(4, keys[3])])
    intake.Intake(str(root), TEAM, clock=lambda: NOW).submit("r1767", "hello", "r1767")   # 뒤 non-import seq 5·6
    execution.Execution(str(root), TEAM, clock=lambda: NOW).claim("r1767", HOLDER)
    j = intake.journal.Journal(str(rt), rec=intake.record)
    out = j.reclaim()
    assert len(out["reclaimed"]) >= 1, out                          # 기준판 = reclaimed 0
    assert sorted(out["reclaimed"]) == ["journal.1.jsonl", "journal.2.jsonl"], out
    assert not (rt / "journal.1.jsonl").exists() and not (rt / "journal.2.jsonl").exists()
    base = _state(rt)["journal_base"]
    assert base["upto"] >= 4 and sorted(base["proj"].get("imported") or {}) == sorted(keys), base
    assert sorted(intake.record.recover_state(j.state(), j.records())["imported"]) == sorted(keys)
    assert j.recover()["result"] == OK and sorted(_state(rt)["imported"]) == sorted(keys)
    count = len(_journal(rt))
    imp = _load(ft2, "core", "legacy_import").LegacyImport(str(root), TEAM, clock=lambda: NOW)
    outs = [imp.put(dict(key=key, body=key, src="x", sha256="0" * 64, bytes=1)) for key in keys]
    assert [o.written for o in outs] == [False] * 4 and len(_journal(rt)) == count, outs
    root2 = Path(tmp) / "mixed"                                     # import + 열린 r1767 = 보존
    rt2 = root2 / ".fable-team" / "teams" / TEAM / "runtime"
    intake.Intake(str(root2), TEAM, clock=lambda: NOW).submit("r1767", "hello", "r1767")
    execution.Execution(str(root2), TEAM, clock=lambda: NOW).claim("r1767", HOLDER)
    _put_lines(rt2 / "journal.jsonl", [_raw(3, keys[0])], "a")
    os.replace(str(rt2 / "journal.jsonl"), str(rt2 / "journal.1.jsonl"))
    _put_lines(rt2 / "journal.jsonl", [_raw(4, keys[1])])
    out = intake.journal.Journal(str(rt2), rec=intake.record).reclaim()
    assert out["reclaimed"] == [] and (rt2 / "journal.1.jsonl").exists(), out


def case_submit_after(tmp, ft2=FT2):                                # ⑨
    w = _world(tmp, ft2)
    rc0, before = _cli(w, "project")
    assert _run(w)[0] == 0
    rc1, sub = _cli(w, "submit", "--command", "r2001", "--body", "x", "--work", "r2001")
    rc2, after = _cli(w, "project")
    assert (rc0, rc1, rc2, sub["result"]) == (0, 0, 0, OK), sub
    assert after["pending"] == before["pending"] + 1 and after["holders"] == before["holders"], (before, after)


def case_crash(tmp, ft2=FT2):                                       # ⑩
    for stop, already in (("after_held", 0), ("after_journal", 1)):
        w = _world(Path(tmp) / stop, ft2)

        def step(name, stop=stop):
            if name == stop:
                raise Boom(name)
        with pytest.raises(Boom):
            _run(w, on_step=step)
        held = {p.name: p.read_bytes() for p in w.held.rglob("*") if p.is_file() and ".tmp" not in p.parts}
        rc, last, _ = _run(w)
        assert rc == 0 and "가져온 수 %d · 건너뜀 %d(이미 가져옴 %d" % (5 - already, already, already) in last, last
        keys = [rec["key"] for rec in _imports(w.rt)]
        assert len(keys) == 5 and keys.count("card/r1001") == 1, keys
        assert all((w.held / "card" / name).read_bytes() == data for name, data in held.items()), held


def case_held_differs(tmp, ft2=FT2):                                # ⑪
    w = _world(tmp, ft2)
    os.makedirs(str(w.held / "card"))
    (w.held / "card" / "r1001-a.md").write_text("다른 사본", encoding="utf-8")
    rc, last, lines = _run(w)
    assert rc == 2 and "card/r1001" not in [rec["key"] for rec in _imports(w.rt)], lines
    assert any("복구 필요" in line for line in lines), lines


# ---- 시험 ----

def test_c1_missing_row_rc1(tmp_path):
    case_missing(tmp_path)


def test_c2_twice_no_new_rows(tmp_path):
    case_idempotent(tmp_path)


def test_c2b_saturated_already_ok_new_full(tmp_path):
    case_saturated(tmp_path)


def test_c3_source_sha_changed_rc1(tmp_path):
    case_sha(tmp_path)


def test_c4_other_team_refused(tmp_path):
    case_team(tmp_path)


def test_c5_existing_state_preserved(tmp_path):
    case_preserve(tmp_path)


REPLACE = ("core/legacy_import.py", 'new = dict(raw, imported=folded["imported"],',
           'new = dict({"schema": 1, "pending": [], "attempts": {}}, imported=folded["imported"],')


def _mutant(tmp, *edits):
    dst = Path(tmp) / "ft2m"
    for sub in ("core", "tools"):
        shutil.copytree(os.path.join(FT2, sub), str(dst / sub), ignore=shutil.ignore_patterns("__pycache__"))
    for rel, old, new in edits:
        text = (dst / rel).read_text(encoding="utf-8")
        assert text.count(old) == 1, (rel, old)
        (dst / rel).write_text(text.replace(old, new), encoding="utf-8")
    return str(dst)


def _caught(case, tmp, ft2, **kw):
    """변이가 사례를 FAIL 로 만드는가(True = 잡힘)."""
    try:
        case(Path(tmp) / "case", ft2=ft2, **kw)
    except AssertionError:
        return True
    return False


def test_c6_replace_runtime_fails_c5(tmp_path):
    assert _caught(case_preserve, tmp_path, _mutant(tmp_path, REPLACE))


def test_m3_preserve_check_removed_leaks_c6(tmp_path):
    assert not _caught(case_preserve, tmp_path, _mutant(tmp_path, REPLACE), checker=lambda *a: [])


def test_c7_overlap_skipped(tmp_path):
    case_overlap(tmp_path)


def test_c8_reclaim_import_segments(tmp_path):
    case_reclaim(tmp_path)


def test_c9_submit_after_import(tmp_path):
    case_submit_after(tmp_path)


def test_c10_crash_resume(tmp_path):
    case_crash(tmp_path)


def test_c11_held_differs_rc2(tmp_path):
    case_held_differs(tmp_path)


def test_dry_run_writes_nothing(tmp_path):
    w = _world(tmp_path)
    before = (w.rt / "journal.jsonl").read_bytes()
    rc, last, _ = _run(w, "--dry-run")
    assert rc == 0 and last.startswith("가져온 수 5 ") and last.endswith("dry-run"), last
    assert (w.rt / "journal.jsonl").read_bytes() == before and not w.held.exists()


def test_usage_rc64(tmp_path):
    assert _load(FT2, "tools", "legacy_import").main(["--root", str(tmp_path)], out=io.StringIO()) == 64


MUTANTS = {
    "M1": (case_missing, [("tools/legacy_import.py", "c = len(plan) - n - a - b - e", "c = 0")]),
    "M2": (case_idempotent, [("core/legacy_import.py", 'if key in (state.get("imported") or {}):', "if False:")]),
    "M4": (case_reclaim, [("core/journal.py", '"imported",   # r1774: 가져온 기록(F6)', "")]),
    "M5": (case_submit_after, [("core/legacy_import.py", 'kind="import",', 'kind="import", holder=row["key"],')]),
    "M6": (case_reclaim, [("core/journal.py", ' if rec["kind"] != "import"}', "}")]),
    "M7": (case_saturated, [("core/legacy_import.py", "row, dry, k=0)", "row, dry, k=1)")]),
    "M8": (case_overlap, [("core/legacy_import.py", "and name in receipts", "and False")]),
}


@pytest.mark.parametrize("name", sorted(MUTANTS))
def test_mutant_caught(tmp_path, name):
    case, edits = MUTANTS[name]
    assert _caught(case, tmp_path, _mutant(tmp_path, *edits)), name


def test_real_reconcile_lines_fit(tmp_path):
    """실제 BYZ 원자료(FT20_BYZ_REPO) 옮김 행 → import 줄 ≤ line_max. 원자료 없음 = skip(성공 아님)."""
    proc = subprocess.run(["git", "-C", BYZ, "show", REAL], capture_output=True, timeout=7)
    if proc.returncode != 0:
        pytest.skip("원자료 없음: %s" % BYZ)
    tool = _load(FT2, "tools", "legacy_import")
    rows = [row for row in json.loads(proc.stdout)["rows"] if row.get("decision") == "옮김"]
    sizes = [tool.line_size(TEAM, 9999999, NOW, row) for row in rows]
    assert len(rows) == 202 and None not in sizes and max(sizes) <= 512, (len(rows), max(s or 0 for s in sizes))
