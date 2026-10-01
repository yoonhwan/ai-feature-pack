#!/usr/bin/env python3
"""Tour 14: back up first, then approve, reject or verify waiting memory candidates one by one."""
import json
import os
from pathlib import Path
import runpy
import subprocess
import uuid
from notebook import Cell, ask, run_notebook

HERE = Path(__file__).resolve().parent
PYTHON = str(Path.home() / '.local/share/airag/runtime/bin/python')
HELPER = str(HERE / 'memory_confirmation.py')
PAGE = 10
SHOW = 240
initialize = runpy.run_path(str(HERE / '03-initialize.py'))
operations = initialize['operations']
KINDS = {'preference': '장기 선호', 'instruction_quote': '지침 후보', 'verified_solution': '해결책'}


def helper(*arguments):
    return [PYTHON, HELPER, *arguments]


def clip(text):
    text = ' '.join(str(text).split())
    return text if len(text) <= SHOW else text[:SHOW] + '…'


def inventory(response, context):
    data = response['data']
    print(f'  사용자 확인 대기(지침·선호): {data["awaiting_confirmation"]}개')
    print(f'  근거 검증 대기(해결책): {data["unverified"]}개')
    print(f'  사용 가능한 기억: {data["visible_memories"]}개 · 검증된 백업 {data["backup_count"]}개')
    print('  자동 승인: 없음 (이 투어는 사용자가 고른 번호만 처리합니다)')
    print('\n해설: 후보는 모델이 원문에서 고른 것이고, 기억으로 쓰려면 사용자 결정이 필요합니다.')
    print('      결정을 쓰기 전에 다음 셀에서 백업을 만들고 검증합니다.')


def backed_up(response, context):
    data = response['data']
    context['backup_ok'] = bool(data['verified'])
    print(f'  백업 ID: {data["backup_id"]}')
    print(f'  격리 복원 검증: {"통과" if data["verified"] else "실패"} · 구성 {len(data["components"])}개')
    before = data['before']
    print(f'  백업 시점: 확인 대기 {before["awaiting_confirmation"]} · 검증 대기 {before["unverified"]} · 기억 {before["visible_memories"]}개')
    print('\n해설: 이 백업이 승인한 기억을 되돌리는 유일한 안전망입니다. 검증이 통과해야 다음 셀의 결정이 열립니다.')


def review(state, label):
    def prepare(context, automatic):
        context['decision'] = {'approve': [], 'verify': [], 'reject': []}
        context['page'] = []
        skip = context.setdefault('skip', {}).get(state, 0)
        done = subprocess.run([str(x) for x in helper('candidates', '--state', state, '--skip', str(skip), '--limit', str(PAGE))],
                              env=context['env'], text=True, capture_output=True, timeout=60)
        try:
            response = json.loads(done.stdout)
        except ValueError:
            response = {'ok': False}
        if not response.get('ok'):
            print('  후보를 읽지 못했습니다:', response.get('error', {}).get('code', 'UNKNOWN'))
            return
        data = response['data']
        context['page'] = [item['candidate_id'] for item in data['candidates']]
        context['remaining'] = data['total'] - skip
        if not data['candidates']:
            print(f'  검토할 {label} 후보가 없습니다.')
            return
        print(f'\n  {label} 후보 {len(data["candidates"])}개 표시 (남은 대기 {context["remaining"]}개)')
        for number, item in enumerate(data['candidates'], 1):
            kind = KINDS.get(item['kind'], item['kind'])
            if not item['source_current']:
                print(f'\n  [{number}] {kind} · 원문이 활성 기간 밖이거나 바뀜 — 본문·인용을 숨깁니다(승인·검증 불가, 거절만 가능)')
                continue
            print(f'\n  [{number}] {kind} · 원문 변경 없음')
            print(f'      기억 본문: {clip(item["text"])}')
            for quote in item['supporting_quotes']:
                print(f'      원문 인용: {clip(quote["quote"])}')
            for message in item['proof_messages']:
                print(f'      성공 근거({message["role"]}): {clip(message["text"])}')
        positive = '승인' if state == 'awaiting_confirmation' else '검증됨 확정'
        for key, name in (('approve' if state == 'awaiting_confirmation' else 'verify', positive), ('reject', '거절')):
            context['decision'][key] = pick(f'\n  {name}할 번호(쉼표로 여러 개, 없으면 Enter=보류) > ', context['page'])
        overlap = set(context['decision']['approve'] + context['decision']['verify']) & set(context['decision']['reject'])
        if overlap:
            print('  같은 후보를 승인과 거절에 모두 넣어 둘 다 보류합니다.')
            context['decision'] = {'approve': [], 'verify': [], 'reject': []}

    return prepare


def pick(prompt, page):
    while True:
        raw = ask(prompt)
        if not raw:
            return []
        try:
            numbers = [int(part) for part in raw.replace(' ', '').split(',') if part]
            if numbers and all(1 <= number <= len(page) for number in numbers):
                return [page[number - 1] for number in dict.fromkeys(numbers)]
        except ValueError:
            pass
        print(f'  1~{len(page)} 사이 번호를 쉼표로 입력하세요.')


def decision_command(context):
    decision = context.get('decision', {})
    command = helper('decide')
    for key in ('approve', 'verify', 'reject'):
        if decision.get(key):
            command += [f'--{key}', ','.join(decision[key])]
    return command


