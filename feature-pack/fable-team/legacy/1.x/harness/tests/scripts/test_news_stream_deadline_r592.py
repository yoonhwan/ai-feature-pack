"""r592 — 뉴스 HTTP 스트림 읽기에 «총 마감 + 조각 사이 무진행» 시각 검사(하드 룰 12) ⓐ~ⓔ.

사건: `/tmp/byz-ft-news-planner.log` «secs=115.5(summary=4.0 important=115.5 …)» — `urlopen(timeout=left)` 는 «한 번 읽기»
상한이라 조각이 그보다 짧은 간격으로 계속 오면 `for raw in lines` 가 끝까지 돈다(총 마감 70초를 안 본다).
가짜 SSE 서버 1(로컬 · 조각 간격 조절) · 실 공급자 0 · 키는 가짜 값.
실행: python3 -m pytest tests/scripts/test_news_stream_deadline_r592.py -q
"""
import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_ft_news_html import DATA  # noqa: E402

import ft_news_html_render as fr  # noqa: E402


def _srv(chunks: list[str], gaps: list[float]) -> tuple[ThreadingHTTPServer, dict]:
    """가짜 SSE 서버 — 조각마다 gaps[i] 초 쉬고 보낸다 · 요청 프롬프트 기록 · 클라이언트가 끊은 뒤 첫 쓰기 실패 시각 기록(ⓔ)."""
    st: dict = {"reqs": [], "closed": None}

    class H(BaseHTTPRequestHandler):
        def log_message(self, *a: object) -> None:
            pass

        def do_POST(self) -> None:
            body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            st["reqs"].append(body["messages"][-1]["content"])
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.end_headers()
            for chunk, gap in zip(chunks, gaps):
                time.sleep(gap)
                ev = json.dumps({"choices": [{"delta": {"content": chunk}}]}, ensure_ascii=False)
                try:
                    self.wfile.write(f"data: {ev}\n\n".encode())
                    self.wfile.flush()
                except OSError:  # 상대(클라이언트)가 소켓을 닫았다 = 연결 열린 채 남음 0
                    st["closed"] = time.monotonic()
                    return
            try:
                self.wfile.write(b"data: [DONE]\n\n")
            except OSError:
                st["closed"] = time.monotonic()

    srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv, st


def _env(monkeypatch, srv: ThreadingHTTPServer, idle: str | None = None) -> None:
    """가짜 서버 주소 + 가짜 키 — 실 ~/.zshrc·실 pi 설정을 읽지 않는다."""
    for k in ("OPENROUTER_API_KEY", "OPENGATEWAY_API_KEY", "FT_NEWS_VIA", "FT_NEWS_EFFORT", "FT_NEWS_PI_MODELS"):
        monkeypatch.delenv(k, raising=False)
    for k, v in {"FT_NEWS_HTTP_BASE": f"http://127.0.0.1:{srv.server_port}/api/v1", "OPENROUTER_API_KEY": "sk-or-fake-r592",
                 "FT_NEWS_MODEL": "openrouter/fake-model", "FT_NEWS_STARTUP_LOG": "/dev/null"}.items():
        monkeypatch.setenv(k, v)
    if idle is None:
        monkeypatch.delenv("FT_NEWS_IDLE_S", raising=False)
    else:
        monkeypatch.setenv("FT_NEWS_IDLE_S", idle)


# ── ⓐ 조각이 짧은 간격으로 계속 오면 총 마감에서 끊는다(지금 판 = 끝까지 읽음 · FAIL) ──

def test_a_total_deadline_stops_endless_chunks(monkeypatch):
    srv, _ = _srv(["가" * 30] * 60, [0.05] * 60)  # 3초 동안 0.05초마다 조각 = 옛 판은 끝까지 읽는다
    _env(monkeypatch, srv)
    t = time.monotonic()
    rc, text, why, _at = fr._http_once("프롬프트", "summary", 0.5)  # 시험용 짧은 마감
    took = time.monotonic() - t
    assert rc == 1 and "총 마감" in why and "답 " in why, why
    assert text.strip()  # 받은 답 글자(부분)는 버리지 않고 사유에 남긴다
    assert took < 2.0  # 마감 근처에서 끊었다(옛 판 = 3초)
    srv.shutdown()


# ── ⓑ 첫 조각 뒤 무진행이 상한을 넘으면 «무진행 N초» 로 끊는다 ──

def test_b_idle_gap_stops_reading(monkeypatch):
    srv, _ = _srv(["나" * 10] * 5, [0.01, 0.8, 0.01, 0.01, 0.01])
    _env(monkeypatch, srv, idle="0.3")
    rc, text, why, _at = fr._http_once("프롬프트", "important", 3.0)
    assert rc == 1 and "무진행" in why, why
    assert text.strip()
    srv.shutdown()


# ── ⓒ 정상 스트림(마감 안) = 동작 불변 ──

def test_c_normal_stream_in_deadline_unchanged(monkeypatch):
    body = json.dumps({"summary": ["가", "나"], "refs": ["#1"]}, ensure_ascii=False)
    chunks = [body[i:i + 6] for i in range(0, len(body), 6)]
    srv, _ = _srv(chunks, [0.01] * len(chunks))
    _env(monkeypatch, srv, idle="5")
    rc, text, why, at = fr._http_once("프롬프트", "summary", 5.0)
    assert rc == 0 and text == body and why == "" and at is not None
    srv.shutdown()


# ── ⓓ 출력이 시작된 뒤 끊긴 경우 = 재시도 0(호출 수 1) ──

def test_d_no_retry_after_output_started(monkeypatch):
    reply = json.dumps({"team_notes": [{"team": f"t{i}", "text": "설명"} for i in range(30)]}, ensure_ascii=False)
    chunks = [reply[i:i + 8] for i in range(0, len(reply), 8)]
    srv, st = _srv(chunks, [0.02] * len(chunks))  # 정상 완료 = 2.5초+ · 시도당 상한 = 2초
    _env(monkeypatch, srv, idle="5")
    monkeypatch.setattr(fr, "UNIT_S", 0.5)
    with pytest.raises(fr.NewsHtmlError, match="teams"):
        fr.call_part(DATA, "teams", time.monotonic() + fr.DEADLINE_S)
    assert len(st["reqs"]) == 1  # 출력이 시작된 뒤 실패 = 재시도 0
    srv.shutdown()


# ── ⓔ 끊은 뒤 소켓이 열린 채 남지 않는다(서버가 다음 쓰기에서 OSError) ──

def test_e_socket_closed_after_stop(monkeypatch):
    srv, st = _srv(["다" * 8] * 80, [0.05] * 80)
    _env(monkeypatch, srv)
    rc, *_ = fr._http_once("프롬프트", "goals", 0.4)
    assert rc == 1
    end = time.monotonic() + 3
    while st["closed"] is None and time.monotonic() < end:
        time.sleep(0.05)
    assert st["closed"] is not None  # 연결이 닫혀 서버 쓰기가 실패했다 = 열린 채 남음 0
    srv.shutdown()
