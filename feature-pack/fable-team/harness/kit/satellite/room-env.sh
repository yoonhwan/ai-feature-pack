# source 해서 쓴다 — room 팀(멀티방 · 표시명 m.room) 값 (graphics-env.sh 꼴 · 2026-10-16 R252 · 판정 1942·1943·1949)
# 경로는 이 파일 위치(<ROOT>/.fable-team/bin-room/)에서 ROOT 를 구한다 — 임시 ROOT 설치 시험과 실설치가 같은 파일.
_RM_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
export FT_SEATS_JSON="$_RM_ROOT/.fable-team/seats-room.json"
export FT_NANO_PREFIX=byz-room-nano-
export FT_NANO_WT_PREFIX=room-nano-
export FT_ACTIVE_TAG=@zc_room_active
export FT_NANO_FEAT=origin/main
export FT_MBOX_SH="$_RM_ROOT/.fable-team/comm/mbox.sh"   # 추적 사본(harness/kit)에서 spawn 을 돌려도 mbox 를 찾게 한다
# 좌석 상한(판정 1949 · 팀장 상시 · 세션 팀당 3 · 위성 합 6) — ft-nano-spawn.sh 가 세션 열기 «전» ft_seat_cap.py 로 센다
export FT_TEAM_SEAT_CAP=3     # byz-room-* tmux 세션 수(팀장 포함)
export FT_GROUP_SEAT_CAP=6    # 명부 _parent 가 같은 위성팀들의 세션 합
export FT_PORT_BASE=38331     # 로컬 서버 포트 슬롯 3 (gateway +0 · worker +1 · FE +2) — 전역 포트 규칙 38301~38399
# ★개설 때 채운다(v65 제안서 판정 1935 확정 뒤 v65 master — 비워 둔다)★
# export FT_SEND_FROM='byz-room-master-claude#0'        # 팀장 — 승계 때 seats-room.json _master 와 같이 고친다
# export FT_BIN=<라이브 .fable-team/bin 절대경로>          # harness-env.sh 와 같은 값
# export FT_GOAL_LEDGER=design/room/GOAL-room.md · FT_NANO_LEDGER=design/room/NANO-LEDGER-room.md · FT_GOAL_LINES_FILE=…
unset _RM_ROOT
