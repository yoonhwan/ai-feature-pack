"""r1006 — 뉴스 슬랙 본문에서 골 표·팀 진행·표준절차(마크다운 표)를 빼고 «골표 <sha10>» 표지 1줄만 · 골 표 문은 «표지 sha10 = 지금 렌더한 골 표 ∧ check 통과».

왜: 슬랙은 마크다운 표를 못 그려 `|---|`·«…» 로 잘린 글이 된다. 같은 표는 뉴스 HTML 지도가 같은 판정기로 이미 그린다.
계약(C1~C6) ↔ 시험(ⓐ~ⓔ):
  ⓐ C1 첫 판 본문 = 표 줄 0 · 표지 1줄      ⓑ C2 표지 sha10 = 렌더 sha10 ∧ check 통과 = 문 통과
  ⓒ C3 표지 없음·sha 다름·렌더 실패·check REJECT·7초 초과 = 문제(무장 REJECT · 비무장 WOULD-REJECT · 조용한 통과 0)
  ⓓ C4 영수증·이어진 판 규칙은 base 그대로    ⓔ C5 각주(상태 절) = `• ` 목록 줄 · 내용·순서 그대로 · 표 줄 0
  C6 kit 짝 cmp0 · 파일 200줄 상한
실행: pytest tests/scripts/test_news_body_goal_tag_r1006.py -q
"""
import re
from datetime import datetime
from pathlib import Path

import pytest
from test_ft_news_publish import draft, env, polished, records, slack  # noqa: F401 — 픽스처 재사용

ROOT = Path(__file__).resolve().parents[3]
BIN = ROOT / "harness" / "bin"
KIT = ROOT / "harness" / "kit" / "fable-team" / "bin"
import sys  # noqa: E402

sys.path.insert(0, str(BIN))

import ft_goal_gate as gate  # noqa: E402
import ft_goal_table as gt  # noqa: E402
import ft_news_ledger_text as lt  # noqa: E402
import ft_news_publish as np  # noqa: E402
import ft_news_status as st  # noqa: E402

NOW = datetime(2026, 10, 27, 10, 30)
REL = "design/planner/PLAN-oppa-ledger.md"
CANON = ROOT / "tests" / "fixtures" / "goal_table" / "AUTONOMY-GOAL-A6-20261018.md"
LEAD = "결정 인터뷰 1건 · 스크립트 0건"


@pytest.fixture(autouse=True)
def canon(monkeypatch, tmp_path):
    monkeypatch.setenv("FT_GOAL_A6_MD", str(CANON))
    monkeypatch.setenv("FT_GOAL_A6_LEDGER", str(tmp_path / "없는원장.md"))


@pytest.fixture
def block() -> str:
    return gt.render()


def _sha(block: str) -> str:
    return re.search(r"[0-9a-f]{10}", block.splitlines()[0].split("(")[1]).group(0)


def _new(teams: int) -> dict:
    new = {("now", "", "지금 전체 상태"): ("진행",)}
    new.update({("3", "", f"팀{i}"): ("가" * 60 + str(i),) for i in range(teams)})
    return new


def arm(tmp: Path) -> None:
    (tmp / ".fable-team" / "state").mkdir(parents=True, exist_ok=True)
    (tmp / ".fable-team" / "state" / "goal-gate.armed").write_text("", encoding="utf-8")


def sdir(tmp: Path) -> Path:
    return tmp / ".fable-team" / "state"


def heading(sha: str = "", run: str = "202610271030") -> str:
    return f"*뉴스 10-27 10:30* — 기준: 오빠 원장({REL}) · 지난 발행 뒤 바뀐 것만" + (f" · 골표 {sha}·{run}" if sha else "")


def body(sha: str = "", extra: str = "") -> str:
    return heading(sha) + "\n\n" + extra + "*지금*\n• 진행\n"


