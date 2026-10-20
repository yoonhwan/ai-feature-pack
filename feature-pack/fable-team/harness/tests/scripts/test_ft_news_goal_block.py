"""R362 뉴스 골 표 — render_parts 첫 판 머리 줄 아래에 골 표 블록 · 이어진 판 묶음 표지(sha10·run id) · publish/post 문(무장 표식 때만 REJECT) · 판 묶음 사전검증 + 검증 영수증 · 거절 통지 · 모듈 누락 fail-closed.

인터페이스(시험이 고정): render_parts(..., goal=<ft-goal-table.sh 출력>) — 첫 판에만 머리 바로 아래(= lead 앞)에 실리고 3500B 계산에 들어간다 · 이어진 판 머리에 `골표 <sha10>·<run id>`.
게이트 = <루트>/.fable-team/state/goal-gate.armed 가 있을 때만 REJECT rc3(발행 0 · 처리 기록 0 · planner [긴급] 1통) · 없으면 WOULD-REJECT 로그만. 후속 판 단독 publisher 는 «검증 영수증»(같은 run 의 묶음 검증)이 있어야 통과.
실행: .venv/bin/python -m pytest tests/scripts/test_ft_news_goal_block.py -q
"""
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

import pytest
from test_ft_news_publish import BODY_A, draft, env, polished, records, slack  # noqa: F401 — 픽스처 재사용

ROOT = Path(__file__).resolve().parents[3]
BIN = ROOT / "harness" / "bin"
sys.path.insert(0, str(BIN))

import ft_goal_gate as gate  # noqa: E402
import ft_goal_table as gt  # noqa: E402
import ft_news_ledger_text as lt  # noqa: E402
import ft_news_post as post  # noqa: E402
import ft_news_publish as np  # noqa: E402

NOW = datetime(2026, 10, 18, 10, 30)
REL = "design/planner/PLAN-oppa-ledger.md"
CANON = ROOT / "tests" / "fixtures" / "goal_table" / "AUTONOMY-GOAL-A6-20261018.md"
LEAD = "결정 인터뷰 1건 · 스크립트 0건"
STUB = '#!/usr/bin/env bash\necho "$@" >> "$FT_STUB_LOG"\nexit 0\n'


@pytest.fixture(autouse=True)
def canon(monkeypatch, tmp_path):
    monkeypatch.setenv("FT_GOAL_A6_MD", str(CANON))
    monkeypatch.setenv("FT_GOAL_A6_LEDGER", str(tmp_path / "없는원장.md"))


@pytest.fixture
def block() -> str:
    return gt.render()


def arm(tmp: Path) -> None:
    (tmp / ".fable-team" / "state").mkdir(parents=True, exist_ok=True)
    (tmp / ".fable-team" / "state" / "goal-gate.armed").write_text("", encoding="utf-8")


def sdir(tmp: Path) -> Path:
    return tmp / ".fable-team" / "state"


def stub_mbox(tmp: Path, monkeypatch) -> Path:
    """planner 알림 대역 — 호출 인자를 로그에 쌓는다. 루트에 seats-planner.json(_master)이 있어야 통지가 나간다."""
    (tmp / ".fable-team").mkdir(parents=True, exist_ok=True)
    (tmp / ".fable-team" / "seats-planner.json").write_text('{"_master": "planner#9"}', encoding="utf-8")
    stub, log = tmp / "mbox-stub.sh", tmp / "mbox-stub.log"
    stub.write_text(STUB, encoding="utf-8")
    monkeypatch.setenv("FT_MBOX", str(stub))
    monkeypatch.setenv("FT_STUB_LOG", str(log))
    return log


def _new(teams: int) -> dict:
    new = {("now", "", "지금 전체 상태"): ("진행",)}
    new.update({("3", "", f"팀{i}"): ("가" * 60 + str(i),) for i in range(teams)})
    return new


def _sha(block: str) -> str:
    return re.search(r"[0-9a-f]{10}", block.splitlines()[0].split("(")[1]).group(0)  # r545: 머리에 출처 표지(`origin/main@`|`file:`)가 붙어도 sha10 만


