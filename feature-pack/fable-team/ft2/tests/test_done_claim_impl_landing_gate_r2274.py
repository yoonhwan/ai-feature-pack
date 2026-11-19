"""r2274 «구현 착지» 판정 한 곳(land_kind) · 예외 한 곳(no_code) — keeper 착지 · card_stage 완성 이동 (카드 반례 ①②③④⑥ · 변이 M1~M3).
대역 = keeper_world_r1812(임시 bare byz·pack · 임시 root · 임시 원장) · 합성 카드 · 판정 불가 대역 = root 의 lib 자리에 둔 가짜 lib · 실 리포·실 원장 0.
경계 = 바뀐 경로가 모두 «design/ 로 시작 ∧ /indices/ 포함» = 카드 문서만(팩 kit 템플릿 indices = 구현).
기준판 = 팩 origin/main → ② ③ ④ⓓⓔⓕ Red · ① 은 lib 없음 Red. sleep 0(시간 초과 대역 = 가짜 git · 상한 env 0.3초).
"""
import importlib.util
import os
import shutil
import subprocess
from pathlib import Path

import pytest

_SPEC = importlib.util.spec_from_file_location("keeper_world_r2274", str(Path(__file__).with_name("keeper_world_r1812.py")))
kw = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(kw)
TEAM, MAIN, OPS = kw.TEAM, "main", "ops/main-base"
LIB = kw.OLD / "bin" / "ft-land-kind-lib.sh"
STUB = '#!/usr/bin/env bash\nft_land_kind() { echo "판정 불가 git diff-tree 시간초과 7초 대역"; return 3; }\nft_no_code() { return 1; }\n'
CARD = "design/harness/indices/%s/%s-x.md"
HEAD = "# 인덱스: %s\n- 상태: 대기\n- 남은 범위: 없음\n"
TPL = {"kit/fable-team/templates/team/indices/대기/t.md": "# t\n"}   # ⑥ⓒ 팩 배포 템플릿


def lib_fn(fn, *args, env=None, lib=LIB):
    p = subprocess.run(["bash", "-c", '. "$1" || exit 9; f="$2"; shift 2; "$f" "$@"', "x", str(lib), fn] + [str(a) for a in args],
                       capture_output=True, text=True, timeout=25, env=env)
    return p.returncode, p.stdout.strip()


def landed_card(w, work, files, stage="진행", head="", refs=(OPS, MAIN), tail="- 착지: {sha}\n"):
    """카드 신설 합침(files + 카드 .md) = sha → 같은 카드 끝에 tail({sha} = 그 sha)."""
    path = CARD % (stage, work)
    sha = w.commit("byz", dict(files, **{path: HEAD % work + head}), OPS)
    for ref in refs:
        w.commit("byz", {path: HEAD % work + head + tail.format(sha=sha, sha10=sha[:10])}, ref)
    return sha


def stub_lib(w):
    lib = w.root / ".fable-team" / "bin" / "ft-land-kind-lib.sh"
    lib.parent.mkdir(parents=True, exist_ok=True)
    lib.write_text(STUB, encoding="utf-8")


def repo(tmp, files):
    r = tmp / "r"
    subprocess.run(["git", "init", "-q", "-b", "main", str(r)], check=True)
    for rel, body in files.items():
        kw._put(r / rel, body)
    kw._git(r, "add", "-A"), kw._git(r, "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false", "commit", "-q", "--allow-empty", "-m", "x")
    return r, kw._git(r, "rev-parse", "HEAD")


# ── ① 판정 불가(land_kind 한 곳) ──
def test_1a_missing_sha_undecidable(tmp_path):
    subprocess.run(["git", "init", "-q", str(tmp_path)], check=True)
    rc, out = lib_fn("ft_land_kind", tmp_path, "0" * 40)
    assert rc == 3 and out.startswith("판정 불가 ") and len(out.splitlines()) == 1, out


