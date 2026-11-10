"""magazine_date_guard — 원장 본문의 상대 날짜 낱말(어제·오늘·내일…)을 찾아 틀린 날짜의 발행을 막는 가드 (R202).

원장은 쓴 날 기준의 «오늘»·«내일» 이 섞인 사람 문서라, 다음 날 아침 판에 그대로 실리면 날짜가 어긋난다(10-15 판 «오늘(10-13)»).
--publish 는 하나라도 있으면 발행하지 않고(rc≠0), --dry-run 은 같은 줄을 WARN 으로 보여 주고 계속한다. 치환은 하지 않는다(쓴 날을 도구가 모른다).
"""
import logging
import re

from magazine_doc_md import Doc

LOG = logging.getLogger("magazine_doc")
WORDS = ("그저께", "어제", "오늘", "내일", "모레", "그제")
# 낱말 바로 뒤에 한글이 붙어도 «조사»면 낱말로 센다(오늘은 · 내일의). 그 밖(오늘날 · 내일모레 · 어제오늘 · 그제서야)은 합성어로 보고 건너뛴다.
JOSA = ("은", "는", "이", "가", "을", "를", "에", "의", "도", "로", "만", "과", "와", "부터", "까지", "처럼", "보다")
_WORD = re.compile("|".join(WORDS))
_QUOTED = re.compile(r"`[^`]*`|「[^」]*」|«[^»]*»|“[^”]*”|\"[^\"]*\"")  # 인용·코드 — 오빠 원문 인용·규칙 문구
_HANGUL = re.compile(r"[가-힣]")


def _mask_quoted(line: str) -> str:
    return _QUOTED.sub(lambda m: " " * len(m.group(0)), line)


def _is_word(line: str, start: int, end: int) -> bool:
    if start > 0 and _HANGUL.match(line[start - 1]):
        return False
    rest = line[end:]
    return not _HANGUL.match(rest[:1]) or rest.startswith(JOSA)


def find_relative_dates(doc: Doc) -> list[tuple[str, str, int]]:
    """[(낱말, 절 제목, 절 본문 안 줄 번호(1부터))] — 칸·팀 본문 전부. 따옴표·코드 안은 제외."""
    hits: list[tuple[str, str, int]] = []
    for cell in [*doc.cells, *doc.teams]:
        for no, line in enumerate(cell.body.splitlines(), 1):
            masked = _mask_quoted(line)
            hits += [(m.group(0), cell.title, no) for m in _WORD.finditer(masked) if _is_word(masked, m.start(), m.end())]
    return hits


def check(doc: Doc, publish: bool) -> bool:
    """찾은 줄을 stdout 에 찍는다(--publish = REJECT · 아니면 WARN). 발행을 막아야 하면 True."""
    hits = find_relative_dates(doc)
    for word, section, line in hits:
        print(f"{'REJECT' if publish else 'WARN'} 상대 날짜 {word} {section} {line}")
    if hits and publish:
        LOG.error("상대 날짜 낱말 %d건 — 발행 거절(원장을 절대 날짜로 고친 뒤 다시)", len(hits))
    return bool(hits) and publish
