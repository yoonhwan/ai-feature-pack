#!/usr/bin/env python3
"""Synthetic-only verification of tour 14. Never touches ~/.local/share/airag or real keys.

Run: feature-pack/rag/.venv/bin/python .fable-team/bin/tour/verify_14_isolated.py
Checks: normal 7-cell tour · forged receipt (B1) · stale/foreign receipt (M1) · log failures leave core intact (M3).
"""
import builtins
import contextlib
from datetime import datetime, timedelta, timezone
import importlib.util
import io
import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import sys
import tempfile
import threading
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path[:0] = [str(HERE), str(ROOT / 'feature-pack/rag-consumer/tests'),
                str(ROOT / 'feature-pack/rag-consumer/src'), str(ROOT / 'feature-pack/rag/src')]
NOW = datetime(2026, 9, 27, 4, tzinfo=timezone.utc)
CONTENT = ('I prefer concise answers, always cite sources, use dark mode, '
           'the fix worked, and the retry also worked.')
QUOTES = ('prefer concise answers', 'always cite sources', 'use dark mode', 'fix worked', 'retry also worked')

import first_collection as collection  # noqa: E402  (tour modules; operational runtime is replaced below)
import test_runtime as t  # noqa: E402
from airag_consumer.runtime import AIRAGRuntime, RuntimeConfig, RuntimeHooks  # noqa: E402


def synthetic_runtime(config, clock=None):
    return AIRAGRuntime(RuntimeConfig.load(config), environ=t.environment(), clock=clock or t.Clock(NOW),
                        hooks=RuntimeHooks(bridge=t.SyntheticBridge(), memory_extractor=Extractor()))


class Extractor:
    synthetic_test_double = True

    def __call__(self, request):
        m = request.messages[0]

        def c(kind, text, quote, proof=False):
            return {'kind': kind, 'text': text, 'anchor_ids': [m.anchor_id],
                    'proof_anchor_ids': [m.anchor_id] if proof else [],
                    'supporting_quotes': [{'anchor_id': m.anchor_id, 'quote': quote}], 'conflict': False}
        return {'candidates': [c('preference', 'Prefer concise answers', QUOTES[0]),
                               c('instruction_quote', 'Always cite sources', QUOTES[1]),
                               c('preference', 'Use dark mode', QUOTES[2]),
                               c('verified_solution', 'The fix worked', QUOTES[3], True),
                               c('verified_solution', 'The retry worked', QUOTES[4], True)]}


if os.environ.get('ISO14_HELPER_MODE') == '1':
    # Subprocess entry used by the notebook cells: the real helper against the synthetic runtime only.
    collection.runtime = lambda: synthetic_runtime(os.environ['ISO14_CONFIG'])
    runpy.run_path(str(HERE / 'memory_confirmation.py'), run_name='__main__')
    raise SystemExit(0)

import memory_confirmation as helper  # noqa: E402
import notebook  # noqa: E402

BASE = Path(tempfile.mkdtemp(prefix='iso14-', dir=os.path.realpath(tempfile.gettempdir())))
RESULTS = []


def check(name, condition, detail=''):
    RESULTS.append((name, bool(condition)))
    print(('PASS ' if condition else 'FAIL ') + name + (f' · {detail}' if detail else ''))
    if not condition and os.environ.get('ISO14_KEEP_GOING') != '1':
        raise SystemExit(f'FAILED: {name}')


def expect_error(name, code, call):
    try:
        call()
    except Exception as error:
        check(name, str(error) == code, f'{type(error).__name__} {error}')
        return
    check(name, False, 'no exception')


def make(label):
    case = BASE / label
    case.mkdir()
    item = t.project(case, now=NOW, content=CONTENT, memory=True)
    clock = t.Clock(NOW)
    app = synthetic_runtime(item['config'], clock)
    app.init()
    app.run_once(explicit_save=True)
    return item, app, clock


def first_id(app, state='awaiting_confirmation'):
    return app.memory_candidates(state)['candidates'][0]['candidate_id']


def visible(app):
    return app.status()['visible_memories']


