#!/usr/bin/env python3
"""Approve a reviewed snapshot and allow gaps only at individually approved records."""
import argparse
from dataclasses import asdict
from datetime import datetime,timezone
import hashlib
import json
from pathlib import Path
import re
import uuid

import first_collection as collection
from airag_consumer.collector import collect_codex_rollout
from airag_consumer.events import AccessScope

BATCH_BYTES=8_388_608


def digest(value):
    return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':')).encode()).hexdigest()


def reviewed(app):
    if app.config.allow_gaps:
        collection.fail('GLOBAL_GAP_POLICY_REQUIRES_REVIEW')
    document=json.loads((app.config.project_root/'tour-08-review.json').read_text())
    if len(document.get('sources',[]))!=1 or len(app.config.sources)!=1:collection.fail('SINGLE_REVIEWED_SOURCE_REQUIRED')
    review=document['sources'][0];source=app.config.sources[0]
    if (review['source_id'],review['source_path'])!=(source.source_id,str(source.path)):collection.fail('REVIEW_SOURCE_MISMATCH')
    start,end=review['from_offset'],review['reviewed_through']
    if type(start) is not int or type(end) is not int or not 0<=start<=end:collection.fail('INVALID_REVIEW_RANGE')
    info=source.path.stat()
    if (info.st_dev,info.st_ino)!=(review['device'],review['inode']):collection.fail('SOURCE_IDENTITY_CHANGED')
    hashed=hashlib.sha256();remaining=end
    with source.path.open('rb') as stream:
        while remaining:
            data=stream.read(min(remaining,1_048_576))
            if not data:collection.fail('SOURCE_TRUNCATED')
            hashed.update(data);remaining-=len(data)
    if hashed.hexdigest()!=review['prefix_sha256']:collection.fail('REVIEWED_SOURCE_CHANGED')
    gaps=review.get('rejection_examples',[])
    if review.get('rejection_examples_truncated') or len(gaps)!=document['rejected_total'] or len(gaps)!=review['counts'].get('rejected',0):collection.fail('INCOMPLETE_REJECTION_REVIEW')
    cursor=start
    with source.path.open('rb') as stream:
        for gap in sorted(gaps,key=lambda x:x['start']):
            if not cursor<=gap['start']<gap['end']<=end or gap['end']-gap['start']>1_048_577:collection.fail('INVALID_REJECTION_RANGE')
            if gap['reason']!='AMBIGUOUS_INJECTED_BLOCK':collection.fail('REJECTION_KIND_REQUIRES_SEPARATE_REVIEW')
            stream.seek(gap['start']);raw=stream.read(gap['end']-gap['start'])
            if not raw.endswith(b'\n') or raw.count(b'\n')!=1 or hashlib.sha256(raw).hexdigest()!=gap['sha256']:collection.fail('REJECTION_DIGEST_MISMATCH')
            cursor=gap['end']
    return review,sorted(gaps,key=lambda x:x['start'])


def write(path,value):
    if path.is_symlink():collection.fail('SYMLINK_RECEIPT_REJECTED')
    tmp=path.with_name(path.name+'.'+uuid.uuid4().hex+'.tmp')
    with tmp.open('x',encoding='utf-8') as stream:stream.write(json.dumps(value,ensure_ascii=False,indent=2)+'\n')
    tmp.chmod(0o600);tmp.replace(path)


def details(app):
    review,gaps=reviewed(app)
    return {'from_offset':review['from_offset'],'through_offset':review['reviewed_through'],
            'rejections':gaps,'public_candidates':review['counts'].get('public_messages',0),
            'source_preserved':True,'global_allow_gaps':app.config.allow_gaps,
            'indexing_started':False,'review_digest':digest(review)}


def approve(app,ack):
    review,gaps=reviewed(app)
    if not ack:return {'approved':False,'reason':'EXPLICIT_REVIEW_ACKNOWLEDGEMENT_REQUIRED'}
    receipt={'version':1,'review_digest':digest(review),'source_id':review['source_id'],
             'from_offset':review['from_offset'],'through_offset':review['reviewed_through'],
             'rejections':gaps,'acknowledged_at':datetime.now(timezone.utc).isoformat(),
             'scope':'only these record ranges and digests; no permission for later input',
             'source_deletion_authorized':False}
    write(app.config.project_root/'tour-09-approval.json',receipt)
    return {'approved':True,'rejected_records':len(gaps),'through_offset':review['reviewed_through'],'source_preserved':True}


