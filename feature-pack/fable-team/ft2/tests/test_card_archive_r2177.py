"""r2177 card_archive 시험 (카드 반례 ①~⑪-c · ⑫ = 기존 시험 재실행 · 변이 M1~M8 은 사본에서).
r2037 world 꼴 그대로 — 임시 bare 원격(byz.git · main·ops/main-base) + 임시 루트 클론 · FT_NOW 고정 · 실 리포·실 push·외부 호출 0 · sleep 0.
판정문 검사 = 팩 ft-team-lib.sh 사본 자리의 ft_close_marker 그대로 · git 호출 = card_stage.spawn 을 세는 감싸개(card_archive 가 불러 쓰는 한 곳).
기준판 = 팩 main 415256bf44 → card_archive.py 없음 = ①~⑪ Red · ⑪-b 는 keeper_endings 기준판 None = Red · ⑪-c ⓐ ⓒ ⓖ 는 기준판과 같은 결과·같은 git 인자 목록.
"""
import importlib.util
import re
from pathlib import Path

import pytest

_SPEC = importlib.util.spec_from_file_location("cs2037_world_r2177", str(Path(__file__).with_name("test_card_stage_da_close_legacy_r2037.py")))
base = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(base)
kw, TEAM, MAIN, OPS, CARD, SHA = base.kw, base.TEAM, base.MAIN, base.OPS, base.CARD, base.SHA
SEAT, MONTH, IDX = "byz-harness-master#1", "2026-11", "design/harness/indices"
ARCH = IDX + "/아카이브/2026-11/r9-x.md"
TO = IDX + "/대기/r8-y.md"
TEXT = "# 인덱스: r9\n- 상태: 대기\n- 정본 영향 없음: 시험\n\n## 상태\n- 2026-11-01 · 생성\n\n## 꼬리\n- x\n"
DROP, USELESS = "닫힘 — r9-x — 버림", "CLOSE — r9-x — 쓸모 없음"   # 1.x 아카이브 갈래와 같이 줄이 «닫힘|CLOSE» 로 시작
LAND = "- 닫힘 — r9-x — main `%s`" % SHA
V = "design/harness/evidence/r9-da/verdict.md"


def verdict(*lines):
    return "# DA 판정\n\n## §1 다른 일\n- 보류\n\n## §2 r9-x — 판정\n%s\n" % "\n".join(lines)


def world(tmp, mp, stage="대기", text=TEXT, ledger=None, lines=(DROP,), refs=(OPS,)):
    w = base.world(tmp, mp, stage=stage, ledger=ledger)
    for ref in refs:
        w.commit("byz", {CARD % stage: text}, ref)
    w.da.write_text(verdict(*lines), encoding="utf-8")
    return w


def run(w, capsys, mp, *extra, da=None, fail=None):
    """(rc, 출력, git 인자 목록) · fail(args) = 주입 결과(None = 진짜 git · "slow" = 시간 초과)."""
    mod, calls = kw._mod(w.ft2 / "adapters" / "pi" / "card_archive.py", "ca2177_%d" % id(w)), []
    real = mod.cs.spawn

    def counted(cwd, args, env=None):
        calls.append(list(args))
        hit = fail and fail(list(args))
        if hit == "slow":
            raise mod.cs.Slow("git %s 시간초과 7초" % args[0])
        return hit if hit else real(cwd, args, env)
    mp.setattr(mod.cs, "spawn", counted)
    argv = ["--root", str(w.root), "--team", TEAM, "--work", "r9", "--seat", SEAT, "--da", da or base.spec(w)] + list(extra)
    rc = mod.main(argv)
    return rc, capsys.readouterr().out.strip(), calls


