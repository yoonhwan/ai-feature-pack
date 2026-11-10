# 인덱스: 유휴 팀 정리 후보와 하네스 재개 관리
<!-- ledger: design/teams/harness/GOAL-harness.md -->
- 상태: 완성
- 근거: 원승인 Pi user 902행·eb54a4ff. 지원 계약 정리 #270917·#270956·#271016은 별도 참고이며 원승인과 구분한다.
- 선행: r1450과 같은 branch에서 함께 랜딩한다.
- 설치: 있음
- 실정리: 실행 0. 이 단위는 기본 off 후보 계획과 하네스 수신·재개 경계를 설치한다.

## 후보 판정
- r1450의 raw actionable을 그대로 사용한다. 미읽음 non-ft 우편 또는 현재 좌석과 정확히 일치하는 state=seat 배정이다. 통지 seen은 작업 완료가 아니므로 후보 판정에서는 빼지 않는다.
- 팀장과 소속 현역 좌석 전원이 actionable 0이고 전원이 턴을 종결한 IDLE 상태여야 한다.
- 과거 stop-ready 행은 현역 구성원에 포함하지 않는다. 정리 뒤 복원할 구성원은 직전 candidate 계획의 cohort에 기록한 좌석으로 한정한다.
- 이 상태를 처음 관측한 시점부터 N분 지속되어야 한다. 기본 N은 60분이며 관측 중 업무·보호 조건·진행 턴이 생기면 시계를 초기화한다.
- 보호는 루트 `seats.json`의 `_master`와 정본 harness 명부의 `_master` 두 역할이다. 정본 team-master 조회와 루트 명부를 읽어 동적으로 판정하며 좌석 이름을 코드에 적지 않는다. 그 밖의 팀별 유휴 master는 후보가 될 수 있다.
- HIL 대기, 사람 발주 대기, 선행 대기 카드, 진행 중 또는 판정 불가 턴은 팀 전체를 보호한다.
- master tick 기본 간격은 280초다. PM/goal 간격은 변경하지 않는다.

## 극단 상태
- 모든 일반 팀장이 정리돼도 루트와 harness의 두 보호 역할은 후보 산출 첫 단계에서 제외한다.
- 하네스의 기존 tick이 card-assign, 사람 우편, HIL을 감지한다. 새 잡을 만들지 않으며 감지·재개 요청은 기존 60초 관측 루프에서 수행한다. 280초 master 주기는 관측 루프보다 길다.
- 실제 resume와 ready 완료는 별도 실행 증거로 확인한다. 기본 off 설치나 후보 계획만으로 280초 안의 운영 재개 완료를 인증하지 않는다.

## 실행 경계
- `FT_TICK_IDLE_TEAMS=0`이 기본이다. 켜진 기존 tick step은 후보 계획을 남기며 자동 close/kill/삭제를 하지 않는다.
- 계획 파일은 소속 좌석, 보호 근거, N분 관측 시작, 정리·보존 목록, 승인 필요 여부를 가진다. 후보와 완료를 구별하며 `cleanup_verified=false`로 시작한다.
- 실제 세션·명부 정리는 하네스가 기존 `ft-seat-close.sh`와 `ft-seat-reap.sh`의 승인 경로로 수행한다.
- 워크트리 정리는 승인된 기존 계획이 있을 때만 `ft-wt-sweep.sh`로 집행한다. 이 도구는 계획을 생성하지 않는다.
- `ft-scratch-repo.sh --prune-missing`은 이미 없는 사본의 등록만 정리한다. 존재하는 사본의 제거 증거로 쓰지 않는다.
- 기존 계획·실파일 존재 여부를 확인하지 않은 항목은 미완료로 남긴다. 삭제 금지 목록을 제외한 잔여물이 실제로 0일 때만 정리 완료다.

## 삭제 금지와 잔여물 목록
- 삭제 금지: 대화 원본 jsonl, baton, 재개 기록, 미커밋 산출, 미푸시 산출, 공유 상태, 카드 정본 indices, 원장, HIL 항목, 브랜치.
- 승인 뒤 조사할 목록: 해당 좌석 전용 임시 stamp와 haswork seen, 종료한 좌석의 워크트리 및 사본, 기존 wt-clean 계획의 미완료 포인터.
- inbox와 shared state는 팀 정리의 삭제 대상이 아니다. r1450의 독립 tidy 정책과 보존 원장을 따른다.

