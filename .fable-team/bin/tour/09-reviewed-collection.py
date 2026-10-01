#!/usr/bin/env python3
"""Tour 09: explicit rejection acknowledgement and bounded raw collection."""
from pathlib import Path
import runpy
from notebook import Cell,ask,run_notebook

HERE=Path(__file__).resolve().parent
PYTHON=str(Path.home()/'.local/share/airag/runtime/bin/python')
initialize=runpy.run_path(str(HERE/'03-initialize.py'))
operations=initialize['operations']


def command(action,*args):return [PYTHON,str(HERE/'reviewed_collection.py'),action,*args]


def details(response,context):
    data=response['data']
    print(f'  검토한 범위: {data["from_offset"]:,} → {data["through_offset"]:,}바이트')
    print(f'  공개 대화 후보: {data["public_candidates"]}개')
    for item in data['rejections']:
        print(f'  거부 위치: {item["start"]:,}–{item["end"]:,} · {item["reason"]}')
        print('  기록 해시: '+item['sha256'])
    print('\n해설: 태그가 불완전해 안전하게 본문을 구분할 수 없는 기록입니다.')
    print('      원본 파일은 보존하고, 이 기록만 사유·해시를 감사 로그에 남긴 뒤 계속할 수 있습니다.')
    print('      검토 범위 이후의 새 기록과 다른 오류는 승인 범위가 아닙니다.')


def acknowledge(context,automatic):
    print('\n확인한 기록만 감사 gap으로 남기고 계속하려면 직접 «검토 승인»을 입력하세요.')
    value=ask('검토 승인 / Enter로 보류 / 종료 > ')
    if value.lower() in ('종료','q','quit','exit'):raise SystemExit(0)
    context['ack']=value=='검토 승인'


def approval(response,context):
    data=response['data']
    print('검토 승인: '+('기록됨' if data['approved'] else '보류'))
    if data['approved']:
        print(f'승인된 거부 기록: {data["rejected_records"]}건 · 끝 범위: {data["through_offset"]:,}바이트')
    print('\n해설: 전체 소스의 오류 자동 건너뛰기 설정은 바꾸지 않습니다.')


def collected(response,context):
    data=response['data'];receipt=data['receipt']
    context['collection_complete']=data['selected_snapshot_complete']
    print(f'  이번 새 저장: {data["inserted_events"]}건 · 누적 저장: {receipt["accepted_count"]}건')
    print(f'  처리 위치: {data["committed_offset"]:,} / {data["target_offset"]:,}바이트')
    print(f'  감사 gap: {receipt["gap_count"]}건')
    print('  선택 범위: '+('수집 완료' if data['selected_snapshot_complete'] else '남은 배치 있음'))
    if data['pending_windows'] is not None:print(f'  검색 발행 대기 창: {data["pending_windows"]}개')
    print('\n해설: 8MiB 이내로 나누어 저장합니다. 승인한 기록 한 줄에서만 제한적으로 건너뜁니다.')
    print('      그 밖의 오류는 중단하며 원본은 보존합니다. 이번 단계에는 모델 색인 호출이 없습니다.')


def final(response,context):
    data=response['data']
    for label,field in [('검색 가능한 창','indexed'),('발행 대기 창','pending'),('실패','failed'),('감사 gap','gaps')]:print(f'  {label}: {data[field]}')
    context['outcome']='reviewed_snapshot_collected' if context.get('collection_complete') else 'collection_incomplete'
    print('\n해설: 수집 범위 처리 완료와 무누락은 다릅니다. 승인한 gap은 계속 명시됩니다.')
    print('      다음 단계에서 새로 준비된 문서 창을 검색에 발행합니다.')


if __name__=='__main__':
    cells=[
        Cell('운영 키 자동 연결','1Password에서 기존 키를 프로세스 환경에 전달합니다.',[PYTHON,str(HERE/'operations_check.py'),'keys'],operations['show_keys'],initialize['keys'],ready=lambda r,c:r['data']['ready']),
        Cell('거부 기록의 위치·사유 확인','08번 검토 결과와 원본 해시를 다시 대조합니다.',command('details'),details),
        Cell('정확한 범위 검토 승인','승인한 거부 기록만 감사 gap으로 남길 수 있습니다. 전체실행도 직접 입력을 기다립니다.',lambda c:command('approve',*(['--ack'] if c.get('ack') else [])),approval,acknowledge,ready=lambda r,c:r['data']['approved']),
        Cell('검토한 범위 수집','한 번에 최대 8MiB를 처리합니다. 남은 배치는 같은 셀에서 Enter로 이어갑니다.',command('collect'),collected,ready=lambda r,c:r['data']['selected_snapshot_complete']),
        Cell('수집 결과 확인','누적 수집·감사 gap·검색 발행 대기를 구분합니다.',command('status'),final),
    ]
    raise SystemExit(run_notebook('09-reviewed-collection','09 · 거부 기록 검토와 범위 수집',cells,
        introduction='키 → 거부 기록 대조 → 직접 검토 승인 → 분할 수집 → 결과\n원본 삭제·오류 자동 건너뛰기 설정 변경·모델 색인은 하지 않습니다.'))
