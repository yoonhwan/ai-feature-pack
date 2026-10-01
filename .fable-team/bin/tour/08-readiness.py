#!/usr/bin/env python3
"""Tour 08: remaining-input review and unattended-operation policy."""
from pathlib import Path
import runpy
from notebook import Cell,run_notebook

HERE=Path(__file__).resolve().parent
PYTHON=str(Path.home()/'.local/share/airag/runtime/bin/python')
initialize=runpy.run_path(str(HERE/'03-initialize.py'))
operations=initialize['operations']


def command(action):return [PYTHON,str(HERE/'readiness.py'),action]


def status(response,context):
    data=response['data']
    print(f'  검색 창: {data["indexed"]}개 · 기억: {data["visible_memories"]}개')
    print(f'  검증 백업: {data["backup_count"]}개 · 실패: {data["failed"]}개')
    print('\n해설: 지금까지 만든 운영 데이터와 백업 상태입니다.')


def scanned(response,context):
    data=response['data'];context['scan_complete']=True
    for source in data['sources']:
        counts=source['counts']
        print(f'  아직 읽지 않은 범위: {source["remaining_bytes_at_start"]:,}바이트')
        print(f'  대화 후보: {counts.get("public_messages",0)}개 · 정책상 제외: {counts.get("excluded",0)}개')
        print(f'  거부 기록: {counts.get("rejected",0)}개 · 미완성 끝부분: {source["pending_partial_bytes"]}바이트')
        for reason,count in source['rejection_reasons'].items():
            print(f'    {reason}: {count}건')
            if reason=='AMBIGUOUS_INJECTED_BLOCK':
                print('    메타데이터 태그가 불완전해 본문과 안전하게 구분할 수 없는 기록입니다.')
    print('\n해설: 분류·마스킹 검사를 사전 실행한 결과이며, 아직 원장 저장이나 색인은 하지 않았습니다.')
    print('      거부된 기록은 원본을 보존한 채 다음 단계에서 사유와 범위를 검토해야 합니다.')


def policy(response,context):
    data=response['data']
    print(f'  입력 확인 주기: {data["poll_seconds"]}초')
    print('  색인 반영: 작업 완료·명시 저장·오래 열린 기록 5분')
    print('  백업: 한국시간 03:00, 꺼져 있었다면 다음 실행에서 1회 보충')
    print('  권한 범위: 같은 소유자·프로젝트의 명시 등록 세션')
    print('  오류 자동 건너뛰기: '+('켜짐' if data['allow_gaps'] else '꺼짐'))
    print('\n해설: 이 주기는 상시 프로세스가 실행 중일 때 적용됩니다. 이번 투어는 서비스를 시작하지 않습니다.')


def conclusion(response,context):
    data=response['data']
    print(f'  검토할 거부 기록: {data["rejected_records"]}건')
    print(f'  확인한 초기 처리 분량: {data["reviewed_backlog_bytes"]:,}바이트')
    if data['next']=='rejection_review':
        print('  다음 단계: 거부 기록의 사유·범위를 검토한 뒤 처리 정책 결정')
    elif data['next']=='bounded_initial_ingestion':
        print('  다음 단계: 확인된 범위의 초기 수집·색인')
    else:
        print('  다음 단계: 상시 실행 연결 검토')
    context['outcome']='operational_preflight_'+data['next']
    print('\n해설: 검토 결과만 기록했습니다. 거부 기록의 자동 승인이나 서비스 시작은 수행하지 않았습니다.')


if __name__=='__main__':
    cells=[
        Cell('운영 키 자동 연결','1Password에서 기존 키를 안전하게 전달합니다.',[PYTHON,str(HERE/'operations_check.py'),'keys'],operations['show_keys'],initialize['keys'],ready=lambda r,c:r['data']['ready']),
        Cell('현재 운영 상태','검색·기억·백업이 준비된 상태를 확인합니다.',command('status'),status),
        Cell('남은 입력과 거부 기록 검사','승인된 세션 파일의 남은 범위를 검사합니다. 원문 본문은 출력하지 않습니다.',command('scan'),scanned),
        Cell('자동 실행 정책 확인','수집·색인·백업 주기와 오류 처리 기본값을 확인합니다.',command('policy'),policy),
        Cell('다음 단계 판정','초기 처리와 거부 기록 검토 중 무엇이 필요한지 실제 결과로 확인합니다.',command('conclusion'),conclusion),
    ]
    raise SystemExit(run_notebook('08-readiness','08 · 남은 입력과 자동 실행 준비',cells,
        introduction='키 → 현재 상태 → 남은 입력 검사 → 정책 확인 → 다음 단계\n이번에는 검사만 합니다. 대량 색인이나 상시 서비스는 시작하지 않습니다.'))
