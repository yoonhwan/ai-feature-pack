#!/usr/bin/env python3
"""Finite first collection: a verified source prefix, without model calls."""
import argparse
from dataclasses import asdict
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re

import deployment_setup as setup
from airag_consumer.collector import _classify, collect_codex_rollout
from airag_consumer.events import AccessScope, parse_event
from airag_consumer.redaction import redact_event
from airag_consumer.runtime import AIRAGRuntime, RuntimeConfig

PUBLIC_MESSAGES = 4
MAX_CAPTURE_BYTES = 1_048_576


def fail(code):
    raise ValueError(code)


def build_plan(config):
    source = config.sources[0]
    scope = AccessScope(config.tenant_id, config.project_id, source.session_id)
    public = accepted = skipped = offset = 0
    last_ordinal = None
    digest = hashlib.sha256()
    opened = source.path.stat()
    with source.path.open('rb') as stream:
        while offset < MAX_CAPTURE_BYTES:
            raw = stream.readline(MAX_CAPTURE_BYTES - offset + 1)
            if not raw or not raw.endswith(b'\n') or offset + len(raw) > MAX_CAPTURE_BYTES:
                break
            end = offset + len(raw)
            item = _classify(raw[:-1], start=offset, end=end, expected_scope=scope,
                             producer_epoch='tour-preview', first_seen_at=datetime.now(timezone.utc).isoformat(),
                             last_ordinal=last_ordinal, allow_gaps=False)
            if item.ordinal is not None:
                last_ordinal = item.ordinal
            if item.disposition == 'accepted':
                redacted = redact_event(parse_event(item.normalized, expected_scope=scope))
                accepted += 1
                public += int(redacted.has_public_text)
            elif item.disposition == 'skipped':
                skipped += 1
            else:
                fail('REJECTED_RECORD_REQUIRES_REVIEW')
            digest.update(raw)
            offset = end
            if public >= PUBLIC_MESSAGES:
                break
    if public < PUBLIC_MESSAGES:
        fail('INSUFFICIENT_VALID_MESSAGES_WITHIN_TOUR_BOUND')
    if (source.path.stat().st_dev, source.path.stat().st_ino) != (opened.st_dev, opened.st_ino):
        fail('SOURCE_IDENTITY_CHANGED')
    return {'version': 1, 'source_path': str(source.path), 'source_id': source.source_id,
            'session_id': source.session_id, 'device': opened.st_dev, 'inode': opened.st_ino,
            'captured_byte_limit': offset, 'prefix_sha256': digest.hexdigest(),
            'public_messages': public, 'accepted_records': accepted, 'excluded_records': skipped,
            'allow_gaps': False, 'model_calls': False, 'source_modified': False}


def plan_path(config):
    return config.project_root / 'tour-04-plan.json'


def verify_plan(config):
    saved = json.loads(plan_path(config).read_text())
    source = config.sources[0]
    if (saved.get('source_path'), saved.get('source_id'), saved.get('session_id')) != (str(source.path), source.source_id, source.session_id):
        fail('TOUR_SOURCE_BINDING_MISMATCH')
    size = saved.get('captured_byte_limit')
    if type(size) is not int or not 0 < size <= MAX_CAPTURE_BYTES or saved.get('allow_gaps') is not False:
        fail('INVALID_TOUR_CAPTURE_BOUND')
    current = source.path.stat()
    if (current.st_dev, current.st_ino) != (saved['device'], saved['inode']):
        fail('SOURCE_IDENTITY_CHANGED')
    with source.path.open('rb') as stream:
        raw = stream.read(size)
    if len(raw) != size or not raw.endswith(b'\n') or hashlib.sha256(raw).hexdigest() != saved['prefix_sha256']:
        fail('SOURCE_PREFIX_CHANGED')
    return saved


def preview():
    config = RuntimeConfig.load(setup.CONFIG)
    path = plan_path(config)
    if path.exists():
        return verify_plan(config)
    plan = build_plan(config)
    setup.write_json(path, plan)
    return plan


def runtime():
    config = RuntimeConfig.load(setup.CONFIG)
    environment = dict(os.environ)
    environment.pop('AIRAG_PROFILE_SOURCE_KEY_HEX', None)
    if config.reference is not None:
        _, tour = setup.context()
        environment[config.reference.source_key_env] = setup.original_key(tour).hex()
    return AIRAGRuntime(config, environ=environment, clock=lambda: datetime.now(timezone.utc))


def collect():
    app = runtime()
    with app._lock():
        plan = verify_plan(app.config)
        ledger = app._open_ledger()
        try:
            before = ledger._con.execute('SELECT count(*) FROM events').fetchone()[0]
            source = app.config.sources[0]
            receipt = collect_codex_rollout(ledger, source_path=source.path, allowed_real_paths=(source.path,),
                source_id=source.source_id, expected_session_id=source.session_id,
                expected_scope=AccessScope(app.config.tenant_id, app.config.project_id, source.session_id),
                captured_byte_limit=plan['captured_byte_limit'], allow_gaps=False)
            after = ledger._con.execute('SELECT count(*) FROM events').fetchone()[0]
            state = app._lifecycle(ledger).refresh(app.config.scope, explicit_save=True)
            return {'inserted_events': after - before, 'stored_events': after, 'receipt': asdict(receipt),
                    'pending_windows': len(state['pending_publication_ids']),
                    'indexed_windows': len(state['searchable_window_ids']),
                    'selected_prefix_unchanged': verify_plan(app.config)['prefix_sha256'] == plan['prefix_sha256'],
                    'full_source_processed': receipt.committed_native_offset == source.path.stat().st_size,
                    'model_calls': False}
        finally:
            ledger.close()


def status():
    app = runtime()
    result = app.status()
    return {name: result[name] for name in ('indexed', 'active', 'visible_memories', 'pending', 'failed', 'gaps', 'collector_sources')}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=('preview', 'collect', 'status'))
    args = parser.parse_args()
    try:
        print(json.dumps({'ok': True, 'data': globals()[args.action]()}, ensure_ascii=False))
    except Exception as error:
        code = getattr(error, 'code', str(error))
        if not isinstance(code, str) or not re.fullmatch(r'[A-Z][A-Z0-9_]{1,100}', code):
            code = type(error).__name__
        print(json.dumps({'ok': False, 'error': {'code': code}}, ensure_ascii=False))
        raise SystemExit(1)