def test_1b_git_slow_undecidable(tmp_path):
    fake = tmp_path / "fake"
    fake.mkdir()
    (fake / "git").write_text("#!/bin/sh\nexec sleep 5\n", encoding="utf-8")
    (fake / "git").chmod(0o755)
    env = dict(os.environ, PATH=str(fake) + os.pathsep + os.environ["PATH"], FT_LAND_KIND_SEC="0.3")
    rc, out = lib_fn("ft_land_kind", tmp_path, "ab" * 20, env=env)
    assert (rc, out) == (3, "판정 불가 git diff-tree 시간초과 7초 abababab"), out


def test_1c_keeper_undecidable_complete_0(tmp_path, monkeypatch):
    w = kw.World(tmp_path, monkeypatch)
    landed_card(w, "r9401", {"src/app.py": "x\n"})
    stub_lib(w)
    w.work("r9401", intent=False)
    lines = w.round()
    assert w.kinds("complete") == 0, lines
    assert any("r9401" in x and "판정 불가" in x and "시간초과" in x for x in lines), lines


def test_1d_card_stage_undecidable_write_0(tmp_path, monkeypatch, capsys):
    w = stage_world(tmp_path, monkeypatch, {"src/app.py": "x\n"})
    stub_lib(w)
    before = heads(w)
    rc, out = run_stage(w, capsys)
    assert rc == 3 and out.startswith("판정 불가 ") and "시간초과" in out, out
    assert heads(w) == before


def test_1e_card_stage_sha_in_no_repo_undecidable(tmp_path, monkeypatch, capsys):   # DA#29 H3ⓑ — BYZ·팩 로컬 둘 다 없음 = 판정 불가 · 쓰기 0
    w = stage_world(tmp_path, monkeypatch, {}, tail="- 착지: %s\n" % ("1a" * 20))
    before = heads(w)
    rc, out = run_stage(w, capsys)
    assert (rc, out) == (3, "판정 불가 착지 sha 로컬 0(BYZ·팩) 1a1a1a1a"), out
    assert heads(w) == before


def test_2b_keeper_empty_commit_landing_complete_0(tmp_path, monkeypatch):   # DA#29 H3ⓐ — 빈 커밋 = 구현 증거 0 = 카드 문서만
    w = kw.World(tmp_path, monkeypatch)
    sha = w.commit("pack", {}, "main")
    w.card("r9403", sha)
    w.work("r9403", intent=False)
    lines = w.round()
    assert w.kinds("complete") == 0, lines
    assert any("r9403" in x and "카드 문서만 착지 " + sha[:8] in x for x in lines), lines


# ── ② keeper: 카드 문서만 착지 = complete 0 ──
def test_2_keeper_card_doc_only_landing_complete_0(tmp_path, monkeypatch):
    w = kw.World(tmp_path, monkeypatch)
    sha = landed_card(w, "r9402", {})
    w.work("r9402", intent=False)
    lines = w.round()
    assert w.kinds("complete") == 0, lines
    assert any("r9402" in x and "카드 문서만 착지 " + sha[:8] in x for x in lines), lines


# ── ③ ④ ⑥ card_stage ──
def stage_world(tmp, mp, files, stage="대기", head="", tail="- 착지: {sha}\n"):
    w = kw.World(tmp, mp)
    w.sha = landed_card(w, "r9", files, stage=stage, head=head, refs=(OPS,), tail=tail)
    w.work("r9", done=True, intent=False, turn=None)
    return w


def bare(w, *a):
    return kw._git(w.tmp, "--git-dir", str(w.tmp / "byz.git"), *a)


def heads(w):
    return {b: bare(w, "rev-parse", b) for b in (MAIN, OPS)}


def run_stage(w, capsys):
    mod = kw._mod(w.ft2 / "adapters" / "pi" / "card_stage.py", "cs2274_%d" % id(w))
    rc = mod.main(["--root", str(w.root), "--team", TEAM, "--work", "r9"])
    return rc, capsys.readouterr().out.strip()


def noop(w, capsys, why):
    before = heads(w)
    rc, out = run_stage(w, capsys)
    assert (rc, out) == (0, "NOOP r9 완성 증거 0 " + why), out
    assert heads(w) == before