def two_tags(block: str, where: str) -> str:
    """표지 2개 — 같은 줄(머리 끝에 하나 더) 또는 다음 줄."""
    tag = f"골표 {_sha(block)}·202610271030"
    if where == "같은 줄":
        return heading(_sha(block)) + " · " + tag + "\n\n*지금*\n• 진행\n"
    return heading(_sha(block)) + "\n" + tag + "\n\n*지금*\n• 진행\n"


def other_block(block: str, name: str) -> str:
    """ft_goal_table 이 내는 다른 블록 하나(팀별 완성 진행·표준절차 골) — 머리·꼬리 글자는 그 한 곳에서 가져온다."""
    head, tail = (gt.TEAMS_HEAD, gt.TEAMS_TAIL) if name == "팀별 완성 진행" else (gt.PROCS_HEAD, gt.PROCS_TAIL)
    return f"{head}{_sha(block)})★\n| 팀 | 끝선 N/M |\n|---|---|\n| planner | 2/5 |\n{tail}\n"


# ── ⓐ C1 본문 표 줄 0 · 표지 1줄 ────────────────────────────────

def test_a_first_part_has_no_table_line_and_exactly_one_tag_line(block):
    teams = gt.render_teams() if hasattr(gt, "render_teams") else ""
    parts = lt.render_parts(NOW, _new(120), [], REL, lead=LEAD, goal=block, teams=teams)
    assert len(parts) >= 2
    assert all("★골 표" not in p and "★팀별 완성 진행" not in p for p in parts)
    assert not [ln for p in parts for ln in p.splitlines() if ln.startswith("|")]  # 표 줄 0
    assert all(p.count("골표 " + _sha(block)) == 1 for p in parts)  # 판마다 표지 1줄
    assert parts[0].splitlines()[1] == LEAD  # 블록이 있던 자리에 lead 가 온다


def test_a_without_goal_the_body_stays_the_same_no_tag_no_table():
    parts = lt.render_parts(NOW, _new(3), [], REL, lead=LEAD)
    assert all("골표" not in p and "|" not in p for p in parts)


# ── ⓑ C2 표지 sha10 = 렌더 sha10 ∧ check 통과 ───────────────────

def test_b_a_tag_equal_to_the_rendered_goal_table_passes_the_gate(block):
    assert gate.problem(body(_sha(block)), sdir(Path("/tmp"))) == ""
    assert gate.verify_bundle([body(_sha(block))]) == ""


# ── ⓒ C3 다섯 칸 × 무장 2 ──────────────────────────────────────

def _five(case: str, monkeypatch, tmp: Path, block: str) -> str:
    """다섯 문제 칸의 본문 — 그 판 하나를 publish 에 넘긴다."""
    if case == "표지 없음":
        return body()
    if case == "표지 sha 다름":
        return body("deadbeef00")
    if case == "렌더 실패":
        monkeypatch.setenv("FT_GOAL_A6_MD", str(tmp / "없는정본.md"))
        return body(_sha(block))
    if case == "check REJECT":  # 렌더는 되는데 정본 행 수와 다르다 = check --block-only REJECT
        fake = block.replace(block.splitlines()[3], "")  # 데이터 행 1개 삭제
        monkeypatch.setattr(gate.gt, "render", lambda: fake)
        return body(_sha(fake))
    assert case == "7초 초과"
    monkeypatch.setattr(gate, "RENDER_S", -1)  # 어떤 렌더도 상한을 넘는다(실제 대기는 없이 갈래만 시험)
    return body(_sha(block))


@pytest.mark.parametrize("case", ["표지 없음", "표지 sha 다름", "렌더 실패", "check REJECT", "7초 초과"])
@pytest.mark.parametrize("armed", [True, False])
def test_c_five_problems_reject_when_armed_and_only_warn_when_not(case, armed, block, monkeypatch, env, slack):  # noqa: F811
    tmp, news = env
    if armed:
        arm(tmp)
    why = np.main(["publish", str(polished(news, "20261027-1030", _five(case, monkeypatch, tmp, block)))])
    logged = (sdir(tmp) / "mbox-guard-goal.log").read_text(encoding="utf-8")
    if armed:
        assert why == 3 and slack.calls() == 0 and records(tmp) == []  # 발행 0 · 기록 0
        assert "REJECT news=" in logged  # 조용한 통과 0
    else:
        assert why == 0 and len(slack.posts) == 1  # 진행하되 로그를 남긴다
        assert "WOULD-REJECT news=" in logged


