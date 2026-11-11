"""r1601 fixed cases: codex paste placeholder counts as our input, receipt before 'sent'.

Run: python3 -m pytest -q <this file>   (CHECK_PY=<mutant path> for the M1 mutation)
"""
import ast
import importlib.util
import json
import os
from pathlib import Path

from short_brief import SHORT_BRIEF  # r1666: 짧은 /tmp 지침 사본

import pytest

HERE = Path(__file__).resolve().parent
CHECK_PY = Path(os.environ.get('CHECK_PY') or HERE / 'check.py')


def load():
    spec = importlib.util.spec_from_file_location('check_r1601', CHECK_PY)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


check = load()
BRIEF = LONG = (HERE / 'CHECK-BRIEF.md').read_text(encoding='utf-8')  # r1625: 지침 전문 = 파일
MESSAGE = check.doorbell_line({'brief': str(SHORT_BRIEF)})  # r1625: 보내는 글 = doorbell 1줄
TERMINAL = '2026-11-10T14:54:32.134Z'
PANE = '%262'
STATUS = '\n\n  GPT-6-Astra low · nano/r1483 · Context 90% left'
PLACEHOLDER = '› [Pasted Content %d chars]' % len(MESSAGE) + STATUS


@pytest.fixture
def pane(tmp_path, monkeypatch):
    """Fake tmux: screens are served in order, Enter appends a real rollout receipt."""
    state = {'screens': [], 'calls': [], 'receipt': True, 'typed': 0, 'enters': 0,
            'rollout': tmp_path / 'rollout.jsonl'}
    state['rollout'].write_text('')

    def fake_run(args):
        state['calls'].append(list(args))
        if 'capture-pane' in args:
            return state['screens'].pop(0) if len(state['screens']) > 1 else state['screens'][0]
        if 'send-keys' in args:
            if '-l' in args:
                state['typed'] += 1
            elif args[-1] == 'Enter':
                state['enters'] += 1
                if state['receipt']:
                    line = {'type': 'response_item', 'payload': {'role': 'user', 'content': [
                        {'type': 'input_text', 'text': MESSAGE}]}}
                    with state['rollout'].open('a') as stream:
                        stream.write(json.dumps(line) + '\n')
        return ''

    monkeypatch.setattr(check, 'run', fake_run)
    monkeypatch.setattr(check.time, 'sleep', lambda _seconds: None)
    cfg = {'rollout': str(state['rollout']), 'message': MESSAGE}
    yield cfg, state


def idle(_events):
    return ('IDLE', TERMINAL, '', False, '-')


def working(_events):
    return ('WORKING', TERMINAL, '', False, '-')


def no_events(_path):
    return [], 0


# --- (a) placeholder = our input; other text = not ours -------------------------------

def test_a_short_message_as_is():
    assert check.exact_input('› 안녕' + STATUS, '안녕') is True


def test_a_wrapped_long_message():
    half = len(LONG) // 2
    wrapped = '› ' + LONG[:half] + '\n  ' + LONG[half:] + STATUS
    assert check.exact_input(wrapped, LONG) is True


def test_a_placeholder_same_length_is_ours():
    assert check.exact_input(PLACEHOLDER, MESSAGE) is True


@pytest.mark.parametrize('editor', [
    '› [Pasted Content %d chars]' % (len(MESSAGE) - 1),
    '› [Pasted Content %d chars]' % (len(MESSAGE) + 7),
    '› [Pasted Content %d chars] 사람이 덧붙임' % len(MESSAGE),
])
def test_a_other_placeholder_or_mixed_is_not_ours(editor):
    assert check.exact_input(editor + STATUS, MESSAGE) is False


# --- (b) Enter only for our input, never while working -------------------------------

def test_b_placeholder_screen_enters_once_and_receipts(pane):
    cfg, state = pane
    state['screens'] = [PLACEHOLDER]
    result = {}
    assert check.deliver(PANE, cfg, TERMINAL, MESSAGE, no_events, idle, result) == 'NOTIFIED'
    assert state['typed'] == 0 and state['enters'] == 1  # already in the box: submit, don't retype
    assert check.submitted(cfg['rollout'], 0, MESSAGE) is True


def test_b_human_text_no_enter_no_typing(pane):
    cfg, state = pane
    state['screens'] = ['› 사람이 직접 쓴 글' + STATUS]
    result = {}
    assert check.deliver(PANE, cfg, TERMINAL, MESSAGE, no_events, idle, result) == 'DELIVERY_INPUT_CHANGED'
    assert state['typed'] == 0 and state['enters'] == 0


HINT = '› Ask Codex to do anything'


def test_b_empty_box_hint_still_types_and_enters(pane):
    cfg, state = pane
    state['screens'] = [HINT + STATUS, PLACEHOLDER]
    result = {}
    assert check.deliver(PANE, cfg, TERMINAL, MESSAGE, no_events, idle, result) == 'NOTIFIED'
    assert state['typed'] == 1 and state['enters'] == 1


