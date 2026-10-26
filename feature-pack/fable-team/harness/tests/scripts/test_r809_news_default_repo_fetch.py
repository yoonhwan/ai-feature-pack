"""r809 — 뉴스(HTML) 틱이 «원장 리포를 먼저 정하고» 그 리포를 받는다 · 받기 실패면 «변화 없음» 대신 «판정 불가» 머리 줄.

결함(arch 131 실측 · r754 마지막 DA 반례 1) = `_run` 이 FT_LEDGER_REPO 가 env 에 있을 때만 fetch_if_stale 을 불렀다 —
기본 경로(env 없음 → LIVE_ROOT)는 받기 0 인데 옛 origin/main 으로 «변화 없음» 을 발행했다.

ⓐ FT_LEDGER_REPO 없음 · LIVE_ROOT = 임시 리포(로컬 bare 원격 · 원격 원장이 로컬 origin/main 보다 1커밋 앞) · 오늘 지도·기준선 있음
   → 받기 1회(FT_LEDGER_FETCH 스텁 호출 수 1) · 새 판 기준 지도 발행(«변화 없음» 0)
ⓑ 같은 꼴 + 받기 실패(스텁 rc1 «fatal: offline») → r907 r2: 게시 0(«판정 불가» 줄도 «변화 없음» 줄도 안 낸다) · rc1
ⓒ FT_LEDGER_REPO 있는 꼴(라이브 지금) → 받기 1회 · 발행 결과 ⓐ 와 같음
ⓓ 받기 성공 + 원격 = 로컬 + 기준선 같음 → «변화 없음» 그대로(정상 오판 0)
ⓔ FT_NEWS_MODE 없음(옛 판 경로) → sync_repo() 그대로(동작 무변경 · 받기 스텁 호출 0)
ⓖ 변이: 받기를 건너뛰면 ⓐ FAIL · «판정 불가» 갈래에 게시를 되살리면 ⓑ FAIL
ⓗ 격리 = 임시 리포·임시 루트 · 가짜 발행기(실 원격·실 원장·실 슬랙·실 mbox 0)

실행: cd harness && PYTHONPATH=bin:kit/fable-team/bin python3.11 -m pytest tests/scripts/test_r809_news_default_repo_fetch.py -q
"""
import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import pytest

BIN = Path(__file__).resolve().parents[3] / "harness" / "bin"
sys.path[:0] = [str(BIN)]
from real_state_guard import guard_begin_module  # noqa: E402,F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

import ft_news_html as fh  # noqa: E402
import ft_news_ledger as fl  # noqa: E402
import ft_news_publish as fp  # noqa: E402

REL = "design/planner/PLAN-oppa-ledger.md"


def _git(repo: Path, *a: str) -> str:
    return subprocess.run(["git", "-C", str(repo), *a], check=True, capture_output=True, text=True).stdout.strip()


def _count(counter: Path) -> int:
    return len(counter.read_text(encoding="utf-8").split())


def _stub(tmp_path: Path, monkeypatch, body: str, name: str = "calls") -> tuple[Path, Path]:
    """FT_LEDGER_FETCH/FT_LEDGER_SYNC 대역 — 부를 때마다 $CNT 에 1줄(카운터 경로는 스크립트에 박음)."""
    counter = tmp_path / f"{name}.txt"
    counter.write_text("", encoding="utf-8")
    p = tmp_path / f"stub-{name}.sh"
    p.write_text(f"#!/bin/bash\nCNT={counter}\n" + body, encoding="utf-8")
    p.chmod(0o755)
    return p, counter


FETCH_OK = 'echo x >> "$CNT"\nexec git -C "$1" fetch --quiet origin main\n'
FETCH_FAIL = 'echo x >> "$CNT"\necho "fatal: offline" >&2\nexit 1\n'


