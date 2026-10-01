#!/usr/bin/env python3
"""Tour 02: inspect policy, inject private runtime keys, and check readiness."""
import getpass
import sys
import warnings
from pathlib import Path
import re
from notebook import Cell, ask, run_notebook
from credentials import CredentialError, fill_environment

PYTHON = '/tmp/airag-installed-20260927/bin/python'
CHECK = Path(__file__).with_name('operations_check.py')
NAMES = ('AIRAG_CONSUMER_KEY_HEX', 'AIRAG_PROJECTION_KEY_HEX', 'AIRAG_ARCHIVE_KEY_HEX')


def check(action):
    return [PYTHON, str(CHECK), action]


def show_keys(response, context):
    data = response['data']
    for name, state in data['variables'].items():
        label = '형식 확인' if state['valid_format'] else '미설정' if not state['present'] else '형식 오류'
        print(f'  {name}: {label}')
    print('\n해설: 원장·검색 DB·아카이브는 서로 다른 32바이트 키를 사용합니다.')
    print('      키 값은 표시하지 않고, 실제 AIRAG 키 검증 함수를 사용합니다.')
    if data['validation_code'] == 'STORE_KEYS_MUST_BE_DISTINCT':
        print('      중복된 키가 있습니다. 세 키는 서로 달라야 합니다.')


def enter_keys(context, automatic):
    try:
        loaded = fill_environment(context['env'])
        if loaded:
            print('1Password 서비스 계정에서 운영 키를 불러왔습니다. 값은 출력하거나 저장하지 않습니다.')
        if all(re.fullmatch(r'[0-9a-fA-F]{64}', context['env'].get(name, '')) for name in NAMES):
            return
    except CredentialError as error:
        print('1Password 연결 확인 필요: ' + str(error))
    if automatic:
        print('전체실행에서는 비밀값 입력을 건너뛰고 현재 환경만 확인합니다.')
        return
    if not sys.stdin.isatty():
        print('숨김 키 입력에는 직접 조작하는 터미널이 필요합니다. 입력을 보류합니다.')
        return
    print('\n본인이 별도로 보관한 키를 입력하세요. 화면에 표시되지 않습니다.')
    print('준비되지 않았다면 Enter로 보류합니다. 자동으로 키를 만들지 않습니다.')
    print('입력은 이 투어의 자식 프로세스 환경에만 전달되며 파일·명령 기록에 남지 않습니다.')
    for name in NAMES:
        if re.fullmatch(r'[0-9a-fA-F]{64}', context['env'].get(name, '')):
            print(name + ': 기존 환경값 사용')
            continue
        while True:
            try:
                with warnings.catch_warnings():
                    warnings.simplefilter('error', getpass.GetPassWarning)
                    value = getpass.getpass(name + ' [64자리 hex / Enter로 보류] > ')
            except (EOFError, KeyboardInterrupt, getpass.GetPassWarning):
                print('\n키 입력을 보류합니다.')
                return
            if not value:
                break
            if not re.fullmatch(r'[0-9a-fA-F]{64}', value):
                print('형식 오류: 0–9, a–f로 구성된 64자리 값이 필요합니다.')
                continue
            context['env'][name] = value
            break


def show_policy(response, context):
    data = response['data']
    print(f'  활성 보관: 메시지 작성일부터 {data["active_retention_days"]}일')
    print('  아카이브: ' + data['archive_retention'])
    print('  백업 시각: ' + data['backup_time'])
    print('  백업 경로: ' + data['backup_root'])
    print('  복구용 백업: 최근 30일, 새 백업 검증 성공 후 오래된 백업 정리')
    print('  공유 범위: ' + data['sharing'])
    print('\n해설: 아카이브 무기한 보관과 복구용 백업 30일 보관은 서로 다른 정책입니다.')


def show_providers(response, context):
    for row in response['data']['providers']:
        print(f'  {row["service"]}: {"연결 정상" if row["ready"] else "연결 확인 필요"} · {row["endpoint"]}')
    print('\n해설: 현재 투어용 모델 연결을 확인한 결과입니다. 상시 운영 연결은 운영 설정에서 고정합니다.')


def show_readiness(response, context):
    data = response['data']
    context['outcome'] = 'configuration_ready' if data['ready_for_configuration'] else 'prerequisites_pending'
    print('  운영 키: ' + ('준비됨' if data['keys_ready'] else '준비 필요'))
    print('  모델 연결: ' + ('정상' if all(x['ready'] for x in data['providers']) else '확인 필요'))
    print('  다음 단계: ' + data['next'])
    print('\n해설: 이 투어는 운영 준비 점검입니다. 실제 DB 초기화·상시 실행은 다음 투어에서 진행합니다.')
    print('      직접 입력한 키는 이 프로세스 종료 시 해제됩니다. 본인의 별도 키 보관이 필요합니다.')


if __name__ == '__main__':
    cells = [
        Cell('운영 정책 확인', '이미 정한 보관·백업·공유 정책을 계약 파일에서 읽습니다.', check('policy'), show_policy),
        Cell('현재 키 준비 상태', '현재 실행 환경에 필요한 키가 있는지 확인합니다. 값은 출력하지 않습니다.', check('keys'), show_keys),
        Cell('운영 키를 환경으로 전달', '실행하면 보관 중인 키를 숨김 입력할 수 있습니다. 키가 없으면 보류해도 됩니다.', check('keys'), show_keys, enter_keys),
        Cell('모델 연결 확인', 'LLM과 임베딩 서버의 실제 모델 목록을 조회합니다.', check('providers'), show_providers),
        Cell('다음 단계 준비 판정', '키와 연결 상태를 합쳐 운영 설정 작성 단계로 넘어갈 준비를 확인합니다.', check('ready'), show_readiness),
    ]
    raise SystemExit(run_notebook('02-operations', '02 · 운영 준비', cells,
        introduction='정책 → 키 확인 → 숨김 키 입력 → 모델 연결 → 준비 판정\n준비되지 않은 항목은 보류로 표시하며, 자동으로 운영 시작을 선언하지 않습니다.'))
