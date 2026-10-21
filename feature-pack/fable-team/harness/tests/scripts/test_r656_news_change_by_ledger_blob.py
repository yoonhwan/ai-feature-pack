"""r656 — 뉴스 «변화 판정»이 원장 내용이 아니라 origin/main 머리 커밋으로 되던 결함(실측 80분 26회 발행 vs 원장 커밋 1~2)
→ 판정 = `<cur>:<원장>` 블롭 대 상태 파일(state/last.blob) · 기준선 커밋(last.sha = 최근 커밋 칸)은 그대로.

ⓐ 지금 판: 원장 안 바뀌고 다른 경로 커밋 3개 → 틱 3회 = 지도 3장(FAIL 기대 = 0장 · «변화 없음» 줄만)
ⓑ 고친 판 같은 입력 → 지도 0 · LLM 0 · 반복 줄 규칙(FT_NEWS_REPEAT_MIN) 그대로
ⓒ 원장 내용 커밋 1 → 지도 1 · 그 지도의 최근 커밋 칸 = 직전 지도 이후 main 커밋 전부(다른 경로 3개 포함)
ⓓ 원장 경로 커밋이지만 블롭 같음(되돌림 두 번) → 지도 0
ⓔ 하루 첫 틱(오늘 지도 없음)은 원장 그대로여도 지도 1
ⓕ 기준 블롭 상태 파일 없음(설치 직후)·깨짐 → 지도 1 + 상태 새로 씀 · 원장 파일이 cur 에 없음 → 지금처럼 rc1
ⓖ 옛 모드(FT_NEWS_MODE 없음) 판 = 그 경로 마지막 커밋 그대로 · html 분기 1곳 그대로

임시 git 리포 + 가짜 발행기·가짜 build/run_files — 실 Slack·실 opencode·실 tmux 0.
실행: cd harness && PYTHONPATH=bin:kit/fable-team/bin python3.11 -m pytest tests/scripts/test_r656_news_change_by_ledger_blob.py -q
"""
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


def _commit(repo: Path, rel: str, text: str, msg: str) -> str:
    p = repo / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8")
    _git(repo, "add", ".")
    _git(repo, "commit", "-qm", msg)
    return _git(repo, "rev-parse", "HEAD")


def _del(repo: Path, rel: str, msg: str) -> str:
    _git(repo, "rm", "-q", rel)
    _git(repo, "commit", "-qm", msg)
    return _git(repo, "rev-parse", "HEAD")


@pytest.fixture
def env(tmp_path, monkeypatch):
    """(root, repo, state, news) + 가짜 발행기·가짜 build/run_files. made = 지도 만든 시각들."""
    repo = tmp_path / "repo"
    repo.mkdir()
    _git(repo, "init", "-q")
    _git(repo, "config", "user.email", "t@t")
    _git(repo, "config", "user.name", "t")
    root = tmp_path / "root"
    state, news = root / ".fable-team" / "state" / "news-ledger", root / "news"
    made: list = []
    monkeypatch.setattr(fh, "build", lambda *a: {"goals": [], "live": []})
    monkeypatch.setattr(fh, "run_files", lambda d, out, now: (made.append(now), (out / "a.html", out / "a.txt"))[1])
    monkeypatch.setattr(fh, "publish_files", lambda h, s, now: (0, {"ts": str(len(made)), "link": f"http://x/{len(made)}"}))
    lines: list = []
    monkeypatch.setattr(fp, "publish_line", lambda text, now: (lines.append(text), 0)[1])
    monkeypatch.setattr(fp, "retry_attach", lambda now: None)
    monkeypatch.setenv("FT_NEWS_MAIN_REF", "HEAD")  # 최근 커밋 칸 = 이 리포 HEAD(origin 없음)
    monkeypatch.setenv("FT_NEWS_REPEAT_MIN", "100000")  # 반복 줄 없이 «변화 0» 만 보는 기본
    for k in ("FT_NEWS_MODE", "FT_LEDGER_SYNC_ERROR", "FT_NEWS_HEAD"):
        monkeypatch.delenv(k, raising=False)
    return root, repo, state, news, made, lines


def _base(state: Path) -> str:
    f = state / "last.sha"
    return f.read_text(encoding="utf-8").strip() if f.is_file() else ""


def _tick(env, cur: str, base: str | None = None):
    root, repo, state, news, _made, _lines = env
    return fh.tick(root, state, repo, REL, news, _base(state) if base is None else base, cur)


def _at(monkeypatch, stamp: str) -> None:
    monkeypatch.setenv("FT_NEWS_NOW", stamp)


