최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — 지금 대상은 A02 트리 5순위 U2 상시 서비스(서버 부재로 bootout, 사용자 서버 기동 통보 대기) + 6순위 보고서 게시 수치 칸.
골의 어느 축인가: A03 — A02 트리 5순위(C12) · 6순위(C13).

# HELM 인계 스냅샷 #5 (2026-10-04 12:1x, HELM ft-airag-helm-claude#4 · 컨텍스트 401k 경고)

## 지금 상태 한 줄
#4 구간(10-03 13:4x ~ 10-04 12:1x) 동안 변화 0 — 커밋·좌석 활동·mbox 0, 18712(byz-embed)·18703(byz-llm) LISTEN 없음(10분마다 확인), com.airag.consumer bootout 유지. 10-04 03:00 슬롯 백업도 서비스 중지로 미생성(사용자 결정 «재개 뒤로 이월»).

## 사용자 지시 (10-04 12:1x, 이 증류의 근거)
HELM 이 «마감 후 전부 닫기 / #5 증류 / 서버 올림» 을 물었고 사용자 답: «증류해서 계속 작업해야지 끝났어?» → 마감(닫기) 아님. 증류하고 계속 작업한다. 후계는 «서버만 기다리는 대기»로 두지 말고 서버 없이 진행 가능한 일을 찾는다.

## 서버 올라오면 할 일 (스냅샷 #4 그대로)
1. `lsof -nP -iTCP:18712 -iTCP:18703 -sTCP:LISTEN` 두 포트 확인.
2. `launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.airag.consumer.plist` (plist·~/.config/airag/credential-source.json 변경 금지 — 서버 복구 통보가 곧 승인).
3. 첫 틱 `~/.local/share/airag/logs/tick-<YYYYMMDD>.log` 마지막 줄: published_succeeded 14 쪽 회복 · status·실패 코드 top-3 · backup_created · 64hex 0.
4. 관찰 수치로 KAKAOBOT-INTEGRATION-REPORT.md 절 C published 칸 → Master 경유 Nano → 사용자 리뷰·수용 → A03 닫힘 → A04.
5. op read 관찰 종결 기준: 7일 key_error 단발 ≤1회 + 매일 03:00 backup_created.

## 좌석 (12:1x)
- 살아 있음: helm-claude#4(나 → 유휴 보존) · helm-claude#3(유휴 보존) · master-claude#2(입력 대기, 오류 없음, ctx 28%, 화면상 주간 사용량 98%).
- 회수(대화 보존): nano-r1#2 · da-codex#0 · arch-claude#1 · checker-claude#0 외. DA 되살리기 `codex resume 01a0f693-a0d0-7a03-bd38-d07a46a67330 -c model="gpt-6.1-sol" -c model_reasoning_effort="low" -c service_tier="fast"`.

## 운영 규칙
push 금지(PUBLIC) · 키 값 기록 금지 · runtime.json·런타임 재설치·launchd·운영 DB 쓰기·인프라 기동은 사용자 승인 · Master 금지 셋(원인 규명·수정 방향·DA 직접 소환)은 HELM 도 지킴 · 하위 좌석 AskUserQuestion 금지 · 골 원장 확인은 7200초 전에 --touch.
