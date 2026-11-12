"""r1761 A1 — pi 모델 일시 오류(«temporarily unavailable»·overloaded)를 UNAVAILABLE(why=model_unavailable)로 가른다.

입력 = 임시 jsonl(마지막 assistant = stopReason error + errorMessage 문구). 실 세션·실 pane·모델 호출 0.
기준판 = 팩 origin/main 의 ft_seat_pi_turn.py (① 이 UNKNOWN → Red). 변이 M1 = 새 갈래 지움 → ① FAIL.
실행: python3 -m pytest -q -p no:cacheprovider feature-pack/fable-team/legacy/1.x/harness/tests/scripts/test_seat_pi_turn_model_unavailable_r1761.py
기준판 실행: git show origin/main:<이 파일> > /tmp/base/ft_seat_pi_turn.py · R1761_PI_TURN=<그 경로> pytest …
"""
import importlib.util
import json
import os
from pathlib import Path

import pytest

TURN = Path(os.environ.get("R1761_PI_TURN") or (Path(__file__).resolve().parents[2] / "bin/ft_seat_pi_turn.py"))
UNAVAILABLE = "The model is temporarily unavailable. Please try again later."


def load(path=None):
    path = Path(path or TURN)
    spec = importlib.util.spec_from_file_location("turn_r1761_" + str(abs(hash(str(path)))), path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def pi_file(tmp_path, message):
    path = tmp_path / "session.jsonl"
    rows = [{"type": "session", "id": "sid-r1761", "cwd": str(tmp_path)},
            {"type": "message", "timestamp": "2026-11-12T09:26:36Z",
             "message": {"role": "assistant", "stopReason": "error", **message}}]
    path.write_text("".join(json.dumps(row) + "\n" for row in rows), encoding="utf-8")
    return path


@pytest.mark.parametrize("text", [UNAVAILABLE, "overloaded_error: engine overloaded, retry later",
                                 "the model is TEMPORARILY UNAVAILABLE."])
def test_1_model_unavailable_is_its_own_state(tmp_path, text):  # ① 기준판 = UNKNOWN/error_without_class
    row = load().file_row(pi_file(tmp_path, {"errorMessage": text}))
    assert row[0] == "UNAVAILABLE", row
    assert row[1] == "-" and row[3] == "-" and row[4] == "pi" and row[7] == "model_unavailable", row


@pytest.mark.parametrize("message, state, why", [
    ({"errorMessage": "rate_limit_error: usage limit reached"}, "RATELIMITED", "rate_limit"),
    ({"errorMessage": "authentication_failed"}, "LOGGEDOUT", "authentication"),
    ({"errorMessage": "HTTP 503 upstream"}, "UNAVAILABLE", "http_unavailable"),
    ({"errorMessage": "connect ECONNREFUSED 127.0.0.1:443"}, "UNAVAILABLE", "connection"),
    ({"errorMessage": "그 밖의 문구"}, "UNKNOWN", "error_without_class"),
])
def test_2_existing_classes_are_unchanged(tmp_path, message, state, why):  # ② 기존 갈래·순서 그대로
    row = load().file_row(pi_file(tmp_path, message))
    assert (row[0], row[7]) == (state, why), row
    assert row[2] == ("1" if state == "LOGGEDOUT" else "-"), row


def test_M1_removing_the_new_branch_makes_1_red(tmp_path):  # M1 = 새 갈래 지움 → ① FAIL(원본 대조 = PASS)
    assert load().file_row(pi_file(tmp_path, {"errorMessage": UNAVAILABLE}))[0] == "UNAVAILABLE"
    text = TURN.read_text(encoding="utf-8")
    hit = [ln for ln in text.splitlines() if "temporarily unavailable" in ln]
    assert len(hit) == 1, "변이 자리(새 문구 줄)가 원본에 1곳이어야 한다"
    (tmp_path / "turn.py").write_text(text.replace(hit[0] + "\n", ""), encoding="utf-8")
    row = load(tmp_path / "turn.py").file_row(pi_file(tmp_path, {"errorMessage": UNAVAILABLE}))
    assert (row[0], row[7]) == ("UNKNOWN", "error_without_class"), row