def archived(w, out, rc, frm="대기", da=None):
    da = da or base.spec(w)
    line = out.splitlines()[0]
    assert rc == 0 and re.fullmatch(r"ARCHIVED r9-x %s→아카이브 [0-9a-f]{40}" % frm, line), out
    names = base.bare(w, "ls-tree", "-r", "--name-only", OPS).splitlines()
    assert ARCH in names and CARD % frm not in names, names
    sha = line.split()[-1]
    assert base.bare(w, "rev-parse", OPS) == sha
    rows = base.bare(w, "diff-tree", "-r", "--no-renames", "--name-status", sha + "^", sha).splitlines()
    assert sorted(rows) == sorted(["D\t" + CARD % frm, "A\t" + ARCH]), rows
    assert base.bare(w, "log", "-1", "--format=%s", OPS) == "[docs] r9-x 2.0 아카이브(DA %s)" % da
    body = base.bare(w, "show", OPS + ":" + ARCH)
    assert "\n- 상태: 아카이브 · %s · DA %s\n" % (kw.NOW, da) in body, body
    tail = "- %s · 아카이브 · DA %s · ft2 card_archive %s→아카이브 · 좌석 %s" % (kw.NOW, da, frm, SEAT)
    state = body.split("## 상태\n")[1].split("\n## ")[0].rstrip("\n").splitlines()
    assert tail in state and body.rstrip().endswith("## 꼬리\n- x"), body
    return state[state.index(tail):]


def test_1_waiting_drop_archived(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch)
    main = base.heads(w)[MAIN]
    rc, out, _ = run(w, capsys, monkeypatch)
    assert len(archived(w, out, rc)) == 1 and base.heads(w)[MAIN] == main


def test_2_doing_useless_archived(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch, stage="진행", lines=(USELESS,))
    rc, out, _ = run(w, capsys, monkeypatch)
    archived(w, out, rc, frm="진행")


def rejected(w, rc, out, before, word):
    assert rc == 1 and len(out.splitlines()) == 1 and out.startswith("REJECT ") and word in out, out
    assert base.heads(w) == before


@pytest.mark.parametrize("lines,word", [
    ((LAND, DROP), "착지한 카드"),                                                   # ③
    (("- 닫힘 — r9-x — main `%s`" % ("a" * 40), "- 닫힘 — r9-x — main `%s`" % ("b" * 40), DROP), "착지한 카드"),   # ③-b
    (("닫힘 — r9-x-y — 버림",), "r9-x"),                                              # ④ 이름 다름
    (("참고: 닫힘 — r9-x — 버림",), "r9-x"),                                          # ④ 문장 중간
    (("- 보류",), "r9-x"),                                                            # ④ 닫힘 줄 없음
])
def test_3_4_verdict_rejects(tmp_path, monkeypatch, capsys, lines, word):
    w = world(tmp_path, monkeypatch, lines=lines)
    before = base.heads(w)
    rc, out, _ = run(w, capsys, monkeypatch)
    rejected(w, rc, out, before, word)


def test_3b_drop_only_contrast(tmp_path, monkeypatch, capsys):   # ③-b 대조 = 버림 줄만(stdout 빔 · rc1) 통과
    w = world(tmp_path, monkeypatch, lines=("  닫힘 — r9-x — 버림 (정리)  ",))
    rc, out, _ = run(w, capsys, monkeypatch)
    archived(w, out, rc)


def test_5_canon_line_missing(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch, text=TEXT.replace("- 정본 영향 없음: 시험\n", ""))
    before = base.heads(w)
    rc, out, _ = run(w, capsys, monkeypatch)
    rejected(w, rc, out, before, "정본 영향 없음")


@pytest.mark.parametrize("ledger,to,word", [
    (True, None, "원장 done"), (False, None, "열린 일"), (False, IDX + "/대기/r7-z.md", "--to"),
    (False, CARD % "대기", "--to"), (False, "design/harness/notes/r8-y.md", "--to"),
])
def test_6_ledger_and_to_rejects(tmp_path, monkeypatch, capsys, ledger, to, word):
    w = world(tmp_path, monkeypatch, ledger=ledger)
    w.commit("byz", {TO: "# r8\n", "design/harness/notes/r8-y.md": "# n\n"}, OPS)
    before = base.heads(w)
    rc, out, _ = run(w, capsys, monkeypatch, *(["--to", to] if to else []))
    rejected(w, rc, out, before, word)


