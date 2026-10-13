"""r117 r2 쉬운 문단 호출 — Haiku 프록시 직접(mirror_summary._fetch 가짜). 에르메스 실행 0 · 실 호출 0.

실행: env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR python3 -m pytest tests/scripts/test_magazine_doc_hermes.py -q
"""
import json
import logging
import threading
import time

import pytest
import _magazine_fakes  # noqa: F401 — slack-mirror 경로를 sys.path 에 올린다

import magazine_hermes as mh
from magazine_doc_md import Cell
from mirror_summary import MODEL, SummaryError


class FakeFetch:
    """_fetch(url, body, timeout) 대역. mode: ok · empty · numbered · path · long · timeout · sleep · http · truncated · bigusage."""

    def __init__(self, mode: str = "ok", sleep: float = 0.0) -> None:
        self.mode, self.sleep = mode, sleep
        self.calls: list[dict] = []
        self.live = self.peak = 0
        self.lock = threading.Lock()

    def __call__(self, url: str, body: bytes, timeout: float) -> bytes:
        with self.lock:
            self.calls.append({"url": url, "body": body, "timeout": timeout, "t": time.time()})
            self.live += 1
            self.peak = max(self.peak, self.live)
        try:
            time.sleep(self.sleep)
            return self._answer()
        finally:
            with self.lock:
                self.live -= 1

    def _answer(self) -> bytes:
        if self.mode == "timeout":
            raise TimeoutError("요청 마감 7.0초 초과")
        if self.mode == "http":
            raise SummaryError("요약 HTTP 503")
        text = {"empty": "", "numbered": "이슈 #1234 와 abc1234def 를 봤어요", "path": "scripts/a/b.py 를 고쳤어요",
                "long": "가" * 201}.get(self.mode, "지금은 멈춰 있고 곧 이어서 해요.")
        data = {"content": [{"type": "text", "text": text}], "stop_reason": "end_turn", "usage": {"input_tokens": 900}}
        if self.mode == "truncated":
            data["stop_reason"] = "max_tokens"
        if self.mode == "bigusage":
            data["usage"]["input_tokens"] = 2001
        if self.mode == "cachesum":  # 긴 요청은 input 4 + cache_creation 으로 잡힌다(실측)
            data["usage"] = {"input_tokens": 4, "cache_creation_input_tokens": 2100, "cache_read_input_tokens": 0}
        if self.mode == "cachesum_ok":
            data["usage"] = {"input_tokens": 4, "cache_creation_input_tokens": 1000, "cache_read_input_tokens": 996}
        return json.dumps(data).encode()


@pytest.fixture
def fetch(monkeypatch):
    def make(mode: str = "ok", sleep: float = 0.0) -> FakeFetch:
        fake = FakeFetch(mode, sleep)
        monkeypatch.setattr(mh, "_fetch", fake)
        return fake
    return make


def cell(key="c1", title="완료한 일", body="- **통역**: 해결\n- **결제**: 메일") -> Cell:
    return Cell(key=key, title=title, body=body)


def test_request_shape_body_cap_max_tokens_and_timeout(fetch):
    fake = fetch()
    big = "지금 팀 상태: 전팀 정지\n\n" + "\n".join(f"- 한글로 길게 쓴 일거리 번호 {i} — 진행" for i in range(400))
    assert mh.easy_one(cell("t1", "통역", big), "http://p") == "지금은 멈춰 있고 곧 이어서 해요."
    call = fake.calls[0]
    req = json.loads(call["body"])
    assert len(call["body"]) <= 1800 and req["model"] == MODEL and req["max_tokens"] <= 400
    assert req["thinking"] == {"type": "disabled"} and call["url"] == "http://p"
    assert call["timeout"] == 7.0  # 3.5초 가산 0
    assert "지금 팀 상태: 전팀 정지" in req["messages"][0]["content"] and "일거리 번호 399" not in req["messages"][0]["content"]


def test_single_huge_line_still_capped(fetch):
    fake = fetch()
    mh.easy_one(cell(body="가" * 9000))
    assert len(fake.calls[0]["body"]) <= 1800


def test_escape_heavy_input_still_within_1800(fetch):
    fake = fetch()
    nasty = "\n".join('| "따옴표" \\ 역슬래시 | \t탭 |' for _ in range(200))
    mh.easy_one(cell(body=nasty))
    assert len(fake.calls[0]["body"]) <= 1800
    json.loads(fake.calls[0]["body"])


def _just_over_cap_cell() -> Cell:
    """줄마다 약 200B 인 입력 — 첫 직렬화가 1,801~1,830B 가 되게 마지막 줄 길이를 맞춘다."""
    for k in range(1, 10):
        for n in range(1, 67):
            c = cell(body="\n".join(["가" * 66] * k + ["나" * n]))
            if 1800 < len(mh._serialize(mh.build_prompt(c))) <= 1830:
                return c
    raise AssertionError("1,801~1,830B 칸을 못 만듦")


def test_body_shrinks_past_line_boundary(fetch):
    fake = fetch()
    mh.easy_one(_just_over_cap_cell())
    assert len(fake.calls[0]["body"]) <= 1800


def test_instruction_wording_is_pinned():
    for word in ("나열", "개수", "100자"):
        assert word in mh.INSTRUCTION
    for word in ("두세 문장", "120자"):
        assert word not in mh.INSTRUCTION


def test_usage_sum_at_limit_passes(fetch):
    fetch("cachesum_ok")
    assert mh.easy_one(cell())


def test_no_hermes_cli_in_module():
    src = open(mh.__file__, encoding="utf-8").read()
    for word in ("subprocess", "--usage-file", "--ignore-rules", "SessionDB"):
        assert word not in src.replace("SessionDB 경로 0", "")


def test_timeout_retries_once_then_fails(fetch):
    fake = fetch("timeout")
    with pytest.raises(mh.EasyError, match="시간 초과"):
        mh.easy_one(cell())
    assert len(fake.calls) == 2


@pytest.mark.parametrize("mode,why", [("empty", "빈 답"), ("numbered", "번호"), ("path", "번호"), ("long", "초과"),
                                      ("truncated", "max_tokens"), ("bigusage", "2001"), ("cachesum", "2104"), ("http", "503")])
def test_bad_answer_raises_without_retry(fetch, mode, why):
    fake = fetch(mode)
    with pytest.raises(mh.EasyError, match=why):
        mh.easy_one(cell())
    assert len(fake.calls) == 1


def test_failed_cells_marked_and_error_logged(fetch, caplog):
    fetch("numbered")
    with caplog.at_level(logging.ERROR, logger="magazine_hermes"):
        got = mh.easy_all([cell("c1"), cell("t1", "통역")])
    assert all(v.text is None and "번호" in v.error for v in got.values())
    assert sum(r.levelno == logging.ERROR for r in caplog.records) == 2


def test_stage_deadline_discards_late_results(fetch):
    fetch(sleep=2)
    start = time.monotonic()
    got = mh.easy_all([cell(f"c{i}") for i in range(3)], deadline=0.5)
    assert time.monotonic() - start < 1.5
    assert all(v.text is None and "마감" in v.error for v in got.values())


def test_at_most_three_in_flight(fetch):
    fake = fetch(sleep=0.3)
    got = mh.easy_all([cell(f"c{i}") for i in range(6)])
    assert all(v.text for v in got.values()) and fake.peak == 3