# ---- B1: a forged manifest + receipt must not open the gate
item, app, clock = make('forged')
forged = app.config.backup_root / 'airag-set-forged'
forged.mkdir()
(forged / 'manifest.json').write_text(json.dumps({'owner': 'airag-operations-v1', 'state': 'verified'}), encoding='utf-8')
helper.write(helper.receipt_path(app), {'backup_id': forged.name, 'before': {}, 'run': 'run-1', 'at': clock().isoformat()})
check('B1 forged id appears in status verified list', forged.name in app.status()['verified_backup_ids'])
expect_error('B1 forged receipt rejected', 'BACKUP_VERIFICATION_FAILED',
             lambda: helper.work('decide', app=app, approve=first_id(app), run='run-1'))
check('B1 core unchanged', visible(app) == 0)

# ---- M1: stale, foreign-run and run-less receipts are rejected; a fresh one passes
item, app, clock = make('stale')
helper.work('backup', app=app, run='run-A')
expect_error('M1 run-less decide rejected', 'TOUR_RUN_REQUIRED', lambda: helper.work('decide', app=app, approve=first_id(app)))
expect_error('M1 other-run receipt rejected', 'BACKUP_NOT_FROM_THIS_TOUR_RUN',
             lambda: helper.work('decide', app=app, approve=first_id(app), run='run-B'))
clock.value += timedelta(days=2)
expect_error('M1 two-day-old receipt rejected', 'BACKUP_RECEIPT_STALE',
             lambda: helper.work('decide', app=app, approve=first_id(app), run='run-A'))
check('M1 core unchanged', visible(app) == 0)
helper.work('backup', app=app, run='run-A')
done = helper.work('decide', app=app, approve=first_id(app), run='run-A')
check('M1 fresh receipt of this run passes', done['results'][0]['state'] == 'materialized' and visible(app) == 1)

# ---- M3: decision-log failures never leave an applied-but-unrecorded decision
item, app, clock = make('log')
helper.work('backup', app=app, run='run-L')
helper.log_path(app).write_text('{ malformed log', encoding='utf-8')
try:
    helper.work('decide', app=app, approve=first_id(app), run='run-L')
    check('M3 malformed log aborts', False)
except Exception as error:
    check('M3 malformed log aborts', True, type(error).__name__)
check('M3 malformed log: core unchanged', visible(app) == 0)
helper.log_path(app).write_text('[]', encoding='utf-8')
with patch.object(helper, 'write', side_effect=OSError('synthetic write failure')):
    try:
        helper.work('decide', app=app, verify=first_id(app, 'unverified'), run='run-L')
        check('M3 intent write failure aborts', False)
    except OSError:
        check('M3 intent write failure aborts', True)
check('M3 intent write failure: core unchanged', visible(app) == 0)
real_write = helper.write
calls = []


def fail_second(path, data):
    calls.append(1)
    if len(calls) == 2:
        raise OSError('synthetic finalize failure')
    return real_write(path, data)


with patch.object(helper, 'write', side_effect=fail_second):
    out = helper.work('decide', app=app, verify=first_id(app, 'unverified'), run='run-L')
logged = json.loads(helper.log_path(app).read_text())
check('M3 finalize failure is reported, not raised', out['log_complete'] is False and out['results'][0]['state'] == 'materialized')
check('M3 intent stays on record after finalize failure',
      logged and logged[-1]['status'] == 'pending' and logged[-1]['intent'][0]['action'] == 'verify')
text = helper.log_path(app).read_text() + helper.receipt_path(app).read_text()
check('M3 log and receipt carry no memory body or quote', not any(q in text for q in QUOTES))

# ---- R5-m1: a run-less backup is refused before it creates anything
item, app, clock = make('norun')
before = app.status()['backup_count']
expect_error('R5-m1 run-less backup refused', 'TOUR_RUN_REQUIRED', lambda: helper.work('backup', app=app))
check('R5-m1 refusal created no backup', app.status()['backup_count'] == before)

