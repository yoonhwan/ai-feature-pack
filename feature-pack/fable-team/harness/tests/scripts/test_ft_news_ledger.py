"""R125 오빠 원장 한 파일 기준 뉴스 — 줄 키 나누기 · 바뀐 줄만 · 기준선 · 알림 · 매거진 연결 (판정 1437).

원장 실물 사본 tests/scripts/fixtures/PLAN-oppa-ledger.md(칸 넷 + 발주 칸) + 고친 픽스처 · 격리 임시 git 저장소 · Slack/mbox 대역.
실행: python3 -m pytest tests/scripts/test_ft_news_ledger.py -q
"""
import re
import subprocess
import sys
from pathlib import Path

import pytest
import _magazine_fakes  # noqa: F401 — slack-mirror 경로를 sys.path 에 올린다

ROOT = Path(__file__).resolve().parents[3]
BIN = ROOT / "harness" / "bin"
KIT = ROOT / "harness" / "kit" / "slack-mirror"
sys.path.insert(0, str(BIN))

import ft_news_ledger as nl  # noqa: E402
import magazine_doc as md  # noqa: E402
import magazine_doc_md as dm  # noqa: E402
from test_ft_news_publish import FakeSlack  # noqa: E402
from real_state_guard import guard_begin_module  # noqa: E402,F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

REAL = (Path(__file__).parent / "fixtures" / "PLAN-oppa-ledger.md").read_text(encoding="utf-8")
REL = "design/planner/PLAN-oppa-ledger.md"
PATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
ROW_OLD = "|  | 가입 메일 템플릿 13종 | 코드 | 완료 |  |"
ROW_NEW = "|  | 가입 메일 템플릿 13종 | 코드 | 진행 — 다시 손봄 |  |"
ROW_ADDED = "|  | 신규 확인 요청 하나 | 문서 | 미착수 |  |"
STUB = '#!/usr/bin/env bash\necho "$1" >> "$FT_STUB_LOG"\ncat "$1" >> "$FT_STUB_LOG"\nexit "${FT_STUB_RC:-0}"\n'


def git(repo: Path, *a: str) -> str:
    return subprocess.run(["git", "-C", str(repo), "-c", "user.name=t", "-c", "user.email=t@t", *a], check=True, capture_output=True, text=True).stdout.strip()


def commit(repo: Path, text: str) -> str:
    f = repo / REL
    f.parent.mkdir(parents=True, exist_ok=True)
    f.write_text(text, encoding="utf-8")
    git(repo, "add", REL)
    git(repo, "commit", "-q", "-m", "ledger")
    return git(repo, "rev-parse", "HEAD")


@pytest.fixture
def env(tmp_path, monkeypatch):
    repo = tmp_path / "ledger-repo"
    repo.mkdir()
    git(repo, "init", "-q")
    (repo / "design").mkdir()  # R383: planner 폴더는 design/TEAMS.md 로 푼다(ft_team_lib) — 꼴1 `design/planner/` 한 행
    (repo / "design" / "TEAMS.md").write_text("| 팀 | 폴더 | 팀장 | 상태 |\n|---|---|---|---|\n| planner | `design/planner/` | planner#9 | 현역 |\n", encoding="utf-8")
    root = tmp_path / "root"
    (root / ".fable-team" / "comm").mkdir(parents=True)
    (root / ".fable-team" / "seats-planner.json").write_text('{"_master": "planner#9"}', encoding="utf-8")
    stub, mbox = tmp_path / "pub.sh", root / ".fable-team" / "comm" / "mbox.sh"
    stub.write_text(STUB, encoding="utf-8")
    mbox.write_text('#!/usr/bin/env bash\necho "$@" >> "$FT_MBOX_LOG"\n', encoding="utf-8")
    for k, v in {"FT_ROOT": root, "FT_LEDGER_REPO": repo, "FT_NEWS_DIR": root / "news", "FT_NEWS_PUBLISH": f"bash {stub}",
                 "FT_STUB_LOG": tmp_path / "stub.log", "FT_MBOX_LOG": tmp_path / "mbox.log", "FT_NEWS_NOW": "2026-10-13 15:00",
                 "FT_LEDGER_SYNCED": "1", "FT_LEDGER_SYNC_MIN": "0"}.items():  # r503 사본 전진은 test_ledger_repo_sync.sh 몫(2분 건너뜀 = r563 시험이 봄 — 여기선 매번)
        monkeypatch.setenv(k, str(v))
    monkeypatch.delenv("FT_STUB_RC", raising=False)
    monkeypatch.setenv("FT_NEWS_STATUS_INTERVAL", "0")  # R209 상태 절·주기·경보 끔 = 옛 동작(새 시험은 test_news_status_section.py)
    return repo, root, tmp_path


