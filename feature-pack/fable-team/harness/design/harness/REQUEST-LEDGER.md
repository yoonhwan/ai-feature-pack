# REQUEST-LEDGER — 축 B 개선요청 원장 (행 추가만 · Issue 가 정본 · 여기는 인덱스)

| # | 접수 | 요청자 | 증상 1줄 | Issue | 오빠 값 | 반영 sha |
|---|---|---|---|---|---|---|
| R1 | 10-04 | byz-planner-arch#1(실측) | mbox send 본문에 백틱이 있으면 훅이 «명령 전체»를 차단 — 파일 편집 heredoc 까지 함께 죽음 · relay 안내만 있고 자동 우회 없음 | #799 | 머지 GO (13:4x) | dedceb2ba6 |
| R2 | 10-04 | byz-planner-arch#1(실측) | COMM-GUIDE-BOOT 매핑표 sha d64777274c4b371a(09-23) 정합 미검 · ft-version.sh check 경로 확인 | #800 | | |
| R3 | 10-04 | FB_CFO#52 #56468 | CI 「LLM Provider Contract」 잡이 main 실행에서 수시간 in_progress 멈춤 | #801 | | |
| R4 | 10-06 | ft-v65-master-claude#138 #57350 (오빠 육안) | auto VAD 개발 중 v65 한글 폴리싱 미반영 고장을 봤는데 «원래 있던 건지 우리가 만든 건지» 가를 v65 기본 동작 기준선이 없었음 → 기능 개발 전·중 v65 기본 동작 기준선 평가를 규칙/게이트로 · 수정 결과(원인·sha)는 v65 팀이 고친 뒤 추가 전달 · 사례 전문 /tmp/mbox/…CASE-polish-ko-not-applied-baseline-gap-20261006.md · C20(기준값)·C21(회귀 팩) 확장 후보 · 10-06 원인 확정(#57402): 폴리싱 첫 문장 미교정=설계(고장 아님·정본 개정 v65 진행) · 회귀 팩 후보 ①러너 settle 판독은 visible 탭에서만 ②press 전 발화 언어 명시 — 저장값 이월 금지(#57428: PRESS_SOURCE_LANG 미지정→브라우저 저장값 ja 이월·한국어 대본 무효) · 게이트 후보(#57433 오빠 원문 「byz-e2e에는 국가 지정이 있고 테스트 준비과정이 있는거야」): press 카드는 byz-e2e 표준 준비(UI 언어 지정·server-ready) 수행 기록이 없으면 발사 금지 — 근원은 tester 가 준비 과정을 건너뛴 것 · 회귀 팩 후보 ③시험 환경 충실도(#57475: 운영 Redis=REDIS_7_0(prod STANDARD_HA·dev·ccu)·CI 7.0.15 일치·로컬 7.4 불일치 → CI Redis 를 7.4 로 올리지 말 것 · 시험은 버전 인지형으로 보충 중) | #834 (Tank 등록 10-07) | | |
| R5 | 10-06 | byz-planner-arch#3 #57528 | v65-goal-commit-msg.sh 가 feat/v6-realtime-live «머지 커밋»에도 M/K 골좌표를 요구(제품 경로 staged→[chore] 거부·머지 예외 0) → main 병합이 --no-verify 로만 가능. 요건: MERGE_HEAD 존재 시 통과 또는 «main 조상 커밋만 포함» 검사 · 대상 scripts/git-hooks/v65-goal-commit-msg.sh | #835 (Tank 등록 10-07) | | |
