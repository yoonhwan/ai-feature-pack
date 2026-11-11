"""r1620 fixed: 영수 출처 — «우리 Enter 뒤 ∧ 사람 흔적 0» 만 NOTIFIED. Run: python3.11 -m pytest -q <file>."""
import importlib.util
import json
import os
import sys
import tempfile
import types
from datetime import datetime, timezone
from pathlib import Path

from short_brief import SHORT_BRIEF  # r1666: 짧은 /tmp 지침 사본

import pytest

HERE = Path(__file__).resolve().parent
CHECK_PY = Path(os.environ.get('CHECK_PY') or HERE / 'check.py')


def load():
    spec = importlib.util.spec_from_file_location('check_r1620', CHECK_PY)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


check = load()
BRIEF = LONG = (HERE / 'CHECK-BRIEF.md').read_text(encoding='utf-8')  # r1625: 지침 전문 = 파일
MESSAGE = check.doorbell_line({'brief': str(SHORT_BRIEF)})  # r1625: 보내는 글 = doorbell 1줄
T0 = datetime(2026, 11, 10, 16, 41, 53, 971000, tzinfo=timezone.utc).timestamp()
STATUS = '\n\n  GPT-6-Astra low · nano#0 · Context 90% left'
HINT = '› Ask Codex to do anything'
OUR_TEXT = '› ' + MESSAGE + STATUS


def iso(epoch):
    return datetime.fromtimestamp(epoch, timezone.utc).isoformat(timespec='milliseconds').replace('+00:00', 'Z')


T = iso(T0)  # 대상 턴 끝 = terminal


def row(epoch, message):
    return json.dumps({'type': 'response_item', 'timestamp': iso(epoch), 'payload': {
        'role': 'user', 'content': [{'type': 'input_text', 'text': message}]}}) + '\n'


def append(path, text):
    with path.open('a') as stream:
        stream.write(text)


def write_cfg(base, brief_text=None):  # r1625 ②: 'message': X → 'brief': 파일 경로 (같은 본문이면 사본 폴더 파일)
    path = SHORT_BRIEF  # r1666: HERE 경로는 이 워크트리에서 200바이트 상한을 넘는다 (짧은 /tmp 사본)
    if brief_text is not None:  # X ≠ MESSAGE = 짧은 격리 경로에 X 본문 (경로 길이가 상한 200B 를 먹지 않게)
        path = Path(tempfile.mkdtemp(dir='/tmp')) / 'CHECK-BRIEF.md'
        path.write_text(brief_text, encoding='utf-8')
    cfg = {'enabled': True, 'seat': 'seat#0', 'rollout': str(base / 'rollout.jsonl'),
           'helper': str(base / 'helper'), 'core': str(base / 'core.html'),
           'interval_seconds': 300, 'brief': str(path)}
    (base / 'config.json').write_text(json.dumps(cfg), encoding='utf-8')

@pytest.fixture
def watch(tmp_path, monkeypatch):
    """Fake tmux(가짜 응답·호출 0) + 가짜 judge + 주입 시계. 실 pane·실 tmux·sleep 0."""
    rollout = tmp_path / 'rollout.jsonl'
    rollout.write_text('')
    (tmp_path / 'core.html').write_text('const stages = [{"items": [["a", false]]}];')
    write_cfg(tmp_path)
    state = {'screens': [HINT + STATUS], 'typed': 0, 'enters': 0, 'clients': '',
             'receipt_on_type': None, 'receipt_on_enter': None, 'judge': ('IDLE', T)}

    def fake_run(args):
        joined = ' '.join(args)
        if 'list-panes' in joined:
            return '%262|1234\n'
        if 'ft-agent-alive.sh' in joined:
            return 'ALIVE\n'
        if 'list-clients' in joined:
            return state['clients']
        if 'capture-pane' in joined:
            return state['screens'].pop(0) if len(state['screens']) > 1 else state['screens'][0]
        if 'send-keys' in joined:
            if '-l' in args:
                state['typed'] += 1
                if state['receipt_on_type'] is not None:
                    append(rollout, row(state['receipt_on_type'], args[-1]))
            elif args[-1] == 'Enter':
                state['enters'] += 1
                if state['receipt_on_enter'] is not None:
                    append(rollout, row(state['receipt_on_enter'], MESSAGE))
        return ''

    stub = types.ModuleType('ft_seat_codex')
    stub.read_events = lambda path: ([], 0)
    stub.judge = lambda events: (*state['judge'], '-', False, '-')
    monkeypatch.setitem(sys.modules, 'ft_seat_codex', stub)
    monkeypatch.setattr(check, 'run', fake_run)
    monkeypatch.setattr(check, 'BASE', tmp_path)
    monkeypatch.setattr(check.time, 'sleep', lambda _seconds: None)
    yield tmp_path, state, rollout


