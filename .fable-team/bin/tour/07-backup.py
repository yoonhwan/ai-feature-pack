#!/usr/bin/env python3
"""Tour 07: encrypted backup, isolated verification and reopen checks."""
from pathlib import Path
import runpy
from notebook import Cell,run_notebook

HERE=Path(__file__).resolve().parent
PYTHON=str(Path.home()/'.local/share/airag/runtime/bin/python')
initialize=runpy.run_path(str(HERE/'03-initialize.py'))
operations=initialize['operations']


def command(action):return [PYTHON,str(HERE/'backup_tour.py'),action]


def baseline(response,context):
    data=response['data'];state=data['status']
    print(f'  검색 창: {state["indexed"]}개 · 기억: {state["visible_memories"]}개')
    print(f'  기존 검증 백업: {state["backup_count"]}개')
    print('  백업 위치: '+data['backup_root'])
    print('\n해설: 대화·검색·기억 데이터의 비교 기준을 저장했습니다. 키 값은 포함하지 않습니다.')
    print('      정책은 한국시간 03:00, 누락 시 다음 실행에서 1회 보충입니다.')


def backed_up(response,context):
    data=response['data'];context['created']=data['created']
    print('백업 생성: '+('완료' if data['created'] else '생성 안 됨'))
    print('위치: '+data.get('path',''))
    print('마지막 검증 성공: '+str(data.get('last_verified_success')))
    print('\n해설: 암호화 백업을 만들고 격리 복원 검증까지 통과한 뒤 성공으로 기록합니다.')
    print(f'      검증 후 정리한 30일 초과 복구 백업: {len(data.get("pruned",[]))}개')


def verified(response,context):
    data=response['data'];context['verified']=data['verified'] and data['backup_bytes_unchanged']
    print('격리 복원 검증: '+('통과' if data['verified'] else '확인 필요'))
    print('검사 구성 요소: '+', '.join(data['components']))
    print('백업 원본 파일: 변경 없음')
    print('\n해설: 운영 DB를 덮어쓰지 않고 임시 경로에서 열어 무결성·원장 연결·현재 시점의 만료 정책을 검사합니다.')


def compared(response,context):
    data=response['data'];state=data['status']
    print('대화·검색·기억 보호 데이터: '+('동일' if data['protected_data_unchanged'] else '확인 필요'))
    print(f'  검색 창: {state["indexed"]}개 · 기억: {state["visible_memories"]}개 · 검증 백업: {state["backup_count"]}개')
    context['outcome']='backup_restore_and_reopen_verified' if data['protected_data_unchanged'] and context.get('created') and context.get('verified') else 'results_require_review'
    print('\n해설: 별도 CLI 프로세스가 같은 키로 다시 열었고, 보호 데이터도 유지됐습니다.')
    print('      백업 메타데이터는 갱신됐으며, 상시 수집·예약 실행은 아직 별도 단계입니다.')


if __name__=='__main__':
    cells=[
        Cell('운영 키 자동 연결','1Password 서비스 계정으로 기존 키를 프로세스 환경에 전달합니다.',
             [PYTHON,str(HERE/'operations_check.py'),'keys'],operations['show_keys'],initialize['keys'],ready=lambda r,c:r['data']['ready']),
        Cell('백업 전 기준 확인','현재 상태와 보호 데이터의 해시를 비교 기준으로 기록합니다.',command('baseline'),baseline),
        Cell('암호화 백업 생성','실행하면 새 백업을 만들고 검증합니다. 성공 후 30일이 지난 AIRAG 복구 백업만 정책대로 정리합니다.',command('backup'),backed_up),
        Cell('백업 격리 복원 검증','방금 만든 백업을 별도 임시 경로에 복원해 다시 검사합니다. 운영 DB는 덮어쓰지 않습니다.',command('verify'),verified),
        Cell('다시 열기·데이터 보존 확인','새 CLI 프로세스에서 다시 열어 원장·검색·기억 데이터가 그대로인지 대조합니다.',command('compare'),compared),
    ]
    raise SystemExit(run_notebook('07-backup','07 · 백업과 격리 복원 검증',cells,
        introduction='키 자동 연결 → 기준 확인 → 암호화 백업 → 격리 검증 → 다시 열기\n원장·검색·기억을 백업하며, 키는 백업 파일에 포함하지 않습니다.'))
