#!/usr/bin/env python3
"""Review waiting memory candidates: verified backup first, then decide only the ids the user names."""
import argparse
from contextlib import contextmanager
from datetime import datetime
import fcntl
import json
import os
from pathlib import Path
import re
import uuid
import first_collection as collection

STATES = ('awaiting_confirmation', 'unverified')
MAX_IDS = 20
MAX_RECEIPT_AGE_S = 6 * 3600
RUN_ENV = 'AIRAG_TOUR14_RUN'


def counts(app):
    status = app.status()
    return {'awaiting_confirmation': app.memory_candidates('awaiting_confirmation', limit=1)['total'],
            'unverified': app.memory_candidates('unverified', limit=1)['total'],
            'visible_memories': status['visible_memories'],
            'backup_count': status['backup_count'],
            'last_verified_backup': status['last_verified_backup'],
            'automatic_confirmation': False}


def receipt_path(app):
    return app.config.project_root / 'tour-14-backup.json'


def log_path(app):
    return app.config.project_root / 'tour-14-decisions.json'


def write(path, data):
    if path.is_symlink():
        collection.fail('SYMLINK_RECEIPT_REJECTED')
    tmp = path.with_name(path.name + '.' + uuid.uuid4().hex + '.tmp')
    with tmp.open('x', encoding='utf-8') as stream:
        stream.write(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    tmp.chmod(0o600)
    tmp.replace(path)


@contextmanager
def decision_lock(app):
    """One decide call at a time: log read, intent, core writes and result all happen under it."""
    with (app.config.project_root / 'tour-14.lock').open('a') as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        yield


def receipt_for_run(app, run):
    """The receipt written by this tour run's own backup cell."""
    if not run:
        collection.fail('TOUR_RUN_REQUIRED')
    path = receipt_path(app)
    if not path.is_file():
        collection.fail('CREATE_VERIFIED_BACKUP_FIRST')
    receipt = json.loads(path.read_text())
    if receipt.get('run') != run:
        collection.fail('BACKUP_NOT_FROM_THIS_TOUR_RUN')
    return receipt


def assert_fresh(app, receipt):
    """Receipt and verified backup are both within the window at the current clock."""
    for stamp in (receipt['at'], receipt['completed_at']):
        age = (app.clock() - datetime.fromisoformat(stamp)).total_seconds()
        if not 0 <= age <= MAX_RECEIPT_AGE_S:
            collection.fail('BACKUP_RECEIPT_STALE')


def verified_receipt(app, run):
    """Fresh receipt from this run whose backup passes isolated restore verification right now."""
    receipt = receipt_for_run(app, run)
    age = (app.clock() - datetime.fromisoformat(receipt['at'])).total_seconds()
    if not 0 <= age <= MAX_RECEIPT_AGE_S:
        collection.fail('BACKUP_RECEIPT_STALE')
    try:
        verified = app.verify_backup(receipt['backup_id'])
    except Exception:
        collection.fail('BACKUP_VERIFICATION_FAILED')
    if verified.get('verified') is not True:
        collection.fail('BACKUP_VERIFICATION_FAILED')
    # The receipt's own fields can be rewritten; the verified set's completion time cannot be faked by that.
    receipt = {**receipt, 'completed_at': verified['completed_at']}
    assert_fresh(app, receipt)
    return receipt


def ids(value):
    found = [item for item in (value or '').split(',') if item]
    if any(re.fullmatch(r'[A-Za-z0-9:_.~-]{1,160}', item) is None for item in found):
        collection.fail('INVALID_CANDIDATE_ID')
    return found


def decide(app, approve, verify, reject, run):
    chosen = [('approve', item) for item in approve] + [('verify', item) for item in verify] + [('reject', item) for item in reject]
    if len(chosen) > MAX_IDS or len({item for _, item in chosen}) != len(chosen):
        collection.fail('INVALID_DECISION_LIST')
    if not chosen:
        return {'results': [], 'noop': True, 'log_complete': True, 'status': counts(app)}
    receipt = verified_receipt(app, run)
    with decision_lock(app):
        assert_fresh(app, receipt)  # the wait for the lock may have outlived the window
        path = log_path(app)
        saved = json.loads(path.read_text()) if path.is_file() else []
        entry = {'entry_id': uuid.uuid4().hex, 'at': app.clock().isoformat(), 'backup_id': receipt['backup_id'],
                 'intent': [{'candidate_id': item, 'action': action} for action, item in chosen], 'status': 'pending'}
        saved.append(entry)
        write(path, saved)  # intent is on disk before the first core write; failure here leaves the core untouched
        actions = {'approve': app.memory_confirm, 'verify': app.memory_verify, 'reject': app.memory_reject}
        results = []
        for action, candidate_id in chosen:
            try:
                outcome = actions[action](candidate_id)
                results.append({'candidate_id': candidate_id, 'action': action, 'state': outcome['state'],
                                'reason': outcome.get('reason')})
            except Exception as error:
                code = str(error)
                results.append({'candidate_id': candidate_id, 'action': action, 'state': 'error',
                                'code': code if re.fullmatch(r'[A-Z][A-Z0-9_]{1,100}', code) else 'DECISION_FAILED'})
        entry.update(status='done', results=results)
        try:
            write(path, saved)
            log_complete = True
        except Exception:
            log_complete = False  # core already applied; the on-disk intent entry keeps the user's decision on record
        return {'results': results, 'noop': False, 'log_complete': log_complete, 'status': counts(app)}


def work(action, *, app=None, state=None, skip=0, limit=10, approve='', verify='', reject='', run=None):
    app = collection.runtime() if app is None else app
    if action == 'inspect':
        return counts(app)
    if action == 'backup':
        if not run:
            collection.fail('TOUR_RUN_REQUIRED')
        before = counts(app)
        created = app.backup(force=True)
        backup_id = Path(created['path']).name
        verified = app.verify_backup(backup_id)
        write(receipt_path(app), {'backup_id': backup_id, 'before': before, 'run': run,
                                  'at': app.clock().isoformat()})
        return {'backup_id': backup_id, 'verified': verified['verified'], 'components': verified['components'],
                'before': before}
    if action == 'candidates':
        if state not in STATES:
            collection.fail('INVALID_STATE')
        return app.memory_candidates(state, limit=limit, skip=skip)
    if action == 'decide':
        return decide(app, ids(approve), ids(verify), ids(reject), run)
    if action == 'summary':
        receipt = receipt_for_run(app, run)
        path = log_path(app)
        tally = {}
        for entry in (json.loads(path.read_text()) if path.is_file() else []):
            if entry.get('backup_id') != receipt['backup_id']:
                continue
            for row in entry.get('results') or [dict(item, state='pending') for item in entry['intent']]:
                key = f'{row["action"]}:{row["state"]}'
                tally[key] = tally.get(key, 0) + 1
        return {'backup_id': receipt['backup_id'], 'before': receipt['before'], 'now': counts(app), 'decisions': tally}
    if action == 'rollback':
        receipt = receipt_for_run(app, run)
        return {'backup_id': receipt['backup_id'], 'backup_path': str(app.config.backup_root / receipt['backup_id']),
                'consumer_db': str(app.config.consumer_db), 'projection_db': str(app.config.projection_db),
                'core_revert_available': False}
    collection.fail('UNKNOWN_ACTION')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=('inspect', 'backup', 'candidates', 'decide', 'summary', 'rollback'))
    parser.add_argument('--state')
    parser.add_argument('--skip', type=int, default=0)
    parser.add_argument('--limit', type=int, default=10)
    parser.add_argument('--approve', default='')
    parser.add_argument('--verify', default='')
    parser.add_argument('--reject', default='')
    args = parser.parse_args()
    try:
        data = work(args.action, state=args.state, skip=args.skip, limit=args.limit,
                    approve=args.approve, verify=args.verify, reject=args.reject, run=os.environ.get(RUN_ENV))
        failed = any(row['state'] == 'error' for row in data.get('results', []))
        print(json.dumps({'ok': not failed, 'data': data, **({'error': {'code': 'DECISION_PARTLY_FAILED'}} if failed else {})},
                         ensure_ascii=False))
        raise SystemExit(1 if failed else 0)
    except Exception as error:
        code = getattr(error, 'code', str(error))
        if not isinstance(code, str) or not re.fullmatch(r'[A-Z][A-Z0-9_]{1,100}', code):
            code = type(error).__name__
        print(json.dumps({'ok': False, 'error': {'code': code}}, ensure_ascii=False))
        raise SystemExit(1)
