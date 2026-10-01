#!/usr/bin/env python3
"""Manual, GO-gated memory tour for the coordinated M6/AIRAG reproduction."""
import argparse
from dataclasses import replace
import json
import os
from pathlib import Path
import re
from airag_consumer.memory import OpenAICompatibleMemoryConfig
from credentials import fill_environment
import first_collection as collection
import reviewed_memory
from request_trace import RequestTrace

CONTROL=Path(__file__).resolve().parents[2]/'airag/load-repro-control.json'


def work(action):
    control=json.loads(CONTROL.read_text())
    if action=='gate':
        return {'ready':control['go_received'],'run_id':control['run_id'],
                'manual_execution':True,'trace':control['trace']}
    if action=='extract' and not control['go_received']:
        collection.fail('GO_AIRAG_REQUIRED')
    fill_environment(os.environ)
    app=collection.runtime()
    key=app._environ.get('AIRAG_MEMORY_API_KEY')
    trace=RequestTrace(control['trace'],control['run_id'],OpenAICompatibleMemoryConfig(
        endpoint=app.config.memory_endpoint,model=app.config.memory_model,
        api_key_provider=(lambda:key) if key else None))
    app.hooks=replace(app.hooks,memory_extractor=trace)
    if action=='extract':
        trace.record('group_start',concurrency=2,admission_bypass='explicit_M6_AIRAG_reproduction')
    result=reviewed_memory.work(action,app=app,allow_busy=action=='extract')
    if action=='extract':
        trace.record('group_end',progress=result['extraction']['progress'],
                     state=result['extraction']['state'])
    return result


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('action',choices=('gate','inspect','recover','extract'))
    args=parser.parse_args()
    try:
        data=work(args.action)
        failed=data.get('extraction',{}).get('state') in ('failed','pending')
        print(json.dumps({'ok':not failed,'data':data,
                         **({'error':{'code':'MEMORY_EXTRACTION_FAILED'}} if failed else {})},ensure_ascii=False))
        raise SystemExit(1 if failed else 0)
    except Exception as error:
        code=getattr(error,'code',str(error))
        if not isinstance(code,str) or not re.fullmatch(r'[A-Z][A-Z0-9_]{1,100}',code):code=type(error).__name__
        print(json.dumps({'ok':False,'error':{'code':code}},ensure_ascii=False))
        raise SystemExit(1)
