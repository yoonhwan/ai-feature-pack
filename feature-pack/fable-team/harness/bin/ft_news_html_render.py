"""ft_news_html_render — 뉴스 HTML 모드(r478)의 «프롬프트 → opencode run(갈래 4개 병렬) → 내용 JSON → 고정 틀 HTML». 쓰는 쪽 = ft_news_html.py.

LLM 은 «내용(JSON)» 만 낸다 — 틀(CSS·절 머리·골 그림)은 templates/news-team-map.html 에 고정(기준본 BYZ-team-map-ref-20261019.html 과 같은 모양).
7초 룰(하드 룰 12 · 판정 1375): 한 번에 내용 전부(출력 3~4.4K자 = 기준량 300자의 10배+)를 받으면 base 30~44초 · max 65초~130초+ 로 70초를 넘었다(r478b 실측)
→ «쪼갤 수 있으면 쪼갠다»: 갈래 4개(summary = 요약·근거 / important = 중요한 일 / goals = 골 6 / teams = 팀 설명 · r478e 에서 옛 top 을 둘로)를 «그 갈래에 필요한 입력만» 넣어 병렬로 부른다.
시도당 상한 = min(고정비 + 7 × ceil(max(입력 토큰 ÷ IN_TOKENS, 예상 출력 글자 ÷ OUT_CHARS)), 총 마감) · 재시도는 «첫 출력 전 실패» 1회만 · 갈래 전부 합친 총 마감 70초 · 실패 = NewsHtmlError(발행 0 · #0 RULE).
고정비(r510) = CLI 기동부터 stdout 첫 바이트까지 «실측» 의 p90 — 기록 state/news-cli-startup.tsv(최근 20 · 시간 초과 = «>상한» 하한값) · 기록 3개 미만 = 잠정 3.5 · FT_NEWS_FIXED_S 가 있으면 그 값(되돌림 = 3.5).
호출 수단(r563) = FT_NEWS_VIA · `http`(기본) = 같은 모델을 OpenAI 호환 chat completions(스트림)로 «직접» 부른다 — CLI 기동 0 이라 시도당 상한 = 7초 룰 그대로(고정비 0) · `opencode` = 옛 경로(되돌림 손잡이).
  http: 모델 id 의 공급자 접두(`openrouter/…`) → 주소(openrouter = https://openrouter.ai/api/v1 · r575 opengateway = https://apis.opengateway.ai/v1) · 모델 = 접두 뒤 · 키 = openrouter = OPENROUTER_API_KEY(env › zshrc 마지막 활성 줄) · opengateway = OPENGATEWAY_API_KEY(env › pi 설정 `~/.pi/agent/models.json` providers.opengateway.apiKey — `$NAME` 이면 그 env · `!명령` 이면 그 명령 stdout) · 값 출력 0 · 접두가 모르는 것·키 없음 = NewsHtmlError(조용히 CLI 로 내려가기 0).
opencode run --standalone = 비대화 1회 · stdin 은 /dev/null(물려받은 stdin 이면 240초 동안 시작 0 실측) · 시간 초과면 프로세스 묶음째 kill.
env: FT_NEWS_MODEL(기본 opencode/deepseek-v4.1-flash-free) · FT_NEWS_EFFORT(변형 → --model <ID>#<변형> · 비거나 base = 변형 없음 · http 는 변형 접미를 뗀다) · FT_NEWS_DEPTH(프롬프트 «깊이» 문장 · 변형이 없을 때 대체) · FT_OPENCODE(기본 opencode)
     · FT_NEWS_VIA(http|opencode) · FT_NEWS_HTTP_BASE(http 주소 앞자리 · 기본 공급자 표) · FT_NEWS_KEY_FILE(키 파일 · 기본 ~/.zshrc) · FT_NEWS_PI_MODELS(pi 설정 · 기본 ~/.pi/agent/models.json · opengateway 키 출처)
     · FT_NEWS_FIXED_S(기동 고정비 고정) · FT_NEWS_STARTUP_LOG(기동 기록 · 기본 <루트>/.fable-team/state/news-cli-startup.tsv)
"""
import html
import json
import math
import os
import re
import signal
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ft_key_rotate_lines import parse_line  # noqa: E402  키 읽기 꼴 재사용(r563 · 값 출력 0)

HERE = Path(__file__).resolve().parent
MODEL = "opencode/deepseek-v4.1-flash-free"
VIA_HTTP, VIA_OPENCODE = "http", "opencode"
HTTP_BASE = {"openrouter": "https://openrouter.ai/api/v1",
             "opengateway": "https://apis.opengateway.ai/v1"}  # 공급자 접두 → OpenAI 호환 주소 앞자리(r575 opengateway = pi 딥식)
