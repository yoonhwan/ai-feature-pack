#!/usr/bin/env python3
"""Tour 04: inspect and collect a small authenticated source prefix."""
from pathlib import Path
import runpy
from notebook import Cell, run_notebook

HERE = Path(__file__).resolve().parent
PYTHON = str(Path.home() / '.local/share/airag/runtime/bin/python')
initialize = runpy.run_path(str(HERE / '03-initialize.py'))
operations = initialize['operations']


def command(action):
    return [PYTHON, str(HERE / 'first_collection.py'), action]


def show_preview(response, context):
    data = response['data']
    print('  원본: ' + data['source_path'])
    print(f'  유효한 대화: {data["public_messages"]}개')
    print(f'  선택 범위: 처음 {data["captured_byte_limit"]:,}바이트의 완성된 줄까지')
    print(f'  정책상 제외 기록: {data["excluded_records"]}개')
    print('\n해설: 도구 실행·메타데이터 등을 구분하고, 대화 4개에 해당하는 앞부분만 선택했습니다.')
    print('      이 범위에 거부 기록이 있으면 저장 전에 멈춥니다. 자동 건너뛰기는 꺼져 있습니다.')


def show_collect(response, context):
    data = response['data']
    context['last_collection'] = data
    print(f'  이번에 새로 저장: {data["inserted_events"]}건')
    print(f'  원장에 저장된 사건: {data["stored_events"]}건')
    print(f'  선택 범위 처리: {"완료" if data["receipt"]["complete_through_snapshot"] else "진행 중"}')
    print(f'  거부/누락 gap: {data["receipt"]["gap_count"]}건')
    print(f'  검색 발행 대기 창: {data["pending_windows"]}개')
    print('\n해설: 원문을 마스킹·검증해 암호화 원장에 저장하고, 검색할 문서 창을 준비했습니다.')
    print('      모델 호출과 색인은 아직 실행하지 않았습니다.')


def show_replay(response, context):
    data = response['data']
    if data['inserted_events'] != 0:
        print('재실행 결과: 추가 저장이 발생했습니다. raw 결과를 확인하세요.')
        context['outcome'] = 'replay_requires_review'
        return
    print('동일 범위 재실행: 새 저장 0건 · 중복 없음')
    print('원본 범위 해시: ' + ('동일' if data['selected_prefix_unchanged'] else '확인 필요'))
    print('\n해설: 이미 받은 데이터는 영수증과 체크포인트로 확인하므로 다시 쌓이지 않습니다.')
    context['outcome'] = 'bounded_collection_and_replay_verified'


def show_status(response, context):
    data = response['data']
    for label, field in [('검색 가능한 창', 'indexed'), ('검색 발행 대기', 'pending'), ('실패', 'failed'), ('기억', 'visible_memories')]:
        print(f'  {label}: {data[field]}')
    print('\n해설: 수집은 완료됐고 검색 발행은 대기 중입니다.')
    print('      다음 05번 투어에서 이 작은 범위만 색인하고 실제 질문으로 확인합니다.')
    print('      전체 세션의 나머지 구간은 아직 수집하지 않았습니다.')


if __name__ == '__main__':
    cells = [
        Cell('입력 범위와 오류 사전 확인', '기존 승인된 세션에서 처음 4개의 유효한 대화를 선택합니다. 원문 내용은 출력하지 않습니다.', command('preview'), show_preview),
        Cell('운영 키 다시 입력', '1Password의 기존 운영 키 3개를 사용합니다.',
             [PYTHON, str(HERE / 'operations_check.py'), 'keys'], operations['show_keys'], initialize['keys'], ready=lambda r,c:r['data']['ready']),
        Cell('선택한 범위 첫 수집', '실행하면 선택한 범위만 운영 암호화 원장에 저장합니다. 원본 파일은 변경하지 않습니다.', command('collect'), show_collect, initialize['keys']),
        Cell('같은 범위 재실행', '동일 요청을 다시 실행해 새 저장이 0건인지 확인합니다.', command('collect'), show_replay),
        Cell('수집 후 상태 확인', '수집 완료와 검색 발행 대기를 구분해 확인합니다.', command('status'), show_status),
    ]
    raise SystemExit(run_notebook('04-first-collection', '04 · 첫 수집과 중복 방지', cells,
        introduction='범위·오류 확인 → 키 입력 → 4개 대화 수집 → 중복 방지 확인 → 상태\n이번에는 수집과 문서 창 준비까지 진행합니다. 검색 색인은 다음 투어입니다.'))
