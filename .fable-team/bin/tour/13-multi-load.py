#!/usr/bin/env python3
"""Interactive preparation and explicitly ordered multi-process load ladder."""
from pathlib import Path
from notebook import Cell,run_notebook
HERE=Path(__file__).resolve().parent
PYTHON=str(Path.home()/'.local/share/airag/runtime/bin/python')

def command(action):return [PYTHON,str(HERE/'multi_load.py'),action]

def planned(response,context):
    d=response['data']
    print('  조정 세션 → 독립 AIRAG 테스트 프로세스 → 공유 LLM')
    for count in d['instances']:
        print(f'  {count}프로세스 × 2요청 = 최대 {count*2}동시 요청 · {d["duration_s"]}초')
    print('  한 단계가 끝난 뒤 다음 단계로 올라갑니다. 실패율 10% 초과·요청 60초 초과·STOP 중 하나면 전체 중단합니다.')
    print('  각 프로세스의 시각·토큰·지연을 별도 로그로 남깁니다. 운영 DB는 열지 않습니다.')
    print('  발주 상태: '+('실행 준비 완료' if d.get('approved') else '#71의 단계·시작 발주 대기'))

def finished(response,context):
    d=response['data']
    for stage in d['stages']:
        print(f'  {stage["instances"]}프로세스 / 최대 {stage["max_inflight"]}요청: 성공 {stage["success"]} · 실패 {stage["failures"]} · {stage["elapsed_s"]:.1f}초')
    print('  중단 기준 도달: '+('예 — 다음 단계 중단' if d['stopping_condition_reached'] else '아니오 — 시험 범위 내 완료'))
    print('  결과: '+str(HERE.parents[1]/'airag/traces'/d['run_id']/'result.json'))
    print('  M6 로그와 시각을 대조해야 실시간 발화에 미친 영향을 판정할 수 있습니다.')
    context['outcome']='multi_load_stopped_at_criterion' if d['stopping_condition_reached'] else 'multi_load_range_completed'

if __name__=='__main__':
    raise SystemExit(run_notebook('13-multi-load','13 · AIRAG 멀티 인스턴스 부하',[
        Cell('프로세스 수와 발주 확인','실제 GPU를 늘리는 대신 AIRAG 요청 프로세스를 늘립니다. #71 발주가 없으면 다음 셀로 넘어가지 않습니다.',command('plan'),planned,ready=lambda r,c:r['data'].get('approved') is True),
        Cell('단계별 멀티 부하','M6 시작 시각에 맞춰 전체실행을 입력하세요. 각 단계는 3분이며 진행 중 요청을 마친 뒤 다음 단계로 갑니다.',command('run'),finished,heartbeat_s=15,timeout_s=6000),
    ],introduction='준비 화면입니다. 자동으로 추론을 시작하지 않습니다.\n발주 확인 → 사용자 전체실행 → 단계별 증가 → 한계/범위 결과 확인'))