def test_c_a_body_that_puts_the_block_back_is_a_problem(block):
    withblock = body(_sha(block), block + "\n")
    assert "골 표 블록이 실렸다" in gate.problem(withblock, sdir(Path("/tmp")))


# ── ⓓ C4 이어진 판·영수증 규칙은 base 그대로 ────────────────────

def test_d_continued_parts_keep_the_bundle_tag_and_receipt_rules(block):
    parts = lt.render_parts(NOW, _new(300), [], REL, lead=LEAD, goal=block)
    assert len(parts) >= 3
    assert gate.verify_bundle(parts) == ""
    other = lt.render_parts(datetime(2026, 10, 27, 10, 31), _new(300), [], REL, lead=LEAD, goal=block)
    assert gate.verify_bundle([*parts[:2], other[2], *parts[3:]]) != ""  # 다른 run 혼합
    assert gate.verify_bundle([parts[0], *parts[2:]]) != ""  # 판번호 누락


# ── ⓔ C5 각주(상태 절) = 목록 줄 · 내용·순서 그대로 · 표 줄 0 ────

def test_e_status_footnote_lines_stay_bullets_in_order_and_carry_no_table(block):
    lines = ["(세션 상태 스냅샷 10:25 · 갱신 안 됨)", "• planner — 일함 1 · 정지 없음 / 해야 할 일: 없음"]
    parts = lt.render_parts(NOW, _new(3), [], REL, lead=LEAD, goal=block, extra=((st.TITLE, lines),))
    got = parts[0].splitlines()
    assert "|---" not in parts[0] and not [ln for ln in got if ln.startswith("|")]  # 표 줄 0
    assert got[-len(lines):] == lines  # 각주(맨 끝) = 내용·순서 그대로
    assert got.index(st.TITLE) < got.index(lines[-1])  # 절 제목 아래


# ── ⓕ 표지 2개 · ⓖ 다른 블록 재삼입 ─────────────────────────

@pytest.mark.parametrize("where", ["같은 줄", "다음 줄"])
@pytest.mark.parametrize("armed", [True, False])
def test_f_two_tags_in_the_first_part_are_a_problem(where, armed, block, monkeypatch, env, slack):  # noqa: F811
    tmp, news = env
    if armed:
        arm(tmp)
    b = two_tags(block, where)
    assert "2개" in gate.problem(b, sdir(tmp))  # 표지는 «정확히 1개»
    rc = np.main(["publish", str(polished(news, "20261027-1031", b))])
    assert (rc == 3 and slack.calls() == 0) if armed else (rc == 0 and len(slack.posts) == 1)


@pytest.mark.parametrize("name", ["팀별 완성 진행", "표준절차 골"])
def test_g_other_goal_table_blocks_in_the_first_part_are_a_problem(name, block, env, slack):  # noqa: F811
    tmp, news = env
    arm(tmp)
    b = body(_sha(block), other_block(block, name))
    assert name in gate.problem(b, sdir(tmp))  # 마커 3종 중 어느 것이든 본문에 있으면 문제
    assert np.main(["publish", str(polished(news, "20261027-1032", b))]) == 3 and slack.calls() == 0


# ── C6 kit 짝 cmp0 · 200줄 상한 ─────────────────────────────────

@pytest.mark.parametrize("name", ["ft_news_ledger_text.py", "ft_goal_gate.py"])
def test_c6_kit_copy_is_identical_and_both_files_stay_under_200_lines(name):
    a, b = (BIN / name).read_bytes(), (KIT / name).read_bytes()
    assert a == b  # kit 짝 cmp0
    assert len(a.decode("utf-8").splitlines()) <= 200
