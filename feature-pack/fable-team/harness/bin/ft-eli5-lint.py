#!/usr/bin/env python3
"""ft-eli5-lint.py <렌더 산출물 md|html> [--terms <eli5_terms.json>] — 쉬운 말(eli5) 합격 기준 4 lint (GUIDE-eli5-criteria · PLAN §2-2).

기준 1 맨 위 한 화면(첫 `##`/`<h2` 앞) = 전문어·번호·sha 0 · 영역 블록 ≤3줄(+외 N건)  ·  기준 2 전문어 첫 등장은 `용어(풀이)` · 빈도 ≤ 요약 줄의 5%
기준 3 요약 ≤40줄 · 펼침(자세히) 밖에 sha·판정번호·#번호 0 · HTML ≤200KB  ·  기준 4 흐름 그림 1(svg 또는 흐름 표 · 상자 ≤7)
요약 = «자세히»(md `## 자세히` · html `<details`) 앞. rc 0 = 전부 통과 · 1 = 하나라도 불합격. lint 는 «오빠가 보는 파일»에 건다.
"""
import html as htmllib
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from ft_board_sheet_cards import term_re  # noqa: E402

NUM = re.compile(r"#\d+|판정\s*\d+|\b[0-9a-f]{7,}\b")
MAX_SUMMARY, MAX_HTML_B, MAX_BOX, AREA_LINES, FREQ = 40, 200_000, 7, 4, 0.05


def regions(raw: str, is_html: bool) -> tuple[str, str]:
    """(첫 화면, 요약) — 태그를 걷어낸 글자."""
    cut_detail = re.split(r"<details", raw, maxsplit=1)[0] if is_html else re.split(r"^## 자세히", raw, maxsplit=1, flags=re.M)[0]
    cut_first = re.split(r"<h2", cut_detail, maxsplit=1)[0] if is_html else re.split(r"^## ", cut_detail, maxsplit=1, flags=re.M)[0]
    strip = (lambda t: htmllib.unescape(re.sub(r"<[^>]+>", "", t))) if is_html else (lambda t: t)
    return strip(cut_first), strip(cut_detail)


def c1(first: str, terms: dict) -> list[str]:
    bad = []
    if NUM.search(first):
        bad.append("첫 화면에 번호·sha·판정번호")
    hit = [t for t in terms if re.search(term_re(t), first)]
    if hit:
        bad.append("첫 화면에 전문어: " + " ".join(hit))
    groups: list[int] = []
    inside = False
    for ln in first.splitlines():
        inside = "⏳ 완성 전" in ln or (inside and not ln.startswith("⏳ 완성 후"))
        if inside and re.match(r"^  [^ ·].* · ", ln):
            groups.append(1)
        elif inside and groups and re.match(r"^    · ", ln):
            groups[-1] += 1
    if any(g > AREA_LINES for g in groups):
        bad.append(f"영역 블록 {max(groups)}줄 > {AREA_LINES}")
    return bad


def c2(summary: str, terms: dict) -> list[str]:
    bad, uses = [], 0
    for t in terms:
        found = list(re.finditer(term_re(t), summary))
        uses += len(found)
        if found and not summary[found[0].end():].startswith("("):
            bad.append(f"전문어 첫 등장에 풀이 없음: {t}")
    lines = [x for x in summary.splitlines() if x.strip()]
    if lines and uses > max(1, FREQ * len(lines)):
        bad.append(f"전문어 빈도 {uses} > 줄 수 {len(lines)} 의 5%")
    return bad


def c3(summary: str, raw: str, is_html: bool) -> list[str]:
    bad = []
    n = len([x for x in summary.splitlines() if x.strip()])
    if n > MAX_SUMMARY:
        bad.append(f"요약 {n}줄 > {MAX_SUMMARY}")
    if NUM.search(summary):
        bad.append(f"펼침 밖 번호·sha {len(NUM.findall(summary))}건")
    if is_html and len(raw.encode("utf-8")) > MAX_HTML_B:
        bad.append("HTML 200KB 초과")
    return bad


def c4(raw: str) -> list[str]:
    if "<svg" in raw:
        n = raw.count('<g class="node"') or raw.count("<rect")  # svg 상자 = node 그룹, 없으면 rect
        return [f"흐름 상자 {n} > {MAX_BOX}"] if n > MAX_BOX else []
    row = re.search(r'^\|\s*흐름\s*\|(.*)$', raw, re.M)
    cells = len(re.findall(r"<td>(?!→)", raw)) if 'class="flow"' in raw else len([c for c in (row[1].split("|") if row else []) if c.strip() and c.strip() != "→"])
    if not row and 'class="flow"' not in raw:
        return ["흐름 그림(svg·흐름 표) 없음"]
    return [f"흐름 상자 {cells} > {MAX_BOX}"] if cells > MAX_BOX else []


def main(argv: list[str]) -> int:
    if not argv or argv[0].startswith("-"):
        print(__doc__, file=sys.stderr)
        return 2
    path, terms_file = Path(argv[0]), HERE / "eli5_terms.json"
    if "--terms" in argv:
        terms_file = Path(argv[argv.index("--terms") + 1])
    raw, terms = path.read_text(encoding="utf-8"), json.loads(terms_file.read_text(encoding="utf-8"))
    is_html = path.suffix == ".html"
    first, summary = regions(raw, is_html)
    results = {1: c1(first, terms), 2: c2(summary, terms), 3: c3(summary, raw, is_html), 4: c4(raw)}
    for n, bad in results.items():
        print(f"FAIL 기준 {n}: " + " / ".join(bad) if bad else f"PASS 기준 {n}")
    return 1 if any(results.values()) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
