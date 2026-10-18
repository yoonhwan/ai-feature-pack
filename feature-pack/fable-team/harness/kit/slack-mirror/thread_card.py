"""thread_card — 카드(인덱스 파일)의 `- 슬랙:` 줄과 단위 ID·판정문 제목 처리 (byz_thread_post 에서 분리 · 200줄 한도).

카드의 `- 슬랙:` 줄이 «게시 대상» 표식이자 장부 백업이다(설계 §3):
  `- 슬랙: <channel> · 시도 <ISO>`  = 게시 «전» 의도 기록   ·   `- 슬랙: <channel> <root_ts>` = 게시 성공.
"""
import re
from pathlib import Path

from mirror_lib import MirrorError

LINE = re.compile(r"^- 슬랙:\s*(?P<ch>\S+)(?:\s+·\s+시도\s+\S+|\s+(?P<ts>\d+\.\d+))\s*$", re.MULTILINE)
PREFIX = "- 슬랙:"


class CardError(MirrorError):
    pass


def unit_id(card: str | Path, team: str | None = None) -> str:
    """`<팀>/<카드 파일 이름(.md 뺀 것)>` — 팀은 --team 또는 경로의 `design/<팀>/` 에서. 둘 다 없으면 raise."""
    p = Path(card)
    if p.suffix != ".md":
        raise CardError(f"카드는 .md 파일이어야 한다: {card}")
    if not team:
        parts = p.resolve().parts
        team = parts[parts.index("design") + 1] if "design" in parts[:-1] else None
    if not team:
        raise CardError(f"팀을 알 수 없다 — 경로에 design/<팀>/ 이 없으면 --team 을 준다: {card}")
    return f"{team}/{p.stem}"


def read_line(card: Path) -> tuple[str, str | None] | None:
    """(channel, root_ts|None) — `- 슬랙:` 줄이 없으면 None(슬랙에 안 올라간 단위). 모양이 깨진 줄은 raise."""
    try:
        text = card.read_text(encoding="utf-8")
    except OSError as e:
        raise CardError(f"카드 읽기 실패: {card} ({type(e).__name__})") from e
    lines = [ln for ln in text.splitlines() if ln.startswith(PREFIX)]
    if not lines:
        return None
    if len(lines) > 1:
        raise CardError(f"카드에 「- 슬랙:」 줄이 {len(lines)}개 — 1개여야 한다: {card}")
    m = LINE.match(lines[0])
    if not m:
        raise CardError(f"카드 「- 슬랙:」 줄 모양 오류: {lines[0]}")
    return m.group("ch"), m.group("ts")


def write_line(card: Path, line: str) -> None:
    """`- 슬랙:` 줄을 바꾸거나, 없으면 `## 상태` 절 끝에 넣는다. 상태 절이 없으면 raise."""
    read_line(card)  # 모양 검증
    rows = card.read_text(encoding="utf-8").split("\n")
    for i, ln in enumerate(rows):
        if ln.startswith(PREFIX):
            rows[i] = line
            break
    else:
        try:
            head = next(i for i, ln in enumerate(rows) if ln.strip() == "## 상태")
        except StopIteration:
            raise CardError(f"카드에 「## 상태」 절이 없다: {card}") from None
        end = next((i for i in range(head + 1, len(rows)) if rows[i].startswith("## ")), len(rows))
        while end > head + 1 and not rows[end - 1].strip():
            end -= 1
        rows.insert(end, line)
    try:
        card.write_text("\n".join(rows), encoding="utf-8")
    except OSError as e:
        raise CardError(f"카드 쓰기 실패: {card} ({type(e).__name__})") from e


def verdict_title(spec: str) -> str:
    """`판정문경로#§N` → 그 파일에서 §N 을 가진 제목 줄(# 뗀 것) — 결과 1줄은 이 줄 그대로. 못 찾으면 raise."""
    path, sep, sec = spec.rpartition("#")
    if not sep or not path or not re.fullmatch(r"§\d+(?:-\w+)?", sec):
        raise CardError(f"--verdict 는 <판정문 경로>#§N 모양이어야 한다: {spec}")
    try:
        text = Path(path).read_text(encoding="utf-8")
    except OSError as e:
        raise CardError(f"판정문 읽기 실패: {path} ({type(e).__name__})") from e
    pat = re.compile(rf"^#{{1,6}}\s+(.*{re.escape(sec)}(?![\w-]).*)$", re.MULTILINE)
    hits = pat.findall(text)
    if len(hits) != 1:
        raise CardError(f"판정문에서 「{sec}」 제목 줄이 {len(hits)}건 — 정확히 1건이어야 한다: {path}")
    return hits[0].strip()
