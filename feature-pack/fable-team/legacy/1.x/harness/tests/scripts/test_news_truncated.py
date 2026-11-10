"""r582 — 뉴스 important 갈래가 «잘린 답» 으로 발행 0 을 반복: 끝난 이유(finish_reason)·생각(reasoning) 글자·usage 를 남기고, 잘림을 «답이 잘림» 으로 이름 붙인다.
가짜 HTTP 서버 1(SSE 재생 · 갈래별 응답) · 실 모델·실 슬랙 0.
실행: python3 -m pytest tests/scripts/test_news_truncated.py -q
"""
import json
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_ft_news_html import CONTENT, DATA, NOW  # noqa: E402

import ft_news_html as fh  # noqa: E402
import ft_news_html_render as fr  # noqa: E402

TRUNCATED = '{"important":[{"title":"환각 고치기","detail":"말끝 잡음","who":"v65"},{"title":"합치기","de'


class FakeSSE:
    """갈래별 SSE 대역 — important 갈래만 «잘림/생각만/정상» 으로 응답하고 나머지는 정상 JSON.
    기록 = self.reqs(요청 본문). finish_reason·reasoning_content·중간 끊김(cut)·4xx 를 주입한다."""

    def __init__(self) -> None:
        self.reqs: list[dict] = []
        self.mode = "ok"  # ok | truncated | reasoning_only | cut | code400
        outer = self

        class H(BaseHTTPRequestHandler):
            def log_message(self, *a: object) -> None:
                pass

            def _sse(self, events: list[dict]) -> None:
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.end_headers()
                for ev in events:
                    self.wfile.write(f"data: {json.dumps(ev, ensure_ascii=False)}\n\n".encode())
                    self.wfile.flush()

            def do_POST(self) -> None:
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                outer.reqs.append(body)
                prompt = body["messages"][-1]["content"]
                schema = prompt.split("출력 스키마:")[1].splitlines()[0]
                part = next(p for p in fr.PARTS if f'"{fr.PARTS[p][0][0]}":' in schema)
                if part != "important":
                    return self._sse([{"choices": [{"delta": {"content": json.dumps(CONTENT, ensure_ascii=False)}}]},
                                      {"choices": [{"delta": {}, "finish_reason": "stop"}]}, {"usage": {"prompt_tokens": 9, "completion_tokens": 9}}])
                if outer.mode == "code400":
                    self.send_response(400)
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    return
                if outer.mode == "truncated":
                    return self._sse([{"choices": [{"delta": {"reasoning_content": "생각" * 600}}]},
                                      {"choices": [{"delta": {"content": TRUNCATED}}]},
                                      {"choices": [{"delta": {}, "finish_reason": "length"}]}])
                if outer.mode == "reasoning_only":
                    return self._sse([{"choices": [{"delta": {"reasoning_content": "생각" * 700}}]},
                                      {"choices": [{"delta": {}, "finish_reason": "length"}]}])
                if outer.mode == "cut":  # 출력이 시작된 뒤 끊김 — finish_reason 0 · [DONE] 0
                    return self._sse([{"choices": [{"delta": {"content": TRUNCATED}}]}])
                return self._sse([{"choices": [{"delta": {"content": json.dumps(CONTENT, ensure_ascii=False)}}]},
                                  {"choices": [{"delta": {}, "finish_reason": "stop"}]}])

        self.srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
        self.base = f"http://127.0.0.1:{self.srv.server_port}/api/v1"

    def important_calls(self) -> int:
        return sum(1 for r in self.reqs if '"important":' in r["messages"][-1]["content"].split("출력 스키마:")[-1].splitlines()[0])


