"""r706 H3 — 뉴스 fetch «5분 안이면 건너뛰기» 표식 = 전용 파일(fetch 성공 때만 씀) · git FETCH_HEAD 를 숫자로 읽지 않는다.

옛 판: FETCH_HEAD(«<sha>\\t\\tbranch 'main' of …») 를 float() → 늘 ValueError → 매분 fetch(10-22 뉴스 로그 487줄 중 351줄 시간 초과).
fetch 대역 = 가짜 스크립트(진짜 git 처럼 FETCH_HEAD 를 씀) · 시계 = 가짜 · 실제 원격·슬랙 0.
실행: python3 -m pytest tests/scripts/test_r706_news_fetch_stamp.py -q
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "harness" / "bin"))

import ft_news_ledger as nl  # noqa: E402
from real_state_guard import guard_begin_module  # noqa: E402,F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

T0 = 1_800_000_000.0


def _git(repo: Path, *a: str) -> str:
    return subprocess.run(["git", "-C", str(repo), "-c", "user.name=t", "-c", "user.email=t@t", *a],
                          check=True, capture_output=True, text=True).stdout.strip()


def _prep(tmp_path, monkeypatch, rc: int = 0):
    """임시 리포 + 가짜 fetch(부를 때마다 로그 1줄 · 진짜 git 처럼 FETCH_HEAD 를 씀 · rc) + 전용 표식 경로 + 가짜 시계."""
    repo = tmp_path / "ledger-repo"
    repo.mkdir()
    _git(repo, "init", "-q")
    (repo / "a.txt").write_text("x\n", encoding="utf-8")
    _git(repo, "add", ".")
    _git(repo, "commit", "-qm", "i")
    head = _git(repo, "rev-parse", "HEAD")
    log, script, stamp = tmp_path / "fetch.log", tmp_path / "fetch.sh", tmp_path / "state" / "fetch.stamp"
    script.write_text(f'#!/usr/bin/env bash\necho try >> "{log}"\n'
                      f'printf "%s\\t\\tbranch \'main\' of github.com:x/y\\n" {head} > "{repo}/.git/FETCH_HEAD"\nexit {rc}\n',
                      encoding="utf-8")
    for k, v in {"FT_LEDGER_FETCH": script, "FT_NEWS_FETCH_MIN": "300", "FT_NEWS_FETCH_STAMP": stamp}.items():
        monkeypatch.setenv(k, str(v))
    monkeypatch.delenv("FT_LEDGER_SYNC_ERROR", raising=False)
    clock = [T0]
    monkeypatch.setattr(nl.time, "time", lambda: clock[0])
    return repo, log, stamp, clock


def _tries(log: Path) -> int:
    return len(log.read_text(encoding="utf-8").split()) if log.exists() else 0


# ── ⓐ 1분 간격 3번 = fetch 1번(옛 판 = FETCH_HEAD float ValueError 를 pass → 3번) ──
def test_a_three_calls_a_minute_apart_fetch_once(tmp_path, monkeypatch):
    repo, log, _stamp, clock = _prep(tmp_path, monkeypatch)
    for _ in range(3):
        assert nl.fetch_if_stale(repo) == ""
        clock[0] += 60
    assert _tries(log) == 1


# ── ⓑ 표식 = fetch 성공 때만 · 5분 안 = fetch 0 · 5분 뒤 = 다시 ──
def test_b_stamp_written_only_on_success_and_skips_within_5min(tmp_path, monkeypatch):
    repo, log, stamp, clock = _prep(tmp_path, monkeypatch)
    assert nl.fetch_if_stale(repo) == ""
    assert float(stamp.read_text(encoding="utf-8").strip()) == T0  # 성공 시각
    clock[0] += 299
    nl.fetch_if_stale(repo)
    assert _tries(log) == 1  # 5분 안 = fetch 0
    clock[0] += 2
    nl.fetch_if_stale(repo)
    assert _tries(log) == 2  # 5분 지남 = 다시


def test_b_failed_fetch_does_not_advance_stamp(tmp_path, monkeypatch):
    repo, log, stamp, clock = _prep(tmp_path, monkeypatch, rc=1)
    stamp.parent.mkdir(parents=True)
    stamp.write_text(f"{T0 - 40 * 60:.0f}\n", encoding="utf-8")
    err = nl.fetch_if_stale(repo)
    assert _tries(log) == 2  # 재시도 1
    assert float(stamp.read_text(encoding="utf-8").strip()) == T0 - 40 * 60  # 실패 = 표식 그대로(낡은 ref 를 최신으로 보지 않음)
    assert err.startswith("원장 ref fetch 실패 — ") and "origin/main = 40분 전 받은 판" in err
    clock[0] += 60
    nl.fetch_if_stale(repo)
    assert _tries(log) == 4  # 실패 뒤엔 건너뛰기 0 — 다음 틱에 또 받는다


def test_b_missing_stamp_fetches_and_age_unknown_on_fail(tmp_path, monkeypatch):
    repo, log, stamp, _clock = _prep(tmp_path, monkeypatch, rc=1)
    err = nl.fetch_if_stale(repo)
    assert _tries(log) == 2 and not stamp.exists()
    assert "origin/main = 받은 시각 모름" in err


def test_b_broken_stamp_fetches_once_and_warns(tmp_path, monkeypatch, caplog):
    repo, log, stamp, _clock = _prep(tmp_path, monkeypatch)
    stamp.parent.mkdir(parents=True)
    stamp.write_text("x\n", encoding="utf-8")
    assert nl.fetch_if_stale(repo) == ""
    assert _tries(log) == 1
    assert any(r.levelname == "WARNING" and "fetch 표식 깨짐" in r.getMessage() for r in caplog.records)
    assert float(stamp.read_text(encoding="utf-8").strip()) == T0  # 성공 = 표식 복구


def test_b_future_stamp_is_not_fresh(tmp_path, monkeypatch):
    repo, log, stamp, _clock = _prep(tmp_path, monkeypatch)
    stamp.parent.mkdir(parents=True)
    stamp.write_text(f"{T0 + 3600:.0f}\n", encoding="utf-8")  # 시계 뒤틀림 — 영영 건너뛰기 0
    nl.fetch_if_stale(repo)
    assert _tries(log) == 1


def test_b_default_stamp_under_state_news_ledger(tmp_path, monkeypatch):
    monkeypatch.delenv("FT_NEWS_FETCH_STAMP", raising=False)
    monkeypatch.setenv("FT_ROOT", str(tmp_path))
    assert nl._fetch_stamp_file() == tmp_path / ".fable-team" / "state" / "news-ledger" / "fetch.stamp"