def news_files(root: Path) -> list[Path]:
    return sorted((root / "news").glob("NEWS-*.md")) if (root / "news").exists() else []


def baseline(root: Path) -> str:
    f = root / ".fable-team" / "state" / "news-ledger" / "last.sha"
    return f.read_text(encoding="utf-8").strip() if f.exists() else ""


# ── ⓐ 줄 키 나누기 ───────────────────────────────────────────────
def test_parse_ledger_splits_cells_into_line_keys():
    lines = nl.parse_ledger(REAL)
    assert {k[0] for k in lines} >= {"now", "1", "2", "2-1", "3", "4"}  # 5 는 머리줄만 있는 빈 표
    row = ("1", "어제(10-12) 시키신 일", "가입 메일 템플릿 13종")
    assert lines[row] == ("코드", "완료")  # 표 = 순번 칸을 뺀 첫 칸이 키, 나머지 칸이 값
    assert any(k[0] == "2" and k[2] == "폰 물결 확인(화면 서버 최신화 뒤)" for k in lines)  # 목록 = 줄 전체가 키
    assert not any("마지막 갱신" in k[2] for k in lines)  # 머리 인용 줄은 키가 아님


# ── ⓑ 두 판 차이 ────────────────────────────────────────────────
def test_diff_lists_only_new_changed_removed():
    new = REAL.replace(ROW_OLD, ROW_NEW).replace("\n### 오늘(10-13) 오전 시키신 일", f"\n{ROW_ADDED}\n\n### 오늘(10-13) 오전 시키신 일", 1)
    new = new.replace("|  | 약관 3종 | 문서 | 진행 — 웹 반영은 법무 회신·시행일 뒤 |  |\n", "")
    d = nl.diff_ledger(nl.parse_ledger(REAL), nl.parse_ledger(new))
    assert [k for k, _ in d] == ["새로", "바뀜", "빠짐"] or sorted(k for k, _ in d) == ["바뀜", "빠짐", "새로"]
    text = "\n".join(t for _, t in d)
    assert "진행 — 다시 손봄" in text and "완료" in text and "→" in text
    assert "신규 확인 요청 하나" in text and "약관 3종" in text
    assert len(d) == 3  # 안 바뀐 줄 0


def test_unchanged_text_has_empty_diff():
    assert nl.diff_ledger(nl.parse_ledger(REAL), nl.parse_ledger(REAL)) == []


# ── ⓓ 첫 실행 · ⓒ 변화 0 · ⓑ 발행 뒤 기준선 · ⓔ 실패 시 기준선 그대로 · ⓕ 미커밋 ──
def test_first_run_records_baseline_only_and_unchanged_publishes_nothing(env):
    repo, root, tmp = env
    sha = commit(repo, REAL)
    assert nl.main(["run"]) == 0 and baseline(root) == sha and news_files(root) == [] and not (tmp / "stub.log").exists()
    assert nl.main(["run"]) == 0 and news_files(root) == []


def test_meta_only_commit_advances_baseline_without_news(env):
    repo, root, tmp = env
    commit(repo, REAL)
    nl.main(["run"])
    sha2 = commit(repo, REAL.replace("마지막 갱신: 2026-10-13 14:0x", "마지막 갱신: 2026-10-13 15:0x"))
    assert nl.main(["run"]) == 0 and news_files(root) == [] and baseline(root) == sha2


