"""r907 — 원장 ref 받기 실패여도 직전 판이 나이 상한(FT_NEWS_STALE_OK_MIN · 기본 15분) 안이면 그 판으로 정상 게시 + 머리 «원장 N분 전 판» 경고.
나이 밖·모름(표식 없음·깨짐·미래 시각) = 지금처럼 «판정 불가» 구간당 1통. 받기 실패 틱 = ledger_fill(원장 표 커밋) 0.

fetch 대역 = 가짜 스크립트(sleep · 시간 초과) · fetch.stamp 시각 조작 · 가짜 Slack(test_ft_news_html 의 FakeSlack) · 실 원격·실 Slack 0.
실행: python3 -m pytest tests/scripts/test_r907_news_stale_head.py -q
"""
import json
import logging
import os
import subprocess
import sys
import time
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(ROOT / "harness" / "bin"))

import ft_news_html as fh  # noqa: E402
import ft_news_ledger as nl  # noqa: E402
from real_state_guard import guard_begin_module  # noqa: E402,F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)
from test_ft_news_html import DATA, oc, slack  # noqa: E402,F401  가짜 opencode·가짜 Slack 픽스처 재사용
from test_ledger_fill_r851 import NOW, REL, fill, origin_ledger, world  # noqa: E402,F401  r4: 실제 채움 커밋 픽스처 재사용(임시 bare origin · 실 원장 0)
from datetime import timedelta  # noqa: E402

ENV_KEYS = ("FT_LEDGER_SYNC_ERROR", "FT_LEDGER_SYNC_REPEAT", "FT_LEDGER_STALE_HEAD", "FT_NEWS_STALE_OK_MIN", "FT_NEWS_HEAD")


def _git(repo: Path, *a: str) -> str:
    return subprocess.run(["git", "-C", str(repo), "-c", "user.name=t", "-c", "user.email=t@t", *a],
                          check=True, capture_output=True, text=True).stdout.strip()


@pytest.fixture
def fetch(tmp_path, monkeypatch):
    """받기 대역 = 시간 초과(상한 1초 · 2초 sleep · 출력 0 → 재시도 1) · 표식·마지막 결과 파일은 tmp."""
    repo = tmp_path / "ledger-repo"
    repo.mkdir()
    _git(repo, "init", "-q")
    (repo / "a.txt").write_text("x\n", encoding="utf-8")
    _git(repo, "add", ".")
    _git(repo, "commit", "-qm", "i")
    log, script = tmp_path / "fetch.log", tmp_path / "fetch.sh"
    script.write_text(f'#!/usr/bin/env bash\necho try >> "{log}"\nsleep 2\nexit 0\n', encoding="utf-8")
    for k, v in {"FT_LEDGER_FETCH": script, "FT_NEWS_FETCH_MIN": "0", "FT_NEWS_FETCH_TIMEOUT": "1",
                 "FT_NEWS_FETCH_STAMP": tmp_path / "fetch.stamp", "FT_NEWS_FETCH_LAST": tmp_path / "fetch-last"}.items():
        monkeypatch.setenv(k, str(v))
    for k in ENV_KEYS:
        monkeypatch.delenv(k, raising=False)
    return repo, log, tmp_path / "fetch.stamp"


def _age(stamp: Path, minutes: float) -> None:
    stamp.write_text(f"{time.time() - minutes * 60:.0f}\n", encoding="utf-8")


def _tick_args(tmp_path, monkeypatch, fills: list):
    monkeypatch.setattr(fh, "build", lambda *a: DATA)
    monkeypatch.setattr(fh, "ledger_fill", lambda root, repo, rel, cur: fills.append(cur) or cur)
    monkeypatch.setenv("FT_LEDGER_FRESH_GATE", "0")
    return (tmp_path, tmp_path / "state", tmp_path, "x.md", tmp_path / "news")


# ── ⓐ 받기 시간 초과 · 직전 판 6분 전 → 경고 구 · 판정 불가 0 · 정상 지도 게시 ──
def test_a_timeout_within_age_sets_stale_head_not_sync_error(fetch, caplog):
    repo, log, stamp = fetch
    _age(stamp, 6.1)
    caplog.set_level(logging.WARNING)
    head = nl.fetch_if_stale(repo)
    assert head.startswith("원장 6분 전 판(받기 실패: ") and "시도 상한" in head and head.endswith(")")
    assert os.environ["FT_LEDGER_STALE_HEAD"] == head
    assert "FT_LEDGER_SYNC_ERROR" not in os.environ  # 판정 불가 갈래로 가지 않는다
    warns = [r.message for r in caplog.records if r.levelname == "WARNING"]
    assert len([w for w in warns if w.startswith("원장 ref fetch 실패 — ")]) == 1  # r907 r3 — 받기 쪽은 WARN 1줄
    assert [r for r in caplog.records if r.levelname == "ERROR"] == []  # ERROR 는 tick 이 구간당 1줄(ⓛ)
    assert len(log.read_text(encoding="utf-8").split()) == 2  # ⓕ 시도 수 그대로(새 원격 호출 0)


def test_a_tick_publishes_map_with_stale_head_first(tmp_path, oc, slack, monkeypatch):  # noqa: F811  픽스처 재사용(oc·slack)
    fills: list = []
    args = _tick_args(tmp_path, monkeypatch, fills)
    monkeypatch.setenv("FT_NEWS_FETCH_LAST", str(tmp_path / "fetch-last"))
    monkeypatch.delenv("FT_LEDGER_SYNC_ERROR", raising=False)
    monkeypatch.setenv("FT_LEDGER_STALE_HEAD", "원장 6분 전 판(받기 실패: fetch 실행 실패: 시도 상한 28초 초과)")
    monkeypatch.setenv("FT_NEWS_NOW", "2026-10-25 12:15")
    assert fh.tick(*args, "a", "b") == (0, "지도 발행")
    text = slack.msgs[-1]["text"]
    assert text.startswith("[뉴스 12:15] 원장 6분 전 판(받기 실패: fetch 실행 실패: 시도 상한 28초 초과) · 팀 지도 — ")
    assert "판정 불가" not in text and slack.msgs[-1].get("files")
    assert fills == []  # ⓔ 낡은 ref 위 원장 커밋 0


