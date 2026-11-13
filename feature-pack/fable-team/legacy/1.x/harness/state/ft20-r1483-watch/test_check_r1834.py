"""r1834: 같은 턴 DELIVERY_INPUT_CHANGED 뒤 빈 입력창이면 상한(600초) 뒤 새 시도 1회 · 남의 글이면 master 쪽지 1통.
Run: CHECK_PY=<check.py> python3.11 -m pytest -q test_check_r1834.py  (기본값 = 같은 폴더 check.py)
변이: M1 재시도 빼기 → ① · M2 상한 0초 → ①′ · M3 남의 글 재시도 → ② · M4 중복 막기 빼기 → ②′
      M5 좌석 키 → ②″ · M6 쪽지 실패 예외 → ③ · M7 typed_at 갱신 빼기 → ④
"""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import types
from datetime import datetime, timezone
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
CHECK_PY = Path(os.environ.get('CHECK_PY') or HERE / 'check.py')
spec = importlib.util.spec_from_file_location('check_r1834', CHECK_PY)
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)
T0 = datetime(2026, 11, 13, 8, 57, 0, tzinfo=timezone.utc).timestamp()
NOW = T0 + 3600  # 대상은 한 시간째 유휴 (유휴 관문 통과)


def iso(epoch):
    return datetime.fromtimestamp(epoch, timezone.utc).isoformat(timespec='milliseconds').replace('+00:00', 'Z')


@pytest.fixture
def world(tmp_path, monkeypatch):
    """tmp 명부·LIVE_BIN + 가짜 tmux·가짜 mbox(인자 기록) + 주입 시계. 실 좌석·실 우편함·sleep 0."""
    ft, live, brief = tmp_path / 'ft', tmp_path / 'livebin', Path(tempfile.mkdtemp(dir='/tmp')) / 'BRIEF.md'
    brief.write_text('[ft20-check 300초] 지침 시험용\n', encoding='utf-8')
    live.mkdir(), ft.mkdir()
    (ft / 'LIVE_BIN').write_text(str(live) + '\n', encoding='utf-8')
    (ft / 'seats-harness.json').write_text(json.dumps({'_master': 'master#1', 'qa#1': {'role': 'qa'}}))
    (core := tmp_path / 'core.html').write_text('const stages = [{"items": [["a", false]]}];', encoding='utf-8')
    (rollout := tmp_path / 'rollout.jsonl').write_text(json.dumps({'type': 'event_msg', 'timestamp': iso(T0),
                                                                  'payload': {'type': 'user_message', 'message': 'turn'}}) + '\n')
    (tmp_path / 'config.json').write_text(json.dumps({
        'enabled': True, 'role': 'qa', 'engine': 'codex', 'core': str(core), 'brief': str(brief),
        'helper': '/pinned/bin', 'rollout': str(rollout), 'roster': str(ft / 'seats-harness.json'),
        'successor_dir': str(ft), 'live_bin': str(ft / 'LIVE_BIN')}), encoding='utf-8')
    message = check.doorbell_line({'brief': str(brief)})
    state = {'box': '', 'land': True, 'typed': 0, 'enters': 0, 'mbox': [], 'mbox_rc': 0,
             'terminal': iso(T0), 'now': NOW, 'message': message}

    def fake(args):
        joined = ' '.join(args)
        if 'mbox.sh' in joined:
            state['mbox'].append(list(args))
            if state['mbox_rc']:
                raise subprocess.CalledProcessError(state['mbox_rc'], args)
        elif 'list-panes' in joined or 'ft-agent-alive.sh' in joined:
            return '%1697|1234\n' if 'list-panes' in joined else 'ALIVE\n'
        elif 'capture-pane' in joined:
            return '› ' + state['box']
        elif 'send-keys' in joined and '-l' in args:
            state['typed'], state['box'] = state['typed'] + 1, message if state['land'] else state['box']
        elif 'send-keys' in joined and args[-1] == 'Enter':
            state['enters'], state['box'] = state['enters'] + 1, ''
            with rollout.open('a', encoding='utf-8') as stream:
                stream.write(json.dumps({'type': 'response_item', 'timestamp': iso(state['now'] + 1), 'payload': {
                    'role': 'user', 'content': [{'type': 'input_text', 'text': message}]}}) + '\n')
        return ''  # has-session · list-clients

    codex = types.ModuleType('ft_seat_codex')
    codex.read_events = lambda path: ([], 0)
    codex.judge = lambda events: ('IDLE', state['terminal'], '-', False, '-')
    monkeypatch.setitem(sys.modules, 'ft_seat_codex', codex)
    for name, value in (('run', fake), ('BASE', tmp_path), ('FT', ft)):
        monkeypatch.setattr(check, name, value)
    monkeypatch.setattr(check.time, 'sleep', lambda _seconds: None)
    monkeypatch.setattr(check.time, 'time', lambda: state['now'])
    return tmp_path, state


