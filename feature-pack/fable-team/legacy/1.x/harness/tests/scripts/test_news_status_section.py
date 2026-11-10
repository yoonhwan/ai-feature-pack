"""R209 planner 뉴스 — 팀·세션 상태 + 해야 할 일 절 · 주기 발행 · 초안 · 신선도 경보 · 이중 방아쇠 (판정 1795·1430).

격리 임시 FT_ROOT(원장 git 저장소 + seats-planner.json + board 스냅샷 JSON) · 게시 도구·mbox 는 스텁 · 실 슬랙·launchctl 호출 0.
실행: python3 -m pytest tests/scripts/test_news_status_section.py -q
"""
import fcntl
import json
import logging
import os
import re
import shutil
import subprocess
from datetime import datetime
from pathlib import Path

import pytest
from test_ft_news_ledger import BIN, REAL, ROW_NEW, ROW_OLD, baseline, commit, env, git, news_files  # noqa: F401  (env = 같은 임시 저장소 픽스처)

import ft_news_ledger as nl
import ft_news_status as ns
import ft_news_watch as nw
from real_state_guard import guard_begin_module  # noqa: E402,F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

KIT = BIN.parent / "kit" / "fable-team" / "bin"  # 팩 배치(r509 · 옛 harness-install 꼴 0)
NOW = "2026-10-13 15:00"
WAIT_NO = "추정: byz-a-master-claude#2 에 마지막 발신 #11(14:00) · 기록상 이후 byz-a-master-claude#2 회신 없음"


def snap(root: Path, hhmmss: str = "145500", day: str = "2026-10-13", stall_min: int = 7, cards: int = 4) -> Path:
    d = root / ".fable-team" / "state" / "board" / day
    d.mkdir(parents=True, exist_ok=True)
    teams = [{"label": "alpha", "seats": {"byz-a-nano-x#0": {"working": True}, "byz-a-arch-claude#1": {"working": False, "wait": WAIT_NO}},
              "stalled": [[f"{stall_min}분", "byz-a-arch-claude#1", "14:07", WAIT_NO]],
              "progress": {f"c{i}": {"seats": [], "title": f"c{i} — 카드 {i} 제목"} for i in range(cards)},
              "queue": [{"idx": "q0", "title": "대기 카드 하나"}, {"idx": "q1", "title": "대기 카드 둘"}]},
             {"label": "beta", "seats": {}, "stalled": [], "progress": {}, "queue": []}]
    f = d / f"{hhmmss}-abc12345.json"
    f.write_text(json.dumps({"date": day, "teams": teams}, ensure_ascii=False), encoding="utf-8")
    return f


@pytest.fixture
def run(env, monkeypatch):  # noqa: F811
    """(repo, root, tmp, go) — go() = 뉴스 1회 실행 rc. 주기 1800 s."""
    repo, root, tmp = env
    monkeypatch.setenv("FT_NEWS_STATUS_INTERVAL", "1800")
    monkeypatch.delenv("FT_NEWS_MODE", raising=False)
    monkeypatch.delenv("FT_NEWS_STALE_MIN", raising=False)
    (root / ".fable-team" / "seats-planner.json").write_text('{"_master": "planner#9"}', encoding="utf-8")
    commit(repo, REAL)
    return repo, root, tmp, lambda: nl.main([])


def repo_head(repo: Path) -> str:
    return git(repo, "log", "-1", "--format=%H")


def posts(tmp: Path) -> int:
    f = tmp / "stub.log"
    return len(re.findall(r"^\S+NEWS-\S+\.md$", f.read_text(encoding="utf-8"), re.M)) if f.exists() else 0


def mboxes(tmp: Path) -> list[str]:
    f = tmp / "mbox.log"
    return f.read_text(encoding="utf-8").splitlines() if f.exists() else []


def at(monkeypatch, stamp: str) -> None:
    monkeypatch.setenv("FT_NEWS_NOW", stamp)


def test_a_snapshot_to_section_shape(env, monkeypatch):  # noqa: F811
    _, root, _ = env
    monkeypatch.setenv("FT_NEWS_STATUS_INTERVAL", "1800")
    snap(root)
    (title, lines), digest = ns.status_block(root, datetime(2026, 10, 13, 15, 0))
    assert title == ns.TITLE and len(lines) == 2 and len(digest) == 40
    assert lines[0].startswith("• alpha — 일함 1 · 정지 arch(a-arch-claude#1): 7분 · 기다리는 것 = master(a-master-claude#2) 회신")
    assert lines[0].count(" · ") >= 4 and "c0" not in lines[0] and "카드 0 제목 · 카드 1 제목 · 카드 2 제목 · 다음 대기: 대기 카드 하나" in lines[0]  # 진행 ≤3 + 큐 1
    assert "카드 3 제목" not in lines[0]
    assert lines[1] == "• beta — 일함 0 · 정지 없음 / 해야 할 일: 진행 카드 없음 · 다음 대기: 없음"


