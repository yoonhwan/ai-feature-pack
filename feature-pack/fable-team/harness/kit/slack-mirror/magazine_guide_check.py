"""magazine_guide_check — 발행 직전 «매거진 지침 검사» (R259 · 판정 1988 · design/harness/GUIDE-magazine-20261016.md §3·§4-1·§5).

위반이 1건이라도 있으면 --publish 는 발행 0(호출한 쪽이 rc≠0) · --dry-run 은 같은 줄을 WARN 으로 찍고 HTML 은 만든다. 자동 삭제·치환 0 — 고치는 곳은 원장이다.
줄 꼴: `REJECT|WARN 지침 <항목> <칸> <원문 조각 40자>` · 결론 줄이 없으면 `… 지침 결론 줄 없음`.
"""
import logging
import re

from magazine_brief import Brief

LOG = logging.getLogger("magazine_doc")
_CMD = re.compile(r"! bash /tmp/h\d+")  # 오빠 실행 한 줄 — 약어 좌표 검사 밖
CRUFT = ("이 표는", "보여줘요", "정리하면", "요약하면", "전반적으로", "다양한", "살펴보면")
RULES: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("판정번호", re.compile(r"판정 ?\d+")),
    ("이슈번호", re.compile(r"#\d+")),
    ("커밋번호", re.compile(r"(?<![0-9A-Za-z])(?=[0-9a-f]*\d)(?=[0-9a-f]*[a-f])[0-9a-f]{7,40}(?![0-9A-Za-z])")),
    ("쪽지번호", re.compile(r"\b\d{5}\b")),
    ("약어좌표", re.compile(r"\b[A-Z]{1,3}\d+[a-z]?\b")),
    ("파일경로", re.compile(r"[\w.-]+/[\w./-]+\.(?:md|py|sh|json|html)")),
    ("칸규칙", re.compile(r"^\s*(?:칸\(|규칙:|>\s)")),
    ("군말", re.compile("|".join(CRUFT) + r"|라고 할 수 있")),
)


def violations(raw: str) -> list[tuple[str, str]]:
    """한 줄의 §3 금지 꼴 [(항목, 원문 조각 40자)] — 축하 칸(r867)이 판에 싣기 전에 같은 규칙으로 거른다."""
    text = _CMD.sub("", raw)
    return [(name, text[m.start():m.start() + 40]) for name, rx in RULES for m in rx.finditer(text)]


def check(brief: Brief, publish: bool) -> int:
    """위반 줄을 stdout 에 찍고 건수를 돌려준다. 칸 1(결론)도 같은 금지 꼴을 본다(헤드라인에 번호가 새면 가장 눈에 띈다)."""
    tag = "REJECT" if publish else "WARN"
    lines: list[str] = [] if brief.conclusion else [f"{tag} 지침 결론 줄 없음"]
    lines += [f"{tag} 지침 {item} {cell} {frag[:40]}" for item, cell, frag in brief.issues]
    for cell in brief.cells():
        for raw in cell.body.splitlines():
            lines += [f"{tag} 지침 {name} {cell.title} {frag}" for name, frag in violations(raw)]
    if lines:
        print("\n".join(lines))
    if lines and publish:
        LOG.error("지침 위반 %d건 — 발행 거절(원장을 지침 §4 대로 고친 뒤 다시)", len(lines))
    return len(lines)
