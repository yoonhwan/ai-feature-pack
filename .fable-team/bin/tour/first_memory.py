#!/usr/bin/env python3
"""Extract one bounded memory batch and inspect scoped candidate counts."""
import argparse
import json
import re
from airag_consumer import memory
import first_collection as collection
from first_index import bound


def summary(app, ledger, state):
    rows = []
    exists = ledger._con.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='airag_memory_candidates'").fetchone()
    if exists:
        rows = ledger._con.execute('''SELECT c.kind,c.disposition,count(*)
            FROM airag_memory_candidates c JOIN airag_memory_extractions e ON e.extraction_id=c.extraction_id
            WHERE e.owner_id=? AND e.tenant_id=? AND e.project_id=? AND e.streams_digest=? AND e.state='complete'
            GROUP BY c.kind,c.disposition ORDER BY c.kind,c.disposition''',
            (app.config.owner_id, app.config.tenant_id, app.config.project_id,
             memory._digest(list(app.config.scope.enrolled_streams)))).fetchall()
    return {'visible_memories': len(state['visible_memory_ids']),
            'candidate_groups': [{'kind':kind,'disposition':disposition,'count':count} for kind,disposition,count in rows],
            'indexed_windows':len(state['searchable_window_ids']),
            'automatic_confirmation':False}


def work(action):
    app = collection.runtime()
    with app._lock():
        ledger = app._open_ledger()
        try:
            _, before_events = bound(app, ledger)
            lifecycle = app._lifecycle(ledger)
            state = lifecycle.refresh(app.config.scope)
            if not state['read_gate']['open'] or not state['searchable_window_ids'] or state['pending_publication_ids']:
                collection.fail('COMPLETE_TOUR_05_FIRST')
            if action == 'inspect':
                return summary(app, ledger, state)
            before = len(state['visible_memory_ids'])
            result = app._extract_memory(lifecycle)
            if not result.get('enabled'):
                collection.fail('MEMORY_EXTRACTION_DISABLED')
            after = lifecycle.refresh(app.config.scope)
            _, after_events = bound(app, ledger)
            return {'extraction':result, 'inventory':summary(app,ledger,after),
                    'new_visible_memories':len(after['visible_memory_ids'])-before,
                    'new_events':after_events-before_events, 'automatic_confirmation':False}
        finally:
            ledger.close()


if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('action',choices=('inspect','extract'))
    args=parser.parse_args()
    try:
        data=work(args.action)
        failed=data.get('extraction',{}).get('state')=='failed'
        print(json.dumps({'ok':not failed,'data':data,
                          **({'error':{'code':'MEMORY_EXTRACTION_FAILED'}} if failed else {})},ensure_ascii=False))
        raise SystemExit(1 if failed else 0)
    except Exception as error:
        code=getattr(error,'code',str(error))
        if not isinstance(code,str) or not re.fullmatch(r'[A-Z][A-Z0-9_]{1,100}',code):code=type(error).__name__
        print(json.dumps({'ok':False,'error':{'code':code}},ensure_ascii=False))
        raise SystemExit(1)