# ── ⓑ 직전 판 16분 전(상한 15) → 지금처럼 판정 불가 ──
def test_b_over_age_is_unjudgeable(fetch):
    repo, _log, stamp = fetch
    _age(stamp, 16.2)
    err = nl.fetch_if_stale(repo)
    assert err.startswith("원장 ref fetch 실패 — ") and "origin/main = 16분 전 받은 판" in err
    assert os.environ["FT_LEDGER_SYNC_ERROR"] == err and "FT_LEDGER_STALE_HEAD" not in os.environ


@pytest.mark.parametrize("raw", ["abc", "-3", "nan", ""])
def test_b_bad_limit_env_falls_back_to_15(fetch, monkeypatch, raw):
    repo, _log, stamp = fetch
    monkeypatch.setenv("FT_NEWS_STALE_OK_MIN", raw)
    _age(stamp, 14.2)
    assert nl.fetch_if_stale(repo).startswith("원장 14분 전 판(")
    for k in ENV_KEYS[:3]:
        os.environ.pop(k, None)
    _age(stamp, 16.2)
    assert nl.fetch_if_stale(repo).startswith("원장 ref fetch 실패 — ")


def test_b_limit_env_number_is_used(fetch, monkeypatch):
    repo, _log, stamp = fetch
    monkeypatch.setenv("FT_NEWS_STALE_OK_MIN", "5")
    _age(stamp, 6.1)
    assert nl.fetch_if_stale(repo).startswith("원장 ref fetch 실패 — ") and "FT_LEDGER_STALE_HEAD" not in os.environ


# ── ⓒ 표식 없음·깨짐·미래 시각(시계 뒤틀림) → 판정 불가 ──
@pytest.mark.parametrize("content", [None, "깨짐\n", "future"])
def test_c_unknown_or_skewed_age_is_unjudgeable(fetch, content):
    repo, _log, stamp = fetch
    if content == "future":
        _age(stamp, -10)
    elif content is not None:
        stamp.write_text(content, encoding="utf-8")
    err = nl.fetch_if_stale(repo)
    assert err.startswith("원장 ref fetch 실패 — ") and os.environ["FT_LEDGER_SYNC_ERROR"] == err
    assert "FT_LEDGER_STALE_HEAD" not in os.environ


# ── 성공 틱 = 경고 구 지움(같은 프로세스에 남은 낡은 값 0) ──
def test_success_clears_stale_head(fetch, monkeypatch, tmp_path):
    repo, _log, stamp = fetch
    _age(stamp, 6.1)
    nl.fetch_if_stale(repo)
    ok = tmp_path / "ok.sh"
    ok.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
    monkeypatch.setenv("FT_LEDGER_FETCH", str(ok))
    assert nl.fetch_if_stale(repo) == "" and "FT_LEDGER_STALE_HEAD" not in os.environ


# ── 두 입구 구분: sync_repo 갈래(«원장 사본 갱신 안 됨») 사유가 이미 있으면 나이 안이어도 판정 불가 그대로 ──
def test_sync_repo_entrance_error_is_kept(fetch, monkeypatch):
    repo, _log, stamp = fetch
    monkeypatch.setenv("FT_LEDGER_SYNC_ERROR", "원장 사본 갱신 안 됨 — ERROR x")
    _age(stamp, 6.1)
    nl.fetch_if_stale(repo)
    assert os.environ["FT_LEDGER_SYNC_ERROR"] == "원장 사본 갱신 안 됨 — ERROR x"


# ── ⓓ 연속 틱: 같은 판 = 변화 없음 줄(경고 구 유지) · 나이 넘는 틱 = 판정 불가 1통 · 그다음 게시 0 ──
def test_d_three_ticks_then_over_age_one_unjudgeable(fetch, tmp_path, oc, slack, monkeypatch):  # noqa: F811  픽스처 재사용(oc·slack)
    repo, _log, stamp = fetch
    fills: list = []
    args = _tick_args(tmp_path, monkeypatch, fills)
    made: list = []
    real = fh.run_files
    monkeypatch.setattr(fh, "run_files", lambda d, out, now: made.append(now) or real(d, out, now))
    monkeypatch.setattr(fh, "_human_key", lambda *a: "k" * 40)  # r5: 키 모름 = 항상 «바뀜» — 이 시험은 «같은 판»(키 그대로)이 전제라 키를 고정한다

    def tick(now: str, minutes: float, base: str, cur: str):
        for k in ENV_KEYS[:3] + ("FT_NEWS_HEAD",):
            os.environ.pop(k, None)
        _age(stamp, minutes)
        nl.fetch_if_stale(repo)
        monkeypatch.setenv("FT_NEWS_NOW", now)
        return fh.tick(*args, base, cur)

    assert tick("2026-10-25 12:15", 6.1, "a", "b") == (0, "지도 발행") and len(made) == 1
    assert slack.msgs[-1]["text"].startswith("[뉴스 12:15] 원장 6분 전 판(받기 실패: ")
    assert tick("2026-10-25 12:20", 7.1, "b", "b") == (0, "원장 커밋 0")  # 같은 판 · 30분 안 = 게시 0
    n = len(slack.msgs)
    assert tick("2026-10-25 12:46", 14.1, "b", "b")[0] == 0 and len(slack.msgs) == n + 1 and len(made) == 1
    line = slack.msgs[-1]["text"]
    assert line.startswith("[뉴스 12:46] 변화 없음 · 지도 ") and "원장 14분 전 판(받기 실패: " in line  # 경고 구 유지
    assert tick("2026-10-25 12:48", 16.1, "b", "b") == (1, "원장 ref fetch 실패")  # r907 r2 — 판정 불가 = 게시 0 · rc1
    assert len(slack.msgs) == n + 1 and len(made) == 1  # 게시 0 · 지도 0
    assert tick("2026-10-25 12:49", 17.1, "b", "b") == (1, "원장 ref fetch 실패 계속") and len(slack.msgs) == n + 1  # 구간 내내 게시 0
    assert fills == []  # ⓔ 받기 실패 틱 내내 원장 커밋 0
    assert json.loads((tmp_path / "state" / "html.json").read_text(encoding="utf-8"))["map_at"] == "2026-10-25 12:15"


# ── ⓔ 받기 정상 틱 = ledger_fill 그대로 1회 ──
def test_e_fill_runs_when_fetch_ok(tmp_path, oc, slack, monkeypatch):  # noqa: F811  픽스처 재사용(oc·slack)
    fills: list = []
    args = _tick_args(tmp_path, monkeypatch, fills)
    for k in ENV_KEYS:
        monkeypatch.delenv(k, raising=False)
    monkeypatch.setenv("FT_NEWS_NOW", "2026-10-25 12:15")
    assert fh.tick(*args, "a", "b") == (0, "지도 발행") and fills == ["b"]
    assert slack.msgs[-1]["text"].startswith("[뉴스 12:15] 팀 지도 — ")


