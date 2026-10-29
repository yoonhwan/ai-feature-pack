"""r1086 — 좌석 jsonl 찾기 ① 짚기(claude argv --session-id) + ② 지금 길 + 매거진 env 2줄 (ⓐ~ⓗ).

픽스처 = 임시 projects 폴더 + 가짜 ps·tmux(호출 기록) + 가짜 검증기 · 실 tmux·실 ~/.claude 조회 0 · 자기 재호출 0.
실행: python3 -m pytest tests/scripts/test_locate_env_r1086.py -q
"""
import os
import plistlib
import re
import subprocess
import sys
import time
from pathlib import Path

import pytest

PACK = Path(__file__).resolve().parents[3]
BIN = PACK / "harness" / "bin"
KITBIN = PACK / "harness" / "kit" / "fable-team" / "bin"
SLACK = PACK / "harness" / "kit" / "slack-mirror"
sys.path[:0] = [str(BIN)]

import ft_api_outage_util as ut  # noqa: E402

CWD_A = "/tmp/r1086/wt-a"
U1 = "11111111-2222-3333-4444-555555555555"  # 파일이 있는 세션 id
U9 = "99999999-8888-7777-6666-555555555555"  # argv 에는 있는데 파일이 없는 세션 id
TMUX = """#!/usr/bin/env bash
echo "$*" >> "$TMUX_LOG"
case "$1" in
  list-panes) cat "$PANE_FILE" ;;
  list-sessions) cat "$PID_FILE" ;;
  *) exit 1 ;;
esac
"""
PS = """#!/usr/bin/env bash
echo "$*" >> "$PS_LOG"
[ "$PS_MODE" = fail ] && exit 1
cat "$PS_FILE"
"""


def enc(cwd: str) -> str:
    return re.sub(r"[^A-Za-z0-9]", "-", cwd)


class World:
    """좌석 몇 개 + projects 폴더 + 가짜 ps·tmux. seat() 로 실행 트리를, file() 로 jsonl 을 만든다."""

    def __init__(self, tmp: Path):
        self.tmp = tmp
        self.fake = tmp / "fake"
        self.fake.mkdir()
        self.dir = tmp / "projects" / enc(CWD_A)
        self.dir.mkdir(parents=True)
        self.projects = tmp / "projects"
        self.panes: list[str] = []
        self.pids: list[str] = []
        self.psrows: list[tuple[int, int, str]] = []
        for name, body in (("tmux", TMUX), ("ps", PS)):
            p = self.fake / name
            p.write_text(body, encoding="utf-8")
            p.chmod(0o755)

    def seat(self, name: str, pid: int, claude: str | None = None) -> "World":
        """pane(name → cwd) + 실행 트리: pid( pane ) → pid+1(셸) → claude(argv 꼬리 = claude). None = claude 없음(pi 좌석)."""
        self.panes.append(f"{name}\t{CWD_A}")
        self.pids.append(f"{name}\t{pid}")
        self.psrows.append((pid + 1, pid, "/bin/zsh"))
        if claude is not None:
            self.psrows.append((pid + 2, pid + 1, "/Users/t/bin/claude " + claude))
        return self

    def file(self, name: str, agent: str = "") -> Path:
        """jsonl 1개 — agent 를 주면 머리에 이름표(r497 지금 길이 읽는 바늘)."""
        p = self.dir / name
        p.write_text((f'{{"type":"agent-name","agentName":"{agent}"}}\n' if agent else '{"type":"user"}\n'), encoding="utf-8")
        return p

    def decoys(self, n: int) -> None:
        for i in range(n):
            self.file(f"decoy-{i:03d}.jsonl")

    def flush(self) -> None:
        (self.tmp / "panes").write_text("\n".join(self.panes) + "\n", encoding="utf-8")
        (self.tmp / "pids").write_text("\n".join(self.pids) + "\n", encoding="utf-8")
        (self.tmp / "psrows").write_text("".join(f"{p} {pp} {c}\n" for p, pp, c in self.psrows), encoding="utf-8")

    def find(self, seats: list[str], deadline: float | None = None) -> dict[str, str]:
        self.flush()
        panes = [tuple(x.split("\t", 1)) for x in self.panes]  # type: ignore[misc]
        return ut.find_jsonls(list(seats), "tmux", self.projects, panes=panes, deadline=deadline)


