#!/usr/bin/env python3
"""Tour 05: publish the first collected range and retrieve its evidence."""
from pathlib import Path
import runpy
from notebook import Cell, ask, run_notebook
from sample_output import search_output

HERE = Path(__file__).resolve().parent
PYTHON = str(Path.home() / '.local/share/airag/runtime/bin/python')
initialize = runpy.run_path(str(HERE / '03-initialize.py'))
operations = initialize['operations']


def command(action, *args):
    return [PYTHON, str(HERE / 'first_index.py'), action, *args]


def preflight(response, context):
    data = response['data']
    print(f'  수집된 사건: {data["stored_events"]}건 · 범위 {data["selected_bytes"]:,}바이트')
    print(f'  검색 대기 창: {data["pending_windows"]}개 · 검색 가능 창: {data["indexed_windows"]}개')
    print('  모델 연결: ' + ', '.join(row['service'] + ' 정상' for row in data['providers']))
    print('\n해설: 04번에서 저장한 범위와 모델 연결을 확인했습니다. 새 대화는 수집하지 않습니다.')


def indexed(response, context):
    data = response['data']
    print(f'  발행 시도: {data["attempted"]}개 · 성공: {data["succeeded"]}개')
    print(f'  검색 가능 창: {data["indexed_windows"]}개 · 대기: {data["pending_windows"]}개')
    print(f'  새 대화 수집: {data["new_events"]}건')
    print('\n해설: 준비한 문서를 청크·번역 보강·임베딩을 거쳐 검색에 발행했습니다.')


def question(context, automatic):
    default = context.get('query', '세션 확인')
    if not automatic:
        value = ask(f'검색할 질문 [Enter = {default}] > ')
        if value.lower() in ('종료', 'q', 'quit', 'exit'):
            raise SystemExit(0)
        default = value or default
    context['query'] = default


def searched(response, context):
    context['search_hits'] = len(response['data'].get('results', []))
    search_output(response['data'])
    print('      검색 범위는 처음 수집한 대화 4개입니다. 뒤쪽 대화의 질문은 아직 범위 밖입니다.')


def replay(response, context):
    data = response['data']
    context['index_replay_ok'] = data['attempted'] == 0 and data['new_events'] == 0 and data['new_jobs'] == 0
    print(f'  새 발행 시도: {data["attempted"]}개 · 새 작업: {data["new_jobs"]}개 · 새 대화: {data["new_events"]}건')
    print('\n해설: 이미 검색 가능한 창은 다시 색인하지 않습니다.')


def status(response, context):
    data = response['data']
    for label, field in [('검색 창', 'indexed'), ('대기', 'pending'), ('실패', 'failed'), ('기억', 'visible_memories')]:
        print(f'  {label}: {data[field]}')
    success = data['indexed'] > 0 and data['pending'] == 0 and data['failed'] == 0 and context.get('search_hits', 0) > 0 and context.get('index_replay_ok')
    context['outcome'] = 'first_index_and_search_verified' if success else 'results_require_review'
    print('\n해설: 원문 검색과 기억 추출은 별개입니다. 이번에는 검색까지 확인합니다.')
    print('      다음 투어에서 기억 후보와 자동 선정·확인 보류를 살펴봅니다.')


if __name__ == '__main__':
    cells = [
        Cell('운영 키 입력', '1Password의 기존 운영 키 3개를 사용합니다.',
             [PYTHON, str(HERE / 'operations_check.py'), 'keys'], operations['show_keys'], initialize['keys'], ready=lambda r,c:r['data']['ready']),
        Cell('범위와 모델 연결 확인', '04번에서 저장한 범위가 그대로인지, 모델이 연결됐는지 확인합니다.', command('preflight'), preflight),
        Cell('처음 수집한 대화 색인', '실행하면 이 작은 범위만 검색에 발행합니다. 모델 처리 동안 잠시 기다려 주세요.', command('index'), indexed),
        Cell('실제 질문으로 근거 찾기', '실행하면 질문을 입력할 수 있습니다. 처음 수집한 대화만 검색합니다.',
             lambda c: command('search', c.get('query', '세션 확인')), searched, question),
        Cell('같은 색인 다시 실행', '새 대화나 새 색인 작업이 생기지 않는지 확인합니다.', command('index'), replay),
        Cell('검색 상태 확인', '검색 가능한 창·대기·실패 상태를 확인합니다.', command('status'), status),
    ]
    raise SystemExit(run_notebook('05-first-search', '05 · 첫 색인과 질문 검색', cells,
        introduction='키 → 범위·연결 → 색인 → 질문 → 재실행 → 상태\n추가 수집과 기억 추출은 하지 않고, 04번의 작은 범위만 사용합니다.'))