# ── ⓐ 지금 판: 다른 경로 커밋만 3개 = 지도 0장 ────────────────────────

def test_a_unrelated_main_commits_make_no_new_map(env, monkeypatch):
    """ⓐ 설치 직후 지도 1(ⓕ) · 그 뒤 원장 안 바뀐 main 커밋 3개 = 지도 0 · «원장 커밋 0» 만."""
    _at(monkeypatch, "2026-10-21 09:00")
    made = env[4]
    c1 = _commit(env[1], REL, "원장 A\n", "[docs] 원장")
    assert _tick(env, c1, base="") == (0, "지도 발행") and len(made) == 1
    got = [_tick(env, _commit(env[1], f"other/f{i}.txt", "x\n", f"[docs] 다른 경로 {i}")) for i in range(3)]
    assert len(made) == 1  # 전 판 = 지도 3장(원장 커밋 0 · LLM 12회)
    assert got == [(0, "원장 커밋 0")] * 3
    assert (env[2] / "last.sha").read_text().strip() == c1 and (env[2] / "last.blob").is_file()  # 기준선은 지도 발행 때만 전진


# ── ⓑ 반복 줄 규칙 그대로 ─────────────────────────────────────────────

def test_b_change_zero_keeps_repeat_line_rule(env, monkeypatch):
    """ⓑ 변화 0 = FT_NEWS_REPEAT_MIN 안 «0줄» · 넘으면 «변화 없음» 1줄 · 지도·LLM 0."""
    _at(monkeypatch, "2026-10-21 09:00")
    made, lines = env[4], env[5]
    c1 = _commit(env[1], REL, "원장 A\n", "[docs] 원장")
    assert _tick(env, c1, base="")[0] == 0
    monkeypatch.setenv("FT_NEWS_REPEAT_MIN", "30")
    cur = _commit(env[1], "other/x.txt", "x\n", "[docs] 다른 경로")
    _at(monkeypatch, "2026-10-21 09:20")
    assert _tick(env, cur) == (0, "원장 커밋 0") and lines == [] and len(made) == 1  # 30분 안 = 줄 0
    _at(monkeypatch, "2026-10-21 09:40")
    assert _tick(env, cur) == (0, "원장 커밋 0") and len(lines) == 1 and lines[0].startswith("[뉴스 09:40] 변화 없음 · 지도 ")
    _at(monkeypatch, "2026-10-21 09:50")
    assert _tick(env, cur) == (0, "원장 커밋 0") and len(lines) == 1 and len(made) == 1  # 30분 안 다시 0줄


# ── ⓒ 원장 내용 커밋 = 지도 1 · 최근 커밋 칸은 그대로 ─────────────────

def test_c_ledger_content_commit_makes_one_map_and_commits_span_from_last_map(env, monkeypatch):
    """ⓒ 원장 내용 커밋 1 → 지도 1 · 최근 커밋 칸 = 직전 지도 기준선 이후 main 커밋 전부(다른 경로 포함)."""
    _at(monkeypatch, "2026-10-21 09:00")
    made = env[4]
    c1 = _commit(env[1], REL, "원장 A\n", "[docs] 원장 A")
    assert _tick(env, c1, base="")[0] == 0
    for i in range(3):
        _commit(env[1], f"other/f{i}.txt", "x\n", f"[docs] 다른 경로 {i}")
    before = _base(env[2])
    c5 = _commit(env[1], REL, "원장 B — 새 지시\n", "[docs] 원장 B")
    _at(monkeypatch, "2026-10-21 09:10")
    assert _tick(env, c5) == (0, "지도 발행") and len(made) == 2
    rows = fh.commits(env[1], before)  # 지도 «최근 커밋» 칸이 쓰는 그 함수
    assert len(rows) == 4 and rows[0].endswith("[docs] 원장 B") and sum("다른 경로" in r for r in rows) == 3
    assert _base(env[2]) == c5 and (env[2] / "last.blob").read_text().strip() == _git(env[1], "rev-parse", f"{c5}:{REL}")


# ── ⓓ 원장 경로 커밋이지만 블롭 같음 = 지도 0 ────────────────────────

def test_d_ledger_commit_with_same_blob_makes_no_map(env, monkeypatch):
    """ⓓ 되돌림 두 번(A→B→A) = 발행 0 — 판정이 커밋이 아니라 내용이라는 증거."""
    _at(monkeypatch, "2026-10-21 09:00")
    made = env[4]
    c1 = _commit(env[1], REL, "원장 A\n", "[docs] 원장 A")
    assert _tick(env, c1, base="")[0] == 0 and len(made) == 1
    _commit(env[1], REL, "원장 B\n", "[docs] 원장 B")
    back = _commit(env[1], REL, "원장 A\n", "[docs] 원장 A 되돌림")
    _at(monkeypatch, "2026-10-21 09:20")
    assert _tick(env, back) == (0, "원장 커밋 0") and len(made) == 1


