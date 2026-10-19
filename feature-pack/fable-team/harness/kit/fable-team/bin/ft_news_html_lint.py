"""ft_news_html_lint — 뉴스 HTML 모드(r478) 게시 «전» 검사: 팀 지도 HTML + 요약. 통과 = `OK` rc0 · 위반 = `LINT <무엇>` 줄들 rc3(발행 0).

규칙: 절 5(h1 «우리 팀들, 지금 어디쯤?» + h2 4개) · 중요한 일 1~7 · 골 6행 · 본문 번호(#숫자·판정 N·sha 꼴)는 맨 아래 각주(<p class="foot">)에만 ·
요약 1~3줄·≤600 B · 시크릿 꼴 0(HTML·요약 둘 다). 쓰는 쪽 = ft_news_html.py publish · ft-news-effort-test.sh.
  ft_news_html_lint.py <html> <summary>
"""
import re
import sys
from pathlib import Path

H1 = "우리 팀들, 지금 어디쯤?"
H2 = ("지금 제일 중요한 일 (순서대로)", "골 6개", "일하는 팀", "쉬는 팀")
MAX_IMPORTANT, GOALS = 7, 6
SUMMARY_LINES, SUMMARY_BYTES = 3, 600
SECRET = re.compile(r"xox[abposr]-[\w-]{6,}|sk-[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|AIza[\w-]{30,}"
                    r"|-----BEGIN [A-Z ]*PRIVATE KEY-----|eyJ[\w-]{10,}\.[\w-]{10,}\.[\w-]{10,}")
NUMBER = re.compile(r"#\d+|판정\s*\d+|\b(?=[0-9a-f]*[a-f])(?=[0-9a-f]*\d)[0-9a-f]{7,40}\b")
FOOT = re.compile(r'<p class="foot">.*?</p>', re.S)


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