def stuck(base, state, age, **extra):  # 같은 턴 · 두 번 넣고 손 뗀 상태 · 마지막 입력 = age 초 전
    value = dict(seat='qa#1', terminal=state['terminal'], first_seen_at=T0, pending_terminal=state['terminal'],
                 pending_offset=0, pending_sha=check.digest(state['message']), retyped=True,
                 typed_at=state['now'] - age, status='DELIVERY_INPUT_CHANGED')
    value.update(extra)
    (base / 'latest.json').write_text(json.dumps(value), encoding='utf-8')


def saved(base):
    return json.loads((base / 'latest.json').read_text(encoding='utf-8'))


def test_1_empty_box_after_max_delay_tries_once_more(world):  # ① · M1
    base, state = world
    stuck(base, state, check.MAX_DELAY_SECONDS + 1)
    assert check.check() == 'NOTIFIED'
    assert state['typed'] == 1 and state['enters'] == 1 and state['mbox'] == []


def test_1b_before_max_delay_types_nothing(world):  # ①′ · M2
    base, state = world
    stuck(base, state, check.MAX_DELAY_SECONDS - 1)
    assert check.check() == 'DELIVERY_INPUT_CHANGED'
    assert state['typed'] == 0 and state['enters'] == 0 and state['mbox'] == []


@pytest.mark.parametrize('pending', [True, False], ids=['deliver', 'input_present'])
def test_2_other_text_alerts_master_once_per_terminal(world, pending):  # ② ②′ ②″ · M3 M4 M5
    base, state = world
    state['box'] = 'abc'  # 아래: deliver 길 / pending 없이 INPUT_PRESENT 로 일찍 끝나는 길
    stuck(base, state, 3600, **({} if pending else {'pending_terminal': None, 'retyped': None}))
    assert check.check() in ('DELIVERY_INPUT_CHANGED', 'INPUT_PRESENT')
    assert state['typed'] == 0 and state['enters'] == 0 and len(state['mbox']) == 1
    assert (sent := state['mbox'][0])[-4:-1] == ['send', 'master#1', 'ft20-r1483-watch']
    assert sent[-1] == ('[막힘] ft20-check 300초 — qa#1 입력창에 남의 글 · 깨움 보류 · terminal %s'
                        % state['terminal'])
    assert (saved(base)['input_alerted_terminal'], saved(base)['alert_rc']) == (state['terminal'], 0)
    state['now'] += 300
    check.check()  # ②′ 같은 terminal = 쪽지 0 더
    assert len(state['mbox']) == 1 and state['typed'] == 0
    state['terminal'] = iso(T0 + 60)  # ②″ 턴이 바뀐 뒤 같은 꼴 = 1통 더
    assert check.check() == 'INPUT_PRESENT'
    assert len(state['mbox']) == 2 and state['typed'] == 0 and state['enters'] == 0


def test_3_mbox_failure_is_recorded_not_raised(world):  # ③ · M6
    base, state = world
    state['box'], state['mbox_rc'] = 'abc', 1
    stuck(base, state, 3600)
    assert check.check() == 'DELIVERY_INPUT_CHANGED'  # 예외 0 · 회차 status 그대로
    assert saved(base)['alert_rc'] == 1 and saved(base)['status'] == 'DELIVERY_INPUT_CHANGED'


def test_4_failed_new_try_waits_for_next_max_delay(world):  # ④ · M7
    base, state = world
    state['land'] = False  # 새 시도 글이 입력창에 안 붙는다
    stuck(base, state, check.MAX_DELAY_SECONDS + 1)
    assert check.check() == 'DELIVERY_INPUT_CHANGED' and state['typed'] == 1
    state['now'] += 300  # 상한 전 다음 회차 = 입력 0
    assert check.check() == 'DELIVERY_INPUT_CHANGED'
    assert state['typed'] == 1 and state['enters'] == 0 and state['mbox'] == []
