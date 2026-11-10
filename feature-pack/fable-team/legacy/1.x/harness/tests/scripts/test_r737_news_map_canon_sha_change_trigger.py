"""r737 — 뉴스 지도 «다시 낼까» 판정이 원장 블롭만 보고 골 정본은 안 봐서, 정본만 바뀐 커밋(원장 그대로)이면 지도가 옛 골로 남던 구멍.
→ 판정 = 원장 블롭(r656 그대로) **또는** 골 정본 «내용» sha 가 상태(state/last.canon)와 다름.

ⓐ 정본만 바뀐 커밋(원장 블롭 같음) → 지도 1 (FAIL 기대: 지금 판 = «원장 커밋 0» 0장)
ⓑ 저장 상태에 정본 sha 칸(last.canon) = 정본 내용 sha256 앞10
ⓒ 정본·원장 둘 다 무변경 커밋 → 지도 0 (r656 회귀 0)
ⓓ 옛 상태 파일(정본 칸 없음) → 첫 판 1회 지도 1 뒤 정상(옛 상태 읽기 실패 0)
ⓔ 기존 시험 그대로 PASS (이 파일 밖 · ⓔ 목록은 증거에)
ⓕ 변이: 정본 sha 판정을 없애면 ⓐ② 이 다시 «변화 0» 으로 돌아간다(조건이 실제로 잡고 있다는 증거)
ⓖ 격리 = 임시 리포·임시 루트 · 가짜 발행기(실 Slack·실 LLM·실 게시 0)

실행: cd harness && PYTHONPATH=bin:kit/fable-team/bin python3.11 -m pytest tests/scripts/test_r737_news_map_canon_sha_change_trigger.py -q
"""
import hashlib
import subprocess
import sys
from pathlib import Path

import pytest

BIN = Path(__file__).resolve().parents[3] / "harness" / "bin"
sys.path[:0] = [str(BIN)]
from real_state_guard import guard_begin_module  # noqa: E402,F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

import ft_news_html as fh  # noqa: E402
import ft_news_publish as fp  # noqa: E402

LEDGER = "design/planner/PLAN-oppa-ledger.md"
CANON = "design/harness/AUTONOMY-GOAL-A6-20261018.md"


def _git(repo: Path, *a: str) -> str:
    return subprocess.run(["git", "-C", str(repo), *a], check=True, capture_output=True, text=True).stdout.strip()


def _commit(repo: Path, files: dict[str, str], msg: str) -> str:
    for rel, text in files.items():
        p = repo / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8")
    _git(repo, "add", "-A")
    _git(repo, "commit", "-qm", msg)
    return _git(repo, "rev-parse", "HEAD")


def _sha10(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:10]


@pytest.fixture
def env(tmp_path, monkeypatch):
    """(root, repo, state, news, made, canon 경로) + 가짜 발행기·가짜 build/run_files. made = 지도 만든 시각들."""
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
    monkeypatch.setenv("FT_GOAL_A6_MD", str(repo / CANON))  # 정본 = 임시 리포 파일(file: 꼴 · gitref 아님)
    monkeypatch.setenv("FT_GOAL_REPO", str(repo))
    for k in ("FT_NEWS_MODE", "FT_LEDGER_SYNC_ERROR", "FT_NEWS_HEAD"):
        monkeypatch.delenv(k, raising=False)
    return root, repo, state, news, made, lines


def _base(state: Path) -> str:
    f = state / "last.sha"
    return f.read_text(encoding="utf-8").strip() if f.is_file() else ""


def _tick(env, cur: str, base: str | None = None):
    root, repo, state, news, _made, _lines = env
    return fh.tick(root, state, repo, LEDGER, news, _base(state) if base is None else base, cur)


def _at(monkeypatch, stamp: str) -> None:
    monkeypatch.setenv("FT_NEWS_NOW", stamp)


# ── ⓐ 정본만 바뀐 커밋 = 지도 1 ──────────────────────────────────────

def test_a_canon_only_commit_makes_one_map(env, monkeypatch):
    """ⓐ① 정본+원장 커밋 = 지도 1 → ② 정본만 커밋(원장 블롭 같음) = 지도 1 (지금 판은 0장 = FAIL)."""
    _at(monkeypatch, "2026-10-22 09:00")
    made = env[4]
    c1 = _commit(env[1], {LEDGER: "원장 A\n", CANON: "정본 A\n"}, "[docs] 정본+원장")
    assert _tick(env, c1, base="") == (0, "지도 발행") and len(made) == 1
    c2 = _commit(env[1], {CANON: "정본 B — 골 하나 늘림\n"}, "[docs] 정본만")
    _at(monkeypatch, "2026-10-22 09:10")
    assert _tick(env, c2) == (0, "지도 발행") and len(made) == 2
    assert _git(env[1], "rev-parse", f"{c1}:{LEDGER}") == _git(env[1], "rev-parse", f"{c2}:{LEDGER}")  # 원장 블롭은 같다


# ── ⓑ 저장 상태에 정본 sha 칸 ────────────────────────────────────────