def test_changed_line_makes_one_news_with_only_that_line_then_none(env):
    repo, root, tmp = env
    commit(repo, REAL)
    nl.main(["run"])
    sha2 = commit(repo, REAL.replace(ROW_OLD, ROW_NEW))
    assert nl.main(["run"]) == 0 and baseline(root) == sha2
    [f] = news_files(root)
    body = f.read_text(encoding="utf-8")
    assert f.name == "NEWS-20261013-1500.md" and body.startswith("*뉴스 10-13 15:00*")
    assert [h for h in re.findall(r"^\*([^*]+)\*", body, re.M)][1:]  # 첫 줄은 머리(뉴스 시각) == ["지금", "바뀐 것", "오빠 할 일", "팀 작업"]
    changed = body.split("*바뀐 것*")[1].split("*오빠 할 일*")[0]
    assert changed.count("•") == 1 and "가입 메일 템플릿 13종" in changed and "다시 손봄" in changed
    teams = body.split("*팀 작업*")[1]
    assert teams.count("•") == 9 and "실시간 통역" in teams and "KakaoBot" in teams  # 쉬는 팀 포함 전 팀
    assert not re.search(r"#\d+|판정\s*\d+", body)
    assert nl.main(["run"]) == 0 and len(news_files(root)) == 1  # 다시 실행 = 발행 0


def test_publish_failure_keeps_baseline_and_retry_republishes_same_diff(env, monkeypatch):
    repo, root, tmp = env
    sha1 = commit(repo, REAL)
    nl.main(["run"])
    commit(repo, REAL.replace(ROW_OLD, ROW_NEW))
    monkeypatch.setenv("FT_STUB_RC", "1")
    assert nl.main(["run"]) != 0 and baseline(root) == sha1
    monkeypatch.delenv("FT_STUB_RC")
    assert nl.main(["run"]) == 0 and baseline(root) != sha1
    assert (tmp / "stub.log").read_text(encoding="utf-8").count("가입 메일 템플릿 13종") >= 2


def test_uncommitted_edit_is_not_in_the_news(env):
    repo, root, tmp = env
    commit(repo, REAL)
    nl.main(["run"])
    (repo / REL).write_text(REAL.replace(ROW_OLD, ROW_NEW), encoding="utf-8")
    assert nl.main(["run"]) == 0 and news_files(root) == []


def test_real_publish_tool_posts_once_against_fake_slack(env, monkeypatch):
    repo, root, tmp = env
    slack = FakeSlack()
    (tmp / "tok").write_text("YOONHWAN_BOT_TOKEN=xoxb-fake\n", encoding="utf-8")
    (tmp / "threads.json").write_text("{}", encoding="utf-8")
    monkeypatch.setenv("FT_NEWS_PUBLISH", f"bash {BIN / 'ft-news-publish.sh'}")
    monkeypatch.setenv("FT_THREAD_POST", str(KIT / "byz_thread_post.py"))
    monkeypatch.setenv("FT_NEWS_POST_ARGS", f"--slack-base {slack.base} --token-file {tmp / 'tok'} --channel C1 --ledger {tmp / 'threads.json'}")
    commit(repo, REAL)
    nl.main(["run"])
    commit(repo, REAL.replace(ROW_OLD, ROW_NEW))
    assert nl.main(["run"]) == 0 and len(slack.posts) == 1 and "다시 손봄" in slack.posts[0]["text"]
    assert nl.main(["run"]) == 0 and len(slack.posts) == 1
    slack.srv.shutdown()


# ── ⓓ 알림은 tests/scripts/test_ft_news_ledger_notify.py (R139) ──


