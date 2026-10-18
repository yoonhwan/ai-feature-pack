#!/usr/bin/env bash
# test_mirror_summary_http.sh — 슬랙 미러 요약 호출: 7초 룰(시간 상한 + 재시도 1) + cliproxy Messages HTTP POST (r-mirror-planner-handled-sentence)
#  ⓓ 명령 경로 시간 초과 2회 · ⓔ 기본값 7.0 · ⓕ~ⓘ HTTP 전송(가짜 서버)
# 실제 프록시·슬랙·claude 호출 0 — 스텁 명령 · 127.0.0.1 가짜 서버.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="${SLACK_MIRROR_KIT:-$HERE/../../scripts/harness-install/slack-mirror}"
[ -d "$KIT" ] || { echo "FAIL kit dir missing: $KIT"; exit 1; }
python3 -I - "$KIT" <<'PYEOF'
import json, stat, sys, tempfile
from pathlib import Path

KIT = sys.argv[1]
sys.path.insert(0, KIT)
import mirror_summary as summ

fails = 0
def check(name, cond, detail=""):
    global fails
    if cond:
        print(f"PASS {name}")
    else:
        fails += 1
        print(f"FAIL {name} {detail}")

tmp = Path(tempfile.mkdtemp())


# ⓓ 요약기 시간 초과 → 정확히 2회 실행 후 SummaryError · 1회째 초과 2회째 성공이면 결과
cnt = tmp / "cnt"
def timeout_stub(name, ok_from):
    p = tmp / name
    out = json.dumps({"what": "재시도로 받았어요", "todo": None}, ensure_ascii=False)
    p.write_text(f"#!/bin/sh\ncat >/dev/null\necho x >> '{cnt}'\nif [ \"$(wc -l < '{cnt}')\" -ge {ok_from} ]; then printf '%s' '{out}'; exit 0; fi\nexec sleep 5\n")
    p.chmod(p.stat().st_mode | stat.S_IXUSR)
    return str(p)
runs = lambda: len(cnt.read_text().splitlines()) if cnt.exists() else 0
cnt.unlink(missing_ok=True)
try:
    summ.summarize(timeout_stub("slow.sh", 99), "보고", "본문", 1.5)  # 스텁은 카운터 증가 뒤 sleep 5 — 마감 1.5초는 부하에서도 스텁 기동보다 길다
    check("ⓓ 매번 시간 초과 → SummaryError", False, "예외 없음")
except summ.SummaryError:
    check("ⓓ 매번 시간 초과 → SummaryError · 실행 정확히 2회", runs() == 2, f"runs={runs()}")
cnt.unlink(missing_ok=True)
r = summ.summarize(timeout_stub("retry.sh", 2), "보고", "본문", 1.5)
check("ⓓ 1회째 초과 · 2회째 성공 → 결과 반환(실행 2회)", r["what"] == "재시도로 받았어요" and runs() == 2, f"{r} runs={runs()}")

# ⓔ 7초 룰 기본값 (하드 룰 12)
import inspect
check("ⓔ summarize 기본 timeout = 7.0", inspect.signature(summ.summarize).parameters["timeout"].default == 7.0)
import byz_mbox_slack_mirror as bm, byz_github_slack_mirror as bg
saved_argv = sys.argv
sys.argv = ["x", "--project", "p", "--mailbox", "m", "--seat", "s", "--channel", "c"]
check("ⓔ byz_mbox_slack_mirror --summary-timeout 기본 7.0", bm.parse().summary_timeout == 7.0)
check("ⓔ byz_mbox_slack_mirror --summarizer-cmd 기본 = cliproxy 주소(CLI 기동 비용 0)", bm.parse().summarizer_cmd == summ.DEFAULT_URL)
sys.argv = ["x", "--repo", "o/r", "--channel", "c"]
check("ⓔ byz_github_slack_mirror --summary-timeout 기본 7.0", bg.parse().summary_timeout == 7.0)
check("ⓔ byz_github_slack_mirror --summarizer-cmd 기본 = cliproxy 주소", bg.parse().summarizer_cmd == summ.DEFAULT_URL)
sys.argv = saved_argv

