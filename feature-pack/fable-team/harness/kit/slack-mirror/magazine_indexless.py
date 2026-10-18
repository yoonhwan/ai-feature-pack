"""본문 인덱스 0 (판정 609 설계 r2-3) — 판정·PR·좌석 번호 같은 «인덱스 표기»를 본문에서 걷어 번호 각주로 옮긴다.

토큰 목록 밖은 손대지 않는다(CO2·B12·UTF8 보존). 걷어 낸 것은 호출 쪽이 만든 각주 한 줄에 «원문 그대로» 남는다.
번호가 허용되는 곳은 각주 문자열(`Foot.html`)뿐이고, 본문 문자열은 `check_body` 가 검사한다.
"""
import re
from collections.abc import Iterable
from html import escape

from magazine_eli5_batches import Eli5Error

_HEX = r"(?<!\w)(?=[0-9a-f]*\d)(?=[0-9a-f]*[a-f])[0-9a-f]{7,40}(?!\w)"  # 숫자·글자 둘 다 든 16진 덩어리만(sha)
TOKENS = re.compile("|".join((
    r"\(#\d+\)", r"판정\s*\d+", r"§\d+", r"byz-[\w-]+#\d+", r"(?<![\w-])R\d{1,3}(?![\w.])", r"(?<![\w&])#\d+",
    r"(?<![\w.])\d+번(?!째)", r"(?<![\w-])(?:M[0-7]|K[1-5])(?![\w-])", _HEX,
)))
_SEP = " \t·:,;-—–|/"


def find_tokens(text: object) -> list[str]:
    return [m.group(0) for m in TOKENS.finditer(str(text))]


def strip_tokens(text: object) -> tuple[str, list[str]]:
    """(토큰을 걷어 낸 글, 걷어 낸 토큰들 — 나온 순서). 걷어 낸 자리가 이웃과 붙어 새 토큰이 되면(`판정 (#1) 4`) 안 남을 때까지 되풀이한다."""
    clean, found = str(text), []
    for _ in range(10):
        found += find_tokens(clean)
        step = re.sub(r"\(\s*\)|\[\s*\]", "", TOKENS.sub(" ", clean))
        step = " ".join(step.split())
        if step == clean:
            break
        clean = step
    return clean.strip(_SEP), found


class Foot:
    """번호 각주 — 본문 줄이 `[n]` 으로 가리키는 «번호가 허용되는 영역»."""

    def __init__(self) -> None:
        self.rows: list[tuple[str, str]] = []

    def add(self, kind: str, text: str) -> int:
        self.rows.append((kind, text))
        return len(self.rows)

    def html(self) -> str:
        if not self.rows:
            return "<p>없어요</p>"
        body = "".join(f"<tr><td>[{n}]</td><td>{escape(k)}</td><td>{escape(t)}</td></tr>" for n, (k, t) in enumerate(self.rows, 1))
        return "<table><thead><tr><th>번호</th><th>종류</th><th>원문</th></tr></thead><tbody>" + body + "</tbody></table>"


def check_body(texts: Iterable[str]) -> None:
    for text in texts:
        found = find_tokens(text)
        if found:
            raise Eli5Error(f"본문 인덱스 검사 실패: {' · '.join(found)} (줄: {text[:40]})")
