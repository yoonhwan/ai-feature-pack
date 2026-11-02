#!/usr/bin/env python3
"""test_goal_readjust_root_r1324.py — 골 재조정 상태 모듈의 «루트 규칙 통일» 시험(r1324 카드 §계약 G1~G4 · §반례 Q1~Q6).

  G1 루트 = root 인자 › ft_goal_ledger.find_root(골 표와 같은 함수) — Q1 · Q3 · Q5 · M1 · M3
  G2 «루트 판정 불가» ≠ «기록 없음» — Q2 · Q4 · M2
  G3 쓰기(state_dir(strict=True))도 같은 루트 — Q5 · M1
  G4 렌더는 죽지 않는다 · H13(LIVE_ROOT 무효) 그대로 — Q2 · Q6 · M4
  ★기준판(팩 origin/main 판)에서는 Q1·Q2·Q5 가 FAIL 한다★ — 이 시험이 «지금 판» 을 재는지 확인하는 칸.

시험 입력 = mktemp 임시 리포 2개(git init · .fable-team/LIVE_BIN · .fable-team/LIVE_ROOT) + 임시 워크트리 1(git worktree add)
  + 임시 데이터 루트(회차 json 1개) — cwd·env 는 칸마다 명시(부르는 쪽 cwd 의존 0) · 네트워크 0 · 자기 재호출 0 · 고정 sleep 0.
"""
from __future__ import annotations

import contextlib
import hashlib
import importlib.util
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import traceback
from pathlib import Path

HARNESS = Path(__file__).resolve().parents[2]
BIN = HARNESS / "bin"
KIT = HARNESS / "kit" / "fable-team" / "bin"
NOW = "2026-11-02 15:00"          # FT_NOW — 머리 «26시간 초과» 판정을 고정한다
GOAL_HASH = "aa11bb22cc"          # 회차 파일 행 식별 = 골 전문 sha10
CANON = "0123456789"
ROUND = {
    "run": "20261102-1", "attempt": 2, "status": "OK", "finished": "2026-11-02 14:41:00",
    "baseline": None, "rows": [{"n": 1, "goal_hash": GOAL_HASH, "label": "기준", "cards_added": 0,
                                "evidence": [], "unknown": []}],
    "inputs": {"canon_sha10": CANON},
}
FAILS: list[str] = []
TMP = Path(tempfile.mkdtemp(prefix="r1324-"))


def ok(label: str, sec: float) -> None:
    print(f"PASS {label} ({sec:.2f}s)")


def bad(label: str, why: str, sec: float) -> None:
    FAILS.append(label)
    print(f"FAIL {label} :: {why[-1200:]} ({sec:.2f}s)")


def run(label: str, fn) -> object | None:
    t0 = time.monotonic()
    try:
        got = fn()
    except Exception:  # noqa: BLE001 — 시험 러너는 예외도 FAIL 로 센다(조용한 0 금지)
        bad(label, traceback.format_exc(), time.monotonic() - t0)
        return None
    ok(label, time.monotonic() - t0)
    return got


# ── 픽스처 ─────────────────────────────────────────────────────────────────────
def git(*args: str, cwd: Path) -> str:
    env = {**os.environ, "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"}
    r = subprocess.run(["git", *args], cwd=str(cwd), capture_output=True, text=True, timeout=7, env=env)
    if r.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} rc={r.returncode} {(r.stderr or r.stdout)[-300:]}")
    return r.stdout.strip()


def make_repo(path: Path) -> Path:
    path.mkdir(parents=True)
    git("init", "-q", "-b", "main", cwd=path)
    (path / ".gitignore").write_text(".fable-team/\n", encoding="utf-8")
    (path / "README.md").write_text("r1324 픽스처\n", encoding="utf-8")
    (path / ".fable-team").mkdir()
    (path / ".fable-team" / "LIVE_BIN").write_text("1.1.255\n", encoding="utf-8")
    git("-c", "user.name=t", "-c", "user.email=t@t", "add", "-A", cwd=path)
    git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "init", cwd=path)
    return path