# ── render_parts ─────────────────────────────────────────────────

def test_goal_block_sits_under_the_head_before_lead_in_the_first_part_only(block):
    parts = lt.render_parts(NOW, _new(120), [], REL, lead=LEAD, goal=block)
    assert len(parts) >= 2
    first = parts[0].splitlines()
    assert first[0].startswith("*뉴스") and first[1] == block.splitlines()[0]  # 머리 바로 아래
    assert parts[0].index("★/골 표★") < parts[0].index(LEAD)  # 블록이 lead 앞
    assert all("★골 표" not in p for p in parts[1:])  # 이어진 판에는 블록 반복 0
    assert all(f"골표 {_sha(block)}·{NOW:%Y%m%d%H%M}" in p.splitlines()[0] for p in parts[1:])  # 묶음 표지 = sha10 + run id


def test_every_part_stays_within_3500_bytes_with_the_block_counted(block):
    parts = lt.render_parts(NOW, _new(120), [], REL, lead=LEAD, goal=block)
    assert all(len(p.encode("utf-8")) <= lt.MAX_BYTES for p in parts)


def test_without_goal_the_text_is_unchanged():
    parts = lt.render_parts(NOW, _new(3), [], REL, lead=LEAD)
    assert all("★골 표" not in p and "골표" not in p for p in parts)


# ── ft_news_publish 문 ───────────────────────────────────────────

def test_unarmed_publish_goes_through_without_block_and_logs_would_reject(env, slack):  # noqa: F811
    tmp, news = env
    assert np.main(["publish", str(polished(news, "20261013-0910", BODY_A))]) == 0
    assert len(slack.posts) == 1
    assert "WOULD-REJECT" in (sdir(tmp) / "mbox-guard-goal.log").read_text(encoding="utf-8")


def test_armed_publish_rejects_first_part_without_block_and_leaves_no_trace(env, slack):  # noqa: F811
    tmp, news = env
    arm(tmp)
    draft(news, "20261013-0900")
    assert np.main(["publish", str(polished(news, "20261013-0910", BODY_A))]) == 3
    assert slack.calls() == 0 and records(tmp) == []  # 발행 0 · processed.tsv 0
    assert not (sdir(tmp) / "news-publish" / "2026-10-13" / "published.txt").exists()


def test_armed_publish_rejects_a_block_with_only_the_tail_marker(env, slack):  # noqa: F811
    tmp, news = env
    arm(tmp)
    assert np.main(["publish", str(polished(news, "20261013-0910", BODY_A + "\n★/골 표★\n"))]) == 3
    assert slack.calls() == 0


def test_armed_publish_rejects_a_forged_block_that_does_not_match_the_canon(env, slack, block):  # noqa: F811
    tmp, news = env
    arm(tmp)
    forged = block.replace("v65 마이크 넘기기 완성", "바꾼 골 원문")
    assert np.main(["publish", str(polished(news, "20261013-0910", forged + "\n" + BODY_A))]) == 3
    assert slack.calls() == 0


def test_armed_publish_accepts_first_part_with_block(env, slack, block):  # noqa: F811
    tmp, news = env
    arm(tmp)
    assert np.main(["publish", str(polished(news, "20261013-0910", block + "\n" + BODY_A))]) == 0
    assert len(slack.posts) == 1 and "★/골 표★" in slack.posts[0]["text"]


# ── H3 후속 판 위장 · 검증 영수증 ────────────────────────────────

def test_a_continued_part_needs_the_bundle_receipt_and_each_number_goes_out_once(env, slack, block):  # noqa: F811
    tmp, news = env
    arm(tmp)
    parts = lt.render_parts(NOW, _new(120), [], REL, lead=LEAD, goal=block)
    assert gate.verify_bundle(parts) == ""
    assert np.main(["publish", str(polished(news, "20261013-0911", parts[1]))]) == 3  # 영수증 없음 = 단독 publisher 거절
    gate.write_receipt(sdir(tmp), parts)
    assert np.main(["publish", str(polished(news, "20261013-0912", parts[1]))]) == 0
    assert np.main(["publish", str(polished(news, "20261013-0913", parts[1] + "\n같은 판번호 다른 글\n"))]) == 3  # 이미 나간 판번호
    assert len(slack.posts) == 1


