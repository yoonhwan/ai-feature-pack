#!/bin/bash
# ft-redis-readonly-user.sh — dev 로컬 redis(도커)에 읽기 전용 계정 `ft-readonly` 를 두고/빼는 «사람 h» 도구 (r623 r4)
#
# ft-redis-read.sh 의 보증 = 서버 거절. 이 스크립트가 그 계정을 만든다(사람 `!` 실행 · 나노·좌석 자동 실행 0).
#   ensure : 비밀번호(1Password develop 볼트 `ft-redis-readonly` · 없으면 새로 만듦) → 0600 파일
#            → `ACL SETUSER ft-readonly reset on ~* -@all +<훅 읽기 목록> +select >비번` (멱등: 같은 규칙으로 다시 씀)
#            → 확인 원문 `ACL DRYRUN ft-readonly SET …`(거절이어야) · `… HSTRLEN …`(OK 여야)
#   check  : 확인 원문만(쓰기 0)
#   revert : `ACL DELUSER ft-readonly` + 비밀번호 파일 삭제(볼트 항목은 남김)
#   rule   : 규칙 낱말만 출력(비밀번호 0)
# 운영 redis 0 · 컨테이너 설정 변경 0 → redis 재기동 때 계정이 사라지면 ensure 를 다시 돌린다(planner 결정 129140).
# 쓰는 법: ft-redis-readonly-user.sh <ensure|check|revert|rule> [--container 이름] [--pass-file 경로] [--hook 경로]
set +o xtrace +o verbose; unset BASH_ENV ENV   # 비번 노출 0(r5): 물려받은 xtrace(SHELLOPTS)를 끄고 자식에도 안 물림 · 비번은 docker exec 표준입력만
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PY=/usr/bin/python3
ACCT=ft-readonly
ITEM=ft-redis-readonly
CT=v6-realtime-live-redis-1
PASS="$($PY -I -c 'import os,pwd;print(pwd.getpwuid(os.getuid()).pw_dir)')/.config/ft/redis-readonly.pass"
HOOK=""
die() { echo "FAIL ft-redis-readonly-user — $*" >&2; exit 2; }

cmd="${1:-}"; shift || true
while [ $# -gt 0 ]; do
  case "$1" in
    --container) CT="${2:?}"; shift 2 ;;
    --pass-file) PASS="${2:?}"; shift 2 ;;
    --hook) HOOK="${2:?}"; shift 2 ;;
    *) die "모르는 인자: $1" ;;
  esac
done

rule() { $PY -I "$HERE/ft_redis_read.py" --acl-rule ${HOOK:+"$HOOK"}; }
rcli() { docker exec -i "$CT" redis-cli; }   # 명령은 표준입력으로(비밀번호가 ps 인자에 안 보이게)

running() {
  [ "$(docker inspect -f '{{.State.Running}}' "$CT" 2>&1)" = true ] || die "컨테이너 $CT 가 실행 중이 아님"
}

check() {
  local w r
  w="$(printf 'ACL DRYRUN %s SET r623:probe v\n' "$ACCT" | rcli 2>&1)"
  r="$(printf 'ACL DRYRUN %s HSTRLEN r623:probe f\n' "$ACCT" | rcli 2>&1)"
  echo "확인 원문 · ACL DRYRUN $ACCT SET   → $w"
  echo "확인 원문 · ACL DRYRUN $ACCT HSTRLEN → $r"
  [ "$r" = OK ] && [ "$w" != OK ] && [ -n "$w" ] || die "확인 실패(쓰기 거절·읽기 허용이 아님)"
  echo "OK ft-redis-readonly-user — $ACCT 쓰기 거절 · 읽기 허용 ($CT)"
}

password() {
  local pw tok="${OP_SERVICE_ACCOUNT_TOKEN_DEVELOP:-}"
  [ -n "$tok" ] || die "OP_SERVICE_ACCOUNT_TOKEN_DEVELOP 없음(develop 볼트 전용 · kskill 토큰 사용 0)"
  pw="$(OP_SERVICE_ACCOUNT_TOKEN="$tok" op read "op://develop/$ITEM/password" 2>/dev/null)"
  if [ -z "$pw" ]; then
    OP_SERVICE_ACCOUNT_TOKEN="$tok" op item create --vault develop --category password --title "$ITEM" \
      --generate-password='letters,digits,32' >/dev/null || die "op item create 실패(develop 볼트 $ITEM)"
    pw="$(OP_SERVICE_ACCOUNT_TOKEN="$tok" op read "op://develop/$ITEM/password")" || die "op read 실패(develop 볼트 $ITEM)"
  fi
  [[ "$pw" =~ ^[A-Za-z0-9]{16,}$ ]] || die "비밀번호 모양 틀림(영숫자 16자 이상이어야 · 값 출력 0)"
  printf '%s' "$pw"
}

case "$cmd" in
  rule) rule ;;
  check) running; check ;;
  ensure)
    running
    r="$(rule)" || die "규칙을 못 만듦(훅 읽기 목록)"
    pw="$(password)" || exit 2
    ( umask 077; mkdir -p "$(dirname "$PASS")" && printf '%s\n' "$pw" > "$PASS" ) || die "비밀번호 파일 쓰기 실패: $PASS"
    chmod 600 "$PASS"
    out="$(printf 'ACL SETUSER %s %s >%s\n' "$ACCT" "$r" "$pw" | rcli 2>&1)"
    [ "$out" = OK ] || die "ACL SETUSER 실패: $out"
    echo "OK ACL SETUSER $ACCT $r >(비밀번호 · 파일 $PASS 0600)"
    check ;;
  revert)
    running
    out="$(printf 'ACL DELUSER %s\n' "$ACCT" | rcli 2>&1)"
    echo "되돌림 원문 · ACL DELUSER $ACCT → $out"
    rm -f "$PASS" && echo "비밀번호 파일 삭제: $PASS (볼트 항목 develop/$ITEM 은 남김)" ;;
  *) die "사용법: ft-redis-readonly-user.sh <ensure|check|revert|rule> [--container 이름] [--pass-file 경로] [--hook 경로]" ;;
esac
