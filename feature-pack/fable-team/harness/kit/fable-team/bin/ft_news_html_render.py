"""ft_news_html_render — 뉴스 HTML 모드(r478)의 «프롬프트 → opencode run 1회 → 내용 JSON → 고정 틀 HTML». 쓰는 쪽 = ft_news_html.py.

LLM 은 «내용(JSON · 수백 자)» 만 낸다 — 틀(CSS·절 머리·골 그림)은 templates/news-team-map.html 에 고정(기준본 BYZ-team-map-ref-20261019.html 과 같은 모양).
상한(하드 룰 12 · 판정 1375 «크기 아는 배치») = 총 마감 70초 · 재시도는 «첫 출력 전 실패» 1회만 · 실패 = NewsHtmlError(발행 0 · #0 RULE).
opencode run --standalone = 비대화 1회 · 새 서버를 남기지 않는다(arch 102 실측 잔존 0) — 시간 초과면 프로세스 묶음째 kill.
env: FT_NEWS_MODEL(기본 opencode/deepseek-v4.1-flash-free) · FT_NEWS_EFFORT(변형 → --model <ID>#<변형> · 비거나 base = 변형 없음) · FT_NEWS_DEPTH(프롬프트 «깊이» 문장 · 변형이 없을 때 대체) · FT_OPENCODE(기본 opencode)
"""
import html
import json
import os
import re
import signal
import subprocess
import time
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODEL = "opencode/deepseek-v4.1-flash-free"
DEADLINE_S = 70
HOT = ' class="hot"'
TEMPLATES = (HERE.parent / "templates", HERE.parent / "kit" / "fable-team" / "templates")  # 설치본·키트 bin 옆 → 팩 harness/bin 옆
SCHEMA = ('{"summary":["3줄 이하"],"important":[{"title":"","detail":"","who":"팀","hot":false}],'
          '"goals":[{"done":"","now":"","left":"","hot":false}],"working":[{"team":"","text":""}],"resting":[{"team":"","text":""}],"refs":["근거 번호"]}')
PROMPT = """너는 BYZ 팀 뉴스 편집자다. 아래 «입력» JSON 만 근거로 «팀 지도» 내용을 JSON 객체 하나로만 답한다 — 설명·코드 펜스 0.
규칙:
- 쉬운 말(바쁜 사장님이 1분에 읽는 말) · 내부어·약어·파일 경로 0.
- 번호(#숫자 · 판정 번호 · 커밋 sha · 카드 번호)는 본문 칸에 쓰지 않는다 — 근거 번호는 "refs" 에만.
- "summary" = 1~3줄 · 합쳐 600바이트 이하 · 첫 줄 = 지금 가장 중요한 한 가지.
- "important" = 지금 제일 중요한 일 순서대로 1~7개 · 급한 불이면 "hot": true.
- "goals" = 입력 goals 순서 그대로 정확히 6개 · done(끝남)/now(지금)/left(남은 일) 각 한두 문장 · 급한 불이면 "hot": true.
- "working" = 일하는 팀 · "resting" = 쉬는 팀(일하는 좌석 0) — 입력 teams 근거.
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


def build_prompt(data: dict) -> str:
    return (PROMPT.replace("@DEPTH@", os.environ.get("FT_NEWS_DEPTH", "")).replace("@SCHEMA@", SCHEMA)
            .replace("@DATA@", json.dumps(data, ensure_ascii=False, indent=1)))


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


def _once(cmd: list[str], left: float) -> tuple[int, str, str]:
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding="utf-8", start_new_session=True)
    try:
        out, err = p.communicate(timeout=left)
    except subprocess.TimeoutExpired as e:
        os.killpg(p.pid, signal.SIGKILL)  # --standalone 사설 서버까지 묶음째(잔존 0)
        p.communicate()
        raise NewsHtmlError(f"opencode run 총 마감 {DEADLINE_S}s 초과") from e
    return p.returncode, out, err


def call_model(prompt: str) -> tuple[str, float]:
    """(답 글, 걸린 초). 첫 출력 전 실패(답 글 0)만 1회 재시도 · 총 마감 DEADLINE_S."""
    cmd = [os.environ.get("FT_OPENCODE") or "opencode", "run", "--standalone", "--model", model_id(), "--format", "json", prompt]
    start, why = time.monotonic(), ""
    for attempt in range(2):
        left = DEADLINE_S - (time.monotonic() - start)
        if left <= 1:
            break
        rc, out, err = _once(cmd, left)
        text = _texts(out)
        if rc == 0 and text.strip():
            return text, time.monotonic() - start
        why = f"rc={rc} 답 글 {len(text)}자 · {err.strip()[:200]}"
        if text.strip():
            break  # 출력이 시작된 뒤 실패 = 재시도 0
    raise NewsHtmlError(f"opencode run 실패({model_id()}): {why}")


def parse_content(text: str) -> dict:
    """답 글 → 내용 dict. JSON 아님·필수 키·꼴 어긋남 = NewsHtmlError(자르기·채우기 0)."""
    i, j = text.find("{"), text.rfind("}")
    try:
        c = json.loads(text[i:j + 1]) if 0 <= i < j else None
    except ValueError as e:
        raise NewsHtmlError(f"응답이 JSON 아님: {e}") from e
    if not isinstance(c, dict):
        raise NewsHtmlError("응답이 JSON 객체 아님")
    need = {"summary": str, "important": dict, "goals": dict, "working": dict, "resting": dict}
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


def render(c: dict, goals: list[dict], now: datetime) -> str:
    tpl = next((d / "news-team-map.html" for d in TEMPLATES if (d / "news-team-map.html").is_file()), None)
    if tpl is None:
        raise NewsHtmlError(f"틀 없음 news-team-map.html ({', '.join(map(str, TEMPLATES))})")
    vals = {"STAMP": f"{now:%m-%d %H:%M}", "LEAD": f"{now:%Y-%m-%d %H:%M} 기준 · 스크립트가 원장·카드·세션 상태·main 커밋을 모아 정리한 지도",
            "IMPORTANT": "\n".join(f'      <li{HOT if x.get("hot") else ""}><div class="what"><strong>{_e(x.get("title"))}</strong>'
                                   f'<span>{_e(x.get("detail"))}</span></div><span class="who">{_e(x.get("who"))}</span></li>' for x in c["important"]),
            "WORKING": "\n".join(f'    <div class="team"><strong>{_e(t.get("team"))}</strong>{_e(t.get("text"))}</div>' for t in c["working"]),
            "RESTING": "\n".join(f'    <div class="team rest"><strong>{_e(t.get("team"))}</strong>{_e(t.get("text"))}</div>' for t in c["resting"]),
            "FOOT": _e(f"근거: {' · '.join(c['refs']) or '원장·카드·세션 상태·main 커밋'} · 정리 {model_id()}")}
    for n, (meta, g) in enumerate(zip(goals, c["goals"]), 1):
        vals |= _goal(n, meta, g)
    out = re.sub(r"\{\{(\w+)\}\}", lambda m: vals.get(m[1], m[0]), tpl.read_text(encoding="utf-8"))
    if left := re.findall(r"\{\{\w+\}\}", out):
        raise NewsHtmlError(f"틀 값 못 채움: {left[:3]}")
    return out
