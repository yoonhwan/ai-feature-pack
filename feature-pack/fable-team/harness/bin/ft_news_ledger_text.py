"""ft_news_ledger_text — 원장 차이를 뉴스 글로 그리고 Slack 한도(3500B)에 맞춰 칸 경계로 n/N 판으로 나눈다 (R125 교정 r2 · 하드 룰 12: 기준량 넘으면 쪼갠다).

판형(판정 1438 참고 판): 지금 → 바뀐 것(차이 줄만) → 오빠 할 일(`## 2.` 전체) → 팀 작업(`## 3.` 전 팀 1팀 1줄 · 쉬는 팀 포함).
나누기: 칸 통째로 들어가면 통째로, 한 판보다 큰 칸만 줄 단위로 이어 쓴다(이어진 판에 칸 제목 반복). 한 줄이 혼자 한도를 넘으면 raise(자르기 0).
"""
from datetime import datetime

MAX_BYTES = 3500  # ft_news_publish.MAX_BYTES 와 같은 값(시험이 대조) — Slack 글 길이 한도는 «바이트»
Lines = dict[tuple[str, str, str], tuple[str, ...]]
Block = tuple[str, list[str]]


def _head(now: datetime, n: int | str, total: int | str, rel: str) -> str:
    stamp = f"{now:%m-%d %H:%M}" + (f" ({n}/{total})" if total != 1 else "")
    return f"*뉴스 {stamp}* — 기준: 오빠 원장({rel}) · 지난 발행 뒤 바뀐 것만"


def build_blocks(new: Lines, diff: list[tuple[str, str]]) -> list[Block]:
    teams = [f"• {k[2]} — {' → '.join(v)}" if v else f"• {k[2]}" for k, v in new.items() if k[0] == "3" and v]
    todo = [f"• {k[2]}" for k in new if k[0] == "2"]
    blocks = [("*지금*", [" · ".join(new.get(("now", "", "지금 전체 상태"), ()))]), ("*바뀐 것*", [f"• [{kind}] {text}" for kind, text in diff]),
              ("*오빠 할 일*", todo), ("*팀 작업* — 쉬는 팀도 전부, 어디까지 하고 멈췄는지", teams)]
    return [(t, ls) for t, ls in blocks if ls]


def _text(head: str, part: list[Block]) -> str:
    return "\n\n".join([head, *(f"{t}\n" + "\n".join(ls) for t, ls in part)]) + "\n"


def _size(now: datetime, rel: str, part: list[Block]) -> int:
    return len(_text(_head(now, 99, 99, rel), part).encode("utf-8"))  # 머리의 (n/N) 자리는 가장 넓게 잡는다


def _put_line(now: datetime, rel: str, parts: list[list[Block]], title: str, line: str) -> None:
    part = parts[-1]
    grown = [*part[:-1], (title, [*part[-1][1], line])] if part and part[-1][0] == title else [*part, (title, [line])]
    if _size(now, rel, grown) <= MAX_BYTES:
        parts[-1] = grown
        return
    alone = [(title, [line])]
    if _size(now, rel, alone) > MAX_BYTES:
        raise ValueError(f"뉴스 한 줄이 혼자 {MAX_BYTES}B 를 넘는다(자르지 않고 발행 0): {line[:40]}…")
    parts.append(alone)


def render_parts(now: datetime, new: Lines, diff: list[tuple[str, str]], rel: str) -> list[str]:
    parts: list[list[Block]] = [[]]
    for block in build_blocks(new, diff):
        if _size(now, rel, [*parts[-1], block]) <= MAX_BYTES:
            parts[-1].append(block)
        elif parts[-1] and _size(now, rel, [block]) <= MAX_BYTES:
            parts.append([block])
        else:
            for line in block[1]:
                _put_line(now, rel, parts, block[0], line)
    return [_text(_head(now, i, len(parts), rel), p) for i, p in enumerate(parts, 1)]