# ── ⓖ R117 변환기가 원장을 읽는다(팀 0) ─────────────────────────
def test_parse_doc_reads_ledger_without_team_zone_and_renders_no_team_section():
    from magazine_brief import build_brief
    from magazine_brief_html import render
    doc = dm.parse_doc(REAL)
    assert doc.teams == [] and len(doc.cells) >= 5
    page = render(build_brief(doc, "2026-10-13", "abc", None, "지난 판 커밋 모름"))
    assert 'id="teams"' not in page and "팀별 전체" not in page and "<h1>" in page and "지난 판 커밋 모름" in page


# ── ⓗ 매거진 연결: 원본 = 원장 지금 커밋 ────────────────────────
def run_link(env_t, extra: dict | None = None) -> subprocess.CompletedProcess:
    repo, root, tmp = env_t
    doc = tmp / "doc.py"
    doc.write_text("import sys\nprint('ARGS', *sys.argv[1:])\n", encoding="utf-8")
    e = {"PATH": PATH, "FT_ROOT": str(root), "FT_LEDGER_REPO": str(repo), "FT_LEDGER_PATH": REL, "FT_MAGAZINE_DOC": str(doc), "FT_LEDGER_SYNCED": "1", **(extra or {})}  # r503 기본 경로 = design/teams/planner/ — 이 픽스처는 옛 경로 리포
    return subprocess.run(["bash", str(KIT / "magazine_from_news.sh"), "--publish"], env=e, capture_output=True, text=True, timeout=30)


def test_magazine_source_is_ledger_current_commit(env):
    sha = commit(env[0], REAL)
    r = run_link(env, {"FT_NEWS_NOW": "2026-10-13 08:00"})
    assert r.returncode == 0 and "--date 2026-10-13" in r.stdout and f"--src-sha {sha}" in r.stdout and f"--src-path {REL}" in r.stdout and f"--src-repo {env[0]}" in r.stdout


def test_magazine_rejects_uncommitted_ledger_edit_and_uncommitted_file(env):
    repo = env[0]
    assert run_link(env).returncode != 0  # 원장 없음
    commit(repo, REAL)
    (repo / REL).write_text(REAL + "\n- 커밋 전 줄\n", encoding="utf-8")
    r = run_link(env)
    assert r.returncode == 5 and "미커밋" in r.stderr


# ── r503 원장 사본 전진 호출: 가짜 sync rc3 → 뉴스 발행 계속 + 머리 ERROR 줄 · 매거진 exit 6 · 매거진 기본값 = 뉴스 사본·새 경로 ──
def fake_sync(tmp: Path, rc: int, line: str) -> Path:
    f = tmp / f"fake-sync-{rc}.sh"
    f.write_text(f'#!/usr/bin/env bash\necho "$1" >> "{tmp}/sync.calls"\necho "{line}"\nexit {rc}\n', encoding="utf-8")
    return f


def test_r503_news_sync_fail_still_publishes_with_error_head_line(env, monkeypatch):
    repo, root, tmp = env
    for k, v in {"FT_LEDGER_SYNCED": "0", "FT_LEDGER_SYNC_ERROR": "", "FT_LEDGER_SYNC": str(fake_sync(tmp, 3, "ERROR ledger 사본이 가지 main 위 — 전진 0"))}.items():
        monkeypatch.setenv(k, v)
    commit(repo, REAL)
    assert nl.run() == 0 and not news_files(root)  # 첫 실행 = 기준선만
    monkeypatch.setenv("FT_LEDGER_SYNCED", "0")  # 다음 틱(새 프로세스)
    commit(repo, REAL.replace(ROW_OLD, ROW_NEW))
    assert nl.run() == 0 and len(news_files(root)) == 1
    assert (tmp / "sync.calls").read_text(encoding="utf-8").splitlines() == [str(repo)] * 2
    log = (tmp / "stub.log").read_text(encoding="utf-8")
    assert "원장 사본 갱신 안 됨 — ERROR ledger 사본이 가지 main 위 — 전진 0" in log and "다시 손봄" in log


