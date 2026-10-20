"""r569 — 원장 ref fetch 상한(CLI 기동 고정비 3.5 + 7 = 10.5초 · 총 마감 70초) + 실패 경고에 «N분 전 받은 판».

fetch 대역 = 가짜 스크립트(정해진 초만큼 sleep 후 rc) · FETCH_HEAD mtime 조작 · 실제 원격·슬랙 0.
실행: python3 -m pytest tests/scripts/test_news_fetch_cap.py -q
"""
import os
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "harness" / "bin"))

import ft_news_ledger as nl  # noqa: E402
from real_state_guard import guard_begin_module  # noqa: E402,F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)


def _git(repo: Path, *a: str) -> str:
    return subprocess.run(["git", "-C", str(repo), "-c", "user.name=t", "-c", "user.email=t@t", *a],
                          check=True, capture_output=True, text=True).stdout.strip()


def _repo(tmp_path: Path) -> Path:
    repo = tmp_path / "ledger-repo"
    repo.mkdir()
    _git(repo, "init", "-q")
    (repo / "a.txt").write_text("x\n", encoding="utf-8")
    _git(repo, "add", ".")
    _git(repo, "commit", "-qm", "i")
    return repo


def _fake(tmp_path: Path, secs: float, rc: int = 0) -> tuple[Path, Path]:
    """fetch 대역 — 부를 때마다 로그 1줄 · secs 만큼 sleep 후 rc."""
    log = tmp_path / "fetch.log"
    script = tmp_path / "fetch.sh"
    script.write_text(f'#!/usr/bin/env bash\necho "try" >> "{log}"\nsleep {secs}\nexit {rc}\n', encoding="utf-8")
    return script, log


def _stamp(repo: Path) -> Path:
    common = subprocess.run(["git", "-C", str(repo), "rev-parse", "--path-format=absolute", "--git-common-dir"],
                            check=True, capture_output=True, text=True).stdout.strip()
    return Path(common) / "FETCH_HEAD"


def _prep(tmp_path, monkeypatch, secs: float, rc: int = 0) -> tuple[Path, Path]:
    repo = _repo(tmp_path)
    script, log = _fake(tmp_path, secs, rc)
    for k, v in {"FT_LEDGER_FETCH": script, "FT_NEWS_FETCH_MIN": "0"}.items():
        monkeypatch.setenv(k, str(v))
    monkeypatch.delenv("FT_LEDGER_SYNC_ERROR", raising=False)
    return repo, log


# ── ⓐ 8초 fetch = 지금 판(7초) 실패 · 고친 판(10.5초) 성공 ──
def test_a_8s_fetch_passes_under_cli_fixed_cost_cap(tmp_path, monkeypatch):
    repo, log = _prep(tmp_path, monkeypatch, 8)
    t0 = time.monotonic()
    err = nl.fetch_if_stale(repo)
    elapsed = time.monotonic() - t0
    assert err == ""  # 성공 = 머리 줄 경고 0
    assert len(log.read_text(encoding="utf-8").split()) == 1  # 첫 시도에 끝(재시도 0)
    assert elapsed >= 7.5  # 7초 룰만으로는 못 넘긴 시간


# ── ⓑ 11초 fetch × 2 = 둘 다 실패 · 시도당 10.5초 · 합 ≤ 22초 여유 · 경고에 «N분 전 받은 판» ──
def test_b_two_timeouts_bounded_and_warn_with_age(tmp_path, monkeypatch, caplog):
    repo, log = _prep(tmp_path, monkeypatch, 11)
    stamp = _stamp(repo)
    stamp.write_text("x\n", encoding="utf-8")
    old = time.time() - (40 * 60 + 5)
    os.utime(stamp, (old, old))
    t0 = time.monotonic()
    err = nl.fetch_if_stale(repo)
    elapsed = time.monotonic() - t0
    assert len(log.read_text(encoding="utf-8").split()) == 2  # 재시도 1
    assert elapsed <= 22.5  # 시도당 10.5 × 2 + 여유(옛 판 = 7 × 2 = 14 · 총 마감 70 안)
    assert err.startswith("원장 ref fetch 실패 — ") and "origin/main = 40분 전 받은 판" in err
    assert os.environ["FT_LEDGER_SYNC_ERROR"] == err  # 머리 줄과 로그가 같은 문구
    assert err in [r.message for r in caplog.records if r.levelname == "ERROR"]


# ── ⓒ FETCH_HEAD 없음 = «받은 시각 모름» ──
def test_c_missing_stamp_says_unknown_time(tmp_path, monkeypatch):
    repo, _log = _prep(tmp_path, monkeypatch, 0, rc=1)
    assert not _stamp(repo).exists()
    err = nl.fetch_if_stale(repo)
    assert "origin/main = 받은 시각 모름" in err


# ── ⓓ FETCH_HEAD 300초 안 = fetch 0(지금 동작) ──
def test_d_fresh_stamp_skips_fetch(tmp_path, monkeypatch):
    repo, log = _prep(tmp_path, monkeypatch, 0)
    monkeypatch.setenv("FT_NEWS_FETCH_MIN", "300")  # 기본값 = 300초 안이면 건너뜀
    stamp = _stamp(repo)
    stamp.write_text(f"{time.time():.0f}\n", encoding="utf-8")  # 지금 동작 = 파일 «내용» 이 시각(초)
    assert nl.fetch_if_stale(repo) == ""
    assert not log.exists()  # 부른 적 0


# ── 상한 계산 = env 로 크게 줘도 총 마감 70초에서 자른다 ──
def test_e_attempt_timeout_clamped_to_budget(monkeypatch):
    monkeypatch.setenv("FT_NEWS_FETCH_TIMEOUT", "55")
    assert nl._attempt_timeout(0.0) == 55.0  # 첫 시도 = 시도당 상한
    assert nl._attempt_timeout(67.0) == 3.0  # 둘째 시도 = 남은 마감만
    assert nl._attempt_timeout(70.0) <= 0  # 마감 소진 = 새 시도 0
