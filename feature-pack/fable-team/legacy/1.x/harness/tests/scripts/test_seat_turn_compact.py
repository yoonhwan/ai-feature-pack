"""r527 ⓐ~ⓓ — 쉬는 동안 자동 압축된 좌석(압축 경계 + 압축 요약 user 1줄)을 «새 턴» 으로 세지 않는다.

픽스처 = 가짜 jsonl 조각(graphics arch 19 실측 꼬리 꼴 그대로 · 내용 문구 0) · 외부 호출 0 · GIT_* env 0.
실행: python3 -m pytest tests/scripts/test_seat_turn_compact.py -q
"""
import json
import sys
from pathlib import Path

PACK = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(PACK / "harness" / "bin"))

import ft_seat_turn as st  # noqa: E402

END_TS = "2026-10-19T20:42:30.877Z"
END = {"type": "system", "subtype": "turn_duration", "timestamp": END_TS, "durationMs": 4242}
BOUNDARY = {"type": "system", "subtype": "compact_boundary", "timestamp": "2026-10-19T21:37:17Z"}
SUMMARY = {"type": "user", "isCompactSummary": True, "timestamp": "2026-10-19T21:37:18Z",
           "message": {"role": "user", "content": "s"}}
ENQUEUE = {"type": "queue-operation", "operation": "enqueue"}


def _msg(kind: str) -> dict:
    return {"type": kind, "message": {"role": kind, "content": [{"type": "text", "text": "x"}]}}


def _side() -> list[dict]:
    """turn_duration 뒤 붙임·제목·모드 기록(실측 39개 중 비대화 기록 꼴)."""
    kinds = ["attachment", "last-prompt", "custom-title", "agent-name", "mode", "permission-mode", "atis-latch", "pr-link"]
    return [{"type": k} for k in kinds for _ in range(3)] + [{"type": "system", "subtype": "informational"}]


def _file(tmp_path: Path, recs: list[dict]) -> str:
    f = tmp_path / "seat.jsonl"
    f.write_text("".join(json.dumps(r, separators=(",", ":")) + "\n" for r in recs), encoding="utf-8")
    return str(f)


def _head() -> list[dict]:
    return [_msg("user"), _msg("assistant"), END]


def test_a_idle_compact_summary_is_idle_with_last_turn_end(tmp_path):
    f = _file(tmp_path, [*_head(), *_side(), BOUNDARY, SUMMARY])
    assert st.turn_of_file(f)[:3] == ("IDLE", END_TS, "4242")


def test_b_real_user_after_summary_is_working(tmp_path):
    f = _file(tmp_path, [*_head(), *_side(), BOUNDARY, SUMMARY, _msg("user")])
    assert st.turn_of_file(f)[0] == "WORKING"


def test_c_assistant_after_summary_is_working(tmp_path):
    f = _file(tmp_path, [*_head(), *_side(), BOUNDARY, SUMMARY, _msg("assistant")])
    assert st.turn_of_file(f)[0] == "WORKING"


def test_d_enqueue_then_summary_is_pending(tmp_path):
    f = _file(tmp_path, [*_head(), ENQUEUE, BOUNDARY, SUMMARY])
    assert st.turn_of_file(f)[0] == "PENDING"


def test_f_status_only_early_return_skips_summary_and_widens_to_turn_end(tmp_path):
    """DA② HOLD 1 — 첫 창(192B)에 turn_duration 이 없고 압축 요약만 보여도 조기 WORKING 0 · 창을 넓혀 IDLE."""
    attach = {"type": "attachment", "data": "a" * 700}
    f = _file(tmp_path, [*_head(), attach, BOUNDARY, SUMMARY])
    assert st.turn_of_file(f, tail_bytes=4096, tail_start=192, status_only=True)[:2] == ("IDLE", END_TS)


def test_a2_no_turn_end_in_window_summary_only_is_not_working(tmp_path):
    """창 안에 turn_duration 이 없는 분기(두 모드) — 압축 요약만 있으면 WORKING 아님."""
    f = _file(tmp_path, [{"type": "custom-title"}, BOUNDARY, SUMMARY])
    assert st.turn_of_file(f)[0] == "UNKNOWN"
    assert st.turn_of_file(f, status_only=False)[0] == "UNKNOWN"
