"""r2037 card_stage --da 갈래 시험 (카드 반례 ①~⑧ · 변이 M1~M4).
r1889 꼴 그대로 — keeper_world_r1812 대역 · 임시 bare 원격(byz.git · main·ops/main-base) + 임시 루트 · 임시 판정문만 쓴다(실 리포·실 원장 0).
판정문 검사 = 팩의 ft-team-lib.sh 를 임시 루트 런타임 자리에 복사해 ft_close_marker 를 그대로 부른다(사본 0).
기준판 = 팩 origin/main → ①②⑧ Red(--da 인자 없음). sleep 0.
"""
import importlib.util
import shutil
from pathlib import Path

_SPEC = importlib.util.spec_from_file_location("keeper_world_r2037", str(Path(__file__).with_name("keeper_world_r1812.py")))
kw = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(kw)
TEAM, MAIN, OPS = kw.TEAM, "main", "ops/main-base"
CARD = "design/harness/indices/%s/r9-x.md"
SHA = "c0" * 20


def world(tmp, mp, stage="진행", ledger=None, verdict="r9-x"):
    w = kw.World(tmp, mp)
    for k, v in (("user.email", "t@t"), ("user.name", "t"), ("commit.gpgsign", "false")):
        kw._git(w.root, "config", k, v)
    w.card("r9", stage=stage, refs=(OPS,))
    if ledger is not None:
        w.work("r9", done=ledger, intent=False, turn=None)
    lib = w.root / ".fable-team" / "bin" / "ft-team-lib.sh"
    lib.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy(str(kw.OLD / "bin" / "ft-team-lib.sh"), str(lib))
    w.da = tmp / "verdict.md"
    w.da.write_text("# DA 판정\n\n## §1 다른 일\n- 보류\n\n## §2 %s — 닫힘 (CLOSE)\n- 닫힘 — %s — main `%s`\n" % (verdict, verdict, SHA),
                    encoding="utf-8")
    return w


def bare(w, *a):
    return kw._git(w.tmp, "--git-dir", str(w.tmp / "byz.git"), *a)


def heads(w):
    return {b: bare(w, "rev-parse", b) for b in (MAIN, OPS)}


def run(w, capsys, spec=None):
    mod = kw._mod(w.ft2 / "adapters" / "pi" / "card_stage.py", "cs2037_%d" % id(w))
    rc = mod.main(["--root", str(w.root), "--team", TEAM, "--work", "r9"] + (["--da", spec] if spec else []))
    return rc, capsys.readouterr().out.strip()


def spec(w, sec="§2"):
    return "%s#%s" % (w.da, sec)


def staged_by_da(w, frm, out, rc):
    assert rc == 0 and out.startswith("STAGED r9-x %s→완성 " % frm), out
    names = bare(w, "ls-tree", "-r", "--name-only", OPS).splitlines()
    assert CARD % "완성" in names and CARD % frm not in names
    body = bare(w, "show", OPS + ":" + CARD % "완성")
    assert "\n- 상태: 완성 · %s · DA %s\n" % (kw.NOW, spec(w)) in body, body
    assert body.rstrip().splitlines()[-1].startswith("- %s · 완성 · DA %s" % (kw.NOW, spec(w))), body


def test_1_doing_card_closed_by_verdict_stages(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch)
    before = heads(w)
    rc, out = run(w, capsys, spec(w))
    staged_by_da(w, "진행", out, rc)
    assert heads(w)[MAIN] == before[MAIN] and len(out.splitlines()) == 1


def test_2_waiting_card_closed_by_verdict_stages(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch, stage="대기")
    rc, out = run(w, capsys, spec(w))
    staged_by_da(w, "대기", out, rc)


def test_3_other_card_name_rejects_without_write(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch, verdict="r9-xy")
    before = heads(w)
    rc, out = run(w, capsys, spec(w))
    assert rc == 1 and out.startswith("REJECT ") and len(out.splitlines()) == 1, out
    assert heads(w) == before


def test_4_missing_section_rejects_without_write(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch)
    before = heads(w)
    rc, out = run(w, capsys, spec(w, "§3"))
    assert rc == 1 and out.startswith("REJECT ") and "§3" in out, out
    assert heads(w) == before


def test_5_no_da_no_done_unchanged(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch)
    before = heads(w)
    rc, out = run(w, capsys)
    assert (rc, out) == (1, "REJECT done 없음 r9")
    assert heads(w) == before


def test_6_done_with_da_keeps_current_branch_plus_compare(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch, ledger=True)
    rc, out = run(w, capsys, spec(w))
    lines = out.splitlines()
    assert rc == 0 and len(lines) == 2 and lines[0].startswith("STAGED r9-x 진행→완성 "), out
    assert lines[1] == "DA 대조 일치 %s" % spec(w), out
    body = bare(w, "show", OPS + ":" + CARD % "완성")
    assert "\n- 상태: 완성 · %s · ft2 complete " % kw.NOW in body and " · DA " not in body


def test_7_verdict_unreadable_is_unsure_without_write(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch)
    before = heads(w)
    rc, out = run(w, capsys, "%s#§2" % (tmp_path / "없는-판정문.md"))
    assert rc == 3 and out.startswith("판정 불가 "), out
    assert heads(w) == before


def test_8_ledger_work_not_done_is_completed_once(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch, ledger=False)
    assert w.kinds("complete") == 0
    rc, out = run(w, capsys, spec(w))
    staged_by_da(w, "진행", out.splitlines()[0], rc)
    proj = w.CLI._load("projection").project(str(w.root), TEAM)
    assert proj["works"]["r9"]["done"] is True and w.kinds("complete") == 1, out