# ---- R5-M2: rewriting the receipt's at/run cannot revive a 48-hour-old real backup
item, app, clock = make('retag')
helper.work('backup', app=app, run='run-T')
clock.value += timedelta(days=2)
receipt = json.loads(helper.receipt_path(app).read_text())
helper.write(helper.receipt_path(app), {**receipt, 'run': 'run-T2', 'at': clock().isoformat()})
check('R5-M2 old backup still passes real verification', app.verify_backup(receipt['backup_id'])['verified'] is True)
expect_error('R5-M2 rewritten receipt cannot reopen decisions', 'BACKUP_RECEIPT_STALE',
             lambda: helper.work('decide', app=app, approve=first_id(app), run='run-T2'))
check('R5-M2 core unchanged', visible(app) == 0)

# ---- R5-M1: overlapping decide calls both keep their intent and result in the log
item, app, clock = make('overlap')
helper.work('backup', app=app, run='run-O')
pending = [row['candidate_id'] for row in app.memory_candidates('awaiting_confirmation')['candidates']][:2]
original_write, first_write, b_done, outcome = helper.write, threading.Event(), threading.Event(), {}


def paused_write(path, data):
    if threading.current_thread().name == 'A' and not first_write.is_set():
        first_write.set()
        b_done.wait(1.5)  # lets B finish first unless the helper serializes the two calls
    return original_write(path, data)


def decide_call(name, candidate_id):
    outcome[name] = helper.work('decide', app=app, approve=candidate_id, run='run-O')
    if name == 'B':
        b_done.set()


with patch.object(helper, 'write', side_effect=paused_write):
    thread_a = threading.Thread(target=decide_call, args=('A', pending[0]), name='A')
    thread_a.start()
    first_write.wait(5)
    thread_b = threading.Thread(target=decide_call, args=('B', pending[1]), name='B')
    thread_b.start()
    thread_a.join(20)
    thread_b.join(20)
entries = json.loads(helper.log_path(app).read_text())
recorded = {row['candidate_id'] for entry in entries for row in entry.get('results', [])}
check('R5-M1 both overlapping decisions applied', set(outcome) == {'A', 'B'} and visible(app) == 2)
check('R5-M1 both decisions stay in the log', recorded == set(pending) and all(e['status'] == 'done' for e in entries),
      f'{len(entries)} entries')

# ---- normal tour: all 7 cells through the real notebook runner, helper in a synthetic subprocess
item, app, clock = make('tour')
os.environ['ISO14_CONFIG'] = str(item['config'])
os.environ['ISO14_HELPER_MODE'] = '1'
os.environ['PYTHONPATH'] = os.pathsep.join(sys.path[1:5])
os.environ.update({k: v for k, v in t.environment().items() if k != 'PATH'})
notebook.STATE = BASE / 'tour-state.json'
spec = importlib.util.spec_from_file_location('tour14', HERE / '14-memory-confirmation.py')
tour = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tour)
tour.PYTHON, tour.HELPER = sys.executable, str(Path(__file__).resolve())
answers = iter(['', '전체실행', '', '', '', '9', '1,2', '3', '재실행', '', '', '', '1', '2', '', '', '', '', ''])


def scripted(prompt=''):
    print(prompt, end='')
    value = next(answers)
    print(repr(value))
    return value


builtins.input = scripted
buffer = io.StringIO()
with contextlib.redirect_stdout(buffer):
    code = notebook.run_notebook('14-memory-confirmation', 'isolated', tour.build_cells(),
                                 context={'env': {**os.environ, 'AIRAG_TOUR14_RUN': 'iso-run'}})
output = buffer.getvalue()
(BASE / 'tour_output.txt').write_text(output)
check('tour exits 0 with 7/7 cells complete', code == 0 and output.count('[완료]') == 7 and next(answers, 'END') == 'END')
check('전체실행 stops before the write cell', '전체실행을 멈추고 Enter 확인을 받습니다' in output)
check('out-of-range pick is re-asked', '사이 번호를 쉼표로 입력하세요' in output)
after = synthetic_runtime(item['config']).status()
check('tour result: 3 memories, nothing waiting', after['visible_memories'] == 3 and not after['memory_awaiting_confirmation_ids'])
print(f'\nALL {len(RESULTS)} CHECKS PASSED · scratch {BASE}')