def _old_find(seats: list[str], panes: list[tuple[str, str]], projects: Path, days: int = 2) -> dict[str, str]:
    """r1086 이전의 find_jsonls — «② 지금 길» 만(ps 실패 때 결과가 같은지 대조하는 기준)."""
    groups: dict[Path, list[str]] = {}
    for s, cwd in panes:
        if s in seats and not any(s in g for g in groups.values()):
            groups.setdefault(projects / enc(cwd), []).append(s)
    out: dict[str, str] = {}
    for d, group in groups.items():
        try:
            files = sorted(((p.stat().st_mtime, p) for p in d.glob("*.jsonl")), reverse=True)
        except OSError:
            continue
        for _, p in (f for f in files if time.time() - f[0] < days * 86400):
            if not (left := [s for s in group if s not in out]):
                break
            try:
                with p.open("rb") as fh:
                    head = fh.read(1 << 20)
            except OSError:
                continue
            out.update({s: str(p) for s in left if f'"agentName":"{s}"'.encode() in head})
    return out


@pytest.fixture
def world(tmp_path, monkeypatch):
    w = World(tmp_path)
    log = tmp_path / "calls.log"
    monkeypatch.setenv("PATH", f"{w.fake}{os.pathsep}{os.environ['PATH']}")
    monkeypatch.setenv("TMUX_LOG", str(log))
    monkeypatch.setenv("PS_LOG", str(log))
    monkeypatch.setenv("PANE_FILE", str(w.tmp / "panes"))
    monkeypatch.setenv("PID_FILE", str(w.tmp / "pids"))
    monkeypatch.setenv("PS_FILE", str(w.tmp / "psrows"))
    monkeypatch.setenv("PS_MODE", "ok")
    return w


@pytest.fixture
def opened(monkeypatch):
    """jsonl «머리 읽기» 계수 — ① 짚기로 찾은 좌석은 다른 파일을 열지 않아야 한다(계약 ①·②)."""
    seen: list[str] = []
    real = Path.open

    def spy(self, mode="r", *a, **k):
        if "b" in mode and str(self).endswith(".jsonl"):  # 쓰기(write_text)는 세지 않는다 — 머리 읽기만
            seen.append(str(self))
        return real(self, mode, *a, **k)

    monkeypatch.setattr(Path, "open", spy)
    return seen


# ── ⓐ ① 짚기 (R1) — 미끼 200개 열기 0 ──────────────────────────────────────
def test_a_pins_by_session_id_without_reading_files(world, opened):
    pinned = world.file(f"{U1}.jsonl")
    world.seat("seat-a", 500, f"--session-id {U1} --model claude-sonnet-5-5").decoys(200)
    assert world.find(["seat-a"]) == {"seat-a": str(pinned)}
    assert opened == []


# ── ⓑ claude 아님 = ② 에서 뺀다 (R2) — pi 나노 ─────────────────────────────
def test_b_non_claude_seat_is_not_searched(world, opened):
    world.seat("seat-pi", 600).file("2026-10-28-pi.jsonl", agent="seat-pi")
    world.file("other.jsonl", agent="seat-other")
    assert world.find(["seat-pi"]) == {}
    assert opened == []


# ── ⓒ ② 지금 길 (R3 · R4) ──────────────────────────────────────────────────
def test_c_claude_without_session_id_falls_back_to_head_read(world, opened):
    no_flag = world.file("r3.jsonl", agent="seat-c")
    world.seat("seat-c", 700, "--model claude-sonnet-5-5")
    assert world.find(["seat-c"]) == {"seat-c": str(no_flag)}
    assert opened == [str(no_flag)]


def test_c_missing_session_file_falls_back_to_head_read(world, opened):
    world.seat("seat-d", 800, f"--session-id {U9}")  # argv 는 있는데 U9.jsonl 이 없다
    by_name = world.file("r4.jsonl", agent="seat-d")
    assert world.find(["seat-d"]) == {"seat-d": str(by_name)}


# ── ⓓ ps 실패 = 지금 길과 같은 결과 (R5) ───────────────────────────────────
def test_d_ps_failure_returns_the_same_as_the_old_path(world, monkeypatch, opened):
    world.file(f"{U1}.jsonl")
    world.seat("seat-a", 500, f"--session-id {U1}")
    found = world.file("named.jsonl", agent="seat-named")
    world.seat("seat-named", 900, "--model claude-sonnet-5-5")
    world.seat("seat-none", 950, "--model claude-sonnet-5-5")
    monkeypatch.setenv("PS_MODE", "fail")
    got = world.find(["seat-a", "seat-named", "seat-none"])
    panes = [tuple(x.split("\t", 1)) for x in world.panes]  # type: ignore[misc]
    assert got == _old_find(["seat-a", "seat-named", "seat-none"], panes, world.projects)
    assert got == {"seat-named": str(found)}


