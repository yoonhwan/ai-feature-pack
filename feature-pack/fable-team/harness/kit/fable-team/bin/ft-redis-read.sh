#!/bin/bash
# ft-redis-read.sh — «읽기 전용 redis 묶음» 실행 도구 (r623 r4 · 하드 룰 11 유지)
#
# 왜 있나: 측정 조작 차단 훅(block-destructive.sh)은 redis-cli 표준입력 파일 꼴을 막는다(훅은 넓히지 않음 · 팩 main 판 그대로).
# 읽기만 하는 묶음(HSTRLEN 789줄 같은)은 이 도구로 돌린다.
#
# 보증 = 서버: redis 읽기 전용 계정 `ft-readonly`(`-@all` + 훅 읽기 목록과 같은 명령만)로만 접속 → 쓰기는 서버가 NOPERM 으로 거절.
#   계정 준비·재기동 뒤 복구 = 사람 h `ft-redis-readonly-user.sh ensure`(멱등) · 계정이 없으면 rc4 로 멈춤(기본 사용자 대신 접속 0).
# 도구 검사 = 빠른 거절 + 원장: 파일을 한 번 읽어(1 MiB · 1만 줄 · UTF-8 · 출력 가능 글자+개행만) 모든 줄 첫 동사가 읽기 목록인지 보고,
#   그 바이트를 그대로 redis-cli 표준입력으로 보낸다. redis-cli 경로·읽기 목록(설치된 훅)·원장·비밀번호 파일은 고정 — 환경변수 갈래 0.
#   자식 환경 = PATH·HOME·LANG·REDISCLI_AUTH 만(FAKETTY*·REDISCLI_RCFILE 등 0) · 출력에 오류 줄이면 rc3.
#
# 쓰는 법: ft-redis-read.sh [-h H] [-p P] [-n N] <묶음 파일>
# rc: 0 통과 · 2 REJECT(호출 0) · 3 서버 오류 줄 · 4 읽기 전용 계정 없음
#
# 래퍼는 외부 명령 0(dirname·cd 0) · PATH 고정 · 본체는 이 파일 옆 ft_redis_read.py 를 /usr/bin/python3 -I 절대경로로만 (r5).
PATH=/usr/bin:/bin
d="${BASH_SOURCE[0]%/*}"; [ "$d" = "${BASH_SOURCE[0]}" ] && d=.
exec /usr/bin/python3 -I "$d/ft_redis_read.py" "$@"
