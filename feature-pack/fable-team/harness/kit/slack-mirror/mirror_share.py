"""mirror_share — 슬랙 = 읽기 전용 공유판 계약 (판정 497 · 설계 DESIGN-slack-readonly-share-20261008 §4-r2).

①답장 요구 문구를 «내보내기 직전» 결정적 정규식으로 막는다(share_guard — LLM 프롬프트만 믿지 않는다)
②모든 글의 첫 줄에 머리표 4종 중 하나(tag · strip_head · first_line_is)
③결정이 필요한 글에는 지금 살아 있는 planner 세션 이름을 싣는다(live_planner · decision_line).
확인 불가면 사유를 그대로 싣고 대체 이름은 없다(#0 RULE). 이 모듈은 mirror_lib 를 «호출 시점» 에만 import 한다(순환 방지).
"""
import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

HEADS = ("작업상황", "이슈보고", "변경내용", "상태")
PLANNER_ROLE = "@planner"  # inbound 원장에 이름 대신 저장하는 역할 표식 — 이름은 보낼 때마다 live_planner 로 정한다
CORRECTED = "(요약 문구 교정)"
OMITTED = "원문 요약 생략 — 아래 전문 참고"
HIL_FALLBACK = "정할 것: 전문 참고"
# `\bQ\d+\b` 는 쓰지 않는다 — 파이썬 유니코드에서 한글도 \w 라 `Q3에`·`질문Q3` 의 경계가 안 잡힌다(설계 A-r3).
REPLY_ASK = re.compile(
    r"답해\s*주|답장|회신해\s*주|답을\s*(?:주|달)|댓글|번호(?:나|로)?\s*답|이\s*스레드에\s*(?:답|한\s*줄)|reply|확인해\s*주"
    + r"|(?<![A-Za-z0-9])Q\d+(?!\d)", re.IGNORECASE)
_HEAD = re.compile(r"^\[(?:" + "|".join(HEADS) + r")\] ")


def share_guard(s: str | None) -> str | None:
    """답장을 요구하는 문구가 있으면 None, 아니면 s 그대로."""
    return None if s is None or REPLY_ASK.search(s) else s


def fix_line(s: str | None, fallback: str) -> tuple[str, bool]:
    """(보낼 문장, 교정했나) — 걸리면 fallback 으로 바꾸고 교정 사실을 호출자가 표시하게 한다."""
    ok = share_guard(s)
    return (ok, False) if ok is not None else (fallback, True)


def answer_hint(tok: str) -> str:
    """쪽지 끝 «이렇게 답하세요» 2줄 — 답은 오빠 글 ts 밑으로(r558), 승인·뉴스·알림 같은 방 글은 `post`(r561). 출처 토큰 줄은 그대로 둔다."""
    parts = tok.split(":")
    if len(parts) < 3 or parts[0] != "slack" or not parts[1]:
        return ""
    return "\n".join((
        f'답 = python3 ~/.hermes/scripts/byz_thread_post.py reply --to-slack {parts[1]} --text "…"',
        '방 글(승인·뉴스·알림) = python3 ~/.hermes/scripts/byz_thread_post.py post --to desk --text "…"',
    ))


def tag(kind: str, text: str) -> str:
    if kind not in HEADS:
        raise ValueError(f"머리표는 {HEADS} 중 하나: {kind}")
    return text if _HEAD.match(text) else f"[{kind}] {text}"


def strip_head(line: str) -> str:
    return _HEAD.sub("", line, count=1)


def first_line_is(text: object, want: str) -> bool:
    """글의 첫 줄이 want 와 같은가 — 양쪽 머리표를 떼고 비교한다(머리표 도입 전에 올라간 글도 같은 글로 찾는다)."""
    return strip_head(str(text).split("\n", 1)[0]) == strip_head(want)


def share_lines(what: str | None, todo: str | None, text: str, label: str) -> tuple[str, str | None, bool]:
    """요약 두 줄을 검사한다. what → 원문 첫 문장 → 생략 문구 · todo → HIL 이면 「정할 것: 전문 참고」 · 아니면 줄 생략. 반환 3째 = 교정 여부."""
    from mirror_lib import first_sentence
    w, fixed = fix_line(what, "")
    if fixed:
        w = share_guard(first_sentence(text)) or OMITTED
    t = share_guard(todo) if todo else None
    if todo and t is None:
        fixed = True
    if label == "HIL" and not t:
        t = HIL_FALLBACK
    return w, t, fixed


def live_planner(seats: str | Path | None = None, key: str = "_master") -> tuple[str | None, str]:
    """(현역 세션 이름 | None, 사유). 명부 `key`(기본 `_master` · desk 수신은 `_desk`)를 읽고 tmux 로 살아 있는지 확인한다 — `_hil_route` 는 읽지 않는다.
    사유 5종: 명부 없음 · JSON 오류(깊은 중첩·메모리 부족은 뒤에 예외 이름) · <key> 없음 · tmux 실행 실패 · 세션 없음. 명부 경로 = 인자 → env MIRROR_PLANNER_SEATS · tmux = env MIRROR_TMUX."""
    path = seats or os.environ.get("MIRROR_PLANNER_SEATS")
    if not path:
        return None, "명부 없음"
    try:
        raw = Path(path).read_text(encoding="utf-8")
    except OSError:
        return None, "명부 없음"
    try:
        data = json.loads(raw)
    except (ValueError, RecursionError, MemoryError) as e:  # r846 r5: 깊은 중첩·거대 명부도 «못 읽음» — 보이게(ERROR) 사유로 돌려준다
        print(f"ERROR: 명부 못 읽음 · {Path(path).name} · {type(e).__name__}", file=sys.stderr)
        return None, "JSON 오류" if isinstance(e, ValueError) else f"JSON 오류 {type(e).__name__}"
    name = data.get(key) if isinstance(data, dict) else None
    if not isinstance(name, str) or not name:
        return None, f"{key} 없음"
    try:
        r = subprocess.run([*shlex.split(os.environ.get("MIRROR_TMUX", "tmux")), "has-session", "-t", f"={name}"],
                           capture_output=True, timeout=10)
    except (OSError, subprocess.SubprocessError, ValueError):
        return None, "tmux 실행 실패"
    if r.returncode == 0:
        return name, "살아 있음"
    return None, "세션 없음" if r.returncode == 1 else "tmux 실행 실패"


def place_text(seats: str | Path | None = None) -> str:
    name, why = live_planner(seats)
    return name or f"확인 불가({why})"


def decision_line(frm: str = "", seats: str | Path | None = None) -> str:
    from mirror_lib import esc
    name, why = live_planner(seats)
    asker = f" · 질문 올린 좌석: {esc(frm)}" if frm else ""
    if name:
        return f"결정 자리: {esc(name)} (그 세션이 인터뷰를 띄웁니다){asker}"
    return f"결정 자리: 확인 불가(planner 현역 세션: {why}) — 하네스 master 에 알림{asker}"
