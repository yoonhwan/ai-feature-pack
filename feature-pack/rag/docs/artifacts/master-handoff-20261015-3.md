골 원문(GOAL-LEDGER-airag.md 복붙):
최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 회복 관찰 + 6순위 C13(KakaoBot 통합 보고서) published 칸 채움.

# Master 승계 스냅샷 #2 → #3 (2026-10-15, 컨텍스트 450k 증류)

골의 어느 축인가: A03 — A02 트리 5순위(C12) 회복 관찰 + 6순위(C13) 보고서 마무리. 승계 첫 일 = 이 문서 + `.fable-team/state/airag/master-progress.md` 마지막 절 읽고 골 대조 + 부팅 3항(세션명 / 모델+창 / Serena 가부)을 mbox 로 보고한 뒤에만 착수.
작업 디렉터리: /Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant (브랜치 feature/rag-transplant, push 금지 — PUBLIC 리포). 답변 한국어, 호칭 "yoonhwan 오빠".

## 현재 상태 (실측 2026-10-15)
- **정지 유지**: planner(byz-planner-master-claude#36/#37) 지시 — 새 착수·spawn·push·좌석 개설 0. 서버가 올라오기 전엔 조치 0.
- `com.airag.consumer` = **disabled · 미로드** (10-13 오빠 승인으로 planner 가 bootout+disable 집행, rc=0). 사유: macOS «다른 앱 데이터 접근»(TCC) 팝업이 3시간 34회 — 조사 결과는 master-progress.md ⚠️ 두 줄. 가설(미확정): `op` 자식 프로세스가 1Password Group Containers 경로를 건드림. `op` 직접 실행 금지.
- 서버 18712(byz-embed)·18703(byz-llm) **미기동**(오빠가 직접 기동, 팀은 기동하지 않음). published 0 의 원인 = 임베딩 서버 다운(PROVIDER_UNREACHABLE retryable) — 서버가 올라오면 다음 틱에 자동 회복.
- repo HEAD b7b7e50(+ 이 스냅샷 커밋) · 작업트리 깨끗(`.claude/`·`CLAUDE.md` 미추적만). 생존 좌석: master 만(HELM·checker·nano·arch·DA 는 tmux 서버 사망으로 없음 — 재개 id 는 master-progress.md).

## 해야 할 것 (서버 기동 통보가 올 때만)
1. 오빠(또는 planner)가 «18712·18703 기동» 통보 → `launchctl enable gui/$(id -u)/com.airag.consumer` 먼저(plist·runtime.json 변경 금지) → HELM/오빠가 bootstrap.
2. 첫 틱 관찰: published 실패 14 → 성공, 새 summary 필드(published_failed·코드 top-3·degraded), 03:00 backup_created.
3. `KAKAOBOT-INTEGRATION-REPORT.md` 절 C published 칸·A.7 예시 채움(서버 복구 뒤 실측만, [실행]/[인용] 표기 유지) → 문서 DA 재리뷰 → 오빠 수용 → A03 종결 → A04.
4. 7일 `op read` 관찰(종결 기준: 단일 틱 key_error ≤1/7일 + 매일 03:00 backup_created; 설계 트리거: 연속 2틱 key_error·03:00 후 30분 초과 지연·7일 3회 이상). 안정 서명 러너는 서버 복구 뒤 architect 설계 주제.
5. 메모리 서버 18703 도달 여부 확인.

## 불변 규칙 (오빠 결정 — 재논의 금지)
- push 금지(PUBLIC). 키 값·비밀 출력 금지(키 이름만). 운영 DB 쓰기·runtime.json/plist 변경·런타임 재설치·서버 기동은 오빠 승인. `op` 직접 실행 금지. 훅·가드 우회 금지(막히면 mbox [HIL]). 좌석 개설/닫기는 래퍼(`ft-tmux-spawn.sh`·`ft-tmux-kill.sh`)만.
- Master 는 원인 규명·수정 위치 지정·DA 직접 소환 금지. 체인 checker → Master → architect → (DA) → Master → impl. 코드는 Nano.
- recv 출력은 버리지 않는다(READ 줄 인용). 발주 뒤 3초 busy 확인, 아니면 `ring`.
- 오빠 결정 기록: published 0 은 해결 후 보고 · 진단 개선(degraded, exit 0 유지) · 보고서 수령자 = KakaoBot 개발자 · 미수용 투어 11/12/13 및 이연 76건은 오빠 범위 결정, phase 8 종결 · P08A-02 = 후속 범위.

## 재개 id (닫힌 좌석)
- checker: `claude --resume 7d2d29b8-905e-454b-9845-91cd0cebdb50`
- nano: `claude --resume 5116bad8-241c-4f20-bae8-c48073643932`
- DA: `codex resume 01a0f693-a0d0-7a03-bd38-d07a46a67330 -c model_reasoning_effort="low" -c model="gpt-6.1-sol" -c service_tier=priority`

## 산출물 위치
- 진행표 `.fable-team/state/airag/master-progress.md`(gitignored) · DA 기록 `feature-pack/rag/docs/artifacts/da-2026100*-sol-*.md` · 보고서 `feature-pack/rag/docs/KAKAOBOT-INTEGRATION-REPORT.md` · HELM 스냅샷 #7 `helm-handoff-20261010-7.md`.
