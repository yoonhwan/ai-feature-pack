"""ft_decision_kind.py — ft-decision-count 의 쪽지 분류 1곳 (R337 · 판정 1804 첫 줄 N 의 분모).

결정 인터뷰·팀 대기 = 보고 의무 급(MUST_REPORT) 미닫힘 중 본문 첫 줄 «머리»(앞 대괄호 묶음)에 질문 표식이 있는 것만.
  질문표식 = [결정]·[HIL]·[인터뷰 요청](«·» 변형 포함) 또는 [긴급] + 첫 줄의 «?»·«예/아니오»·«①…②» 선택지
  통보 = 통보 머리([완료]·[완료·휴식…]·[정지 레디]·[수령]·[회신…]·[보고]) — 물음표가 있어도 0 · 표식 없는 쪽지도 통보
  묵음 = 24시간 넘은 질문 — 첫 줄 N 에서 빼고 «묵은 M건» 칸으로(숨기지 않는다)
  본문 없음 = 본문 파일이 사라진 행(r738) — 셈을 멈추지 않고 «본문 없음» 으로 세고 stderr 경고 1줄 · 그 밖의 읽기 실패는 그대로 ReadError
닫힘 = obligation_closed(줄, answered_seqs(planner)) — 정본 술어 1곳.
"""
import re
import sys
from datetime import datetime

from ft_decision_alarm import ReadError
from ft_inbox_core import MUST_REPORT, obligation_closed

STALE_MIN = 24 * 60
HEAD = re.compile(r"(?:\s*\[[^\]]*\])+")
NOTICE = re.compile(r"\[(?:완료|정지 레디|수령|회신|보고)[^\]]*\]")
ASK = re.compile(r"\[(?:결정|HIL|인터뷰 요청)(?:·[^\]]*)?\]")  # [결정 대기 경보] 같은 이름 겹침은 질문 아님
CHOICE = re.compile(r"[?？]|예\s*/\s*아니오|①.*②")
BODY_MISSING = "본문 없음"
ORDER = {"질문표식": 0, BODY_MISSING: 1, "묵음": 2, "통보": 3}


def head_line(path):
    """본문 첫 줄 — 앞의 «[from->to]» 꼬리표는 뗀다. 파일이 없으면 None(r738) · 그 밖의 못 읽음은 ReadError(분류를 지어내지 않는다)."""
    try:
        with open(path, encoding="utf-8") as f:
            first = f.readline().strip()
    except FileNotFoundError:
        return None
    except OSError as e:
        raise ReadError(f"쪽지 본문 못 읽음: {path or '(body_path 빈 값)'} {type(e).__name__}")
    return re.sub(r"^\[[^\]]*->[^\]]*\]\s*", "", first)


def kind(first, mins):
    m = HEAD.match(first)
    head = m.group() if m else ""
    if NOTICE.search(head) or not (ASK.search(head) or ("[긴급" in head and CHOICE.search(first))):
        return "통보"
    return "묵음" if mins >= STALE_MIN else "질문표식"


def minutes(ts, now):
    t = datetime.fromisoformat(ts)
    return int((now - (t.astimezone().replace(tzinfo=None) if t.tzinfo else t)).total_seconds() // 60)


def open_rows(rows, answered, now):
    """보고 의무 급 미닫힘 → [(줄, 이유 낱말, 경과 분)]."""
    out = []
    for x in rows:
        if x["cls"] in MUST_REPORT and not obligation_closed(x, answered):
            mins = minutes(x["ts"], now)
            first = head_line(x["body_path"])
            if first is None:  # r738: 본문 파일이 없어도 셈은 계속한다 — 조용한 0 이 아니도록 seq·경로를 남긴다
                print(f"WARN ft-decision-count: 쪽지 본문 없음 #{x['seq']} {x['body_path'] or '(body_path 빈 값)'}", file=sys.stderr)
            out.append((x, BODY_MISSING if first is None else kind(first, mins), mins))
    return out