# ── ⓔ 마감이 지나면 머리 읽기 0 (R6) ───────────────────────────────────────
def test_e_deadline_stops_the_head_read(world, opened):
    world.seat("seat-c", 700, "--model claude-sonnet-5-5")
    world.decoys(3)
    world.file("named.jsonl", agent="seat-c")
    assert world.find(["seat-c"], deadline=time.monotonic() - 1) == {}  # 마감 지난 읽기는 버린다 — 못 찾음 그대로
    assert opened == []


# ── ⓕ 검증기 모듈 경로 (R7) ────────────────────────────────────────────────
def _magazine_env(tmp: Path, pythonpath: str | None) -> dict[str, str]:
    root, repo, out, log = tmp / "root", tmp / "repo", tmp / "out", tmp / "verify.env"
    (root / ".fable-team").mkdir(parents=True)
    out.mkdir()
    (out / "a.html").write_text("<h1>매거진</h1>\n", encoding="utf-8")
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    rel = "design/teams/planner/PLAN-oppa-ledger.md"
    (repo / rel).parent.mkdir(parents=True)
    (repo / rel).write_text("# 원장\n", encoding="utf-8")
    for a in (["add", "-A"], ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "l"]):
        subprocess.run(["git", "-C", str(repo), *a], check=True)
    doc = tmp / "doc.py"
    doc.write_text(f'if __name__ == "__main__":\n    print("PUBLISH warn=0 html={out / "a.html"}")\n', encoding="utf-8")
    vbin = tmp / "ft-news-verify"
    vbin.write_text(f'#!/usr/bin/env bash\nprintf "%s" "$PYTHONPATH" > "{log}"\n', encoding="utf-8")
    vbin.chmod(0o755)
    env = {"PATH": os.environ["PATH"], "FT_ROOT": str(root), "FT_LEDGER_REPO": str(repo), "FT_LEDGER_PATH": rel,
           "FT_LEDGER_SYNCED": "1", "FT_LEDGER_FRESH_GATE": "0", "FT_MAGAZINE_REPUBLISH": "1",
           "FT_MAGAZINE_DOC": str(doc), "FT_NEWS_VERIFY_BIN": str(vbin)}
    if pythonpath is not None:
        env["PYTHONPATH"] = pythonpath
    return env | {"_LOG": str(log)}


def _run_magazine(env: dict[str, str]) -> str:
    log = Path(env.pop("_LOG"))
    r = subprocess.run(["bash", str(SLACK / "magazine_from_news.sh"), "--publish", "--out-dir", str(Path(env["FT_ROOT"]).parent / "out")],
                       env=env, capture_output=True, text=True, timeout=30)
    assert r.returncode == 0, r.stderr
    return log.read_text(encoding="utf-8")


def test_f_verifier_gets_the_script_folder_first(tmp_path):
    assert _run_magazine(_magazine_env(tmp_path, None)) == str(SLACK)
    assert _run_magazine(_magazine_env(tmp_path / "b", "/existing/dir")) == f"{SLACK}:/existing/dir"


# ── ⓖ plist 틀 — FT_HARNESS_ROOT 1개 ───────────────────────────────────────
def test_g_magazine_plist_template_has_harness_root(tmp_path):
    t = (SLACK / "com.byz.ft-magazine.plist.template").read_text(encoding="utf-8")
    for k, v in (("__PY__", "/usr/bin/python3"), ("__HOME__", str(tmp_path)), ("__BYZ_ROOT__", str(tmp_path / "root")),
                 ("__HARNESS_ROOT__", str(tmp_path / "harness-ops")), ("__REPO__", "r"), ("__CHANNEL__", "c")):
        t = t.replace(k, v)
    assert "__" not in re.sub(r"<!DOCTYPE[^>]*>", "", t).split("<dict>", 1)[0]  # 자리표시 잔여 없음(앞머리)
    env = plistlib.loads(t.encode("utf-8"))["EnvironmentVariables"]
    assert env["FT_HARNESS_ROOT"] == str(tmp_path / "harness-ops")
    assert t.count("<key>FT_HARNESS_ROOT</key>") == 1
    p = tmp_path / "com.byz.ft-magazine.plist"
    p.write_text(t, encoding="utf-8")
    r = subprocess.run(["plutil", "-lint", str(p)], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr


# ── ⓗ bin·kit 같은 내용 ────────────────────────────────────────────────────
def test_h_bin_and_kit_util_are_identical():
    assert (BIN / "ft_api_outage_util.py").read_bytes() == (KITBIN / "ft_api_outage_util.py").read_bytes()