# ── ⓕ 받기 실패 갈래 시간 = 시도 상한 2회 + 유예(새 원격 호출 0 · 하드 룰 12 마감 그대로) ──
def test_f_stale_branch_adds_no_time(fetch):
    repo, log, stamp = fetch
    _age(stamp, 6.1)
    t0 = time.monotonic()
    nl.fetch_if_stale(repo)
    assert time.monotonic() - t0 <= 6.5 and len(log.read_text(encoding="utf-8").split()) == 2


# ── ⓖ DA⑥ r1 반례 — 나이 상한 env 유한성 · 표식 값 유한성 ──
@pytest.mark.parametrize("raw", ["inf", "1e309", "-inf", "nan"])
def test_g_non_finite_limit_falls_back_to_15(fetch, monkeypatch, raw):
    """env 상한이 유한하지 않으면 기본 15분 — inf 로 무제한 통과(DA⑥ r1 HOLD) 0."""
    repo, _log, stamp = fetch
    monkeypatch.setenv("FT_NEWS_STALE_OK_MIN", raw)
    _age(stamp, 14.2)
    assert nl.fetch_if_stale(repo).startswith("원장 14분 전 판(")  # 15분 상한 그대로
    for k in ENV_KEYS[:3]:
        os.environ.pop(k, None)
    _age(stamp, 16.2)
    assert nl.fetch_if_stale(repo).startswith("원장 ref fetch 실패 — ") and "FT_LEDGER_STALE_HEAD" not in os.environ


@pytest.mark.parametrize("raw", ["nan", "inf", "-inf", "1e400"])
def test_g_non_finite_stamp_is_unjudgeable(fetch, raw):
    """표식 값이 유한하지 않으면 «모름» = 판정 불가 갈래 · 문구 계산 예외 0."""
    repo, _log, stamp = fetch
    stamp.write_text(raw + "\n", encoding="utf-8")
    err = nl.fetch_if_stale(repo)
    assert err.startswith("원장 ref fetch 실패 — ") and os.environ["FT_LEDGER_SYNC_ERROR"] == err
    assert "FT_LEDGER_STALE_HEAD" not in os.environ


# ── ⓗ 판정 불가 = 게시 0 · ERROR 1줄(구간 첫 틱) · rc1 · 회복 틱 정상 게시 ──
def test_h_over_age_publishes_nothing_rc1_one_error(fetch, tmp_path, oc, slack, monkeypatch, caplog):  # noqa: F811  픽스처 재사용(oc·slack)
    repo, _log, stamp = fetch
    fills: list = []
    args = _tick_args(tmp_path, monkeypatch, fills)
    monkeypatch.setenv("FT_NEWS_FETCH_LAST", str(tmp_path / "fetch-last"))
    made: list = []
    real = fh.run_files
    monkeypatch.setattr(fh, "run_files", lambda d, out, now: made.append(now) or real(d, out, now))
    caplog.set_level(logging.ERROR)
    _age(stamp, 16.1)
    nl.fetch_if_stale(repo)
    monkeypatch.setenv("FT_NEWS_NOW", "2026-10-25 12:15")
    assert fh.tick(*args, "a", "b") == (1, "원장 ref fetch 실패")
    assert slack.msgs == [] and made == [] and fills == []  # 게시 0 · 지도 0 · 원장 커밋 0
    errs = [r for r in caplog.records if r.levelname == "ERROR"]  # ⓛ 첫 실패 틱 ERROR «전체» 1줄(받기 쪽은 WARN)
    assert len(errs) == 1 and "판정 불가 · 게시 0" in errs[0].getMessage()
    assert (tmp_path / "fetch-last").read_text(encoding="utf-8").strip() == "fail"
    for k in ENV_KEYS[:3] + ("FT_NEWS_HEAD",):
        os.environ.pop(k, None)
    _age(stamp, 17.1)
    nl.fetch_if_stale(repo)
    monkeypatch.setenv("FT_NEWS_NOW", "2026-10-25 12:16")
    caplog.clear()
    assert fh.tick(*args, "b", "b") == (1, "원장 ref fetch 실패 계속") and slack.msgs == []  # 같은 구간 = ERROR 0
    assert not [r for r in caplog.records if r.levelname == "ERROR" and "판정 불가" in r.getMessage()]
    ok = tmp_path / "ok.sh"
    ok.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
    monkeypatch.setenv("FT_LEDGER_FETCH", str(ok))
    for k in ENV_KEYS[:3] + ("FT_NEWS_HEAD",):
        os.environ.pop(k, None)
    assert nl.fetch_if_stale(repo) == ""
    monkeypatch.setenv("FT_NEWS_NOW", "2026-10-25 12:17")
    assert fh.tick(*args, "c", "d") == (0, "지도 발행") and len(slack.msgs) == 1 and len(made) == 1  # 회복 틱 정상 게시


# ── ⓘ 발행 주기 — 기계 채움 칸은 «변화» 가 아니다 + 최소 간격 10분 ──
LEDGER_FILLED = """# 원장
사람 글 {human}
## 2. 오빠 할 일 (기계 채움 10-25 12:0{n} · {n}건)
1. 실행 줄 — 기다린 지 {mins}분 · ! bash /tmp/x.sh
## 3. 팀 작업
| 팀 | 지금 하는 것 | 다음 |
|---|---|---|
| planner | 진행 {cards}장 | 대기 0장 |
"""


