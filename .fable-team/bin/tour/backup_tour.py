#!/usr/bin/env python3
"""Create/verify a backup and compare protected operational data."""
import argparse
import hashlib
import json
import re
import uuid
from pathlib import Path
import first_collection as collection

CONSUMER_TABLES = ('events','records','sources','deliveries','rejections',
                   'airag_memory_candidates','airag_memory_extractions',
                   'airag_lifecycle_memories','airag_lifecycle_windows')
PROJECTION_TABLES = ('sources','source_revisions','jobs','generations','chunks')


def table_digests(connection, names):
    present={row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    output={}
    for name in names:
        if name not in present:
            continue
        rows=connection.execute(f'SELECT * FROM "{name}"').fetchall()
        encoded=sorted(json.dumps([{'blob':value.hex()} if isinstance(value,bytes) else value for value in row],
                                  ensure_ascii=False,separators=(',',':')) for row in rows)
        output[name]={'rows':len(rows),'sha256':hashlib.sha256('\n'.join(encoded).encode()).hexdigest()}
    return output


def snapshot(app):
    with app._lock():
        ledger=app._open_ledger();projection=None
        try:
            projection=app._open_projection()
            return {'consumer':table_digests(ledger._con,CONSUMER_TABLES),
                    'projection':table_digests(projection,PROJECTION_TABLES)}
        finally:
            if projection is not None:projection.close()
            ledger.close()


def write(path,data):
    if path.is_symlink():collection.fail('SYMLINK_RECEIPT_REJECTED')
    tmp=path.with_name(path.name+'.'+uuid.uuid4().hex+'.tmp')
    with tmp.open('x',encoding='utf-8') as stream:stream.write(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    tmp.chmod(0o600);tmp.replace(path)


def status_counts(app):
    state=app.status()
    return {key:state[key] for key in ('indexed','visible_memories','pending','failed','backup_count','verified_backup_ids','last_verified_backup')}


def work(action):
    app=collection.runtime()
    baseline_path=app.config.project_root/'tour-07-baseline.json'
    receipt_path=app.config.project_root/'tour-07-backup.json'
    if action=='baseline':
        state=status_counts(app)
        write(baseline_path,{'protected_data':snapshot(app),'before_status':state})
        return {'status':state,'backup_root':str(app.config.backup_root),'captured':True,
                'policy':'03:00 Asia/Seoul; startup catchup once; verified recovery backups retained 30 days'}
    if not baseline_path.is_file():collection.fail('CAPTURE_BACKUP_BASELINE_FIRST')
    if action=='backup':
        result=app.backup(force=True)
        write(receipt_path,result)
        return result
    if not receipt_path.is_file():collection.fail('CREATE_TOUR_BACKUP_FIRST')
    receipt=json.loads(receipt_path.read_text())
    path=Path(receipt['path'])
    if path.parent!=app.config.backup_root:collection.fail('BACKUP_RECEIPT_SCOPE_MISMATCH')
    if action=='verify':
        files=list(path.glob('*.bin'))
        if not files:collection.fail('BACKUP_COMPONENTS_MISSING')
        before={file.name:hashlib.sha256(file.read_bytes()).hexdigest() for file in files}
        result=app.verify_backup(path.name)
        unchanged=all(hashlib.sha256((path/name).read_bytes()).hexdigest()==digest for name,digest in before.items())
        if not unchanged:collection.fail('BACKUP_BYTES_CHANGED_DURING_VERIFICATION')
        return {**result,'backup_bytes_unchanged':True,'restore_destination':'isolated temporary directory'}
    if action=='compare':
        baseline=json.loads(baseline_path.read_text())
        same=snapshot(app)==baseline['protected_data']
        return {'protected_data_unchanged':same,'status':status_counts(app),
                'new_process_reopen':True,'automatic_collection_started':False}
    collection.fail('UNKNOWN_TOUR_ACTION')


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('action',choices=('baseline','backup','verify','compare'))
    args=parser.parse_args()
    try:
        data=work(args.action)
        failed=data.get('protected_data_unchanged') is False
        print(json.dumps({'ok':not failed,'data':data,**({'error':{'code':'PROTECTED_DATA_CHANGED'}} if failed else {})},ensure_ascii=False))
        raise SystemExit(1 if failed else 0)
    except Exception as error:
        code=getattr(error,'code',str(error))
        if not isinstance(code,str) or not re.fullmatch(r'[A-Z][A-Z0-9_]{1,100}',code):code=type(error).__name__
        print(json.dumps({'ok':False,'error':{'code':code}},ensure_ascii=False))
        raise SystemExit(1)
