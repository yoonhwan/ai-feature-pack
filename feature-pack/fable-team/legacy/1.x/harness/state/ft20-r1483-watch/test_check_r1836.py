"""r1836: Pi 입력창을 «비었다» 고 확인할 수 없으면 입력 0 · Enter 0 · 재입력 0 · INPUT_UNDECIDABLE + master 쪽지 1통.
Run: CHECK_PY=<check.py> PI_SEAT_PY=<ft20_pi_seat.py> python3.11 -m pytest -q test_check_r1836.py (기본값 = 같은 폴더)
변이: M1 unknown→empty → ① ⑤ · M2 아래 줄 검사 빼기 → ④ · M3 넘친 상자 글 0 = empty → ③′
      M4 reason unknown 무시 → ⑥ · M5 입력 뒤 재확인 unknown 무시 → ⑪ · M6 알림 중복 막기 빼기 → ⑦
"""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
CHECK_PY = Path(os.environ.get('CHECK_PY') or HERE / 'check.py')
PI_SEAT_PY = Path(os.environ.get('PI_SEAT_PY') or HERE / 'ft20_pi_seat.py')


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


check = load('check_r1836', CHECK_PY)
seat = load('ft20_pi_seat', PI_SEAT_PY)
T0 = datetime(2026, 11, 13, 5, 0, 0, tzinfo=timezone.utc).timestamp()
NOW = T0 + 3600  # 대상은 한 시간째 유휴 (유휴 관문 통과)
SEP, CWD, STATUS = '─' * 80, '~/Project/ai-feature-pack (main)', '↑126 ↓31k R3.8M W209k CH99.5% 12.0%/1.0M  opus'
FIXTURE = (HERE / 'fixtures' / 'r1836-pane-1697.txt').read_text(encoding='utf-8')  # ① 반례 고정본
OVER = '── ↑ 12 more ' + '─' * 60


def pane(*lines):
    return '\n'.join(lines)


EMPTY = pane('대화', SEP, '', SEP, CWD, STATUS)  # ②
BUSY = pane('── ⠇ Working ' + '─' * 60, '', SEP, CWD, STATUS)  # ②′
OVER_TEXT = pane(OVER, 'abc', SEP, CWD, STATUS)  # ③
OVER_BLANK = pane(OVER, '', SEP, CWD, STATUS)  # ③′
FOOTER = pane(SEP, '', SEP, 'ft-reload-request: inactive seat=x — 요청 파일 그대로', STATUS)  # ④
NUDGE = pane(SEP, '  ft-idle-nudge: 판정 불가 — 카드판 rc=0', SEP, CWD, STATUS)  # ⑨
BROKEN = pane(SEP, 'ft-idle-nudge: 판정 불가 — 턴 0' + '─' * 12, SEP, CWD, STATUS)  # ⓒ


def iso(epoch):
    return datetime.fromtimestamp(epoch, timezone.utc).isoformat(timespec='milliseconds').replace('+00:00', 'Z')


@pytest.mark.parametrize('capture,expected', [
    (FIXTURE, ('unknown', 'no-bottom')), ('', ('unknown', 'no-bottom')), (FOOTER, ('unknown', 'foreign-footer')),
    (BROKEN, ('unknown', 'broken-border')), (EMPTY, ('empty', '')), (OVER_TEXT, ('text', '')),
    (OVER_BLANK, ('text', '')), (NUDGE, ('text', ''))],
    ids=['1_fixture', '5_blank', '4_footer', 'c_broken', '2_empty', '3_overflow', '3b_overflow_blank', '9_nudge'])
def test_box_state_three_values(capture, expected):  # B1 B2 · M1 M2 M3
    state, _text, why = seat.box_state(capture)
    assert (state, why) == expected
    assert seat.box(capture) == seat.box_state(capture)[1]  # box() 호환 래퍼


def test_6_reason_blocks_ready(monkeypatch):  # ⑥ · M4 (기준판 READY)
    monkeypatch.setattr(check, 'ENGINE', 'pi')
    monkeypatch.setitem(sys.modules, 'ft20_pi_seat', seat)
    assert check.reason('IDLE', iso(T0 + 1), iso(T0), FIXTURE) == 'INPUT_UNDECIDABLE'
    assert check.reason('IDLE', iso(T0 + 1), iso(T0), BUSY) == 'PANE_BUSY'  # ②′ 바쁨이 먼저
    assert check.reason('IDLE', iso(T0 + 1), iso(T0), EMPTY) == 'READY'


