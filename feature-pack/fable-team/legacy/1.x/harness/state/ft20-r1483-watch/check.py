#!/usr/bin/env python3
"""Temporary exact-session watchdog; existing ft Codex parser, one check per launchd tick."""
import fcntl
import hashlib
import json
import re
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

BASE = Path(__file__).resolve().parent
FT = Path('/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team')  # r1666: 명부·도달 파일·LIVE_BIN 자리


def run(args):
    return subprocess.run(args, check=True, capture_output=True, text=True, timeout=7).stdout


def roster_names(path, role):  # r1666 ⓔ: 그 역할의 현역 좌석 (승계·닫힘 표시 제외 · 좌석 이름 등록 0)
    data = json.loads(Path(path).read_text(encoding='utf-8'))
    return [name for name, row in data.items()
            if isinstance(row, dict) and row.get('role') == role
            and not row.get('_replaced_by') and not row.get('stop_ready')]


def successor_of(seat, folder=None):  # r1666 ⓔ: 도달 파일(state/successor/<좌석>.json) → 후계 · 연쇄 추적
    seen, now = {seat}, seat
    while True:
        path = Path(folder or FT / 'state' / 'successor') / (now + '.json')
        try:
            nxt = json.loads(path.read_text(encoding='utf-8')).get('successor') or now
        except (OSError, ValueError):
            return now
        if nxt == now or nxt in seen:  # 순환·자기 참조 = 여기서 멈춘다
            return now
        seen.add(nxt)
        now = nxt


def session_exists(seat):  # r1666: tmux 세션 유무 (명령 실패 = False · 예외로 회차를 죽이지 않는다)
    try:
        run(['tmux', 'has-session', '-t', '=' + seat])
        return True
    except subprocess.SubprocessError:
        return False


def resolve_target(cfg):  # r1666 ⓔ 받는 좌석 = 명부 현역 → 도달 파일 후계. (좌석, 문제) · 문제면 송신 0
    role = cfg.get('role')
    if not role:  # role 칸 없는 옛 config = 종전 seat 칸 그대로 (설치 때 role 로 옮긴다)
        return cfg['seat'], None
    roster = Path(cfg.get('roster') or FT / 'seats-harness.json')
    try:
        names = roster_names(roster, role)
    except (OSError, ValueError) as error:
        return None, ('ROSTER_UNREADABLE', '%s: %s' % (roster, error))
    if not names:
        return None, ('NO_TARGET_SEAT', '명부 role=%s 현역 0 (%s)' % (role, roster))
    targets = {successor_of(name, cfg.get('successor_dir')) for name in names}  # 교체 전이 중 = 후계 하나로 모인다
    if len(targets) > 1:  # 한쪽을 임의로 고르지 않는다 (대상 모호)
        return None, ('TARGET_AMBIGUOUS', '명부 role=%s 현역 %d석 → 대상 %d: %s'
                      % (role, len(names), len(targets), ' '.join(sorted(targets))))
    seat = targets.pop()
    if not session_exists(seat):
        return None, ('TARGET_NOT_RUNNING', '%s: tmux 세션 없음' % seat)
    return seat, None


def overdue(result):  # r1666 R1②: «디바운스 + 주기» 상한을 넘겼나 (넘으면 유휴 문턱을 기다리지 않는다)
    mark = result.get('sent_at')
    if mark is None:  # 아직 송신 0 = 이 턴을 처음 본 시각부터 잰다 (회차 시각이 아니다)
        mark = result.get('first_seen_at')
    return mark is not None and time.time() - mark >= MAX_DELAY_SECONDS


def live_bin(cfg):  # r1666 ⓖ: 회차마다 LIVE_BIN 파일을 읽는다 (판 번호를 등록·설정에 고정하지 않는다)
    path = Path(cfg.get('live_bin') or FT / 'LIVE_BIN')
    try:
        value = path.read_text(encoding='utf-8').splitlines()[0].strip()
    except (OSError, IndexError):
        return cfg['helper']  # LIVE_BIN 없음 = 종전 칸 (판 고정 아님 · 아래에서 1줄 남긴다)
    return value or cfg['helper']


