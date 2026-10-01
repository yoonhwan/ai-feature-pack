#!/usr/bin/env python3
"""Generate AIRAG keys only in a directly operated terminal."""
import secrets
import sys


def main():
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        print('직접 조작하는 터미널에서 실행하세요. 파일·파이프로 키를 출력하지 않습니다.', file=sys.stderr)
        return 1
    print('\nAIRAG · 64자리 hex 키 생성기')
    print('Enter를 누를 때마다 새 키 하나를 생성합니다.')
    print('출력된 값을 1Password의 해당 Password 아이템에 저장하세요.')
    print('파일 저장·클립보드 복사·AIRAG 설정 변경은 자동으로 하지 않습니다.')
    names = ('AIRAG_CONSUMER_KEY_HEX', 'AIRAG_PROJECTION_KEY_HEX', 'AIRAG_ARCHIVE_KEY_HEX')
    generated = set()
    for index, name in enumerate(names, 1):
        choice = input(f'\n[{index}/3] {name}\nEnter: 생성 · q: 종료 > ').strip().lower()
        while choice not in ('', 'q', '종료'):
            choice = input('Enter를 눌러 생성하거나 q로 종료하세요 > ').strip().lower()
        if choice in ('q', '종료'):
            return 0
        key = secrets.token_hex(32)
        while key in generated:
            key = secrets.token_hex(32)
        generated.add(key)
        print(f'\n{name}\n\n{key}\n', flush=True)
        input('1Password에 저장했으면 Enter > ')
    print('\n세 키를 각각 보관했습니다. 운영 준비 투어의 같은 이름 입력란에 붙여 넣으세요.')
    print('이 창에는 키가 표시되어 있으니 저장 후 창을 닫아 주세요.')
    input('Enter: 생성기 종료 > ')
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (EOFError, KeyboardInterrupt):
        print('\n생성기를 종료합니다.')