@pytest.fixture
def fillenv(tmp_path, monkeypatch):
    """기계 채움 칸(§2·표)과 사람 글줄이 함께 있는 원장 git 리포 + 가짜 build/발행."""
    import ft_news_publish as np
    repo, rel = tmp_path / "repo", "design/planner/PLAN.md"
    repo.mkdir()
    _git(repo, "init", "-q")
    _git(repo, "config", "user.email", "t@t")
    _git(repo, "config", "user.name", "t")
    state, made = tmp_path / "state", []
    monkeypatch.setattr(fh, "build", lambda *a: DATA)
    monkeypatch.setattr(fh, "run_files", lambda d, out, now: (made.append(now), (out / "a.html", out / "a.txt"))[1])
    monkeypatch.setattr(fh, "publish_files", lambda h, s, now: (0, {"ts": str(len(made)), "link": f"http://x/{len(made)}"}))
    monkeypatch.setattr(np, "publish_line", lambda text, now: 0)
    monkeypatch.setattr(np, "retry_attach", lambda now: None)
    monkeypatch.setattr(fh, "ledger_fill", lambda root, r_, rel_, cur: cur)  # 채움 커밋은 시험이 직접 만든다
    monkeypatch.setenv("FT_NEWS_MAIN_REF", "HEAD")
    monkeypatch.setenv("FT_NEWS_REPEAT_MIN", "100000")
    monkeypatch.setenv("FT_LEDGER_FRESH_GATE", "0")
    for k in ("FT_NEWS_MODE", "FT_LEDGER_SYNC_ERROR", "FT_NEWS_HEAD", "FT_NEWS_MIN_GAP_MIN", "FT_LEDGER_STALE_HEAD"):
        monkeypatch.delenv(k, raising=False)
    return repo, rel, state, made


def _commit_ledger(repo, rel, text: str, msg: str = "원장", email: str = "") -> str:
    p = repo / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8")
    _git(repo, "add", ".")
    who = ["-c", f"user.email={email}"] if email else []
    _git(repo, *who, "commit", "-qm", msg)
    return _git(repo, "rev-parse", "HEAD")


def _fill_commit(repo, rel, text: str, msg: str = "채움") -> str:
    """기계 채움이 만드는 커밋과 같은 커미터 이메일(ft_ledger_fill.WHO@byz.local · 한 곳) — 메시지는 임의(판별에 안 쓴다)."""
    from ft_ledger_fill import WHO
    return _commit_ledger(repo, rel, text, msg=msg, email=f"{WHO}@byz.local")


def test_i_fill_only_changes_are_not_a_change_and_gap_is_10(fillenv, tmp_path, monkeypatch):
    """채움 커밋만 쌓인 3틱 = 게시 0 · 사람 글줄 1줄 = 게시 1 · 그 뒤 5분 변화 = 게시 0(간격) · 10분 변화 = 게시 1."""
    repo, rel, state, made = fillenv
    news = tmp_path / "news"
    base_f = state / "last.sha"
    stamp = {"v": ""}

    def tick(cur: str, at: str):
        monkeypatch.setenv("FT_NEWS_NOW", at)
        base = base_f.read_text(encoding="utf-8").strip() if base_f.is_file() else ""
        return fh.tick(tmp_path, state, repo, rel, news, base, cur)

    c1 = _commit_ledger(repo, rel, LEDGER_FILLED.format(human="A", n=1, mins=5, cards=1))
    stamp["v"] = c1
    assert tick(c1, "2026-10-25 12:00") == (0, "지도 발행") and len(made) == 1
    for i, (n, mins, cards) in enumerate([(2, 6, 2), (3, 7, 3), (4, 8, 4)], start=1):
        c = _fill_commit(repo, rel, LEDGER_FILLED.format(human="A", n=n, mins=mins, cards=cards))
        assert tick(c, f"2026-10-25 12:0{i}") == (0, "원장 커밋 0") and len(made) == 1  # 채움 커밋만 = 변화 0
    c_human = _commit_ledger(repo, rel, LEDGER_FILLED.format(human="B — 사람이 쓴 새 줄", n=5, mins=9, cards=5))
    assert tick(c_human, "2026-10-25 12:10") == (0, "지도 발행") and len(made) == 2  # 사람 칸 1줄 = 게시 1
    c_5 = _commit_ledger(repo, rel, LEDGER_FILLED.format(human="C", n=6, mins=10, cards=6))
    assert tick(c_5, "2026-10-25 12:15") == (0, "게시 간격 안") and len(made) == 2  # 5분 뒤 = 간격
    c_10 = _commit_ledger(repo, rel, LEDGER_FILLED.format(human="D", n=7, mins=11, cards=7))
    assert tick(c_10, "2026-10-25 12:25") == (0, "지도 발행") and len(made) == 3  # 10분 뒤 = 게시
    assert (state / "last.blob").read_text(encoding="utf-8").strip() == c_10  # 판정 키 = 채움 아닌 마지막 커밋 sha(r4)


def test_i_min_gap_env_finite_positive_only(fillenv, monkeypatch):
    """최소 간격 env — 유한하고 1 ≤ 값 ≤ 1440 만 · 0 이하·1441·1e308·숫자 아님·nan·inf = 10."""
    for raw, want in (("3", 3.0), ("1440", 1440.0), ("0", 10.0), ("-5", 10.0), ("1441", 10.0),
                      ("1e308", 10.0), ("abc", 10.0), ("nan", 10.0), ("inf", 10.0)):
        monkeypatch.setenv("FT_NEWS_MIN_GAP_MIN", raw)
        assert fh._min_gap_min() == want


# ── ⓙ 판정 키 = fill 이 실제로 다시 쓰는 구간만 (사람 표 칸 변경은 «바뀜») ──
LEDGER_TABLES = """# 원장
사람 글줄 {human}
## 3. 팀 작업
| 팀 | 지금 하는 것 | 다음 |
|---|---|---|
| planner | 진행 {cards}장 | 대기 0장 |
## 4. 드러난 문제
| 문제 | 상태 |
|---|---|
| r907 {issue} | 열림 |
"""


def test_j_key_is_last_non_fill_commit(fillenv, tmp_path, monkeypatch):
    """ⓙ' 채움 커밋(§3 표 변경 · §2 줄 변경) 연속 = 게시 0 · 사람 커밋 1(§4 칸) = 게시 1 · 사람이 채움 구간을 고친 커밋도 «사람» = 게시 1(메시지 파싱 0)."""
    repo, rel, state, made = fillenv
    news = tmp_path / "news"
    base_f = state / "last.sha"

    def tick(cur: str, at: str):
        monkeypatch.setenv("FT_NEWS_NOW", at)
        base = base_f.read_text(encoding="utf-8").strip() if base_f.is_file() else ""
        return fh.tick(tmp_path, state, repo, rel, news, base, cur)

    c1 = _commit_ledger(repo, rel, LEDGER_TABLES.format(human="A", cards=1, issue="a"))
    assert tick(c1, "2026-10-25 12:00") == (0, "지도 발행") and len(made) == 1
    for i, cards in enumerate((2, 3, 4), start=1):  # 채움 커밋 3개
        f = _fill_commit(repo, rel, LEDGER_TABLES.format(human="A", cards=cards, issue="a"))
        assert fh._human_key(repo, rel, f) == c1  # 키 = 채움 아닌 마지막 커밋 = c1 그대로
        assert tick(f, f"2026-10-25 12:0{i}") == (0, "원장 커밋 0") and len(made) == 1
    c3 = _commit_ledger(repo, rel, LEDGER_TABLES.format(human="A", cards=4, issue="b"))
    assert fh._human_key(repo, rel, c3) == c3
    assert tick(c3, "2026-10-25 12:12") == (0, "지도 발행") and len(made) == 2  # 사람 커밋 1 = 게시 1
    c4 = _commit_ledger(repo, rel, LEDGER_TABLES.format(human="A", cards=9, issue="b"))  # 채움 구간(§3)만 고쳤어도 커미터가 채움이 아니면 사람
    assert tick(c4, "2026-10-25 12:30") == (0, "지도 발행") and len(made) == 3


