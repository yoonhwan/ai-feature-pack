"""r1831 이관 import 줄 512 — 반례 ①~⑤ · 변이 M1~M5(사본). I1 src 폴더만 · I2 넘친 행만 · I3 실제 사유 · I4 --precheck.
격리 tmp · 실제 core LegacyImport·journal · sleep 0."""
import importlib.util
import io
import json
import os
import re
import shutil
from pathlib import Path
from types import SimpleNamespace

import pytest

FT2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEAM, NOW = "lecture", "2026-11-13T00:00:00"
LONG, HUGE = "L67-" + "x" * 48, "L68-" + "y" * 196        # 기준판 517 꼴 · I1 뒤에도 512 초과
_N = [0]


def _load(ft2, sub, name):
    _N[0] += 1
    spec = importlib.util.spec_from_file_location("r1831_%s_%d" % (name, _N[0]), os.path.join(ft2, sub, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _card(name):
    return {"cat": "카드", "id": name, "loc": "design/teams/%s/indices/대기/%s.md" % (TEAM, name),
            "decision": "옮김", "target_id": "2.0 record: card/" + name}


def _world(tmp, names, ft2=FT2, runtime=True, mail=False):
    root, cards = Path(tmp) / "root", Path(tmp) / "cards"
    os.makedirs(str(root / ".fable-team" / "comm"))
    if runtime:
        assert _load(ft2, "core", "intake").Intake(str(root), TEAM, clock=lambda: NOW).submit(
            "r1767", "hello", "r1767").result == "접수 성공"
    rows = [_card(name) for name in names]
    for row in rows:
        os.makedirs(str((cards / row["loc"]).parent), exist_ok=True)
        (cards / row["loc"]).write_text("# %s\n" % row["id"], encoding="utf-8")
    if mail:
        (root / ".fable-team" / "comm" / "mailbox.jsonl").write_text('{"seq": 41, "body": "x"}\n', encoding="utf-8")
        rows.append({"cat": "미처리 쪽지", "id": "41", "loc": ".fable-team/comm/mailbox.jsonl#seq=41",
                     "decision": "옮김", "target_id": "2.0 intake: mbox/41"})
    rec = Path(tmp) / "reconcile.json"
    rec.write_text(json.dumps({"meta": {"team": TEAM, "cards_root": str(cards)}, "rows": rows}), encoding="utf-8")
    return SimpleNamespace(root=str(root), rec=str(rec), ft2=ft2, rt=root / ".fable-team" / "teams" / TEAM / "runtime")


def _run(w, *extra, caps=None):
    buf = io.StringIO()
    rc = _load(w.ft2, "tools", "legacy_import").main(["--root", w.root, "--team", TEAM, "--reconcile", w.rec]
                                                     + list(extra), caps=caps, out=buf)
    return rc, buf.getvalue().strip().splitlines()


_imported = lambda w: json.loads((w.rt / "state.json").read_text(encoding="utf-8")).get("imported") or {}  # noqa: E731


def case_long_name(tmp, ft2=FT2):                                   # ① · ⑤
    w = _world(tmp, [LONG], ft2)
    core, loc = _load(ft2, "core", "legacy_import"), _card(LONG)["loc"]
    full = core.build_line(TEAM, 9, NOW, dict(key="card/" + LONG, body="card/%s.md" % LONG, src=loc,
                                              sha256="0" * 64, bytes=99))
    assert core.journal.line_bytes(full) > 512                       # 기준판 꼴 = 넘침
    assert _run(w)[0] == 0
    src = _imported(w)["card/" + LONG]["src"]
    assert src == os.path.dirname(loc) and src + "/" + LONG + ".md" == loc, src
    rc, lines = _run(w)                                              # ⑤ 멱등
    assert rc == 0 and "가져온 수 0 · 건너뜀 1(이미 가져옴 1 · 겹침 0)" in lines[-1], lines


def case_intake_src(tmp, ft2=FT2):                                  # ①′
    w = _world(tmp, [], ft2, mail=True)
    assert _run(w)[0] == 0
    assert _imported(w)["intake/mbox/41"]["src"] == ".fable-team/comm/mailbox.jsonl#seq=41"


def case_only_row(tmp, ft2=FT2):                                    # ②
    w = _world(tmp, ["L01-a", HUGE, "L02-b"], ft2)
    rc, lines = _run(w)
    assert rc == 1 and set(_imported(w)) == {"card/L01-a", "card/L02-b"}, lines
    assert any(re.fullmatch(r"누락 card/%s: 줄 \d+ 바이트 > 512" % HUGE, line) for line in lines), lines
    assert "용량 거절 0" in lines[-1] and not any("뒤" in line for line in lines), lines


def case_full_reason(tmp, ft2=FT2):                                 # ③
    w = _world(tmp, ["L01-a", "L02-b", "L03-c"], ft2)
    caps = dict(total_cap=_load(ft2, "core", "journal").Journal(str(w.rt)).usage() + 2000)
    rc, lines = _run(w, caps=caps)
    assert rc == 1 and "용량 거절 1" in lines[-1] and not _imported(w), lines
    assert "누락 card/L03-c: 용량 부족 뒤" in lines and not any("용량 거절 뒤" in line for line in lines), lines


def case_precheck(tmp, ft2=FT2):                                    # ④ runtime 없음
    w = _world(tmp, ["L01-a", LONG, HUGE], ft2, runtime=False)
    rc, lines = _run(w, "--precheck")
    hit = re.fullmatch(r"가져올 수 2 · 누락 1\(.+\) · 최대 줄 (\d+) 바이트 / 512", lines[-1] if lines else "")
    assert rc == 1 and len(lines) == 1 and hit and int(hit.group(1)) > 512, (rc, lines)
    assert not (Path(w.root) / ".fable-team" / "teams").exists() and not (Path(w.root) / ".fable-team" / "state").exists()
    w2 = _world(Path(tmp) / "fit", ["L01-a", LONG], ft2, runtime=False)
    rc, lines = _run(w2, "--precheck")
    hit = re.fullmatch(r"가져올 수 2 · 누락 0 · 최대 줄 (\d+) 바이트 / 512", lines[-1])
    assert rc == 0 and hit and int(hit.group(1)) <= 512, lines  # 폴더만이면 긴 이름도 들어감


def case_precheck_runtime(tmp, ft2=FT2):                            # ④′ runtime 있음
    w = _world(tmp, ["L01-a", LONG, HUGE], ft2)
    rc_d, dry = _run(w, "--dry-run")
    rc_p, pre = _run(w, "--precheck")
    nums = [int(re.search(word + r" (\d+)", line).group(1)) for line, word in
            ((pre[-1], "가져올 수"), (pre[-1], "누락"), (dry[-1], "가져온 수"), (dry[-1], "누락"))]
    assert rc_p == rc_d == 1 and nums[:2] == nums[2:] == [2, 1] and not _imported(w), (dry, pre)


CASES = {"c1": case_long_name, "c1b": case_intake_src, "c2": case_only_row, "c3": case_full_reason,
         "c4": case_precheck, "c4b": case_precheck_runtime}


@pytest.mark.parametrize("name", sorted(CASES))
def test_case(tmp_path, name):
    CASES[name](tmp_path)


def _mutant(tmp, old, new):
    dst = Path(tmp) / "ft2m"
    for sub in ("core", "tools"):
        shutil.copytree(os.path.join(FT2, sub), str(dst / sub), ignore=shutil.ignore_patterns("__pycache__"))
    path = dst / "tools" / "legacy_import.py"
    assert path.read_text(encoding="utf-8").count(old) == 1, old
    return path.write_text(path.read_text(encoding="utf-8").replace(old, new), encoding="utf-8") and str(dst)


MUTANTS = {
    "M1": (case_long_name, "return head if head and tail == name else loc", "return loc"),
    "M2": (case_intake_src, "return head if head and tail == name else loc", "return head if head else loc"),
    "M3": (case_only_row, "stop = None if size_refused else status", "stop = status"),
    "M4": (case_full_reason, 'e, stop = 1, "용량 부족"', "e = 1"),
    "M5": (case_precheck, "size > limit", "False"),
}


@pytest.mark.parametrize("name", sorted(MUTANTS))
def test_mutant_caught(tmp_path, name):
    case, old, new = MUTANTS[name]
    ft2 = _mutant(tmp_path, old, new)
    with pytest.raises(AssertionError):
        case(Path(tmp_path) / "case", ft2=ft2)