HTTP_KEY = {"openrouter": "OPENROUTER_API_KEY", "opengateway": "OPENGATEWAY_API_KEY"}
DEADLINE_S = 70
# r582 — 0단계 측정(harness/evidence/r582/00-measure.txt): deepseek v4.1 은 답 전에 생각을 8.7K~13.5K 자 쓰고, 그 토큰이 max_tokens 4096 을 먼저 먹어
# 5회 중 2회가 finish_reason=length(답 0자 또는 끝 근처에서 잘림)로 실패했다. 같은 프롬프트로 필드 3종을 재어 «생각 0자 · JSON OK» 3/3 이 나온 필드 = reasoning_effort.
REASONING_OFF = {"reasoning_effort": "none"}  # 생각 끄기 — 0단계 원문이 정한 한 곳. 공급자가 거부(4xx)하면 그 사실을 ERROR 로 남긴다(조용히 빼기 0)
FIXED_S, UNIT_S, IN_TOKENS, OUT_CHARS, BYTES_PER_TOKEN = 3.5, 7, 2000, 300, 3  # 7초 룰 기준량 · CLI 기동 고정비 · 한글 섞인 글 ≈ 3 B/토큰(추정)
SUMMARY_LINES, SUMMARY_BYTES = 3, 600  # r588 — 린트와 같은 상한(ft_news_html_lint) · 팀 상태 줄 포함해 넘으면 «자르지 않고» ERROR
STARTUP_KEEP, STARTUP_MIN = 20, 3  # r510 — 기동 기록 최근 20줄 · 3개 미만 = 잠정 FIXED_S
_STARTUP_LOCK = threading.Lock()  # 갈래 4개가 병렬로 기록한다
HOT = ' class="hot"'
WORK_ICON = ('<svg class="ic" viewBox="0 0 84 84" aria-hidden="true"><circle cx="42" cy="42" r="40" fill="var(--now-bg)"/><circle cx="26" cy="36" r="8" fill="var(--accent)"/>'
             '<circle cx="42" cy="30" r="9" fill="var(--done)"/><circle cx="58" cy="36" r="8" fill="var(--accent)"/>'
             '<path d="M14 62c2-10 22-10 24 0M30 60c2-12 22-12 24 0M46 62c2-10 22-10 24 0" fill="none" stroke="var(--ink)" stroke-width="3.5" stroke-linecap="round"/></svg>')
TEMPLATES = (HERE.parent / "templates", HERE.parent / "kit" / "fable-team" / "templates")  # 설치본·키트 bin 옆 → 팩 harness/bin 옆
SCHEMAS = {"summary": f'["{SUMMARY_LINES - 1}줄 이하"]', "important": '[{"title":"","detail":"","who":"팀","hot":false}]', "refs": '["근거 번호"]',
           "goals": '[{"done":"","now":"","left":"","hot":false}]', "team_notes": '[{"team":"live 의 team 그대로","text":""}]'}
FACT_RULES = ('- 입력 facts = 코드가 tmux 좌석·jsonl 로 잰 «사실» — 원장 문장과 어긋나면 facts 가 이긴다. «일하는 팀» 이 1개 이상이면 '
              '«모든 팀이 멈춤·대기·쉼» 같은 문장 금지 · 일하는/쉬는 팀 수·이름은 facts 그대로.\n'
              '- facts.확인 불가 팀은 쉬는 팀이 아니다 — 그 팀이 쉰다·멈췄다·대기 중이라고 상태를 단정하지 말 것(쓰려면 «상태 확인 불가»).\n'
              '- facts.자율 이 "ON" 이면 병합 승인은 desk 가 실행한다 — «사장님 승인을 기다린다» 금지 · "모름" 이면 승인·자율 이야기를 쓰지 않는다.')