def test_r503_news_sync_ok_once_per_tick_and_only_for_explicit_repo(env, monkeypatch):
    repo, root, tmp = env
    for k, v in {"FT_LEDGER_SYNCED": "0", "FT_LEDGER_SYNC_ERROR": "", "FT_LEDGER_SYNC": str(fake_sync(tmp, 0, "SYNC aaaaaaaaaa..bbbbbbbbbb"))}.items():
        monkeypatch.setenv(k, v)
    assert nl.sync_repo() == "" and nl.sync_repo() == ""  # 같은 틱 두 번째 = 건너뜀
    assert (tmp / "sync.calls").read_text(encoding="utf-8").splitlines() == [str(repo)]
    monkeypatch.setenv("FT_LEDGER_SYNCED", "0")
    monkeypatch.delenv("FT_LEDGER_REPO")
    assert nl.sync_repo() == "" and len((tmp / "sync.calls").read_text(encoding="utf-8").splitlines()) == 1  # 기본 LIVE_ROOT = 옮기지 않음


def test_r503_magazine_sync_fail_exits_6_and_publishes_nothing(env):
    repo, root, tmp = env
    commit(repo, REAL)
    r = run_link(env, {"FT_LEDGER_SYNCED": "0", "FT_LEDGER_SYNC": str(fake_sync(tmp, 3, "ERROR ledger 사본 미커밋 추적 변경 1 — 전진 0 (x.md)"))})
    assert r.returncode == 6 and "원장 사본 갱신 실패 — ERROR ledger 사본 미커밋 추적 변경 1" in r.stderr and "ARGS" not in r.stdout
    r = run_link(env, {"FT_LEDGER_SYNCED": "0", "FT_LEDGER_SYNC": str(fake_sync(tmp, 0, "SYNC up-to-date"))})
    assert r.returncode == 0 and "ARGS" in r.stdout and "SYNC up-to-date" in r.stderr


def test_r503_magazine_default_source_is_news_copy_new_path(env):
    repo, root, tmp = env
    e = {"PATH": PATH, "FT_ROOT": str(root), "FT_LEDGER_SYNCED": "1", "FT_MAGAZINE_DOC": str(tmp / "doc.py")}
    r = subprocess.run(["bash", str(KIT / "magazine_from_news.sh")], env=e, capture_output=True, text=True, timeout=30)
    assert r.returncode == 2 and f"{root}/.worktrees/news-ledger-main/design/teams/planner/PLAN-oppa-ledger.md" in r.stderr


# ── 3ⓐ ft-tick.sh 연결: 30분 무초안 감시 → 원장 한 줄 ─────────────
def tick_news_ledger(tmp: Path, dry: int) -> subprocess.CompletedProcess:
    """ft-tick.sh 의 news_ledger 함수만 꺼내 가짜 ft-news-ledger.sh 와 1바퀴."""
    m = re.search(r"^news_ledger\(\) \{.*?^\}", (BIN / "ft-tick.sh").read_text(encoding="utf-8"), re.S | re.M)
    assert m, "ft-tick.sh 에 news_ledger 함수 없음"
    assert "news_watch" not in (BIN / "ft-tick.sh").read_text(encoding="utf-8")  # 감시 함수 삭제
    (tmp / "ft-news-ledger.sh").write_text(f'echo called >> "{tmp}/ledger.calls"\n', encoding="utf-8")
    return subprocess.run(["bash", "-c", f'HERE="{tmp}"; ROOT="{tmp}"; DRY={dry}\n{m.group(0)}\nnews_ledger'], env={"PATH": PATH}, capture_output=True, text=True, timeout=30)


def test_tick_calls_ledger_script_each_pass_and_dry_run_calls_nothing(tmp_path):
    assert tick_news_ledger(tmp_path, 1).stdout.strip() == "DRY kind=news-ledger" and not (tmp_path / "ledger.calls").exists()
    assert tick_news_ledger(tmp_path, 0).returncode == 0 and (tmp_path / "ledger.calls").read_text(encoding="utf-8") == "called\n"


# ── 교정 r2: 크기 초과 = 칸 경계로 n/N 판 · 전 판 rc 0 일 때만 기준선 ─────
import ft_news_publish as np  # noqa: E402