def make_data(path: Path) -> Path:
    d = path / ".fable-team" / "state" / "goal-readjust" / "rounds"
    d.mkdir(parents=True)
    (d / "20261102-1-02.json").write_text(json.dumps(ROUND, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    return path


def world(name: str, *, rounds: bool = True, live_root: str | None = "data") -> dict:
    """임시 리포 + 워크트리 + 데이터 루트(+회차 1). live_root=None 이면 LIVE_ROOT 파일 없음 · 'broken' 이면 무효 값."""
    root = TMP / name
    repo = make_repo(root / "repo")
    wt = root / "wt"
    git("worktree", "add", "-q", str(wt), "-b", "wt1", cwd=repo)
    data = make_data(root / "data") if rounds else (root / "data").mkdir(parents=True) or root / "data"
    if live_root == "broken":
        (repo / ".fable-team" / "LIVE_ROOT").write_text(str(root / "no-such-dir") + "\n", encoding="utf-8")
    elif live_root:
        (repo / ".fable-team" / "LIVE_ROOT").write_text(str(data) + "\n", encoding="utf-8")
    outside = root / "outside"
    outside.mkdir()
    return {"root": root, "repo": repo, "wt": wt, "data": data, "outside": outside}


# ── 모듈 로드 · cwd/env 고정 ────────────────────────────────────────────────────
def load_state(bin_dir: Path, tag: str):
    name = f"rs_{tag}"
    spec = importlib.util.spec_from_file_location(name, bin_dir / "ft_goal_readjust_state.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


@contextlib.contextmanager
def at(bin_dir: Path, cwd: Path, tag: str = "now", **envvars: str):
    """cwd·env 를 이 칸의 입력으로 고정하고 그 bin 의 모듈을 새로 import 한다(다른 칸과 섞이지 않는다)."""
    saved_cwd = os.getcwd()
    saved = {k: os.environ.get(k) for k in ("FT_ROOT", "FT_NOW")}
    os.environ.pop("FT_ROOT", None)
    os.environ["FT_NOW"] = NOW
    for k, v in envvars.items():
        os.environ[k] = str(v)
    for name in ("ft_goal_ledger", "ft_team_lib"):   # 이전 칸이 import 한 사본을 재사용하지 않는다
        sys.modules.pop(name, None)
    sys.path.insert(0, str(bin_dir))
    os.chdir(cwd)
    try:
        yield load_state(bin_dir, tag)
    finally:
        os.chdir(saved_cwd)
        sys.path.remove(str(bin_dir))
        for k, v in saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v


def cells(mod) -> dict:
    state = mod.read()
    return {"header": mod.header(state), "cell": mod.row_cell(state, 1, GOAL_HASH, CANON),
            "error": state.get("error"), "run": (state.get("last_ok") or {}).get("run")}


def strict_dir(mod):
    return mod.state_dir(strict=True)


def probe_dir(ctx) -> tuple[str, str]:
    """state_dir(strict=True) 결과 — («dir», 경로) 또는 («err», 사유). 예외도 «판정 불가» 라는 값으로 잡는다(Q5·Q6·M1)."""
    try:
        with ctx as mod:
            return "dir", str(strict_dir(mod))
    except RuntimeError as exc:
        return "err", f"{type(exc).__name__}: {exc}"


def q5(got: tuple[str, str], want: Path) -> None:
    kind, val = got
    assert kind == "dir", f"state_dir 못 풂 :: {val}"
    assert Path(val) == want, f"state_dir={val}"


def _err(probe: tuple[str, str], need: str = "") -> str:
    kind, val = probe
    assert kind == "err", f"StatePathError 가 아니다 :: {kind}={val}"
    assert need in val, f"사유={val!r} 에 {need!r} 없음"
    return val


def error_of(fn) -> str:
    try:
        fn()
    except Exception as exc:  # noqa: BLE001 — 사유 글자를 본다
        return f"{type(exc).__name__}: {exc}"
    return ""

# ── Q1 «FT_ROOT 없이 워크트리 cwd» — 회차가 실재하면 머리 «재조정: ok=…» · 칸 «기준» ─────
def q1(got: dict) -> None:
    assert got is not None, "read/header/row_cell 이 죽었다"
    assert got["error"] is None, f"루트를 못 풀었다 :: {got['error']!r}"
    assert got["run"] == "20261102-1", f"last_ok={got['run']!r}"
    assert got["header"].startswith("재조정: ok=20261102-1 14:41"), f"머리={got['header']!r}"
    assert got["cell"] == "기준", f"칸={got['cell']!r}"


# ── Q2 «git 밖 cwd · FT_ROOT 없음» — 판정 불가(«기록 없음» 글자 0) ────────────────────
def q2(got: dict) -> None:
    assert got is not None, "read/header/row_cell 이 죽었다(렌더를 죽이면 G4 위반)"
    assert got["header"].startswith("재조정 판정 불가("), f"머리={got['header']!r}"
    assert got["cell"] == "모름(루트 판정 불가)", f"칸={got['cell']!r}"
    blob = got["header"] + got["cell"]
    assert "기록 없음" not in blob, f"«기록 없음» 글자가 남았다 :: {blob!r}"


# ── Q4 «루트 정상 · 회차 0» — 그때만 «기록 없음» ──────────────────────────────────
def q4(got: dict) -> None:
    assert got is not None, "read/header/row_cell 이 죽었다"
    assert got["error"] is None, f"루트 판정 불가로 샜다 :: {got['error']!r}"
    assert got["header"] == "재조정 기록 없음", f"머리={got['header']!r}"
    assert got["cell"] == "모름(기록 없음)", f"칸={got['cell']!r}"


# ── Q6 «LIVE_ROOT 무효» — 판정 불가(리포 루트로 조용히 대체 0 · H13) ────────────────────
def q6(got: dict, why: str) -> None:
    assert got is not None, "read/header/row_cell 이 죽었다"
    assert got["header"].startswith("재조정 판정 불가("), f"머리={got['header']!r}"
    assert "LIVE_ROOT 무효" in got["header"], f"사유가 LIVE_ROOT 무효가 아니다 :: {got['header']!r}"
    assert got["cell"] == "모름(루트 판정 불가)", f"칸={got['cell']!r}"
    assert "상태 폴더" not in why and "LIVE_ROOT 무효" in why, f"strict 사유={why!r}"


# ── 변이 ───────────────────────────────────────────────────────────────────────
def variant(name: str, edits: list[tuple[str, str]]) -> Path:
    d = TMP / "mut" / name
    d.mkdir(parents=True)
    for f in ("ft_goal_readjust_state.py", "ft_goal_ledger.py", "ft_team_lib.py"):
        shutil.copy2(BIN / f, d / f)
    p = d / "ft_goal_readjust_state.py"
    s = p.read_text(encoding="utf-8")
    for old, new in edits:
        assert s.count(old) >= 1, f"변이 {name}: 치환 대상이 없다 :: {old[:60]!r}"
        s = s.replace(old, new, 1)
    p.write_text(s, encoding="utf-8")
    return d


def main() -> int:
    base_sha = git("rev-parse", "HEAD", cwd=HARNESS)
    top = Path(git("rev-parse", "--show-toplevel", cwd=HARNESS))
    rel = BIN.relative_to(top)
    bin_before = hashlib.sha256((BIN / "ft_goal_readjust_state.py").read_bytes()).hexdigest()
    print(f"INFO head={base_sha[:10]} bin_sha={bin_before[:12]} python={sys.version.split()[0]} tmp={TMP}")

    # 기준판 = 팩 origin/main 판(이 카드의 «전» 판) · 새 판 = 지금 작업 파일
    base_dir = TMP / "base"
    base_dir.mkdir()
    (base_dir / "ft_goal_readjust_state.py").write_bytes(
        subprocess.run(["git", "show", f"origin/main:{rel.as_posix()}/ft_goal_readjust_state.py"],
                       cwd=str(HARNESS), capture_output=True, timeout=7, check=True).stdout)
    for f in ("ft_goal_ledger.py", "ft_team_lib.py"):
        shutil.copy2(BIN / f, base_dir / f)

    w = world("q1", live_root="data")
    w0 = world("q4", rounds=False, live_root=None)
    w6 = world("q6", live_root="broken")

    # ── Q1·Q2·Q3·Q4·Q5·Q6 (지금 판) ────────────────────────────────────────────
    want_dir = w["data"] / ".fable-team" / "state" / "goal-readjust"
    run("Q1 FT_ROOT 없이 워크트리 cwd = 머리 «재조정: ok=…» · 칸 «기준»",
        lambda: judge_cells(q1, at(BIN, w["wt"], "q1a")))
    run("Q2 git 밖 cwd · FT_ROOT 없음 = «재조정 판정 불가(…)» · 칸 «모름(루트 판정 불가)» · «기록 없음» 글자 0",
        lambda: q2(cells_with(at(BIN, w["outside"], "q2a"))))
    run("Q3 FT_ROOT=<리포> · cwd 밖 = Q1 과 같은 출력(회귀)",
        lambda: q1(cells_with(at(BIN, w["outside"], "q3a", FT_ROOT=str(w["repo"])))))
    run("Q4 루트 정상 · 회차 0 = «재조정 기록 없음» · «모름(기록 없음)»",
        lambda: q4(cells_with(at(BIN, w0["outside"], "q4a", FT_ROOT=str(w0["repo"])))))
    run("Q5 FT_ROOT 없이 워크트리 cwd → state_dir(strict=True) = <데이터 루트>/state/goal-readjust",
        lambda: q5(probe_dir(at(BIN, w["wt"], "q5a")), want_dir))
    run("Q5b git 밖 cwd → StatePathError 사유에 find_root 사유(LIVE_BIN)",
        lambda: _assert(_err(probe_dir(at(BIN, w["outside"], "q5b"))).find("LIVE_BIN") >= 0, "사유에 LIVE_BIN 없음"))
    run("Q6 LIVE_ROOT 무효 = «재조정 판정 불가(LIVE_ROOT 무효…)» · strict 도 같은 사유",
        lambda: q6(cells_with(at(BIN, w6["outside"], "q6a", FT_ROOT=str(w6["repo"]))),
                   _err(probe_dir(at(BIN, w6["outside"], "q6b", FT_ROOT=str(w6["repo"]))), "LIVE_ROOT 무효")))

    # ── 기준판(팩 origin/main) — Q1·Q2·Q5 가 FAIL 해야 «지금 판» 을 재는 시험이다 ──────────
    run("기준판 Q1 FAIL(«재조정 기록 없음» — 회차가 실재하는데 못 본다)",
        lambda: _must_fail(q1, cells_with(at(base_dir, w["wt"], "b1"))))
    run("기준판 Q2 FAIL(«기록 없음» 글자가 남는다 — 판정 불가 아님)",
        lambda: _must_fail(q2, cells_with(at(base_dir, w["outside"], "b2"))))
    run("기준판 Q5 FAIL(StatePathError «FT_ROOT 없음»)",
        lambda: (_assert("FT_ROOT 없음" in _err(probe_dir(at(base_dir, w["wt"], "b5"))), "기준판 사유가 «FT_ROOT 없음» 이 아니다"),
                 _must_fail(lambda got: q5(got, want_dir), probe_dir(at(base_dir, w["wt"], "b5b")))))

    # ── 변이 M1~M4 (하나씩 독립 · 각 뒤 bin·kit cmp0) ────────────────────────────
    m1 = variant("M1", [('        return find_root(StatePathError), ""', '        return None, "FT_ROOT 없음"')])
    run("M1 find_root 폴백 삭제(FT_ROOT 만) → Q1·Q5 FAIL",
        lambda: (_must_fail(q1, cells_with(at(m1, w["wt"], "m1"))),
                 _must_fail(lambda got: q5(got, want_dir), probe_dir(at(m1, w["wt"], "m1b"))),
                 _cmp0()))
    m2 = variant("M2", [('        return f"재조정 판정 불가({_reason(state[\'error\'])})"', '        return "재조정 기록 없음"'),
                        ('        return WHERE', '        return "모름(기록 없음)"')])
    run("M2 판정 불가를 «기록 없음» 글자로 → Q2 FAIL · Q4 는 그대로 PASS",
        lambda: (_must_fail(q2, cells_with(at(m2, w["outside"], "m2"))),
                 q4(cells_with(at(m2, w0["outside"], "m4ok", FT_ROOT=str(w0["repo"])))),
                 _cmp0()))
    m3 = variant("M3", [("\nimport os\n", "\nimport os\nimport subprocess\n"),
                        ('        return find_root(StatePathError), ""',
                         '        out = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, timeout=7).stdout.strip()\n'
                         '        return (Path(out), "") if out else (None, "M3")')])
    run("M3 git 공용 루트 대신 cwd 의 --show-toplevel(워크트리 자신) → Q1 FAIL",
        lambda: (_must_fail(q1, cells_with(at(m3, w["wt"], "m3"))), _cmp0()))
    m4 = variant("M4", [('    return (path, "") if path.is_dir() else (None, f"LIVE_ROOT 무효({path})")',
                         '    return (path, "") if path.is_dir() else (base, "")')])
    run("M4 LIVE_ROOT 무효를 리포 루트로 대체 → Q6 FAIL",
        lambda: (_must_fail(lambda c: q6(c, "LIVE_ROOT 무효(변이 제거)"),
                            cells_with(at(m4, w6["outside"], "m4a", FT_ROOT=str(w6["repo"])))),
                 _cmp0()))

    # ── 잔여 조건 — bin·kit cmp0 · 작업 파일 불변 · 새 실행 비트 0 · 회귀 목록 안내 ──────
    run("bin ↔ kit cmp0 (같은 판)", lambda: _assert(*_cmp_pair(BIN / "ft_goal_readjust_state.py",
                                                             KIT / "ft_goal_readjust_state.py")))
    run("시험 뒤 작업 파일 불변(변이는 사본만 고쳤다)",
        lambda: _assert(hashlib.sha256((BIN / "ft_goal_readjust_state.py").read_bytes()).hexdigest() == bin_before,
                        "bin/ft_goal_readjust_state.py 가 변했다"))
    run("새 시험 파일 모드 = 실행 비트 0(100644)",
        lambda: _assert(not (Path(__file__).stat().st_mode & 0o111), f"mode={stat.S_IMODE(Path(__file__).stat().st_mode):o}"))

    print(f"== test_goal_readjust_root_r1324: fail={len(FAILS)} · head={base_sha[:10]} · tmp={TMP}")
    return 0 if not FAILS else 1


# ── 작은 도우미 ────────────────────────────────────────────────────────────────
def _assert(cond, why: str):
    assert cond, why
    return cond


def _cmp_pair(a: Path, b: Path) -> tuple[bool, str]:
    return (a.read_bytes() == b.read_bytes(), f"{a.name} ≠ {b.name}")


def _cmp0() -> None:
    _assert(*_cmp_pair(BIN / "ft_goal_readjust_state.py", KIT / "ft_goal_readjust_state.py"))


def _must_fail(judge, got) -> None:
    """judge 가 got 을 FAIL 시켜야 통과 — 변이·기준판이 «그 칸» 에서만 갈린다는 증거."""
    try:
        judge(got)
    except AssertionError:
        return
    raise AssertionError("변이/기준판이 이 칸을 통과했다(칸이 변이를 못 잡는다)")


def cells_with(ctx) -> dict:
    with ctx as mod:
        return cells(mod)


def judge_cells(judge, ctx) -> None:
    judge(cells_with(ctx))


def judge_dir(ctx, want: Path) -> None:
    q5(probe_dir(ctx), want)


if __name__ == "__main__":
    try:
        sys.exit(main())
    finally:
        if os.environ.get("FT_KEEP_TMP") != "1":
            shutil.rmtree(TMP, ignore_errors=True)