def test_b_same_digest_posts_zero_different_posts_one(run, monkeypatch):
    repo, root, tmp, go = run
    at(monkeypatch, NOW)
    snap(root)
    assert go() == 0 and posts(tmp) == 0  # 첫 실행 = 기준선만
    assert go() == 0 and posts(tmp) == 1  # 원장 새 커밋 0 · 절만 1판
    assert go() == 0 and posts(tmp) == 1  # 같은 분 재실행 = 0
    snap(root, "150500", stall_min=40)
    at(monkeypatch, "2026-10-13 15:40")
    assert go() == 0 and posts(tmp) == 1  # 정지 «분»만 달라진 것은 바뀐 것이 아니다
    snap(root, "153900", cards=2)
    at(monkeypatch, "2026-10-13 15:41")
    assert go() == 0 and posts(tmp) == 2  # 카드 목록이 바뀜 + 주기 지남


def test_b2_interval_not_elapsed_posts_zero(run, monkeypatch):
    _, root, tmp, go = run
    at(monkeypatch, NOW)
    snap(root)
    go(), go()
    snap(root, "150100", cards=2)
    at(monkeypatch, "2026-10-13 15:10")  # 10분 < 1800 s
    assert go() == 0 and posts(tmp) == 1


def test_c_ledger_commit_appends_section(run, monkeypatch):
    repo, root, tmp, go = run
    at(monkeypatch, NOW)
    snap(root)
    go()
    commit(repo, REAL.replace(ROW_OLD, ROW_NEW))
    assert go() == 0 and posts(tmp) == 1
    body = (tmp / "stub.log").read_text(encoding="utf-8")
    assert "바뀐 것" in body and ns.TITLE in body and "• alpha — 일함 1" in body
    assert (root / ".fable-team" / "state" / "news-ledger" / "status.sha").exists()


def test_d_draft_mode_writes_file_only(run, monkeypatch):
    _, root, tmp, go = run
    monkeypatch.setenv("FT_NEWS_MODE", "draft")
    at(monkeypatch, NOW)
    snap(root)
    go()
    assert go() == 0 and posts(tmp) == 0 and len(news_files(root)) == 1


def test_e_stale_snapshot_line_and_error(env, caplog, monkeypatch):  # noqa: F811
    _, root, _ = env
    monkeypatch.setenv("FT_NEWS_STATUS_INTERVAL", "1800")
    snap(root, "135900")
    with caplog.at_level(logging.ERROR, logger="ft_news_ledger"):
        (_, lines), _d = ns.status_block(root, datetime(2026, 10, 13, 15, 0))
    assert lines[0] == "(세션 상태 스냅샷 13:59 · 갱신 안 됨)"
    assert any("오래됐다" in r.message for r in caplog.records)


def test_f_no_snapshot_raises_and_status_only_run_fails(run, monkeypatch):
    _, root, tmp, go = run
    with pytest.raises(RuntimeError, match="스냅샷 0장"):
        ns.status_block(root, datetime(2026, 10, 13, 15, 0))
    at(monkeypatch, NOW)
    go()
    assert go() == 1 and posts(tmp) == 0  # 대체 0 — 조용히 빈 절을 올리지 않는다


def test_g_lock_held_skips_run(run, monkeypatch):
    _, root, tmp, go = run
    at(monkeypatch, NOW)
    snap(root)
    go()
    state = root / ".fable-team" / "state" / "news-ledger"
    with open(state / ".lock", "w", encoding="utf-8") as f:
        fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
        assert go() == 0 and posts(tmp) == 0  # 다른 방아쇠가 일하는 중
    assert go() == 0 and posts(tmp) == 1


def _published(root: Path, stamp: str) -> Path:
    f = root / ".fable-team" / "state" / "news-publish" / "2026-10-13" / "published.txt"
    f.parent.mkdir(parents=True, exist_ok=True)
    f.write_text("x", encoding="utf-8")
    t = datetime.strptime(stamp, "%Y-%m-%d %H:%M").timestamp()
    os.utime(f, (t, t))
    return f