def test_j_real_fill_commits_do_not_move_key_including_row_lowering(tmp_path, monkeypatch, world):  # noqa: F811
    """ⓙ' 실제 ft_ledger_fill.fill 로 만든 채움 커밋(닫힌 행 내리기 포함) 3개 = 키 그대로(DA⑥ r3 반례 ①) · 사람 커밋 위에서는 키 = 그 커밋."""
    w = world
    repo = w["repo"]
    head = lambda ref: fh._human_key(repo, REL, ref)  # noqa: E731
    base_key = head("origin/main")
    assert base_key and base_key == _git(repo, "log", "-1", "--format=%H", "origin/main", "--", REL)  # 원장을 건드린 마지막 커밋("base")
    before = origin_ledger(w, "main")
    assert "| 2 | 옛 일 닫기 |" in before.split("## 5.")[0]  # 닫힌 행이 1절에 있다 → 채움이 5절로 내린다
    for step, at in enumerate((0, 3, 4)):  # 채움 3회 — 입력(열린 질문 목록)을 바꿔 매번 새 채움 커밋
        if step == 1:  # 첫 채움이 닫힌 행을 «처음 본 시각» 으로 적었다 → 그 뒤 «발행 성공» 기록이 있으면 두 번째 채움이 5절로 내린다
            w["mag"].write_text(json.dumps({"k": {"uploaded": True, "at": f"{NOW + timedelta(minutes=1):%Y-%m-%d %H:%M}"}}), encoding="utf-8")
        w["q"].write_text(json.dumps({"open": {str(1 + step): {"seat": "s#1", "what": f"질문 {step}", "state": "open"}}}, ensure_ascii=False), encoding="utf-8")
        rc, sha = fill(w, NOW + timedelta(minutes=at))
        assert rc == 0 and sha
        _git(repo, "fetch", "-q", "origin")
        assert head("origin/ledger/auto") == base_key  # 채움 커밋만 = 키 그대로
    filled = origin_ledger(w)
    assert filled != before and "| 2 | 옛 일 닫기 |" not in filled.split("## 5.")[0] and "| 10-12-2 | 옛 일 닫기 |" in filled.split("## 5.")[1]  # 행 내리기 실제 일어남(fill 출력 «내림 1»)
    _git(repo, "checkout", "-q", "-B", "human", "origin/ledger/auto")
    (repo / REL).write_text(filled + "\n사람이 손으로 쓴 새 줄\n", encoding="utf-8")
    _git(repo, "commit", "-qam", "사람 수정")
    assert head("HEAD") == _git(repo, "rev-parse", "HEAD") != base_key


def test_j_key_unknown_when_git_log_fails_or_times_out(fillenv, monkeypatch, caplog):
    """ⓙ' git log 실패(없는 ref) · 시간 초과 · 채움 모듈 없음 = 키 None(모름 = «바뀜» 쪽) · WARN."""
    repo, rel, _state, _made = fillenv
    c = _commit_ledger(repo, rel, "# 원장\n사람 A\n")
    assert fh._human_key(repo, rel, c) == c and fh._human_key(repo, rel, "no-such-ref") is None
    caplog.set_level(logging.WARNING)
    real = subprocess.run

    def boom(cmd, *a, **kw):
        if "log" in cmd:
            raise subprocess.TimeoutExpired(cmd, kw.get("timeout", 7))
        return real(cmd, *a, **kw)
    monkeypatch.setattr(fh.subprocess, "run", boom)
    assert fh._human_key(repo, rel, c) is None
    assert [r for r in caplog.records if "판정 키 모름" in r.getMessage()]


def test_j_unknown_key_publishes_but_gap_still_caps(fillenv, tmp_path, monkeypatch):
    """키 모름 = «바뀜» → 게시 후보 · 최소 간격 10분이 상한(채움 커밋이 매 틱 와도 하루 235회가 아님)."""
    repo, rel, state, made = fillenv
    monkeypatch.setattr(fh, "_human_key", lambda *a: None)
    news, base_f = tmp_path / "news", state / "last.sha"

    def tick(cur: str, at: str):
        monkeypatch.setenv("FT_NEWS_NOW", at)
        base = base_f.read_text(encoding="utf-8").strip() if base_f.is_file() else ""
        return fh.tick(tmp_path, state, repo, rel, news, base, cur)

    assert tick(_commit_ledger(repo, rel, "# 원장\nA\n"), "2026-10-25 12:00") == (0, "지도 발행") and len(made) == 1
    assert tick(_commit_ledger(repo, rel, "# 원장\nB\n"), "2026-10-25 12:02") == (0, "게시 간격 안") and len(made) == 1
    assert tick(_commit_ledger(repo, rel, "# 원장\nC\n"), "2026-10-25 12:11") == (0, "지도 발행") and len(made) == 2


# ── ⓚ 간격 상태 손상 = «모름» = 게시 가능 + WARN (영영 미루기·예외 0) · env 상한 ──
@pytest.mark.parametrize("map_at", ["broken", "9999-12-31 23:59", ""])
def test_k_broken_or_future_map_at_publishes_with_warn(fillenv, tmp_path, monkeypatch, caplog, map_at):
    repo, rel, state, made = fillenv
    state.mkdir(parents=True, exist_ok=True)
    (state / "html.json").write_text(json.dumps({"at": "2026-10-25 12:00", "map_at": map_at}), encoding="utf-8")
    caplog.set_level(logging.WARNING)
    c = _commit_ledger(repo, rel, "# 원장\n사람 A\n")
    monkeypatch.setenv("FT_NEWS_NOW", "2026-10-25 12:05")
    assert fh.tick(tmp_path, state, repo, rel, tmp_path / "news", "", c) == (0, "지도 발행") and len(made) == 1
    assert [r for r in caplog.records if r.levelname == "WARNING" and "지도 상태 시각 모름" in r.getMessage()]


