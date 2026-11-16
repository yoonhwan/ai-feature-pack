"""r2152 card_stage 짝 표 남의 카드 착지 관문 시험 (카드 반례 ①~⑦ · 변이 M1~M3).
r2147 꼴 그대로 — keeper_world_r1812 대역 · 임시 bare 원격(byz.git · main·ops/main-base) + 임시 루트 · 임시 원장(done 1행) · 짝 표 cards.tsv 대역 · 합성 카드 본문(실 리포·실 keeper·push 0).
관문 = 고른 카드 이름이 <work>.md · <work>-*.md(own)면 `^- 착지: <40자>` · 아니면(짝 표 남의 카드) `^- 착지(<work>): <40자>` 줄만.
기준판 = 팩 origin/main → ① 만 Red(앞선 «- 착지:» 줄로 STAGED) · ② ③ ⑦ Green. sleep 0.
"""
import importlib.util
from pathlib import Path

_SPEC = importlib.util.spec_from_file_location("keeper_world_r2152", str(Path(__file__).with_name("keeper_world_r1812.py")))
kw = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(kw)
TEAM, MAIN, OPS = kw.TEAM, "main", "ops/main-base"
IDX = "design/harness/indices/%s/%s.md"
LAND = "1a" * 20
MINE = "2b" * 20
HEAD = "# 인덱스: %s\n- 상태: 진행 — 남은 일 C4 press\n"


def world(tmp, mp, work, name, stage="진행", extra="", mapped=None):
    """work 원장 done 1행 · ops/main-base 에 카드 1장 · mapped = 짝 표 대상 카드 경로(None = 짝 표 없음)."""
    w = kw.World(tmp, mp)
    for k, v in (("user.email", "t@t"), ("user.name", "t"), ("commit.gpgsign", "false")):
        kw._git(w.root, "config", k, v)
    w.path = IDX % (stage, name)
    w.commit("byz", {w.path: HEAD % name + extra}, OPS)
    w.work(work, done=True, intent=False, turn=None)
    if mapped:
        kw._put(w.runtime() / "cards.tsv", "%s\t%s\n" % (work, mapped))
    w.name, w.stage, w.run_work = name, stage, work
    return w


def bare(w, *a):
    return kw._git(w.tmp, "--git-dir", str(w.tmp / "byz.git"), *a)


def heads(w):
    return {b: bare(w, "rev-parse", b) for b in (MAIN, OPS)}


def run(w, capsys):
    mod = kw._mod(w.ft2 / "adapters" / "pi" / "card_stage.py", "cs2152_%d" % id(w))
    rc = mod.main(["--root", str(w.root), "--team", TEAM, "--work", w.run_work])
    return rc, capsys.readouterr().out.strip()


def held(w, capsys):
    """착지 줄 없음 → rc 3 1줄 · 두 원격 ref 그대로 · 카드 바이트 그대로(커밋 0 · push 0)."""
    before, body = heads(w), bare(w, "show", OPS + ":" + w.path)
    rc, out = run(w, capsys)
    assert (rc, out) == (3, "판정 불가 착지 줄 없음 %s" % w.name), out
    assert heads(w) == before and bare(w, "show", OPS + ":" + w.path) == body


def staged(w, capsys):
    before = heads(w)
    rc, out = run(w, capsys)
    assert rc == 0 and out.startswith("STAGED %s %s→완성 " % (w.name, w.stage)), out
    names = bare(w, "ls-tree", "-r", "--name-only", OPS).splitlines()
    assert IDX % ("완성", w.name) in names and w.path not in names
    assert heads(w)[MAIN] == before[MAIN] and bare(w, "rev-parse", OPS + "^") == before[OPS]


def test_1_mapped_parent_with_earlier_landing_only_holds(tmp_path, monkeypatch, capsys):
    held(world(tmp_path, monkeypatch, "press17", "lang-resync", extra="- 착지: %s (PR #8790)\n" % LAND,
               mapped=IDX % ("진행", "lang-resync")), capsys)


def test_2_mapped_parent_with_named_landing_stages(tmp_path, monkeypatch, capsys):
    extra = "- 착지: %s (PR #8790)\n- 착지(press17): %s\n" % (LAND, MINE)
    staged(world(tmp_path, monkeypatch, "press17", "lang-resync", extra=extra, mapped=IDX % ("진행", "lang-resync")), capsys)


def test_3_mapped_parent_with_other_work_landing_holds(tmp_path, monkeypatch, capsys):
    held(world(tmp_path, monkeypatch, "press17", "lang-resync", extra="- 착지(press16): %s\n" % MINE,
               mapped=IDX % ("진행", "lang-resync")), capsys)


def test_4_own_doing_card_plain_landing_stages(tmp_path, monkeypatch, capsys):
    staged(world(tmp_path, monkeypatch, "r9", "r9", extra="- 착지: %s\n" % LAND), capsys)


def test_5_own_tail_waiting_card_plain_landing_stages(tmp_path, monkeypatch, capsys):
    staged(world(tmp_path, monkeypatch, "r9", "r9-tail", stage="대기", extra="- 착지: %s\n" % LAND), capsys)


def test_6_mapped_to_own_name_card_plain_landing_stages(tmp_path, monkeypatch, capsys):
    staged(world(tmp_path, monkeypatch, "r9", "r9", extra="- 착지: %s\n" % LAND, mapped=IDX % ("진행", "r9")), capsys)


def test_7_mapped_parent_work_name_is_escaped(tmp_path, monkeypatch, capsys):
    held(world(tmp_path, monkeypatch, "r.x", "parent", extra="- 착지(rax): %s\n" % MINE,
               mapped=IDX % ("진행", "parent")), capsys)
