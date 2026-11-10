"""시트 입력 ① 카드 — 정해진 줄만 읽는다 (PLAN §2-1): `- say:` · `## 상태` 절 마지막 사건 · `- 선행:` · `- 시기:` · 최우선 표식. 다른 줄은 읽는 코드가 없다.

글자는 전부 «치환»으로만 만든다: 단계 문구 = sheet_stages.json · 쉬운 말 = sheet_words.json + eli5_terms.json · 번호·sha 는 줄에서 지운다(펼침 안에만 남는다).
"""
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
TITLE_SCAN_LINES = 5
NUMS = re.compile(r"#\d+|판정\s*\d+|\b[0-9a-f]{7,}\b")


def table(name: str):
    return json.loads((HERE / name).read_text(encoding="utf-8"))


def term_re(term: str) -> str:
    """전문어 경계 — 영문은 단어 경계 · 한글은 앞 글자가 한글이 아닐 때만(「패턴」 속 「턴」 오탐 방지)."""
    return rf"(?<![A-Za-z0-9]){re.escape(term)}(?![A-Za-z0-9])" if term.isascii() else rf"(?<![가-힣A-Za-z0-9]){re.escape(term)}"


def plain(text: str) -> str:
    """오빠 화면용 한 줄 — 전문어는 대체어로 · 번호·sha 는 지운다."""
    for term, alt in table("eli5_terms.json").items():
        text = re.sub(term_re(term), alt, text)
    return re.sub(r"\s{2,}", " ", NUMS.sub("", text)).strip(" -·")


def short_title(title: str) -> str:
    return plain(re.split(r" — | · |\(|:", title, maxsplit=1)[0])[:40]


def section_last(text: str, head: str) -> str:
    m = re.search(rf"^## {head}\s*\n(.*?)(?=^## |\Z)", text, re.M | re.S)
    bullets = [x for x in (m[1].splitlines() if m else []) if x.startswith("- ")]
    return bullets[-1] if bullets else ""


def stage(last_event: str) -> str:
    for rule in table("sheet_stages.json"):
        m = re.search(rule["re"], last_event)
        if m:
            return m.expand(rule["text"])
    return "진행 중"


def facts(path: Path) -> dict:
    text = path.read_text(encoding="utf-8")
    h1 = next((ln for ln in text.splitlines()[:TITLE_SCAN_LINES] if re.match(r"#\s", ln)), "")  # ft_board_collect._title 과 같은 규칙 — 앞 주석 줄은 건너뛴다
    title = re.sub(r"^#\s+(?:인덱스:\s*)?", "", h1) or path.stem
    say = re.search(r"^- say:\s*(.+)$", text, re.M)
    prereq = re.search(r"^- 선행:\s*(.+)$", text, re.M)
    when = re.search(r"^- 시기:\s*(.+)$", text, re.M)
    return {"say": say[1].strip() if say else short_title(title), "title": title,
            "where": stage(section_last(text, "상태")), "prereq": prereq[1].strip() if prereq else "",
            "after": bool(when and "완성 후" in when[1]), "star": "사용자 최우선" in text or bool(re.search(r"\bK4\b", text))}


def team_cards(root: Path, seats_file: Path) -> list[dict]:
    """한 팀의 대기·진행 카드 — [{team, slug, folder, path(리포 상대), …facts}]"""
    seats = json.loads(seats_file.read_text(encoding="utf-8"))
    if not seats.get("_cards"):
        return []
    key = "v65" if seats_file.stem == "seats" else seats_file.stem.removeprefix("seats-")
    base = root / ".worktrees" / seats["_cards_wt"] if seats.get("_cards_wt") else root
    out = []
    for folder in ("진행", "대기"):
        for p in sorted((base / seats["_cards"] / folder).glob("*.md")):
            out.append({"team": key, "label": seats.get("_label") or key, "slug": p.stem, "folder": folder,
                        "path": str(p.relative_to(base)), **facts(p)})
    return out


def area_of(team: str) -> str | None:
    return table("sheet_areas.json")["teams"].get(team)
