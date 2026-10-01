#!/usr/bin/env python3
"""Bounded synthetic LLM load; never opens operational AIRAG databases."""
import argparse
from concurrent.futures import ThreadPoolExecutor,wait,FIRST_COMPLETED
from datetime import datetime,timezone
import fcntl
import json
import os
from pathlib import Path
import re
import time
import uuid
from airag_consumer.memory import ExtractionRequest,SourceMessage,OpenAICompatibleMemoryConfig
from provider_load import read_load
from request_trace import RequestTrace

ROOT=Path(__file__).resolve().parents[2]/'airag/traces'
CONFIG=Path.home()/'.local/share/airag/projects/ai-feature-pack/runtime.json'
DURATION=180
CONCURRENCY=2
MAX_REQUESTS=120
TEXTS=(
    '공개 테스트 프로젝트의 결정: 고객 기록은 프로젝트별로 분리하고 암호화한다. 검색 결과에는 원문 근거를 연결한다. 운영 기록과 실험 데이터는 별도 경로에 보관하기로 합의했다.',
    '진행 상태: 문서 가져오기와 검색 연결을 완료했다. 백업 복원 검사는 진행 중이다. 다음 작업은 잘못된 입력을 거부하는 검사와 다시 실행해도 중복 저장되지 않는지 확인하는 것이다.',
    '사용자 선호 후보: 보고서는 먼저 결론을 짧게 보여주고 진행 상태를 트리로 정리해 달라. 장기 선호로 저장하려면 사용자 확인을 받아야 한다. 이 문장은 공개 부하 테스트용 합성 대화다.',
    '검증 기록: 합성 파일 세 개를 테스트 저장소에 추가하고 검색 결과가 나오는 것을 확인했다. 삭제 후에는 같은 검색어로 원문이 노출되지 않았다. 실제 운영 데이터에 대한 성공 주장은 아니다.',
)


def request_for(index):
    return ExtractionRequest(f'synthetic-load-{index}',tuple(
        SourceMessage(f'fixture-{index}-{n}','user' if n%2==0 else 'assistant',f'실험 묶음 {index}. '+text)
        for n,text in enumerate(TEXTS)))


def exercise(tracer, *, duration_s=DURATION, concurrency=CONCURRENCY,
             max_requests=MAX_REQUESTS, metrics=None, stop_requested=None, stop_on_error=True):
    if duration_s<=0 or type(concurrency) is not int or concurrency not in (1,2,4) or max_requests<1:
        raise ValueError('INVALID_LOAD_LIMITS')
    started=time.monotonic();deadline=started+duration_s
    stop_requested=stop_requested or (lambda:False)
    submitted=success=failures=0;reason=None;last_metric=started-5
    tracer.record('load_start',duration_s=duration_s,concurrency=concurrency,max_requests=max_requests,
                  dataset='public_synthetic',operational_db_opened=False)
    with ThreadPoolExecutor(max_workers=concurrency,thread_name_prefix='airag-load') as pool:
        pending=set()
        while True:
            while (not failures or not stop_on_error) and not stop_requested() and len(pending)<concurrency and submitted<max_requests and time.monotonic()<deadline:
                pending.add(pool.submit(tracer,request_for(submitted)))
                submitted+=1
            if not pending:
                break
            done,pending=wait(pending,timeout=1,return_when=FIRST_COMPLETED)
            for future in done:
                try:future.result()
                except Exception as error:
                    failures+=1
                    code=getattr(error,'code',type(error).__name__)
                    reason=code if isinstance(code,str) and re.fullmatch(r'[A-Z][A-Z0-9_]{1,100}',code) else type(error).__name__
                else:success+=1
            if metrics and time.monotonic()-last_metric>=5:
                try:tracer.record('server_snapshot',**metrics())
                except Exception as error:tracer.record('server_snapshot_unavailable',error_type=type(error).__name__)
                last_metric=time.monotonic()
    result={'submitted':submitted,'success':success,'failures':failures,'error_code':reason,
            'elapsed_s':round(time.monotonic()-started,3),'submission_window_s':duration_s,
            'concurrency':concurrency,'operational_db_opened':False,
            'stop_reason':'request_failed' if failures else 'coordinated_stop' if stop_requested() else 'request_cap' if submitted>=max_requests else 'duration_reached'}
    tracer.record('load_end',**result)
    return result


