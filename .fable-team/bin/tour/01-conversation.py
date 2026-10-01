#!/usr/bin/env python3
"""Tour 01: inspect and search the accepted encrypted sample."""
from pathlib import Path
import sys
from notebook import Cell, ask, run_notebook
from sample_output import status_output, search_output

CLIENT = Path(__file__).with_name('sample_client.py')


def command(*args):
    return [sys.executable, str(CLIENT), *args]


def status(response, context):
    context['status'] = response['data']
    status_output(response['data'])


def prepare_question(context, automatic):
    default = context.get('question', '대화 기록은 얼마 동안 활성 상태로 보관하나요?')
    if not automatic:
        value = ask(f'검색할 질문 [Enter = {default}] > ')
        if value.lower() in ('종료', 'quit', 'exit', 'q'):
            raise SystemExit(0)
        default = value or default
    context['question'] = default


def verify_command(context):
    ids = context.get('status', {}).get('verified_backup_ids', [])
    return command('verify', ids[-1] if ids else 'no-verified-backup')


if __name__ == '__main__':
    cells = [
        Cell('샘플 상태 살펴보기', '수집·검색·기억이 얼마나 준비됐는지 확인합니다.', command('status'), status),
        Cell('과거 결정 찾기', '백업 시각을 물어 과거 대화의 근거를 찾습니다.',
             command('search', '백업은 언제 실행하나요?', '--limit', '3'), lambda r,c: search_output(r['data'])),
        Cell('내 질문으로 검색', '실행하면 검색어를 입력할 수 있습니다.',
             lambda c: command('search', c.get('question', '대화 기록은 얼마 동안 활성 상태로 보관하나요?'), '--limit', '3'),
             lambda r,c: search_output(r['data']), prepare_question),
        Cell('백업을 실제로 검증', '기존 백업을 임시 경로에 복원해 무결성과 연결을 검사합니다.', verify_command,
             lambda r,c: print('백업 검증: ' + ('통과' if r['data'].get('verified') else '결과 확인 필요') + '\n해설: 격리 임시 복원으로 검사한 결과입니다.')),
        Cell('마지막 상태 확인', '투어 후 검색·기억과 실패/대기 상태를 확인합니다.', command('status'), status),
    ]
    raise SystemExit(run_notebook('01-conversation', '01 · 대화 검색과 백업', cells,
        introduction='검증 샘플을 실제 CLI로 조회합니다. 원문 검색·근거·백업을 차례로 확인합니다.'))
