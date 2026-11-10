# CLOSEOUT — 하네스 (master#29 · 2026-10-11 · 판정 1068 전 팀 마감)

## 골 원문 (GOAL-harness.md 복붙)
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 축별 상태와 닫는 증거
| 단위 (골 축) | 상태 | 닫는 증거 |
|---|---|---|
| R102 이슈 닫기 게이트 (B 개선요청 접수·협의 + C 업그레이드·설치) | 닫힘 | PR 1259 squash `15b8920236c3516defe69c2295cac7aff012c16e` · 카드 `design/teams/harness/indices/완성/r102-issue-close-gate.md` · 판정문 `OPS-VERDICTS-20261006.md §117` · 세트 `d2ff250ebd702758116b76a2b850d41e8b3cd90f` · 요청 원장 R102 닫힘 |
| 라이브 설치 (C) | 완료 | 루트 `.fable-team/bin` + `v6-realtime-live/.fable-team/bin` 에 close-check·close-gate(신규)·ft-gh-as-tank · 백업 `.bak-r102-20261011T134602Z` · drift-check OK files=108 · dry-run ③ rc=0 · ② rc=3 · 라벨 `status:observing` 생성 |
| ops 문서 묶음 랜딩 (판정 1064·1066 · C) | 닫힘 | PR 1260 squash `32d0374ed0e8c600e3c7ae07537cc814be989b60` · 16파일 코드 0 · 패치 동일 대조 |
| ops 카드 cap-o5c-contract-cap-input 완성 이동 | 닫힘 | ops 쪽 커밋 `26d3f654f4`(정본 줄 `873c95783d`) · 랜딩 `32d0374ed0e8` |
| troubleshoot 1KB 위생 | 닫힘 | `f4be3bbad5` (1025→893B) |

## 배포 브랜치
main = `32d0374ed0e8` (R102·ops 묶음 반영). `ops/main-base` 로컬 커밋 다수(요청 원장·인계서·카드·판정문·이 문서)는 push 금지 브랜치(판정 739) — 코드 랜딩 때 land 가지로 옮겨 묶음 랜딩(planner 승인 값 필요).
push 전 로컬 검증: 시험 3종 rc=0 (`test_issue_close_gate.sh` · `test_issue_close_canon.sh` · `test_gh_as_tank.sh`).

## 나중에 볼 것
**다른 트랙 랜딩 때**
- 접수만 된 요청(착수 0): R82·R84·R88·R89 · 명부 자동 갱신 부재 묶음(R90~R93·R96·R98·R100·R101) · R94(tcc8 러너 세트 공통 파일) · R95(DA⑥ 브리프 «분기 플래그 판별 층 RED») · R97(mbox send 수신자 검증 WARN) · R99(CD standing 게이트 빈 응답 재조회)
- 다른 팀 명부 `_hil_route` 점검(graphics·ops·feature) — 각 팀 master 요청 때
- ops/main-base 로컬 커밋 묶음 main 랜딩
**완성 후**
- R86 라이브 확인(planner 가 오빠 입력창 시험을 요청할 때만) → 요청 원장 R34·R57·R85 닫기
- 브랜치 정리 [HIL]: `nano/r102-issue-close-gate` 등 보존 브랜치 삭제는 사람 승인
- 나노 mutation 임시 사본 `$TMPDIR/mut-r102-*` 정리(저장소 밖)
- arch#27 세션 정리 후보(keep-last-2 하한 유의)
- Tank 래퍼 `ft-gh-as-tank.sh` 200줄 분할 + 내부 gh 호출 7초 룰 적용(arch#28 별 후보 · 쪽지 76125)

## 다시 여는 법
버그·요청이 생기면 이 문서와 `design/teams/harness/REQUEST-LEDGER.md` 를 읽고 새 master 좌석을 연다(`tmuxc open … --model 'claude-sonnet-5-5[1m]' --ctx 1m --effort high` · `zsh -lc` 로 감쌈). 승계 인계서 `HANDOFF-harness-master-28-to-29-20261011.md` 의 운영 규칙·함정 절이 유효 — 특히 라이브 도구는 `v6-realtime-live/.fable-team/bin` 에서만 실행(루트 bin 은 옛 부분 사본), 라이브 파일 모드는 설치 미러(`scripts/harness-install/fable-team/bin`)와 같게(ft-gh-as-tank.sh 는 644).
