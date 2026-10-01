#!/usr/bin/env python3
"""Tour 03: review, install, configure and initialize the operational stores."""
from pathlib import Path
import re
import runpy
from notebook import Cell, run_notebook

HERE = Path(__file__).resolve().parent
BOOT = '/tmp/airag-installed-20260927/bin/python'
RUNTIME_PYTHON = Path.home() / '.local/share/airag/runtime/bin/python'
SETUP = HERE / 'deployment_setup.py'
operations = runpy.run_path(str(HERE / '02-operations.py'))


def command(action):
    return lambda context: [str(RUNTIME_PYTHON) if action in ('prepare', 'init', 'status') else BOOT, str(SETUP), action]


def keys(context, automatic):
    if not all(re.fullmatch(r'[0-9a-fA-F]{64}', context['env'].get(name, '')) for name in operations['NAMES']):
        operations['enter_keys'](context, False)


def show_plan(response, context):
    data = response['data']
    for label, field in [('프로젝트', 'project_id'), ('소유자', 'owner_id'), ('운영 데이터', 'project_root'),
                         ('설치 위치', 'runtime'), ('백업 위치', 'backup_root'), ('수집할 세션 파일', 'source')]:
        print(f'  {label}: {data[field]}')
    print('\n해설: 개인 프로젝트용 저장소를 새로 준비합니다. 원본은 읽기 전용으로 연결합니다.')
    print('      현재 모델·리비전을 유지하고, 연결 주소를 반영한 새 운영 프로필을 만듭니다.')


def show_install(response, context):
    print('설치 완료: ' + response['data']['runtime'])
    print('\n해설: 검증된 패키지를 임시 폴더 밖의 전용 실행 환경에 설치했습니다.')


def show_config(response, context):
    print('설정 파일: ' + response['data']['config'])
    print('원본 DB 불변: ' + ('확인' if response['data']['original_database_unchanged'] else '확인 필요'))
    print('\n해설: 설정에는 경로·프로필·권한 범위만 들어갑니다. 키 값은 저장하지 않습니다.')
    print('      입력 오류는 자동으로 건너뛰지 않는 설정입니다. 수집 전 검토는 다음 투어에서 합니다.')


def show_init(response, context):
    print('암호화 저장소 초기화: ' + ('완료' if response['data']['initialized'] else '확인 필요'))
    print('기존 투어 출처 연결: ' + str(response['data']['reference_source_count']) + '개')
    print('\n해설: 원장·검색 DB와 프로필을 준비했습니다. 실제 수집은 다음 투어에서 시작합니다.')


def show_status(response, context):
    data = response['data']
    for label, field in [('검색 창', 'indexed'), ('기억', 'visible_memories'), ('실패', 'failed'), ('대기', 'pending')]:
        print(f'  {label}: {data[field]}')
    print('  기존 문서 연결: ' + str(data['reference_source_count']) + '개')
    context['outcome'] = 'operational_stores_initialized'
    print('\n해설: 처음 초기화한 운영 저장소의 검색 창·기억은 0개가 정상입니다.')
    print('      다음은 입력 범위·오류 검토 후 첫 수집을 시작하는 투어입니다.')


if __name__ == '__main__':
    cells = [
        Cell('운영 구성안 확인', '저장 위치·소유자·수집할 세션을 먼저 확인합니다.', command('plan'), show_plan),
        Cell('저장한 키 다시 입력', '1Password에 보관한 동일한 세 키를 사용합니다. 전체실행도 필수 키 입력에서 기다립니다.',
             [BOOT, str(HERE / 'operations_check.py'), 'keys'], operations['show_keys'], keys, ready=lambda r,c:r['data']['ready']),
        Cell('전용 실행 환경 설치', '실행하면 ~/.local/share/airag/runtime에 검증된 CLI와 의존성을 설치합니다.', command('install'), show_install),
        Cell('운영 설정 준비', '실행하면 운영 경로에 설정 파일과 프로필 전용 DB를 만듭니다.', command('prepare'), show_config, keys),
        Cell('암호화 저장소 초기화', '실행하면 입력한 키로 운영 원장·검색 DB를 초기화합니다. 기존 원본·샘플을 보존합니다.', command('init'), show_init, keys),
        Cell('초기 상태 확인', '실제 운영 DB를 다시 열어 초기 상태와 기존 문서 연결을 확인합니다.', command('status'), show_status),
    ]
    raise SystemExit(run_notebook('03-initialize', '03 · 운영 설정과 초기화', cells,
        introduction='구성안 → 키 입력 → CLI 설치 → 설정 준비 → 암호화 DB 초기화 → 상태 확인\n키 값은 이 프로세스에서만 사용합니다. 1Password에 보관한 값을 사용하세요.'))