## 재개 경로 하나
1. 기본 off watch가 직전 cohort의 stop-ready 좌석으로 온 사람 발주, 정확한 카드 배정, 기존 pending HIL을 확인한다. 기존 mbox handover로 하네스 큐에 원 seq 또는 카드/HIL 참조를 인계한다. background는 recv하지 않는다. 하네스의 실제 mbox 수신 뒤 `comm/receipts/<하네스>.jsonl`의 forwarded seq와 발신자를 읽기만 대조한다.
2. 수신 영수가 있고 `FT_TICK_IDLE_TEAM_REOPEN=1`인 경우에만 기존 zombie-clean resume로 보존된 대화를 기동한다. 이 옵션도 기본 0이다.
3. 세션 기동 뒤 기존 `ft-seat-close.sh --reopen`으로 원래 role·tick·명부 지시자를 복원한다.
4. 원 요청 참조를 포함한 해당 좌석의 실제 `[레디]`를 하네스가 수신해야 재개 완료다. 같은 영수 정본에서 인계 이후 회신을 좌석별로 누적하며 먼저 도착한 ready를 다시 소비하지 않는다. 모든 대상의 ready 전에는 새 업무를 전달하지 않는다.

## 플랜팀 정본
같은 branch source는 `design/teams/planner/IDLE-TEAM-LIFECYCLE.md`다. 배포 대상은 BYZ `design/teams/planner/GUIDE-planner.md`이며 실제 정본 반영과 문서 repo의 별도 격리 commit은 root가 맡는다.

## 검증 범위
임시 FT_ROOT, 팀장 1명과 nano 2명, 가상 시각, 가짜 도구만 사용한다. N분 경계, 전역 master 보호, 자식 작업과 진행 턴, HIL·사람·선행 대기, 삭제 금지 목록, 하네스 수신부터 ready까지의 순서를 검증한다. 운영 세션·우편·정리 실행은 0이다.

## 완료 증거
- 팩 구현: [PR #771](https://github.com/yoonhwan/ai-feature-pack/pull/771), main `5717298ffda4b57fd8709a3c112a1f9a5fbaf932`. r1450 구현과 같은 branch에서 함께 착지했다.
- 설치: `1.1.288`, source/kit/live 4쌍 일치와 정상 설치 대조 `OK n=4 skip=0`. 설치 원문은 BYZ `.fable-team/state/r1450/landing-05-install.log`와 `landing-09-live-install-check.log`다.
- DA: r1450은 BYZ `.fable-team/state/r1450/da-integrated-01.md`의 APPROVE, r1452는 `.fable-team/comm/bodies/271205.txt`의 cohort 보정 한정 APPROVE. [보정 RED→GREEN 및 인접 회귀 원문](../../../../evidence/r1452/09-dormant-cohort-red-green.log)을 보존한다.
- 최종 checker: BYZ `.fable-team/state/r1450/checker-integrated-01.json`, `COMPLETE/PASS`. 원래 REJECT와 이전 checker FAIL은 별도 보존했다.
- planner 정본: BYZ 문서 owner가 GUIDE·STRUCTURE 2파일을 [main `eb2d525a90d8c4cea68f9679133c5cbca03e9b6d`](https://github.com/SecondWindStudio/byz-agents/commit/eb2d525a90d8c4cea68f9679133c5cbca03e9b6d)에 반영했다. 승인된 2파일 blob과 원격 반영본이 일치한다.
- 완료 범위와 한계: 기본 off 후보 계획·재개 경계의 구현과 설치를 완료했다. `FT_TICK_IDLE_TEAMS=0`, `FT_TICK_IDLE_TEAM_REOPEN=0`, master 간격 280초이며 실정리는 0회다. 실제 운영 resume·ready 완료와 280초 내 운영 재개 보장은 별도 실행 증거가 필요하다.
