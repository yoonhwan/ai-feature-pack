#!/usr/bin/env python3
"""Publish one pending window from the completed, explicitly reviewed snapshot."""
import argparse
import json
import re
import time
from airag_consumer import bridge
import first_collection as collection
from first_index import providers
import reviewed_collection


def bound(app,ledger):
    review,gaps=reviewed_collection.reviewed(app)
    approval=json.loads((app.config.project_root/'tour-09-approval.json').read_text())
    if approval.get('review_digest')!=reviewed_collection.digest(review) or approval.get('rejections')!=gaps:
        collection.fail('REVIEW_APPROVAL_MISMATCH')
    row=ledger._con.execute('SELECT next_native_offset FROM airag_rollout_collector_sources WHERE source_id=?',(app.config.sources[0].source_id,)).fetchone()
    if row!=(review['reviewed_through'],):collection.fail('COMPLETE_REVIEWED_COLLECTION_FIRST')
    accepted=ledger._con.execute("SELECT count(*) FROM airag_rollout_collector_plans WHERE source_id=? AND state='finalized' AND disposition='accepted' AND native_start>=? AND native_end<=?",
        (app.config.sources[0].source_id,review['from_offset'],review['reviewed_through'])).fetchone()[0]
    if accepted!=review['counts'].get('accepted',0):collection.fail('REVIEWED_RECORD_COUNT_MISMATCH')
    return review,ledger._con.execute('SELECT count(*) FROM events').fetchone()[0]


def counts(state):
    return {'indexed':len(state['searchable_window_ids']),'pending':len(state['pending_publication_ids']),
            'failed':sum(w['publication_state']=='failed' for w in state['windows'])}


def performance(projection, collection_name, result):
    if not result or not result.get('ok'):
        return {'available': False}
    row=projection.execute("""SELECT n.structured_json FROM normalized_documents n
        JOIN sources s ON s.ready_generation_id=n.generation_id
        JOIN collections c ON c.collection_id=s.collection_id
        WHERE c.name=? AND s.source_key=?""",
        (collection_name,result['source_key'])).fetchone()
    if row is None:return {'available': False}
    data=json.loads(row[0]).get('llm_enrichment',{})
    execution=data.get('execution')
    if not isinstance(execution,dict):return {'available':False}
    windows={}
    for item in data.get('groups',[]):
        windows.setdefault(item['group_id'].split('-')[1],item.get('execution_metrics',{}))
    calls=[call for item in windows.values() for call in item.get('http_calls',[])]
    return {'available':True,**execution,'semantic_windows':len(windows),
            'result_cache_hits':sum(bool(item.get('cache_hit')) for item in windows.values()),
            'generation_calls':sum(c['path']=='/chat/completions' for c in calls),
            'tokenize_calls':sum(c['path']=='/tokenize' for c in calls),
            'generation_api_seconds_sum':round(sum(c['seconds'] for c in calls if c['path']=='/chat/completions'),3),
            'tokenize_api_seconds_sum':round(sum(c['seconds'] for c in calls if c['path']=='/tokenize'),3),
            'prompt_tokens':sum(c['prompt_tokens'] for c in calls),
            'completion_tokens':sum(c['completion_tokens'] for c in calls),
            'cached_prompt_tokens':sum(c['cached_prompt_tokens'] for c in calls)}


def work(action,query=None):
    app=collection.runtime()
    with app._lock():
        ledger=app._open_ledger();projection=None
        try:
            review,before_events=bound(app,ledger)
            life=app._lifecycle(ledger);state=life.refresh(app.config.scope)
            if not state['read_gate']['open']:collection.fail('CURRENT_TIME_EXPIRY_PASS_REQUIRED')
            projection=app._open_projection()
            if action=='preflight':
                return {**counts(state),'stored_events':before_events,'through_offset':review['reviewed_through'],
                        'providers':providers(projection,app.config.profile_key),'new_collection':False}
            if action=='publish':
                pending=state['pending_publication_ids']
                before_jobs=projection.execute('SELECT count(*) FROM jobs').fetchone()[0]
                started=time.monotonic()
                result=None
                if pending:
                    result=bridge._publish_window(life,app.config.scope,projection,
                        collection=app.config.collection,profile_key=app.config.profile_key,window_id=pending[0])
                state=life.refresh(app.config.scope);_,after_events=bound(app,ledger)
                remaining=counts(state)
                return {**remaining,'attempted':int(result is not None),'ok':result is None or result.get('ok') is True,
                        'error_code':None if result is None or result.get('ok') else result.get('error',{}).get('code','UNKNOWN'),
                        'retryable':None if result is None or result.get('ok') else result.get('error',{}).get('retryable'),
                        'new_events':after_events-before_events,
                        'new_jobs':projection.execute('SELECT count(*) FROM jobs').fetchone()[0]-before_jobs,
                        'complete':remaining['pending']==0 and remaining['failed']==0,
                        'seconds':round(time.monotonic()-started,3),'new_collection':False,
                        'performance':performance(projection,app.config.collection,result)}
            if action=='search':
                result=bridge.search_history(life,app.config.scope,projection,
                    collection=app.config.collection,profile_key=app.config.profile_key,query=query,top_k=3)
                bound(app,ledger);return result
            if action=='status':return {**counts(state),'stored_events':before_events,'visible_memories':len(state['visible_memory_ids']),
                                        'complete':not state['pending_publication_ids'] and counts(state)['failed']==0}
            collection.fail('UNKNOWN_TOUR_ACTION')
        finally:
            if projection is not None:projection.close()
            ledger.close()


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=('preflight','publish','search','status'));parser.add_argument('query',nargs='?',default='백업은 언제 실행하나요?');args=parser.parse_args()
    try:
        data=work(args.action,args.query);failed=data.get('ok') is False
        print(json.dumps({'ok':not failed,'data':data,**({'error':{'code':data.get('error_code'),'retryable':data.get('retryable')}} if failed else {})},ensure_ascii=False))
        raise SystemExit(1 if failed else 0)
    except Exception as error:
        code=getattr(error,'code',str(error))
        if not isinstance(code,str) or not re.fullmatch(r'[A-Z][A-Z0-9_]{1,100}',code):code=type(error).__name__
        print(json.dumps({'ok':False,'error':{'code':code}},ensure_ascii=False));raise SystemExit(1)