def next_segment(cursor,end,gaps):
    for gap in gaps:
        if gap['start']<cursor<gap['end']:collection.fail('CURSOR_INSIDE_REJECTED_RECORD')
        if cursor==gap['start']:return gap['end'],True,gap
        if cursor<gap['start']:return min(gap['start'],cursor+BATCH_BYTES),False,None
    return min(end,cursor+BATCH_BYTES),False,None


def collect(app):
    with app._lock():
        review,gaps=reviewed(app)
        approval_path=app.config.project_root/'tour-09-approval.json'
        if not approval_path.is_file():collection.fail('REVIEW_APPROVAL_REQUIRED')
        approval=json.loads(approval_path.read_text())
        if approval.get('review_digest')!=digest(review) or approval.get('rejections')!=gaps:collection.fail('REVIEW_APPROVAL_MISMATCH')
        ledger=app._open_ledger()
        try:
            source=app.config.sources[0]
            row=ledger._con.execute('SELECT next_native_offset FROM airag_rollout_collector_sources WHERE source_id=?',(source.source_id,)).fetchone()
            if row is None or not review['from_offset']<=row[0]<=review['reviewed_through']:collection.fail('CHECKPOINT_OUTSIDE_APPROVED_REVIEW')
            cursor=row[0];before=ledger._con.execute('SELECT count(*) FROM events').fetchone()[0]
            limit,allow_gap,target=next_segment(cursor,review['reviewed_through'],gaps)
            receipt=collect_codex_rollout(ledger,source_path=source.path,allowed_real_paths=(source.path,),
                source_id=source.source_id,expected_session_id=source.session_id,
                expected_scope=AccessScope(app.config.tenant_id,app.config.project_id,source.session_id),
                captured_byte_limit=limit,expected_native_offset=cursor,allow_gaps=allow_gap,max_batch_bytes=BATCH_BYTES)
            allowed={(item['start'],item['end'],item['sha256'],item['reason']) for item in gaps}
            for gap in receipt.coverage_gaps:
                if review['from_offset']<=gap.start_offset<review['reviewed_through'] and (gap.start_offset,gap.end_offset,gap.native_sha256,gap.reason_code) not in allowed:
                    collection.fail('UNAPPROVED_GAP_DETECTED')
            if receipt.committed_native_offset==cursor and cursor<review['reviewed_through']:collection.fail('COLLECTION_MADE_NO_PROGRESS')
            reviewed(app)
            complete=receipt.committed_native_offset==review['reviewed_through']
            pending=None
            if complete:
                state=app._lifecycle(ledger).refresh(app.config.scope,explicit_save=True)
                pending=len(state['pending_publication_ids'])
            return {'inserted_events':ledger._con.execute('SELECT count(*) FROM events').fetchone()[0]-before,
                    'committed_offset':receipt.committed_native_offset,'target_offset':review['reviewed_through'],
                    'selected_snapshot_complete':complete,'receipt':asdict(receipt),'pending_windows':pending,
                    'approved_gap_segment':allow_gap,'global_allow_gaps_unchanged':not app.config.allow_gaps,
                    'model_calls':False,'source_preserved':True}
        finally:ledger.close()


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=('details','approve','collect','status'));parser.add_argument('--ack',action='store_true');args=parser.parse_args()
    try:
        app=collection.runtime()
        data=details(app) if args.action=='details' else approve(app,args.ack) if args.action=='approve' else collect(app) if args.action=='collect' else collection.status()
        print(json.dumps({'ok':True,'data':data},ensure_ascii=False))
    except Exception as error:
        code=getattr(error,'code',str(error))
        if not isinstance(code,str) or not re.fullmatch(r'[A-Z][A-Z0-9_]{1,100}',code):code=type(error).__name__
        print(json.dumps({'ok':False,'error':{'code':code}},ensure_ascii=False));raise SystemExit(1)
