"""ft_decision_kind.py — ft-decision-count 의 쪽지 분류 1곳 (R337 · 판정 1804 첫 줄 N 의 분모).

결정 인터뷰·팀 대기 = 보고 의무 급(MUST_REPORT) 미닫힘 중 본문 첫 줄 «머리»(앞 대괄호 묶음)에 질문 표식이 있는 것만.
  질문표식 = [결정]·[HIL]·[인터뷰 요청](«·» 변형 포함) 또는 [긴급] + 첫 줄의 «?»·«예/아니오»·«①…②» 선택지
  통보 = 통보 머리([완료]·[완료·휴식…]·[정지 레디]·[수령]·[회신…]·[보고]) — 물음표가 있어도 0 · 표식 없는 쪽지도 통보
       · 첫 줄 끝 «(원래 [정리])»(mbox_guard r1098 승격분 · r1148) — 머리가 [HIL] 이어도 통보
  묵음 = 24시간 넘은 질문 — 첫 줄 N 에서 빼고 «묵은 M건» 칸으로(숨기지 않는다)
  본문 없음 = 본문 파일이 사라진 행(r738) — 셈을 멈추지 않고 «본문 없음» 으로 세고 stderr 경고 1줄 · 그 밖의 읽기 실패는 그대로 ReadError
닫힘 = obligation_closed(줄, answered_seqs(planner)) — 정본 술어 1곳.
"""
import os
import re
import sys
from datetime import datetime

from ft_decision_alarm import ReadError
from ft_inbox_core import INBOX, MUST_REPORT, obligation_closed

STALE_MIN = 24 * 60
HEAD = re.compile(r"(?:\s*\[[^\]]*\])+")
NOTICE = re.compile(r"\[(?:완료|정지 레디|수령|회신|보고)[^\]]*\]")
ASK = re.compile(r"\[(?:결정|HIL|인터뷰 요청)(?:·[^\]]*)?\]")  # [결정 대기 경보] 같은 이름 겹침은 질문 아님
CHOICE = re.compile(r"[?？]|예\s*/\s*아니오|①.*②")
PROMOTED = re.compile(r"\(원래 \[정리\]\)\s*$")  # r1148: mbox_guard 승격(r1098)이 첫 줄 끝에 붙인 표식 — 머리는 [HIL] 이어도 원래 [정리](통보)
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
    if NOTICE.search(head) or PROMOTED.search(first) or not (ASK.search(head) or ("[긴급" in head and CHOICE.search(first))):
        return "통보"
    return "묵음" if mins >= STALE_MIN else "질문표식"


def minutes(ts, now):
    t = datetime.fromisoformat(ts)
    return int((now - (t.astimezone().replace(tzinfo=None) if t.tzinfo else t)).total_seconds() // 60)


def heads_path():
    return os.environ.get("FT_DECISION_HEADS") or f"{os.path.dirname(INBOX)}/ft-decision-heads.tsv"


def heads_load(path):
    """머리 캐시(seq<TAB>첫 줄) → {seq: 첫 줄}. 깨진 줄(탭·숫자 seq 없음 · 깨진 글자)만 무시 · 파일 없음 = 빈 캐시 · 못 읽음 = WARN 1줄 + 빈 캐시(느려질 뿐 값은 같다)."""
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            lines = f.read().split("\n")
    except FileNotFoundError:
        return {}
    except OSError as e:
        print(f"WARN ft-decision-count: 머리 캐시 못 읽음 {path} {type(e).__name__}", file=sys.stderr)
        return {}
    out = {}
    for ln in lines:
        seq, tab, first = ln.partition("\t")
        if tab and seq.isascii() and seq.isdigit() and "�" not in first:
            out[seq] = first
    return out


def heads_append(path, fresh):
    """새로 연 본문의 첫 줄을 캐시에 이어 쓴다. 마지막 줄이 개행 없이 끊겼으면 줄바꿈부터 · 실패 = WARN 1줄(집계는 그대로)."""
    if not fresh:
        return
    try:
        with open(path, "a+", encoding="utf-8") as f:
            f.seek(0, 2)
            lead = ""
            if f.tell():
                f.seek(f.tell() - 1)
                lead = "" if f.read(1) == "\n" else "\n"
            f.write(lead + "".join(f"{s}\t{' '.join(first.split(chr(9)))}\n" for s, first in fresh))
    except OSError as e:
        print(f"WARN ft-decision-count: 머리 캐시 못 씀 {path} {type(e).__name__}", file=sys.stderr)


def open_rows(rows, answered, now):
    """보고 의무 급 미닫힘 → [(줄, 이유 낱말, 경과 분)]. 본문 첫 줄은 머리 캐시에서 읽고 캐시에 없는 본문만 연다(r1236)."""
    out, cache, fresh = [], heads_load(heads_path()), []
    for x in rows:
        if x["cls"] in MUST_REPORT and not obligation_closed(x, answered):
            mins = minutes(x["ts"], now)
            first = cache.get(str(x["seq"]))
            if first is None:
                first = head_line(x["body_path"])
                if first is not None:  # 본문 없음은 캐시에 넣지 않는다(다음에 생길 수 있음)
                    fresh.append((x["seq"], first))
            out.append((x, BODY_MISSING if first is None else kind(first, mins), mins))
    heads_append(heads_path(), fresh)
    miss = sorted((x for x, k, _ in out if k == BODY_MISSING), key=lambda x: x["seq"])
    if miss:  # r738: 본문 파일이 없어도 셈은 계속한다 — 조용한 0 이 아니도록 건수·seq 범위·첫 경로를 남긴다(r1135: 건마다 1줄 → 1줄로 묶음)
        print(f"WARN ft-decision-count: 쪽지 본문 없음 {len(miss)}건(첫 #{miss[0]['seq']} · 끝 #{miss[-1]['seq']}) {miss[0]['body_path'] or '(body_path 빈 값)'}", file=sys.stderr)
    return out
