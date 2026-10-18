최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 회복 관찰 + 6순위 C13(KakaoBot 통합 보고서) published 칸 채움.
골의 어느 축인가: A03 — C12·C13. 판정 2303 «전팀 증류 레디 → 팀장만 남기고 종료레디» 인계서 (ft-airag-master-claude#8 · 2026-10-19)

# AIRAG 인계서 — 증류 레디 (정지 상태)

## 팀 상태 (정지 · 오빠 재개 지시 전까지 새 작업 0)
- 열린 단위: A03 DOING(C12 consumer 회복 관찰 미달 · C13 KakaoBot 통합 보고서 published 칸 미채움) · A04 BLOCKED_BY_A03.
- 운영 상태: launchd `com.airag.consumer` = bootout + disabled (재적재 0). plist `~/Library/LaunchAgents/com.airag.consumer.plist` 그대로. 시험 라벨(opprobe.*) 없음.
- 막힌 원인: launchd 아래 틱이 `op read` 를 부르면 macOS «다른 앱 데이터» 권한 창이 매번 뜸(허용이 세션 한정). 터미널 아래에서는 창 없이 성공.
- 후보 판정: R-D·R-S·R-L·R-P·R-F(FDA)·R-B·R-E ✗ / R-H(op 자식 HOME 격리) 터미널 로그 시험 통과(`feature-pack/rag/docs/artifacts/oprh-20261018-104235.txt`) / R-F(0600 평문 키 사본) 구현만·오빠 보류 / 폴백 R-SDK.
- 오빠 새 방향(planner#68 #2908): launchd 데몬 폐기 → «airag 를 앱으로 등록하고 폴더 권한 1회» (KakaoBot 처럼 독립 프로세스). «설치+launchd 첫 틱» 단계는 이 방향으로 재설계.

## 커밋 (브랜치 feature/rag-transplant · push 0 · PUBLIC 저장소 — push 는 별도 승인)
- 3b9f1fd tick 키 파일 원천(R-F · store_keys_file 설정 없으면 비활성)
- 82a5b73 [wip] R-H op 자식 HOME 격리 — 신규 시험 18개 통과 · **기존 tick 회귀(9 파일) 미실행 · DA 미요청**
- 증거 문서: `feature-pack/rag/docs/artifacts/` arch-20261018-opread-prescription / opread-nopopup / escalation-fable·astra-nopopup / opre·oprh 시험 원문 / tcc-log-20261018-0945.txt
- 계획·발주 파일(미추적): `.fable-team/state/airag/` · `.fable-team/prompts/`

## 대기 값 (남의 회신)
- 오빠 재개 지시(하네스 완성 뒤). 재개 때 arch 가 R-H 커밋(82a5b73) 처분 + 앱 등록 방식 재설계.

## 다시 여는 법
1. 현역 planner 좌석 확인(`tmux ls | grep planner-master`) → 재개 발주 recv.
2. 골 원문 3줄 + 축(A03 C12) 매핑 보고 → 착수.
3. arch 에 «서명 앱 1개 + 폴더 권한 1회» 재설계 발주 → 필요하면 R-H 회귀(`pytest` tick 관련 9 파일) 후 astra DA.
4. 클릭 시험·권한 창 띄우는 실행 금지 — 시험은 터미널 로그 전용.
5. 좌석은 새로 연다(arch·DA·nano). 재개 기록으로 `zombie-clean.sh resume '<세션명>'` 가능.
