"""r1605 fixed cases: 「마지막 활동 뒤 300초 조용해야」 유휴 관문 (시각 주입 · 실 sleep 0).

Run: python3.11 -m pytest -q <this file>   (CHECK_PY=<mutant path> for the M1 mutation)
"""
import importlib.util
import json
import os
import sys
import types
from datetime import datetime, timedelta, timezone
from pathlib import Path

from short_brief import SHORT_BRIEF  # r1666: 짧은 /tmp 지침 사본

import pytest

HERE = Path(__file__).resolve().parent
CHECK_PY = Path(os.environ.get('CHECK_PY') or HERE / 'check.py')


def load():
    spec = importlib.util.spec_from_file_location('check_r1605', CHECK_PY)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


check = load()
BRIEF = LONG = (HERE / 'CHECK-BRIEF.md').read_text(encoding='utf-8')  # r1625: 지침 전문 = 파일
MESSAGE = check.doorbell_line({'brief': str(SHORT_BRIEF)})  # r1625: 보내는 글 = doorbell 1줄
GATE = 300
T_EPOCH = datetime(2026, 11, 10, 15, 41, 27, 814000, tzinfo=timezone.utc).timestamp()
T = iso = datetime.fromtimestamp(T_EPOCH, timezone.utc).isoformat(timespec='milliseconds').replace('+00:00', 'Z')
PANE = '%262'
STATUS = '\n\n  GPT-6-Astra low · nano/r1483 · Context 90% left'
HINT = '› Ask Codex to do anything'
TYPING = [HINT + STATUS, HINT + STATUS, '› ' + MESSAGE + STATUS]  # check() 1회 + deliver 1회 캡처 뒤 입력
CORE = 'const stages = [{"items": [["a", false]]}];'


def line(epoch, message='someone else'):
    return json.dumps({'type': 'event_msg', 'timestamp': datetime.fromtimestamp(
        epoch, timezone.utc).isoformat(timespec='milliseconds').replace('+00:00', 'Z'),
        'payload': {'type': 'user_message', 'message': message}}) + '\n'


@pytest.fixture
def watch(tmp_path, monkeypatch):
    """Fake tmux + fake judge; rollout lines carry real timestamps so the clock can be injected."""
    rollout = tmp_path / 'rollout.jsonl'
    rollout.write_text('')
    (tmp_path / 'core.html').write_text(CORE)
    cfg = {'enabled': True, 'seat': 'seat#0', 'rollout': str(rollout), 'helper': str(tmp_path / 'helper'),
           'core': str(tmp_path / 'core.html'), 'interval_seconds': 300,
           'brief': str(SHORT_BRIEF)}  # r1625: 'message': X → 'brief': 파일 경로
    (tmp_path / 'config.json').write_text(json.dumps(cfg), encoding='utf-8')
    state = {'screens': ['› ' + STATUS], 'typed': 0, 'enters': 0, 'receipt': True, 'judge': ('IDLE', T)}

    def fake_run(args):
        joined = ' '.join(args)
        if 'list-panes' in joined:
            return '%262|1234\n'
        if 'ft-agent-alive.sh' in joined:
            return 'ALIVE\n'
        if 'capture-pane' in joined:
            return state['screens'].pop(0) if len(state['screens']) > 1 else state['screens'][0]
        if 'send-keys' in joined:
            if '-l' in args:
                state['typed'] += 1
            elif args[-1] == 'Enter':
                state['enters'] += 1
                if state['receipt']:
                    with rollout.open('a') as stream:
                        stream.write(json.dumps({'type': 'response_item', 'payload': {'role': 'user', 'content': [
                            {'type': 'input_text', 'text': MESSAGE}]}}) + '\n')
        return ''

    stub = types.ModuleType('ft_seat_codex')
    stub.read_events = lambda path: ([], 0)
    stub.judge = lambda events: (*state['judge'], '-', False, '-')
    monkeypatch.setitem(sys.modules, 'ft_seat_codex', stub)
    monkeypatch.setattr(check, 'run', fake_run)
    monkeypatch.setattr(check, 'BASE', tmp_path)
    monkeypatch.setattr(check.time, 'sleep', lambda _seconds: None)
    yield cfg, state, rollout, tmp_path


