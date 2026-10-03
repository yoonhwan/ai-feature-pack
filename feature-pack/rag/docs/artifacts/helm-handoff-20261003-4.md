최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — 지금 대상은 A02 트리 5순위 U2 상시 서비스(서버 부재로 bootout, 사용자 서버 기동 통보 대기) + 6순위 보고서 게시 수치 칸.
골의 어느 축인가: A03 — A02 트리 5순위(C12) · 6순위(C13).

# HELM 인계 스냅샷 #4 (2026-10-03 13:4x, HELM ft-airag-helm-claude#3 · 컨텍스트 400k 경고)

## 지금 상태 한 줄
코드 쪽 열린 일 0. 남은 막힘은 하나 — **임베딩 서버 byz-embed(127.0.0.1:18712)·memory LLM byz-llm(18703)이 LISTEN 없음**. 상시 서비스 com.airag.consumer 는 10-02 15:54 bootout 상태 그대로(사용자 결정 «서버 복구 통보 전 재개 금지», 03:00 슬롯 백업 증거는 재개 뒤로 이월). 10-02 23:4x 이후 커밋·좌석 활동 없음, 10분 점검만 계속.

## 사용자가 «서버 올렸다»고 알려 주면 할 일
1. `lsof -nP -iTCP:18712 -iTCP:18703 -sTCP:LISTEN` 로 두 포트 LISTEN 확인.
2. 서비스 재개: `launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.airag.consumer.plist` (plist·자격 파일 ~/.config/airag/credential-source.json 유지 — 변경 금지).
3. 첫 틱 관찰: `~/.local/share/airag/logs/tick-<YYYYMMDD>.log` 마지막 줄 — 기대: published_succeeded 가 14 쪽으로 회복(실패 창은 retryable pending, DB 쓰기 불필요) · 새 요약 필드(status degraded/ok · 실패 코드 top-3) · 03:00 슬롯 backup_created(첫 성공 틱이 대신 만듦) · 64hex 0. 키 읽기 실패 시 로그 type 에 예외 클래스명.
4. 관찰 결과로 6순위 보고서(feature-pack/rag/docs/KAKAOBOT-INTEGRATION-REPORT.md) 절 C 의 published 수치 칸 채우기 → Master 경유 Nano. 그 뒤 사용자 리뷰·수용 → A03 닫힘 판정 → A04(투어·운영 검증·완료 판정).
5. op read 관찰 종결 기준(architect 채택): 7일 key_error 단발 ≤1회 + 매일 03:00 backup_created / 설계 트리거: 2틱 연속·03:00 후 첫 성공 틱 30분+ 지연·7일 3회+.

## HELM#3 구간에 닫힌 것 (10-02 17:2x ~ 10-03)
- 진단 가시성(degraded=any-fail·실패 코드 top-3): Nano#2 f28e936·63ed629 → 코드 DA r2 PASS(87a1225) → minor «or True» 7f72839 → DA r3 PASS(d0d822f).
- 런타임 재설치 1차(사용자 «지금 재설치»): 87a1225 휠 · 백업 runtime.bak-20261002-1755.
- 15:42 exit 30 OP_READ_UNAVAILABLE 1회: checker 사실(checker-op30-facts.json) → architect 판정(타임아웃 또는 exec OSError, C12 영향=지연·놓침 아님) → kind 기록 3줄 Nano 7e7a81f·86045ad → DA PASS 0/0/0(667cd43).
- 런타임 재설치 2차(사용자 «지금 재설치»): 667cd43 휠(consumer 42a93b2a… · core d909cb58… 불변) · 백업 runtime.bak-20261002-2343 · 설치 모듈 46개 해시=HEAD.
- 6순위 보고서 절 C·D 초안 a4e589b · bd06533 · 07e0bd1(Claude 좌석 수집 불가 근거).

## 사용자 결정 (지시 원장 INSTRUCTION-LEDGER-airag.md 17:5x·20:1x·22:3x 절)
재설치 2회 승인(각 1회분) · 서비스 «중지 유지» · kind 기록 3줄 «한다·DA 가벼운 리뷰» · 관찰 종결 기준 architect 안 채택 · push 계속 보류(A04 때 공개 적합성 검토 후 재질문).

## 좌석 (13:4x)
- 살아 있음: helm-claude#3(나, 유휴 예정) · master-claude#2(대기).
- 좀비 정리로 회수(대화 기록 보존, «쓰던 좌석만 복구» — 발주 생기면 같은 대화로 되살림): nano-r1#2(06시) · da-codex#0·arch-claude#1·checker-claude#0(05시) · arch#0·helm#2·master#1·nano-r1#1(02시). DA 되살리기: `codex resume 01a0f693-a0d0-7a03-bd38-d07a46a67330 -c model="gpt-6.1-sol" -c model_reasoning_effort="low" -c service_tier="fast"` (또는 zombie-clean.sh restore).

## 운영 규칙
push 금지(PUBLIC) · 키 값 기록 금지 · runtime.json 변경·런타임 재설치·launchd 변경·운영 DB 쓰기·인프라 기동은 사용자 승인(재개 bootstrap 은 서버 복구 통보가 곧 승인) · Master 금지 셋(원인 규명·수정 방향·DA 직접 소환)은 HELM 도 지킴 · 하위 좌석 AskUserQuestion 금지 · 골 원장 확인은 2시간 기준 전에 미리 --touch.