def test_a_single_spoofed_continued_part_is_rejected_by_the_publisher_and_by_the_bundle_check(env, slack):  # noqa: F811
    tmp, news = env
    arm(tmp)
    spoof = "*뉴스 10-18 10:30 (2/2)* — 기준 · 골표 0123456789·202610181030\n골 표 없는 본문\n"
    assert gate.verify_bundle([spoof]) != "" and gate.problem(spoof, sdir(tmp)) != ""
    assert np.main(["publish", str(polished(news, "20261013-0910", spoof))]) == 3
    assert slack.calls() == 0


def test_bundle_rejects_mixed_runs_missing_and_duplicate_part_numbers(block):
    parts = lt.render_parts(NOW, _new(300), [], REL, lead=LEAD, goal=block)
    assert len(parts) >= 3
    other = lt.render_parts(datetime(2026, 10, 18, 10, 31), _new(300), [], REL, lead=LEAD, goal=block)
    assert gate.verify_bundle(parts) == ""
    assert gate.verify_bundle([*parts[:2], other[2], *parts[3:]]) != ""  # 다른 run 혼합
    assert gate.verify_bundle([parts[0], *parts[2:]]) != ""  # 판번호 누락
    assert gate.verify_bundle([parts[0], parts[1], parts[1], *parts[3:]]) != ""  # 판번호 중복


def test_bundle_check_always_checks_the_real_block_of_the_first_element(block):
    parts = lt.render_parts(NOW, _new(120), [], REL, lead=LEAD, goal=block)
    no_block = [parts[0].replace("★/골 표★", "").replace(block.splitlines()[0], ""), *parts[1:]]
    assert gate.verify_bundle(no_block) != ""


# ── 판 묶음 사전검증 (ft_news_post) ──────────────────────────────

def _bundle_env(tmp_path, monkeypatch):
    stub = tmp_path / "pub.sh"
    stub.write_text('#!/usr/bin/env bash\necho "$1" >> "$FT_PUB_LOG"\nexit 0\n', encoding="utf-8")
    monkeypatch.setenv("FT_NEWS_PUBLISH", f"bash {stub}")
    monkeypatch.setenv("FT_PUB_LOG", str(tmp_path / "stub.log"))
    state = sdir(tmp_path) / "news-ledger"
    state.mkdir(parents=True)
    (state / "last.sha").write_text("base\n", encoding="utf-8")
    return tmp_path / "news", state


def test_bundle_with_a_valid_first_part_and_tagged_rest_is_published_whole_and_leaves_a_receipt(tmp_path, monkeypatch, block):
    news, state = _bundle_env(tmp_path, monkeypatch)
    arm(tmp_path)
    parts = lt.render_parts(NOW, _new(120), [], REL, lead=LEAD, goal=block)
    rc, _ = post.publish(news, state, parts, NOW, "cur1")
    assert rc == 0 and len((tmp_path / "stub.log").read_text().splitlines()) == len(parts)
    assert (state / "last.sha").read_text().strip() == "cur1" and any((sdir(tmp_path) / "goal-bundle").glob("*.json"))


def test_bundle_with_one_bad_part_publishes_nothing_keeps_last_sha_and_notifies_once(tmp_path, monkeypatch, block):
    news, state = _bundle_env(tmp_path, monkeypatch)
    log = stub_mbox(tmp_path, monkeypatch)
    arm(tmp_path)
    parts = lt.render_parts(NOW, _new(120), [], REL, lead=LEAD, goal=block)
    parts[-1] = parts[-1].replace("골표 ", "골표X ")  # 마지막 판의 묶음 표지를 깬다
    rc, got = post.publish(news, state, parts, NOW, "cur1")
    assert rc == 3 and got == [] and not (tmp_path / "stub.log").exists()  # 전체 발행 0
    assert (state / "last.sha").read_text().strip() == "base"  # 기준선 불변
    assert list(news.glob("NEWS-*.md")) == []  # 판 파일도 남기지 않는다
    assert log.read_text(encoding="utf-8").count("[긴급] 뉴스 발행 거절") == 1  # planner [긴급] 1통
    post.publish(news, state, parts, NOW, "cur1")
    assert log.read_text(encoding="utf-8").count("[긴급] 뉴스 발행 거절") == 1  # 같은 거절은 10분 안 중복 억제