@pytest.fixture
def llm(tmp_path, monkeypatch):
    srv = FakeSSE()
    keyfile = tmp_path / "zshrc"
    keyfile.write_text("export OPENROUTER_API_KEY=sk-or-fake-r582\n", encoding="utf-8")
    for k, v in {"FT_NEWS_HTTP_BASE": srv.base, "FT_NEWS_KEY_FILE": str(keyfile),
                 "FT_NEWS_STARTUP_LOG": str(tmp_path / "startup.tsv"), "FT_NEWS_MODEL": "openrouter/anthropic/claude-haiku-5.5"}.items():
        monkeypatch.setenv(k, v)
    for k in ("OPENROUTER_API_KEY", "FT_NEWS_VIA", "FT_NEWS_EFFORT"):
        monkeypatch.delenv(k, raising=False)
    yield srv
    srv.srv.shutdown()


# ⓐ 잘린 JSON + finish_reason=length → «답이 잘림» 이라는 이름 · 발행 0
def test_r582_a_truncated_answer_is_named_not_json_error(tmp_path, llm, monkeypatch):
    monkeypatch.setenv("FT_OPENCODE", str(tmp_path / "없는-opencode"))
    llm.mode = "truncated"
    with pytest.raises(fr.NewsHtmlError) as e:
        fh.run_files(DATA, tmp_path / "o", NOW)
    msg = str(e.value)
    assert "답이 잘림" in msg and "finish_reason=length" in msg and f"생각 {len('생각' * 600)}자" in msg
    assert "Expecting ',' delimiter" not in msg  # 옛 판 = «응답이 JSON 아님» (이유 없음)
    assert not (tmp_path / "o").exists()  # 발행 0


# ⓑ content 0 · reasoning 만 · length → «답 0자 · 생각 M자 · length»
def test_r582_b_reasoning_only_reports_thought_size(tmp_path, llm, monkeypatch):
    monkeypatch.setenv("FT_OPENCODE", str(tmp_path / "없는-opencode"))
    llm.mode = "reasoning_only"
    with pytest.raises(fr.NewsHtmlError) as e:
        fh.run_files(DATA, tmp_path / "o", NOW)
    msg = str(e.value)
    assert "답 0자" in msg and f"생각 {len('생각' * 700)}자" in msg and "끝난 이유=length" in msg
    assert not (tmp_path / "o").exists()


# ⓒ 정상 stop + 온전한 JSON → 그대로 성공(동작 불변)
def test_r582_c_normal_stop_still_publishes_the_map(tmp_path, llm, monkeypatch):
    monkeypatch.setenv("FT_OPENCODE", str(tmp_path / "없는-opencode"))
    html_p, sum_p = fh.run_files(DATA, tmp_path / "o", NOW)
    assert html_p.is_file() and "환각 고치기" in html_p.read_text(encoding="utf-8") and sum_p.is_file()


# ⓓ 0단계 갈래(생각 끔) 필드가 실제 요청 본문에 실린다 · 공급자가 거부하면 그 사실을 남긴다
def test_r582_d_request_body_carries_reasoning_off_and_400_is_named(tmp_path, llm, monkeypatch):
    monkeypatch.setenv("FT_OPENCODE", str(tmp_path / "없는-opencode"))
    fh.run_files(DATA, tmp_path / "o", NOW)
    assert llm.reqs and all(r.get("reasoning_effort") == "none" for r in llm.reqs)
    assert all(r.get("stream_options") == {"include_usage": True} for r in llm.reqs)  # 토큰(usage)을 받아 잘림 계산 근거로 남긴다
    llm.mode, llm.reqs[:] = "code400", []
    with pytest.raises(fr.NewsHtmlError) as e:
        fh.run_files(DATA, tmp_path / "o2", NOW)
    assert "HTTP 400" in str(e.value) and "reasoning_effort" in str(e.value) and not (tmp_path / "o2").exists()


# ⓔ 출력이 시작된 뒤 실패 = 재시도 0(호출 수 = 1)
def test_r582_e_no_retry_after_output_started(tmp_path, llm, monkeypatch):
    monkeypatch.setenv("FT_OPENCODE", str(tmp_path / "없는-opencode"))
    llm.mode = "cut"
    with pytest.raises(fr.NewsHtmlError):
        fh.run_files(DATA, tmp_path / "o", NOW)
    assert llm.important_calls() == 1
