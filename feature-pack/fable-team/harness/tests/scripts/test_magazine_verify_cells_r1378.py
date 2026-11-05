"""r1378 매거진 발행 검증(ft-news-verify --kind magazine)이 매거진 글에 맞는 칸만 잰다.

M1 ⓓ = 그 매거진이 만든 원장 sha(지도 last.sha 로 안 떨어진다) · M2 조상 아니면 거짓
M3 ⓘ = 슬랙 뿌리 글 본문만(문서 전체 0) · M4 뿌리 글 파일 없음 = «검증 불가»
M5 꼬리 «검증 N/M · 해당 없음 ⓐⓑⓒ» · 해당 없음을 PASS 로 안 셈 · M6 news 출력·분모 그대로

실행: python3 -m pytest tests/scripts/test_magazine_verify_cells_r1378.py -q
임시 리포·가짜 매거진 HTML·가짜 뿌리 글 · 실 슬랙·실 쪽지 0.
"""
import contextlib
import io
import os
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
BIN = ROOT / "harness" / "bin"
KIT = ROOT / "harness" / "kit" / "slack-mirror"
sys.path[:0] = [str(BIN), str(KIT)]

import _news_verify as nv  # noqa: E402
import _news_verify_cells as cells  # noqa: E402
import _news_verify_lib as lib  # noqa: E402
import _news_verify_pub_cells as pub  # noqa: E402
import root_readback_guard as guard  # noqa: E402  r1004 실제 가드(대역 0)
from real_state_guard import guard_begin_module  # noqa: E402,F401  r541: 실 상태 지문 + git 밖 cwd

NOW = "2026-11-05 08:30"
GIT_ENV = {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}
STALE = "1234567890" + "a" * 30  # 리포에 없는 옛 지도 sha(뉴스 지도 last.sha 자리)


def git(cwd: Path, *a: str) -> str:
    return subprocess.run(["git", "-C", str(cwd), *a], check=True, capture_output=True, text=True, env={**os.environ, **GIT_ENV}).stdout


def write(p: Path, text: str) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8")


def magazine_html() -> str:
    """매거진 글 꼴 — 머리에 리포 sha 0 · 표 줄 25 · «…» 21 · «오빠 할 일»·«팀 N개» 줄 0(문서 전체를 가드에 넣으면 위반)."""
    table = "\n".join(f"<tr><td>항목 {i}</td><td>값 {i}</td></tr>" for i in range(13))
    dots = " ".join(["…"] * 21)
    return (f"<html><body><h1>매거진 2026-11-05 · 오빠 확인판</h1>\n<table>{table}</table>\n"
            f"<section class=\"goal\"><table><tr><td>골 1</td><td>진행</td></tr></table></section>\n<p>{dots}</p></body></html>")


class World:
    """임시 원장 사본(origin/main ref 있음) · 가짜 매거진 HTML · 가짜 뿌리 글 파일 하나."""

    def __init__(self, tmp: Path):
        self.tmp, self.root = tmp, tmp / "root"
        self.repo = self._repo(tmp)
        self.head = git(self.repo, "rev-parse", "HEAD").strip()
        self.base = git(self.repo, "rev-parse", "HEAD~1").strip()
        self.state = self.root / ".fable-team/state/news-ledger"
        self.st = self.root / ".fable-team/state/news-verify"
        write(self.state / "last.sha", STALE + "\n")
        self.html = tmp / f"MAGAZINE-DOC-2026-11-05-{self.head[:10]}.html"
        write(self.html, magazine_html())
        self.root_txt = tmp / f"MAGAZINE-DOC-2026-11-05-{self.head[:10]}.root.txt"
        write(self.root_txt, "매거진 2026-11-05 · 오빠 확인판\n오늘 원장은 3팀이 한 일을 담았다.\n전문은 HTML 한 장에 있다.")

    @staticmethod
    def _repo(tmp: Path) -> Path:
        origin, repo = tmp / "origin.git", tmp / "repo"
        subprocess.run(["git", "init", "-q", "--bare", "-b", "main", str(origin)], check=True)
        subprocess.run(["git", "clone", "-q", str(origin), str(repo)], check=True, capture_output=True)
        git(repo, "checkout", "-q", "-b", "main")
        write(repo / "design/TEAMS.md", "| 팀 | 폴더 | 상태 |\n|---|---|---|\n| harness | `design/harness/` | 현역 |\n")
        git(repo, "add", "-A")
        git(repo, "commit", "-qm", "base")
        write(repo / "design/teams/planner/PLAN-oppa-ledger.md", "# 오빠 원장\n")
        git(repo, "add", "-A")
        git(repo, "commit", "-qm", "원장")
        git(repo, "push", "-q", "origin", "main")
        git(repo, "fetch", "-q", "origin")
        return repo

    def ctx(self, kind: str = "magazine", pub_sha: str = "", root_text: Path | None = None) -> lib.Ctx:
        return lib.Ctx(kind=kind, texts=[lib.read_body(self.html)], root=self.root, repo=self.repo,
                       rel="design/teams/planner/PLAN-oppa-ledger.md", state=self.state, verify_state=self.st,
                       now=nv._now(), pub_sha=pub_sha, root_text=root_text)


