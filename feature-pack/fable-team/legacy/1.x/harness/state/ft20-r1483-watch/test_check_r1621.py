"""r1621 fixed: ft20 300초 점검 대상이 codex QA → Pi 후계로 옮겨도 같은 계약. Run: python3.11 -m pytest -q <file>."""
import importlib.util, json, os, sys, types
from datetime import datetime, timezone
from pathlib import Path

from short_brief import SHORT_BRIEF  # r1666: 짧은 /tmp 지침 사본
import pytest

HERE = Path(__file__).resolve().parent
CHECK_PY = Path(os.environ.get('CHECK_PY') or HERE / 'check.py')
HELPER = Path('/Users/yoonhwan/.claude/fable-team/live/1.1.291/bin')


def load():
    spec = importlib.util.spec_from_file_location('check_r1621', CHECK_PY)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


check = load()
BRIEF = LONG = (HERE / 'CHECK-BRIEF.md').read_text(encoding='utf-8')  # r1625: 지침 전문 = 파일 (긴 글 = BRIEF)
MESSAGE = check.doorbell_line({'brief': str(SHORT_BRIEF)})  # r1625: 보내는 글 = doorbell 1줄
SEAT, T0 = 'byz-harness-qa-ft20-pi#0', datetime(2026, 11, 11, 8, 0, 0, tzinfo=timezone.utc).timestamp()
SEP, TAIL = '─' * 80, LONG[-420:]  # 실측: 80x24 pane 에서 1146자 본문은 상자를 넘겨 바닥 경계선만 남는다
FOOT = '\n~/proj\n↑126 ↓31k R3.8M W209k CH99.5% 12.0%/1.0M  opus'  # r1836: 실제 Pi 바닥 = cwd 줄 + 상태 줄
PANE_EMPTY, PANE_OURS = SEP + '\n\n' + SEP + FOOT, SEP + '\n' + MESSAGE + '\n' + SEP + FOOT
PANE_HUMAN = SEP + '\n사람이 쓴 글\n' + SEP + FOOT
PANE_BUSY = SEP + '\n\n' + SEP + '\n── ⠦ Working ' + '─' * 60
PANE_CLIPPED = '── ↑ 24 more ' + '─' * 50 + '\n' + '\n'.join(
    TAIL[i:i + 70] for i in range(0, len(TAIL), 70)) + '\n' + SEP + FOOT
PANE_OTHER = '── ↑ 24 more ' + '─' * 50 + '\n사람이 쓴 다른 글\n' + SEP + FOOT
CODEX_HINT = '› Ask Codex to do anything'
sys.path.insert(0, str(HELPER))
sys.path.insert(0, str(HERE))
if os.environ.get('PI_SEAT_PY'):  # 변이 M2·M3: 대체 Pi 판독기를 그 이름으로 주입
    spec = importlib.util.spec_from_file_location('ft20_pi_seat', os.environ['PI_SEAT_PY'])
    sys.modules['ft20_pi_seat'] = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(sys.modules['ft20_pi_seat'])


def iso(epoch):
    return datetime.fromtimestamp(epoch, timezone.utc).isoformat(timespec='milliseconds').replace('+00:00', 'Z')


def row(style, epoch, role, text, stop=None):
    if style != 'pi':
        return {'type': 'response_item', 'timestamp': iso(epoch), 'payload': {
            'role': role, 'content': [{'type': 'input_text', 'text': text}]}}
    payload = {'role': role, 'content': [{'type': 'text', 'text': text}]}
    if stop:
        payload['stopReason'] = stop
    return {'type': 'message', 'timestamp': iso(epoch), 'message': payload}


def append(path, record):
    with path.open('a', encoding='utf-8') as stream:
        stream.write(json.dumps(record, ensure_ascii=False) + '\n')


