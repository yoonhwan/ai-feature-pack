"""r1625: 지침 전문은 CHECK-BRIEF.md · 입력창엔 경로+sha 1줄(doorbell). Run: python3.11 -m pytest -q <file>."""
import hashlib
import json
import re
import tempfile
from pathlib import Path

from short_brief import SHORT_BRIEF  # r1666: 짧은 /tmp 지침 사본

from test_check_r1621 import (HERE, check, watch, latest, iso, T0, BRIEF, LONG, MESSAGE,
                              PANE_CLIPPED, PANE_OURS)

LIVE_SHA = '79e03f9d41b85d57f164b552113acf167fe34a05d3a71f5e6cd4b1e2f51371a2'  # r1625 이행 당시 값(기록용 · 단언 0)
LIVE_BYTES = 3194  # r1625 이행 당시 값(기록용 · 단언 0) — 라이브 message = 1416자
DOORBELL_MAX = check.DOORBELL_MAX_BYTES  # r1673: 꼴 불변식은 check.py 정본 상한(200)을 그대로 쓴다
DOORBELL_RE = re.compile(r'^\[ft20-check 300초\] 지침 = (/.+) sha ([0-9a-f]{12}) · 그 형식으로 점검$')
BRIEF_PATH = SHORT_BRIEF  # r1666: 깊은 워크트리 경로에서 doorbell 200바이트 상한을 피한다


def sha12(text):
    return hashlib.sha256(text.encode('utf-8')).hexdigest()[:12]


def spy(watch, monkeypatch):
    """가짜 tmux 위에 «무엇을 입력했나» 만 덧기록한다 (실 pane·실 launchd 0)."""
    base, state, jsonl = watch
    typed = []
    inner = check.run

    def record(args):
        if 'send-keys' in args and '-l' in args:
            typed.append(args[-1])
        return inner(args)

    monkeypatch.setattr(check, 'run', record)
    return base, state, typed


def point(base, brief):  # config 의 brief 칸만 바꾼다
    cfg = json.loads((base / 'config.json').read_text(encoding='utf-8'))
    cfg['brief'] = str(brief)
    (base / 'config.json').write_text(json.dumps(cfg), encoding='utf-8')


def short_brief(text):  # 짧은 격리 경로 — 경로 길이가 제품 상한 200B 를 먹지 않게
    path = Path(tempfile.mkdtemp()) / 'CHECK-BRIEF.md'
    path.write_text(text, encoding='utf-8')
    return path


def test_a_doorbell_is_one_short_line():  # ⓐ
    line = check.doorbell_line({'brief': str(BRIEF_PATH)})
    assert DOORBELL_RE.match(line), line
    assert DOORBELL_RE.match(line).group(1) == str(BRIEF_PATH)  # 절대 경로 그대로
    assert DOORBELL_RE.match(line).group(2) == sha12(BRIEF)
    assert '\n' not in line and len(line.encode('utf-8')) <= 200


def test_a_round_types_only_the_doorbell(watch, monkeypatch):  # ⓐ · M2: brief 전문을 보내면 여기서 빨강
    base, state, typed = spy(watch, monkeypatch)
    state['receipt_on_enter'] = T0 + 301
    assert check.check() == 'NOTIFIED'
    assert typed == [MESSAGE] and len(typed[0].encode('utf-8')) <= DOORBELL_MAX


def brief_ok(path):  # ⓑ 지침 꼴: 비어 있지 않음 ∧ UTF-8 ∧ doorbell 1줄 ≤ 상한 ∧ 지침 > doorbell×10
    try:
        text = path.read_text(encoding='utf-8')  # UTF-8 이 아니면 지침으로 못 쓴다
    except UnicodeDecodeError:
        return False
    line = check.doorbell_line({'brief': str(path)})
    body, bell = len(text.encode('utf-8')), len(line.encode('utf-8'))
    return bool(text.strip()) and '\n' not in line and bell <= DOORBELL_MAX and body > bell * 10


def test_bf_brief_shape_and_size():  # ⓑ·ⓕ 바이트 지문 단언 0 — 내용이 아니라 꼴만 본다(r1673)
    assert brief_ok(SHORT_BRIEF)  # 지금 지침 = 통과 · ⓕ 크기 뜻(지침 ≫ doorbell) 유지


