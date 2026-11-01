#!/usr/bin/env bash
# ft-card-assign-watch.sh status|tick [--now <시각>] | set <카드> 좌석 <이름>|대기 <사유>|없음 — 카드→좌석 배정 감시(배정 없는 카드 N · 대기 초과 M). 팀 정지 = team-pause <팀> --verdict <N> --reason <10자+> | team-resume <팀> · 사람 보류 = record <카드> waiting 사람 verdict <N> (r1291). 본체는 같은 디렉터리 ft_card_assign_watch.py (r1224).
exec python3 "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/ft_card_assign_watch.py" "$@"