def save(path, value):
    tmp = path.with_suffix('.tmp')
    tmp.write_text(json.dumps(value, ensure_ascii=False) + '\n', encoding='utf-8')
    tmp.replace(path)


IDLE_GATE_SECONDS = 300  # r1605: «마지막 활동 뒤 300초 조용했나» 관문 (StartInterval 과 별개)
MAX_DELAY_SECONDS = IDLE_GATE_SECONDS + 300  # r1666 R1②: 디바운스 + 주기 = 최악 지연 상한 (새 숫자 0)
DOORBELL_MAX_BYTES = 200  # r1625: 입력창에 넣는 지침 문구는 1줄 · 200바이트가 상한
DOORBELL = '[ft20-check 300초] 지침 = %s sha %s · 그 형식으로 점검'  # r1625: 경로 + 지침 지문
ENGINE = None  # r1621: None|'codex' = 지금 경로 그대로 · 'pi' = Pi 판독기 (engine 키를 더하기만)
TYPED_AT = None  # r1621 B1: 우리가 상자에 글을 넣은 시각 (그 뒤 사람 흔적 0 판정용)
BOX_WHY = ''  # r1836 B4: 이 회차 Pi 입력창 판정 불가 이유


def stamp_of(value):
    """ISO-8601(Z) 시각 → epoch 초. 못 읽으면 None."""
    try:
        return datetime.fromisoformat(str(value).replace('Z', '+00:00')).timestamp()
    except ValueError:
        return None


def last_stamp(path):  # rollout 마지막 줄의 timestamp (뒤 64KB 창) · 못 읽으면 ''
    try:
        with open(path, 'rb') as stream:
            stream.seek(max(0, Path(path).stat().st_size - 65536))
            raw = stream.read()
    except OSError:
        return ''
    for line in reversed(raw.splitlines()):
        try:
            return json.loads(line).get('timestamp', '')
        except (ValueError, AttributeError):
            continue
    return ''


def idle_seconds(rollout, terminal, now=None):
    """마지막 활동 = max(턴 끝, rollout 마지막 줄 시각) 뒤 흐른 초 (못 읽으면 None)."""
    marks = [stamp for stamp in (stamp_of(terminal), stamp_of(last_stamp(rollout))) if stamp is not None]
    return None if not marks else (time.time() if now is None else now) - max(marks)


def doorbell_line(cfg):  # r1625: 지침 전문은 파일에서 · 입력창엔 경로+sha 12자 1줄 (못 읽으면 OSError)
    path = Path(cfg['brief'])
    path = path if path.is_absolute() else (BASE / path).resolve()
    sha = hashlib.sha256(path.read_text(encoding='utf-8').encode('utf-8')).hexdigest()[:12]
    line = DOORBELL % (path, sha)
    size = len(line.encode('utf-8'))
    if '\n' in line or size > DOORBELL_MAX_BYTES:  # 자르기·전문 송신 fallback 0
        raise ValueError('doorbell unusable: %d bytes (max %d) path=%s' % (size, DOORBELL_MAX_BYTES, path))
    return line


def pi_reader():  # r1621: Pi 판독기 — 지연 import (helper 경로는 check() 가 넣는다)
    import ft20_pi_seat
    return ft20_pi_seat


