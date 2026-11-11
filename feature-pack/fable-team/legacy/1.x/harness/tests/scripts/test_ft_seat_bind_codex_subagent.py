"""r1635 — codex 좌석 결속(`bind_codex`)이 서브에이전트 rollout 을 후보에서 뺀다.

가짜 HOME 의 rollout jsonl + 주입한 ps·lsof(실 프로세스·tmux 0) · 사례 ⓐ본1+서브4 ⓑ본2 ⓒ서브만 ⓓ못 읽는 첫 줄 ⓔ부모 불일치 ⓘ배열 부모 ⓖ사본 4곳 · 손자 사슬은 이어 봄.
"""

import importlib.util
import json
import time
from pathlib import Path

import pytest

HARNESS = Path(__file__).resolve().parents[2]
COPIES = ("bin/ft_seat_bind.py", "kit/fable-team/bin/ft_seat_bind.py", "comm/ft_seat_bind.py", "kit/zombie-clean/ft_seat_bind.py")
IDENT = "t-codex#1:@1.%1"
MAIN = "01a1bdbf-0000-7000-8000-000000000001"
SUB = "01a0e17d-0000-7000-8000-00000000{:04d}"
OTHER = "01a1cccc-0000-7000-8000-000000000009"


def _load():
    spec = importlib.util.spec_from_file_location("ft_seat_bind_r1635", HARNESS / "bin/ft_seat_bind.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class World:
    def __init__(self, tmp_path: Path):
        self.home = tmp_path / "home"
        self.dir = self.home / ".codex/sessions/2026/11/11"
        self.dir.mkdir(parents=True)
        self.files: list[Path] = []

    def rollout(self, uuid: str, thread_source: str = "user", parent: object = None, raw: str | None = None) -> Path:
        head = raw if raw is not None else json.dumps({"type": "session_meta", "payload": {
            "id": uuid, "cwd": "/tmp/w", "thread_source": thread_source,
            **({"parent_thread_id": parent} if parent else {})}})
        p = self.dir / f"rollout-2026-11-11-{len(self.files)}-{uuid}.jsonl"
        p.write_text(head + "\n", encoding="utf-8")
        self.files.append(p)
        return p

    def bind(self, monkeypatch: pytest.MonkeyPatch, mod) -> dict:
        lstart = time.strftime("%a %b %d %H:%M:%S %Y", time.localtime(min(f.stat().st_mtime for f in self.files) - 60))
        comm = {"100": "/bin/zsh", "101": "/x/bin/codex"}
        opened = "".join(f"n{f}\n" for f in self.files)

        def fake_sh(*a):
            if a[0] == "ps":
                return (0, comm.get(a[-1], "")) if a[2] == "comm=" else (0, lstart)
            if a[0] == "lsof":
                return 0, opened if a[-1] == "101" else ""
            raise AssertionError(f"예상 밖 외부 조회: {a}")

        monkeypatch.setattr(mod, "sh", fake_sh)
        monkeypatch.setattr(mod, "candidates", lambda pid: {"100": ["100", "101"], "101": ["101"]}.get(pid, []))
        return mod.bind_codex("100", IDENT, str(self.home))


def test_a_main_plus_four_subagents_binds_main(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    mod, w = _load(), World(tmp_path)
    main = w.rollout(MAIN)
    [w.rollout(SUB.format(i), "subagent", MAIN) for i in range(4)]
    r = w.bind(monkeypatch, mod)
    assert r["rc"] == 0, r
    assert (r["uuid"], r["jsonl"], r["binding"]["source"]) == (MAIN, str(main), "codex-open-fd")


def test_b_two_main_rollouts_bind_nothing(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    mod, w = _load(), World(tmp_path)
    w.rollout(MAIN)
    w.rollout(OTHER)
    w.rollout(SUB.format(1), "subagent", MAIN)
    r = w.bind(monkeypatch, mod)
    assert (r["rc"], r["reason"]) == (1, "codex rollout 2개")


def test_c_subagent_only_binds_nothing(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    mod, w = _load(), World(tmp_path)
    for i in range(3):
        w.rollout(SUB.format(i), "subagent", MAIN)
    r = w.bind(monkeypatch, mod)
    assert (r["rc"], r["reason"]) == (1, "codex rollout 0개")


def test_d_unreadable_first_line_is_not_dropped(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    mod, w = _load(), World(tmp_path)
    w.rollout(MAIN)
    w.rollout(OTHER, raw="{깨진 첫 줄")
    r = w.bind(monkeypatch, mod)
    assert (r["rc"], r["reason"]) == (1, "codex rollout 2개")


def test_e_subagent_with_other_parent_binds_nothing(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    mod, w = _load(), World(tmp_path)
    w.rollout(MAIN)
    w.rollout(SUB.format(1), "subagent", OTHER)
    r = w.bind(monkeypatch, mod)
    assert (r["rc"], r["reason"]) == (1, "subagent 부모 불일치")


def test_h_grandchild_chain_reaches_main(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    # 깊이 2(손자) = 부모가 서브에이전트 id 여도 사슬이 남은 1개에 닿으면 같은 세션
    mod, w = _load(), World(tmp_path)
    main = w.rollout(MAIN)
    w.rollout(SUB.format(1), "subagent", MAIN)
    w.rollout(SUB.format(2), "subagent", SUB.format(1))
    r = w.bind(monkeypatch, mod)
    assert r["rc"] == 0 and r["jsonl"] == str(main), r


def test_i_array_parent_is_judged_not_traceback(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    # parent_thread_id 가 배열이면 traceback(TypeError unhashable) 대신 판정 1줄
    mod, w = _load(), World(tmp_path)
    w.rollout(MAIN)
    w.rollout(SUB.format(1), "subagent", [MAIN])
    r = w.bind(monkeypatch, mod)  # 보정 전엔 TypeError(unhashable) → 이 줄에서 FAIL
    assert (r["rc"], r["reason"]) == (1, "subagent 부모 불일치")


def test_j_array_subagent_id_is_judged_not_traceback(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    # id 가 배열이면 subs 키 해시(TypeError) 대신 판정 1줄
    mod, w = _load(), World(tmp_path)
    w.rollout(MAIN)
    w.rollout("sub", "subagent", OTHER, raw=json.dumps({"type": "session_meta", "payload": {
        "id": ["01a0"], "cwd": "/tmp/w", "thread_source": "subagent", "parent_thread_id": OTHER}}))
    r = w.bind(monkeypatch, mod)  # 보정 전엔 TypeError(unhashable) → 이 줄에서 FAIL
    assert (r["rc"], r["reason"]) == (1, "subagent 부모 불일치")


def test_g_bind_codex_body_identical_in_four_copies() -> None:
    def body(rel: str) -> str:
        text = (HARNESS / rel).read_text(encoding="utf-8")
        return text[text.index("def rollout_meta"):text.index("def lstart_epoch")]  # 사본마다 같은 본문

    assert len({body(c) for c in COPIES}) == 1