def test_unarmed_bundle_without_block_is_published_with_a_would_reject_log(tmp_path, monkeypatch):
    news, state = _bundle_env(tmp_path, monkeypatch)
    rc, _ = post.publish(news, state, ["*뉴스 10-18 10:30* — 기준\n"], NOW, "cur1")
    assert rc == 0 and (tmp_path / "stub.log").exists()
    assert "WOULD-REJECT" in (sdir(tmp_path) / "mbox-guard-goal.log").read_text(encoding="utf-8")


def test_draft_mode_also_verifies_the_bundle(tmp_path, monkeypatch, block):
    news, state = _bundle_env(tmp_path, monkeypatch)
    monkeypatch.setenv("FT_NEWS_MODE", "draft")
    arm(tmp_path)
    assert post.publish(news, state, ["*뉴스 10-18 10:30* — 기준\n"], NOW, "cur1")[0] == 3  # 초안도 블록 없이는 만들지 않는다
    assert list(news.glob("NEWS-*.md")) == []


# ── H4 모든 진입점 통지 · H1④ 모듈·렌더 예외 ─────────────────────

def test_publish_reject_and_render_failure_each_notify_planner_once(env, slack, monkeypatch):  # noqa: F811
    tmp, news = env
    log = stub_mbox(tmp, monkeypatch)
    arm(tmp)
    assert np.main(["publish", str(polished(news, "20261013-0910", BODY_A))]) == 3  # 단독 publisher 거절
    assert log.read_text(encoding="utf-8").count("[긴급] 뉴스 발행 거절") == 1
    monkeypatch.setenv("FT_GOAL_A6_MD", str(tmp / "없는정본.md"))
    with pytest.raises(gt.GoalError):
        gate.goal_block(sdir(tmp))  # 원장 뉴스의 렌더 실패(무장) = 예외 + 통지
    assert log.read_text(encoding="utf-8").count("진입점: render") == 1


def test_unarmed_render_failure_logs_would_reject_and_returns_empty(tmp_path, monkeypatch):
    monkeypatch.setenv("FT_GOAL_A6_MD", str(tmp_path / "없는정본.md"))
    assert gate.goal_block(sdir(tmp_path)) == ""
    assert "WOULD-REJECT news=render" in (sdir(tmp_path) / "mbox-guard-goal.log").read_text(encoding="utf-8")


def test_missing_gate_module_import_falls_back_to_the_fail_closed_stand_in():
    code = "import sys; sys.modules['ft_goal_gate'] = None; sys.path.insert(0, %r); import ft_news_post as p; print(type(p.goal_gate).__name__)" % str(BIN)
    out = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, check=False)
    assert out.stdout.strip() == "_MissingGate", out.stderr


def test_missing_gate_stand_in_rejects_when_armed_and_passes_with_a_log_when_not(env, slack, monkeypatch):  # noqa: F811
    tmp, news = env
    monkeypatch.setattr(np, "goal_gate", post._MissingGate(ImportError("x")))
    assert np.main(["publish", str(polished(news, "20261013-0910", BODY_A))]) == 0  # 비무장 = 경고 후 진행
    arm(tmp)
    assert np.main(["publish", str(polished(news, "20261013-0920", BODY_A + "다른 판\n"))]) == 3  # 무장 = 거절(fail-closed)
    stand_in = post._MissingGate(ImportError("x"))
    with pytest.raises(RuntimeError):
        stand_in.goal_block(sdir(tmp))