@pytest.mark.parametrize("raw", ["[]", '{"map_at": 123}', '{"at": null}', '{"at": 5, "map_at": ["x"], "fail_at": {}}', "{깨진 json", '"문자열"', "null"])
def test_k_garbage_state_file_no_exception_warn_and_check_stale_once(fillenv, tmp_path, monkeypatch, caplog, raw):
    """ⓚ' html.json 이 객체 아님·칸 형 틀림·깨진 JSON → 예외 0 · WARN · 게시 가능 · nl.run 이 check_stale 을 정확히 1회(DA⑥ r3 반례 ②)."""
    repo, rel, state, made = fillenv
    state.mkdir(parents=True, exist_ok=True)
    (state / "html.json").write_text(raw, encoding="utf-8")
    c = _commit_ledger(repo, rel, "# 원장\n사람 A\n")
    (state / "last.blob").write_text(c + "\n", encoding="utf-8")  # 키 그대로 = «변화 없음» 갈래(오늘 지도 있음 판정이 상태 칸을 읽는 자리)까지 탄다
    monkeypatch.setenv("FT_NEWS_NOW", "2026-10-25 12:05")
    monkeypatch.setenv("FT_ROOT", str(tmp_path / "root"))
    stale: list = []
    monkeypatch.setattr(nl, "interval_s", lambda: 1)
    monkeypatch.setattr(nl, "check_stale", lambda *a: stale.append(a))
    monkeypatch.setattr(nl, "_run", lambda root, st: fh.tick(root, state, repo, rel, tmp_path / "news", "", c))
    caplog.set_level(logging.WARNING)
    assert nl.run() == 0 and len(made) == 1 and len(stale) == 1
    assert [r for r in caplog.records if r.levelname == "WARNING" and ("지도 상태" in r.getMessage() or "지도 상태 시각 모름" in r.getMessage())]


# ── ⓝ 어떤 예외든 check_stale 은 항상 · ERROR 1줄 + rc1 ──
def test_n_tick_exception_is_caught_error_once_rc1(fillenv, tmp_path, monkeypatch, caplog):
    repo, rel, state, _made = fillenv
    c = _commit_ledger(repo, rel, "# 원장\nA\n")

    def boom(*a):
        raise TypeError("임의 예외")
    monkeypatch.setattr(fh, "_tick", boom)
    caplog.set_level(logging.ERROR)
    rc, why = fh.tick(tmp_path, state, repo, rel, tmp_path / "news", "", c)
    assert rc == 1 and why == "뉴스 틱 예외 TypeError"
    errs = [r for r in caplog.records if r.levelname == "ERROR"]
    assert len(errs) == 1 and "TypeError" in errs[0].getMessage() and "임의 예외" in errs[0].getMessage()


def test_n_run_calls_check_stale_even_when_run_raises(tmp_path, monkeypatch, caplog):
    monkeypatch.setenv("FT_ROOT", str(tmp_path))
    stale: list = []
    monkeypatch.setattr(nl, "interval_s", lambda: 1)
    monkeypatch.setattr(nl, "check_stale", lambda *a: stale.append(a))

    def boom(root, state):
        raise TypeError("임의 예외")
    monkeypatch.setattr(nl, "_run", boom)
    caplog.set_level(logging.ERROR)
    assert nl.run() == 1 and len(stale) == 1
    errs = [r for r in caplog.records if r.levelname == "ERROR"]
    assert len(errs) == 1 and "TypeError" in errs[0].getMessage()


def test_n_git_show_timeout_is_a_runtime_error(fillenv, monkeypatch):
    """남은 git 호출(show 포함) 7초 상한 — 넘으면 RuntimeError(= 지도 만들기 실패 경로 · 무한 대기 0)."""
    repo, rel, _state, _made = fillenv
    c = _commit_ledger(repo, rel, "# 원장\nA\n")
    assert fh._git(repo, "show", f"{c}:{rel}").startswith("# 원장")
    real = subprocess.run

    def slow(cmd, *a, **kw):
        assert kw.get("timeout") == fh.GIT_S == 7
        raise subprocess.TimeoutExpired(cmd, kw["timeout"])
    monkeypatch.setattr(fh.subprocess, "run", slow)
    with pytest.raises(RuntimeError, match="시간 초과"):
        fh._git(repo, "show", f"{c}:{rel}")
    monkeypatch.setattr(fh.subprocess, "run", real)


def test_k_first_tick_without_state_has_no_warn(fillenv, tmp_path, monkeypatch, caplog):
    """상태 파일 자체가 없음 = 첫 판(«모름» 아님) — 게시 1 · WARN 0."""
    repo, rel, state, made = fillenv
    caplog.set_level(logging.WARNING)
    c = _commit_ledger(repo, rel, "# 원장\n사람 A\n")
    monkeypatch.setenv("FT_NEWS_NOW", "2026-10-25 12:00")
    assert fh.tick(tmp_path, state, repo, rel, tmp_path / "news", "", c) == (0, "지도 발행") and len(made) == 1
    assert not [r for r in caplog.records if r.levelname == "WARNING" and "지도 상태 시각 모름" in r.getMessage()]


# ── ⓦ 채움 판별 = 커미터 이메일(메시지 0) · 키 모름 = base==cur 여도 «바뀜» ──
def test_w_fill_is_told_by_committer_email_not_message(fillenv, tmp_path, monkeypatch):
    """사람 커밋 메시지(PR 본문)에 채움 문구가 있어도 사람 = 게시 1 · 채움 이메일 커밋은 메시지가 무엇이든 채움 = 게시 0."""
    from ft_ledger_fill import MSG
    repo, rel, state, made = fillenv
    news, base_f = tmp_path / "news", state / "last.sha"

    def tick(cur: str, at: str):
        monkeypatch.setenv("FT_NEWS_NOW", at)
        base = base_f.read_text(encoding="utf-8").strip() if base_f.is_file() else ""
        return fh.tick(tmp_path, state, repo, rel, news, base, cur)

    c1 = _commit_ledger(repo, rel, LEDGER_TABLES.format(human="A", cards=1, issue="a"))
    assert tick(c1, "2026-10-25 12:00") == (0, "지도 발행") and len(made) == 1
    f = _fill_commit(repo, rel, LEDGER_TABLES.format(human="A", cards=2, issue="a"), msg="아무 메시지")  # 채움 이메일 · 메시지 임의
    assert fh._human_key(repo, rel, f) == c1 and tick(f, "2026-10-25 12:02") == (0, "원장 커밋 0") and len(made) == 1
    c_pr = _commit_ledger(repo, rel, LEDGER_TABLES.format(human="B 사람 변경", cards=2, issue="a"), msg=f"PR 본문\n\n{MSG}\n사람이 인용")  # 사람 이메일 · 메시지에 채움 문구
    assert fh._human_key(repo, rel, c_pr) == c_pr
    assert tick(c_pr, "2026-10-25 12:12") == (0, "지도 발행") and len(made) == 2  # 사람 변경 게시 1


