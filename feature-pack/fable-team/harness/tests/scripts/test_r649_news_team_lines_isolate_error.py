"""r649 — 뉴스·매거진 «팀 상태» 절: 보드 수집이 error 로 격리한 팀(`ft_board_collect.team_or_error` = `{key,label,error}`)을
뉴스 줄 만들기 `ft_news_status._lines` 가 몰라 `t['seats']` KeyError → 절 전체가 «원천 없음: 'seats'» 한 줄로 바뀌던 결함
(2026-10-21 14:11·16:09 두 번) + 쪽지함 조회 `ft_board_env.inbox` 의 60초 상한(하드 룰 12 = 7초 + 재시도 1).

ⓐ 스냅샷 팀 3개 중 1개 error → 정상 팀 2줄 그대로 + error 팀 «못 읽음: <사유>» 1줄(전 판 = «원천 없음: 'seats'»)
ⓑ `status_block` 같은 결과(예외 0) · digest 에 못 읽음 팀 포함
ⓒ 모든 팀 error → 팀마다 «못 읽음» 줄(절 통째 교체 0)
ⓓ 스냅샷 자체가 깨짐·없음 → 지금처럼 «원천 없음» 1줄(이건 그대로)
ⓔ 가짜 ft-inbox 가 sleep 20 → `inbox()` 7초 상한 + 재시도 1 → 그 팀만 error · 수집 시간이 팀 수와 무관한 상한 안
ⓕ 가짜 ft-inbox rc≠0 → 그 팀만 error(정상 팀 불변)

격리 임시 FT_ROOT · 가짜 tmux/gh/인박스/판정 원장 — 실 좌석·실 우편함·실 외부 호출 0.
실행: cd harness && PYTHONPATH=bin:kit/fable-team/bin python3.11 -m pytest tests/scripts/test_r649_news_team_lines_isolate_error.py -q
"""
import json
import os
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

import pytest

import ft_board_env as be
import ft_news_html as nh
import ft_news_status as ns

BIN = Path(__file__).resolve().parents[3] / "harness" / "bin"
DAY, HHMMSS = "2026-10-13", "145500"
NOW = datetime(2026, 10, 13, 15, 0)
SLOW = "ft-inbox.sh show 시간 초과"


def _team(label: str, working: int = 0) -> dict:
    seats = {f"byz-a-nano-x{i}#0": {"working": True} for i in range(working)}
    return {"label": label, "seats": seats, "stalled": [], "progress": {}, "queue": []}


def _err(label: str, why: str = SLOW) -> dict:
    return {"key": label, "label": label, "error": why}


def snap(root: Path, teams: list, raw: str | None = None) -> Path:
    d = root / ".fable-team" / "state" / "board" / DAY
    d.mkdir(parents=True, exist_ok=True)
    f = d / f"{HHMMSS}-abc12345.json"
    f.write_text(raw if raw is not None else json.dumps({"date": DAY, "teams": teams}, ensure_ascii=False), encoding="utf-8")
    return f


