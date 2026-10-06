최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — 남은 대상은 A02 트리 5순위 U2 상시 서비스(서버 부재로 bootout, 사용자 서버 기동 통보 대기) + 6순위 보고서 published 칸(서버 필요).
골의 어느 축인가: A03 — A02 트리 5순위(C12)·6순위(C13).

# HELM 인계 스냅샷 #6 (2026-10-07 04:0x, HELM ft-airag-helm-claude#5 · 컨텍스트 400k 경고)

## 지금 상태 한 줄
서버 없이 할 수 있는 일은 10-04에 다 닫았다. 그 뒤 약 2.5일 동안 변화가 없다. 18712(byz-embed)·18703(byz-llm)은 LISTEN 없음, com.airag.consumer는 bootout 상태 그대로, HEAD 5a0d0f7.

## #5 구간에 한 일 (10-04 12:2x ~ 10-07)
- 서버 불필요 칸 S1~S7(종료코드 표·PROCESSING_FAILED 1곳·P08A-02 미구현·휠 설치·15:12 호출 주체·core 회귀 502 passed): c4580aa
- 사용자 판정 P08A-02 «후속 범위로 기록»: 8837bcb (B.2 행·D.11)
- 사용자 판정 문서 DA «지금 서버 무관 부분»: r1 REJECT 0/2/2(6b51c45) → Nano 수정 2d09cdd → r2 PASS 0/0/1(5a0d0f7)
- 사용자 판정 «작업 좌석만 닫기»: checker-claude#1·nano-r1#3·da-codex#0 를 1회 토큰으로 ft-tmux-kill.sh 집행
- 사용자 판정 «점검 간격 늘리기»: 체크 루프 30분(23,53분)
- 좀비 정리로 helm-claude#4 회수(10-05 18:21, 복구 안 함)
- 보고 틀: 사용자 10-05 지시 «사람이 읽는 보고» — 결론 1줄 → 오빠 할 일 → 바뀐 것 3줄 이내 → 근거 1줄(커밋·경로는 맨 끝)

## 좌석
- 살아 있음: helm-claude#5(나 → 유휴 보존) · master-claude#2(입력 대기, ctx 39%, 대화 20700a59)
- 닫음(대화 보존): checker-claude#1=7d2d29b8-905e-454b-9845-91cd0cebdb50 · nano-r1#3=5116bad8-241c-4f20-bae8-c48073643932 · DA=`codex resume 01a0f693-a0d0-7a03-bd38-d07a46a67330 -c model="gpt-6.1-sol" -c model_reasoning_effort="low" -c service_tier="fast"`

## 서버 올라오면 할 일 (스냅샷 #4·#5 그대로)
1. `lsof -nP -iTCP:18712 -iTCP:18703 -sTCP:LISTEN` 두 포트 확인.
2. `launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.airag.consumer.plist` (plist·~/.config/airag/credential-source.json 변경 금지 — 서버 복구 통보가 곧 승인).
3. 첫 틱 `~/.local/share/airag/logs/tick-<YYYYMMDD>.log` 마지막 줄: published_succeeded 14 쪽 회복 · status·실패 코드 top-3 · backup_created · 64hex 0.
4. 관찰 수치로 보고서 절 C published 칸 → Master 경유 Nano → 변경분만 문서 DA 재리뷰 → 사용자 리뷰·수용 → A03 닫힘 → A04.
5. op read 관찰 종결 기준: 7일 key_error 단발 ≤1회 + 매일 03:00 backup_created.

## 알려진 운영 잡음
- 맥북 잠자기 동안 크론·틱이 비고, 깨어나면 몰려 들어온다(10-05·10-06 실측). 골 틱 «원장 다시 읽기»는 2시간마다 온다 → 원장 읽고 --touch 로 처리.
- 대기가 길어지면 사용자에게 CLOSEOUT(정본 1장 + 전부 닫기) 전환을 한 번 제안했으나(10-05 16:2x) 답 없음 — 사용자 결정 전까지 현 방식 유지.

## 운영 규칙
push 금지(PUBLIC) · 키 값 기록 금지 · runtime.json·런타임 재설치·launchd·운영 DB 쓰기·인프라 기동은 사용자 승인 · Master 금지 셋(원인 규명·수정 방향·DA 직접 소환)은 HELM 도 지킴 · 하위 좌석 AskUserQuestion 금지 · 골 원장 확인은 7200초 전에 --touch.
