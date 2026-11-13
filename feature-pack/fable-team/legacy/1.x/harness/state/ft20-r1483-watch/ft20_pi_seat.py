"""r1621 — ft20 300초 점검의 Pi 갈래 판독기. check.py 가 engine 'pi' 일 때만 부른다.
Pi 결속 = 회차마다 ft_seat_pi.locate(seat) · 상자 = 마지막 두 «전부 ─» 줄 사이 ·
상자가 화면보다 길면(alt screen · history 0) 바닥 경계선 위 글 꼬리 · 바쁨 = «⠋ Working» 줄."""
import json
import re
from datetime import datetime

DIVIDER = re.compile(r'^─+$')
MARK = re.compile(r'^─+ .+ ─+$')  # 내용 있는 ─ 줄 = 바쁨 표식·접힘 표식
OVERFLOW = re.compile(r'^─+ ↑ \d+ more ─+$')  # r1836 B2: 넘친 상자 위 경계선
STATUS = re.compile(r'^↑\d+\s+↓')  # r1836 B1: Pi 마지막 상태 줄
BROKEN = re.compile(r'─{8,}$')  # r1836 B1 ⓒ: ─ 8개 이상으로 끝나는 줄

def _pi():  # helper 경로는 check.py 가 sys.path 에 넣는다 → 지연 import
    return __import__('ft_seat_pi')

def locate(seat):  # ⓑ Pi 세션 jsonl — 후보 ≠1 이면 ValueError (추측 0)
    return _pi().locate(seat)[0]

def stamp_of(value):
    try:
        return datetime.fromisoformat(str(value).replace('Z', '+00:00')).timestamp()
    except ValueError:
        return None

def read_events(path):  # judge 에 넘길 레코드 + 읽은 바이트
    records, size = [], 0
    with open(path, 'rb') as stream:
        for line in stream:
            size += len(line)
            try:
                record = json.loads(line)
            except ValueError:
                raise ValueError('Pi jsonl 손상 레코드') from None
            if isinstance(record, dict):
                records.append(record)
    return records, size

def judge(records):  # ⓒ (state, terminal, duration, aborted, why) — codex 판정기와 같은 꼴
    state, end, why = __import__('ft_seat_pi_turn').judge(records)
    return state, (end if state == 'IDLE' else '-'), '-', False, why

def submitted(path, offset, message, stamps=False):  # ⓓ 우리 글 = type message · role user · content text
    found = []
    with open(path, 'rb') as stream:
        stream.seek(offset)
        raw = stream.read(262144)
    for line in raw.splitlines():
        try:
            record = json.loads(line)
        except ValueError:
            continue
        payload = record.get('message') if record.get('type') == 'message' else None
        if not isinstance(payload, dict) or payload.get('role') != 'user':
            continue
        content = payload.get('content')
        parts = [p.get('text', '') for p in content
                 if isinstance(p, dict) and p.get('type') == 'text'] if isinstance(content, list) else []
        text = content if isinstance(content, str) else ''.join(parts)
        if len(parts) > 1 or ''.join(text.split()) != ''.join(message.split()):
            continue  # 실측: Pi 는 본문 속 줄바꿈을 보존하지 않는다 → 공백 무시 비교
        if not stamps:
            return True
        found.append(stamp_of(record.get('timestamp')))
    return found

def _marks(pane):  # (줄들, «전부 ─» 줄 번호)
    lines = pane.splitlines()
    return lines, [i for i, line in enumerate(lines) if DIVIDER.fullmatch(line.strip())]

def box_state(pane):  # r1836 B1·B2: (empty|text|unknown, 글, 이유) — 경계를 못 찾으면 «빈 칸» 아님
    lines, marks = _marks(pane)
    if not marks:
        return 'unknown', '', 'no-bottom'
    last, start = marks[-1], marks[-2] + 1 if len(marks) >= 2 else marks[-1]
    while len(marks) < 2 and start > 0 and lines[start - 1].strip() and not MARK.match(lines[start - 1].strip()):
        start -= 1
    text = '\n'.join(line for line in lines[start:last] if not MARK.match(line.strip())).strip()
    if any(not (s.startswith(('~/', '/')) or STATUS.match(s)) for s in (x.strip() for x in lines[last + 1:]) if s):
        return 'unknown', text, 'foreign-footer'  # 아래 경계선 밑 = cwd·상태 줄만
    if any(BROKEN.search(s) and not MARK.match(s) and not DIVIDER.fullmatch(s) for s in map(str.strip, lines[start:])):
        return 'unknown', text, 'broken-border'  # ─ 로 끝나는 덮인 경계선
    if not any(STATUS.match(x.strip()) for x in lines[last + 1:]):
        return 'unknown', text, 'no-status'  # ⓓ 상태 줄 없음 = 화면 바닥을 못 봄
    top = next((i for i in range(last - 1, -1, -1) if DIVIDER.fullmatch(lines[i].strip()) or MARK.match(lines[i].strip())), None)
    if top is not None and OVERFLOW.match(lines[top].strip()):
        return 'text', text, ''  # 넘친 상자 = 글 있음 (보이는 글 0 이어도)
    return ('text' if text else 'empty'), text, ''

def box(pane):  # ⓔ 상자 글 — 두 경계선 사이 · 바닥 경계선만 보이면 위쪽 글 꼬리 (r1836: 상태는 box_state)
    return box_state(pane)[1]

def busy(pane):  # ⓔ 바쁨 표식 «⠋ Working» 은 ── 사이에 박혀 있다
    return bool(re.search(r'^─+.*Working.*─+$', pane, flags=re.M))

def exact_input(capture, message, quiet=False):  # ⓔ 공백 무시 «전체» 일치 · 꼬리 접미사는 상자가 잘렸고
    text, flat = ''.join(box(capture).split()), ''.join(message.split())  # 우리 입력 뒤 사람 흔적 0 일 때만 (B1)
    if text and text == flat:
        return True
    return len(_marks(capture)[1]) < 2 and quiet and len(text) >= 120 and flat.endswith(text)