# ⓕ~ⓘ 요약 호출 = cliproxy Messages HTTP POST (CLI 기동 비용 제거 · fix2) — 가짜 서버(127.0.0.1) 시험, 실 프록시 호출 0
import http.server, threading, time
class Fake:
    """script: ("ok", text) | ("delay", sec, text) | ("status", code) | ("split", 헤더 전 대기초, 본문 전 대기초, text) | ("raw", 응답 본문 문자열) — 소진되면 마지막 항목 반복. reqs = (path, body dict)."""
    def __init__(self, script):
        self.script, self.reqs, outer = list(script), [], self
        class H(http.server.BaseHTTPRequestHandler):
            def log_message(self, *a): pass
            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["content-length"])))
                outer.reqs.append((self.path, body))
                step = outer.script[min(len(outer.reqs), len(outer.script)) - 1]
                try:
                    if step[0] == "status":
                        self.send_response(step[1]); self.end_headers(); return
                    if step[0] == "delay":
                        time.sleep(step[1])
                    if step[0] == "split":
                        time.sleep(step[1])
                    payload = step[1].encode() if step[0] == "raw" else json.dumps({"content": [{"type": "thinking", "thinking": ""}, {"type": "text", "text": step[-1]}]}).encode()
                    self.send_response(200); self.send_header("content-type", "application/json"); self.send_header("content-length", str(len(payload))); self.end_headers()  # 실 프록시처럼 Content-Length 응답
                    if step[0] == "split":  # 헤더 전 step[1]초 · 본문 전 step[2]초 — 소켓 단계별 timeout 이면 단계마다 새로 셈
                        self.wfile.flush(); time.sleep(step[2])
                    self.wfile.write(payload)
                except OSError:
                    pass  # 클라이언트가 시간 초과로 끊음
        self.srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
        self.srv.daemon_threads = True
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
        self.url = f"http://127.0.0.1:{self.srv.server_address[1]}"
GOOD = json.dumps({"what": "HTTP 로 받았어요", "todo": None}, ensure_ascii=False)
f = Fake([("ok", GOOD)])
r = summ.summarize(f.url, "보고", "본문", 2.0)
check("ⓕ http 주소 → Messages POST 1회 · thinking 블록 건너뛰고 text 의 JSON 에서 what", r["what"] == "HTTP 로 받았어요" and len(f.reqs) == 1, f"{r} {len(f.reqs)}")
path, body = f.reqs[0]
check("ⓘ 경로 /v1/messages · model=claude-haiku-5-5 · thinking 끔", path == "/v1/messages" and body.get("model") == "claude-haiku-5-5" and body.get("thinking") == {"type": "disabled"}, str(body)[:200])
check("ⓘ 프롬프트 바이트 동일(PROMPT.format) · user 메시지 1개", body["messages"] == [{"role": "user", "content": summ.PROMPT.format(label="보고", text="본문")}], str(body["messages"])[:200])
f = Fake([("delay", 1.5, GOOD), ("ok", GOOD)])
r = summ.summarize(f.url, "보고", "본문", 0.5)
check("ⓖ 첫 요청 시간 초과 · 둘째 정상 → 결과(요청 정확히 2회)", r["what"] == "HTTP 로 받았어요" and len(f.reqs) == 2, f"{r} {len(f.reqs)}")
f = Fake([("delay", 1.5, GOOD)])
try:
    summ.summarize(f.url, "보고", "본문", 0.5)
    check("ⓖ 둘 다 지연 → SummaryError", False, "예외 없음")
except summ.SummaryError:
    check("ⓖ 둘 다 지연 → 정확히 2회 뒤 SummaryError", len(f.reqs) == 2, str(len(f.reqs)))
for code in (401, 503):
    f = Fake([("status", code)])
    try:
        summ.summarize(f.url, "보고", "본문", 2.0)
        check(f"ⓗ HTTP {code} → SummaryError", False, "예외 없음")
    except summ.SummaryError as e:
        check(f"ⓗ HTTP {code} → 재시도 없이 SummaryError(요청 1회 · 코드 명시)", len(f.reqs) == 1 and str(code) in str(e), f"{len(f.reqs)} {e}")
dead = Fake([("ok", GOOD)]); dead.srv.shutdown(); dead.srv.server_close()
try:
    summ.summarize(dead.url, "보고", "본문", 1.0)
    check("ⓗ 연결 거부 → SummaryError", False, "예외 없음")
except summ.SummaryError:
    check("ⓗ 연결 거부 → 재시도 1회 뒤 SummaryError(조용한 폴백 0)", True)
# ⓙ 요청 1회 전체 마감(fix3 H1): 헤더 0.35초 + 본문 0.35초 = 총 0.7초 > timeout 0.5(각 단계는 0.5 미만) → 1회째에서 끊고 재시도 1 → 둘 다 같으면 SummaryError
f = Fake([("split", 0.35, 0.35, GOOD)])
t0 = time.monotonic()
try:
    summ.summarize(f.url, "보고", "본문", 0.5)
    check("ⓙ 본문이 마감 뒤에 오는 응답은 성공 처리 금지(받고 버림)", False, f"예외 없음 reqs={len(f.reqs)}")