def staged(w, rc, out, frm="대기"):
    assert rc == 0 and out.startswith("STAGED r9-x %s→완성 " % frm), out
    names = bare(w, "ls-tree", "-r", "--name-only", OPS).splitlines()
    assert CARD % ("완성", "r9") in names and CARD % (frm, "r9") not in names


def test_3_card_stage_card_doc_only_noop(tmp_path, monkeypatch, capsys):
    w = stage_world(tmp_path, monkeypatch, {})
    noop(w, capsys, "카드 문서만 착지 " + w.sha[:8])


EXC = {"4a_doc_head": ("- 구현: 없음 — 문서 카드\n", "- 착지: {sha}\n"),
       "4b_r1768_close_code0": ("", "- 2026-11-15 — 닫힘(대조 · 코드 0 · DA #1)\n"),
       "4c_live_db": ("", "- 착지: 라이브 DB 반영(2026-11-15 · loom prod · 행 12)\n")}


@pytest.mark.parametrize("case", list(EXC))
def test_4abc_card_stage_exceptions_stage(tmp_path, monkeypatch, capsys, case):
    head, tail = EXC[case]
    w = stage_world(tmp_path, monkeypatch, {}, head=head, tail=tail)
    staged(w, *run_stage(w, capsys))


def test_4d_r1380_no_landing_line_noop_fill(tmp_path, monkeypatch, capsys):
    noop(stage_world(tmp_path, monkeypatch, {"src/app.py": "x\n"}, tail=""), capsys, "착지 줄 0 · 보완")


def test_4e_plan_landing_line_noop(tmp_path, monkeypatch, capsys):
    noop(stage_world(tmp_path, monkeypatch, {}, tail="- 착지: ★사람 승인★ — 오빠 승인 뒤 main 머지\n"), capsys, "착지 줄 0")


def test_4f_short_sha_in_line_judged(tmp_path, monkeypatch, capsys):
    w = stage_world(tmp_path, monkeypatch, {}, tail="- 착지: main {sha10} (PR 3657 · 머지)\n")
    noop(w, capsys, "카드 문서만 착지 " + w.sha[:8])


@pytest.mark.parametrize("files", [{"src/app.py": "x\n"}, {"design/rag/sql/m6.sql": "select 1;\n"}], ids=["6a_code", "6b_sql"])
def test_6_card_stage_impl_landing_stages(tmp_path, monkeypatch, capsys, files):
    w = stage_world(tmp_path, monkeypatch, files)
    staged(w, *run_stage(w, capsys))


def test_6c_card_stage_pack_template_landing_stages(tmp_path, monkeypatch, capsys):
    w = kw.World(tmp_path, monkeypatch)
    sha = w.commit("pack", TPL, "main")
    kw._git(w.tmp / "pack", "fetch", "-q", "origin")
    w.commit("byz", {CARD % ("대기", "r9"): HEAD % "r9" + "- 착지: %s\n" % sha}, OPS)
    w.work("r9", done=True, intent=False, turn=None)
    staged(w, *run_stage(w, capsys))


@pytest.mark.parametrize("files", [{"src/app.py": "x\n"}, {"design/rag/sql/m6.sql": "select 1;\n"}], ids=["6a_code", "6b_sql"])
def test_6_keeper_impl_landing_completes(tmp_path, monkeypatch, files):
    w = kw.World(tmp_path, monkeypatch)
    sha = landed_card(w, "r9406", files)
    w.work("r9406", intent=False)
    lines = w.round()
    assert w.kinds("complete") == 1 and any("COMPLETED" in x and sha in x for x in lines), lines


def test_6c_keeper_pack_template_landing_completes(tmp_path, monkeypatch):
    w = kw.World(tmp_path, monkeypatch)
    sha = w.commit("pack", TPL, "main")
    w.card("r9407", sha)
    w.work("r9407", intent=False)
    lines = w.round()
    assert w.kinds("complete") == 1 and any("COMPLETED" in x and sha in x for x in lines), lines


