"""r1621 fixed (2/2): Pi 상자·영수·전환 계약. Run: python3.11 -m pytest -q <file>."""
import json
import tempfile
from pathlib import Path

import pytest

from test_check_r1621 import (HERE, check, watch, latest, iso, row, append, MESSAGE, SEAT, T0, SEP, TAIL, FOOT,
                              BRIEF, LONG, PANE_EMPTY, PANE_OURS, PANE_HUMAN, PANE_BUSY, PANE_CLIPPED, PANE_OTHER)

SUFFIX_ONLY = SEP + '\n' + TAIL[-200:] + '\n' + SEP  # 상자 전체가 보이는데 꼬리만 같다
PANE_WORKING_OURS = '── ⠋ Working ' + '─' * 60 + '\n' + MESSAGE + '\n' + SEP + '\n~/proj'
assert len(''.join(SUFFIX_ONLY.split())) >= 120  # R2: 가드 제거 변이가 실제로 걸리는 길이


def test_d_pi_receipt_is_our_user_row(watch):  # ⓓ · M2: assistant 행을 영수로 읽으면 빨강
    base, state, _ = watch
    state['echo_on_type'], state['receipt_on_enter'] = T0, T0 + 301
    assert check.check() == 'NOTIFIED'
    assert latest(base)['auto_notified'] is True and state['enters'] == 1


def test_d_pi_receipt_survives_linebreak_loss(watch):  # ⓓ 실측: Pi 는 본문 속 \n 을 보존하지 않는다
    base, state, _ = watch
    state['receipt_on_enter'] = T0 + 301
    assert check.check() == 'NOTIFIED' and latest(base)['sent_terminal'] == iso(T0)


def test_e_pi_busy_and_box(watch, monkeypatch):  # ⓔ · M3: 바쁨 표식 없으면 PANE_BUSY 대신 READY
    monkeypatch.setattr(check, 'ENGINE', 'pi')
    assert check.reason('IDLE', iso(T0 + 1), iso(T0), PANE_BUSY) == 'PANE_BUSY'
    assert check.reason('IDLE', iso(T0 + 1), iso(T0), PANE_OURS) == 'INPUT_PRESENT'
    assert check.reason('IDLE', iso(T0 + 1), iso(T0), PANE_HUMAN) == 'INPUT_PRESENT'
    assert check.reason('IDLE', iso(T0 + 1), iso(T0), PANE_EMPTY) == 'READY'
    assert check.exact_input(PANE_OURS, MESSAGE) is True
    assert check.exact_input(PANE_EMPTY, MESSAGE) is False
    assert check.exact_input(PANE_HUMAN, MESSAGE) is False
    assert check.exact_input(PANE_CLIPPED, LONG) is True  # 잘린 상자 = 글 꼬리 접미사 (긴 글 = BRIEF)
    assert check.exact_input(PANE_OTHER, MESSAGE) is False
    assert check.reason('IDLE', iso(T0 + 1), iso(T0), PANE_OTHER) == 'INPUT_PRESENT'


def test_e_codex_box_still_codex(watch, monkeypatch):
    monkeypatch.setattr(check, 'ENGINE', 'codex')
    assert check.exact_input('› ' + MESSAGE, MESSAGE) is True  # ⓐ: codex 상자 계약 불변
    assert check.reason('IDLE', iso(T0 + 1), iso(T0), 'esc to interrupt') == 'PANE_BUSY'


def test_b1_suffix_only_when_clipped_and_quiet(watch, monkeypatch):  # B1 · M4
    base, state, _ = watch
    monkeypatch.setattr(check, 'ENGINE', 'pi')
    monkeypatch.setattr(check, 'TYPED_AT', T0)
    state['clients'] = ''
    assert check.quiet_since(T0) is True
    assert check.exact_input(PANE_CLIPPED, LONG) is True  # 잘린 상자 ∧ 사람 흔적 0
    state['clients'] = str(int(T0 + 10))  # 우리 입력 뒤 사람 client 입력
    assert check.quiet_since(T0) is False
    assert check.exact_input(PANE_CLIPPED, LONG) is False
    state['clients'] = ''
    assert check.exact_input(SUFFIX_ONLY, LONG) is False  # 상자 전체가 보이면 전체 일치만
    assert check.exact_input(PANE_OURS, MESSAGE) is True