def test_w_more_fill_than_scan_window_means_key_unknown_and_publish_candidate(fillenv, tmp_path, monkeypatch, caplog):
    """최근 KEY_SCAN_N 개가 전부 채움 = 키 모름(None) → base==cur 여도 «바뀜» = 게시 후보(간격이 상한) · WARN."""
    repo, rel, state, made = fillenv
    monkeypatch.setattr(fh, "KEY_SCAN_N", 3)
    news = tmp_path / "news"
    _commit_ledger(repo, rel, LEDGER_TABLES.format(human="A", cards=1, issue="a"))
    for n in range(2, 6):  # 채움 4개 > 창 3
        last = _fill_commit(repo, rel, LEDGER_TABLES.format(human="A", cards=n, issue="a"))
    caplog.set_level(logging.WARNING)
    assert fh._human_key(repo, rel, last) is None
    assert [r for r in caplog.records if "판정 키 모름" in r.getMessage()]
    monkeypatch.setenv("FT_NEWS_NOW", "2026-10-25 12:00")
    assert fh.tick(tmp_path, state, repo, rel, news, last, last) == (0, "지도 발행") and len(made) == 1  # base == cur 인데도 게시 후보
    monkeypatch.setenv("FT_NEWS_NOW", "2026-10-25 12:03")
    assert fh.tick(tmp_path, state, repo, rel, news, last, last) == (0, "게시 간격 안") and len(made) == 1  # 간격이 상한
    monkeypatch.setenv("FT_NEWS_NOW", "2026-10-25 12:11")
    assert fh.tick(tmp_path, state, repo, rel, news, last, last) == (0, "지도 발행") and len(made) == 2


# ── ⓧ 시각 칸(map_at · fail_at · at) = 한 함수 · 모름(미래·깨짐) = 대기 0 + WARN ──
@pytest.mark.parametrize("bad", ["9999-12-31 23:59", "broken"])
def test_x_bad_fail_at_waits_zero_and_warns(fillenv, tmp_path, monkeypatch, caplog, bad):
    """fail_at 이 미래·깨짐이어도 «재시도 대기» 에 영영 갇히지 않는다 — 지금 게시 + WARN."""
    repo, rel, state, made = fillenv
    state.mkdir(parents=True, exist_ok=True)
    (state / "html.json").write_text(json.dumps({"at": "2026-10-25 11:00", "map_at": "2026-10-25 11:00", "fail_at": bad}), encoding="utf-8")
    c = _commit_ledger(repo, rel, "# 원장\n사람 A\n")
    caplog.set_level(logging.WARNING)
    monkeypatch.setenv("FT_NEWS_NOW", "2026-10-25 12:00")
    assert fh.tick(tmp_path, state, repo, rel, tmp_path / "news", "", c) == (0, "지도 발행") and len(made) == 1
    assert [r for r in caplog.records if r.levelname == "WARNING" and "지도 상태 시각 모름" in r.getMessage() and "fail_at" in r.getMessage()]


@pytest.mark.parametrize("bad", ["9999-12-31 23:59", "broken"])
def test_x_bad_at_waits_zero_and_warns(fillenv, tmp_path, monkeypatch, caplog, bad):
    """at 이 미래·깨짐 + 원장 키 그대로 + 오늘 지도 있음 → 변화 없음 줄 1회(반복 대기에 갇히지 않음) + WARN."""
    import ft_news_publish as np
    repo, rel, state, made = fillenv
    lines: list[str] = []
    monkeypatch.setattr(np, "publish_line", lambda text, now: lines.append(text) or 0)
    c = _commit_ledger(repo, rel, "# 원장\n사람 A\n")
    state.mkdir(parents=True, exist_ok=True)
    (state / "html.json").write_text(json.dumps({"at": bad, "map_at": "2026-10-25 11:00", "link": "http://x/0"}), encoding="utf-8")
    (state / "last.blob").write_text(c + "\n", encoding="utf-8")
    caplog.set_level(logging.WARNING)
    monkeypatch.setenv("FT_NEWS_NOW", "2026-10-25 12:00")
    assert fh.tick(tmp_path, state, repo, rel, tmp_path / "news", c, c) == (0, "원장 커밋 0") and len(lines) == 1 and "변화 없음" in lines[0]
    assert [r for r in caplog.records if r.levelname == "WARNING" and "지도 상태 시각 모름" in r.getMessage() and "at=" in r.getMessage()]


# ── ⓨ ledger 쪽 git(rev-parse · cat-file 포함) 7초 상한 · 시간 초과 = 판정 불가 갈래 · check_stale 항상 ──
@pytest.fixture
def slow_git(tmp_path, monkeypatch):
    """PATH 맨 앞에 «30초 자는 git» 대역 — 상한만 1초로 줄여 시험(실제 상수는 7)."""
    bin_dir = tmp_path / "slowbin"
    bin_dir.mkdir()
    g = bin_dir / "git"
    g.write_text("#!/bin/sh\nexec sleep 30\n", encoding="utf-8")
    g.chmod(0o755)
    monkeypatch.setenv("PATH", f"{bin_dir}{os.pathsep}{os.environ['PATH']}")
    monkeypatch.setattr(nl, "GIT_S", 1)


def test_y_ledger_git_constant_is_7():
    assert nl.GIT_S == 7


def test_y_ledger_rev_parse_and_cat_file_time_out_fast(slow_git, tmp_path):
    t0 = time.monotonic()
    with pytest.raises(RuntimeError, match="시간 초과"):
        nl._git(tmp_path, "rev-parse", "--verify", "HEAD")
    with pytest.raises(RuntimeError, match="시간 초과"):
        nl.check_base(tmp_path, "a" * 40, "x.md")
    assert time.monotonic() - t0 < 10  # 30초 대역이 아니라 상한(1초 × 2)


