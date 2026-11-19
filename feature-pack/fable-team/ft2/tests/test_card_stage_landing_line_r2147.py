"""r2147 card_stage 착지 관문 시험 (카드 반례 ①~⑤d · 변이 M1~M4).
r2037 꼴 그대로 — keeper_world_r1812 대역 · 임시 bare 원격(byz.git · main·ops/main-base) + 임시 루트 · 임시 원장(done 1행) · 합성 카드 본문 · 임시 판정문만 쓴다(실 리포·실 원장·실 keeper 0).
관문 = 고른 카드(부모 SHA 본문)에 `^- 착지: <40자>` 줄 · 또는 gate 있음 ∧ why None. 둘 다 없으면 rc 3 «착지 줄 없음 <stem>» · 원격 쓰기 0.
r2274 C3 — 둘 다 없으면 rc 0 «NOOP r9 완성 증거 0 착지 줄 0[ · 보완]»(16진수 없는 착지 줄 = «착지 줄 0» · 착지 줄 없음 = «· 보완») · 7~40자 16진수 = 그 sha 로 판정.
기준판 = 팩 origin/main → ① ③ ⑤c Red(착지 줄 없이 STAGED). sleep 0.
"""
import importlib.util
import shutil
from pathlib import Path

import pytest

_SPEC = importlib.util.spec_from_file_location("keeper_world_r2147", str(Path(__file__).with_name("keeper_world_r1812.py")))
kw = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(kw)
TEAM, MAIN, OPS = kw.TEAM, "main", "ops/main-base"
CARD = "design/harness/indices/%s/r9-x.md"
SHA = "c0" * 20
LAND = "1a" * 20
HEAD = "# 인덱스: r9\n- 상태: 대기\n- 남은 범위: 없음\n"


def world(tmp, mp, stage="진행", extra="", ledger=True):
    w = kw.World(tmp, mp)
    for k, v in (("user.email", "t@t"), ("user.name", "t"), ("commit.gpgsign", "false")):
        kw._git(w.root, "config", k, v)
    extra = extra.replace(LAND, w.land_sha()) if LAND in extra else extra   # r2274 DA#29 H3ⓑ — 가짜 sha = 판정 불가 → 실제 팩 커밋
    w.commit("byz", {CARD % stage: HEAD + extra}, OPS)
    if ledger is not None:
        w.work("r9", done=ledger, intent=False, turn=None)
    lib = w.root / ".fable-team" / "bin" / "ft-team-lib.sh"
    lib.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy(str(kw.OLD / "bin" / "ft-team-lib.sh"), str(lib))
    w.da = tmp / "verdict.md"
    w.da.write_text("# DA 판정\n\n## §1 r9-x — 보류\n- 보류\n\n## §2 r9-x — 닫힘 (CLOSE)\n- 닫힘 — r9-x — main `%s`\n" % SHA,
                    encoding="utf-8")
    return w


def bare(w, *a):
    return kw._git(w.tmp, "--git-dir", str(w.tmp / "byz.git"), *a)


def heads(w):
    return {b: bare(w, "rev-parse", b) for b in (MAIN, OPS)}


def run(w, capsys, sec=None):
    mod = kw._mod(w.ft2 / "adapters" / "pi" / "card_stage.py", "cs2147_%d" % id(w))
    rc = mod.main(["--root", str(w.root), "--team", TEAM, "--work", "r9"] + (["--da", "%s#%s" % (w.da, sec)] if sec else []))
    return rc, capsys.readouterr().out.strip()


def held(w, capsys, stage, sec=None, why="착지 줄 0 · 보완"):
    """착지 증거 없음 → r2274 rc 0 NOOP 1줄 · 두 원격 ref 그대로 · 카드 바이트 그대로."""
    before, body = heads(w), bare(w, "show", OPS + ":" + CARD % stage)
    rc, out = run(w, capsys, sec)
    assert (rc, out) == (0, "NOOP r9 완성 증거 0 " + why), out
    assert heads(w) == before and bare(w, "show", OPS + ":" + CARD % stage) == body


def staged(w, frm, out, rc, lines=1):
    rows = out.splitlines()
    assert rc == 0 and len(rows) == lines and rows[0].startswith("STAGED r9-x %s→완성 " % frm), out
    names = bare(w, "ls-tree", "-r", "--name-only", OPS).splitlines()
    assert CARD % "완성" in names and CARD % frm not in names
    return rows


def test_1_done_waiting_card_without_landing_line_holds(tmp_path, monkeypatch, capsys):
    held(world(tmp_path, monkeypatch, stage="대기"), capsys, "대기")


def test_2_done_doing_card_with_landing_line_stages(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch, extra="- 착지: %s\n" % LAND)
    before = heads(w)
    rc, out = run(w, capsys)
    staged(w, "진행", out, rc)
    assert heads(w)[MAIN] == before[MAIN]
    assert bare(w, "rev-parse", OPS + "^") == before[OPS]   # 지금과 같은 커밋 1


@pytest.mark.parametrize("line", ["- 착지: 대기\n", "- 착지: %s\n" % ("1a" * 20 + "b")])
def test_3_landing_line_not_40_hex_holds(tmp_path, monkeypatch, capsys, line):
    held(world(tmp_path, monkeypatch, extra=line), capsys, "진행", why="착지 줄 0")


def test_3b_short_hex_landing_line_judged_by_that_sha(tmp_path, monkeypatch, capsys):   # r2274 ④ⓕ — 7자 16진수 = 그 sha · 어느 리포에도 없음 = 판정 불가(DA#29 H3ⓑ)
    w = world(tmp_path, monkeypatch, extra="- 착지: 139335c\n")
    before = heads(w)
    rc, out = run(w, capsys)
    assert (rc, out) == (3, "판정 불가 착지 sha 로컬 0(BYZ·팩) 139335c"), out
    assert heads(w) == before


def test_4_landing_line_inside_status_section_stages(tmp_path, monkeypatch, capsys):
    extra = "\n## 상태\n- 2026-11-16 · 진행\n- 착지: %s (main 머지 · ops/main-base)\n" % LAND
    w = world(tmp_path, monkeypatch, extra=extra)
    rc, out = run(w, capsys)
    staged(w, "진행", out, rc)


def test_5a_no_done_valid_da_stages_and_completes_once(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch, ledger=False)
    rc, out = run(w, capsys, "§2")
    staged(w, "진행", out, rc, lines=2)
    assert w.kinds("complete") == 1


def test_5b_done_valid_da_without_landing_line_stages_with_match(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch)
    rc, out = run(w, capsys, "§2")
    rows = staged(w, "진행", out, rc, lines=2)
    assert rows[1] == "DA 대조 일치 %s#§2" % w.da, out


def test_5c_done_invalid_da_without_landing_line_holds(tmp_path, monkeypatch, capsys):
    held(world(tmp_path, monkeypatch), capsys, "진행", "§1")


def test_5d_done_invalid_da_with_landing_line_stages_with_mismatch(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch, extra="- 착지: %s\n" % LAND)
    rc, out = run(w, capsys, "§1")
    rows = staged(w, "진행", out, rc, lines=2)
    assert rows[1].startswith("DA 대조 불일치 "), out