@pytest.fixture
def world(tmp_path, monkeypatch):
    """로컬 리포(live) + 그 origin 인 bare 원격(원장이 1커밋 앞) · 오늘 지도·기준선이 있는 상태."""
    remote = tmp_path / "remote.git"
    subprocess.run(["git", "init", "-q", "--bare", str(remote)], check=True)
    _git(remote, "symbolic-ref", "HEAD", "refs/heads/main")  # clone 이 main 을 체크아웃하도록
    live = tmp_path / "live"
    live.mkdir()
    _git(live, "init", "-q", "-b", "main")
    _git(live, "config", "user.email", "t@t")
    _git(live, "config", "user.name", "t")
    (live / REL).parent.mkdir(parents=True, exist_ok=True)
    (live / REL).write_text("원장 A\n", encoding="utf-8")
    _git(live, "add", "-A")
    _git(live, "commit", "-qm", "[docs] 원장 A")
    c1 = _git(live, "rev-parse", "HEAD")
    _git(live, "remote", "add", "origin", str(remote))
    _git(live, "push", "-q", "origin", "HEAD:main")
    _git(live, "update-ref", "refs/remotes/origin/main", c1)  # 로컬 origin/main = 낡은 판(fetch 전)
    seed = tmp_path / "seed"
    subprocess.run(["git", "clone", "-q", str(remote), str(seed)], check=True)
    _git(seed, "config", "user.email", "t@t")
    _git(seed, "config", "user.name", "t")
    (seed / REL).write_text("원장 B\n", encoding="utf-8")
    _git(seed, "add", "-A")
    _git(seed, "commit", "-qm", "[docs] 원장 B")
    _git(seed, "push", "-q", "origin", "HEAD:main")
    c2 = _git(seed, "rev-parse", "HEAD")

    root = tmp_path / "root"
    (root / ".fable-team").mkdir(parents=True, exist_ok=True)
    (root / ".fable-team" / "LIVE_ROOT").write_text(str(live) + "\n", encoding="utf-8")  # 기본 경로 = env FT_LEDGER_REPO 없음
    news = tmp_path / "news"
    news.mkdir()
    state = root / ".fable-team" / "state" / "news-ledger"
    state.mkdir(parents=True, exist_ok=True)
    (state / "last.sha").write_text(c1 + "\n", encoding="utf-8")
    (state / "last.blob").write_text(c1 + "\n", encoding="utf-8")  # r907 r4: 판정 키 = 원장 경로를 건드린 «채움 아닌» 마지막 커밋 sha(옛 값 = 원장 블롭)
    (state / "html.json").write_text(json.dumps({"at": "2026-10-23 09:00", "map_at": "2026-10-23 09:00", "link": "http://x/0"}), encoding="utf-8")

    made, lines = [], []
    monkeypatch.setattr(fh, "build", lambda *a: {"goals": [], "live": []})
    monkeypatch.setattr(fh, "run_files", lambda d, out, now: (made.append(now), (out / "a.html", out / "a.txt"))[1])
    monkeypatch.setattr(fh, "publish_files", lambda h, s, now: (0, {"ts": str(len(made)), "link": f"http://x/{len(made)}"}))
    monkeypatch.setattr(fp, "publish_line", lambda text, now: (lines.append(text), 0)[1])
    monkeypatch.setattr(fp, "retry_attach", lambda now: None)
    monkeypatch.setattr(fh, "_canon_sha", lambda: "")  # r737 정본 판정은 이 카드 밖 — 변화 판정은 원장 블롭만

    monkeypatch.setenv("FT_NEWS_MODE", "html")
    monkeypatch.setenv("FT_LEDGER_PATH", REL)
    monkeypatch.setenv("FT_NEWS_DIR", str(news))
    monkeypatch.setenv("FT_NEWS_NOW", "2026-10-23 09:40")
    monkeypatch.setenv("FT_NEWS_REPEAT_MIN", "30")
    monkeypatch.setenv("FT_NEWS_FETCH_MIN", "0")  # FETCH_HEAD mtime 과 무관하게 «받기» 를 세도록
    monkeypatch.setenv("FT_NEWS_STATUS_INTERVAL", "0")
    monkeypatch.setenv("FT_LEDGER_SYNC_STAMP", str(tmp_path / "sync.ts"))
    monkeypatch.setenv("FT_LEDGER_SYNCED", "")  # sync_repo 의 «같은 틱 1회» 를 리셋(테스트 간 누출 0)
    for k in ("FT_LEDGER_REPO", "FT_LEDGER_SYNC_ERROR", "FT_NEWS_HEAD", "FT_LEDGER_FETCH", "FT_LEDGER_SYNC", "FT_NEWS_MAIN_REF"):
        monkeypatch.delenv(k, raising=False)
    return {"tmp": tmp_path, "root": root, "live": live, "remote": remote, "state": state,
            "news": news, "made": made, "lines": lines, "c1": c1, "c2": c2}