BIG_OLD = "| 완료 |"
BIG_NEW = "| 진행 — " + "가" * 60 + " |"


def big_diff_commit(repo: Path) -> str:
    return commit(repo, REAL.replace(BIG_OLD, BIG_NEW))  # 완료 줄 전부 바뀜 — 한 판(3500B)을 훌쩍 넘는 차이


def test_limit_constant_equals_publish_limit():
    assert nl.MAX_BYTES == np.MAX_BYTES == 3500


def test_big_diff_is_split_in_order_each_part_within_limit_then_baseline(env):
    repo, root, tmp = env
    commit(repo, REAL)
    nl.main(["run"])
    sha2 = big_diff_commit(repo)
    assert nl.main(["run"]) == 0 and baseline(root) == sha2
    parts = news_files(root)
    n = len(parts)
    assert n >= 2 and [p.name for p in parts] == [f"NEWS-20261013-1500-p{i}.md" for i in range(1, n + 1)]
    bodies = [p.read_text(encoding="utf-8") for p in parts]
    assert all(len(b.encode("utf-8")) <= nl.MAX_BYTES for b in bodies)
    assert all(b.startswith("*뉴스 10-13 15:00 (") and f"({i}/{n})*" in b.splitlines()[0] for i, b in enumerate(bodies, 1))
    called = [ln for ln in (tmp / "stub.log").read_text(encoding="utf-8").splitlines() if ln.endswith(".md")]
    assert [Path(c).name for c in called] == [p.name for p in parts]  # 판 순서대로 발행
    rows = re.findall(r"^• \[바뀜\] (.+?):", "\n".join(bodies), re.M)
    assert len(rows) == len(set(rows)) == REAL.count(BIG_OLD)  # 바뀐 줄이 한 번씩, 빠짐 없이


def test_second_part_failure_keeps_baseline_and_rerun_adopts_first_part(env, monkeypatch):
    repo, root, tmp = env
    slack = FakeSlack()
    (tmp / "tok").write_text("YOONHWAN_BOT_TOKEN=xoxb-fake\n", encoding="utf-8")
    (tmp / "threads.json").write_text("{}", encoding="utf-8")
    wrap = tmp / "wrap.sh"
    wrap.write_text(f'#!/usr/bin/env bash\ncase "$1" in *"$FT_FAIL_ON"*) exit 1;; esac\nexec bash {BIN / "ft-news-publish.sh"} "$@"\n', encoding="utf-8")
    monkeypatch.setenv("FT_NEWS_PUBLISH", f"bash {wrap}")
    monkeypatch.setenv("FT_THREAD_POST", str(KIT / "byz_thread_post.py"))
    monkeypatch.setenv("FT_NEWS_POST_ARGS", f"--slack-base {slack.base} --token-file {tmp / 'tok'} --channel C1 --ledger {tmp / 'threads.json'}")
    sha1 = commit(repo, REAL)
    nl.main(["run"])
    big_diff_commit(repo)
    monkeypatch.setenv("FT_FAIL_ON", "-p2.md")
    assert nl.main(["run"]) != 0 and baseline(root) == sha1 and len(slack.posts) == 1
    monkeypatch.setenv("FT_FAIL_ON", "@@never@@")
    monkeypatch.setenv("FT_NEWS_NOW", "2026-10-13 15:07")  # 다시 도는 분이 달라도 같은 판 머리 시각 — 첫 판 채택
    assert nl.main(["run"]) == 0 and baseline(root) != sha1
    n = len(news_files(root))
    assert len(slack.posts) == n and all(f"15:00 ({i}/{n})" in p["text"] for i, p in enumerate(slack.posts, 1))  # 첫 판 재발행 0 · 나머지만 추가
    slack.srv.shutdown()


def test_single_line_over_limit_raises_and_publishes_nothing(env):
    repo, root, tmp = env
    sha1 = commit(repo, REAL)
    nl.main(["run"])
    commit(repo, REAL.replace(ROW_OLD, "|  | 가입 메일 템플릿 13종 | 코드 | " + "가" * 1300 + " |  |"))
    assert nl.main(["run"]) != 0 and baseline(root) == sha1 and not (tmp / "stub.log").exists()


