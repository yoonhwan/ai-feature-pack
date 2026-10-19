"""ft_news_html_render — 뉴스 HTML 모드(r478)의 «프롬프트 → opencode run(갈래 4개 병렬) → 내용 JSON → 고정 틀 HTML». 쓰는 쪽 = ft_news_html.py.

LLM 은 «내용(JSON)» 만 낸다 — 틀(CSS·절 머리·골 그림)은 templates/news-team-map.html 에 고정(기준본 BYZ-team-map-ref-20261019.html 과 같은 모양).
7초 룰(하드 룰 12 · 판정 1375): 한 번에 내용 전부(출력 3~4.4K자 = 기준량 300자의 10배+)를 받으면 base 30~44초 · max 65초~130초+ 로 70초를 넘었다(r478b 실측)
→ «쪼갤 수 있으면 쪼갠다»: 갈래 4개(summary = 요약·근거 / important = 중요한 일 / goals = 골 6 / teams = 팀 설명 · r478e 에서 옛 top 을 둘로)를 «그 갈래에 필요한 입력만» 넣어 병렬로 부른다.
시도당 상한 = min(고정비 3.5 + 7 × ceil(max(입력 토큰 ÷ IN_TOKENS, 예상 출력 글자 ÷ OUT_CHARS)), 총 마감) · 재시도는 «첫 출력 전 실패» 1회만 · 갈래 전부 합친 총 마감 70초 · 실패 = NewsHtmlError(발행 0 · #0 RULE).
opencode run --standalone = 비대화 1회 · stdin 은 /dev/null(물려받은 stdin 이면 240초 동안 시작 0 실측) · 시간 초과면 프로세스 묶음째 kill.
env: FT_NEWS_MODEL(기본 opencode/deepseek-v4.1-flash-free) · FT_NEWS_EFFORT(변형 → --model <ID>#<변형> · 비거나 base = 변형 없음) · FT_NEWS_DEPTH(프롬프트 «깊이» 문장 · 변형이 없을 때 대체) · FT_OPENCODE(기본 opencode)
"""
import html
import json
import math
import os
import re
import signal
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODEL = "opencode/deepseek-v4.1-flash-free"
DEADLINE_S = 70
FIXED_S, UNIT_S, IN_TOKENS, OUT_CHARS, BYTES_PER_TOKEN = 3.5, 7, 2000, 300, 3  # 7초 룰 기준량 · CLI 기동 고정비 · 한글 섞인 글 ≈ 3 B/토큰(추정)
HOT = ' class="hot"'
WORK_ICON = ('<svg class="ic" viewBox="0 0 84 84" aria-hidden="true"><circle cx="42" cy="42" r="40" fill="var(--now-bg)"/><circle cx="26" cy="36" r="8" fill="var(--accent)"/>'
             '<circle cx="42" cy="30" r="9" fill="var(--done)"/><circle cx="58" cy="36" r="8" fill="var(--accent)"/>'
             '<path d="M14 62c2-10 22-10 24 0M30 60c2-12 22-12 24 0M46 62c2-10 22-10 24 0" fill="none" stroke="var(--ink)" stroke-width="3.5" stroke-linecap="round"/></svg>')
TEMPLATES = (HERE.parent / "templates", HERE.parent / "kit" / "fable-team" / "templates")  # 설치본·키트 bin 옆 → 팩 harness/bin 옆
SCHEMAS = {"summary": '["3줄 이하"]', "important": '[{"title":"","detail":"","who":"팀","hot":false}]', "refs": '["근거 번호"]',
           "goals": '[{"done":"","now":"","left":"","hot":false}]', "team_notes": '[{"team":"live 의 team 그대로","text":""}]'}
FACT_RULES = ('- 입력 facts = 코드가 tmux 좌석·jsonl 로 잰 «사실» — 원장 문장과 어긋나면 facts 가 이긴다. «일하는 팀» 이 1개 이상이면 '
              '«모든 팀이 멈춤·대기·쉼» 같은 문장 금지 · 일하는/쉬는 팀 수·이름은 facts 그대로.\n'
              '- facts.확인 불가 팀은 쉬는 팀이 아니다 — 그 팀이 쉰다·멈췄다·대기 중이라고 상태를 단정하지 말 것(쓰려면 «상태 확인 불가»).\n'
              '- facts.자율 이 "ON" 이면 병합 승인은 desk 가 실행한다 — «사장님 승인을 기다린다» 금지 · "모름" 이면 승인·자율 이야기를 쓰지 않는다.')
