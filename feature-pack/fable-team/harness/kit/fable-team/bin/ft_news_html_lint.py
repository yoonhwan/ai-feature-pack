"""ft_news_html_lint — 뉴스 HTML 모드(r478) 게시 «전» 검사: 팀 지도 HTML + 요약. 통과 = `OK` rc0 · 위반 = `LINT <무엇>` 줄들 rc3(발행 0).

규칙: 절 5(h1 «우리 팀들, 지금 어디쯤?» + h2 4개) · 중요한 일 1~7 · 골 6행 · 본문 번호(#숫자·판정 N·sha 꼴)는 맨 아래 각주(<p class="foot">)에만 ·
요약 1~3줄·≤600 B · 시크릿 꼴 0(HTML·요약 둘 다) · 요약·중요한 일이 코드 판정과 어긋남 0(fact_problems · r478d). 쓰는 쪽 = ft_news_html.py publish · ft-news-effort-test.sh.
  ft_news_html_lint.py <html> <summary>
"""
import re
import sys
from pathlib import Path

H1 = "우리 팀들, 지금 어디쯤?"
H2 = ("지금 제일 중요한 일 (순서대로)", "일하는 팀", "골 6개", "쉬는 팀")  # r478d: 일하는 팀 = 골 카드 위 그림 카드
MAX_IMPORTANT, GOALS = 7, 6
SUMMARY_LINES, SUMMARY_BYTES = 3, 600
SECRET = re.compile(r"xox[abposr]-[\w-]{6,}|sk-[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|AIza[\w-]{30,}"
                    r"|-----BEGIN [A-Z ]*PRIVATE KEY-----|eyJ[\w-]{10,}\.[\w-]{10,}\.[\w-]{10,}")
NUMBER = re.compile(r"#\d+|판정\s*\d+|\b(?=[0-9a-f]*[a-f])(?=[0-9a-f]*\d)[0-9a-f]{7,40}\b")
FOOT = re.compile(r'<p class="foot">.*?</p>', re.S)
ALL_STOP = re.compile(r"(모든|전체)\s*팀[^.\n]{0,40}?(멈|정지|대기|쉬)|전\s?팀(이|은|들이|들은)\s[^.\n]{0,40}?(멈|정지|대기|쉬)"  # «전팀 지침…» 제목은 조사 없음 = 제외
                      r"|팀(이|은|들이|들은)?\s*(모두|전부|다)\s[^.\n]{0,20}?(멈|정지|대기|쉬)")
APPROVAL_WAIT = re.compile(r"승인[^.\n]{0,15}?(기다|대기)")


def _text(html: str) -> str:
    """보이는 글만 — style·svg·태그(속성 안 색 값 #0f7c86 등)를 지운다."""
    html = re.sub(r"<style>.*?</style>|<svg.*?</svg>", " ", html, flags=re.S)
    return re.sub(r"<[^>]+>", " ", html)


def problems(html: str, summary: str) -> list[str]:
    out: list[str] = []
    h1 = re.findall(r"<h1>(.*?)</h1>", html, re.S)
    h2 = [re.sub(r"<[^>]+>", "", h).strip() for h in re.findall(r"<h2[^>]*>(.*?)</h2>", html, re.S)]
    if h1 != [H1] or h2 != list(H2):
        out.append(f"절 5 아님 — h1={h1} h2={h2}")
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


def fact_problems(html: str, summary: str, prio: str) -> list[str]:
    """요약·중요한 일 문장 ↔ 코드 판정(r478d · desk 실측 거짓 문장): 일하는 팀(지도 «일하는 팀» 칸 = 라이브 좌석 실측) ≥1 인데
    «모든 팀 … 멈춤·대기» = 위반 · 각주 «자율 ON|OFF|모름» 이 OFF 가 아닌데 «승인 … 기다림» = 위반(ON 이면 desk 가 병합 · 모름이면 쓰지 않는다)."""
    out: list[str] = []
    said = summary + "\n" + _text(prio)
    working = html.count('<section class="goal work">')  # 일하는 팀 카드 = 라이브 좌석 실측(코드)
    if working and (m := ALL_STOP.search(said)):
        out.append(f"일하는 팀 {working}개인데 «{m[0].strip()}» 문장")
    foot = FOOT.search(html)
    auto = re.search(r"자율 (ON|OFF|모름)", foot[0]) if foot else None
    auto_v = auto[1] if auto else "모름"
    if auto_v != "OFF" and (m := APPROVAL_WAIT.search(said)):
        out.append(f"자율 {auto_v} 인데 «{m[0].strip()}» 문장")
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