def test_r1_working_round_types_nothing(pane):
    """R1: a WORKING re-round must not type the body (literal input 0) and not move pending."""
    cfg, state = pane
    state['screens'] = ['› ' + STATUS, PLACEHOLDER]
    state['receipt'] = False
    result = {}
    assert check.deliver(PANE, cfg, TERMINAL, MESSAGE, no_events, idle, result) == 'DELIVERY_UNCERTAIN'
    typed, enters, offset = state['typed'], state['enters'], result['pending_offset']
    state['screens'] = [HINT + STATUS]  # 이전 입력은 사라지고 빈 힌트만 남은 재회차
    status = check.deliver(PANE, cfg, TERMINAL, MESSAGE, no_events, working, result)
    assert status == 'DELIVERY_STATE_CHANGED'
    assert state['typed'] == typed and state['enters'] == enters  # 본문 입력 0 · Enter 0
    assert result['pending_terminal'] == TERMINAL and result['pending_offset'] == offset


def test_b_working_state_no_enter(pane):
    cfg, state = pane
    state['screens'] = ['› ' + STATUS, PLACEHOLDER]
    result = {}
    assert check.deliver(PANE, cfg, TERMINAL, MESSAGE, no_events, working, result) == 'DELIVERY_STATE_CHANGED'
    assert state['enters'] == 0


# --- (c) no receipt -> pending only; next round submits without retyping ------------

def test_c1_no_receipt_leaves_pending_only(pane):
    cfg, state = pane
    state['screens'] = ['› ' + STATUS, PLACEHOLDER]
    state['receipt'] = False
    result = {}
    assert check.deliver(PANE, cfg, TERMINAL, MESSAGE, no_events, idle, result) == 'DELIVERY_UNCERTAIN'
    assert 'sent_terminal' not in result
    assert result['pending_terminal'] == TERMINAL and state['typed'] == 1


def test_c2_next_round_enters_without_retyping(pane):
    cfg, state = pane
    state['screens'] = ['› ' + STATUS, PLACEHOLDER]
    state['receipt'] = False
    result = {}
    check.deliver(PANE, cfg, TERMINAL, MESSAGE, no_events, idle, result)
    assert state['typed'] == 1
    state['receipt'] = True
    state['screens'] = [PLACEHOLDER]
    assert check.deliver(PANE, cfg, TERMINAL, MESSAGE, no_events, idle, result) == 'NOTIFIED'
    assert state['typed'] == 1  # no second typing for the same terminal event


def test_c3_late_receipt_finishes_without_enter(pane):
    cfg, state = pane
    state['screens'] = ['› ' + STATUS, PLACEHOLDER]
    state['receipt'] = False
    result = {}
    check.deliver(PANE, cfg, TERMINAL, MESSAGE, no_events, idle, result)
    with state['rollout'].open('a') as stream:
        stream.write(json.dumps({'type': 'response_item', 'payload': {'role': 'user', 'content': [
            {'type': 'input_text', 'text': MESSAGE}]}}) + '\n')
    enters = state['enters']
    state['screens'] = [PLACEHOLDER]
    assert check.deliver(PANE, cfg, TERMINAL, MESSAGE, no_events, idle, result) == 'NOTIFIED'
    assert state['typed'] == 1 and state['enters'] == enters


def test_c4_empty_box_resends_once_only(pane):
    cfg, state = pane
    state['screens'] = ['› ' + STATUS, PLACEHOLDER]
    state['receipt'] = False
    result = {}
    check.deliver(PANE, cfg, TERMINAL, MESSAGE, no_events, idle, result)
    state['screens'] = ['› ' + STATUS, PLACEHOLDER]
    assert check.deliver(PANE, cfg, TERMINAL, MESSAGE, no_events, idle, result) == 'DELIVERY_UNCERTAIN'
    assert state['typed'] == 2  # one resend
    state['screens'] = ['› ' + STATUS]
    assert check.deliver(PANE, cfg, TERMINAL, MESSAGE, no_events, idle, result) == 'DELIVERY_INPUT_CHANGED'
    assert state['typed'] == 2  # never a third typing for the same terminal event


# --- claim order guard --------------------------------------------------------------

def test_sent_terminal_written_only_after_receipt():
    tree = ast.parse(CHECK_PY.read_text(encoding='utf-8'))
    parents = {}
    for node in ast.walk(tree):
        for child in ast.iter_child_nodes(node):
            parents[child] = node
    hits = 0
    for node in ast.walk(tree):
        if not isinstance(node, ast.Assign):
            continue
        if 'sent_terminal' not in ast.unparse(node.targets[0]):
            continue
        if 'terminal' not in ast.unparse(node.value):
            continue
        hits += 1
        chain = []
        child = node
        while child in parents:
            child = parents[child]
            chain.append(child)
        assert any(isinstance(n, ast.If) and 'NOTIFIED' in ast.unparse(n.test) for n in chain), \
            'sent_terminal must be written only inside the NOTIFIED branch'
    assert hits == 1