def decided(response, context):
    data = response['data']
    names = {'approve': '승인', 'verify': '검증 확정', 'reject': '거절'}
    if data['noop']:
        print('  아무것도 고르지 않아 쓰지 않았습니다. (전부 보류)')
    for row in data['results']:
        outcome = row['state'] if row['state'] != 'error' else '오류 ' + row['code']
        print(f'  {names[row["action"]]} → {outcome}' + (f' ({row["reason"]})' if row.get('reason') else ''))
    left = sum(1 for row in data['results'] if row['state'] in ('materialized', 'rejected'))
    skip = context.setdefault('skip', {})
    state = context['state_now']
    skip[state] = skip.get(state, 0) + len(context['page']) - left
    if not data['log_complete']:
        print('  ⚠ 결정은 코어에 적용됐지만 결과 기록 갱신에 실패했습니다. 의도 기록(tour-14-decisions.json)은 남아 있습니다.')
    print(f'  현재 기억 {data["status"]["visible_memories"]}개 · 확인 대기 {data["status"]["awaiting_confirmation"]} · 검증 대기 {data["status"]["unverified"]}')
    print('\n해설: 번호로 고른 후보만 처리했습니다. 보류한 후보는 그대로 남고, 거절한 후보는 다시 승인할 수 없습니다.')
    print('      남은 후보는 이 셀을 재실행하면 이어서 보여 줍니다.')


def review_cell(state, title, explanation):
    def mark(context, automatic):
        context['state_now'] = state
        review(state, '지침·선호' if state == 'awaiting_confirmation' else '해결책')(context, automatic)
    return Cell(title, explanation, decision_command, decided, mark, requires_enter=True)


def summary(response, context):
    data = response['data']
    before, now = data['before'], data['now']
    print(f'  기억: {before["visible_memories"]}개 → {now["visible_memories"]}개')
    print(f'  확인 대기: {before["awaiting_confirmation"]} → {now["awaiting_confirmation"]} · 검증 대기: {before["unverified"]} → {now["unverified"]}')
    for key, value in sorted(data['decisions'].items()):
        print(f'  이번 결정 {key}: {value}건')
    context['outcome'] = 'memory_confirmation_reviewed'
    print(f'  기준 백업: {data["backup_id"]}')
    print('\n해설: 숫자는 코어 상태와 대조한 값입니다. 남은 대기 후보는 다음에 이어서 검토할 수 있습니다.')


def rollback(response, context):
    data = response['data']
    print('  승인·검증으로 만든 기억을 개별로 되돌리는 기능은 코어에 없습니다.')
    print('  (해결책에는 reopen_solution 이 있으나 CLI·런타임에 노출되지 않았고, 거절은 번복할 수 없습니다.)')
    print(f'  되돌리려면 이 투어 첫머리에 만든 백업 {data["backup_id"]} 로 복원합니다. 직접 하는 절차:')
    print('    1) AIRAG 프로세스를 멈춘다(실행 중이면 잠금 때문에 복원 후에도 충돌).')
    print(f'    2) 현재 DB를 지우지 말고 이름만 바꿔 보관: {data["consumer_db"]} · {data["projection_db"]}')
    print(f'    3) 백업 세트({data["backup_path"]})의 consumer.bin·projection.bin 을 위 DB 경로로 복사한다.')
    print('    4) status 로 기억 수가 백업 시점과 같은지 확인한다.')
    print('  이 투어는 복원을 대신 실행하지 않습니다. 복원하면 백업 이후의 모든 변경도 함께 사라집니다.')
    print('\n해설: 되돌릴 수 있는지보다 «승인 전 백업이 검증되었는지»가 안전의 핵심입니다.')


def build_cells():
    return [
        Cell('운영 키 자동 연결', '1Password에 저장한 기존 키 3개를 사용합니다.',
             [PYTHON, str(HERE / 'operations_check.py'), 'keys'], operations['show_keys'], initialize['keys'],
             ready=lambda r, c: r['data']['ready']),
        Cell('후보 현황', '확인 대기와 근거 검증 대기 후보의 수를 읽기만 합니다.', helper('inspect'), inventory),
        Cell('백업 생성과 검증', '운영 저장소에 새 백업을 쓰고 격리 복원으로 검증합니다. 통과해야 이후 결정이 열립니다. Enter로만 실행합니다.',
             helper('backup'), backed_up, requires_enter=True,
             ready=lambda r, c: c.get('backup_ok', False), timeout_s=300, heartbeat_s=15),
        review_cell('awaiting_confirmation', '지침·선호 후보 승인·거절',
                    '후보를 원문 인용과 함께 최대 10개씩 보여 줍니다. 승인·거절할 번호를 직접 입력합니다. Enter만 누르면 보류이고 아무것도 쓰지 않습니다.'),
        review_cell('unverified', '해결책 근거 검증',
                    '해결책 후보와 성공 근거 원문을 보여 줍니다. 원문을 보고 정말 해결됐다고 판단한 번호만 «검증됨»으로 확정합니다.'),
        Cell('결과 정리', '백업 시점과 지금 상태를 코어에서 다시 읽어 비교합니다.', helper('summary'), summary),
        Cell('되돌리기 안내', '승인한 기억을 되돌리는 방법을 코어 사실대로 안내합니다.', helper('rollback'), rollback),
    ]


if __name__ == '__main__':
    environment = {**os.environ, 'AIRAG_TOUR14_RUN': uuid.uuid4().hex}
    raise SystemExit(run_notebook('14-memory-confirmation', '14 · 기억 후보 확인·거절·검증', build_cells(), context={'env': environment},
        introduction='키 → 현황 → 백업·검증 → 지침·선호 결정 → 해결책 근거 검증 → 정리 → 되돌리기 안내\n쓰기 셀은 전체실행에서도 멈추고 Enter를 받습니다. 번호로 고른 후보만 처리하며 자동 승인은 없습니다.'))
