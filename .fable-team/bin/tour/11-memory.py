#!/usr/bin/env python3
"""Tour 11: resume independent memory batches with bounded parallel inference."""
from pathlib import Path
import runpy
from notebook import Cell, run_notebook

HERE=Path(__file__).resolve().parent
PYTHON=str(Path.home()/'.local/share/airag/runtime/bin/python')
initialize=runpy.run_path(str(HERE/'03-initialize.py'))
operations=initialize['operations']
KINDS={'decision':'결정','progress':'진행 상태','verified_solution':'해결책','preference':'장기 선호','instruction_quote':'지침 후보'}
STATES={'materialized':'기억 반영','awaiting_confirmation':'사용자 확인 대기','unverified':'근거 검증 대기','conflict':'충돌 보류','rejected':'거부','pending_materialization':'반영 대기'}


def command(action):
    return [PYTHON,str(HERE/'reviewed_memory.py'),action]


def inventory(response,context):
    data=response['data']
    print(f'  검색 가능한 창: {data["indexed_windows"]}개')
    print(f'  사용 가능한 기억: {data["visible_memories"]}개')
    progress=data['progress']
    context['last_completed']=progress['completed_batches']
    print(f'  기억 배치: {progress["completed_batches"]}/{progress["total_batches"]} 완료 · 남음 {progress["remaining_batches"]}개 · 실패 {progress["failed_batches"]}개')
    print('  병렬 요청: 최대 2개 · 완료된 배치는 재사용')
    if progress['remaining_batches']:
        print('  남은 시간: 실행 후 실제 처리 속도로 추정합니다.')
    if not data['candidate_groups']:
        print('  아직 기억 후보가 없거나, 남길 내용이 없는 범위입니다.')
    for row in data['candidate_groups']:
        print(f'  {KINDS.get(row["kind"],row["kind"])} / {STATES.get(row["disposition"],row["disposition"])}: {row["count"]}개')
    print('\n해설: 원문 검색은 기억 선정과 별개로 계속 가능합니다.')
    print('      결정·진행은 자동 선정하고, 장기 선호·지침은 확인받으며 해결책은 검증 근거가 필요합니다.')


def recovered(response,context):
    data=response['data']
    print(f'  중단 배치 복구: {data["recovered_batches"]}개 · 모델 호출 없음')
    print('  실행 잠금 확보 후 결과가 저장되지 않은 pending 배치만 재시도 대상으로 전환했습니다.')
    print('  완료된 기억과 확인·검증 대기는 보존합니다.')


def extracted(response,context):
    data=response['data'];result=data['extraction']
    context['source_complete']=result['source_complete']
    progress=result['progress']
    completed=progress['completed_batches']
    delta=completed-context.get('last_completed',completed)
    context['last_completed']=completed
    samples=context.setdefault('timing_samples',[])
    if delta>0:
        samples.append((result['elapsed_s'],delta))
        del samples[:-5]
    print(f'  기억 배치: {completed}/{progress["total_batches"]} 완료 · 남음 {progress["remaining_batches"]}개')
    print(f'  이번 모델 요청: {result["provider_requests"]}개 · 동시 최대 {result["concurrency"]}개 · {result["elapsed_s"]:.1f}초')
    if samples and progress['remaining_batches']:
        seconds=sum(t for t,n in samples)/sum(n for t,n in samples)*progress['remaining_batches']
        print(f'  남은 예상 시간: 약 {seconds/60:.1f}분 (최근 실측 기준, 서버 지연에 따라 변동)')
    print(f'  이번 배치 후보: {result["candidate_count"]}개')
    print(f'  기억 반영: {result["materialized_count"]}개')
    print(f'  사용자 확인 대기: {result["awaiting_confirmation_count"]}개 · 근거 검증 대기: {result["unverified_count"]}개')
    print('  입력 범위 처리: '+('완료' if result['source_complete'] else '남은 배치 있음'))
    print(f'  새 대화 수집: {data["new_events"]}건')
    print('\n해설: 모델이 고른 후보를 원문 근거와 연결해 검사한 결과입니다.')
    print('      후보 0개도 정상입니다. 기억할 내용이 없을 때 억지로 만들지 않습니다.')


def replay(response,context):
    data=response['data'];result=data['extraction']
    good=result['source_complete'] and not result['provider_called'] and data['new_visible_memories']==0 and data['new_events']==0
    context['replay_verified']=good
    print('  새 모델 호출: '+('있음' if result['provider_called'] else '없음'))
    print(f'  새 기억: {data["new_visible_memories"]}개 · 새 대화: {data["new_events"]}건')
    print('\n해설: 처리가 끝난 범위는 모델을 다시 호출하거나 같은 기억을 중복 생성하지 않습니다.')


def finish(response,context):
    inventory(response,context)
    context['outcome']='reviewed_memory_selection_verified' if context.get('source_complete') and context.get('replay_verified') else 'results_require_review'
    print('      이번 투어는 확인 대기 후보를 승인하지 않습니다. 기존 감사 gap 1건은 유지되며 상시 수집은 별도 단계입니다.')


if __name__=='__main__':
    cells=[
        Cell('운영 키 자동 연결','1Password에 저장한 기존 키 3개를 사용합니다.',[PYTHON,str(HERE/'operations_check.py'),'keys'],operations['show_keys'],initialize['keys'], ready=lambda r,c:r['data']['ready']),
        Cell('검색과 기억의 현재 상태','10번에서 발행한 승인 범위와 현재 기억 수를 확인합니다.',command('inspect'),inventory),
        Cell('중단 배치 복구','프로젝트 실행 잠금을 확보한 뒤 중단된 요청만 재시도 가능 상태로 바꿉니다. 다른 실행이 있으면 거부합니다.',command('recover'),recovered),
        Cell('기억 후보 추출','기존 배치당 최대 4개를 유지하고 모델 요청 2개를 병렬 처리합니다. 전체실행은 남은 배치를 이어가며 오류 시 멈춥니다.',command('extract'),extracted,ready=lambda r,c:r['data']['extraction']['source_complete'],allow_auto_repeat=True,heartbeat_s=15,timeout_s=240),
        Cell('자동 선정과 보류 구분','실제로 생성된 후보의 종류와 반영·보류 상태를 확인합니다.',command('inspect'),inventory),
        Cell('같은 기억 처리 재실행','완료된 범위의 모델 호출과 새 기억 생성이 0인지 확인합니다.',command('extract'),replay,ready=lambda r,c:c.get('replay_verified',False),heartbeat_s=15,timeout_s=240),
        Cell('기억 상태 정리','사용 가능한 기억과 확인·검증 대기를 구분합니다.',command('inspect'),finish),
    ]
    raise SystemExit(run_notebook('11-memory','11 · 승인 범위의 기억 확장',cells,
        introduction='키 → 현재 상태 → 중단 복구 → 후보 추출 → 분류 → 재실행 → 정리\n승인 범위만 처리합니다. 모델 요청 최대 2개·DB 저장 순차 처리. 완료 배치를 재사용합니다.\n새 대화 수집·자동 확인 승인은 하지 않습니다. 후보 0개도 정상입니다.'))