def plan(concurrency=CONCURRENCY):
    return {'duration_s':DURATION,'concurrency':concurrency,'max_requests':MAX_REQUESTS,
            'request_timeout_s':120,'max_total_s':DURATION+120,
            'input':'public_synthetic','operational_db_opened':False}


def run(concurrency=CONCURRENCY, after_run=None):
    if type(concurrency) is not int or concurrency not in (1,2,4):
        raise ValueError('INVALID_LOAD_LIMITS')
    if after_run is not None and not re.fullmatch(r'airag-synthetic-[A-Za-z0-9-]+',after_run):
        raise ValueError('INVALID_BASELINE_RUN')
    ROOT.mkdir(parents=True,exist_ok=True)
    with (ROOT/'synthetic-load.lock').open('a') as lock:
        wait_until=time.monotonic()+330
        while True:
            try:
                fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if after_run is None:raise ValueError('LOAD_TEST_ALREADY_RUNNING') from None
                if time.monotonic()>=wait_until:raise ValueError('BASELINE_WAIT_TIMEOUT') from None
                time.sleep(.25)
        if after_run is not None:
            baseline=ROOT/(after_run+'.result.json')
            if not baseline.is_file():raise ValueError('BASELINE_NOT_COMPLETE')
            prior=json.loads(baseline.read_text())
            if prior.get('failures') or prior.get('concurrency')!=2:
                raise ValueError('BASELINE_NOT_SUCCESSFUL')
        settings=json.loads(CONFIG.read_text())
        run_id='airag-synthetic-'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')+'-'+uuid.uuid4().hex[:6]
        trace=ROOT/(run_id+'.jsonl')
        key=os.environ.get('AIRAG_MEMORY_API_KEY')
        config=OpenAICompatibleMemoryConfig(endpoint=settings['memory_endpoint'],model=settings['memory_model'],
                                           api_key_provider=(lambda:key) if key else None)
        tracer=RequestTrace(str(trace),run_id,config)
        tracer.record('comparison_baseline',baseline_run_id=after_run)
        result=exercise(tracer,concurrency=concurrency,metrics=lambda:read_load(config.endpoint,config.model))
        rows=[json.loads(line) for line in trace.read_text().splitlines()]
        ends=[row for row in rows if row['event']=='http_end']
        result.update(run_id=run_id,trace=str(trace),baseline_run_id=after_run,
            input_tokens=sum(row['input_tokens'] or 0 for row in ends),
            output_tokens=sum(row['output_tokens'] or 0 for row in ends),
            missing_usage=sum(row['input_tokens'] is None or row['output_tokens'] is None for row in ends),
            max_request_s=max((row['elapsed_s'] for row in ends),default=0))
        trace.with_suffix('.result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
        return result


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=('plan','run'))
    parser.add_argument('--concurrency',type=int,choices=(1,2,4),default=CONCURRENCY)
    parser.add_argument('--after-run')
    args=parser.parse_args()
    try:
        data=plan(args.concurrency) if args.action=='plan' else run(args.concurrency,args.after_run)
        print(json.dumps({'ok':not data.get('failures'),'data':data},ensure_ascii=False))
        raise SystemExit(1 if data.get('failures') else 0)
    except Exception as error:
        code=str(error)
        if not re.fullmatch(r'[A-Z][A-Z0-9_]{1,100}',code):code=type(error).__name__
        print(json.dumps({'ok':False,'error':{'code':code}},ensure_ascii=False));raise SystemExit(1)