def reason(state, terminal, previous, pane):
    if state != 'IDLE':
        return state
    if terminal == previous:
        return 'ALREADY_NOTIFIED'
    if ENGINE == 'pi':  # r1621 ⓔ: Pi 바쁨 표식 · 입력 상자 (마지막 두 ─── 줄 사이) · r1836 B3: 판정 불가 = READY 0
        return ('PANE_BUSY' if pi_reader().busy(pane) else 'INPUT_UNDECIDABLE' if undecidable(pane) else
                'INPUT_PRESENT' if box_filled(pane) else 'READY')
    if re.search(r'esc to interrupt|Working \(|Thinking', pane):
        return 'PANE_BUSY'
    prompts = re.findall(r'^›\s*(.*)$', pane, flags=re.M)
    if prompts and prompts[-1].strip() not in ('', 'Ask Codex to do anything'):
        return 'INPUT_PRESENT'
    return 'READY'


def submitted(path, offset, message, stamps=False):  # r1620: stamps=True 면 매치 행의 epoch 시각 목록
    if ENGINE == 'pi':  # r1621 ⓓ: Pi 영수 = type message · role user · content text
        return pi_reader().submitted(path, offset, message, stamps)
    found = []
    with open(path, 'rb') as stream:
        stream.seek(offset)
        raw = stream.read(262144)
    for line in raw.splitlines():
        try:
            record = json.loads(line)
        except ValueError:
            continue
        payload = record.get('payload', {})
        content = payload.get('content', []) if record.get('type') == 'response_item' else []
        if (record.get('type') == 'event_msg' and payload.get('type') == 'user_message'
                and payload.get('message', '').strip() == message) or (
                payload.get('role') == 'user' and len(content) == 1
                and content[0].get('type') == 'input_text' and content[0].get('text', '').strip() == message):
            if not stamps:
                return True
            found.append(stamp_of(record.get('timestamp')))
    return found


def digest(message):  # r1620: 본문 길이·내용 지문 (옛 글 감지)
    return '%d:%s' % (len(message), hashlib.sha256(message.encode()).hexdigest()[:16])
def classify(stamps, result):  # r1620: 우리 Enter 뒤 ∧ 사람 입력 흔적 0 일 때만 NOTIFIED
    known = [stamp for stamp in stamps if stamp is not None]
    if not known:  # 시각 없는 영수 = r1601 계약 그대로 (출처 판정 불가)
        result['auto_notified'] = True
        return 'NOTIFIED'
    try:  # 붙어 있는 tmux client 의 마지막 입력 시각 (못 읽으면 None = 흔적 불명)
        marks = [float(v) for v in run(['tmux', 'list-clients', '-F', '#{client_activity}']).split()]
    except (subprocess.SubprocessError, ValueError):
        marks = None
    enter_at, typed_at, receipt_at = result.get('enter_at'), result.get('typed_at'), max(known)
    start = None if typed_at is None else int(typed_at)  # DA② R1·R2: 창 = [typed_at 내림, receipt_at 올림] · 없으면 불명
    human = marks is None or start is None or any(start <= mark < receipt_at + 1 for mark in marks)
    result.update(receipt_at=receipt_at, auto_notified=bool(
        enter_at is not None and min(known) >= enter_at and not human))
    return 'NOTIFIED' if result['auto_notified'] else 'MANUAL_OR_UNKNOWN_SUBMIT'


def quiet_since(since):  # r1621 B1: 우리 입력 시각 뒤에 붙은 client 입력 흔적 0
    if since is None:
        return False
    try:
        marks = [float(v) for v in run(['tmux', 'list-clients', '-F', '#{client_activity}']).split()]
    except (subprocess.SubprocessError, ValueError):
        return False
    return not any(mark >= int(since) for mark in marks)


def exact_input(capture, message):
    if ENGINE == 'pi':  # r1621 ⓔ·B1: 상자 글 == 우리 글 (잘린 상자만 접미사 · 사람 흔적 0)
        return pi_reader().exact_input(capture, message, quiet_since(TYPED_AT))
    prompts = list(re.finditer(r'^› ?', capture, flags=re.M))
    if not prompts:
        return False
    editor = re.split(r'^\s*(?:GPT-\S+|\? for shortcuts|\d+% context left)',
                      capture[prompts[-1].end():], maxsplit=1, flags=re.M)[0]
    pasted = re.fullmatch(r'\[Pasted Content (\d+) chars\]', editor.strip())
    if pasted:
        return int(pasted.group(1)) == len(message)  # folded paste = our notification (r1601)
    return ''.join(editor.split()) == ''.join(message.split())


