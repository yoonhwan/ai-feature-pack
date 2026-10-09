최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — 남은 대상은 A02 트리 5순위 U2 상시 서비스(서버 부재로 bootout, 사용자 서버 기동 통보 대기) + 6순위 보고서 published 칸(서버 필요).
골의 어느 축인가: A03 — A02 트리 5순위(C12)·6순위(C13).

# HELM 인계 스냅샷 #7 (2026-10-10 03:2x, HELM ft-airag-helm-claude#6 · 컨텍스트 401k 경고)

## 지금 상태 한 줄
#6 구간(10-07 04:3x ~ 10-10 03:2x, 약 3일) 동안 변화 0. 18712(byz-embed)·18703(byz-llm) LISTEN 없음, com.airag.consumer bootout 그대로, HEAD 5a0d0f7 위 스냅샷 커밋뿐(73e9583 → 이 스냅샷).

## #6 구간에 한 일
- 승계 6단계 완료: 골 대조 #2429 · 크론 12afbb13(23,53) #2430 · #5 전환 확인 #2431.
- 30분 체크 루프 약 140회 — 매번 mbox 0건 · GOAL-OK · 서버 0 · master#2 입력 대기. 골 원장은 2시간 기한 전 --touch 유지.
- 10-08 16:2x 관찰: master-claude#2 권한 모드가 bypass → «manual mode on»으로 바뀜(누가 바꿨는지 화면에 없음). 되돌리지 않음 — 오빠에게 shift+tab 로 bypass 복귀 요청(16:24·16:54 보고). 답 없음, 지금도 manual.
- 같은 시각 주간 사용량 99% → 0% 초기화(6d23h) 확인 — 서버 복구 뒤 좌석 재개 시 한도 걱정 없음.
- 오빠에게 CLOSEOUT 전환(정본 1장 + 전부 닫기 → 서버 뜨면 새로 열기) 2회 제안(10-08 03:54 · 10-09 07:54). 답 없음 → 현 방식 유지.

## 좌석
- 살아 있음: helm-claude#6(나 → 유휴 보존) · master-claude#2(입력 대기, ctx 39%, manual mode, 대화 20700a59)
- 닫음(대화 보존): checker-claude#1=7d2d29b8-905e-454b-9845-91cd0cebdb50 · nano-r1#3=5116bad8-241c-4f20-bae8-c48073643932 · DA=`codex resume 01a0f693-a0d0-7a03-bd38-d07a46a67330 -c model="gpt-6.1-sol" -c model_reasoning_effort="low" -c service_tier="fast"`
- helm-claude#5: 유휴 보존(10-07 이후 접촉 없음)

## 서버 올라오면 할 일 (스냅샷 #4~#6 그대로)
1. `lsof -nP -iTCP:18712 -iTCP:18703 -sTCP:LISTEN` 두 포트 확인 → 오빠에게 즉시 알림.
2. 오빠 통보(=승인) 뒤 `launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.airag.consumer.plist` (plist·~/.config/airag/credential-source.json 변경 금지).
3. 첫 틱 `~/.local/share/airag/logs/tick-<YYYYMMDD>.log` 마지막 줄: published_succeeded 14 쪽 회복 · status·실패 코드 top-3 · backup_created · 64hex 0.
4. 관찰 수치로 보고서 절 C published 칸 → Master 경유 Nano → 변경분만 문서 DA 재리뷰 → 사용자 리뷰·수용 → A03 닫힘 → A04.
5. op read 관찰 종결 기준: 7일 key_error 단발 ≤1회 + 매일 03:00 backup_created.
- 주의: master#2 가 manual mode 면 명령마다 오빠 승인에서 멈춘다 — 재개 전 오빠에게 bypass 복귀 다시 확인.

## 알려진 운영 잡음
- 맥북 잠자기 동안 크론·틱이 비고 깨어나면 몰려 들어온다. 골 틱 «원장 다시 읽기»는 2시간마다 → 원장 읽고 --touch.
- 세션 크론은 7일 자동 만료 — 새 HELM 은 설치 시각 + 7일 전에 재설치.

## 운영 규칙
push 금지(PUBLIC) · 키 값 기록 금지 · runtime.json·런타임 재설치·launchd·운영 DB 쓰기·인프라 기동은 사용자 승인 · Master 금지 셋(원인 규명·수정 방향·DA 직접 소환)은 HELM 도 지킴 · 하위 좌석 AskUserQuestion 금지 · 골 원장 확인은 7200초 전에 --touch.
