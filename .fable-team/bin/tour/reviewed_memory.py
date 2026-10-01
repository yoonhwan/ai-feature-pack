#!/usr/bin/env python3
"""Extract one bounded memory batch and inspect scoped candidate counts."""
import argparse
import json
import re
from airag_consumer import memory
from airag_consumer.runtime import MEMORY_BATCH_INPUT_BYTES, MEMORY_MAX_MESSAGES_PER_BATCH
import first_collection as collection
from reviewed_index import bound
from provider_load import read_load


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
            'automatic_confirmation':False,
            'progress':memory.memory_progress(
                app._lifecycle(ledger), app.config.scope, model_id=app.config.memory_model,
                batch_input_bytes=MEMORY_BATCH_INPUT_BYTES,
                max_messages_per_batch=MEMORY_MAX_MESSAGES_PER_BATCH)}


def work(action, *, app=None, allow_busy=False):
    app = collection.runtime() if app is None else app
    with app._lock():
        ledger = app._open_ledger()
        try:
            _, before_events = bound(app, ledger)
            lifecycle = app._lifecycle(ledger)
            state = lifecycle.refresh(app.config.scope)
            if not state['read_gate']['open'] or not state['searchable_window_ids'] or state['pending_publication_ids']:
                collection.fail('COMPLETE_TOUR_10_FIRST')
            if action == 'inspect':
                return summary(app, ledger, state)
            if action == 'recover':
                lineage=memory._lineage_id(app.config.scope, app.config.memory_model,
                    memory.MEMORY_PROMPT_VERSION, MEMORY_BATCH_INPUT_BYTES, MEMORY_MAX_MESSAGES_PER_BATCH)
                pending=[row[0] for row in ledger._con.execute(
                    """SELECT e.extraction_id FROM airag_memory_extractions e
                       JOIN airag_memory_batches b ON b.batch_id=e.batch_id
                       WHERE b.lineage_id=? AND e.state='pending'""", (lineage,)).fetchall()]
                recovered=memory.recover_interrupted_memory_batches(
                    lifecycle,app.config.scope,model_id=app.config.memory_model,
                    expected_extraction_ids=pending,batch_input_bytes=MEMORY_BATCH_INPUT_BYTES,
                    max_messages_per_batch=MEMORY_MAX_MESSAGES_PER_BATCH,clock=app.clock)
                return {**recovered,'inventory':summary(app,ledger,state),'provider_called':False}
            progress=memory.memory_progress(
                lifecycle,app.config.scope,model_id=app.config.memory_model,
                batch_input_bytes=MEMORY_BATCH_INPUT_BYTES,
                max_messages_per_batch=MEMORY_MAX_MESSAGES_PER_BATCH)
            if progress['remaining_batches'] and not allow_busy:
                load=read_load(app.config.memory_endpoint,app.config.memory_model)
                if not load['ready']:
                    return {'deferred':True,'provider_load':load,'progress':progress,
                            'provider_called':False,'new_events':0}
            before = len(state['visible_memory_ids'])
            result = app._extract_memory(lifecycle, concurrency=2)
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
    parser.add_argument('action',choices=('inspect','recover','extract'))
    args=parser.parse_args()
    try:
        data=work(args.action)
        deferred=data.get('deferred',False)
        failed=deferred or data.get('extraction',{}).get('state') in ('failed','pending')
        error={'code':'PROVIDER_BUSY','message':'공유 모델 서버가 사용 중입니다. 새 요청 없이 멈췄습니다. 잠시 뒤 재시도하세요.'} if deferred else {'code':'MEMORY_EXTRACTION_FAILED'}
        print(json.dumps({'ok':not failed,'data':data,
                          **({'error':error} if failed else {})},ensure_ascii=False))
        raise SystemExit(1 if failed else 0)
    except Exception as error:
        code=getattr(error,'code',str(error))
        if not isinstance(code,str) or not re.fullmatch(r'[A-Z][A-Z0-9_]{1,100}',code):code=type(error).__name__
        print(json.dumps({'ok':False,'error':{'code':code}},ensure_ascii=False))
        raise SystemExit(1)