def undecidable(capture):  # r1836 B3: Pi 입력창 판정 불가면 이유(그 회차 기록) · 아니면 ''
    global BOX_WHY
    state, _text, why = pi_reader().box_state(capture) if ENGINE == 'pi' else ('', '', '')
    BOX_WHY = why if state == 'unknown' else BOX_WHY
    return why if state == 'unknown' else ''


def box_filled(capture):  # r1621 ⓔ: 입력창에 글이 있나 (Pi 상자 · codex 마지막 › 줄 · 빈 칸 힌트 제외)
    if ENGINE == 'pi':  # r1836 B3: text 만 참 (unknown 은 reason·deliver 가 먼저 막는다)
        return pi_reader().box_state(capture)[0] == 'text'
    return (re.findall(r'^› ?(.*)$', capture, flags=re.M) or [''])[-1].strip() not in ('', 'Ask Codex to do anything')


def alert_master(cfg, result, what='입력창에 남의 글'):  # r1834 E2: 깨움 보류 · master 쪽지 (같은 terminal 1회 · 실패 = alert_rc)
    if result.get('input_alerted_terminal') == result['terminal']:
        return
    try:
        master = json.loads(Path(cfg.get('roster') or FT / 'seats-harness.json').read_text(encoding='utf-8'))['_master']
        run(['bash', str(FT / 'comm' / 'mbox.sh'), 'send', master, 'ft20-r1483-watch',
             '[막힘] ft20-check 300초 — %s %s · 깨움 보류 · terminal %s' % (cfg['seat'], what, result['terminal'])])
        result.update(alert_rc=0, input_alerted_terminal=result['terminal'])
    except subprocess.CalledProcessError as error:
        result['alert_rc'] = error.returncode
    except (OSError, ValueError, KeyError, subprocess.SubprocessError):
        result['alert_rc'] = -1


def submit(pane, cfg, terminal, message, read_events, judge, offset, gate=None, result=None):
    if judge(read_events(cfg['rollout'])[0])[:2] != ('IDLE', terminal):
        return 'DELIVERY_STATE_CHANGED'
    if gate is not None and not gate():  # r1605: Enter 직전 유휴 300초 재확인
        return 'IDLE_DEBOUNCE'
    result = result if result is not None else {}
    result['enter_at'] = time.time()
    run(['tmux', 'send-keys', '-t', pane, 'Enter'])
    for _ in range(3):
        time.sleep(0.4)
        stamps = submitted(cfg['rollout'], offset, message, stamps=True)
        if stamps:
            return classify(stamps, result)
    return 'DELIVERY_UNCERTAIN'