# ── ⓔ 하루 첫 틱 = 원장 그대로여도 지도 1 ───────────────────────────

def test_e_first_tick_of_day_publishes_even_without_change(env, monkeypatch):
    """ⓔ 오늘 지도 없음 = 지도 1(지금 규칙 유지) · 상태는 그대로 전진."""
    _at(monkeypatch, "2026-10-21 09:00")
    made = env[4]
    c1 = _commit(env[1], REL, "원장 A\n", "[docs] 원장 A")
    assert _tick(env, c1, base="")[0] == 0 and len(made) == 1
    _at(monkeypatch, "2026-10-22 08:01")
    assert _tick(env, c1) == (0, "지도 발행") and len(made) == 2


# ── ⓕ 상태 파일 없음·깨짐 = 지도 1 · 원장 없음 = rc1 ────────────────

def test_f_missing_or_broken_blob_state_publishes_and_rewrites_state(env, monkeypatch):
    """ⓕ 블롭 상태 파일 없음·깨짐 = 지도 1 + 상태 새로 씀(조용한 0 발행 0)."""
    _at(monkeypatch, "2026-10-21 09:00")
    made = env[4]
    c1 = _commit(env[1], REL, "원장 A\n", "[docs] 원장 A")
    assert _tick(env, c1, base="")[0] == 0 and len(made) == 1
    cur = _commit(env[1], "other/x.txt", "x\n", "[docs] 다른 경로")
    blob = (env[2] / "last.blob").read_text()
    for garbage in ("", "깨진 값\n", blob[:10] + "\n"):
        (env[2] / "last.blob").write_text(garbage, encoding="utf-8")
        _at(monkeypatch, "2026-10-21 10:0%d" % len(made))
        assert _tick(env, cur) == (0, "지도 발행")
        assert (env[2] / "last.blob").read_text().strip() == _git(env[1], "rev-parse", f"{cur}:{REL}")
    assert len(made) == 4


def test_f_ledger_missing_in_cur_is_rc1_without_publish(env, monkeypatch):
    """ⓕ 원장 파일이 cur 에 없음 = 지금처럼 rc1(발행 0 · 기준선 그대로)."""
    _at(monkeypatch, "2026-10-21 09:00")
    made = env[4]
    c1 = _commit(env[1], REL, "원장 A\n", "[docs] 원장 A")
    assert _tick(env, c1, base="")[0] == 0
    gone = _del(env[1], REL, "[docs] 원장 지움")
    monkeypatch.setattr(fh, "build", lambda *a: (_ for _ in ()).throw(RuntimeError(f"git show 실패: {REL}")))  # 진짜 build = `git show <cur>:<원장>` 실패
    _at(monkeypatch, "2026-10-21 09:30")
    assert _tick(env, gone)[0] == 1 and len(made) == 1 and _base(env[2]) == c1


# ── ⓖ 옛 모드 그대로 ────────────────────────────────────────────────

def test_g_old_mode_cur_is_last_path_commit_not_ref_head(env, monkeypatch):
    """ⓖ FT_NEWS_MODE 없음 = 판정 기준(그 경로 마지막 커밋) 그대로 · 다른 경로 커밋에 흔들리지 않는다."""
    c1 = _commit(env[1], REL, "원장 A\n", "[docs] 원장 A")
    cur = _commit(env[1], "other/x.txt", "x\n", "[docs] 다른 경로")
    assert fl.news_cur(env[1], REL) == c1 != cur
    monkeypatch.setenv("FT_NEWS_MODE", "html")
    assert fl.news_cur(env[1], REL) == cur  # html 모드 = ref 머리(r563 그대로)


def test_g_html_branch_calls_tick_once_and_state_is_two_cells(env):
    """ⓖ html 분기 1곳 그대로 · 기준선 = 두 칸(last.sha · last.blob) 이름이 코드에 있다."""
    src = (BIN / "ft_news_ledger.py").read_text(encoding="utf-8")
    assert src.count('if os.environ.get("FT_NEWS_MODE") == "html":') == 1 and src.count("return tick(") == 1
    html_src = (BIN / "ft_news_html.py").read_text(encoding="utf-8")
    assert '"last.blob"' in html_src and '"last.sha"' in html_src