PARTS = {  # 갈래 → (받을 키, 넘길 입력 키, 갈래 규칙, 예상 출력 글자) · r478e: 옛 top(요약+중요한 일+근거)을 2갈래로(부하 load 25 · max 에서 38.5초 상한 초과)
    "summary": (("summary", "refs"), ("now", "facts", "goals", "ledger", "urgent", "commits"),
                f'- "summary" = 1~{SUMMARY_LINES - 1}줄 · 네가 쓴 줄은 합쳐 500바이트 이하 · 첫 줄은 코드가 넣는다.\n'  # r590 — 견본과 같은 상한에서 만든다
                '- 팀 상태(일함·쉼·정지·확인 불가·몇 팀)는 쓰지 말 것 — 첫 줄 «팀 상태» 는 코드가 좌석 실측으로 넣는다(r588).\n'
                '- 근거 번호(#숫자 · 판정 번호 · 커밋 sha · 카드 번호)는 "refs" 에만(10개 이하).\n' + FACT_RULES, 700),
    "important": (("important",), ("now", "facts", "goals", "ledger", "urgent"),
                  '- "important" = 지금 제일 중요한 일 순서대로 1~7개 · title 한 마디 · detail 한 문장 · who = 팀 · 급한 불이면 "hot": true.\n' + FACT_RULES, 1000),
    "goals": (("goals",), ("now", "goals", "ledger"),
              '- "goals" = 입력 goals 순서 그대로 정확히 6개 · done(끝남)/now(지금)/left(남은 일) 각 한두 문장 · 급한 불이면 "hot": true.', 1800),
    "teams": (("team_notes",), ("now", "teams", "live"),
              '- "team_notes" = 입력 live 의 팀마다 정확히 1개 · team 은 live 의 team 글자 그대로 · text = 그 팀이 지금 하는 일 또는 기다리는 것 한 문장(입력 teams 근거).\n'
              '- 일하는 팀/쉬는 팀 판정·좌석 수는 쓰지 않는다 — 코드가 live(tmux 좌석·jsonl 실측)로 정한다.', 1200),
}
PROMPT = """너는 BYZ 팀 뉴스 편집자다. 아래 «입력» JSON 만 근거로 «팀 지도» 의 한 부분을 JSON 객체 하나로만 답한다 — 설명·코드 펜스 0.
규칙:
- 쉬운 말(바쁜 사장님이 1분에 읽는 말) · 내부어·약어·파일 경로 0.
- 번호(#숫자 · 판정 번호 · 커밋 sha · 카드 번호)는 본문 칸에 쓰지 않는다.
@RULES@
- 입력에 없는 것은 지어내지 않는다 — 모르면 "원천 없음".
@DEPTH@
출력 스키마: @SCHEMA@
입력:
@DATA@
"""


class NewsHtmlError(RuntimeError):
    pass


def model_id() -> str:
    m, eff = os.environ.get("FT_NEWS_MODEL") or MODEL, os.environ.get("FT_NEWS_EFFORT", "").strip()
    return f"{m}#{eff}" if eff and eff != "base" else m


def via() -> str:
    """호출 수단 — http(기본 · CLI 기동 0) | opencode(옛 경로 · 되돌림 = FT_NEWS_VIA=opencode)."""
    return (os.environ.get("FT_NEWS_VIA") or VIA_HTTP).strip()


def http_target() -> tuple[str, str, str]:
    """(주소, 모델, 키 이름) — 모델 id 접두가 공급자 · 접두 뒤가 모델 · 모르는 접두 = NewsHtmlError(조용한 CLI 대체 0)."""
    provider, _, model = model_id().split("#")[0].partition("/")
    if not model or provider not in HTTP_BASE:
        raise NewsHtmlError(f"모델 id 접두 {provider or '(없음)'} — HTTP 주소 없음(FT_NEWS_VIA=opencode 로 옛 경로 · 모델 id = <공급자>/<모델>)")
    return (os.environ.get("FT_NEWS_HTTP_BASE") or HTTP_BASE[provider]).rstrip("/") + "/chat/completions", model, HTTP_KEY[provider]


def pi_models_path() -> Path:
    """pi 설정 자리 — opengateway 키 출처(r575 · 시험은 FT_NEWS_PI_MODELS 로 대역)."""
    return Path(os.environ.get("FT_NEWS_PI_MODELS") or Path.home() / ".pi" / "agent" / "models.json").expanduser()