PARTS = {  # 갈래 → (받을 키, 넘길 입력 키, 갈래 규칙, 예상 출력 글자) · r478e: 옛 top(요약+중요한 일+근거)을 2갈래로(부하 load 25 · max 에서 38.5초 상한 초과)
    "summary": (("summary", "refs"), ("now", "facts", "goals", "ledger", "urgent", "commits"),
                '- "summary" = 1~3줄 · 합쳐 600바이트 이하 · 첫 줄 = 지금 가장 중요한 한 가지.\n'
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


def build_prompt(data: dict, part: str) -> str:
    keys, inputs, rules, _ = PARTS[part]
    schema = "{" + ",".join(f'"{k}":{SCHEMAS[k]}' for k in keys) + "}"
    sub = {k: data[k] for k in inputs if k in data}
    return (PROMPT.replace("@RULES@", rules).replace("@DEPTH@", os.environ.get("FT_NEWS_DEPTH", "")).replace("@SCHEMA@", schema)
            .replace("@DATA@", json.dumps(sub, ensure_ascii=False, indent=1)))


def cap_s(prompt: str, part: str) -> float:
    """시도당 상한(7초 룰 «크기 아는 배치»)."""
    units = max(len(prompt.encode("utf-8")) / BYTES_PER_TOKEN / IN_TOKENS, PARTS[part][3] / OUT_CHARS)
    return min(FIXED_S + UNIT_S * math.ceil(units), DEADLINE_S)


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


def _once(cmd: list[str], left: float, part: str) -> tuple[int | None, str, str]:
    """(rc, stdout, stderr) — 시간 초과 = (None, 그때까지 stdout, 사유). 답 글은 끝에 한 번에 오므로 초과 = «첫 출력 전 실패»(r478e)."""
    p = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding="utf-8", start_new_session=True)
    try:
        out, err = p.communicate(timeout=left)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL)  # --standalone 사설 서버까지 묶음째(잔존 0)
        out, _ = p.communicate()
        return None, out or "", f"{part} 상한 {left:.0f}s 초과(총 마감 {DEADLINE_S}s)"
    return p.returncode, out, err


def _json(text: str, part: str) -> dict:
    i, j = text.find("{"), text.rfind("}")
    try:
        c = json.loads(text[i:j + 1]) if 0 <= i < j else None
    except ValueError as e:
        raise NewsHtmlError(f"{part} 응답이 JSON 아님: {e}") from e
    if not isinstance(c, dict):
        raise NewsHtmlError(f"{part} 응답이 JSON 객체 아님")
    return {k: c.get(k) for k in PARTS[part][0]}


def call_part(data: dict, part: str, end: float) -> tuple[dict, float]:
    """한 갈래 — (그 갈래 키 dict, 걸린 초). 첫 출력 전 실패(답 글 0 · 시도당 상한 초과 포함)만 1회 재시도 · 둘 다 총 마감 안."""
    prompt = build_prompt(data, part)
    cmd = [os.environ.get("FT_OPENCODE") or "opencode", "run", "--standalone", "--model", model_id(), "--format", "json", prompt]
    start, why = time.monotonic(), ""
    for _ in range(2):
        left = min(cap_s(prompt, part), end - time.monotonic())
        if left <= 1:
            break
        rc, out, err = _once(cmd, left, part)
        text = _texts(out)
        if rc == 0 and text.strip():
            return _json(text, part), time.monotonic() - start
        why = err.strip()[:200] if rc is None else f"rc={rc} 답 글 {len(text)}자 · {err.strip()[:200]}"
        if text.strip():
            break  # 출력이 시작된 뒤 실패 = 재시도 0
    raise NewsHtmlError(f"opencode run {part} 실패({model_id()}): {why or '총 마감 남은 시간 없음'}")


def call_model(data: dict) -> tuple[dict, dict[str, float]]:
    """갈래 전부 병렬 → (합친 내용, 갈래별 걸린 초). 하나라도 실패 = NewsHtmlError(나머지도 각자 상한 안에서 끝난다)."""
    end = time.monotonic() + DEADLINE_S
    with ThreadPoolExecutor(len(PARTS)) as pool:
        futs = {p: pool.submit(call_part, data, p, end) for p in PARTS}
    content, secs = {}, {}
    for p, f in futs.items():
        got, secs[p] = f.result()
        content |= got
    return check_content(content | bucket(content.pop("team_notes"), data.get("live"))), secs


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