# ── 교정 r3 (DA⑥ HOLD) ──────────────────────────────────────────
def test_C1_real_ledger_without_date_in_title_needs_date_arg(env, monkeypatch, tmp_path):
    """날짜 없는 실물 원장 → «실제» magazine_doc.run 이 --date 로 HTML 을 만든다(외부 호출 0) · --date 도 제목 날짜도 없으면 DocError(rc 1)."""
    repo = env[0]
    commit(repo, REAL)
    base = ["--src-repo", str(repo), "--src-sha", "HEAD", "--src-path", REL, "--out-dir", str(tmp_path / "out"), "--state", str(tmp_path / "state.json"), "--dry-run"]
    assert md.main(base) == 1 and not list((tmp_path / "out").glob("*.html"))
    assert md.main([*base, "--date", "2026-10-13"]) == 0
    [page] = (tmp_path / "out").glob("MAGAZINE-DOC-2026-10-13-*.html")
    assert "2026-10-13" in page.read_text(encoding="utf-8")


def test_C2_midnight_partial_retry_posts_six_without_duplicate_first_part(env, monkeypatch):
    """10-13 23:50 판 묶음 중 p2 실패 → 10-14 00:00 재실행: 첫 시도 시각이 고정돼 첫 판 채택(post 0) · 총 글 = 판 수 · 상태는 10-13 폴더."""
    repo, root, tmp = env
    slack = FakeSlack()
    (tmp / "tok").write_text("YOONHWAN_BOT_TOKEN=xoxb-fake\n", encoding="utf-8")
    (tmp / "threads.json").write_text("{}", encoding="utf-8")
    wrap = tmp / "wrap.sh"
    wrap.write_text(f'#!/usr/bin/env bash\ncase "$1" in *"$FT_FAIL_ON"*) exit 1;; esac\nexec bash {BIN / "ft-news-publish.sh"} "$@"\n', encoding="utf-8")
    monkeypatch.setenv("FT_NEWS_PUBLISH", f"bash {wrap}")
    monkeypatch.setenv("FT_THREAD_POST", str(KIT / "byz_thread_post.py"))
    monkeypatch.setenv("FT_NEWS_POST_ARGS", f"--slack-base {slack.base} --token-file {tmp / 'tok'} --channel C1 --ledger {tmp / 'threads.json'}")
    sha1 = commit(repo, REAL)
    nl.main(["run"])
    sha2 = commit(repo, REAL.replace(BIG_OLD, "| 진행 — " + "가" * 150 + " |"))  # DA 반례처럼 판이 여럿 나오는 큰 차이
    monkeypatch.setenv("FT_NEWS_NOW", "2026-10-13 23:50")
    monkeypatch.setenv("FT_FAIL_ON", "-p2.md")
    assert nl.main(["run"]) != 0 and baseline(root) == sha1 and len(slack.posts) == 1
    monkeypatch.setenv("FT_FAIL_ON", "@@never@@")
    monkeypatch.setenv("FT_NEWS_NOW", "2026-10-14 00:00")
    assert nl.main(["run"]) == 0 and baseline(root) == sha2
    n = len(news_files(root))
    assert n >= 3 and len(slack.posts) == n  # 판마다 글 1개 — 첫 판 중복 0
    pub = root / ".fable-team" / "state" / "news-publish"
    assert (pub / "2026-10-13" / "published.txt").exists() and not (pub / "2026-10-14").exists()  # 날짜 기준 = 첫 시도 시각
    slack.srv.shutdown()


def test_ft_tick_passes_shellcheck():
    import shutil
    if not shutil.which("shellcheck"):
        pytest.skip("shellcheck 없음")
    done = subprocess.run(["shellcheck", str(BIN / "ft-tick.sh")], capture_output=True, text=True)
    assert done.returncode == 0, done.stdout