def _assert_fetch_then_new_map(w, counter: Path, n: int = 1) -> None:
    """ⓐ 의 단정 — 받기 n회 · 새 원장 판 기준 지도 1장 · «변화 없음» 줄 0 · 기준선 전진."""
    assert fl._run(w["root"], w["state"]) == (0, "지도 발행")
    assert _count(counter) == n
    assert len(w["made"]) == 1 and w["lines"] == []
    assert _git(w["live"], "rev-parse", "origin/main") == w["c2"]
    assert (w["state"] / "last.sha").read_text(encoding="utf-8").strip() == w["c2"]


def _assert_unjudgeable(w) -> None:
    """ⓑ 의 단정 — r907 r2: 판정 불가 = 게시 0(«판정 불가» 줄도 «변화 없음» 줄도 안 낸다) · 지도 0 · rc1 은 부르는 쪽이 본다."""
    assert w["lines"] == [] and w["made"] == []


# ── ⓐ 기본 경로(env 없음)도 리포를 먼저 정하고 받는다 ────────────────

def test_a_default_repo_env_missing_still_fetches(world, tmp_path, monkeypatch):
    """ⓐ FT_LEDGER_REPO 없음 = LIVE_ROOT 리포를 «받기 전에» 정하고 받는다 — 새 판 기준 지도 1장(옛 판 = 받기 0 · «변화 없음»)."""
    stub, counter = _stub(tmp_path, monkeypatch, FETCH_OK)
    monkeypatch.setenv("FT_LEDGER_FETCH", str(stub))
    _assert_fetch_then_new_map(world, counter)


# ── ⓑ 받기 실패 = «판정 불가» 머리 줄 ────────────────────────────────

def test_b_fetch_failure_publishes_unjudgeable_line(world, tmp_path, monkeypatch):
    """ⓑ 받기 실패면 «변화 없음» 이 아니라 «판정 불가 — 원장 ref fetch 실패 …» — 낡은 판을 «변화 0» 으로 읽지 않는다."""
    stub, counter = _stub(tmp_path, monkeypatch, FETCH_FAIL)
    monkeypatch.setenv("FT_LEDGER_FETCH", str(stub))
    assert fl._run(world["root"], world["state"]) == (1, "원장 ref fetch 실패")  # r907 r2: rc1 = launchd 종료 코드 → check_stale 정지 경보
    assert _count(counter) >= 1  # 재시도 규칙은 이 카드 밖 — 1회 이상이면 받기 시도는 한 것
    _assert_unjudgeable(world)


# ── ⓒ env 로 리포를 준 꼴(라이브 지금) = 결과 같음 ───────────────────

def test_c_explicit_repo_env_same_result(world, tmp_path, monkeypatch):
    """ⓒ FT_LEDGER_REPO 있는 꼴 = 지금 라이브 — 받기 1회 · 새 판 기준 지도 1장(고치기 전과 같은 결과)."""
    stub, counter = _stub(tmp_path, monkeypatch, FETCH_OK)
    monkeypatch.setenv("FT_LEDGER_FETCH", str(stub))
    monkeypatch.setenv("FT_LEDGER_REPO", str(world["live"]))
    _assert_fetch_then_new_map(world, counter)


# ── ⓓ 받기 성공 + 원격 = 로컬 = 기준선 → «변화 없음» 그대로 ──────────

def test_d_fetch_ok_and_no_new_commit_keeps_change_line(world, tmp_path, monkeypatch):
    """ⓓ 원격이 로컬·기준선과 같으면 «변화 없음» 줄 그대로(정상 오판 0 · «판정 불가» 0)."""
    _git(world["remote"], "update-ref", "refs/heads/main", world["c1"])  # 원격 = 로컬
    stub, counter = _stub(tmp_path, monkeypatch, FETCH_OK)
    monkeypatch.setenv("FT_LEDGER_FETCH", str(stub))
    monkeypatch.setenv("FT_LEDGER_REPO", str(world["live"]))
    assert fl._run(world["root"], world["state"]) == (0, "원장 커밋 0")
    assert _count(counter) == 0 and world["made"] == []  # r847: ls-remote 원격 == origin/main → 받기 0(옛 판 = 1)
    assert world["lines"] == ["[뉴스 09:40] 변화 없음 · 지도 http://x/0"]


# ── ⓔ 옛 판(FT_NEWS_MODE 없음) = sync_repo() 그대로 ─────────────────

