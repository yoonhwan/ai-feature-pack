"""R109 ⓐⓑ — 매거진 요약·풀이는 프록시 Messages HTTP 직접 + thinking disabled + 호출당 7초(+시간 초과만 재시도 1). 가짜 프록시(127.0.0.1) · 실 프록시 0.

실행: timeout 120 python3 -m pytest tests/scripts/test_magazine_http.py -q
"""
import json
import socket
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest
from _magazine_fakes import fake_model

import magazine_cli_args
import magazine_eli5_batches as batches
import magazine_summary as ms
from mirror_lib import EXTERNAL_CALL_TIMEOUT_S, MAX_RETRIES

LINES = {"lines": ["main 에 두 건이 들어갔어요", "이슈는 하나 열렸어요", "오빠가 할 일은 하나예요"]}


class FakeProxy:
    """요청마다 behaviors 를 하나씩 소비(다 쓰면 마지막 것 반복). 항목 = ("ok", 텍스트|함수(body)) · ("sleep", 초) · ("status", 코드) · ("raw", 바이트)."""

    def __init__(self, *behaviors: tuple) -> None:
        self.behaviors, self.requests = list(behaviors), []
        outer = self

        class H(BaseHTTPRequestHandler):
            def log_message(self, format: str, *args: object) -> None:  # noqa: A002
                pass

            def do_POST(self) -> None:
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                outer.requests.append({"path": self.path, "body": body})
                kind, arg = outer.behaviors[min(len(outer.requests), len(outer.behaviors)) - 1]
                if kind == "sleep":
                    time.sleep(arg)
                    return
                if kind == "status":
                    return self._send(arg, b'{"error": "x"}')
                if kind == "raw":
                    return self._send(200, arg)
                text = arg(body) if callable(arg) else arg
                self._send(200, json.dumps({"content": [{"type": "text", "text": text}]}).encode())

            def _send(self, code: int, raw: bytes) -> None:
                self.send_response(code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)

        self.srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
        self.url = f"http://127.0.0.1:{self.srv.server_port}"

    def close(self) -> None:
        self.srv.shutdown()


@pytest.fixture
def proxy():
    made: list[FakeProxy] = []

    def make(*behaviors: tuple) -> FakeProxy:
        made.append(FakeProxy(*behaviors))
        return made[-1]

    yield make
    for p in made:
        p.close()


def test_request_is_messages_post_with_thinking_disabled(proxy):
    p = proxy(("ok", json.dumps(LINES, ensure_ascii=False)))
    s = ms.summarize_model(fake_model(), p.url)
    assert s.failure is None and s.lines == LINES["lines"]
    req = p.requests[0]
    assert len(p.requests) == 1 and req["path"] == "/v1/messages"
    assert req["body"]["model"] == "claude-haiku-5-5" and req["body"]["thinking"] == {"type": "disabled"}
    assert isinstance(req["body"]["max_tokens"], int) and req["body"]["max_tokens"] > 0
    assert req["body"]["messages"] == [{"role": "user", "content": ms.PROMPT.format(facts=ms.facts(fake_model()))}]


def test_time_limit_is_the_seven_second_rule_constants():
    assert (EXTERNAL_CALL_TIMEOUT_S, MAX_RETRIES) == (7.0, 1)
    assert ms.run_cmd.__defaults__ == (EXTERNAL_CALL_TIMEOUT_S,)


def test_timeout_is_retried_once_then_succeeds(proxy):
    p = proxy(("sleep", 1.0), ("ok", "된다"))
    assert ms.run_cmd(p.url, "q", timeout=0.3) == "된다"
    assert len(p.requests) == 2


def test_two_timeouts_raise_after_exactly_retry_plus_one_calls(proxy):
    p = proxy(("sleep", 1.0))
    with pytest.raises(ms.SummaryError, match="TimeoutError"):
        ms.run_cmd(p.url, "q", timeout=0.3)
    assert len(p.requests) == MAX_RETRIES + 1


@pytest.mark.parametrize("code", [400, 429, 500, 503])
def test_http_error_raises_without_retry(proxy, code):
    p = proxy(("status", code))
    with pytest.raises(ms.SummaryError, match=str(code)):
        ms.run_cmd(p.url, "q")
    assert len(p.requests) == 1


def test_connection_refused_raises_fast_without_retry():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        url = f"http://127.0.0.1:{s.getsockname()[1]}"
    t0 = time.monotonic()
    with pytest.raises(ms.SummaryError, match="요약 호출 실패"):
        ms.run_cmd(url, "q")
    assert time.monotonic() - t0 < 2


@pytest.mark.parametrize("raw", [b"not json", b'{"content": "x"}', b'{"content": [1]}', b"[]"])
def test_bad_body_is_a_summary_error(proxy, raw):
    with pytest.raises(ms.SummaryError, match="응답 해석 실패"):
        ms.run_cmd(proxy(("raw", raw)).url, "q")


def test_http_failure_is_a_visible_summary_failure_not_a_silent_default(proxy, caplog):
    s = ms.summarize_model(fake_model(), proxy(("status", 503)).url)
    assert s.failure and "503" in s.failure and s.lines[0].endswith(f"(요약 실패: {s.failure})")
    assert any(r.levelno >= 40 for r in caplog.records)


def test_eli5_runner_uses_http_and_thinking_disabled(proxy):
    units = [{"path": "p1", "title": "단위"}]
    answer = {"units": [{"ref": "p1", "icon": "🪟", "analogy": "창문 닦기 같은 일", "lines": ["흐린 곳을 닦았어요"]}]}
    p = proxy(("ok", json.dumps(answer, ensure_ascii=False)))
    out = batches.explain(units, p.url, "문체", ms.run_cmd)
    assert isinstance(out["p1"], dict) and p.requests[0]["body"]["thinking"] == {"type": "disabled"}


def test_eli5_http_failure_marks_each_card_call_failed(proxy):
    out = None
    with pytest.raises(batches.Eli5Error, match="AI 풀이 0건"):
        out = batches.explain([{"path": "p1", "title": "단위"}], proxy(("status", 503)).url, "문체", ms.run_cmd)
    assert out is None


def test_magazine_cli_default_summary_cmd_is_the_proxy_url():
    cmd = magazine_cli_args.parse_args([]).summary_cmd
    assert cmd == ms.PROXY_URL and cmd.startswith("http://127.0.0.1:")