@pytest.fixture
def world(tmp_path, monkeypatch):
    w = World(tmp_path)
    monkeypatch.setenv("FT_ROOT", str(w.root))
    monkeypatch.setenv("FT_NOW", NOW)
    monkeypatch.setenv("FT_NEWS_VERIFY_NOTIFY", "0")  # 쪽지 0(실 mbox 안 건드린다)
    monkeypatch.setenv("FT_NEWS_VERIFY_STATE", str(w.st))
    return w


def run(w: World, *extra: str) -> tuple[int, str]:
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = nv.main(["--kind", "magazine", "--body", str(w.html), "--root", str(w.root), "--repo", str(w.repo),
                      "--state", str(w.state), "--tail", *extra])
    return rc, buf.getvalue()


# ── M1·M2 ⓓ 발행 sha = 그 매거진이 만든 원장 sha ─────────────────────────────

def test_m1_pub_sha_is_origin_main_head_not_ledger_map(world):
    """M1: --pub-sha = origin/main 머리 · 지도 last.sha 는 리포 밖 옛 sha → ⓓ 참 · 출력에 last.sha 값 0."""
    verdict, why = cells.cell_d(world.ctx(pub_sha=world.head))
    assert verdict == lib.PASS, why
    assert STALE[:10] not in why, why
    assert world.head[:10] in why


def test_m2_pub_sha_not_ancestor_is_false(world):
    """M2: --pub-sha = origin/main 의 조상 아닌 sha → ⓓ 거짓 «발행본이 옛 판»(진짜 사건은 그대로 실패)."""
    orphan = subprocess.run(["git", "-C", str(world.repo), "commit-tree", git(world.repo, "rev-parse", "HEAD^{tree}").strip(), "-m", "옛 갈래"],
                            capture_output=True, text=True, check=True, env={**os.environ, **GIT_ENV}).stdout.strip()
    verdict, why = cells.cell_d(world.ctx(pub_sha=orphan))
    assert verdict == lib.FAIL, why
    assert "옛 판" in why, why


def test_m1b_pub_sha_missing_falls_to_body_name_not_map(world):
    """M1 보탬: --pub-sha 없이 파일 이름 MAGAZINE-DOC-<날>-<sha10> 만 있어도 그 sha 로 잰다(지도 last.sha 로 0)."""
    sha = nv._pub_sha("", [world.html])
    assert sha == world.head[:10], sha
    verdict, why = cells.cell_d(world.ctx(pub_sha=sha))
    assert verdict == lib.PASS, why
    assert STALE[:10] not in why, why
    rc, out = run(world)  # 끝-끝: ⓓ 는 실패 줄에 없다 = 참(다른 칸은 모름/검증 불가로 남는다)
    assert "ⓓ 발행 sha" not in out, out


# ── M3·M4 ⓘ 뿌리 글 칸 = 슬랙에 올린 뿌리 글 본문만 ─────────────────────────

def test_m3_root_text_only_passes_while_doc_would_fail(world):
    """M3: 뿌리 글 = 짧은 글(가드 통과) · 문서 HTML 은 표 줄 25·«…» 21 → ⓘ 참(문서 전체를 넣으면 거짓)."""
    doc = "\n".join(world.ctx().texts)  # 문서 전체 본문
    assert guard.check(doc), "가드가 문서 전체를 통과시키면 이 시험이 뜻이 없다"
    verdict, why = pub.cell_i(world.ctx(root_text=world.root_txt))
    assert verdict == lib.PASS, why


def test_m4_root_text_missing_is_unavailable_not_pass(world):
    """M4: --root-text 파일 없음 → ⓘ «검증 불가» · PASS 0(문서 전체로 되돌아가지 않는다)."""
    verdict, why = pub.cell_i(world.ctx(root_text=world.tmp / "없는파일.root.txt"))
    assert verdict == lib.UNAVAILABLE, why
    assert verdict != lib.PASS


# ── M5·M6 꼬리·분모·뉴스 회귀 ─────────────────────────────────────────────

def _stub_cells(monkeypatch, verdict=lib.PASS):
    """칸 판정 대역 — 꼬리·분모만 본다(칸 내용은 M1~M4 가 따로 잰다)."""
    def fake(name: str, fn, ctx):
        if verdict == "one_missing":
            return (lib.UNKNOWN, "대역 실패") if name.startswith("ⓗ") else (lib.PASS, "대역 참")
        return verdict, "대역 참"
    monkeypatch.setattr(nv, "run_cell", fake)


