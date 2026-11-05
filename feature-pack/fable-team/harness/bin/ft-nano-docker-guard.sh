#!/usr/bin/env bash
# ft-nano-docker-guard.sh — r1418 «나노 좌석 docker·podman·nerdctl 가드».
#   부르는 꼴 ① 가드 폴더 래퍼(.fable-team/guard-bin/<이름>) → ft-nano-docker-guard.sh <docker|podman|nerdctl> "$@"
#             ② 이름이 docker·podman·nerdctl 인 사본으로 직접 → <이름> "$@"
#   지우기 꼴(rmi · image rm|remove|prune · volume rm|remove|prune · container|builder|buildx|system prune · compose down --rmi|-v) = REJECT 1줄 rc 3 · 진짜 바이너리 호출 0.
#   그 밖 = 가드 래퍼를 뺀 PATH 에서 같은 이름의 진짜 바이너리로 exec — argv·stdin·env·출력·rc 그대로.
#   진짜가 없으면 «판정 불가 — 진짜 <이름> 없음» 1줄 rc 127(지어내지 않는다).
#   왜: ops 나노(pi 좌석 = Claude 훅 0)가 공유 베이스 이미지 7개를 h 없이 지워 DB 쓰는 나노 시험이 전부 멈췄다 — 훅 목록과 무관한 겹.
set -u

REJECT_MSG='나노 좌석은 이미지·볼륨 지우기 금지 — h 로 올려라(ft-hil.sh --add)'

self="$(basename -- "$0")"
case "$self" in
  docker|podman|nerdctl) name="$self" ;;
  *) name="${1:-}"; [ "$#" -gt 0 ] && shift ;;
esac
case "$name" in
  docker|podman|nerdctl) ;;
  *) printf '판정 불가 — 부른 이름을 못 읽었다(%s) · 사용: ft-nano-docker-guard.sh <docker|podman|nerdctl> [인자…]\n' "${name:-}" >&2; exit 2 ;;
esac

orig=("$@")

# 전역 옵션 소비 — 값 있는 옵션은 값까지, «--옵션=값» 은 한 낱말, 값 없는 옵션은 한 낱말. 첫 하위 명령 앞에서 멈춘다.
while [ "$#" -gt 0 ]; do
  case "$1" in
    --*=*) shift ;;
    -H|--host|-c|--context|--config|-l|--log-level|--tlscacert|--tlscert|--tlskey) shift; [ "$#" -gt 0 ] && shift ;;
    --tls|--tlsverify|-D|--debug) shift ;;
    *) break ;;
  esac
done

ALL=" $* "
sub="${1:-}"; [ "$#" -gt 0 ] && shift

_sub_deny() {   # $1 = 하위 명령 · $2 = 그다음 낱말 → rc0 = 지우기 꼴
  case "$1" in
    rmi) return 0 ;;
    image|volume|container|builder|buildx|system)
      case "$1|$2" in
        image\|rm|image\|remove|image\|prune) return 0 ;;
        volume\|rm|volume\|remove|volume\|prune) return 0 ;;
        container\|prune|builder\|prune|buildx\|prune|system\|prune) return 0 ;;
      esac ;;
  esac
  return 1
}

_compose_deny() {   # 남은 인자 = compose 전역 옵션부터 → rc0 = down 에 --rmi·-v 가 붙었다
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --*=*) shift ;;
      -f|--file|-p|--project-name|--project-directory|--env-file|--profile|--ansi|--parallel|--progress) shift; [ "$#" -gt 0 ] && shift ;;
      -*) shift ;;
      *) break ;;
    esac
  done
  [ "${1:-}" = down ] || return 1
  shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --rmi|--rmi=*|-v|--volumes) return 0 ;;
    esac
    shift
  done
  return 1
}

deny=0
case "$sub" in
  compose) _compose_deny "$@" && deny=1 ;;
  '') deny=0 ;;
  *) _sub_deny "$sub" "${1:-}" && deny=1 ;;
esac
# ★첫 낱말만 본다★ 인자 속 글자(«image rm» · «rmi-container»)는 판정에 쓰지 않는다(G4) — 하위 명령이 run·logs 면 그대로 넘긴다.
if [ "$deny" = 1 ]; then printf '%s\n' "$REJECT_MSG" >&2; exit 3; fi

# 진짜 바이너리 = 가드 래퍼를 뺀 PATH 에서 같은 이름. 래퍼 판별 = 파일 머리에 «ft-nano-docker-guard» 표식(심링크 아닌 일반 파일).
rest=""
IFS=:
for d in ${PATH:-}; do
  [ -n "$d" ] || continue
  f="$d/$name"
  if [ -f "$f" ] && [ -r "$f" ] && head -n 5 "$f" 2>/dev/null | grep -q 'ft-nano-docker-guard'; then continue; fi
  rest="${rest:+$rest:}$d"
done
unset IFS

real=""
IFS=:
for d in $rest; do
  [ -n "$d" ] || continue
  if [ -f "$d/$name" ] && [ -x "$d/$name" ]; then real="$d/$name"; break; fi
done
unset IFS

[ -n "$real" ] || { printf '판정 불가 — 진짜 %s 없음\n' "$name" >&2; exit 127; }
exec "$real" "${orig[@]}"
