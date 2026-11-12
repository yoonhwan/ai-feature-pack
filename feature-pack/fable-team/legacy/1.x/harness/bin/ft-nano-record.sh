#!/usr/bin/env bash
# ft-nano-record.sh — r1717: 착지(ft-merge-land LANDED) 뒤 그 카드를 맡은 나노가 «정리 기록» 을 남기는 도구(카드 «## 상태» 절 + 카드 ref 반영 + 닫기 요청).
#   due [--pr N] [--no-fetch]            읽기만 — 장부(state/land-record-turn.jsonl) 줄마다 카드별 1줄(차례·닫기 요청 밀림·끝·주인 없음·카드 없음·판정 불가)
#   notify [--pr N] [--no-fetch]         due 의 열린 줄마다 쪽지 1통(같은 열쇠 재발신 0 · 1800초 뒤 1회만 재촉) — ft-merge-lib fm_land_turn · ft_stall_scan 이 부른다
#   landed --seat <좌석> --pr <N> --card <stem> [--test "<명령> rc=0"] [--left "<종류>=<담당>"] [--handoff <경로>]
#                                        나노가 «[정리 차례]» 쪽지의 명령 그대로 실행 — 세트·착지·완료 줄을 카드 ref 에 1커밋으로 보내고 확인한 뒤 DONE|ALREADY · 끝줄 NEXT(닫기 명령)
#   settle --seat <좌석> --pr <N> (--card <stem>… | --no-card "<사유>")   팀장·arch 가 «카드 없음» 장부 줄을 닫는다(덧줄 append)
#   done --seat <좌석> --card <stem> --did "<한 일>" --test "<명령> rc=0" [--pr <N>] [--left …] [--wt <작업 폴더>] [--handoff <경로>]   일 끝 완료 줄(착지 전)
#   refused --seat <좌석> --cause "<진행 아닌 거절 사유 전부>"            닫기 거절 이력(1회 = 나노에 해소 쪽지 · 2회 = 팀장 «[유보]» · 3회부터 발신 0)
#   rc 0 = 끝 · 1 = REJECT(쓰기 0) · 2 = usage · 3 = 판정 불가(git·fetch·push·tmux·명부·잠금 실패 — 쓰기·닫기 요청 0 · 다시 실행하면 단계마다 이어진다)
#   이 도구는 tmux kill·ft-nano-close·ft-seat-close 를 부르지 않는다 — 닫기는 팀장 집행 또는 자동 닫기(ft_stall_scan «갈래=착지기록»)뿐.
#   루트 = env FT_ROOT(없으면 cwd 의 git 공용 루트) · 본체 = 같은 폴더 ft_nano_record*.py · 새 파일 mode 100644(`bash <이 파일>` 로 부른다).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
case "${1:-}" in
  due|settle) m=ft_nano_record_due.py;;
  notify) m=ft_nano_record_notify.py;;
  landed) m=ft_nano_record_write.py;;
  done|refused) m=ft_nano_record_done.py;;
  *) echo "usage: $0 due|notify|landed|settle|done|refused … (머리 주석)" >&2; exit 2;;
esac
[ -f "$HERE/$m" ] || { echo "판정 불가 $m 없음($HERE) rc=1"; exit 3; }
exec python3 "$HERE/$m" "$@"