def test_e_old_mode_path_still_calls_sync_repo(world, tmp_path, monkeypatch):
    """ⓔ 모드 없음 = 옛 판 경로 — sync_repo 1회 · 원장 ref 받기 스텁 0(동작 무변경)."""
    monkeypatch.delenv("FT_NEWS_MODE", raising=False)
    sync_stub, sync_counter = _stub(tmp_path, monkeypatch, 'echo x >> "$CNT"\necho "사본 동기화 ok"\nexit 0\n', name="sync")
    fetch_stub, fetch_counter = _stub(tmp_path, monkeypatch, FETCH_OK, name="fetch")
    monkeypatch.setenv("FT_LEDGER_SYNC", str(sync_stub))
    monkeypatch.setenv("FT_LEDGER_FETCH", str(fetch_stub))
    monkeypatch.setenv("FT_LEDGER_REPO", str(world["live"]))
    assert fl._run(world["root"], world["state"]) == (0, "원장 커밋 0")
    assert _count(sync_counter) == 1 and _count(fetch_counter) == 0
    assert world["made"] == [] and world["lines"] == []


# ── ⓖ 변이 = 조건의 몫 ───────────────────────────────────────────────

def test_g1_mutation_skipping_fetch_falls_back_to_change_line(world, tmp_path, monkeypatch):
    """ⓖ① 받기를 건너뛰면(옛 판) ⓐ 단정이 깨진다 — «새 판 기준 지도» 를 만드는 것은 받기다."""
    stub, counter = _stub(tmp_path, monkeypatch, FETCH_OK)
    monkeypatch.setenv("FT_LEDGER_FETCH", str(stub))
    monkeypatch.setattr(fl, "fetch_if_stale", lambda repo: "")  # 변이 = 받기 0
    with pytest.raises(AssertionError):
        _assert_fetch_then_new_map(world, counter)


def _mutated_html(tmp_path, old: str, new: str):
    """r907 r3 — 변이 모듈(소스 한 줄 바꿔 exec) — «변이를 실제로 넣고 빨강 확인» 하기 위한 도구."""
    src = (BIN / "ft_news_html.py").read_text(encoding="utf-8")
    assert src.count(old) == 1, src.count(old)
    f = tmp_path / "ft_news_html_mut.py"
    f.write_text(src.replace(old, new), encoding="utf-8")
    spec = importlib.util.spec_from_file_location("ft_news_html_mut", f)
    mod = importlib.util.module_from_spec(spec)
    sys.modules["ft_news_html_mut"] = mod
    spec.loader.exec_module(mod)
    return mod


def test_g2_mutation_unjudgeable_publish_revival_makes_b_red(world, tmp_path, monkeypatch):
    """ⓖ② 변이 = «판정 불가» 갈래에 게시를 되살리면(r907 r2 코드로 되돌림) ⓑ 단정(게시 0)이 빨강 — 조건의 몫."""
    stub, counter = _stub(tmp_path, monkeypatch, FETCH_FAIL)
    monkeypatch.setenv("FT_LEDGER_FETCH", str(stub))
    mut = _mutated_html(tmp_path, '        return 1, "원장 ref fetch 실패"\n',
                        '        __import__("ft_news_publish").publish_line(zero_change_line(now, last, warn), now)\n'
                        '        return 0, "원장 ref fetch 실패"\n')
    monkeypatch.setattr(fh, "tick", mut.tick)  # _run 은 «from ft_news_html import tick» 로 이 이름을 쓴다
    assert fl._run(world["root"], world["state"]) == (0, "원장 ref fetch 실패")  # 변이 판 = 한 줄 게시
    assert world["lines"]  # 옛 판처럼 «판정 불가» 1줄
    with pytest.raises(AssertionError):
        _assert_unjudgeable(world)
    monkeypatch.undo()


# ── ⓗ 격리 ───────────────────────────────────────────────────────────

def test_h_isolation_temp_git_and_fake_publishers(world):
    """ⓗ 실 원격·실 원장·실 슬랙·실 mbox 0 — 리포는 임시 폴더, 발행기·지도 생성은 가짜."""
    assert world["remote"].parent == world["tmp"] and world["live"].parent == world["tmp"]
    assert fh.publish_files.__name__ == "<lambda>" and fp.publish_line.__name__ == "<lambda>"
    assert not Path("/tmp/byz-ft-news-planner.log") == world["state"]
