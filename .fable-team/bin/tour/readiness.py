#!/usr/bin/env python3
"""Inspect the remaining authorized source before any unattended collection."""
import argparse
from collections import Counter
from datetime import datetime,timezone
import hashlib
import json
import os
import re
import time
from pathlib import Path
import uuid

import first_collection as collection
from airag_consumer.events import AccessScope,parse_event,EventError
from airag_consumer.redaction import redact_event
from airag_consumer.collector import _classify

MAX_SCAN_BYTES=128*1024*1024
MAX_RECORD_BYTES=1_048_576


def scan_source(source,scope,*,offset,last_ordinal,prefix_sha256):
    counts=Counter();reasons=Counter();rejections=[];digest=hashlib.sha256();started=time.monotonic()
    with source.path.open('rb') as stream:
        opened=os.fstat(stream.fileno());captured=opened.st_size
        if captured-offset>MAX_SCAN_BYTES:collection.fail('SOURCE_REQUIRES_PAGED_REVIEW')
        if offset<0 or offset>captured:collection.fail('INVALID_COLLECTOR_CHECKPOINT')
        remaining=offset
        while remaining:
            chunk=stream.read(min(remaining,1_048_576))
            if not chunk:collection.fail('SOURCE_TRUNCATED')
            digest.update(chunk);remaining-=len(chunk)
        if digest.hexdigest()!=prefix_sha256:collection.fail('SOURCE_PREFIX_CHANGED')
        start_offset=offset
        while offset<captured:
            if time.monotonic()-started>20:collection.fail('SOURCE_REVIEW_TIME_BOUND_REACHED')
            raw=stream.readline(min(MAX_RECORD_BYTES+2,captured-offset))
            if not raw.endswith(b'\n'):
                if len(raw)>MAX_RECORD_BYTES:collection.fail('RECORD_TOO_LARGE_REQUIRES_REVIEW')
                break
            if len(raw)-1>MAX_RECORD_BYTES:collection.fail('RECORD_TOO_LARGE_REQUIRES_REVIEW')
            end=offset+len(raw)
            item=_classify(raw[:-1],start=offset,end=end,expected_scope=scope,producer_epoch='readiness-preview',
                           first_seen_at=datetime.now(timezone.utc).isoformat(),last_ordinal=last_ordinal,allow_gaps=True)
            reason=None
            if item.ordinal is not None:last_ordinal=item.ordinal
            if item.disposition=='gap':reason=item.reason_code
            elif item.disposition=='skipped':counts['excluded']+=1
            else:
                try:
                    event=redact_event(parse_event(item.normalized,expected_scope=scope))
                    counts['accepted']+=1
                    counts['public_messages']+=int(event.has_public_text)
                except EventError as error:reason=str(error)
            if reason:
                counts['rejected']+=1;reasons[reason]+=1
                if len(rejections)<20:
                    rejections.append({'start':offset,'end':end,'reason':reason,'sha256':hashlib.sha256(raw).hexdigest()})
            digest.update(raw);offset=end
        current=source.path.stat()
        if (current.st_dev,current.st_ino)!=(opened.st_dev,opened.st_ino):collection.fail('SOURCE_IDENTITY_CHANGED')
    return {'source_id':source.source_id,'source_path':str(source.path),'device':opened.st_dev,'inode':opened.st_ino,
            'from_offset':start_offset,'reviewed_through':offset,'snapshot_bytes':captured,
            'remaining_bytes_at_start':captured-start_offset,'pending_partial_bytes':captured-offset,
            'prefix_sha256':digest.hexdigest(),'counts':dict(counts),'rejection_reasons':dict(reasons),
            'rejection_examples':rejections,'rejection_examples_truncated':counts['rejected']>len(rejections),
            'seconds':round(time.monotonic()-started,3),'source_modified':False,'automatic_skip_authorized':False}


def scan():
    app=collection.runtime();reports=[]
    with app._lock():
        ledger=app._open_ledger()
        try:
            for source in app.config.sources:
                row=ledger._con.execute('SELECT next_native_offset,last_ordinal,prefix_sha256,device,inode,tenant_id,project_id,expected_session_id FROM airag_rollout_collector_sources WHERE source_id=?',(source.source_id,)).fetchone()
                if row is None:collection.fail('FIRST_COLLECTION_REQUIRED')
                current=source.path.stat()
                if (str(current.st_dev),str(current.st_ino))!=(str(row[3]),str(row[4])):
                    collection.fail('SOURCE_IDENTITY_CHANGED')
                if tuple(row[5:])!=(app.config.tenant_id,app.config.project_id,source.session_id):
                    collection.fail('SOURCE_ENROLLMENT_MISMATCH')
                reports.append(scan_source(source,AccessScope(app.config.tenant_id,app.config.project_id,source.session_id),offset=row[0],last_ordinal=row[1],prefix_sha256=row[2]))
        finally:ledger.close()
    result={'sources':reports,'rejected_total':sum(x['counts'].get('rejected',0) for x in reports),
            'collection_started':False,'source_text_logged':False}
    path=app.config.project_root/'tour-08-review.json'
    temporary=path.with_name(path.name+'.'+uuid.uuid4().hex+'.tmp')
    with temporary.open('x',encoding='utf-8') as stream:stream.write(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    temporary.chmod(0o600);temporary.replace(path)
    return result


def status():
    app=collection.runtime();state=app.status()
    return {key:state[key] for key in ('indexed','visible_memories','pending','failed','backup_count','last_verified_backup','collector_sources')}


def policy():
    app=collection.runtime()
    return {'poll_seconds':app.config.poll_seconds,'flush':'task completion / explicit save / 5-minute open tail',
            'backup':'03:00 Asia/Seoul; one startup catchup','allow_gaps':app.config.allow_gaps,
            'source_count':len(app.config.sources),'sharing':'same owner/project and explicitly enrolled streams',
            'service_started_by_this_tour':False}


def conclusion():
    app=collection.runtime();path=app.config.project_root/'tour-08-review.json'
    if not path.is_file():collection.fail('COMPLETE_SOURCE_REVIEW_FIRST')
    report=json.loads(path.read_text());rejected=report['rejected_total']
    incomplete=any(x['pending_partial_bytes'] for x in report['sources'])
    backlog=sum(x['remaining_bytes_at_start'] for x in report['sources'])
    return {'rejected_records':rejected,'partial_tail':incomplete,'reviewed_backlog_bytes':backlog,
            'next':'rejection_review' if rejected else 'bounded_initial_ingestion' if backlog else 'service_start_review',
            'service_started':False,'automatic_skip_authorized':False,'review_file':str(path)}


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=('status','scan','policy','conclusion'));args=parser.parse_args()
    try:print(json.dumps({'ok':True,'data':globals()[args.action]()},ensure_ascii=False))
    except Exception as error:
        code=getattr(error,'code',str(error))
        if not isinstance(code,str) or not re.fullmatch(r'[A-Z][A-Z0-9_]{1,100}',code):code=type(error).__name__
        print(json.dumps({'ok':False,'error':{'code':code}},ensure_ascii=False));raise SystemExit(1)
