"""r2274 «구현 착지» 판정 한 곳(land_kind) — keeper 착지 · card_stage 완성 이동 (카드 반례 ①②③④⑥ · 변이 M1~M3).
대역 = keeper_world_r1812(임시 bare byz·pack · 임시 root · 임시 원장) · 합성 카드 · 판정 불가 대역 = root 의 lib 자리에 둔 가짜 lib · 실 리포·실 원장 0.
기준판 = 팩 origin/main 1abd86cb → ② ③ Red(카드 문서만 착지를 착지로 셈) · ① 은 land_kind 없음 Red. sleep 0(시간 초과 대역 = 가짜 git · 상한 env 0.3초).
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
STUB = '#!/usr/bin/env bash\nft_land_kind() { echo "판정 불가 git diff-tree 시간초과 7초 대역"; return 3; }\n'
CARD = "design/harness/indices/%s/%s-x.md"
HEAD = "# 인덱스: %s\n- 상태: 대기\n- 남은 범위: 없음\n"


def land_kind(*args, env=None):
    p = subprocess.run(["bash", "-c", '. "$1" || exit 9; ft_land_kind "$2" "$3"', "x", str(LIB)] + [str(a) for a in args],
                       capture_output=True, text=True, timeout=25, env=env)
    return p.returncode, p.stdout.strip()


def landed_card(w, work, files, stage="진행", head="", refs=(OPS, MAIN)):
    """카드 신설 합침(files + 카드 .md) = 착지 sha → 같은 카드에 «- 착지: <그 sha>» 줄(두 ref)."""
    path = CARD % (stage, work)
    sha = w.commit("byz", dict(files, **{path: HEAD % work + head}), OPS)
    for ref in refs:
        w.commit("byz", {path: HEAD % work + head + "- 착지: %s\n" % sha}, ref)
    return sha


def stub_lib(w):
    lib = w.root / ".fable-team" / "bin" / "ft-land-kind-lib.sh"
    lib.parent.mkdir(parents=True, exist_ok=True)
    lib.write_text(STUB, encoding="utf-8")


# ── ① 판정 불가(land_kind 한 곳) ──
def test_1a_missing_sha_undecidable(tmp_path):
    subprocess.run(["git", "init", "-q", str(tmp_path)], check=True)
    rc, out = land_kind(tmp_path, "0" * 40)
    assert rc == 3 and out.startswith("판정 불가 ") and len(out.splitlines()) == 1, out


def test_1b_git_slow_undecidable(tmp_path):
    fake = tmp_path / "fake"
    fake.mkdir()
    (fake / "git").write_text("#!/bin/sh\nexec sleep 5\n", encoding="utf-8")
    (fake / "git").chmod(0o755)
    env = dict(os.environ, PATH=str(fake) + os.pathsep + os.environ["PATH"], FT_LAND_KIND_SEC="0.3")
    rc, out = land_kind(tmp_path, "ab" * 20, env=env)
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


# ── ② keeper: 카드 문서만 착지 = complete 0 ──
def test_2_keeper_card_doc_only_landing_complete_0(tmp_path, monkeypatch):
    w = kw.World(tmp_path, monkeypatch)
    sha = landed_card(w, "r9402", {})
    w.work("r9402", intent=False)
    lines = w.round()
    assert w.kinds("complete") == 0, lines
    assert any("r9402" in x and "카드 문서만 착지 " + sha[:8] in x for x in lines), lines


# ── ③ ④ ⑥ card_stage ──
def stage_world(tmp, mp, files, stage="대기", head=""):
    w = kw.World(tmp, mp)
    w.sha = landed_card(w, "r9", files, stage=stage, head=head, refs=(OPS,))
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


def test_3_card_stage_card_doc_only_noop(tmp_path, monkeypatch, capsys):
    w = stage_world(tmp_path, monkeypatch, {})
    before = heads(w)
    rc, out = run_stage(w, capsys)
    assert (rc, out) == (0, "NOOP r9 완성 증거 0 카드 문서만 착지 %s" % w.sha[:8]), out
    assert heads(w) == before


def staged(w, rc, out, frm="대기"):
    assert rc == 0 and out.startswith("STAGED r9-x %s→완성 " % frm), out
    names = bare(w, "ls-tree", "-r", "--name-only", OPS).splitlines()
    assert CARD % ("완성", "r9") in names and CARD % (frm, "r9") not in names


def test_4_card_stage_doc_card_exception_stages(tmp_path, monkeypatch, capsys):
    w = stage_world(tmp_path, monkeypatch, {}, head="- 구현: 없음 — 문서 카드\n")
    staged(w, *run_stage(w, capsys))


@pytest.mark.parametrize("files", [{"src/app.py": "x\n"}, {"design/rag/sql/m6.sql": "select 1;\n"}], ids=["6a_code", "6b_sql"])
def test_6_card_stage_impl_landing_stages(tmp_path, monkeypatch, capsys, files):
    w = stage_world(tmp_path, monkeypatch, files)
    staged(w, *run_stage(w, capsys))


@pytest.mark.parametrize("files", [{"src/app.py": "x\n"}, {"design/rag/sql/m6.sql": "select 1;\n"}], ids=["6a_code", "6b_sql"])
def test_6_keeper_impl_landing_completes(tmp_path, monkeypatch, files):
    w = kw.World(tmp_path, monkeypatch)
    sha = landed_card(w, "r9406", files)
    w.work("r9406", intent=False)
    lines = w.round()
    assert w.kinds("complete") == 1 and any("COMPLETED" in x and sha in x for x in lines), lines


@pytest.mark.parametrize("files,want", [({"src/a.py": "x"}, "구현"), ({"design/rag/sql/m.sql": "x"}, "구현"),
                                        ({"design/k/indices/진행/a.md": "x"}, "카드 문서만"), ({}, "구현")], ids=["code", "sql", "card", "empty"])
def test_6_land_kind_direct(tmp_path, files, want):
    r = tmp_path / "r"
    subprocess.run(["git", "init", "-q", "-b", "main", str(r)], check=True)
    for rel, body in files.items():
        kw._put(r / rel, body)
    kw._git(r, "add", "-A"), kw._git(r, "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false", "commit", "-q", "--allow-empty", "-m", "x")
    assert land_kind(r, kw._git(r, "rev-parse", "HEAD")) == (0, want)


# ── 변이 M1~M3(사본 lib · 원본 위 사례와 같은 입력) ──
def mutant(tmp, old, new):
    src = LIB.read_text(encoding="utf-8")
    assert old in src
    lib = tmp / "mut-lib.sh"
    lib.write_text(src.replace(old, new, 1), encoding="utf-8")
    return lib


@pytest.mark.parametrize("mut", ["M1", "M3"])
def test_mutants_lib(tmp_path, monkeypatch, capsys, mut):
    """M1 늘 «구현» → ③ FAIL · M3 경계 design/* → ⑥ⓑ FAIL(원본은 위 ③·⑥ⓑ PASS)."""
    old, new, files = {"M1": ('"카드 문서만" if paths', '"구현" if paths', {}),
                       "M3": ('"*/indices/*"', '"design/*"', {"design/rag/sql/m6.sql": "select 1;\n"})}[mut]
    w = stage_world(tmp_path, monkeypatch, files)
    lib = w.root / ".fable-team" / "bin" / "ft-land-kind-lib.sh"
    lib.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy(str(mutant(tmp_path, old, new)), str(lib))
    rc, out = run_stage(w, capsys)
    if mut == "M1":
        assert out.startswith("STAGED "), out   # 카드 문서만인데 옮김 = ③ FAIL
    else:
        assert out.startswith("NOOP r9 완성 증거 0 카드 문서만"), out   # SQL 착지를 문서만으로 봄 = ⑥ⓑ FAIL


def test_mutant_m2_card_stage_without_land_kind(tmp_path, monkeypatch, capsys):
    """M2 card_stage 가 land_kind 를 안 부름 → ③ FAIL · keeper ② 는 그대로 PASS(부르는 곳이 따로)."""
    w = stage_world(tmp_path, monkeypatch, {})
    mod = kw._mod(w.ft2 / "adapters" / "pi" / "card_stage.py", "cs2274m2_%d" % id(w))
    mod.land.land_kind = lambda *a: "구현"
    rc = mod.main(["--root", str(w.root), "--team", TEAM, "--work", "r9"])
    assert capsys.readouterr().out.startswith("STAGED "), rc