def at(monkeypatch, epoch):
    monkeypatch.setattr(check.time, 'time', lambda: epoch)


def latest(base):
    return json.loads((base / 'latest.json').read_text(encoding='utf-8'))


# --- ⓐ 299초는 보내지 않는다 --------------------------------------------------------

def test_a_idle_299_below_gate(tmp_path):
    rollout = tmp_path / 'rollout.jsonl'
    rollout.write_text(line(T_EPOCH))
    assert check.idle_seconds(str(rollout), T, now=T_EPOCH + 299) == pytest.approx(299)


def test_a_299_round_debounces(watch, monkeypatch):
    cfg, state, rollout, base = watch
    rollout.write_text(line(T_EPOCH))  # 마지막 활동 = 턴 끝 T
    at(monkeypatch, T_EPOCH + 299)
    assert check.check() == 'IDLE_DEBOUNCE'
    record = latest(base)
    assert record['status'] == 'IDLE_DEBOUNCE' and record['idle_seconds'] == 299
    assert record['idle_remaining_seconds'] == 1  # 남은 초 1줄
    assert state['typed'] == 0 and state['enters'] == 0
    assert record.get('sent_terminal') is None and record.get('pending_terminal') is None


# --- ⓑ 300초면 1회 발신 · 같은 터미널 다음 회차 0 ------------------------------------

def test_b_300_round_sends_once(watch, monkeypatch):
    cfg, state, rollout, base = watch
    rollout.write_text(line(T_EPOCH))
    state['screens'] = list(TYPING)
    at(monkeypatch, T_EPOCH + 300)
    assert check.check() == 'NOTIFIED'
    assert state['typed'] == 1 and state['enters'] == 1
    assert latest(base)['sent_terminal'] == T and latest(base)['idle_seconds'] == 300
    state['screens'] = ['› ' + STATUS]
    at(monkeypatch, T_EPOCH + 600)
    assert check.check() == 'ALREADY_NOTIFIED'
    assert state['typed'] == 1 and state['enters'] == 1  # 다음 회차 발신 0


# --- ⓒ 새 활동은 시계를 되돌린다 -----------------------------------------------------

def test_c_new_activity_resets_clock(watch, monkeypatch):
    cfg, state, rollout, base = watch
    a_epoch = T_EPOCH + 200
    rollout.write_text(line(T_EPOCH) + line(a_epoch))
    at(monkeypatch, a_epoch + 299)
    assert check.check() == 'IDLE_DEBOUNCE'  # 턴 끝 기준 499초지만 활동 기준 299초
    assert state['typed'] == 0 and state['enters'] == 0
    assert latest(base)['idle_seconds'] == 299
    state['screens'] = list(TYPING)
    at(monkeypatch, a_epoch + 300)
    assert check.check() == 'NOTIFIED' and state['enters'] == 1


# --- ⓓ 작업 중·복구 회차도 같은 관문 --------------------------------------------------

def test_d_working_round_types_nothing(watch, monkeypatch):
    cfg, state, rollout, base = watch
    state['judge'] = ('WORKING', '-')
    rollout.write_text(line(T_EPOCH))  # 방금 활동 = 유휴 0
    at(monkeypatch, T_EPOCH + 5)
    assert check.check() == 'WORKING'
    assert state['typed'] == 0 and state['enters'] == 0


def test_d_typing_and_enter_recheck_gate(watch):
    cfg, state, rollout, base = watch
    state['screens'] = [HINT + STATUS]
    idle = lambda _events: ('IDLE', T, '-', False, '-')
    assert check.deliver(PANE, cfg, T, MESSAGE, lambda _p: ([], 0), idle, {}, lambda: False) == 'IDLE_DEBOUNCE'
    assert state['typed'] == 0 and state['enters'] == 0  # 문자 입력 0
    state['screens'] = ['› ' + MESSAGE + STATUS]
    pending = {'pending_terminal': T, 'pending_offset': 0}
    assert check.deliver(PANE, cfg, T, MESSAGE, lambda _p: ([], 0), idle, pending, lambda: False) == 'IDLE_DEBOUNCE'
    assert state['enters'] == 0 and state['typed'] == 0  # Enter 0 · pending 불변
    assert pending == {'pending_terminal': T, 'pending_offset': 0}
