"""ft_news_html_lint — 뉴스 HTML 모드(r478) 게시 «전» 검사: 팀 지도 HTML + 요약. 통과 = `OK` rc0 · 위반 = `LINT <무엇>` 줄들 rc3(발행 0).

규칙: 절 6(h1 «우리 팀들, 지금 어디쯤?» + h2 5개 · r490 «확인 불가») · 중요한 일 1~7 · 골 6행 · 본문 번호(#숫자·판정 N·sha 꼴)는 맨 아래 각주(<p class="foot">)에만 ·
요약 1~3줄·≤600 B · 시크릿 꼴 0(HTML·요약 둘 다) · 요약·중요한 일이 코드 판정과 어긋남 0(fact_problems · r478d · r490 확인 불가 팀 쉼 단정).
쓰는 쪽 = ft_news_html.py publish · ft-news-effort-test.sh.
  ft_news_html_lint.py <html> <summary>
"""
import re
import sys
from pathlib import Path

H1 = "우리 팀들, 지금 어디쯤?"
H2 = ("지금 제일 중요한 일 (순서대로)", "일하는 팀", "확인 불가", "골 6개", "쉬는 팀")  # r478d: 일하는 팀 = 골 카드 위 그림 카드 · r490: 확인 불가 ≠ 쉬는 팀
MAX_IMPORTANT, GOALS = 7, 6
SUMMARY_LINES, SUMMARY_BYTES = 3, 600
SECRET = re.compile(r"xox[abposr]-[\w-]{6,}|sk-[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|AIza[\w-]{30,}"
                    r"|-----BEGIN [A-Z ]*PRIVATE KEY-----|eyJ[\w-]{10,}\.[\w-]{10,}\.[\w-]{10,}")
NUMBER = re.compile(r"#\d+|판정\s*\d+|\b(?=[0-9a-f]*[a-f])(?=[0-9a-f]*\d)[0-9a-f]{7,40}\b")
FOOT = re.compile(r'<p class="foot">.*?</p>', re.S)
ALL_STOP = re.compile(r"(모든|전체)\s*팀[^.\n]{0,40}?(멈|정지|대기|쉬)|전\s?팀(이|은|들이|들은)\s[^.\n]{0,40}?(멈|정지|대기|쉬)"  # «전팀 지침…» 제목은 조사 없음 = 제외
                      r"|팀(이|은|들이|들은)?\s*(모두|전부|다)\s[^.\n]{0,20}?(멈|정지|대기|쉬)")
APPROVAL_WAIT = re.compile(r"승인[^.\n]{0,15}?(기다|대기)")
REST_SAID = re.compile(r"쉬|멈|정지|대기")
NEGATED_TAIL = re.compile(r"[^,，.\n]{0,24}?(지\s*않|지\s*못|아니|아닙|않습니다|않는다|않음)")  # r498: 쉼 글자 «뒤» 같은 절의 부정 꼬리
CLAUSE_END = re.compile(r"[,，.\n]|며 ")  # «고 » 로는 자르지 않는다 — «멈췄다고 단정하지 않» 의 «다고» 가 잘린다
QUESTION_TAIL = re.compile(r"는지|ㄴ지|은지|던지|었는지|았는지|했는지|인지")  # r602: «쉬는지 일하는지 확인 불가다» = 물음꼴 = 단정 아님
UNKNOWN_TEAM = re.compile(r'<div class="team unk"><strong>(.*?)</strong>')


def _text(html: str) -> str:
    """보이는 글만 — style·svg·태그(속성 안 색 값 #0f7c86 등)를 지운다."""
    html = re.sub(r"<style>.*?</style>|<svg.*?</svg>", " ", html, flags=re.S)
    return re.sub(r"<[^>]+>", " ", html)


def problems(html: str, summary: str) -> list[str]:
    out: list[str] = []
    h1 = re.findall(r"<h1>(.*?)</h1>", html, re.S)
    h2 = [re.sub(r"<[^>]+>", "", h).strip() for h in re.findall(r"<h2[^>]*>(.*?)</h2>", html, re.S)]
    if h1 != [H1] or h2 != list(H2):
        out.append(f"절 6 아님 — h1={h1} h2={h2}")
    prio = re.search(r'<section class="prio">(.*?)</section>', html, re.S)
    n = len(re.findall(r"<li[ >]", prio[1])) if prio else 0
    if not 1 <= n <= MAX_IMPORTANT:
        out.append(f"중요한 일 {n}개 (1~{MAX_IMPORTANT})")
    if (g := html.count('<section class="goal">')) != GOALS:
        out.append(f"골 {g}행 ({GOALS}행이어야)")
    if found := NUMBER.findall(_text(FOOT.sub(" ", html))):
        out.append(f"각주 밖 번호 {len(found)}건 ({', '.join(found[:3])})")
    lines = [ln for ln in summary.splitlines() if ln.strip()]
    if not 1 <= len(lines) <= SUMMARY_LINES or len(summary.encode("utf-8")) > SUMMARY_BYTES:
        out.append(f"요약 {len(lines)}줄·{len(summary.encode('utf-8'))}B ({SUMMARY_LINES}줄·{SUMMARY_BYTES}B 이내)")
    if SECRET.search(html) or SECRET.search(summary):
        out.append("시크릿 꼴 있음")
    return out + fact_problems(html, summary, prio[1] if prio else "")