def test_m5_magazine_tail_counts_applied_cells_only(world, monkeypatch):
    """M5: 꼬리 = «검증 6/6 · 해당 없음 ⓐⓑⓒ» · 해당 없음은 PASS 로 안 셈(분모 6 · 9 아님)."""
    _stub_cells(monkeypatch)
    rc, out = run(world)
    assert rc == 0, out
    assert "검증 6/6 · 해당 없음 ⓐⓑⓒ" in out, out
    assert world.html.read_text(encoding="utf-8").rstrip().endswith("검증 6/6 · 해당 없음 ⓐⓑⓒ")
    assert "ⓐ 오빠 할 일 건수 —" not in out  # 해당 없음 칸은 실패 줄에도 안 나온다


def test_m5b_one_applied_cell_fails_is_5_of_6(world, monkeypatch):
    """M5 보탬: 적용 칸 하나 실패 → «검증 5/6» rc1(해당 없음 3칸을 참으로 세면 8/9 가 된다)."""
    _stub_cells(monkeypatch, "one_missing")
    rc, out = run(world)
    assert rc == 1, out
    assert "검증 5/6 · 해당 없음 ⓐⓑⓒ" in out, out
    assert "ⓗ 팀 지도 — 대역 실패" in out, out


def test_m6_news_output_and_denominator_unchanged(world, monkeypatch):
    """M6: --kind news 같은 입력 → 꼬리 «검증 9/9»·«해당 없음» 0·분모 9(지금과 같은 바이트)."""
    _stub_cells(monkeypatch)
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = nv.main(["--kind", "news", "--body", str(world.html), "--root", str(world.root), "--repo", str(world.repo),
                      "--state", str(world.state), "--tail"])
    out = buf.getvalue()
    assert rc == 0, out
    assert "kind=news 검증 9/9" in out, out
    assert "해당 없음" not in out, out
    assert world.html.read_text(encoding="utf-8").rstrip().endswith("검증 9/9")


# ── 발행기 호출 줄: --pub-sha(발행 줄 원장 sha) + --root-text(뿌리 글 파일) ─────────

FAKE_DOC = '''
import argparse

LEDGER_SHA = "__SHA__"


def parse_args(argv):
    p = argparse.ArgumentParser()
    for name in ("--src-repo", "--src-sha", "--src-path", "--date", "--state", "--out-dir"):
        p.add_argument(name, default="")
    p.add_argument("--publish", action="store_true")
    p.add_argument("--dry-run", action="store_true")
    return p.parse_known_args(argv)[0]


if __name__ == "__main__":
    print("PUBLISH warn=0 elapsed=0.1s html=MAGAZINE-DOC-x.html")
    print(f"published date=2026-11-05 {LEDGER_SHA}:design/teams/planner/PLAN-oppa-ledger.md root_ts=1.1 html=MAGAZINE-DOC-x.html")
'''


def test_shell_call_passes_pub_sha_and_root_text(world, tmp_path):
    """발행기 호출 줄(계약): published 줄의 원장 sha → --pub-sha · 발행본 옆 .root.txt → --root-text."""
    outdir = tmp_path / "out"
    write(outdir / "MAGAZINE-DOC-x.html", magazine_html())
    fake = tmp_path / "fake_doc.py"
    write(fake, FAKE_DOC.replace("__SHA__", world.head))
    seen = tmp_path / "args.log"
    verify = tmp_path / "fake-verify.sh"
    write(verify, '#!/usr/bin/env bash\nprintf \'%s\\n\' "$@" > "$FT_TEST_ARGS"\n')
    env = {**os.environ, "FT_ROOT": str(world.root), "FT_NEWS_NOW": NOW, "FT_LEDGER_REPO": str(world.repo),
           "FT_LEDGER_SYNCED": "1", "FT_LEDGER_FRESH_GATE": "0", "FT_MAGAZINE_DOC": str(fake),
           "FT_NEWS_VERIFY_BIN": str(verify), "FT_TEST_ARGS": str(seen)}
    done = subprocess.run(["bash", str(KIT / "magazine_from_news.sh"), "--out-dir", str(outdir)],
                          capture_output=True, text=True, env=env)
    assert done.returncode == 0, done.stderr
    args = seen.read_text(encoding="utf-8").splitlines()
    assert args[0] == "--kind" and args[1] == "magazine"
    assert args[args.index("--pub-sha") + 1] == world.head, args
    assert args[args.index("--root-text") + 1] == str(outdir / "MAGAZINE-DOC-x.root.txt"), args
    assert "--tail" in args
