#!/usr/bin/env python3
"""Forward read-only tour commands to the installed CLI using in-memory test keys."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import sys
import time
import uuid

parser = argparse.ArgumentParser(description='AIRAG 검증 샘플 CLI 투어')
parser.add_argument('command', choices=('status', 'search', 'verify'))
parser.add_argument('arguments', nargs=argparse.REMAINDER)
args = parser.parse_args()
root = Path('/private/var/folders/vm/j7_jw8050t553wj5wqlvnmmh0000gn/T/airag-live-acceptance-0ysg_idj')
control = root / 'test-control-v2.json'
response = root / 'test-control-v2-result.json'
try:
    os.kill(2405, 0)
except ProcessLookupError:
    parser.exit(1, '투어 키 보조 프로세스가 종료됐습니다. 세션에서 샘플 복원을 요청해 주세요.\n')
with (root / 'tour-client.lock').open('a') as lock:
    fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
    request_id = 'tour-' + uuid.uuid4().hex
    request = {'id': request_id, 'operation': 'cli', 'args': [args.command, *args.arguments]}
    temporary = root / ('tour-request-' + request_id + '.json')
    temporary.write_text(json.dumps(request, ensure_ascii=False), encoding='utf-8')
    temporary.replace(control)
    deadline = time.monotonic() + 180
    while time.monotonic() < deadline:
        try:
            result = json.loads(response.read_text())
        except (OSError, ValueError):
            time.sleep(0.25)
            continue
        if result.get('id') != request_id or result.get('state') == 'running':
            time.sleep(0.25)
            continue
        if result.get('state') == 'failed':
            parser.exit(1, 'CLI 실행 실패: ' + result.get('error_type', 'UNKNOWN') + '\n')
        output = result.get('stdout', '')
        try:
            print(json.dumps(json.loads(output), ensure_ascii=False, indent=2))
        except ValueError:
            print(output, end='')
        if result.get('exit_code'):
            print(result.get('stderr', ''), end='', file=sys.stderr)
        sys.exit(result.get('exit_code', 1))
    parser.exit(1, '응답 대기 시간이 초과됐습니다. 동일 명령을 반복하지 말고 세션에서 상태를 확인해 주세요.\n')