def test_h_stale_alert_once_then_rearms(run, monkeypatch):
    _, root, tmp, go = run
    at(monkeypatch, NOW)
    snap(root)
    _published(root, "2026-10-13 11:00")  # 240분 전
    go(), go()
    sent = [m for m in mboxes(tmp) if "뉴스 정지" in m]
    assert len(sent) == 1 and "240분" in sent[0] and "마지막 11:00" in sent[0] and "planner#9" in sent[0]
    go()
    assert len([m for m in mboxes(tmp) if "뉴스 정지" in m]) == 1  # 정지 1건당 1통
    _published(root, "2026-10-13 14:30")  # 발행됨 → 재무장
    go()
    assert not (root / ".fable-team" / "state" / "news-ledger" / "stale.notified").exists()
    _published(root, "2026-10-13 09:00")
    go()
    assert len([m for m in mboxes(tmp) if "뉴스 정지" in m]) == 2


def test_i_no_external_calls(run, monkeypatch):
    _, root, tmp, go = run
    calls: list[str] = []
    real = subprocess.run

    def spy(cmd, *a, **k):
        calls.append(" ".join(map(str, cmd)))
        return real(cmd, *a, **k)

    monkeypatch.setattr(nl.subprocess, "run", spy)
    monkeypatch.setattr(nw.subprocess, "run", spy)
    at(monkeypatch, NOW)
    snap(root)
    go(), go()
    assert calls and not [c for c in calls if "launchctl" in c or "byz_thread_post" in c]
    assert all(c.startswith(("git ", "bash ")) for c in calls)  # git · 스텁 게시 도구 · 스텁 mbox 뿐


# ── DA⑥ r209 교정 ────────────────────────────────────────────────
def test_h2_draft_does_not_consume_publish_baseline(run, monkeypatch):
    repo, root, tmp, go = run
    at(monkeypatch, NOW)
    snap(root)
    go()
    commit(repo, REAL.replace(ROW_OLD, ROW_NEW))
    monkeypatch.setenv("FT_NEWS_MODE", "draft")
    assert go() == 0 and posts(tmp) == 0 and len(news_files(root)) == 1
    assert baseline(root) != repo_head(repo)  # 초안은 게시 기준선을 옮기지 않는다
    monkeypatch.setenv("FT_NEWS_MODE", "auto")
    assert go() == 0 and posts(tmp) == 1 and baseline(root) == repo_head(repo)  # draft → auto 게시 1


def test_h2_new_commit_without_snapshot_publishes_nothing(run, monkeypatch):
    repo, root, tmp, go = run
    at(monkeypatch, NOW)
    snap(root)
    go()
    before = baseline(root)
    commit(repo, REAL.replace(ROW_OLD, ROW_NEW))
    shutil.rmtree(root / ".fable-team" / "state" / "board")
    assert go() == 1 and posts(tmp) == 0 and baseline(root) == before  # 절 없는 판 게시 0 · 기준선 그대로
    snap(root)
    assert go() == 0 and posts(tmp) == 1  # 스냅샷이 생기면 같은 차이를 다시 낸다


def test_h3_new_publish_between_observations_rearms(run, monkeypatch):
    _, root, tmp, go = run
    at(monkeypatch, NOW)
    snap(root)
    _published(root, "2026-10-13 11:00")
    go()
    assert len([m for m in mboxes(tmp) if "뉴스 정지" in m]) == 1
    _published(root, "2026-10-13 15:10")  # 관측 없이 새 발행
    at(monkeypatch, "2026-10-13 19:00")  # 다음 관측은 fresh 구간을 지난 뒤
    go()
    assert len([m for m in mboxes(tmp) if "뉴스 정지" in m]) == 2


def test_h1_stale_only_alerts_without_publishing(run, monkeypatch):
    _, root, tmp, go = run
    at(monkeypatch, NOW)
    snap(root)
    _published(root, "2026-10-13 11:00")
    assert nl.main(["stale"]) == 0 and nl.main(["stale"]) == 0
    assert len([m for m in mboxes(tmp) if "뉴스 정지" in m]) == 1 and posts(tmp) == 0  # 게시 0 · 경보 1


def test_h1_tick_calls_stale_watch_when_ledger_off():
    src = (BIN / "ft-tick.sh").read_text(encoding="utf-8")
    assert 'ft_news_ledger.py" stale' in src and "FT_TICK_NEWS_WATCH" in src
    assert (KIT / "ft-tick.sh").read_bytes() == (BIN / "ft-tick.sh").read_bytes()