def test_y_run_with_slow_ledger_git_returns_fast_and_calls_check_stale_once(slow_git, tmp_path, monkeypatch, caplog):
    root = tmp_path / "root"
    root.mkdir()
    monkeypatch.setenv("FT_ROOT", str(root))
    monkeypatch.setenv("FT_NEWS_MODE", "html")
    monkeypatch.setenv("FT_NEWS_MAIN_REF", "HEAD")  # 읽는 ref 고르기(read_ref · 자체 7초 상한)를 건너뛰고 ledger 의 rev-parse(_git)가 첫 git 호출이 되게
    monkeypatch.setenv("FT_LEDGER_REPO", str(tmp_path))
    monkeypatch.setenv("FT_LEDGER_PATH", "x.md")
    monkeypatch.setenv("FT_NEWS_DIR", str(tmp_path / "news"))
    monkeypatch.setattr(nl, "fetch_if_stale", lambda repo: "")
    stale: list = []
    monkeypatch.setattr(nl, "interval_s", lambda: 1)
    monkeypatch.setattr(nl, "check_stale", lambda *a: stale.append(a))
    caplog.set_level(logging.ERROR)
    t0 = time.monotonic()
    assert nl.run() == 1 and len(stale) == 1
    assert time.monotonic() - t0 < 10
    assert [r for r in caplog.records if r.levelname == "ERROR" and "시간 초과" in r.getMessage()]


# ── ⓩ r6 — «모름/실패» 를 조용히 정상으로 넘기는 기본값 뒤집기 ──
def test_z1_state_without_at_field_waits_zero_and_warns_once(fillenv, tmp_path, monkeypatch, caplog):
    """상태 파일은 있는데 `at` 칸 없음(map_at 오늘) · 키 그대로 → 대기 0(변화 없음 줄 1회) + WARN 1줄(at 칸 없음). fail_at 없음은 정상 = WARN 0."""
    import ft_news_publish as np
    repo, rel, state, made = fillenv
    lines: list[str] = []
    monkeypatch.setattr(np, "publish_line", lambda text, now: lines.append(text) or 0)
    c = _commit_ledger(repo, rel, "# 원장\n사람 A\n")
    state.mkdir(parents=True, exist_ok=True)
    (state / "html.json").write_text(json.dumps({"map_at": "2026-10-25 11:00", "link": "fake"}), encoding="utf-8")
    (state / "last.blob").write_text(c + "\n", encoding="utf-8")
    caplog.set_level(logging.WARNING)
    monkeypatch.setenv("FT_NEWS_NOW", "2026-10-25 12:00")
    assert fh.tick(tmp_path, state, repo, rel, tmp_path / "news", c, c) == (0, "원장 커밋 0") and len(lines) == 1 and "변화 없음" in lines[0]
    warns = [r.getMessage() for r in caplog.records if r.levelname == "WARNING" and "지도 상태 시각 모름" in r.getMessage()]
    assert len(warns) == 1 and "at 칸 없음" in warns[0]  # fail_at 칸 없음은 WARN 0(실패한 적 없음 = 정상)


@pytest.fixture
def run_env(fillenv, tmp_path, monkeypatch):
    """nl.run() 을 실 git 리포(커밋 1개) 위에서 돌리는 환경 — 받기·알림·게시 대역 · 틱 호출 기록 · check_stale 기록."""
    repo, rel, state, made = fillenv
    _commit_ledger(repo, rel, "# 원장\n사람 A\n")
    root = tmp_path / "root"
    root.mkdir()
    for k, v in (("FT_ROOT", str(root)), ("FT_NEWS_MODE", "html"), ("FT_LEDGER_REPO", str(repo)), ("FT_LEDGER_PATH", rel),
                 ("FT_NEWS_DIR", str(tmp_path / "news")), ("FT_NEWS_FETCH_LAST", str(tmp_path / "fetch-last"))):
        monkeypatch.setenv(k, v)
    ticks, stale = [], []
    monkeypatch.setattr(nl, "fetch_if_stale", lambda r: "")
    monkeypatch.setattr(nl, "interval_s", lambda: 1)
    monkeypatch.setattr(nl, "check_stale", lambda *a: stale.append(a))
    monkeypatch.setattr(fh, "tick", lambda *a: ticks.append(a) or (0, "지도 발행"))
    return repo, ticks, stale


def test_z2_show_timeout_only_is_unjudgeable_one_error_per_section(run_env, monkeypatch, caplog):
    """rev-parse 성공 · `git show` 만 시간 초과 → 알림 try 가 삼키지 않는다: 게시(tick) 0 · rc1 · check_stale 매 틱 · 3틱 연속 ERROR 정확히 1줄(구간당 1줄)."""
    repo, ticks, stale = run_env
    real = subprocess.run

    def show_hangs(cmd, *a, **kw):
        if "show" in cmd:
            raise subprocess.TimeoutExpired(cmd, kw.get("timeout", 7))
        return real(cmd, *a, **kw)
    monkeypatch.setattr(nl.subprocess, "run", show_hangs)
    caplog.set_level(logging.WARNING)
    assert [nl.run() for _ in range(3)] == [1, 1, 1]
    assert ticks == [] and len(stale) == 3  # 게시 0 · 정지 감시 3회
    errs = [r.getMessage() for r in caplog.records if r.levelname == "ERROR"]
    assert len(errs) == 1 and "시간 초과" in errs[0]
    assert len([r for r in caplog.records if r.levelname == "WARNING" and "구간 계속" in r.getMessage()]) == 2
    assert not [e for e in errs if "알림 건너뜀" in e]


def test_z3_notify_own_failure_is_skipped_and_publishing_continues(run_env, monkeypatch, caplog):
    """알림 «자체» 실패(슬랙 등) = «알림 건너뜀» 1줄 · 게시는 진행(기존 행동 유지)."""
    _repo, ticks, stale = run_env

    def boom(root, text, state):
        raise OSError("슬랙 대역 실패")
    monkeypatch.setattr(nl, "notify", boom)
    caplog.set_level(logging.ERROR)
    assert nl.run() == 0 and len(ticks) == 1 and len(stale) == 1
    errs = [r.getMessage() for r in caplog.records if r.levelname == "ERROR"]
    assert len(errs) == 1 and "알림 건너뜀" in errs[0]