def deliver(pane, cfg, terminal, message, read_events, judge, result, gate=None):
    # Type once per terminal, submit what the box holds, let the receipt decide 'NOTIFIED'.
    offset = Path(cfg['rollout']).stat().st_size
    typed = result.get('pending_terminal') == terminal
    if typed and result.get('pending_sha') and result['pending_sha'] != digest(message):
        return 'DELIVERY_MESSAGE_CHANGED'  # r1620 ⓔ: 본문이 바뀐 뒤 옛 글에 Enter 0
    if typed and submitted(cfg['rollout'], result.get('pending_offset') or 0, message):
        # r1620 ⓐ: 지난 회차 글의 영수 = 사람·불명이면 성공 0 (시각 없는 영수는 종전 계약)
        return classify(submitted(cfg['rollout'], result.get('pending_offset') or 0, message, stamps=True),
                        result)
    # R1: literal input and Enter only for an IDLE session on this terminal.
    if judge(read_events(cfg['rollout'])[0])[:2] != ('IDLE', terminal):
        return 'DELIVERY_STATE_CHANGED'
    capture = run(['tmux', 'capture-pane', '-pt', pane, '-S', '-25'])
    if ENGINE == 'pi' and pi_reader().busy(capture):  # r1621 R1: Pi «Working» 이면 입력·Enter 0 (pending 칸 보존)
        return 'PANE_BUSY'
    if undecidable(capture):  # r1836 B3: 입력 전 판정 불가 = 입력·Enter·claim 손 0
        return 'INPUT_UNDECIDABLE'
    if not exact_input(capture, message):
        # r1834 E1: 두 번 넣고 손 뗀 상태는 빈 입력창이면 마지막 입력 뒤 상한(600초)에 새 시도 1회로 풀린다
        expired = time.time() - (result.get('typed_at') or 0) >= MAX_DELAY_SECONDS
        if box_filled(capture) or (typed and result.get('retyped') and not expired):
            return 'DELIVERY_INPUT_CHANGED'  # someone else's text, or typed twice already.
        if gate is not None and not gate():  # r1605: 문자 입력 직전 유휴 300초 재확인
            return 'IDLE_DEBOUNCE'
        result['retyped'] = bool(typed)  # typing never landed: one resend, then hands off.
        run(['tmux', 'send-keys', '-t', pane, '-l', message])
        result.update(pending_terminal=terminal, pending_offset=offset, typed_at=time.time(), pending_sha=digest(message))  # r1620: 지문·입력 시각
        global TYPED_AT
        TYPED_AT = result['typed_at']  # r1621 B1: 방금 넣은 글 뒤 사람 흔적 0 부터 잰다
        # Let the CLI finish its paste burst before treating Enter as submission.
        time.sleep(0.4)
        stamps = submitted(cfg['rollout'], offset, message, stamps=True)
        if stamps:
            return classify(stamps, result)  # r1620 ⓑ: 우리 Enter 전 영수 = 사람·불명
        capture = run(['tmux', 'capture-pane', '-pt', pane, '-S', '-25'])
        if undecidable(capture):  # r1836 B3: 입력 뒤 깨짐 = 방금 claim 보존 · Enter 0
            return 'INPUT_UNDECIDABLE'
        if not exact_input(capture, message):
            return 'DELIVERY_INPUT_CHANGED'
    elif not typed:
        # our notification already sits in the box: book the claim before Enter (r1601).
        result.update(pending_terminal=terminal, pending_offset=offset, pending_sha=digest(message))
    return submit(pane, cfg, terminal, message, read_events, judge, offset, gate, result)