@pytest.fixture
def root(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    r = tmp_path / "root"
    (r / ".fable-team").mkdir(parents=True)
    monkeypatch.setenv("FT_ROOT", str(r))
    monkeypatch.setenv("FT_NEWS_STATUS_INTERVAL", "1800")
    return r


# ── ⓐ ──
def test_error_team_keeps_other_team_lines_and_shows_reason(root: Path) -> None:
    """ⓐ 정상 팀 2줄은 글자 그대로 · error 팀은 «못 읽음: <사유>» 1줄 — 절 전체 교체(«원천 없음») 0."""
    snap(root, [_team("정상하나", 1), _team("정상둘"), _err("못읽팀")])
    lines = nh.teams(root)
    assert isinstance(lines, list), f"절 통째 교체됨: {lines!r}"
    assert lines[0] == "(스냅샷 10-13 14:55)", lines
    assert lines[1].startswith("• 정상하나 — 일함 1 · 정지 없음"), lines
    assert lines[2].startswith("• 정상둘 — 일함 0 · 정지 없음"), lines
    assert lines[3] == f"• 못읽팀 — 못 읽음: {SLOW}", lines


def test_error_line_truncates_reason_to_80_chars(root: Path) -> None:
    """사유가 길어도 한 줄 80자까지만 — 뉴스 줄이 사유문에 먹히지 않게."""
    long_why = "쪽지함 조회 실패 " + "가" * 200
    snap(root, [_team("정상"), _err("못읽팀", long_why)])
    line = nh.teams(root)[-1]
    assert line == "• 못읽팀 — 못 읽음: " + long_why[:80], line


# ── ⓑ ──
def test_status_block_same_result_and_digest_includes_error_team(root: Path) -> None:
    """ⓑ status_block 도 예외 0 · 같은 «못 읽음» 줄 · digest 는 그 팀 사유에 반응한다."""
    snap(root, [_team("정상하나", 1), _err("못읽팀")])
    block, digest = ns.status_block(root, NOW)
    assert block[0] == ns.TITLE
    assert [ln for ln in block[1] if "못 읽음" in ln] == [f"• 못읽팀 — 못 읽음: {SLOW}"], block
    snap(root, [_team("정상하나", 1), _err("못읽팀", "다른 사유")])
    _, digest2 = ns.status_block(root, NOW)
    assert digest != digest2


# ── ⓒ ──
def test_all_teams_error_get_their_own_lines(root: Path) -> None:
    """ⓒ 전 팀 error — 팀마다 «못 읽음» 줄(절 통째 교체 0)."""
    snap(root, [_err("팀가", "사유가"), _err("팀나", "사유나")])
    lines = nh.teams(root)
    assert isinstance(lines, list), f"절 통째 교체됨: {lines!r}"
    assert [ln for ln in lines if "못 읽음" in ln] == ["• 팀가 — 못 읽음: 사유가", "• 팀나 — 못 읽음: 사유나"], lines


# ── ⓓ ──
def test_broken_or_missing_snapshot_still_one_source_line(root: Path) -> None:
    """ⓓ 스냅샷 자체가 깨짐·없음 = 지금처럼 «원천 없음» 1줄(숨기지 않는다) · status_block 은 raise."""
    snap(root, [], raw="{ 깨짐")
    assert nh.teams(root).startswith("원천 없음: ")
    with pytest.raises(RuntimeError):
        ns.status_block(root, NOW)
    for f in (root / ".fable-team" / "state" / "board").rglob("*"):
        if f.is_file():
            f.unlink()
    assert nh.teams(root).startswith("원천 없음: ")
    with pytest.raises(RuntimeError):
        ns.status_block(root, NOW)


# ── ⓔ·ⓕ = 수집 경로(ft-board.py collect) ──
def _board(tmp_path: Path, mode: str) -> dict:
    """임시 공용 루트(git 리포) + 명부 2팀(정상·느림/실패) + 가짜 인박스. tmux 살아 있는 세션 0 = 좌석 칸 없이 팀·카드만."""
    root = tmp_path / "broot"
    fb = root / ".fable-team"
    for d in (fb / "comm", fb / "state", root / "t" / "ok" / "진행", root / "t" / "slow" / "진행"):
        d.mkdir(parents=True, exist_ok=True)
    git = ["git", "-C", str(root)]
    subprocess.run([*git, "init", "-q"], check=True)
    subprocess.run([*git, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "base"], check=True)
    (fb / "state" / "verdicts.jsonl").write_text("", encoding="utf-8")
    (root / "t" / "ok" / "진행" / "c-ok.md").write_text("# 인덱스: ok 카드\n본문\n", encoding="utf-8")
    (root / "t" / "slow" / "진행" / "c-slow.md").write_text("# 인덱스: slow 카드\n본문\n", encoding="utf-8")
    for key, label, cards in (("ok", "정상팀", "t/ok"), ("slow", "느린팀", "t/slow")):
        (fb / f"seats-{key}.json").write_text(json.dumps(
            {"_label": label, "_master": f"{key}-m#1", "_cards": cards, f"{key}-m#1": {"role": "master"}}, ensure_ascii=False), encoding="utf-8")
    (tmp_path / "gh.json").write_text("[]", encoding="utf-8")
    (tmp_path / "tmux.sh").write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    calls = tmp_path / "inbox.calls"
    slow_body = 'echo call >> "%s"\nsleep 20\necho EMPTY\n' % calls if mode == "slow" else 'echo call >> "%s"\nexit 1\n' % calls
    script = tmp_path / "inbox.sh"
    script.write_text(f'#!/bin/sh\ncase "$1" in slow-m#1) {slow_body} ;; esac\necho EMPTY\n', encoding="utf-8")
    env = {**os.environ, "FT_ROOT": str(root), "FT_BOARD_NOW": NOW.isoformat(), "FT_BOARD_GH_TTL": "0",
           "FT_VERDICT_BIN": str(BIN / "ft-verdict.sh"), "FT_BOARD_TMUX": f"bash {tmp_path / 'tmux.sh'}",
           "FT_BOARD_INBOX": f"bash {script}"}
    env.pop("GIT_DIR", None)
    return {"root": root, "env": env, "calls": calls}


def _collect(b: dict) -> tuple[subprocess.CompletedProcess, float]:
    t0 = time.monotonic()
    r = subprocess.run([sys.executable, str(BIN / "ft-board.py"), "collect"], capture_output=True, text=True, env=b["env"], timeout=120)
    return r, time.monotonic() - t0


def _team_of(d: dict, key: str) -> dict:
    return next(t for t in d["teams"] if t["key"] == key)


def test_slow_inbox_is_bounded_and_only_that_team_errors(tmp_path: Path) -> None:
    """ⓔ 20초 느린 쪽지함 = 7초 상한 + 재시도 1(2회 호출) → 그 팀만 error · 정상 팀 숫자 그대로 · 수집 전체 < 20초."""
    b = _board(tmp_path, "slow")
    r, elapsed = _collect(b)
    assert r.returncode == 0, r.stderr
    d = json.loads(r.stdout)
    assert _team_of(d, "ok")["counts"]["진행"] == 1
    slow = _team_of(d, "slow")
    assert "ft-inbox.sh show 실패" in slow["error"], slow
    assert slow["error"].startswith("ft-inbox.sh show 실패(7초 상한") or "7초 상한" in slow["error"], slow
    assert elapsed < 20, f"쪽지함 하나가 수집을 {elapsed:.1f}s 붙잡았다"
    assert b["calls"].read_text(encoding="utf-8").count("call") == 2, "재시도 1회 = 호출 2회"


def test_inbox_rc_nonzero_marks_only_that_team(tmp_path: Path) -> None:
    """ⓕ 가짜 ft-inbox rc≠0 → 그 팀만 error(정상 팀 불변) · 재시도 1회 = 호출 2회."""
    b = _board(tmp_path, "fail")
    r, _elapsed = _collect(b)
    assert r.returncode == 0, r.stderr
    d = json.loads(r.stdout)
    slow = _team_of(d, "slow")
    assert "ft-inbox.sh show" in slow["error"] and "rc=1" in slow["error"], slow
    assert _team_of(d, "ok")["counts"]["진행"] == 1
    assert b["calls"].read_text(encoding="utf-8").count("call") == 2


def test_inbox_default_timeout_is_seven_seconds() -> None:
    """기본 상한이 60초가 아니라 7초(하드 룰 12) · 재시도 1 — 소스 상수로 고정한다."""
    assert be.INBOX_TIMEOUT_S == 7
    assert be.INBOX_RETRIES == 1