def test_b_qa_edit_passes_empty_and_tiny_fail():  # ⓑ QA 개정 견딤 · 빈 파일·큰 doorbell 거절
    assert brief_ok(short_brief(BRIEF + '한 줄 추가'))  # 한 글자 바뀐 사본도 통과
    assert not brief_ok(short_brief(''))  # 빈 파일 = FAIL
    assert not brief_ok(short_brief(' ' * 5000))  # M1: «비어 있지 않음» 을 지우면 여기서 빨강
    assert not brief_ok(short_brief('짧은 지침'))  # M2: «× 10» 을 지우면 여기서 빨강
    non_utf8 = short_brief('가')  # UTF-8 아님 = 지침 아님
    non_utf8.write_bytes(b'\xff\xfe ok')
    assert not brief_ok(non_utf8)


def test_c_missing_brief_sends_nothing(watch, monkeypatch):  # ⓒ
    base, state, typed = spy(watch, monkeypatch)
    point(base, base / 'no-such-brief.md')
    assert check.check() == 'BRIEF_UNUSABLE'
    assert typed == [] and state['typed'] == 0 and state['enters'] == 0
    error = json.loads((base / 'error.json').read_text(encoding='utf-8'))
    assert error['status'] == 'BRIEF_UNUSABLE' and 'no-such-brief' in error['error']


def test_c_over_cap_sends_nothing(watch, monkeypatch, tmp_path):  # ⓒ · M1: 상한 검사 제거 = 여기서 빨강
    base, state, typed = spy(watch, monkeypatch)
    deep = tmp_path / ('d' * 100) / ('e' * 100) / 'CHECK-BRIEF.md'  # 경로만으로 200바이트를 넘긴다
    deep.parent.mkdir(parents=True)
    deep.write_text(BRIEF, encoding='utf-8')
    point(base, deep)
    assert check.check() == 'BRIEF_UNUSABLE'
    assert typed == [] and state['typed'] == 0 and state['enters'] == 0
    error = json.loads((base / 'error.json').read_text(encoding='utf-8'))
    assert 'bytes (max 200)' in error['error']  # 잘라 보내지 않고 크기를 그대로 적는다


def test_d_brief_change_changes_the_sha_part():  # ⓓ
    changed = short_brief(BRIEF + '한 줄 추가')  # 제품 상한 200B 그대로 (경로 길이 우회 금지)
    before = DOORBELL_RE.match(check.doorbell_line({'brief': str(BRIEF_PATH)}))
    after = DOORBELL_RE.match(check.doorbell_line({'brief': str(changed)}))
    assert before.group(2) == sha12(BRIEF) and after.group(2) == sha12(changed.read_text(encoding='utf-8'))
    assert before.group(2) != after.group(2)  # 본문이 바뀌면 옛 문구를 «옛 글» 로 판정한다


def test_e_receipt_needs_the_whole_doorbell(watch):  # ⓔ 꼬리 접미사 예외 없이 전체 일치
    base, state, _ = watch
    state['receipt_on_enter'] = T0 + 301
    assert check.check() == 'NOTIFIED'
    record = latest(base)
    assert record['status'] == 'NOTIFIED' and record['auto_notified'] is True
    assert check.exact_input(PANE_OURS, MESSAGE) is True  # 상자 글 = doorbell 전체
    assert check.exact_input(PANE_CLIPPED, MESSAGE) is False  # 잘린 긴 글 꼬리 = 우리 글 아님
    assert check.exact_input(PANE_CLIPPED, LONG) is True  # 긴 글 축은 그대로 (BRIEF)


def test_b1_long_text_guard_through_deliver(watch, monkeypatch):  # R1-a: 긴 글 B1 가드는 deliver 로 따로
    base, state, jsonl = watch
    state['screens'] = [PANE_CLIPPED]  # 잘린 상자 = BRIEF 꼬리
    state['clients'] = str(int(T0 + 10))  # typed_at 뒤 사람 client 입력
    pending = {'pending_terminal': iso(T0), 'pending_offset': 0, 'typed_at': T0, 'pending_sha': check.digest(LONG)}
    idle = lambda _events: ('IDLE', iso(T0), '-', False, '-')
    monkeypatch.setattr(check, 'ENGINE', 'pi')
    monkeypatch.setattr(check, 'TYPED_AT', T0)
    assert check.deliver('%737', {'rollout': str(jsonl)}, iso(T0), LONG,
                         lambda _p: ([], 0), idle, pending) == 'DELIVERY_INPUT_CHANGED'
    assert state['typed'] == 0 and state['enters'] == 0
