#!/usr/bin/env python3
from pathlib import Path
from notebook import Cell,run_notebook
HERE=Path(__file__).resolve().parent
PYTHON=str(Path.home()/'.local/share/airag/runtime/bin/python')

def command(action):return [PYTHON,str(HERE/'synthetic_load.py'),action]

def planned(response,context):
    print('  공개 합성 대화 · 동시 최대 2요청 · 새 요청 발송 3분')
    print('  최대 120요청 · 오류 시 새 요청 중단 · 진행 중 요청은 최대 120초 대기')
    print('  운영 DB·기억·검색 색인은 열거나 변경하지 않습니다.')
    print('  M6 발화를 준비한 뒤 전체실행으로 진행하세요.')

def finished(response,context):
    d=response['data'];context['outcome']='synthetic_load_finished'
    print(f'  성공 {d["success"]}건 · 실패 {d["failures"]}건 · 총 {d["elapsed_s"]:.1f}초')
    print(f'  입력 {d["input_tokens"]} / 출력 {d["output_tokens"]}토큰 · 사용량 미수신 {d["missing_usage"]}건')
    print(f'  가장 긴 요청: {d["max_request_s"]:.1f}초')
    print('  요청 로그: '+d['trace'])
    print('  M6 로그와 실제 요청 시각을 대조해야 동시 부하 여부를 판정할 수 있습니다.')

if __name__=='__main__':
    raise SystemExit(run_notebook('12-synthetic-load','12 · 3분 연속 부하 재현',[
        Cell('부하 범위 확인','운영 데이터 대신 별도 합성 대화를 모델에 반복 전송합니다.',command('plan'),planned),
        Cell('3분 부하 실행','M6와 함께 실행하세요. 기존 완료분 재사용 없이 실제 모델 요청을 반복합니다.',command('run'),finished,heartbeat_s=15,timeout_s=330),
    ],introduction='직접 전체실행을 입력하면 시작합니다. 동시2개를 유지하며 3분 동안 새 요청을 보냅니다.\n진행 중 요청 마무리까지 최대 5분이 걸릴 수 있습니다. 자동으로 시작하지 않습니다.'))
