# 유휴 팀 정리와 하네스 재개 관리

배포 대상은 BYZ `design/teams/planner/GUIDE-planner.md`다. 이 source를 r1450과 같은 branch에서 검토하고, 운영 정본 반영은 설치 담당이 수행한다. 전역 VOICE 블록은 수정하지 않는다.

1. 팀 소속 현역 좌석 전원의 raw actionable이 0이고 전원이 턴을 종결한 IDLE 상태로 60분 지속되면 팀 정리 후보로 올린다. 루트 `seats.json`의 `_master`와 정본 harness 명부의 `_master` 두 역할을 동적으로 보호한다. HIL 대기, 사람 발주 대기, 선행 대기 카드, 진행 중 턴이 하나라도 있으면 팀 전체를 보호한다.
2. 후보 계획은 기존 `ft-tick.sh`의 기본 off step이 만든다. 실제 정리와 재개는 하네스팀이 명시 승인 아래 기존 도구로 집행한다. 후보 계획과 실정리 완료를 구분한다.
3. 재개는 하네스의 원 seq 수신 영수, 기존 resume, `ft-seat-close.sh --reopen`의 명부 복원, 실제 ready 수신 영수의 네 단계를 따른다. background는 하네스 큐를 recv하지 않는다. 직전 확정 cohort만 복원하고 ready를 좌석별로 누적하며 모든 ready 전에는 새 발주를 내리지 않는다.

원본 대화, baton, 재개 기록, 미커밋·미푸시 산출, 공유 상태, 카드 정본, 원장, HIL 항목과 브랜치는 삭제하지 않는다. 워크트리와 기존 사본은 보존 검증과 정리 계획을 거친다. `wt-sweep` 또는 `prune-missing` 호출만으로 잔여물이 0이라고 보고하지 않는다.
