"""ft_board_root — 슬랙 보드 «뿌리 글» 본문 만들기 + UTF-8 바이트 상한 (v423a · arch#18 반송 r1).

슬랙 chat.update 는 약 3.9KB 에서 msg_too_long 으로 거부한다(R49) — render --slack 전체(수십 KB)를 그대로 못 보낸다.
  root < render --slack 출력   → 머리 + ⓪ 팀 요약 + ④ 오늘 판정표 + 고정 끝줄 (①②③ 은 터미널 보드 · 변화는 스레드 답글)
  cap [--tail T] < 본문        → 본문 + T 가 상한 안이 되게 «본문»을 UTF-8 안전하게 자른다(T 는 항상 남는다 · 동결 본문용)
⓪·④ 안의 표 줄은 «• » 목록 줄로 바꾼다(r1022 · 슬랙은 표를 못 그리고 되읽기 가드 r1004 가 표 줄을 지운다) — 칸 사이 « · » · 구분 줄 제거 · 표 아닌 줄은 그대로.
상한 = CAP(3500) 바이트. 절 머리(`*⓪ `~`*④ `)를 못 찾으면 raise(조용한 대체 0 · rc 1). ft_board_render.py 는 건드리지 않는다.
"""
import re
import sys

CAP = 3500
HEADS = ("*⓪ ", "*① ", "*② ", "*③ ", "*④ ")
FOOT = "… ①완성 트리·②세션 트리·③큐 = 터미널 보드(`ft-board.py render --term`) · 변화는 이 스레드 답글"
OMIT_TAIL = "문구 생략 "


def _b(s: str) -> int:
    return len(s.encode("utf-8"))


def _cut(s: str, limit: int) -> str:
    """UTF-8 경계에서 자른다(바이트 limit 이하) — 잘렸으면 끝에 `…`."""
    if _b(s) <= limit:
        return s
    return s.encode("utf-8")[: limit - _b("…")].decode("utf-8", errors="ignore") + "…"


LINK = re.compile(r"<[^<>|]*\|[^<>]*>")  # 슬랙 링크 `<주소|글자>` — 안쪽 파이프는 칸 경계가 아니다(r1022)
SEPARATOR = re.compile(r"^\s*\|?\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)+\|?\s*$")  # 표 구분 줄 `|---|:--:|`
MARK_PLACE = re.compile("\x00(\\d+)\x00")


def _table_row(line: str) -> bool:
    """되읽기 가드가 «표 줄» 로 세는 줄 — 파이프 2개 이상(링크 안 파이프 제외) 또는 구분 줄."""
    return LINK.sub("", line).count("|") >= 2 or bool(SEPARATOR.match(line))


def _cells(line: str) -> list[str]:
    """표 줄 → 칸 글자 목록(앞 목록 표지·앞뒤 파이프·빈 칸 제거 · 링크 안 파이프는 글자 그대로)."""
    body = line.strip()
    for mark in ("- ", "* ", "+ ", "• "):
        if body.startswith(mark):
            body = body[len(mark):]
            break
    links: list[str] = []

    def _hold(m: re.Match[str]) -> str:
        links.append(m.group(0))
        return f"\x00{len(links) - 1}\x00"

    body = LINK.sub(_hold, body)
    out = []
    for cell in body.split("|"):
        cell = MARK_PLACE.sub(lambda m: links[int(m.group(1))], cell).strip()
        if cell:
            out.append(cell)
    return out


def _list_lines(lines: list[str]) -> list[str]:
    """⓪·④ 안의 표 줄 = `• ` 목록 줄 · 구분 줄은 뺀다 · 표 아닌 줄은 그대로(r1022)."""
    out: list[str] = []
    for line in lines:
        if SEPARATOR.match(line):
            continue
        if not _table_row(line):
            out.append(line)
        elif cells := _cells(line):
            out.append("• " + " · ".join(cells))
    return out


def _sections(body: str) -> tuple[list[str], list[str], list[str]]:
    lines = body.split("\n")
    at = [next((i for i, x in enumerate(lines) if x.startswith(h)), -1) for h in HEADS]
    if -1 in at or at != sorted(at):
        raise ValueError(f"보드 본문에서 절 머리 {HEADS} 를 순서대로 못 찾음 — 발행 0")

    def between(a: int, b: int) -> list[str]:
        return [x for x in lines[a + 1:b] if x.strip()]
    return [x for x in lines[:at[0]] if x.strip()], between(at[0], at[1]), between(at[4], len(lines))


def root_text(body: str) -> str:
    head, teams, verdicts = _sections(body)
    verdicts = [x for x in verdicts if not x.startswith(OMIT_TAIL)]  # 잘려 나간 절의 치환 계수 — 뿌리에 무의미
    teams, verdicts = _list_lines(teams), _list_lines(verdicts)  # 슬랙은 표를 못 그린다 — 표 줄 0(되읽기 가드 r1004)

    def build(ts: list[str]) -> str:
        return "\n".join([*head, "", HEADS[0] + "팀 요약*", *ts, "", HEADS[4] + "오늘 판정표*", *verdicts, "", FOOT])
    for k in range(len(teams), -1, -1):
        text = build(teams[:k] + ([f"… 외 {len(teams) - k}팀"] if k < len(teams) else []))
        if _b(text) <= CAP:
            return text
    text = _cut(build([]), CAP)
    if _b(text) > CAP:
        raise ValueError("상한 단언 실패(코드 결함)")
    return text


def cap_text(text: str, tail: str = "") -> str:
    out = _cut(text.rstrip("\n"), CAP - _b(tail) - 1) + tail if _b(text) + _b(tail) > CAP else text.rstrip("\n") + tail
    if _b(out) > CAP:
        raise ValueError("상한 단언 실패(코드 결함)")
    return out


def main(argv: list[str]) -> int:
    data = sys.stdin.buffer.read().decode("utf-8")
    if argv == ["root"]:
        out = root_text(data)
    elif argv[:1] == ["cap"] and (len(argv) == 1 or (len(argv) == 3 and argv[1] == "--tail")):
        out = cap_text(data, argv[2] if len(argv) == 3 else "")
    else:
        print(__doc__, file=sys.stderr)
        return 2
    _ = sys.stdout.buffer.write(out.encode("utf-8"))  # 끝 개행 0 — 바이트 단언이 보내는 문자열과 같다
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as e:  # noqa: BLE001 — 실패는 숨기지 않고 rc≠0 (#0 RULE)
        print(f"ft_board_root: {type(e).__name__}: {e}", file=sys.stderr)
        sys.exit(1)
