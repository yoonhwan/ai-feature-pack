# 인덱스: mbox.sh 200줄 이하 분리 — 동작 변화 0 [structure] (CLAUDE.md Code Metrics · 판정 #62814 arch 회신 #62821)
<!-- ledger: design/teams/harness/GOAL-harness.md -->
- Issue: 없음 → master #62814 질의 · arch 판정 #62821(나노 4 카드 범위 밖 · 위생 대기 1장)
- 상태: 대기
- 선행: 나노 4(인박스 · nano/v425-master-inbox) 랜딩 · 나노 3(대기/v423-publish-report-hooks.md) 랜딩 — 둘 다 mbox.sh 를 만지므로 그 뒤에 한 번에 쪼갠다(충돌 0)
- 시험 입력: 기존 mbox 시험 + 임시 FT_ROOT 에서 send·relay·recv·peek·ring 왕복 — 실제 좌석 쪽지 0
- 기준값: 라이브 `.fable-team/comm/mbox.sh` 226줄(2026-10-08 실측) · `tools/comm-canonical/mbox.sh` 동기화 뒤 226 + 나노 4 훅

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: C(업그레이드 반영 — 통신 도구를 고치는 카드가 200줄 한도에 계속 걸려 반송되지 않게). 핵심 한 줄: mbox.sh 를 기능 무변화로 서브명령별 파일로 나눠 200줄 이하로 만든다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
CLAUDE.md Code Metrics 는 파일 200줄 한도다. 라이브 mbox.sh 는 이미 226줄이고 정본 사본(tools/comm-canonical)이 라이브보다 뒤처져 있다가 나노 4 가 같은 바이트로 맞췄다. 기능 카드(인박스·보고 훅)가 이 파일에 몇 줄씩 더할 때마다 한도 위반이 «기능 카드 탓»으로 반송된다. 이 카드는 동작을 바꾸지 않고 서브명령(send·relay·recv 계열·doorbell 도우미)을 같은 디렉터리의 source 파일로 나눈다. 진입점 이름·인자·출력·rc 는 바이트 단위로 같아야 한다.

## 사전검증
- 소환: 아니오
- 면제: 동작 변화 0 인 [structure] 분리 · 같은 입력의 출력·rc 대조 시험으로 닫음 — arch 서명 byz-harness-arch-claude#14

## 조사 근거
- `tools/comm-canonical/mbox.sh:147` send 분기(가장 긴 블록) · 같은 파일 relay 분기 · doorbell_status 도우미.
- `tools/comm-canonical/check-drift.sh` 정본↔라이브 차이 점검 도구(분리 뒤 새 파일도 대상에 넣는다).

## 구현 범위 (닫힌 목록)
1. `tools/comm-canonical/mbox.sh` → 진입점(인자 분기만) + `tools/comm-canonical/mbox_send.sh`·`mbox_util.sh` 등 source 파일(각 200줄 이하 · 이름은 나노 결정).
2. `tools/comm-canonical/check-drift.sh` 대상 목록에 새 파일 추가.
3. 시험: 분리 전 HEAD 와 분리 뒤에서 같은 시나리오(send·relay·recv·peek·ring · 가드 거부 exit 3 · --no-notify 경고)의 stdout·stderr·rc 동일 diff 0.

커밋은 자기 브랜치, **push 금지**. **금지**: 동작·메시지 문구 변경 · mbox.py 수정 · 라이브 .fable-team/comm 쓰기(설치는 master).

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- 분리 전후 출력 diff 0 · 각 파일 200줄 이하 · bash -n · shellcheck 새 경고 0.
- 카드 증거 줄 형식: `세트: <40hex> · 시험: <명령 1개> rc=0 · 이슈: 0`.
- 랜딩 뒤 master 집행: 라이브 comm 에 진입점+새 파일 cp · check-drift OK.

## 상태
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#14 · #62821).
- 정본 영향 없음: 통신 도구 구조 분리만.
