#!/bin/bash
# r623 r4·r6 준비 h — dev 로컬 redis(도커 v6-realtime-live-redis-1)에 읽기 전용 계정 ft-readonly 를 둔다.
# 나노는 이 계획 파일만 썼다 · 실행 0. 실행 = desk(사람 `!` · `ft-hil.sh --add` 로 /tmp/h<N>) — planner 대리 결정 129140.
# 전제: 팩 1.1.174 설치 뒤(LIVE_BIN 에 ft-redis-readonly-user.sh · ft_redis_read.py) · ~/.claude/hooks/block-destructive.sh 설치본.
# 하는 일: 비밀번호 develop 볼트 `ft-redis-readonly`(없으면 새로) → ~/.config/ft/redis-readonly.pass(0600)
#         → ACL SETUSER ft-readonly reset on ~* -@all +<훅 읽기 목록 35> +select +acl|whoami >비번 (멱등)
#         → 확인 원문: ACL DRYRUN ft-readonly SET → 거절 · HSTRLEN → OK
# 운영 redis 0 · 컨테이너 설정 변경 0 · 기본 사용자·앱 연결 무영향.
# redis 재기동 뒤 계정이 사라지면 ft-redis-read.sh 가 rc4 로 알린다 → 이 h 를 다시 돌린다.
# ★r6: 도구는 `env -i … /bin/bash -p` 로만 돈다(BASH_ENV·SHELLOPTS 무시 · 아니면 도구가 rc2 로 거절)★
# 되돌림: 아래 줄의 ensure 를 revert 로 바꿔 실행.
set -uo pipefail
env -i PATH=/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin HOME="$HOME" \
  OP_SERVICE_ACCOUNT_TOKEN_DEVELOP="$OP_SERVICE_ACCOUNT_TOKEN_DEVELOP" \
  /bin/bash -p /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/bin/ft-redis-readonly-user.sh ensure
