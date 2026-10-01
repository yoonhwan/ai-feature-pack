#!/usr/bin/env python3
"""Ordered separate-process load stages, with coordinator-enforced stop criteria."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace
from datetime import datetime,timezone
import fcntl
import json
import multiprocessing
import os
from pathlib import Path
import re
import signal
import sys
import time
import uuid
from airag_consumer.memory import OpenAICompatibleMemoryConfig
from provider_load import read_load
from request_trace import RequestTrace
from synthetic_load import exercise,CONFIG,ROOT

CONTROL=ROOT.parent/'multi-load-control.json'
STOP_FILE=ROOT.parent/'multi-load.stop'


class InstanceTrace(RequestTrace):
    def __init__(self,*args,instance_id,**kwargs):
        super().__init__(*args,**kwargs)
        self.instance_id=instance_id

    def record(self,event,**fields):
        super().record(event,instance_id=self.instance_id,pid=os.getpid(),
                       monotonic_at=time.monotonic(),**fields)

    def __call__(self,request):
        return super().__call__(replace(request,extraction_id=f'{self.instance_id}:{request.extraction_id}'))


def worker(settings,run_id,instance_id,directory,duration_s,go,stop):
    path=Path(directory)/(instance_id+'.jsonl')
    try:
        key=os.environ.get('AIRAG_MEMORY_API_KEY')
        config=OpenAICompatibleMemoryConfig(endpoint=settings['memory_endpoint'],model=settings['memory_model'],
                                           api_key_provider=(lambda:key) if key else None)
        tracer=InstanceTrace(str(path),run_id,config,instance_id=instance_id)
        tracer.record('worker_ready')
        if not go.wait(timeout=60):raise ValueError('COORDINATOR_START_TIMEOUT')
        result=exercise(tracer,duration_s=duration_s,concurrency=2,max_requests=120,
                        stop_requested=stop.is_set,stop_on_error=False)
        tracer.record('worker_done',result=result)
    except BaseException as error:
        with path.open('a',encoding='utf-8') as stream:
            stream.write(json.dumps({'event':'worker_error','instance_id':instance_id,
                                     'error_type':type(error).__name__})+'\n')


def read_events(paths,offsets):
    rows=[]
    for path in paths:
        if not path.exists():continue
        with path.open(encoding='utf-8') as stream:
            stream.seek(offsets.get(str(path),0))
            while True:
                before=stream.tell();line=stream.readline()
                if not line or not line.endswith('\n'):
                    offsets[str(path)]=before
                    break
                rows.append(json.loads(line))
                offsets[str(path)]=stream.tell()
    return rows


def stop_children(children):
    # Only the test processes created by this coordinator are stopped.
    for process in children:
        if process.is_alive():process.terminate()
    for process in children:
        process.join(timeout=1)
        if process.is_alive():process.kill();process.join(timeout=1)


def stage(settings,directory,instances,*,duration_s=180,stop_latency_s=60,
          failure_rate_limit=.10,stop_file=None):
    if type(instances) is not int or not 1<=instances<=16:
        raise ValueError('INVALID_INSTANCE_COUNT')
    if not 0<duration_s<=180 or not 0<stop_latency_s<=120 or not 0<=failure_rate_limit<=1:
        raise ValueError('INVALID_LOAD_LIMITS')
    directory=Path(directory);directory.mkdir(parents=True,exist_ok=False)
    run_id=directory.name;ctx=multiprocessing.get_context('spawn')
    go=ctx.Event();stop=ctx.Event();children=[];events=[];offsets={}
    paths=[directory/f'instance-{n+1:02d}.jsonl' for n in range(instances)]
    coordinator=RequestTrace(str(directory/'coordinator.jsonl'),run_id,None)
    metric_pool=ThreadPoolExecutor(max_workers=1);metric_future=None
    reason=None;started=time.monotonic();active={};ready_ids=set();done_ids=set()
    completed=failed=0
    try:
        for n in range(instances):
            process=ctx.Process(target=worker,args=(settings,run_id,f'instance-{n+1:02d}',str(directory),duration_s,go,stop))
            process.start();children.append(process)
        ready_deadline=time.monotonic()+45
        while len(ready_ids)<instances:
            new=read_events(paths,offsets);events.extend(new)
            ready_ids.update(r['instance_id'] for r in new if r['event']=='worker_ready')
            if stop_file and Path(stop_file).exists():raise ValueError('MASTER_STOP_REQUESTED')
            if time.monotonic()>ready_deadline or any(r['event']=='worker_error' for r in new) or any(p.exitcode is not None for p in children):
                raise ValueError('WORKER_START_FAILED')
            if len(ready_ids)<instances:time.sleep(.05)
        coordinator.record('stage_start',instances=instances,max_inflight=instances*2,duration_s=duration_s,
                           failure_rate_limit=failure_rate_limit,stop_latency_s=stop_latency_s,
                           failure_denominator='completed_responses')
        started=time.monotonic();go.set();last_metric=started-5
        while len(done_ids)<instances:
            new=read_events(paths,offsets);events.extend(new)
            # Process timestamp order across process logs, not instance number.
            for row in sorted(new,key=lambda r:r.get('monotonic_at',float('inf'))):
                event=row['event']
                if event=='http_start':active[row['request_id']]=row
                elif event=='http_end':
                    active.pop(row['request_id'],None);completed+=1
                    failed+=row['status']!='success'
                    if row['elapsed_s']>stop_latency_s:reason='REQUEST_LATENCY_EXCEEDED'
                elif event=='worker_done':done_ids.add(row['instance_id'])
                elif event=='worker_error':reason='WORKER_ERROR'
            if completed and failed/completed>failure_rate_limit:reason='FAILURE_RATE_EXCEEDED'
            if any(time.monotonic()-r['monotonic_at']>stop_latency_s for r in active.values()):reason='REQUEST_LATENCY_EXCEEDED'
            if stop_file and Path(stop_file).exists():reason='MASTER_STOP'
            if any(p.exitcode not in (None,0) for p in children):reason='WORKER_ERROR'
            if time.monotonic()-started>duration_s+stop_latency_s+5:reason='STAGE_DRAIN_TIMEOUT'
            if reason:
                stop.set()
                coordinator.record('stage_stop',reason=reason,completed=completed,failures=failed,
                                   active_requests=len(active))
                stop_children(children)
                events.extend(read_events(paths,offsets))
                break
            if metric_future is not None and metric_future.done():
                try:coordinator.record('server_snapshot',**metric_future.result())
                except Exception as error:coordinator.record('metrics_unavailable',error_type=type(error).__name__)
                metric_future=None
            if metric_future is None and time.monotonic()-last_metric>=5:
                metric_future=metric_pool.submit(read_load,settings['memory_endpoint'],settings['memory_model'])
                last_metric=time.monotonic()
            if len(done_ids)<instances:time.sleep(.05)
        for process in children:process.join(timeout=1)
        starts={r['request_id']:r for r in events if r['event']=='http_start'}
        ends={r['request_id']:r for r in events if r['event']=='http_end'}
        unfinished=set(starts)-set(ends)
        for request_id in unfinished:
            coordinator.record('http_cancelled',request_id=request_id,instance_id=starts[request_id]['instance_id'],
                               reason=reason or 'WORKER_INCOMPLETE',input_tokens=None,output_tokens=None)
        if unfinished and reason is None:reason='WORKER_INCOMPLETE'
        result={'run_id':run_id,'instances':instances,'max_inflight':instances*2,
                'elapsed_s':round(time.monotonic()-started,3),'stopped':reason is not None,'stop_reason':reason,
                'submitted':len(starts),'success':sum(r['status']=='success' for r in ends.values()),
                'failures':sum(r['status']!='success' for r in ends.values()),'cancelled':len(unfinished),
                'worker_errors':sum(r['event']=='worker_error' for r in events),
                'failure_denominator':'completed_responses','failure_rate_limit':failure_rate_limit,
                'traces':[str(p) for p in paths],'operational_db_opened':False}
        coordinator.record('stage_end',**{k:v for k,v in result.items() if k!='run_id'})
        (directory/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
        return result
    finally:
        stop.set();go.set();stop_children(children)
        metric_pool.shutdown(wait=False,cancel_futures=True)


def run():
    control=json.loads(CONTROL.read_text())
    if control.get('approved') is not True:raise ValueError('MASTER_STAGE_ORDER_REQUIRED')
    if STOP_FILE.exists():raise ValueError('MASTER_STOP_REQUESTED')
    levels=control['instances']
    if not isinstance(levels,list) or not levels or any(type(n) is not int or not 1<=n<=16 for n in levels) or levels!=sorted(set(levels)):
        raise ValueError('INVALID_LOAD_LADDER')
    ROOT.mkdir(parents=True,exist_ok=True)
    with (ROOT/'synthetic-load.lock').open('a') as lock:
        try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:raise ValueError('LOAD_TEST_ALREADY_RUNNING') from None
        settings=json.loads(CONFIG.read_text())
        run_id='airag-multi-'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')+'-'+uuid.uuid4().hex[:6]
        results=[]
        for count in levels:
            if STOP_FILE.exists():break
            result=stage(settings,ROOT/run_id/f'{count:02d}-instances',count,
                         duration_s=control['duration_s'],stop_latency_s=control['stop_latency_s'],
                         failure_rate_limit=control['failure_rate_limit'],stop_file=STOP_FILE)
            results.append(result)
            print(json.dumps({'stage_finished':count,'success':result['success'],'failures':result['failures'],'stopped':result['stopped']}),file=sys.stderr,flush=True)
            if result['stopped'] or result['worker_errors']:break
        report={'run_id':run_id,'stages':results,
                'stopping_condition_reached':STOP_FILE.exists() or any(r['stopped'] for r in results),
                'interpretation':'configured stopping criterion, not proof of hardware capacity; compare M6 timeline separately'}
        (ROOT/run_id).mkdir(parents=True,exist_ok=True)
        (ROOT/run_id/'result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
        return report


def request_stop():
    STOP_FILE.parent.mkdir(parents=True,exist_ok=True)
    STOP_FILE.write_text(datetime.now(timezone.utc).isoformat()+'\n')
    return {'stop_requested':True,'marker':str(STOP_FILE)}


if __name__=='__main__':
    def interrupted(signum,frame):raise KeyboardInterrupt()
    signal.signal(signal.SIGTERM,interrupted)
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=('plan','run','stop'));args=parser.parse_args()
    try:
        data=json.loads(CONTROL.read_text()) if args.action=='plan' else request_stop() if args.action=='stop' else run()
        print(json.dumps({'ok':True,'data':data},ensure_ascii=False))
    except Exception as error:
        code=str(error)
        if not re.fullmatch(r'[A-Z][A-Z0-9_]{1,100}',code):code=type(error).__name__
        print(json.dumps({'ok':False,'error':{'code':code}},ensure_ascii=False));raise SystemExit(1)