def test_6_open_work_with_to_archived(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch, ledger=False)
    w.commit("byz", {TO: "# r8\n"}, OPS)
    rc, out, _ = run(w, capsys, monkeypatch, "--to", TO)
    assert archived(w, out, rc)[1:] == ["대체됨: %s · 사유: %s" % (TO, base.spec(w))]


def test_7_rerun_noop_and_complete_only(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch)
    run(w, capsys, monkeypatch)
    before = base.heads(w)
    rc, out, _ = run(w, capsys, monkeypatch)
    assert (rc, out) == (0, "NOOP r9-x 이미 아카이브") and base.heads(w) == before
    w2 = world(tmp_path / "b", monkeypatch, stage="완성")
    before = base.heads(w2)
    rc, out, _ = run(w2, capsys, monkeypatch)
    rejected(w2, rc, out, before, "완성 카드")


@pytest.mark.parametrize("hit", [
    lambda a: (128, "") if a[0] == "fetch" else None,
    lambda a: "slow" if a[0] == "ls-tree" else None,
    lambda a: (1, "") if a[0] == "commit-tree" else None,
    lambda a: (1, "") if a[0] == "push" else None,                              # 거절 2회
])
def test_8_git_failures_unsure_no_write(tmp_path, monkeypatch, capsys, hit):
    w = world(tmp_path, monkeypatch)
    before = base.heads(w)
    rc, out, _ = run(w, capsys, monkeypatch, fail=hit)
    assert rc == 3 and out.startswith("판정 불가 ") and len(out.splitlines()) == 1, out
    assert base.heads(w) == before


def test_8_push_refused_once_then_archived(tmp_path, monkeypatch, capsys):
    w, seen = world(tmp_path, monkeypatch), []
    rc, out, calls = run(w, capsys, monkeypatch, fail=lambda a: (1, "") if a[0] == "push" and not seen and not seen.append(1) else None)
    archived(w, out, rc)
    assert sum(c[0] == "push" for c in calls) == 2 and sum(c[0] == "fetch" for c in calls) == 2


def test_9_two_cards_unsure(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch, stage="진행", refs=(OPS, MAIN))
    before = base.heads(w)
    rc, out, _ = run(w, capsys, monkeypatch)
    assert (rc, out) == (3, "판정 불가 두 가지에 진행 카드") and base.heads(w) == before
    w2 = world(tmp_path / "b", monkeypatch)
    w2.commit("byz", {CARD % "진행": TEXT}, OPS)
    rc, out, _ = run(w2, capsys, monkeypatch)
    assert (rc, out) == (3, "판정 불가 진행·대기 둘 다 카드")


def test_10_stale_worktree_verdict_reads_branch(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch)
    w.commit("byz", {V: verdict(DROP)}, OPS)
    pin = base.heads(w)[OPS]
    kw._put(w.root / V, verdict("- 보류"))
    monkeypatch.chdir(w.root)
    rc, out, _ = run(w, capsys, monkeypatch, da=V + "#§2")
    archived(w, out, rc, da=V + "#§2")
    assert out.splitlines()[1:] == ["판정문 출처 origin/%s %s" % (OPS, pin[:10])], out


def keeper(w):
    k = w.keeper()
    k.fresh(str(w.root))
    return k, k.close.__func__.__globals__["endings"]


def test_11_keeper_reads_archive(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch)
    rc, out, _ = run(w, capsys, monkeypatch)
    archived(w, out, rc)
    w.work("r5", intent=False, turn=None)   # 팀 원장 journal(다른 일) — 팀 폴더 후보 0 이면 resolve_card 가 발주 본문을 읽는다
    k, endings = keeper(w)
    nxt = kw._mod(w.ft2 / "adapters" / "pi" / "keeper_next.py", "kn2177_%d" % id(w))
    assert endings._card_end(k, TEAM, "r9") == ("superseded", "카드 아카이브/")
    assert nxt.moved_to(ARCH, IDX) == "아카이브"