def _segments(summary: str, prio: str) -> list[tuple[str, str]]:
    """위반 문구에 «갈래 + 번호 + 문장 전문» 을 남기려고 요약 줄·중요한 일 항목을 따로 센다(r594 · 지어냄/원장 사실 판정용)."""
    segs = [(f"summary {i}", ln.strip()) for i, ln in enumerate((x for x in summary.splitlines() if x.strip()), 1)]
    items = re.findall(r"<li[ >].*?</li>", prio, re.S)
    return segs + [(f"important {i}", _text(li).strip()) for i, li in enumerate(items, 1)]


def _quote(sent: str) -> str:
    return " ".join(sent.split())[:200]


def _first(segs: list[tuple[str, str]], rx: re.Pattern) -> tuple[str, str] | None:
    return next(((label, sent) for label, sent in segs if rx.search(sent)), None)


def fact_problems(html: str, summary: str, prio: str) -> list[str]:
    """요약·중요한 일 문장 ↔ 코드 판정(r478d · desk 실측 거짓 문장): 일하는 팀(지도 «일하는 팀» 칸 = 라이브 좌석 실측) ≥1 인데
    «모든 팀 … 멈춤·대기» = 위반 · 각주 «자율 ON|OFF|모름» 이 OFF 가 아닌데 «승인 … 기다림» = 위반(ON 이면 desk 가 병합 · 모름이면 쓰지 않는다).
    r594: 위반 문구에 갈래·번호와 문장 전문을 싣는다 — «승인을 기다» 조각만으로는 모델 지어냄인지 원장 사실인지 못 가른다."""
    out: list[str] = []
    segs = _segments(summary, prio)
    said = summary + "\n" + _text(prio)
    working = html.count('<section class="goal work">')  # 일하는 팀 카드 = 라이브 좌석 실측(코드)
    if working and (hit := _first(segs, ALL_STOP)):
        out.append(f"일하는 팀 {working}개인데 멈춤 단정 문장 [{hit[0]}] «{_quote(hit[1])}»")
    foot = FOOT.search(html)
    auto = re.search(r"자율 (ON|OFF|모름)", foot[0]) if foot else None
    auto_v = auto[1] if auto else "모름"
    if auto_v != "OFF" and (hit := _first(segs, APPROVAL_WAIT)):
        out.append(f"자율 {auto_v} 인데 승인 대기 문장 [{hit[0]}] «{_quote(hit[1])}»")
    return out + unknown_problems(html, said)


def _rest_asserted(s: str) -> bool:
    """쉼 글자 하나라도 «뒤» 같은 절 안에 부정 꼬리가 없으면 단정(r498 · «쉰다거나 멈췄다고 단정하지 않습니다» 는 단정 아님).
    r602: 쉼 글자 바로 뒤 6자 안이 물음꼴(는지·ㄴ지·…)이면 «모른다» 는 말이므로 단정 아님 — «쉬고 있다»·«대기 중이다» 는 그대로 단정."""
    def asserted(m: re.Match) -> bool:
        tail = CLAUSE_END.split(s[m.end():], maxsplit=1)[0]
        return not (QUESTION_TAIL.search(tail[:6]) or NEGATED_TAIL.match(tail))
    return any(asserted(m) for m in REST_SAID.finditer(s))


def unknown_problems(html: str, said: str) -> list[str]:
    """«확인 불가» 블록 팀(turn 시간 초과·실패 = 모름 · r490 · 오빠 «챗봇팀은 왜쉬어?»)을 이름으로 짚은 «절» 에 쉬·멈·정지·대기 단정 = 위반.
    r588: 판정은 절(CLAUSE_END 로 나눈 조각) 단위 — 한 문장 안에 확인 불가 팀과 «쉬며» 절이 같이 있어도(00:57 판 «지금은 다섯 팀…이 쉬며, 세 팀(feature·graphics·harness)은 상태 확인 불가다») 절이 다르면 위반이 아니다. 보고 문구는 문장 그대로."""
    out: list[str] = []
    for team in dict.fromkeys(t.strip() for t in UNKNOWN_TEAM.findall(html)):
        name = re.compile(rf"(?<![\w-]){re.escape(team)}(?![\w-])")
        for s in re.split(r"[.\n]", said):
            if name.search(s) and any(_rest_asserted(cl) for cl in CLAUSE_END.split(s) if name.search(cl)):
                out.append(f"확인 불가 팀 {team} 에 쉼 단정 «{s.strip()}»")
                break
    return out


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    found = problems(Path(argv[0]).read_text(encoding="utf-8"), Path(argv[1]).read_text(encoding="utf-8"))
    print("\n".join(f"LINT {p}" for p in found) or "OK")
    return 3 if found else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
