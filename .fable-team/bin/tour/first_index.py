#!/usr/bin/env python3
"""Publish and search only the already-collected tour-04 snapshot."""
import argparse
import json
import re
import urllib.request

import first_collection as collection
from airag import profiles
from airag_consumer import bridge


def bound(app, ledger):
    if len(app.config.sources) != 1:
        collection.fail('TOUR_EXPECTS_ONE_SOURCE')
    plan = collection.verify_plan(app.config)
    row = ledger._con.execute(
        'SELECT next_native_offset FROM airag_rollout_collector_sources WHERE source_id=?',
        (app.config.sources[0].source_id,),
    ).fetchone()
    count = ledger._con.execute('SELECT count(*) FROM events').fetchone()[0]
    if row != (plan['captured_byte_limit'],) or count != plan['accepted_records']:
        collection.fail('COLLECTED_RANGE_DIFFERS_FROM_TOUR_04')
    return plan, count


def providers(projection, profile_key):
    embedding, _ = profiles.config_from_profile(projection, profile_key)
    llm = profiles.llm_from_profile(projection, profile_key)
    targets = [('embedding', embedding)] + ([] if llm is None else [('llm', llm)])
    result = []
    for label, config in targets:
        try:
            with urllib.request.urlopen(config.endpoint.rstrip('/') + '/models', timeout=5) as response:
                payload = json.load(response)
            ready = config.model in [item.get('id') for item in payload.get('data', [])]
        except Exception:
            ready = False
        result.append({'service': label, 'ready': ready})
    if not all(item['ready'] for item in result):
        collection.fail('MODEL_CONNECTION_REQUIRED')
    return result


def work(action, query=None):
    app = collection.runtime()
    with app._lock():
        ledger = app._open_ledger()
        projection = None
        try:
            plan, before_events = bound(app, ledger)
            lifecycle = app._lifecycle(ledger)
            state = lifecycle.refresh(app.config.scope)
            if not state['read_gate']['open']:
                collection.fail('CURRENT_TIME_EXPIRY_PASS_REQUIRED')
            projection = app._open_projection()
            if action == 'preflight':
                return {'stored_events': before_events, 'selected_bytes': plan['captured_byte_limit'],
                        'pending_windows': len(state['pending_publication_ids']),
                        'indexed_windows': len(state['searchable_window_ids']),
                        'providers': providers(projection, app.config.profile_key), 'new_collection': False}
            if action == 'index':
                if state['pending_publication_ids']:
                    providers(projection, app.config.profile_key)
                before_jobs = projection.execute('SELECT count(*) FROM jobs').fetchone()[0]
                results = bridge.publish_pending_windows(lifecycle, app.config.scope, projection,
                    collection=app.config.collection, profile_key=app.config.profile_key)
                after = lifecycle.refresh(app.config.scope)
                _, after_events = bound(app, ledger)
                return {'attempted': len(results), 'succeeded': sum(item.get('ok') is True for item in results),
                        'failures': [item.get('error', {}).get('code', 'UNKNOWN') for item in results if not item.get('ok')],
                        'indexed_windows': len(after['searchable_window_ids']),
                        'pending_windows': len(after['pending_publication_ids']),
                        'new_events': after_events - before_events,
                        'new_jobs': projection.execute('SELECT count(*) FROM jobs').fetchone()[0] - before_jobs,
                        'source_prefix_unchanged': True, 'new_collection': False}
            if action == 'search':
                result = bridge.search_history(lifecycle, app.config.scope, projection,
                    collection=app.config.collection, profile_key=app.config.profile_key, query=query, top_k=3)
                bound(app, ledger)
                return result
            collection.fail('UNKNOWN_TOUR_ACTION')
        finally:
            if projection is not None:
                projection.close()
            ledger.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=('preflight', 'index', 'search', 'status'))
    parser.add_argument('query', nargs='?', default='세션 확인')
    args = parser.parse_args()
    try:
        data = collection.status() if args.action == 'status' else work(args.action, args.query)
        failed = bool(data.get('failures'))
        print(json.dumps({'ok': not failed, 'data': data,
                          **({'error': {'code': 'INDEX_PUBLICATION_FAILED'}} if failed else {})}, ensure_ascii=False))
        raise SystemExit(1 if failed else 0)
    except Exception as error:
        code = getattr(error, 'code', str(error))
        if not isinstance(code, str) or not re.fullmatch(r'[A-Z][A-Z0-9_]{1,100}', code):
            code = type(error).__name__
        print(json.dumps({'ok': False, 'error': {'code': code}}, ensure_ascii=False))
        raise SystemExit(1)
