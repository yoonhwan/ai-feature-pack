"""Shared terminal notebook interaction for sequential AIRAG tours."""
from __future__ import annotations
from dataclasses import dataclass
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shlex
import subprocess
import time

QUIT = {'q', 'quit', 'exit', '종료', '그만'}
RUN = {'', 'run', '실행', 'go'}
STATE = Path(__file__).resolve().parents[2] / 'airag' / 'tour-state.json'


def ask(prompt):
    try:
        return input(prompt).strip()
    except (EOFError, KeyboardInterrupt):
        print('\n투어를 종료합니다.')
        raise SystemExit(0)


@dataclass
class Cell:
    title: str
    explanation: str
    command: object
    explain: object
    prepare: object = None
    ready: object = None
    allow_auto_repeat: bool = False
    timeout_s: float = 240
    heartbeat_s: float | None = None
    requires_enter: bool = False


def run_command(command, environment, *, timeout_s=240, heartbeat_s=None):
    if heartbeat_s is None:
        return subprocess.run(command, env=environment, text=True, capture_output=True, timeout=timeout_s)
    started = time.monotonic()
    with subprocess.Popen(command, env=environment, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE) as process:
        try:
            while True:
                remaining = timeout_s - (time.monotonic() - started)
                if remaining <= 0:
                    raise subprocess.TimeoutExpired(command, timeout_s)
                try:
                    stdout, stderr = process.communicate(timeout=min(heartbeat_s, remaining))
                    return subprocess.CompletedProcess(command, process.returncode, stdout, stderr)
                except subprocess.TimeoutExpired:
                    print(f'  현재 창 응답 대기 · {int(time.monotonic() - started)}초 경과', flush=True)
        except BaseException:
            if process.poll() is None:
                process.terminate()
                try:
                    process.communicate(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.communicate()
            raise


def run_notebook(tour_id, title, cells, *, introduction='', context=None):
    context = {} if context is None else context
    context.setdefault('env', dict(os.environ))
    completed = []

    def checkpoint(state):
        STATE.parent.mkdir(parents=True, exist_ok=True)
        STATE.write_text(json.dumps({
            'tour_id': tour_id, 'title': title, 'state': state,
            'completed_cells': completed, 'total_cells': len(cells),
            'outcome': context.get('outcome'),
            'updated_at': datetime.now(timezone.utc).isoformat(),
        }, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

    def exit_tour(code=0):
        checkpoint('exited')
        print('투어를 종료합니다. 입력한 키 값은 파일로 저장하지 않습니다.')
        return code

    checkpoint('awaiting_start')
    print('\nAIRAG · ' + title)
    print(introduction)
    print('Enter/실행: 현재 셀 실행 · 전체실행: 남은 셀 자동 진행 · 종료: 나가기')
    if ask('\nEnter를 누르면 첫 셀을 설명합니다 > ').lower() in QUIT:
        return exit_tour()
    automatic = False
    for number, cell in enumerate(cells, 1):
        print('\n' + '─' * 64)
        print(f'셀 {number}/{len(cells)} · {cell.title}')
        print('─' * 64 + '\n' + cell.explanation)
        while True:
            command = cell.command(context) if callable(cell.command) else cell.command
            print(f'\nIn [{number}]: {shlex.join([str(x) for x in command])}')
            if automatic and cell.requires_enter:
                print('이 셀은 운영 저장소에 씁니다. 전체실행을 멈추고 Enter 확인을 받습니다.')
                automatic = False
            choice = '실행' if automatic else ask('Enter 또는 실행 > ').lower()
            if choice in QUIT:
                return exit_tour()
            if choice in ('전체실행', 'all'):
                automatic = not cell.requires_enter
            elif choice not in RUN:
                print('Enter, 실행, 전체실행, 종료 중 하나를 입력하세요.')
                continue
            if cell.prepare:
                cell.prepare(context, automatic)
                updated = cell.command(context) if callable(cell.command) else cell.command
                if updated != command:
                    command = updated
                    print(f'In [{number}]: {shlex.join([str(x) for x in command])}')
            print('\n실행 중…', flush=True)
            started = time.monotonic()
            try:
                result = run_command([str(x) for x in command], context['env'],
                                     timeout_s=cell.timeout_s, heartbeat_s=cell.heartbeat_s)
            except KeyboardInterrupt:
                return exit_tour()
            except (OSError, subprocess.TimeoutExpired) as error:
                print('실행 오류:', type(error).__name__)
                automatic = False
                continue
            if result.returncode:
                print(result.stdout.strip())
                print(result.stderr.strip())
                automatic = False
                if ask('Enter: 재시도 · 종료 > ').lower() in QUIT:
                    return exit_tour(1)
                continue
            try:
                response = json.loads(result.stdout)
            except ValueError:
                response = result.stdout
            print(f'\nOut [{number}] · {time.monotonic() - started:.1f}초')
            cell.explain(response, context)
            ready = cell.ready is None or bool(cell.ready(response, context))
            checkpoint('running')
            if not ready:
                if automatic and cell.allow_auto_repeat:
                    print('다음 대기 창을 이어서 처리합니다.')
                    continue
                automatic = False
                print('아직 이 셀이 완료되지 않았습니다. Enter로 같은 셀을 이어서 실행합니다.')
            if automatic:
                break
            while True:
                prompt = '\nEnter: 다음 셀 · raw: 전체 결과 · 재실행 · 전체실행 · 종료 > ' if ready else '\nEnter: 같은 셀 실행 · raw: 전체 결과 · 종료 > '
                if not ready and cell.allow_auto_repeat:
                    prompt = '\nEnter: 다음 창 · 전체실행: 남은 창 연속 처리 · raw · 종료 > '
                choice = ask(prompt).lower()
                if choice == 'raw':
                    print(json.dumps(response, ensure_ascii=False, indent=2) if not isinstance(response, str) else response)
                    continue
                if choice in QUIT:
                    return exit_tour()
                if not ready and choice in ('', '다음', 'next', '전체실행', 'all'):
                    automatic = cell.allow_auto_repeat and choice in ('전체실행', 'all')
                    choice = '재실행'
                if choice in ('재실행', 'retry'):
                    break
                if choice in ('전체실행', 'all'):
                    automatic = True
                if choice in ('', '다음', 'next', '전체실행', 'all'):
                    break
                print('Enter를 누르면 다음 셀로 이동합니다.')
            if choice in ('재실행', 'retry'):
                continue
            break
        completed.append(cell.title)
        checkpoint('running')
    print('\n투어 완료')
    for index, item in enumerate(completed):
        print(f'{"└─" if index == len(completed)-1 else "├─"} [완료] {item}')
    checkpoint('completed')
    return 0
