"""r1666 단계 2: check.py 가 받는 좌석을 명부·도달 파일에서 찾고, 대상이 바뀌면 입력 위치만 비우고, helper 는 LIVE_BIN 을 매 회차 읽는다.
Run: CHECK_PY=<check.py> python3.11 -m pytest -q test_check_r1666.py  (기본값 = 같은 폴더 check.py)
변이: M1 도달 파일 확인 삭제 → test_successor_is_the_target 빨강 · M2 초기화 삭제 → test_target_change_clears_input_position 빨강 · M3 helper 판 고정 → test_helper_comes_from_live_bin_every_round 빨강
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
spec = importlib.util.spec_from_file_location('check_r1666', CHECK_PY)
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)
T0 = datetime(2026, 11, 11, 8, 0, 0, tzinfo=timezone.utc).timestamp()
MESSAGE = check.doorbell_line({'brief': str(HERE / 'CHECK-BRIEF.md')}) if (HERE / 'CHECK-BRIEF.md').exists() else ''


def iso(epoch):
    return datetime.fromtimestamp(epoch, timezone.utc).isoformat(timespec='milliseconds').replace('+00:00', 'Z')


@pytest.fixture
def world(tmp_path, monkeypatch):
    """tmp 명부·도달 파일·LIVE_BIN + 가짜 tmux(기록만) + 주입 시계. 실 좌석·실 launchd·sleep 0."""
    ft, live, brief = tmp_path / 'ft', tmp_path / 'livebin', Path(tempfile.mkdtemp(dir='/tmp')) / 'BRIEF.md'
    (ft / 'state' / 'successor').mkdir(parents=True)
    brief.write_text('[ft20-check 300초] 지침 시험용\n', encoding='utf-8')
    live.mkdir()
    (ft / 'LIVE_BIN').write_text(str(live) + '\n', encoding='utf-8')
    core = tmp_path / 'core.html'
    core.write_text('const stages = [{"items": [["a", false]]}];', encoding='utf-8')
    rollout = tmp_path / 'rollout.jsonl'
    rollout.write_text(json.dumps({'type': 'event_msg', 'timestamp': iso(T0),
                                   'payload': {'type': 'user_message', 'message': 'turn'}}) + '\n',
                       encoding='utf-8')
    state = {'tmux': ['qa#1'], 'typed': 0, 'enters': 0, 'session': [], 'judge': ('IDLE', iso(T0)),
             'live': live, 'rollout': rollout, 'brief': brief, 'ft': ft}
    message_box = []

    def roster(*seats, **replaced):  # 명부 = 좌석 이름 → 행
        rows = {'_version': '1.1.292'}
        for seat in seats:
            rows[seat] = {'role': 'qa', 'agent': 'pi'}
        for seat in replaced.get('replaced', ()):
            rows[seat] = {'role': 'qa', 'agent': 'pi', '_replaced_by': 'qa#9'}
        (ft / 'seats-harness.json').write_text(json.dumps(rows), encoding='utf-8')

    def successor(seat, nxt):
        (ft / 'state' / 'successor' / (seat + '.json')).write_text(
            json.dumps({'successor': nxt}), encoding='utf-8')

    def config(**extra):
        value = {'enabled': True, 'role': 'qa', 'engine': 'codex', 'interval_seconds': 300,
                 'core': str(core), 'brief': str(brief), 'helper': '/pinned/1.1.291/bin', 'rollout': str(rollout),
                 'roster': str(ft / 'seats-harness.json'), 'successor_dir': str(ft / 'state' / 'successor'),
                 'live_bin': str(ft / 'LIVE_BIN')}
        value.update(extra)
        (tmp_path / 'config.json').write_text(json.dumps(value), encoding='utf-8')

    def latest(**value):
        (tmp_path / 'latest.json').write_text(json.dumps(value), encoding='utf-8')

    def fake(args):
        joined = ' '.join(args)
        if 'has-session' in joined:
            seat = args[-1].lstrip('=')
            state['session'].append(seat)
            if seat not in state['tmux']:
                raise subprocess.CalledProcessError(1, args)
            return ''
        if 'list-panes' in joined:
            return '%737|1234\n'
        if 'ft-agent-alive.sh' in joined:
            return 'ALIVE\n'
        if 'list-clients' in joined:
            return ''
        if 'capture-pane' in joined:
            return '› ' + message_box[0]
        if 'send-keys' in joined and '-l' in args:
            state['typed'] += 1
        elif 'send-keys' in joined and args[-1] == 'Enter':
            state['enters'] += 1
            with rollout.open('a', encoding='utf-8') as stream:
                stream.write(json.dumps({'type': 'response_item', 'timestamp': iso(T0 + 301), 'payload': {
                    'role': 'user', 'content': [{'type': 'input_text', 'text': message_box[0]}]}}) + '\n')
        return ''

    codex = types.ModuleType('ft_seat_codex')
    codex.read_events = lambda path: ([], 0)
    codex.judge = lambda events: (*state['judge'], '-', False, '-')
    monkeypatch.setitem(sys.modules, 'ft_seat_codex', codex)
    monkeypatch.setattr(check, 'run', fake)
    monkeypatch.setattr(check, 'BASE', tmp_path)
    monkeypatch.setattr(check, 'FT', ft)
    monkeypatch.setattr(check.time, 'sleep', lambda _seconds: None)
    monkeypatch.setattr(check.time, 'time', lambda: state.get('now', T0 + 300))
    monkeypatch.setattr(check, 'DOORBELL', '[ft20-check 300초] 지침 = %s sha %s · 그 형식으로 점검')
    message_box.append(check.doorbell_line({'brief': str(brief)}))
    state.update(roster=roster, successor=successor, config=config, latest=latest)
    return tmp_path, state


def saved(base):
    return json.loads((base / 'latest.json').read_text(encoding='utf-8'))


def test_target_comes_from_roster_not_a_fixed_seat(world):  # ⓔ
    base, state = world
    state['roster']('qa#1')
    state['config'](seat='byz-old-fixed#0')
    check.check()
    assert 'qa#1' in state['session'] and saved(base)['seat'] == 'qa#1'


def test_successor_is_the_target(world):  # ⓔ · M1: 도달 파일 확인 삭제 = 여기서 빨강
    base, state = world
    state['roster']('qa#1', 'qa#2')  # 명부 갱신 전 (둘 다 현역) · 도달 파일이 후계를 가리킨다
    state['successor']('qa#1', 'qa#2')
    state['tmux'] = ['qa#1', 'qa#2']
    state['config']()
    check.check()
    assert saved(base).get('seat') == 'qa#2'


def test_missing_target_sends_nothing_with_one_error_line(world):  # ⓔ: 현역 tmux 없음 = 송신 0 + error 1줄
    base, state = world
    state['tmux'] = []
    state['roster']('qa#1')
    state['config']()
    assert check.check() == 'TARGET_NOT_RUNNING'  # RuntimeError 0
    assert state['typed'] == 0 and state['enters'] == 0
    assert json.loads((base / 'error.json').read_text(encoding='utf-8'))['status'] == 'TARGET_NOT_RUNNING'


def test_two_live_seats_is_ambiguous(world):  # ⓔ: 한쪽을 임의로 고르지 않는다
    base, state = world
    state['roster']('qa#1', 'qa#2')
    state['config']()
    assert check.check() == 'TARGET_AMBIGUOUS' and state['typed'] == 0


def test_target_change_clears_input_position(world):  # ⓕ · M2: 초기화 삭제 = 여기서 빨강
    base, state = world
    state['roster']('qa#1')
    state['config']()
    state['latest'](seat='qa#0', sent_terminal=iso(T0), pending_offset=7, pending_sha='x', events={'kept': True})
    state['now'] = T0 + 10  # 유휴 300초 전 = 송신 0 (입력 위치를 덮어쓰지 않는다)
    assert check.check() == 'IDLE_DEBOUNCE'
    after = saved(base)
    assert after['seat'] == 'qa#1'
    assert after['sent_terminal'] is None and after['pending_offset'] is None and after['pending_sha'] is None


def test_same_target_keeps_input_position(world):  # ⓕ 반대쪽: 같은 대상이면 이월
    base, state = world
    state['roster']('qa#1')
    state['config']()
    state['latest'](seat='qa#1', sent_terminal=iso(T0), pending_offset=7, pending_sha='x')
    state['now'] = T0 + 10
    assert check.check() == 'IDLE_DEBOUNCE'
    after = saved(base)
    assert after['sent_terminal'] == iso(T0) and after['pending_offset'] == 7 and after['pending_sha'] == 'x'


def test_helper_comes_from_live_bin_every_round(world):  # ⓖ · M3: 판 고정 = 여기서 빨강
    base, state = world
    state['roster']('qa#1')
    state['config']()
    check.check()
    assert sys.path[0] == str(state['live'])
    second = state['live'].parent / 'livebin-2'
    second.mkdir()
    (state['ft'] / 'LIVE_BIN').write_text(str(second) + '\n', encoding='utf-8')
    check.check()
    assert sys.path[0] == str(second)


def test_idle_debounce_stays_300_seconds(world):  # ⓗ: r1605 문턱 불변
    base, state = world
    state['roster']('qa#1')
    state['config']()
    state['now'] = T0 + 299
    assert check.check() == 'IDLE_DEBOUNCE' and state['typed'] == 0
    state['now'] = T0 + 300
    assert check.check() != 'IDLE_DEBOUNCE'


def test_error_round_keeps_the_seat_so_next_round_resets(world):  # DA 단계 2 R1① 재현
    base, state = world
    state['roster']('qa#1')
    state['config']()
    state['latest'](seat='qa#0', sent_terminal=iso(T0), pending_offset=7, pending_sha='x')
    state['tmux'] = []  # 1회차 = 대상 tmux 없음 (송신 0 · error 1줄)
    assert check.check() == 'TARGET_NOT_RUNNING'
    assert saved(base).get('seat')  # 저장에서 seat 가 사라지면 다음 회차가 대상을 못 알아본다
    state['tmux'] = ['qa#1']  # 2회차 = 대상 살아남 · 유휴 문턱 전 (송신 0 이어도 상태는 정리된다)
    state['now'] = T0 + 10
    check.check()
    after = saved(base)
    assert after['seat'] == 'qa#1'
    assert after['pending_offset'] is None and after['pending_sha'] is None and after['sent_terminal'] is None


def test_max_delay_sends_even_when_the_seat_is_never_idle(world):  # DA 단계 2 R1② 재현 (오빠 «왜 스케줄이 없어»)
    base, state = world
    state['roster']('qa#1')
    state['config']()
    turn = iso(T0)
    state['latest'](seat='qa#1', terminal=turn, first_seen_at=T0 - 601, sent_terminal=iso(T0 - 900))
    state['now'] = T0 + 10  # 유휴 10초 = 문턱 미달이지만 «처음 본 뒤 611초» = 상한(600초) 초과
    assert check.check() != 'IDLE_DEBOUNCE' and state['enters'] + state['typed'] >= 1
    assert saved(base).get('sent_at')
    state['latest'](seat='qa#1', terminal=turn, first_seen_at=T0 - 100)  # 상한 안 = 종전 디바운스 그대로
    state['now'] = T0 + 10
    assert check.check() == 'IDLE_DEBOUNCE' and state['enters'] == 1


def test_legacy_latest_without_seat_counts_as_target_change(world):  # DA 단계 2 R2①
    base, state = world
    state['roster']('qa#1')
    state['config']()
    state['latest'](sent_terminal=iso(T0), pending_offset=7, pending_sha='x')  # 구판 = seat 칸 없음
    state['now'] = T0 + 10
    check.check()
    after = saved(base)
    assert after['seat'] == 'qa#1'
    assert after['pending_offset'] is None and after['pending_sha'] is None and after['sent_terminal'] is None


def test_first_seen_survives_rounds_before_the_first_send(world):  # DA 단계 2 R2②
    base, state = world
    state['roster']('qa#1')
    state['config']()
    # 좌석은 계속 깨서 유휴가 300초를 못 넘는다 (5분 점검·쪽지). 회차마다 rollout 끝 시각이 새로 붙는다.
    for step in (0, 120, 240, 360, 480, 600):
        state['now'] = T0 + step
        with state['rollout'].open('a', encoding='utf-8') as stream:
            stream.write(json.dumps({'type': 'event_msg', 'timestamp': iso(T0 + step),
                                     'payload': {'type': 'user_message', 'message': 'wake %d' % step}}) + '\n')
        status = check.check()
    assert status != 'IDLE_DEBOUNCE' and state['enters'] + state['typed'] >= 1  # 600초 상한이면 보낸다
    assert saved(base)['first_seen_at'] <= T0 + 0.5
