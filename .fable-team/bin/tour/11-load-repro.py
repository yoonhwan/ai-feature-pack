#!/usr/bin/env python3
from pathlib import Path
import runpy
from notebook import Cell,run_notebook

HERE=Path(__file__).resolve().parent
memory=runpy.run_path(str(HERE/'11-memory.py'))
PYTHON=memory['PYTHON']

def command(action):
    return [PYTHON,str(HERE/'load_repro.py'),action]

def gate(response,context):
    data=response['data']
    print('  master GO: '+('수신 완료' if data['ready'] else '아직 미수신 — 추론을 시작하지 않습니다.'))
    print('  요청 로그: '+data['trace'])

if __name__=='__main__':
    cells=[
        Cell('동시 재현 시작 신호','master의 GO airag를 확인합니다. 신호 뒤 사용자가 전체실행을 입력합니다.',command('gate'),gate,ready=lambda r,c:r['data']['ready']),
        Cell('남은 기억 배치 확인','기존 승인 범위와 완료/남은 배치를 확인합니다. 키는 기존 1Password 연결을 사용합니다.',command('inspect'),memory['inventory']),
        Cell('중단 배치 복구','프로젝트 잠금을 확보하고 저장 결과 없는 중단 배치만 복구합니다.',command('recover'),memory['recovered']),
        Cell('M6와 동시 기억 추출','부하 재현을 위해 이 투어에서만 혼잡 검사를 우회합니다. 최대2요청·실패 시 중단·완료분 재사용.',command('extract'),memory['extracted'],ready=lambda r,c:r['data']['extraction']['source_complete'],allow_auto_repeat=True,heartbeat_s=15,timeout_s=240),
        Cell('재실행 중복 확인','완료 범위에 새 모델 요청이 없는지 확인합니다.',command('extract'),memory['replay'],ready=lambda r,c:c.get('replay_verified',False)),
        Cell('기억 결과 정리','확인·검증 보류와 사용 가능한 기억을 구분합니다.',command('inspect'),memory['finish']),
    ]
    raise SystemExit(run_notebook('11-memory-load-repro','11 · M6 / AIRAG 동시 부하 재현',cells,
        introduction='준비 상태입니다. GO 신호를 알려드린 뒤 직접 전체실행을 입력하세요.\n요청 시각·응답 usage만 기록하며 본문·키는 로그에 남기지 않습니다.'))
