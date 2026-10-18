# zz-dogfood 시험 팀 정리 계획 (R373 · 삭제 = HIL · 지금 실행 0)

골좌표: 하네스 GOAL 표 B(개선요청 등록·처리) — R373 도그푸딩 산출물(시험 팀)을 남기지 않는다. 닫는 증거 = 정리 커밋 sha + `ft-team-upgrade.sh --check-teams` OK.

## 지울 것 (전부 R373 이 만든 것)
| 대상 | 위치 | 되돌림 |
|---|---|---|
| 팀 폴더 틀 14칸 | `design/zz-dogfood/` (tracked) | `git revert` 정리 커밋 |
| 명단 행 | `design/TEAMS.md` 1행 · `design/TEAMSET.md` 표 2 1행 | `git revert` 정리 커밋 |
| 명부 | 공용 루트 `.fable-team/seats-zz-dogfood.json` (gitignore · 커밋 밖) | `/tmp/zz-dogfood-roster.bak.json` 복사 |

## 지우지 않는 것
브랜치(삭제는 HIL 별건) · 다른 팀 파일 · 걸린 것 카드(R374~R376) · 시나리오 기록(R373 카드 «시나리오 기록» 절).

## 실행
- 계획 파일 `PLAN-zz-dogfood-cleanup-20261018.sh.hil` — 사람이 `! bash /tmp/h54` 한 줄(`ft-hil.sh --add` 등록 완료 · 아직 안 침 · h52·h53 은 대체됨 · h54 = `ZZ_WT=<루트 체크아웃> bash <루트>/design/teams/harness/PLAN-…sh.hil` — 착지 뒤 루트에 파일이 생긴 다음에만 동작, 다른 워크트리에서 치려면 h54 안 ZZ_WT·경로를 고친다). 나노·master 가 직접 치지 않는다.
- ★`ZZ_WT=<착지 뒤 origin/main 기준 워크트리 경로>` 필수(기본값 0 · 없으면 STOP)★ · 그 워크트리 HEAD 가 R373 착지분 `bbcecf620e` 를 품어야 한다(아니면 STOP).
- 가드(하나라도 걸리면 STOP · 지운 것 0): 좌석 행 0 · 틀 집합 밖 파일 0(`find design/zz-dogfood -type f` 기준 — 미추적·무시 파일 포함) · `byz-zz-dogfood*` tmux 세션 0 · 워크트리 미커밋·미추적 0(`git status --porcelain` 비어 있음).
- 언제: R373 DA⑥ CLOSE 뒤 · planner 설치(h48) 앞(시험 팀이 전 팀 패치 `--all` 대상에 끼지 않게).