@pytest.fixture
def world(tmp_path, monkeypatch):
    """tmp 명부·LIVE_BIN + 가짜 tmux·Pi 결속·mbox(인자 기록) + 주입 시계. 실 pane·실 우편함·sleep 0."""
    ft, brief = tmp_path / 'ft', Path(tempfile.mkdtemp(dir='/tmp')) / 'BRIEF.md'
    brief.write_text('[ft20-check 300초] 지침 시험용\n', encoding='utf-8')
    ft.mkdir()
    (ft / 'LIVE_BIN').write_text(str(tmp_path / 'livebin') + '\n', encoding='utf-8')
    (ft / 'seats-harness.json').write_text(json.dumps({'_master': 'master#1', 'pi#1': {'role': 'qa'}}))
    (core := tmp_path / 'core.html').write_text('const stages = [{"items": [["a", false]]}];', encoding='utf-8')
    (jsonl := tmp_path / 'pi.jsonl').write_text(json.dumps({'type': 'message', 'timestamp': iso(T0), 'message': {
        'role': 'assistant', 'content': [{'type': 'text', 'text': 'done'}]}}) + '\n', encoding='utf-8')
    (tmp_path / 'config.json').write_text(json.dumps({
        'enabled': True, 'role': 'qa', 'engine': 'pi', 'core': str(core), 'brief': str(brief),
        'helper': '/pinned/bin', 'roster': str(ft / 'seats-harness.json'),
        'successor_dir': str(ft), 'live_bin': str(ft / 'LIVE_BIN')}), encoding='utf-8')
    message = check.doorbell_line({'brief': str(brief)})
    state = {'screens': [EMPTY], 'typed': 0, 'enters': 0, 'mbox': [], 'mbox_rc': 0,
             'terminal': iso(T0), 'now': NOW, 'message': message, 'after_type': pane(SEP, message, SEP, CWD, STATUS)}

    def fake(args):
        joined = ' '.join(args)
        if 'mbox.sh' in joined:
            state['mbox'].append(list(args))
            if state['mbox_rc']:
                raise subprocess.CalledProcessError(state['mbox_rc'], args)
        elif 'list-panes' in joined or 'ft-agent-alive.sh' in joined:
            return '%1697|1234\n' if 'list-panes' in joined else 'ALIVE\n'
        elif 'capture-pane' in joined:
            return state['screens'].pop(0) if len(state['screens']) > 1 else state['screens'][0]
        elif 'send-keys' in joined and '-l' in args:
            state['typed'], state['screens'] = state['typed'] + 1, [state['after_type']]
        elif 'send-keys' in joined and args[-1] == 'Enter':
            state['enters'] += 1
            with jsonl.open('a', encoding='utf-8') as stream:
                stream.write(json.dumps({'type': 'message', 'timestamp': iso(state['now'] + 1), 'message': {
                    'role': 'user', 'content': [{'type': 'text', 'text': message}]}}) + '\n')
        return ''  # has-session · list-clients

    monkeypatch.setitem(sys.modules, 'ft20_pi_seat', seat)
    monkeypatch.setattr(seat, 'locate', lambda name: str(jsonl))
    monkeypatch.setattr(seat, 'read_events', lambda path: ([], 0))
    monkeypatch.setattr(seat, 'judge', lambda events: ('IDLE', state['terminal'], '-', False, '-'))
    for name, value in (('run', fake), ('BASE', tmp_path), ('FT', ft)):
        monkeypatch.setattr(check, name, value)
    monkeypatch.setattr(check.time, 'sleep', lambda _seconds: None)
    monkeypatch.setattr(check.time, 'time', lambda: state['now'])
    return tmp_path, state


def stuck(base, state, age, **extra):  # 실사건 꼴: 같은 턴 · 두 번 넣고 손 뗀 상태 · 마지막 입력 = age 초 전
    value = dict(seat='pi#1', terminal=state['terminal'], first_seen_at=T0, pending_terminal=state['terminal'],
                 pending_offset=0, pending_sha=check.digest(state['message']), retyped=True,
                 typed_at=state['now'] - age, status='DELIVERY_INPUT_CHANGED')
    value.update(extra)
    (base / 'latest.json').write_text(json.dumps(value), encoding='utf-8')


def saved(base):
    return json.loads((base / 'latest.json').read_text(encoding='utf-8'))


BODY = '[막힘] ft20-check 300초 — pi#1 입력창 판정 불가(no-bottom) · 깨움 보류 · terminal %s'