def test_b1_human_activity_after_typing_blocks_enter(watch):  # B1: check 회차 결선 (R1-a: latest.json → check() 경계)
    base, state, _ = watch
    root = Path(tempfile.mkdtemp())
    sub = root / ('b' * max(1, 100 - len(str(root)) - len('/CHECK-BRIEF.md')))  # 경로 100자 = 글자 ≥120 · 바이트 ≤200
    sub.mkdir()
    brief = sub / 'CHECK-BRIEF.md'  # 접미사 가드가 실제로 걸리는 길이의 문구를 만든다
    brief.write_text(BRIEF, encoding='utf-8')
    cfg = json.loads((base / 'config.json').read_text(encoding='utf-8'))
    cfg['brief'] = str(brief)
    (base / 'config.json').write_text(json.dumps(cfg), encoding='utf-8')
    message = check.doorbell_line({'brief': str(brief)})
    clipped = '── ↑ 24 more ' + '─' * 50 + '\n' + message[-130:] + '\n' + SEP + FOOT
    state['screens'] = [clipped, clipped]  # 잘린 상자 = 우리 글 꼬리
    state['clients'] = str(int(T0 + 10))  # typed_at 뒤 사람 client 입력
    (base / 'latest.json').write_text(json.dumps(
        {'pending_terminal': iso(T0), 'pending_offset': 0, 'typed_at': T0,
         'pending_sha': check.digest(message)}), encoding='utf-8')
    assert check.check() == 'DELIVERY_INPUT_CHANGED'
    assert state['typed'] == 0 and state['enters'] == 0


def test_r1_working_pane_never_enters(watch, monkeypatch):  # R1: IDLE journal ∧ Working pane = Enter 0
    base, state, _ = watch
    state['screens'] = [PANE_WORKING_OURS, PANE_WORKING_OURS]
    (base / 'latest.json').write_text(json.dumps(
        {'seat': SEAT, 'pending_terminal': iso(T0), 'pending_offset': 0, 'typed_at': T0,
         'pending_sha': check.digest(MESSAGE)}), encoding='utf-8')  # r1666: seat 칸 = 같은 좌석 (seat 없음 = 대상 바뀜 계약)
    assert check.check() == 'PANE_BUSY'  # pending 갈래
    assert state['typed'] == 0 and state['enters'] == 0
    kept = latest(base)
    assert kept['pending_offset'] == 0 and kept['typed_at'] == T0  # pending 칸 보존 (새 청구 0)
    (base / 'latest.json').unlink()
    state['screens'] = [PANE_WORKING_OURS, PANE_WORKING_OURS]  # 우리 글이 상자에 있고 pending 0
    assert check.check() == 'PANE_BUSY'
    assert state['typed'] == 0 and state['enters'] == 0


def test_f_live_switch_keeps_codex_values():
    if not (HERE / 'config.json').exists():  # r1666: 이 시험은 런타임 폴더 값 대조용 (팩 사본에는 라이브 config 가 없다)
        pytest.skip('런타임 폴더 전용 시험')
    cfg = json.loads((HERE / 'config.json').read_text(encoding='utf-8'))
    if cfg.get('engine') != 'pi':
        pytest.skip('ⓕ 전환 전')
    prior = cfg.get('prior', {})
    assert prior.get('seat') and prior.get('thread_id') and prior.get('rollout')  # 옛 값 보존
    assert cfg['seat'] == SEAT and 'rollout' not in cfg  # Pi 갈래는 경로 고정 0
    old = sorted(HERE.glob('latest.codex-*.json'))
    assert old and json.loads(old[-1].read_text(encoding='utf-8')).get('status')  # 옛 판정 보존