def check():
    cfg = json.loads((BASE / 'config.json').read_text(encoding='utf-8'))
    latest = BASE / 'latest.json'
    old = json.loads(latest.read_text(encoding='utf-8')) if latest.exists() else {}
    result = {'at': time.time(), 'sent_terminal': old.get('sent_terminal'), 'interval_seconds': 300,
              'pending_terminal': old.get('pending_terminal'),
              'pending_offset': old.get('pending_offset'), 'retyped': old.get('retyped'),
              'pending_sha': old.get('pending_sha'), 'typed_at': old.get('typed_at'),
              'sent_at': old.get('sent_at'), 'first_seen_at': old.get('first_seen_at'),
              'input_alerted_terminal': old.get('input_alerted_terminal'), 'alert_rc': old.get('alert_rc')}
    other = {}  # r1834 E2: 이 회차 입력창에 남의 글이 있었나
    global TYPED_AT, BOX_WHY
    TYPED_AT, BOX_WHY = result.get('typed_at'), ''
    def finish(status):
        result['status'] = status
        if status == 'INPUT_UNDECIDABLE':  # r1836 B4: other.text 없이 판정 불가 자체로 기록·알림
            result['box_undecidable'] = BOX_WHY
            alert_master(cfg, result, '입력창 판정 불가(%s)' % BOX_WHY)
        elif other.get('text') and status in ('INPUT_PRESENT', 'DELIVERY_INPUT_CHANGED'):
            alert_master(cfg, result)
        save(latest, result)
        return status
    if not cfg['enabled']:
        return finish('DISABLED')
    seat, problem = resolve_target(cfg)  # r1666 ⓔ: 회차마다 명부·도달 파일에서 받는 좌석을 찾는다
    # r1666 ⓕ (DA 단계 2 R1①): 실패 회차에도 seat 를 남긴다 — 잃으면 다음 회차가 대상 변경을 못 알아본다
    result['seat'] = seat or old.get('seat') or cfg.get('seat')
    if problem is not None:  # 송신 0 + error 1줄 · 예외로 회차를 죽이지 않는다 (RuntimeError 0)
        save(BASE / 'error.json', {'at': time.time(), 'status': problem[0], 'error': problem[1][:1000]})
        return finish(problem[0])
    if old.get('seat') != seat:  # r1666 ⓕ: 대상이 바뀌면 «그 좌석의 입력 위치» 만 비운다 (사건 이력은 이월)
        # seat 칸 없는 구판 latest 도 «대상 바뀜» 이다 — 옛 좌석의 위치 값이 새 좌석에 뜻이 없다 (DA 단계 2 R2①)
        result.update(pending_offset=None, pending_sha=None, sent_terminal=None, input_alerted_terminal=None)
    cfg['seat'] = seat
    core = Path(cfg['core']).read_text(encoding='utf-8')
    stages = json.loads(re.search(r'const stages = (.*?);', core).group(1))
    items = [item for stage in stages for item in stage['items']]
    if len(items) == 20 and all(item[1] is True for item in items):
        cfg['enabled'] = False
        save(BASE / 'config.json', cfg)
        finish('GOAL_COMPLETE_DISABLED')
        return 'GOAL_COMPLETE_DISABLED'
    try:  # r1625: 지침은 파일에서 1줄로만 — 실패면 이 회차 송신 0 + error.json 1줄
        message = doorbell_line(cfg)
    except (OSError, ValueError) as error:
        save(BASE / 'error.json', {'at': time.time(), 'status': 'BRIEF_UNUSABLE',
                                   'error': str(error)[:1000]})
        return finish('BRIEF_UNUSABLE')
    sys.path.insert(0, live_bin(cfg))  # r1666 ⓖ: LIVE_BIN 매 회차 읽기 (예: live/1.1.29x/bin)
    global ENGINE
    ENGINE = cfg.get('engine') or 'codex'  # r1621: 없거나 'codex' = 종전 경로 그대로 (ⓐ)
    if ENGINE == 'pi':  # r1621 ⓑ: 회차마다 Pi 결속으로 찾음 (경로 고정 0 · 후보 ≠1 = 판정 불가)
        import ft20_pi_seat as reader
        cfg['rollout'] = reader.locate(cfg['seat'])
    else:
        import ft_seat_codex as reader
    read_events, judge = reader.read_events, reader.judge
    try:
        rows = run(['tmux', 'list-panes', '-t', cfg['seat'], '-F', '#{pane_id}|#{pane_pid}']).splitlines()
    except subprocess.SubprocessError as error:  # 대상 tmux 없음 = 송신 0 + error 1줄
        save(BASE / 'error.json', {'at': time.time(), 'status': 'TARGET_NOT_RUNNING',
                                   'error': ('%s: %s' % (cfg['seat'], error))[:1000]})
        return finish('TARGET_NOT_RUNNING')
    if len(rows) != 1:
        raise RuntimeError('exactly one target pane required')
    pane, pid = rows[0].split('|')
    alive = run(['bash', '/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/comm/ft-agent-alive.sh', cfg['seat']])
    if 'ALIVE' not in alive.upper():
        raise RuntimeError('agent not verified')
    events, size = read_events(cfg['rollout'])
    state, terminal, _, _, why = judge(events)
    result['terminal'] = terminal  # r1666 R2②: 매 회차 저장한다 (빠지면 다음 회차가 턴을 새로 봐서 상한이 안 쌓인다)
    same_turn = old.get('seat') == seat and old.get('terminal') in (None, terminal)
    result['first_seen_at'] = (old.get('first_seen_at') if same_turn and old.get('first_seen_at')
                               else time.time())  # 같은 턴을 계속 미루는 중 = 처음 본 시각 유지
    result.update(read_bytes=size, state=state, reason=why, pane=pane)
    capture = run(['tmux', 'capture-pane', '-pt', pane, '-S', '-25'])
    ours = exact_input(capture, message)
    other['text'] = not ours and box_filled(capture)
    if terminal == result['sent_terminal'] and not ours:
        return finish('ALREADY_NOTIFIED')
    # r1605: 마지막 활동 뒤 300초가 차기 전에는 알림도 입력도 없다 (같은 관문을 입력 직전에 재확인).
    idle = idle_seconds(cfg['rollout'], terminal)
    result['idle_seconds'] = None if idle is None else int(idle)

    def gate():
        fresh = idle_seconds(cfg['rollout'], terminal)
        return fresh is not None and (fresh >= IDLE_GATE_SECONDS or overdue(result))

    # r1666 R1②: 5분 점검·쪽지 깸이 유휴를 계속 되돌려도, 마지막 송신 뒤 상한을 넘으면 보낸다
    if state == 'IDLE' and idle is not None and idle < IDLE_GATE_SECONDS and not overdue(result):
        result['idle_remaining_seconds'] = IDLE_GATE_SECONDS - int(idle)
        return finish('IDLE_DEBOUNCE')
    # A claim without a submitted turn is not a receipt: when the box still holds our own
    # notification the earlier round never submitted it (r1601), so submit instead of waiting.
    if result.get('pending_terminal') != terminal and not ours:
        decision = reason(state, terminal, result['sent_terminal'], capture)
        if decision != 'READY':
            return finish(decision)
        # Re-read the authoritative turn boundary immediately before notification.
        if judge(read_events(cfg['rollout'])[0])[:2] != (state, terminal):
            return finish('STATE_CHANGED')
    status = deliver(pane, cfg, terminal, message, read_events, judge, result, gate)
    if status in ('NOTIFIED', 'MANUAL_OR_UNKNOWN_SUBMIT'):
        # Receipt first: 'sent' is written only once the rollout shows our user turn.
        result['sent_terminal'], result['pending_terminal'] = terminal, None
        result['sent_at'] = time.time()  # r1666 R1②: 상한 기준 = «마지막 송신» (회차 시각이 아니다)
        result['auto_notified'] = status == 'NOTIFIED'  # r1620: 사람·불명 영수는 성공 수 0
    return finish(status)


if __name__ == '__main__':
    with (BASE / 'lock').open('w', encoding='utf-8') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        try:
            check()
        except Exception as error:
            # Fixed-size latest error; no append-only logs or model call.
            ep = BASE / 'error.json'
            prior = json.loads(ep.read_text(encoding='utf-8')) if ep.exists() else {}
            detail = str(error)[:1000]
            save(ep, {'at': time.time(), 'status': 'CRITICAL', 'error': detail})
            if prior.get('error') != detail:
                try:
                    roster = Path('/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/seats-harness.json')
                    master = json.loads(roster.read_text(encoding='utf-8'))['_master']
                    run(['bash', '/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/comm/mbox.sh', 'send', master, 'ft20-r1483-watch', '[긴급] ft 2.0 오케스트레이션 체크 판정 실패. state/ft20-r1483-watch/error.json 확인·좌석 복구 필요. 동일 오류 반복 알림 없음.'])
                except Exception:
                    pass
            raise SystemExit(1)
