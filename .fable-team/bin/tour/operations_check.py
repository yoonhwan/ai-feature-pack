#!/usr/bin/env python3
"""Read-only operational readiness checks; never emits secret values."""
import argparse
import json
import os
from pathlib import Path
import re
import urllib.request
from airag_consumer.operations import KEY_NAMES, OperationsError, load_store_keys


def keys():
    fields = {name: {'present': bool(os.environ.get(name)),
                     'valid_format': bool(re.fullmatch(r'[0-9a-fA-F]{64}', os.environ.get(name, '')))}
              for name in KEY_NAMES.values()}
    try:
        load_store_keys(KEY_NAMES, os.environ)
        ready, code = True, None
    except OperationsError as error:
        ready, code = False, str(error)
    return {'variables': fields, 'ready': ready, 'validation_code': code,
            'values_printed': False, 'stores_created': False}


def providers():
    rows = []
    for label, port, expected in [('LLM', 18703, 'byz-llm'), ('임베딩', 18712, 'byz-embed')]:
        row = {'service': label, 'endpoint': f'http://127.0.0.1:{port}/v1', 'ready': False}
        try:
            with urllib.request.urlopen(row['endpoint'] + '/models', timeout=5) as response:
                data = json.load(response)
            row['ready'] = expected in [item.get('id') for item in data.get('data', [])]
        except Exception as error:
            row['error_type'] = type(error).__name__
        rows.append(row)
    return rows


def policy():
    root = Path(__file__).resolve().parents[3]
    contract = json.loads((root / 'feature-pack/rag/docs/artifacts/p08a01-contract.json').read_text())
    storage = contract['storage']
    return {'active_retention_days': storage['retention_target_days'],
            'archive_retention': '기한 없이 보관, 별도 요청으로 조회',
            'backup_time': storage['backup_policy']['schedule_time_and_timezone'],
            'backup_root': storage['backup_policy']['destination'],
            'backup_retention': storage['backup_policy']['backup_retention'],
            'key_owner': '사용자: 외부 보관과 복구 관리',
            'sharing': '같은 프로젝트의 본인 세션, 다른 프로젝트와 분리'}


parser = argparse.ArgumentParser()
parser.add_argument('action', choices=('keys', 'providers', 'policy', 'ready'))
args = parser.parse_args()
if args.action == 'keys':
    data = keys()
elif args.action == 'providers':
    data = {'providers': providers()}
elif args.action == 'policy':
    data = policy()
else:
    key_state, endpoints = keys(), providers()
    ready = key_state['ready'] and all(row['ready'] for row in endpoints)
    data = {'keys_ready': key_state['ready'], 'providers': endpoints,
            'ready_for_configuration': ready, 'deployment_started_by_this_tour': False,
            'next': '운영 설정 작성·초기화 투어' if ready else '미준비 항목을 채운 뒤 이 셀 재실행'}
print(json.dumps({'ok': True, 'data': data}, ensure_ascii=False))