def pi_key() -> str:
    """pi 설정 providers.opengateway.apiKey → 키(pi models.md 꼴 3가지: 글자 그대로 · `$NAME`/`${NAME}` = 그 env · `!명령` = 그 명령 stdout).
    없거나 빈 값 = "" (호출부가 «키 없음») · 값은 반환만 하고 어디에도 출력하지 않는다."""
    try:
        cfg = json.loads(pi_models_path().read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return ""
    prov = cfg.get("providers") if isinstance(cfg, dict) else None
    raw = (prov.get("opengateway") or {}).get("apiKey") if isinstance(prov, dict) else None
    raw = raw.strip() if isinstance(raw, str) else ""
    if raw.startswith("!"):  # pi = 요청 때마다 명령을 돌린다(예: `!security find-generic-password -ws opengateway`)
        try:
            return subprocess.run(raw[1:], shell=True, capture_output=True, text=True, timeout=10).stdout.strip()  # noqa: S602
        except (OSError, subprocess.SubprocessError):
            return ""
    if raw.startswith("$"):  # $NAME · ${NAME}
        return (os.environ.get(raw.lstrip("$").strip("{}")) or "").strip()
    return raw


def api_key(name: str) -> str:
    """키 = env › (opengateway 면) pi 설정 › 키 파일(기본 ~/.zshrc) «마지막 활성 줄» · 없으면 NewsHtmlError · 값은 어디에도 출력하지 않는다."""
    if value := (os.environ.get(name) or "").strip():
        return value
    if name == HTTP_KEY["opengateway"]:  # r575 — opengateway 키 출처 = pi 설정 1곳(값 출력 0)
        if key := pi_key():
            return key
        raise NewsHtmlError(f"키 없음: {name} · pi 설정 opengateway({pi_models_path()})")
    file = Path(os.environ.get("FT_NEWS_KEY_FILE") or Path.home() / ".zshrc")
    try:
        lines = file.read_text(encoding="utf-8", errors="replace").splitlines(keepends=True)
    except OSError as e:
        raise NewsHtmlError(f"{name} 없음 (env·{file} 둘 다 — {e.strerror})") from e
    last = []
    for ln in lines:
        try:
            if p := parse_line(ln, name):
                last.append(p[2])
        except ValueError:
            continue
    if not last:
        raise NewsHtmlError(f"{name} 없음 (env·{file} 둘 다)")
    return last[-1].strip()


def build_prompt(data: dict, part: str) -> str:
    keys, inputs, rules, _ = PARTS[part]
    schema = "{" + ",".join(f'"{k}":{SCHEMAS[k]}' for k in keys) + "}"
    sub = {k: data[k] for k in inputs if k in data}
    return (PROMPT.replace("@RULES@", rules).replace("@DEPTH@", os.environ.get("FT_NEWS_DEPTH", "")).replace("@SCHEMA@", schema)
            .replace("@DATA@", json.dumps(sub, ensure_ascii=False, indent=1)))


def cap_s(prompt: str, part: str, fixed: float = FIXED_S) -> float:
    """시도당 상한(7초 룰 «크기 아는 배치») · fixed = CLI 기동 고정비(fixed_s)."""
    units = max(len(prompt.encode("utf-8")) / BYTES_PER_TOKEN / IN_TOKENS, PARTS[part][3] / OUT_CHARS)
    return min(fixed + UNIT_S * math.ceil(units), DEADLINE_S)


def startup_log() -> Path:
    if os.environ.get("FT_NEWS_STARTUP_LOG"):
        return Path(os.environ["FT_NEWS_STARTUP_LOG"])
    from ft_board_env import ft_root
    return ft_root() / ".fable-team" / "state" / "news-cli-startup.tsv"


def _startup_rows() -> list[str]:
    try:
        return startup_log().read_text(encoding="utf-8").splitlines()[-STARTUP_KEEP:]
    except FileNotFoundError:
        return []
    except (OSError, RuntimeError) as e:
        print(f"WARN 기동 기록 못 읽음 — 고정비 잠정 {FIXED_S}s: {e}", file=sys.stderr)
        return []


def fixed_s() -> float:
    """CLI 기동 고정비 = FT_NEWS_FIXED_S › 기록 p90(nearest-rank · «>상한» 은 그 상한값) › 기록 3개 미만 = 잠정 FIXED_S."""
    if os.environ.get("FT_NEWS_FIXED_S"):
        return float(os.environ["FT_NEWS_FIXED_S"])
    vals = []
    for ln in _startup_rows():
        try:
            vals.append(float(ln.rsplit("\t", 1)[-1].lstrip(">")))
        except ValueError:
            continue
    vals.sort()
    return vals[math.ceil(0.9 * len(vals)) - 1] if len(vals) >= STARTUP_MIN else FIXED_S


def record_startup(part: str, first: float | None, cap: float) -> None:
    """시도 1개 = 1줄 «시각\t갈래\t첫 출력까지 초 | >상한» · 최근 STARTUP_KEEP 줄만 · 쓰기 실패 = WARN(발행은 계속)."""
    row = f"{datetime.now():%Y-%m-%d %H:%M:%S}\t{part}\t" + (f"{first:.1f}" if first is not None else f">{cap:.1f}")
    try:
        f = startup_log()
        with _STARTUP_LOCK:
            f.parent.mkdir(parents=True, exist_ok=True)
            old = f.read_text(encoding="utf-8").splitlines() if f.is_file() else []
            tmp = f.with_name(f"{f.name}.{os.getpid()}.tmp")
            tmp.write_text("\n".join([*old, row][-STARTUP_KEEP:]) + "\n", encoding="utf-8")
            os.replace(tmp, f)
    except (OSError, RuntimeError) as e:
        print(f"WARN 기동 기록 못 씀 — 발행은 계속: {e}", file=sys.stderr)


def _texts(stdout: str) -> str:
    """--format json 이벤트 줄 중 type=text 의 part.text 를 이어 붙인다(다른 줄·깨진 줄은 무시)."""
    out = []
    for ln in stdout.splitlines():
        try:
            ev = json.loads(ln)
        except ValueError:
            continue
        if isinstance(ev, dict) and ev.get("type") == "text":
            out.append(str((ev.get("part") or {}).get("text", "")))
    return "".join(out)


def _once(cmd: list[str], left: float, part: str) -> tuple[int | None, str, str, float | None]:
    """(rc, stdout, stderr, 첫 출력까지 초 | None) — 시간 초과 = (None, 그때까지 stdout, 사유, …). 답 글은 끝에 한 번에 오므로 초과 = «첫 출력 전 실패»(r478e).
    첫 출력 = stdout 첫 바이트(r510 — 기동 고정비 실측 · 답 글이 끝에 한 번에 오면 완료 시각과 같다 = 보수적)."""
    t0 = time.monotonic()
    p = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
    got, first = {"out": b"", "err": b""}, []

    def pump(f, key: str) -> None:
        while b := f.read1(65536):
            if key == "out" and not first:
                first.append(time.monotonic() - t0)
            got[key] += b
    ths = [threading.Thread(target=pump, args=a, daemon=True) for a in ((p.stdout, "out"), (p.stderr, "err"))]
    for t in ths:
        t.start()
    try:
        p.wait(timeout=left)
        for t in ths:  # 프로세스가 끝나도 손주가 파이프를 쥐면 상한까지만 기다린다
            t.join(max(0.0, t0 + left - time.monotonic()))
        over = any(t.is_alive() for t in ths)
    except subprocess.TimeoutExpired:
        over = True
    if over:
        os.killpg(p.pid, signal.SIGKILL)  # --standalone 사설 서버까지 묶음째(잔존 0)
        p.wait()
        for t in ths:
            t.join()
    out, err = (got[k].decode("utf-8", "replace") for k in ("out", "err"))
    at = first[0] if first else None
    return (None, out, f"{part} 상한 {left:.0f}s 초과(총 마감 {DEADLINE_S}s)", at) if over else (p.returncode, out, err, at)


def _sse_text(lines) -> tuple[str, list, dict]:
    """OpenAI 호환 스트림 줄 → (이어 붙인 글, 첫 글 시각 목록, 끝난 이유 묶음) — data: 줄만 · 깨진 줄·[DONE] 무시.
    묶음 = {finish_reason: 마지막 값 · usage: 마지막 값 · reasoning: 생각(reasoning_content) 글자 수} — 답 글은 지금처럼 content 만(r582)."""
    out, first, meta = [], [], {"finish_reason": None, "usage": {}, "reasoning": 0}
    for raw in lines:
        if not first:
            first.append(time.monotonic())
        line = raw.decode("utf-8", "replace").strip()
        if not line.startswith("data:"):
            continue
        body = line[5:].strip()
        if body == "[DONE]":
            break
        try:
            ev = json.loads(body)
        except ValueError:
            continue
        if ev.get("usage"):
            meta["usage"] = ev["usage"]
        for ch in ev.get("choices") or []:
            delta = ch.get("delta") or {}
            text = delta.get("content") or ""
            if text:
                out.append(str(text))
            if delta.get("reasoning_content"):
                meta["reasoning"] += len(str(delta["reasoning_content"]))
            if ch.get("finish_reason"):
                meta["finish_reason"] = ch["finish_reason"]
    return "".join(out), first, meta


def _http_once(prompt: str, part: str, left: float) -> tuple[int | None, str, str, float | None]:
    """HTTP 1회 — (rc, 답 글, 사유, 첫 출력까지 초 | None). 스트림 첫 바이트까지 잰다 · 시간 초과 = (None, …, «상한 초과», None) = 첫 출력 전 실패(재시도 1)."""
    url, model, key = http_target()
    body = json.dumps({"model": model, "stream": True, "max_tokens": int(os.environ.get("FT_NEWS_HTTP_MAX_TOKENS", "2048")),  # 예상 출력 1800자 여유(무제한 = 모델 65536 요구 → 크레딧 초과 402 실측)
                       **REASONING_OFF,  # r582 — 생각 끄기(0단계 측정이 정한 필드 1곳)
                       "stream_options": {"include_usage": True},  # r582 — 잘림 계산 근거(토큰)를 usage 로 남긴다(0단계에서 이 공급자가 받는 것 확인)
                       "messages": [{"role": "user", "content": prompt}]}, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json", "Authorization": f"Bearer {api_key(key)}"})
    t0 = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=left) as r:  # noqa: S310 — 주소 = 공급자 표(시험은 로컬 서버)
            text, first, meta = _sse_text(r)
    except urllib.error.HTTPError as e:
        if e.code == 400 and REASONING_OFF:  # r582 — 생각 끄기 필드를 공급자가 거부 = 조용히 빼고 보내지 않고 ERROR 로 남긴다
            detail = e.read()[:160].decode("utf-8", "replace").replace("\n", " ")
            return e.code, "", f"{part} HTTP 400 — 생각 끄기 필드({','.join(REASONING_OFF)}) 거부: {detail}", None
        return e.code, "", f"{part} HTTP {e.code}", None
    except (socket.timeout, TimeoutError):
        return None, "", f"{part} 상한 {left:.0f}s 초과(총 마감 {DEADLINE_S}s)", None
    except (urllib.error.URLError, OSError) as e:
        return 1, "", f"{part} HTTP 실패: {e}", None
    at = first[0] - t0 if first else None
    diag = f"끝난 이유={meta['finish_reason'] or '없음'} · 답 {len(text)}자 · 생각 {meta['reasoning']}자"
    if meta["usage"]:  # usage 를 보내는 공급자(stream_options)면 토큰까지 남긴다 — 잘림 계산 근거
        diag += f" · 토큰 입{meta['usage'].get('prompt_tokens', '?')}/출{meta['usage'].get('completion_tokens', '?')}"
    if not text.strip():
        return 1, "", f"{part} 답 0자 · {diag}", at
    if meta["finish_reason"] == "length":  # 잘린 답 — JSON 파싱 실패로 오해하지 않게 이름 붙인다(발행 0)
        return 1, text, f"{part} 답이 잘림(finish_reason=length · 답 {len(text)}자 · 생각 {meta['reasoning']}자) — 발행 0", at
    return 0, text, "", at


def _json(text: str, part: str) -> dict:
    i, j = text.find("{"), text.rfind("}")
    try:
        c = json.loads(text[i:j + 1]) if 0 <= i < j else None
    except ValueError as e:
        raise NewsHtmlError(f"{part} 응답이 JSON 아님: {e}") from e
    if not isinstance(c, dict):
        raise NewsHtmlError(f"{part} 응답이 JSON 객체 아님")
    return {k: c.get(k) for k in PARTS[part][0]}


def call_part(data: dict, part: str, end: float, fixed: float = FIXED_S) -> tuple[dict, float]:
    """한 갈래 — (그 갈래 키 dict, 걸린 초). 첫 출력 전 실패(답 글 0 · 시도당 상한 초과 포함)만 1회 재시도 · 둘 다 총 마감 안.
    시도마다 «첫 출력까지 초»(시간 초과 = «>상한») 를 기동 기록에 1줄(r510) · http 경로는 CLI 기동 고정비 0(r563)."""
    prompt = build_prompt(data, part)
    how = via()
    if how == VIA_OPENCODE:
        cmd = [os.environ.get("FT_OPENCODE") or "opencode", "run", "--standalone", "--model", model_id(), "--format", "json", prompt]
    elif how != VIA_HTTP:
        raise NewsHtmlError(f"FT_NEWS_VIA={how} 모름 — http | opencode")
    start, why = time.monotonic(), ""
    for _ in range(2):
        left = min(cap_s(prompt, part, 0.0 if how == VIA_HTTP else fixed), end - time.monotonic())
        if left <= 1:
            break
        rc, out, err, first = _once(cmd, left, part) if how == VIA_OPENCODE else _http_once(prompt, part, left)
        if first is not None or rc is None:
            record_startup(part, first, left)
        text = _texts(out) if how == VIA_OPENCODE else out
        if rc == 0 and text.strip():
            return _json(text, part), time.monotonic() - start
        why = err.strip()[:200] if rc is None else f"rc={rc} 답 글 {len(text)}자 · {err.strip()[:200]}"
        if text.strip():
            break  # 출력이 시작된 뒤 실패 = 재시도 0
    raise NewsHtmlError(f"{how} {part} 실패({model_id()}): {why or '총 마감 남은 시간 없음'}")


def call_model(data: dict) -> tuple[dict, dict[str, float], float]:
    """갈래 전부 병렬 → (합친 내용, 갈래별 걸린 초, 기동 고정비). 하나라도 실패 = NewsHtmlError(나머지도 각자 상한 안에서 끝난다)."""
    end, fixed = time.monotonic() + DEADLINE_S, fixed_s()
    if fixed >= DEADLINE_S:
        print(f"WARN 기동 고정비 p90 {fixed:.1f}s ≥ 천장 {DEADLINE_S}s — 갈래 상한 = 천장", file=sys.stderr)
    with ThreadPoolExecutor(len(PARTS)) as pool:
        futs = {p: pool.submit(call_part, data, p, end, fixed) for p in PARTS}
    content, secs = {}, {}
    for p, f in futs.items():
        got, secs[p] = f.result()
        content |= got
    return add_status_line(check_content(content | bucket(content.pop("team_notes"), data.get("live")))), secs, fixed


def bucket(notes: object, live: object) -> dict[str, list[dict]]:
    """일하는/쉬는 팀 = 코드가 live(팀별 tmux 좌석·jsonl turn 실측)로 정한다(r478c · 오빠 반려 «일하는 챗봇이 쉬는 쪽에»).
    일하는 팀 = 일하는 좌석(WORKING) ≥ 1 · 일하는 좌석 많은 순 · LLM 은 팀별 설명 한 문장만(없으면 «설명 없음» 그대로).
    확인 불가 = 일하는 0 ∧ turn «?» ≥ 1(사유 칸 · r490 · 오빠 «챗봇팀은 왜쉬어?») · 쉬는 팀 = 일하는 0 ∧ 확인 불가 0."""
    if not isinstance(live, list) or not live:
        raise NewsHtmlError("입력 live(팀별 라이브 좌석 실측) 없음 — 일하는/쉬는 팀을 정할 수 없다")
    text = {str(n.get("team", "")).strip(): str(n.get("text", "")).strip() for n in notes if isinstance(n, dict)} if isinstance(notes, list) else {}
    work = sorted((t for t in live if t["working"]), key=lambda t: (-t["working"], t["team"]))
    unknown = lambda t: f" · 확인 불가 {t['unknown']}" if t.get("unknown") else ""  # noqa: E731
    why = lambda t: t.get("unknown_reason") or f"turn 확인 불가 {t['unknown']}석"  # noqa: E731
    return {"working": [{"team": t["team"], "seats": f"일하는 좌석 {t['working']}/{t['live']}{unknown(t)}", "note": text.get(t["team"]) or "설명 없음"} for t in work],
            "unknown": [{"team": t["team"], "text": f"라이브 좌석 {t['live']} · 확인 불가 {t['unknown']} ({why(t)}) · {text.get(t['team']) or '설명 없음'}"}
                        for t in live if not t["working"] and t.get("unknown")],
            "resting": [{"team": t["team"], "text": f"라이브 좌석 {t['live']} · 일하는 좌석 0 · {text.get(t['team']) or '설명 없음'}"}
                        for t in live if not t["working"] and not t.get("unknown")]}


def status_line(c: dict) -> str:
    """팀 상태 1~3문장 — 코드가 live(좌석·jsonl)로 정한 셋(일하는/쉬는/확인 불가)에서 «0개 칸은 생략»(r588).
    모델에게 이 문장을 쓰게 하지 않는다 — 00:57 판은 확인 불가 팀(feature·graphics·harness)을 «쉬며» 절에 넣어 린트 3건으로 발행 0."""
    rows = (("일하는 팀", c["working"]), ("쉬는 팀", c["resting"]), ("상태 확인 불가", c["unknown"]))
    said = [f"{label} {len(group)}개: {', '.join(t['team'] for t in group)}" for label, group in rows if group]
    return ". ".join(said) or "팀 상태 원천 없음"


def add_status_line(c: dict) -> dict:
    """summary 첫 줄 = 코드가 만든 팀 상태 줄(원문 그대로 · r588) · 상태 줄 포함 3줄·600B 넘으면 «자르지 않고» ERROR(조용한 자르기 0)."""
    c["summary"] = [status_line(c), *[s.strip() for s in c["summary"] if s.strip()]]
    text = "\n".join(c["summary"])
    if len(c["summary"]) > SUMMARY_LINES or len(text.encode("utf-8")) > SUMMARY_BYTES:
        raise NewsHtmlError(f"요약 {len(c['summary'])}줄·{len(text.encode('utf-8'))}B — 팀 상태 줄 포함 {SUMMARY_LINES}줄·{SUMMARY_BYTES}B 이내여야 한다(자르지 않는다)")
    return c


def check_content(c: dict) -> dict:
    """합친 내용 꼴 검사 — 필수 키·꼴 어긋남·골 6 아님 = NewsHtmlError(자르기·채우기 0)."""
    need = {"summary": str, "important": dict, "goals": dict, "working": dict, "unknown": dict, "resting": dict}
    for key, kind in need.items():
        if not isinstance(c.get(key), list) or not all(isinstance(x, kind) for x in c[key]):
            raise NewsHtmlError(f"응답 필수 키 없음·꼴 다름: {key}")
    if len(c["goals"]) != 6 or any(not isinstance(g.get(k), str) for g in c["goals"] for k in ("done", "now", "left")):
        raise NewsHtmlError(f"응답 goals {len(c['goals'])}개 — 6개·done/now/left 글이어야")
    c["refs"] = [str(r) for r in c.get("refs") or []]
    return c


def _e(v: object) -> str:
    return html.escape(str(v or ""), quote=False)


def _goal(n: int, meta: dict, g: dict) -> dict[str, str]:
    left = g["left"].strip()
    tone = "hot" if g.get("hot") else ("done" if left in ("", "-", "없음") else "now")
    now = '<div class="step s-hot"><b>급한 불</b>' if g.get("hot") else '<div class="step s-now"><b>지금</b>'
    team = re.sub(r"\s*\([^)]*\)", "", str(meta.get("team", ""))).strip()
    track = "\n".join(f"        {a}{_e(b)}</div>" for a, b in (('<div class="step s-done"><b>끝남</b>', g["done"]), (now, g["now"]), ('<div class="step s-left"><b>남은 일</b>', left)))
    return {f"G{n}_TONE": tone, f"G{n}_HEAD": _e(f"골 {n} · {team}"), f"G{n}_SAY": _e(meta.get("goal", "")), f"G{n}_TRACK": track}


def _work_card(t: dict) -> str:
    """일하는 팀 = 골 카드와 같은 그림 카드(r478d · 오빠 2차 반려 «챗봇이 아래에 텍스트만») — 좌석 수는 코드 · 설명은 LLM 한 문장."""
    return (f'  <section class="goal work">\n    {WORK_ICON}\n    <div class="body">\n      <span class="gnum">{_e(t["seats"])}</span>\n'
            f'      <p class="say">{_e(t["team"])}</p>\n      <div class="track">\n        <div class="step s-now"><b>지금</b>{_e(t["note"])}</div>\n'
            '      </div>\n    </div>\n  </section>')


def render(c: dict, goals: list[dict], now: datetime, autonomy: str = "모름") -> str:
    """autonomy = 자율 모드 실측(ON·OFF·모름) — 각주에 «자율 X» 로 싣고 린트가 승인 문장을 그 값과 대조한다(r478d)."""
    tpl = next((d / "news-team-map.html" for d in TEMPLATES if (d / "news-team-map.html").is_file()), None)
    if tpl is None:
        raise NewsHtmlError(f"틀 없음 news-team-map.html ({', '.join(map(str, TEMPLATES))})")
    vals = {"STAMP": f"{now:%m-%d %H:%M}", "LEAD": f"{now:%Y-%m-%d %H:%M} 기준 · 스크립트가 원장·카드·세션 상태·main 커밋을 모아 정리한 지도",
            "IMPORTANT": "\n".join(f'      <li{HOT if x.get("hot") else ""}><div class="what"><strong>{_e(x.get("title"))}</strong>'
                                   f'<span>{_e(x.get("detail"))}</span></div><span class="who">{_e(x.get("who"))}</span></li>' for x in c["important"]),
            "WORKING": "\n".join(map(_work_card, c["working"])) or '  <p class="lead">지금 일하는 좌석 0 (tmux 좌석·jsonl 실측)</p>',
            "UNKNOWN": "\n".join(f'    <div class="team unk"><strong>{_e(t.get("team"))}</strong>{_e(t.get("text"))}</div>' for t in c["unknown"]),
            "RESTING": "\n".join(f'    <div class="team rest"><strong>{_e(t.get("team"))}</strong>{_e(t.get("text"))}</div>' for t in c["resting"]),
            "FOOT": _e(f"근거: {' · '.join(c['refs']) or '원장·카드·세션 상태·main 커밋'} · 자율 {autonomy} · 정리 {model_id()}")}
    for n, (meta, g) in enumerate(zip(goals, c["goals"]), 1):
        vals |= _goal(n, meta, g)
    out = re.sub(r"\{\{(\w+)\}\}", lambda m: vals.get(m[1], m[0]), tpl.read_text(encoding="utf-8"))
    if left := re.findall(r"\{\{\w+\}\}", out):
        raise NewsHtmlError(f"틀 값 못 채움: {left[:3]}")
    return out
