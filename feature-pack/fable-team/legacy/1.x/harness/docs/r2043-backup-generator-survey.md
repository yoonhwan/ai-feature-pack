# r2043 조사표 — 백업·로그 생성기 목록 (카드 «## 조사표» 절 원본)

- 카드: BYZ-Agents `design/harness/indices/대기/r2043-roster-backup-cap-prune.md`
- 실측: 2026-11-15 · 나노 읽기만 · BYZ-Agents `.fable-team` 루트 · 표시 «arch» = 카드 실측 줄 값(이번에 다시 안 셈)
- 제안 칸: 지킴 = 이 카드(r2043 bak_cap)로 상한 50 · 새 카드 = 필요하면 따로 · 지우면 안 됨 = 되돌림 근거라 상한 두지 않음

| 생성 도구 파일:줄 | 이름 꼴 | 지금 개수 | 상한 | 제안 |
|---|---|---|---|---|
| ft-seat-close.sh:137·156 | `seats*.json.bak-close-<YYYYmmddHHMMSS>` | 287 (planner 202 · cfo 36 · feature 23 · knowledge 7 · harness 5 · 그 밖 각 3) | 이제 있음 50 | 지킴 |
| ft-seat-close.sh:128·134 | `seats*.json.bak-reopen-<ts>` | 0 | 이제 있음 50 | 지킴 |
| ft-seat-retire.sh:205 · ft_roster_lib.py apply_routes(apply_cells 경유) | `seats*.json.bak-retire-<ts>` | 452 (harness 247 · planner 134 · cfo 32 · feature 16 · knowledge 8 · 그 밖 각 3) | 이제 있음 50 | 지킴 |
| ft-tick-team.sh:106 retarget_seat | `seats*.json.bak-retarget-<ts>` | 0 | 이제 있음 50 | 지킴 |
| ft_team_rename.py:244·246 (ft-team-rename.sh 껍데기) | `seats-<옛>.json.bak-rename-<YYYYmmdd-HHMMSS>` | 0 | 이제 있음 50 | 지킴 |
| ft_key_rotate_io.py apply_edits | `~/.zshrc`·`.env` `.bak-keyrotate-<KEY>-<YYYYmmdd-HHMMSS><us>` | 0 (~/.zshrc) | 이제 있음 50(키별) · lib 없는 묶음 복사본은 정리 0 | 지킴 |
| ft-live-put.sh:31 | `<라이브 파일>.bak-<표식>`(예 `.bak-r2043`) | 라이브 1.1.292/bin `.bak-r*` 267 (arch) · 루트 아래 `.bak-r<N>` 86 | 없음 | 새 카드 — 설치 되돌림 근거 · 표식별 1개라 무한 증가는 아님(설치 횟수만큼) |
| ft-root-bin-migrate.sh:82 | `<파일>.bak-r962` | (위 86 에 포함) | 1개 고정(같은 이름) | 지우면 안 됨 — 일회 이전 되돌림 근거 |
| ft-tick-install.sh:220 | `<plist>.bak-r199` | [확인 필요: ~/Library/LaunchAgents] | 1개 고정(있으면 REJECT) | 지우면 안 됨 |
| 손 백업(도구 아님) | `.bak-ft*` · `.bak-pk*` | 22 · 11 | 없음 | 새 카드 — 만든 도구 없음(사람·arch 손 백업) · 자동 정리 대상 아님 |
| ft-root-bin-shim.sh ③ | `.fable-team/bin.stale-<시각>/` 폴더 | 10 | 없음 | 지우면 안 됨 — 옮김(삭제 0) 되돌림 근거 |
| ft-team-switch.sh unmark | `state/ft20-switch/<팀>.json.unmarked-<ts>` | 71 (state 폴더 전체 `*unmarked*`) | 없음 | 새 카드 — restore 가 «가장 새 것» 만 쓴다 · 상한 두려면 R336 창 규칙과 대조 필요 |
| ft_inbox_rotate.py:59 | `inbox/archive/<계보>-rotated-<YYYYmmdd>.jsonl` · `rotated.log` | [확인 필요] | 없음 | 새 카드 — 쪽지 보관(감사 근거) |
| comm/mbox.py 송신 원장 회전 | `mailbox.log.jsonl` + `.1~.3` | 4 | 있음(SENT_LOG_KEEP=3) | 지킴 아님 — 이미 상한 |
| comm/mbox 본문 | `comm/bodies/<seq>*` | 86,949 | 없음 | 새 카드 — 범위 밖(카드 동결) · 쪽지 seq 참조라 지우기 전 참조 규칙 필요 |

## 상한 규칙 (이 카드로 지키는 줄)

- 함수: `ft_roster_lib.bak_cap(<원본>, <종류>, [상한])` · 셸 `ft_bak_cap` (ft-team-lib.sh · 같은 Python 함수 호출)
- 단위 = (원본 파일 · 종류) · 상한 = env `FT_BAK_CAP` 정수 50~100 · 없거나 밖이면 50
- 대상 = 정확히 `<원본>.bak-<종류>-<숫자 ts>` 일반 파일 · 심링크·폴더·꼴 밖 꼬리·`.bak-r<N>` = 손 0
- 순서 = 이름 속 ts 숫자(자릿수 → 값) · 오래된 것부터 지움 · 실패 = stderr `WARN 백업 상한 정리 실패 …` 1줄 · 본 작업 rc 불변