def test_b_state_records_canon_content_sha(env, monkeypatch):
    """ⓑ 지도가 올라간 뒤 state/last.canon = 그때 정본 «내용» sha256 앞10 (지도 발행 때만 전진)."""
    _at(monkeypatch, "2026-10-22 09:00")
    made = env[4]
    c1 = _commit(env[1], {LEDGER: "원장 A\n", CANON: "정본 A\n"}, "[docs] 정본+원장")
    assert _tick(env, c1, base="")[0] == 0 and len(made) == 1
    assert (env[2] / "last.canon").read_text(encoding="utf-8").strip() == _sha10("정본 A\n")
    busy = _commit(env[1], {"other/x.txt": "x\n"}, "[docs] 다른 경로")  # 지도 0 → 정본 칸 그대로
    _at(monkeypatch, "2026-10-22 09:05")
    assert _tick(env, busy) == (0, "원장 커밋 0") and len(made) == 1
    assert (env[2] / "last.canon").read_text(encoding="utf-8").strip() == _sha10("정본 A\n")


# ── ⓒ 정본·원장 무변경 커밋 = 지도 0 (r656 회귀 0) ───────────────────

def test_c_unrelated_commit_makes_no_map(env, monkeypatch):
    """ⓒ 원장·정본 둘 다 그대로인 커밋 3개 = 지도 0 · «원장 커밋 0» 만."""
    _at(monkeypatch, "2026-10-22 09:00")
    made = env[4]
    c1 = _commit(env[1], {LEDGER: "원장 A\n", CANON: "정본 A\n"}, "[docs] 정본+원장")
    assert _tick(env, c1, base="")[0] == 0 and len(made) == 1
    for i in range(3):
        cur = _commit(env[1], {f"other/f{i}.txt": "x\n"}, f"[docs] 다른 경로 {i}")
        _at(monkeypatch, "2026-10-22 09:0%d" % (i + 1))
        assert _tick(env, cur) == (0, "원장 커밋 0")
    assert len(made) == 1


# ── ⓓ 옛 상태 파일(정본 칸 없음) = 첫 판 1회 뒤 정상 ─────────────────

def test_d_old_state_without_canon_cell_republishes_once(env, monkeypatch):
    """ⓓ last.canon 없는 옛 상태 = 첫 틱 1회 지도(정본 칸 새로 씀) → 다음 틱 «변화 0»(읽기 실패 0)."""
    _at(monkeypatch, "2026-10-22 09:00")
    made = env[4]
    c1 = _commit(env[1], {LEDGER: "원장 A\n", CANON: "정본 A\n"}, "[docs] 정본+원장")
    assert _tick(env, c1, base="")[0] == 0 and len(made) == 1
    (env[2] / "last.canon").unlink()  # 설치 직후 옛 상태 파일 꼴
    _at(monkeypatch, "2026-10-22 09:10")
    assert _tick(env, c1) == (0, "지도 발행") and len(made) == 2
    assert (env[2] / "last.canon").read_text(encoding="utf-8").strip() == _sha10("정본 A\n")
    _at(monkeypatch, "2026-10-22 09:20")
    assert _tick(env, c1) == (0, "원장 커밋 0") and len(made) == 2


# ── ⓕ 변이: 정본 sha 판정을 없애면 ⓐ② 이 다시 «변화 0» ──────────────

def test_f_mutation_without_canon_sha_misses_canon_only_commit(env, monkeypatch):
    """ⓕ 정본 sha 를 «못 읽음»(=그 조건 없음)으로 두면 정본만 바뀐 커밋이 «원장 커밋 0» 으로 샌다 — 조건의 몫."""
    _at(monkeypatch, "2026-10-22 09:00")
    made = env[4]
    c1 = _commit(env[1], {LEDGER: "원장 A\n", CANON: "정본 A\n"}, "[docs] 정본+원장")
    assert _tick(env, c1, base="")[0] == 0 and len(made) == 1
    monkeypatch.setattr(fh, "_canon_sha", lambda: "")  # 변이 = 정본 sha 못 읽음
    c2 = _commit(env[1], {CANON: "정본 B\n"}, "[docs] 정본만")
    _at(monkeypatch, "2026-10-22 09:10")
    assert _tick(env, c2) == (0, "원장 커밋 0") and len(made) == 1


# ── 정본 못 읽음 = 판정 0(뉴스 틱 안 죽는다) ────────────────────────

def test_canon_unreadable_keeps_ledger_judgment(env, monkeypatch, caplog):
    """정본 파일이 없어도 틱은 살아 있다 — 원장 블롭 판정(r656)만으로 동작 · 예외 0 · 그 사실은 ERROR 로그 1줄(r737 arch §199)."""
    _at(monkeypatch, "2026-10-22 09:00")
    made = env[4]
    c1 = _commit(env[1], {LEDGER: "원장 A\n", CANON: "정본 A\n"}, "[docs] 정본+원장")
    assert _tick(env, c1, base="")[0] == 0 and len(made) == 1
    (env[1] / CANON).unlink()  # 정본 사라짐(작업 트리) → load_canon 실패
    c2 = _commit(env[1], {LEDGER: "원장 B\n"}, "[docs] 원장 B")
    _at(monkeypatch, "2026-10-22 09:10")
    assert _tick(env, c2) == (0, "지도 발행") and len(made) == 2
    assert any(r.levelname == "ERROR" and "골 정본 못 읽음" in r.getMessage() for r in caplog.records)  # 조용한 info 아님
