"""R25 초안 시험 — 요약 명령을 가짜로 바꿔 «실패 원인이 오류 문구에 남는가 · 라우팅 env 가 이 호출에만 가는가» 를 본다.

실행: uv run pytest -q tests/scripts/test_mirror_summary_cc_route.py  (실제 LLM·프록시 호출 0 · 키트 mirror_summary.py 를 import)
"""
import os
import sys
import textwrap
from pathlib import Path

import pytest

KIT = Path(__file__).resolve().parents[3] / "harness" / "kit" / "slack-mirror"
sys.path.insert(0, str(KIT))
import mirror_summary as summ  # noqa: E402


def fake(tmp_path: Path, body: str) -> str:
    p = tmp_path / "fake.py"
    p.write_text(textwrap.dedent(body), encoding="utf-8")
    return f"{sys.executable} {p}"


def test_default_cmd_goes_through_cc_wrapper_not_direct_claude():
    assert summ.DEFAULT_CMD.startswith("~/.headroom/claude-hr.sh ")
    assert "~/.local/bin/claude" not in summ.DEFAULT_CMD
    assert "--model claude-haiku-5-5 " in summ.DEFAULT_CMD
    assert summ.SUMMARY_ENV == {"CLIPROXY_ROUTE": "1", "HEADROOM_ROUTE": "0"}


def test_limit_message_on_stdout_is_kept_in_error(tmp_path: Path):
    cmd = fake(tmp_path, """
        import sys
        print("You've hit your weekly limit · resets Oct 12 at 12pm (Asia/Seoul)")
        sys.exit(1)
    """)
    with pytest.raises(summ.SummaryError) as e:
        summ.summarize(cmd, "보고", "본문")
    assert "종료코드 1" in str(e.value) and "weekly limit" in str(e.value)


def test_wrapper_refusal_on_stderr_is_kept_in_error(tmp_path: Path):
    cmd = fake(tmp_path, """
        import sys
        print("claude-hr: cliproxy 경유가 요청됐지만 :8317 /v1/models 실패 — 직결 폴백을 거부한다", file=sys.stderr)
        sys.exit(69)
    """)
    with pytest.raises(summ.SummaryError) as e:
        summ.summarize(cmd, "보고", "본문")
    assert "종료코드 69" in str(e.value) and "직결 폴백을 거부" in str(e.value)


def test_no_output_says_so_and_cause_is_capped(tmp_path: Path):
    with pytest.raises(summ.SummaryError) as e:
        summ.summarize(fake(tmp_path, "import sys; sys.exit(3)"), "보고", "본문")
    assert str(e.value) == "요약 종료코드 3: 출력 없음"
    long = fake(tmp_path, "import sys; print('x' * 500); sys.exit(1)")
    with pytest.raises(summ.SummaryError) as e:
        summ.summarize(long, "보고", "본문")
    assert len(str(e.value)) <= len("요약 종료코드 1: ") + 160


def test_route_env_reaches_subprocess_only(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("CLIPROXY_ROUTE", "0")  # 바깥 값이 0 이어도 요약 호출은 1
    cmd = fake(tmp_path, """
        import json, os
        print(json.dumps({"what": os.environ.get("CLIPROXY_ROUTE", "") + os.environ.get("HEADROOM_ROUTE", ""), "todo": None}))
    """)
    assert summ.summarize(cmd, "보고", "본문")["what"] == "10"
    assert os.environ["CLIPROXY_ROUTE"] == "0"  # 부모 프로세스 env 는 그대로