def latest(base):
    return json.loads((base / 'latest.json').read_text(encoding='utf-8'))


def type_round(base, state, monkeypatch, epoch):
    """문자를 넣었는데 상자가 어긋나 끝나는 회차 — pending 기록 · 실패 status 반환."""
    state['screens'] = [HINT + STATUS, HINT + STATUS, '› someone' + STATUS]
    monkeypatch.setattr(check.time, 'time', lambda: epoch)
    assert check.check() == 'DELIVERY_INPUT_CHANGED'
    return latest(base)


def test_a_manual_enter_after_input_changed(watch, monkeypatch):
    base, state, rollout = watch
    rollout.write_text(row(T0, 'turn start'))
    assert type_round(base, state, monkeypatch, T0 + 300)['pending_sha']  # 실패 status·pending 이 남는다
    append(rollout, row(T0 + 310, MESSAGE))  # 사람이 Enter (우리 send-keys 호출 0)
    state['screens'] = ['› someone' + STATUS]
    monkeypatch.setattr(check.time, 'time', lambda: T0 + 700)
    assert check.check() == 'MANUAL_OR_UNKNOWN_SUBMIT'
    assert latest(base)['auto_notified'] is False and latest(base)['sent_terminal'] == T
    assert state['enters'] == 0 and state['typed'] == 1  # 이 회차 Enter 0 · 재입력 0


@pytest.mark.parametrize('setup, clients, expected', [
    ({'receipt_on_type': T0 + 301}, '', 'MANUAL_OR_UNKNOWN_SUBMIT'),  # ⓑ 우리 Enter 전 영수 (M2)
    ({'receipt_on_enter': T0 + 301}, '', 'NOTIFIED'),  # ⓒ 우리 Enter 뒤 영수
    ({'receipt_on_enter': T0 + 301}, str(int(T0 + 300.5)), 'MANUAL_OR_UNKNOWN_SUBMIT'),  # ⓓ 창 안 흔적 (M3)
    ({'receipt_on_enter': T0 + 301}, str(int(T0 + 300)), 'MANUAL_OR_UNKNOWN_SUBMIT'),  # DA R1: typed_at 과 같은 초 = 사람 쪽
    ({'receipt_on_enter': T0 + 301}, str(int(T0 - 900)), 'NOTIFIED'),  # ⓓ 창 밖 활동은 무관
    ({'receipt_on_enter': T0 + 301, 'seed': True}, '', 'MANUAL_OR_UNKNOWN_SUBMIT'),  # DA R2: typed_at 없음 = 불명
])
def test_bcd_receipt_origin(watch, monkeypatch, setup, clients, expected):
    base, state, rollout = watch
    rollout.write_text(row(T0, 'turn start'))
    if setup.get('seed'):  # r1620 이전 회차가 글만 넣고 끝난 상태 — typed_at 기록이 없다
        (base / 'latest.json').write_text(json.dumps({'pending_terminal': T, 'pending_offset': 0}))
    state.update(setup, clients=clients, screens=[OUR_TEXT] * 3 if setup.get('seed') else [HINT + STATUS] * 2 + [OUR_TEXT])
    monkeypatch.setattr(check.time, 'time', lambda: T0 + 300)
    assert check.check() == expected
    record = latest(base)
    assert record['auto_notified'] is (expected == 'NOTIFIED')
    assert state['enters'] == (0 if 'receipt_on_type' in setup else 1)
    if expected == 'NOTIFIED' and setup.get('receipt_on_enter'):
        assert record['enter_at'] == T0 + 300 and record['receipt_at'] == T0 + 301  # enter_at < receipt_at


def test_e_message_changed_since_typing(watch, monkeypatch):
    base, state, rollout = watch
    rollout.write_text(row(T0, 'turn start'))
    assert type_round(base, state, monkeypatch, T0 + 300)['pending_sha']
    write_cfg(base, BRIEF + 'x' * 295)  # 1121 → 1416 이력 꼴 (지침 본문 변경 → doorbell sha 변경)
    state['screens'] = ['› someone' + STATUS]
    monkeypatch.setattr(check.time, 'time', lambda: T0 + 600)
    assert check.check() == 'DELIVERY_MESSAGE_CHANGED'
    assert state['enters'] == 0 and state['typed'] == 1