@pytest.mark.parametrize("files,want", [({"src/a.py": "x"}, "구현"), ({"design/rag/sql/m.sql": "x"}, "구현"), (TPL, "구현"),
                                        ({"design/k/indices/진행/a.md": "x", "design/teams/p/indices/대기/b.md": "y"}, "카드 문서만"),
                                        ({}, "카드 문서만")], ids=["code", "sql", "pack_tpl", "card", "empty"])
def test_6_land_kind_direct(tmp_path, files, want):
    r, sha = repo(tmp_path, files)
    assert lib_fn("ft_land_kind", r, sha) == (0, want)


@pytest.mark.parametrize("body,want", [("- 구현: 없음 — 문서 카드\n", (0, "ⓐ 구현 없음")),
                                       ("- 닫힘(대조 · 코드 0)\n", (0, "ⓑ 닫힘 코드 0")),
                                       ("- 2026-11-15 — 닫힘(대조 · 코드 0 · x)\n", (0, "ⓑ 닫힘 코드 0")),
                                       ("- 착지: 라이브 DB 반영(11-15)\n", (0, "ⓒ 라이브 DB 반영")),
                                       ("- 착지: 라이브 DB 반영(e6ba7693c6)\n", (1, "")),
                                       ("- 착지: ★사람 승인★ — x\n", (1, "")), ("- 2026-11-15 — 닫힘(대조)\n", (1, "")), ("", (1, ""))],
                         ids=["a", "b", "b_date", "c", "c_hex", "plan", "close_no_code0", "empty"])
def test_no_code_fixed_three(body, want):
    assert lib_fn("ft_no_code", body) == want


# ── 변이 M1~M3(사본 lib · 원본 위 사례와 같은 입력) ──
def mutant(tmp, old, new):
    src = LIB.read_text(encoding="utf-8")
    assert src.count(old) == 1, old
    lib = tmp / "mut-lib.sh"
    lib.write_text(src.replace(old, new, 1), encoding="utf-8")
    return lib


BOUND = 'x.startswith("design/") and "/indices/" in x'
MUT = {"M1": ('"카드 문서만" if all(', '"구현" if all(', {}, "STAGED "),   # 카드 문서만인데 옮김 = ③ FAIL
       "M3a": (BOUND, 'x.startswith("design/")', {"design/rag/sql/m6.sql": "select 1;\n"}, "NOOP r9 완성 증거 0 카드 문서만"),   # ⑥ⓑ FAIL
       "M3b": (BOUND, '"/indices/" in x', TPL, "NOOP r9 완성 증거 0 카드 문서만")}   # ⑥ⓒ FAIL(템플릿을 문서로 봄)


@pytest.mark.parametrize("mut", list(MUT))
def test_mutants_lib(tmp_path, monkeypatch, capsys, mut):
    old, new, files, want = MUT[mut]
    w = kw.World(tmp_path, monkeypatch)
    side = "pack" if files is TPL else "byz"
    sha = w.commit(side, dict(files, **({} if side == "pack" else {CARD % ("대기", "r9"): HEAD % "r9"})), "main" if side == "pack" else OPS)
    side == "pack" and kw._git(w.tmp / "pack", "fetch", "-q", "origin")
    w.commit("byz", {CARD % ("대기", "r9"): HEAD % "r9" + "- 착지: %s\n" % sha}, OPS)
    w.work("r9", done=True, intent=False, turn=None)
    shutil.copy(str(mutant(tmp_path, old, new)), str(w.root / ".fable-team" / "bin" / "ft-land-kind-lib.sh"))
    rc, out = run_stage(w, capsys)
    assert out.startswith(want), out


def test_mutant_m2_card_stage_without_land_kind(tmp_path, monkeypatch, capsys):
    """M2 card_stage 가 land_kind 를 안 부름 → ③ FAIL · keeper ② 는 그대로 PASS(부르는 곳이 따로)."""
    w = stage_world(tmp_path, monkeypatch, {})
    mod = kw._mod(w.ft2 / "adapters" / "pi" / "card_stage.py", "cs2274m2_%d" % id(w))
    mod.land.land_kind = lambda *a: "구현"
    rc = mod.main(["--root", str(w.root), "--team", TEAM, "--work", "r9"])
    assert capsys.readouterr().out.startswith("STAGED "), rc