def mapped(w, *paths):
    kw._put(w.root / ".fable-team/teams/harness/runtime/cards.tsv", "".join("r9\t%s\n" % p for p in paths))


def test_11b_mapped_card_archived_superseded(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch, ledger=False)
    w.commit("byz", {TO: "# r8\n"}, OPS)
    mapped(w, CARD % "대기")
    rc, out, _ = run(w, capsys, monkeypatch, "--to", TO)
    archived(w, out, rc)
    k, endings = keeper(w)
    nxt = kw._mod(w.ft2 / "adapters" / "pi" / "keeper_next.py", "kn2177b_%d" % id(w))
    assert endings._card_end(k, TEAM, "r9") == ("superseded", "카드 아카이브/")
    assert endings.ending(k, TEAM, "r9") == ("superseded", "카드 아카이브/")
    assert nxt.moved_to(ARCH, IDX) == "아카이브"


def traced(w, fail=None):
    """(_card_end 결과, git 인자 목록) · fail(args) = 주입 (rc, out, err)."""
    k, endings = keeper(w)
    calls, real = [], k.git

    def git(repo, *args, **kws):
        calls.append(list(args))
        return (fail and fail(list(args))) or real(repo, *args, **kws)
    k.git = git
    return endings._card_end(k, TEAM, "r9"), calls


def ls(ref, folder="design/harness"):
    return ["ls-tree", "-r", "--name-only", "origin/" + ref, "--", folder + "/indices"]


SHOW = ["show", "origin/%s:%s" % (OPS, CARD % "대기")]
TEAMS = [["show", "origin/%s:design/TEAMS.md" % r] for r in (OPS, MAIN)]
BASE_A = [ls(OPS), ls(MAIN)] * 2 + [SHOW]                                               # 기준판 415256bf44 에서 잼
BASE_G = (TEAMS[:1] + [ls(OPS), ls(OPS, "design/teams/harness")] + TEAMS[1:] + [ls(MAIN), ls(MAIN, "design/teams/harness")]
          + TEAMS[:1] + [ls(OPS), ls(OPS, "design/teams/harness")])


def test_11c_mapped_paths(tmp_path, monkeypatch):
    w = world(tmp_path, monkeypatch)                                                     # ⓐ 짝 표 카드가 대기에 그대로
    mapped(w, CARD % "대기")
    got, calls = traced(w)
    assert got is None and calls == BASE_A, (got, calls)
    mapped(w, CARD % "대기", CARD % "진행")                                              # ⓒ 같은 일 2줄 = 기준판 None · git 0
    assert traced(w) == (None, [])
    mapped(w, IDX + "/대기/r9-q.md")                                                      # ⓓ 어느 단계에도 없음
    assert traced(w)[0] is None
    w.commit("byz", {IDX + "/아카이브/2026-10/r9-q.md": "# q\n", IDX + "/아카이브/2026-11/r9-q.md": "# q\n"}, OPS)
    assert traced(w)[0] is False                                                         # ⓑ 두 월 폴더에 같은 이름
    other = "design/teams/planner/indices/대기/r9-p.md"
    mapped(w, other)
    w.commit("byz", {"design/teams/planner/indices/아카이브/2026-11/r9-p.md": "# p\n"}, MAIN)
    assert traced(w)[0] == ("superseded", "카드 아카이브/")                              # ⓔ 다른 팀 폴더 · 둘째 가지
    hits = []
    got, _ = traced(w, lambda a: (128, "", "x") if a[0] == "ls-tree" and any("아카이브" in x for x in a) and not hits.append(a) else None)
    assert got is False and hits                                                         # ⓕ 아카이브 찾는 ls-tree 실패


def test_11c_g_unmapped_team_card_same_calls(tmp_path, monkeypatch):                   # ⓖ 짝 표 없음 · 팀 폴더 아카이브 카드
    w = kw.World(tmp_path, monkeypatch)
    w.commit("byz", {ARCH: TEXT}, OPS)
    w.work("r9", intent=False, turn=None)
    got, calls = traced(w)
    assert got == ("superseded", "카드 아카이브/") and calls == BASE_G, (got, calls)
