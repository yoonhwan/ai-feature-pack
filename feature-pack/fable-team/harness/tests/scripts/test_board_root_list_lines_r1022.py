"""r1022 보드 뿌리 글 — ⓪·④ 표 줄을 «• » 목록 줄로 (슬랙 되읽기 가드 r1004 예외 0 통과).

계약 대응표(카드 §계약↔시험)를 그대로 칸으로 옮겼다.
  C1 root_text 출력 = 표 줄·구분 줄 0 · 가드 check() == None        → ⓐ 실제 꼴 본문 · 변이 «목록 변환 삭제» → FAIL
  C2 칸 글자 보존(슬랙 링크 파이프 포함 · 순서 그대로)              → ⓑ
  C3 절 순서·FOOT·3500B 상한·절 머리 없음 = raise 그대로            → ⓒ
  C4 짝 cmp0                                                      → kit_bin_sync (러너가 부른다 · 여기서는 바이트 cmp)
실행: python3 -m pytest tests/scripts/test_board_root_list_lines_r1022.py -q
"""
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]  # feature-pack/fable-team
KITBIN = ROOT / "harness" / "kit" / "fable-team" / "bin"
KIT = ROOT / "harness" / "kit" / "slack-mirror"
sys.path[:0] = [str(KIT), str(KITBIN)]

import ft_board_root as br  # noqa: E402
import root_readback_guard as guard  # noqa: E402

LINK = "<https://byz.slack.com/archives/C1/p1|팀 | 상태>"  # 칸 안 슬랙 링크 — 안쪽 파이프는 칸 경계가 아니다
TEAM_ROWS = [
    f"- 팀1 | 지금: 진행 1(카드 r1022) | 큐: 대기 2 | 오빠 할 일 0 | {LINK}",
    "- 팀2 아래 | 지금: 진행 0 | 큐: 대기 1 | 오빠 할 일 1 | 정지 0",
]
VERDICT_ROWS = ["1 · 보드 표 줄 · APPROVE · 하네스,바이브", "2 · 가드 예외 0 · APPROVE · 하네스"]
TABLE = ["| 팀 | 끝선 N/M | 마지막 착지 |", "|---|---|---|", "| 하네스 | 12/14 | 12:59 |", "| | |"]


def body(teams=None, verdicts=None, head="결론 — 보드 발행을 되살렸어요") -> str:
    """실제 꼴 보드 본문 — 머리 + ⓪(표 줄 섞임) + ①②③ + ④(표 줄 섞임)."""
    return "\n".join([head, "*⓪ 팀 요약*", *(TEAM_ROWS if teams is None else teams),
                      *([*TABLE, "… 외 0팀"] if teams is None else []),
                      "*① 완성 트리*", "a", "*② 세션 트리*", "b", "*③ 큐*", "c",
                      "*④ 오늘 판정표*", *(VERDICT_ROWS if verdicts is None else verdicts)])


def test_실제_꼴_본문이_가드를_통과한다():
    out = br.root_text(body())
    assert "|" not in out.replace(LINK, "")  # 표 줄·구분 줄 0(링크 안 파이프는 글자)
    assert guard.check(out) is None


def test_칸_글자가_순서대로_남는다():
    out = br.root_text(body())
    row = next(ln for ln in out.split("\n") if ln.startswith("• 팀1 "))
    assert row.startswith("• 팀1 · 지금: 진행 1(카드 r1022) · 큐: 대기 2 · 오빠 할 일 0 · ")
    assert row.endswith(LINK)  # 링크 파이프·순서 보존
    assert "• 하네스 · 12/14 · 12:59" in out.split("\n")
    assert "1 · 보드 표 줄 · APPROVE · 하네스,바이브" in out  # 표 아니던 줄은 그대로


def test_변이_목록_변환_삭제면_가드가_잡는다(monkeypatch):
    monkeypatch.setattr(br, "_list_lines", lambda lines: list(lines))  # 변이: 표 줄을 안 바꾼다
    assert guard.check(br.root_text(body())) is not None


def test_절_순서_FOOT_상한_그대로():
    out = br.root_text(body())
    lines = out.split("\n")
    assert lines[0].startswith("결론")  # 첫 줄 = 머리(결론 줄 · 가드 C3)
    assert out.index("*⓪ 팀 요약*") < out.index("*④ 오늘 판정표*")
    assert out.endswith(br.FOOT)  # 끝줄 고정
    assert "{①" not in out and "①②③" not in out.split("\n")[0]
    assert len(out.encode("utf-8")) <= br.CAP


def test_상한_넘으면_자르고_말줄임은_3개_미만():
    long = [f"- 팀{i} | 지금: 진행 1(카드 {i}) | 큐: 대기 2 | 오빠 할 일 0 | " + "가" * 30 for i in range(40)]
    out = br.root_text(body(teams=long))
    assert len(out.encode("utf-8")) <= br.CAP
    assert "… 외 " in out  # 접힌 팀 수 줄
    assert guard.check(out) is None
    assert out.count("…") < guard.ELLIPSIS_MAX


def test_절_머리_없으면_raise():
    with pytest.raises(ValueError):
        br.root_text("결론만 있고 절 머리 0")


def test_짝_바이트_같다():
    pair = (ROOT / "harness" / "bin" / "ft_board_root.py").read_bytes()
    assert pair == (KITBIN / "ft_board_root.py").read_bytes()