@pytest.fixture
def watch(tmp_path, monkeypatch):
    """고정 Pi 세션 jsonl + 가짜 tmux(기록만) + 주입 시계. 실 pane·실 launchd·sleep 0."""
    jsonl = tmp_path / 'pi.jsonl'
    (tmp_path / 'core.html').write_text('const stages = [{"items": [["a", false]]}];')
    state = {'style': 'pi', 'screens': [PANE_EMPTY, PANE_EMPTY, PANE_OURS], 'typed': 0, 'enters': 0,
             'clients': '', 'locate': [], 'echo_on_type': None, 'receipt_on_enter': None, 'paste_style': True,
             'judge': ('IDLE', iso(T0)), 'ambiguous': False,
             'prior': {'seat': 'old-seat#0', 'thread_id': 'tid', 'rollout': '/old/rollout.jsonl'}}

    def seed(style='pi', stop='end_turn'):
        state['style'] = style
        jsonl.write_text('')
        if style == 'pi':
            append(jsonl, {'type': 'session', 'id': 'sid', 'cwd': str(tmp_path)})
            append(jsonl, {'type': 'session_info', 'name': SEAT})
        append(jsonl, row(style, T0 - 10, 'user', 'turn start'))
        append(jsonl, row(style, T0, 'assistant', 'done', stop))

    def cfg(engine=True, rollout=False):
        value = {'enabled': True, 'seat': SEAT, 'helper': str(HELPER), 'core': str(tmp_path / 'core.html'),
                 'interval_seconds': 300, 'brief': str(SHORT_BRIEF), 'prior': state['prior']}  # r1625 ②
        if engine:
            value['engine'] = 'pi'
        if rollout:
            value['rollout'] = str(jsonl)
        (tmp_path / 'config.json').write_text(json.dumps(value, ensure_ascii=False), encoding='utf-8')

    def locate(seat, tmux=None):  # ⓑ: 좌석 이름으로만 찾는다 (경로 고정 0)
        state['locate'].append(seat)
        if state['ambiguous']:
            raise ValueError('Pi session 후보 2개')
        return (str(jsonl), {'id': 'sid'}, '1234', str(tmp_path))

    def fake(args):
        joined = ' '.join(args)
        if 'list-panes' in joined:
            return '%737|1234\n'
        if 'ft-agent-alive.sh' in joined:
            return 'ALIVE\n'
        if 'list-clients' in joined:
            return state['clients']
        if 'capture-pane' in joined:
            return state['screens'].pop(0) if len(state['screens']) > 1 else state['screens'][0]
        if 'send-keys' in joined and '-l' in args:  # 같은 글의 assistant 행 = 영수 아님 (M2)
            state['typed'] += 1
            if state['echo_on_type'] is not None:
                append(jsonl, row(state['style'], state['echo_on_type'], 'assistant', args[-1], 'end_turn'))
        elif 'send-keys' in joined and args[-1] == 'Enter':  # 실측: Pi 영수는 본문 속 \n 을 떨어뜨린다
            state['enters'] += 1
            if state['receipt_on_enter'] is not None:
                text = MESSAGE.replace('\n', '') if state['paste_style'] else MESSAGE
                append(jsonl, row(state['style'], state['receipt_on_enter'], 'user', text))
        return ''

    seed()
    cfg()
    state.update(seed=seed, cfg=cfg)
    pi = types.ModuleType('ft_seat_pi')
    pi.locate = locate
    codex = types.ModuleType('ft_seat_codex')
    codex.read_events = lambda path: ([], 0)
    codex.judge = lambda events: (*state['judge'], '-', False, '-')
    monkeypatch.setitem(sys.modules, 'ft_seat_pi', pi)
    monkeypatch.setitem(sys.modules, 'ft_seat_codex', codex)
    monkeypatch.setattr(check, 'run', fake)
    monkeypatch.setattr(check, 'BASE', tmp_path)
    monkeypatch.setattr(check.time, 'sleep', lambda _seconds: None)
    monkeypatch.setattr(check.time, 'time', lambda: T0 + 300)
    yield tmp_path, state, jsonl


def latest(base):
    return json.loads((base / 'latest.json').read_text(encoding='utf-8'))


def test_a_codex_engine_unchanged(watch):  # ⓐ engine 없음 = 종전 codex 경로 그대로
    base, state, _ = watch
    state['seed']('codex', 'end_turn')
    state['cfg'](engine=False, rollout=True)
    state['screens'] = [CODEX_HINT, CODEX_HINT, '› ' + MESSAGE]
    state['paste_style'], state['receipt_on_enter'] = False, T0 + 301
    assert check.check() == 'NOTIFIED'
    assert state['locate'] == [] and state['typed'] == 1 and state['enters'] == 1


def test_b_pi_round_binds_by_locate(watch):  # ⓑ · M1: 갈래 없으면 locate 0 → 여기서 빨강
    base, state, _ = watch
    state['receipt_on_enter'] = T0 + 301
    assert check.check() == 'NOTIFIED'
    assert state['locate'] == [SEAT] and latest(base)['sent_terminal'] == iso(T0)


def test_b_two_candidates_is_an_error(watch):  # ⓑ: 후보 ≠1 = 판정 불가 (추측 0)
    base, state, _ = watch
    state['ambiguous'] = True
    with pytest.raises(ValueError):
        check.check()
    assert state['typed'] == 0


def test_c_pi_state_needs_termination(watch):  # ⓒ: 종료 증거 없음 = IDLE 아님 · enqueue = PENDING
    base, state, jsonl = watch
    state['seed']('pi', None)
    assert check.check() == 'UNKNOWN' and state['typed'] == 0 and state['enters'] == 0
    state['seed']('pi', 'end_turn')
    append(jsonl, {'type': 'queue-operation', 'operation': 'enqueue', 'timestamp': iso(T0 + 1)})
    assert check.check() == 'PENDING' and state['enters'] == 0