except summ.SummaryError:
    check("ⓙ 마감 초과 → 재시도 1 → 정확히 2회 뒤 SummaryError · 총 경과 ≤ 2×0.5 + 0.4", len(f.reqs) == 2 and time.monotonic() - t0 <= 1.4, f"reqs={len(f.reqs)} el={time.monotonic() - t0:.2f}")
f = Fake([("split", 0.35, 0.35, GOOD), ("ok", GOOD)])
check("ⓙ 1회째 마감 초과 · 2회째 정상 → 결과(요청 2회)", summ.summarize(f.url, "보고", "본문", 0.5)["what"] == "HTTP 로 받았어요" and len(f.reqs) == 2, str(len(f.reqs)))
# ⓚ 응답 꼴 오류(fix3 H2): 어떤 JSON 꼴이든 SummaryError(TypeError 전파 0) · 재시도 0 = HTTP 1회
for raw in ('{"content": null}', '{"content": "문자열"}', '{"content": ["문자열"]}', '{"content": [null]}', '[]', 'null', '{"content": [{"type": "text", "text": null}]}'):
    f = Fake([("raw", raw)])
    try:
        summ.summarize(f.url, "보고", "본문", 2.0)
        check(f"ⓚ 응답 {raw} → SummaryError", False, "예외 없음")
    except summ.SummaryError:
        check(f"ⓚ 응답 {raw} → SummaryError · HTTP 1회", len(f.reqs) == 1, str(len(f.reqs)))
    except Exception as e:
        check(f"ⓚ 응답 {raw} → SummaryError", False, f"{type(e).__name__} 가 샘")
# ⓛ 실제 byz_mbox_slack_mirror.Mirror._summarize 경로에서 ⓚ 는 None(요약 실패 ERROR 1줄)로 끝난다 — 예외 전파 0
import types, io, contextlib
import byz_mbox_slack_mirror as bm
f = Fake([("raw", '{"content": null}')])
me = types.SimpleNamespace(a=types.SimpleNamespace(summarizer_cmd=f.url, summary_timeout=2.0))
err = io.StringIO()
try:
    with contextlib.redirect_stderr(err):
        res = bm.Mirror._summarize(me, 1, "보고", "원문")
    check("ⓛ 운영 콜백 _summarize: 응답 꼴 오류 → None · ERROR 1줄 · 예외 0", res is None and err.getvalue().count("ERROR") == 1, f"{res} {err.getvalue()}")
except Exception as e:
    check("ⓛ 운영 콜백 _summarize: 응답 꼴 오류 → None", False, f"{type(e).__name__} 전파")
# ⓜ 버려진 요청 0(fix4): 본문이 소켓 timeout 보다 짧은 간격(0.05초)으로 계속 흘러와도 마감(0.25초)에 연결을 닫는다 — 스레드·소켓 잔존 0
class Stream:
    def __init__(self):
        self.closed, self.stop, outer = 0, threading.Event(), self
        class H(http.server.BaseHTTPRequestHandler):
            def log_message(self, *a): pass
            def do_POST(self):
                self.rfile.read(int(self.headers["content-length"]))
                self.send_response(200); self.send_header("Transfer-Encoding", "chunked"); self.end_headers()
                try:
                    while not outer.stop.wait(0.05):
                        self.wfile.write(b"1\r\n \r\n"); self.wfile.flush()
                except OSError:
                    outer.closed += 1  # 클라이언트가 연결을 닫음
        self.srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
        self.srv.daemon_threads = True
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
        self.url = f"http://127.0.0.1:{self.srv.server_address[1]}"
st = Stream()
base, took = threading.active_count(), []
for _ in range(4):
    t0 = time.monotonic()
    try:
        summ.summarize(st.url, "보고", "본문", 0.25)
    except summ.SummaryError:
        pass
    took.append(time.monotonic() - t0)
end = time.monotonic() + 1.5
while (st.closed < 8 or threading.active_count() > base) and time.monotonic() < end:
    time.sleep(0.05)
check("ⓜ 실패 4회(요청 8회) → 서버가 본 연결 종료 8회(마감 즉시 close)", st.closed == 8, f"closed={st.closed}")
check("ⓜ 실패 뒤 스레드 증가 0", threading.active_count() <= base, f"base={base} now={threading.active_count()}")
check("ⓜ 실패마다 경과 ≤ 2×0.25 + 0.2", max(took) <= 0.7, str([round(x, 2) for x in took]))
st.stop.set()
check("ⓘ 모델·주소 상수", summ.MODEL == "claude-haiku-5-5" and summ.DEFAULT_URL == "http://127.0.0.1:8317")


print(f"RESULT fail={fails}")
sys.exit(1 if fails else 0)
PYEOF