@pytest.mark.parametrize('pending', [True, False], ids=['deliver', 'reason'])
def test_1_fixture_types_nothing_and_alerts(world, pending):  # ① · M1 (기준판 = 입력 1 → Red)
    base, state = world
    state['screens'] = [FIXTURE]
    stuck(base, state, check.MAX_DELAY_SECONDS + 1, **({} if pending else {'pending_terminal': None}))
    before = saved(base)
    assert check.check() == 'INPUT_UNDECIDABLE'
    assert state['typed'] == 0 and state['enters'] == 0
    after = saved(base)
    assert after['status'] == 'INPUT_UNDECIDABLE' and after['box_undecidable'] == 'no-bottom'
    assert all(after[k] == before[k] for k in ('pending_terminal', 'typed_at', 'retyped', 'pending_sha'))
    assert len(state['mbox']) == 1 and state['mbox'][0][-4:-1] == ['send', 'master#1', 'ft20-r1483-watch']
    assert state['mbox'][0][-1] == BODY % state['terminal']
    assert (after['input_alerted_terminal'], after['alert_rc']) == (state['terminal'], 0)


def test_7_alert_once_per_terminal_and_rc(world):  # ⑦ · M6
    base, state = world
    state['screens'] = [FIXTURE]
    stuck(base, state, check.MAX_DELAY_SECONDS + 1)
    check.check()
    state['now'] += 300
    assert check.check() == 'INPUT_UNDECIDABLE' and len(state['mbox']) == 1  # 같은 terminal = 0 더
    state['terminal'] = iso(T0 + 60)
    assert check.check() == 'INPUT_UNDECIDABLE' and len(state['mbox']) == 2  # 턴이 바뀜 = 1 더
    state['terminal'], state['mbox_rc'] = iso(T0 + 120), 1
    assert check.check() == 'INPUT_UNDECIDABLE'  # 쪽지 실패 = 예외 0
    assert saved(base)['alert_rc'] == 1 and state['typed'] == 0


def test_10_three_rounds_never_retype(world):  # ⑩ (기준판 = 회차마다 입력 1 → Red)
    base, state = world
    state['screens'] = [FIXTURE]
    stuck(base, state, check.MAX_DELAY_SECONDS + 1)
    for _ in range(3):
        check.check()
        state['now'] += check.MAX_DELAY_SECONDS + 1
    assert state['typed'] == 0 and state['enters'] == 0


def test_11_broken_after_typing_keeps_claim_no_enter(world):  # M5 · DA 메모: 입력 후 깨짐 = 입력 1 보존 · Enter 0
    base, state = world
    state['after_type'] = FIXTURE  # 처음엔 깨끗한 빈 상자 · 입력 뒤 재확인에서 경계가 덮인다
    assert check.check() == 'INPUT_UNDECIDABLE'
    assert state['typed'] == 1 and state['enters'] == 0
    claim = saved(base)
    assert claim['pending_terminal'] == state['terminal'] and claim['typed_at'] == state['now']
    state['now'] += check.MAX_DELAY_SECONDS + 1  # 다음 회차도 깨짐 = 재입력 0
    assert check.check() == 'INPUT_UNDECIDABLE'
    assert state['typed'] == 1 and state['enters'] == 0


def test_2_clean_empty_box_still_notifies(world):  # ② 회귀
    base, state = world
    assert check.check() == 'NOTIFIED' and state['typed'] == 1 and state['enters'] == 1 and state['mbox'] == []


def test_2b_working_before_box(world):  # ②′ 회귀
    base, state = world
    state['screens'] = [BUSY]
    assert check.check() == 'PANE_BUSY' and state['typed'] == 0 and state['mbox'] == []


@pytest.mark.parametrize('screen', [OVER_TEXT, OVER_BLANK, NUDGE], ids=['3_overflow', '3b_overflow_blank', '9_nudge'])
def test_3_9_text_box_is_others_text(world, screen):  # ③ ③′ ⑨ · M3: 입력 0 · Enter 0 · r1834 E2 쪽지 1
    base, state = world
    state['screens'] = [screen]
    stuck(base, state, check.MAX_DELAY_SECONDS + 1)
    assert check.check() == 'DELIVERY_INPUT_CHANGED'
    assert state['typed'] == 0 and state['enters'] == 0 and len(state['mbox']) == 1
    assert '남의 글' in state['mbox'][0][-1]
