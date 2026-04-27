# baton v1.1 멀티 에이전트 시뮬레이션 시나리오

> tmux 통합(v1.1) 기준. `BATON_TMUX_ENABLE=true` 설정 후 전체 시나리오 동작.

---

## 시나리오 1: 단일 사용자 — 노트북 닫고 다른 머신에서 이어 작업

### 상황

아침에 회사 맥북에서 Claude Code로 작업 시작. 회의실로 이동하며 노트북 덮음.
회의실 데스크탑에서 tmux attach만으로 즉시 복원.

### ASCII 다이어그램

```
[회사 맥북]                        [회의실 데스크탑]

  Claude Code 세션                   $ ssh dev-box
       │                                   │
  /baton:wt-create v5-pr-a4               │
       │                                   │
  .worktrees/v5-pr-a4/ 생성              │
  tmux 세션: baton-byz-v5-pr-a4          │
       │                                   │
  작업 진행 중...                         │
  JOURNAL.md 자동 누적                   │
       │                                   │
  노트북 덮음 (Ctrl+B D — detach)         │
       │                                   │
  ┌────────────────────────────────────────▼──────┐
  │          tmux 세션 살아있음 (백그라운드)        │
  │          baton-byz-v5-pr-a4                   │
  │          CURRENT.md status: active            │
  └───────────────────────────────────────────────┘
                                         │
                             tmux a -t baton-byz-v5-pr-a4
                                         │
                             ┌───────────▼───────────┐
                             │  세션 그대로 복원      │
                             │  NEXT.md 자동 출력    │
                             │  "이어서 작업"        │
                             └───────────────────────┘
```

### 명령 시퀀스

```bash
# [회사 맥북 — 아침]
/baton:wt-create v5-pr-a4
# ✓ 워크트리 생성: .worktrees/v5-pr-a4
# ✓ tmux 세션 생성: baton-byz-v5-pr-a4

cd .worktrees/v5-pr-a4
/oh-my-claudecode:autopilot "v5 phase a4 구현"
# 작업 중...

Ctrl+B D  # tmux detach (세션 유지, 세션 종료 아님)

# [회의실 데스크탑 — 30분 후]
tmux a -t baton-byz-v5-pr-a4
# → 세션 그대로 복원, NEXT.md 자동 출력

# 또는 새 Claude Code 세션에서
cd .worktrees/v5-pr-a4
/baton:resume
# → NEXT.md 출력, 어디서 끊겼는지 즉시 파악
```

### baton 없으면?
세션 끊기는 순간 컨텍스트 증발. 다른 머신에서 다시 처음부터 설명해야 함.

### baton + tmux로 해결되는 점
tmux 세션이 살아있어 attach만으로 복원. NEXT.md가 "다음에 할 일"을 한 줄로 요약해 둠.

---

## 시나리오 2: 사용자가 워크트리 만들고 Hermes에 자율 위임

### 상황

사용자가 5분 투자해서 워크트리 + 지시를 세팅하고 detach.
Hermes(또는 다른 에이전트)가 1~2시간 자율 진행. 다음날 결과만 확인.

### ASCII 다이어그램

```
[사용자 — 5분]
      │
  /baton:wt-create v5-pr-a4
      │
  tmux a -t baton-byz-v5-pr-a4
      │
  ┌───▼────────────────────────────────────────────┐
  │  tmux 세션 안에서:                              │
  │  hermes "PLAN.md 보고 v5-pr-a4 phase 진행.    │
  │           완료 시 /baton:finish &&             │
  │           /baton:wt-clean"                     │
  └───┬────────────────────────────────────────────┘
      │
  Ctrl+B D  (detach)
      │
      ▼
  [Hermes 자율 진행 — 1~2시간]
      │
      ├─ SessionStart 훅: CURRENT.md status 확인
      │   → paused 상태면 /baton:resume 자동
      │
      ├─ UserPromptSubmit 훅: 매 INTENT → JOURNAL.md
      │
      ├─ PostToolUse 훅: 하네스 결과 → JOURNAL.md
      │   + CURRENT.md last_harness 갱신
      │
      ├─ (외부 하네스 호출, 코드 작성, 커밋)
      │
      └─ 완료 시:
          /baton:finish   → status: done
          /baton:wt-clean → archive 압축 보관
          tmux 세션 종료 알림

[사용자 — 다음날]
      │
  git pull
      │
  ~/.baton/current/bin/baton archive list
  # [v5-pr-a4_20260427_2231] feat/v5-pr-a4
  #   완료: 2026-04-27 22:31 | 세션 4개 | 하네스 8회
      │
  ~/.baton/current/bin/baton archive show v5-pr-a4_20260427_2231
  # PLAN.md, JOURNAL.md, CURRENT.md, NEXT.md
  # Hermes가 한 모든 결정 + turn 히스토리 즉시 조회
```

### 명령 시퀀스

```bash
# [사용자 — 설정 5분]
/baton:wt-create v5-pr-a4
tmux a -t baton-byz-v5-pr-a4

# 세션 안에서 Hermes에 지시
hermes "PLAN.md 보고 v5-pr-a4 phase 진행. 완료 시 /baton:finish && /baton:wt-clean"

Ctrl+B D   # detach, 세션 유지

# [다음날 — 결과 확인]
git pull
~/.baton/current/bin/baton archive list
~/.baton/current/bin/baton archive show v5-pr-a4_20260427_2231
# → JOURNAL.md에 Hermes 전체 행적 기록됨
```

### baton 없으면?
Hermes가 뭘 했는지 알 방법 없음. 로그가 흩어지거나 세션 종료 시 사라짐.

### baton + tmux로 해결되는 점
훅이 모든 turn을 JOURNAL.md에 자동 기록. archive로 영구 보관. 사용자는 git pull 후 즉시 조회.

---

## 시나리오 3: 멀티 에이전트 동시 (워크트리 3개, tmux 세션 3개)

### 상황

큰 기능을 3개 phase로 나눠 Claude Opus / Codex / Gemini가 동시 진행.
각자 독립 워크트리에서 충돌 없이 병렬 작업.

### ASCII 다이어그램

```
[사용자 — main]
      │
  /baton:wt-create phase-backend
  /baton:wt-create phase-frontend
  /baton:wt-create phase-infra
      │
      ▼
┌─────────────────────────────────────────────────────┐
│  tmux 세션 3개 (자동 생성)                           │
│                                                     │
│  baton-byz-phase-backend                           │
│  baton-byz-phase-frontend                          │
│  baton-byz-phase-infra                             │
└──────────┬────────────────┬──────────────┬──────────┘
           │                │              │
           ▼                ▼              ▼
   .worktrees/          .worktrees/    .worktrees/
   phase-backend/       phase-frontend/ phase-infra/
   port: 8090/3011      port: 8100/3021 port: 8110/3031
           │                │              │
     Claude Opus         Codex CLI     Gemini CLI
     (백엔드 API)         (프론트)      (인프라)
           │                │              │
           ▼                ▼              ▼
   JOURNAL.md           JOURNAL.md    JOURNAL.md
   (각자 독립 기록)      (각자 독립)   (각자 독립)
           │                │              │
           └────────────────┴──────────────┘
                            │
                   .baton/archive/INDEX.jsonl
                   (git-tracked, 3건 자동 누적)
                            │
                       git push
                            │
                   [크루 — 다른 머신]
                   git pull
                   /baton:archive search "phase"
                   → 3건 즉시 조회
```

### 명령 시퀀스

```bash
# [사용자 — main에서 워크트리 3개 생성]
/baton:wt-create phase-backend
/baton:wt-create phase-frontend
/baton:wt-create phase-infra

# 각 세션에 에이전트 할당
tmux a -t baton-byz-phase-backend
# → claude opus: /oh-my-claudecode:autopilot "백엔드 API 구현"
# Ctrl+B D

tmux a -t baton-byz-phase-frontend
# → codex exec: "프론트엔드 컴포넌트 구현"
# Ctrl+B D

tmux a -t baton-byz-phase-infra
# → gemini: "인프라 terraform 설정"
# Ctrl+B D

# [병렬 진행 — 사용자 개입 없음]

# [진행 상황 확인]
/baton:status
# 활성 워크트리:
#   - phase-backend  (feat/phase-backend)
#     tmux: baton-byz-phase-backend | attach: tmux a -t baton-byz-phase-backend
#   - phase-frontend (feat/phase-frontend)
#     tmux: baton-byz-phase-frontend | attach: tmux a -t baton-byz-phase-frontend
#   - phase-infra    (feat/phase-infra)
#     tmux: baton-byz-phase-infra    | attach: tmux a -t baton-byz-phase-infra

# [완료 후 각 워크트리 정리]
# 각 세션에서:
/baton:finish
/baton:wt-clean

# [전체 결과 조회]
/baton:archive list
# [phase-backend_xxx]  feat/phase-backend   완료
# [phase-frontend_xxx] feat/phase-frontend  완료
# [phase-infra_xxx]    feat/phase-infra     완료
```

### baton 없으면?
포트 충돌, 브랜치 혼선, 각 에이전트 결과가 어디 있는지 모름. 수동 조율 필요.

### baton + tmux로 해결되는 점
포트 자동 할당으로 충돌 0. 각 워크트리 독립 메모리. archive로 전체 결과 통합 조회.

---

## 시나리오 4: 엑스클로우 크루 — git archive로 결정 이력 공유

### 상황

크루 A(백엔드)가 작업 완료 후 push. 크루 B(프론트엔드)가 다른 머신에서 pull해서
A의 결정 + JOURNAL 전체를 즉시 파악하고 이어 작업.

### ASCII 다이어그램

```
[크루 A — 백엔드 개발자 (머신 1)]
      │
  /baton:wt-create glossary-fix
  # .worktrees/glossary-fix/ 생성
      │
  작업 진행
  PLAN.md: "glossary 정규화 정책 변경: 복수형 → 단수형"
  JOURNAL.md: 14 turns 자동 기록
      │
  /baton:finish
  /baton:wt-clean
  # → .baton/archive/glossary-fix_20260427_1530.tar.gz 생성
  # → INDEX.jsonl 갱신
      │
  git add .baton/archive/
  git commit -m "[chore] glossary-fix archive"
  git push
      │
      ▼
┌─────────────────────────────────────┐
│  .baton/archive/                    │
│    glossary-fix_20260427_1530.tar.gz│
│    INDEX.jsonl  ← git-tracked       │
└──────────────────────┬──────────────┘
                       │ git push
                       │
[크루 B — 프론트엔드 개발자 (머신 2)]
                       │
                  git pull
                       │
  ~/.baton/current/bin/baton archive search "glossary"
  # [glossary-fix_20260427_1530] feat/glossary-fix
  #   크루 A, 2026-04-27 15:30
  #   PLAN.md:14: glossary 정규화 정책 변경...
  #   JOURNAL.md:87: Turn 9 — 복수형 제거 완료, 단수형 통일
       │
  ~/.baton/current/bin/baton archive extract glossary-fix_20260427_1530
  # → /tmp/baton-extracted/glossary-fix_20260427_1530/
  #   PLAN.md / JOURNAL.md / CURRENT.md / NEXT.md
       │
  # A의 모든 결정 + 14 turn 히스토리 즉시 열람
  # "glossary 관련 프론트엔드 반영" 작업 시작
  /baton:wt-create glossary-fix-fe
```

### 명령 시퀀스

```bash
# [크루 A — 머신 1]
/baton:wt-create glossary-fix
cd .worktrees/glossary-fix
/baton:plan glossary-fix
# PLAN.md 작성: glossary 정규화 정책
/oh-my-claudecode:autopilot "glossary 정규화 구현"
/baton:finish
/baton:wt-clean

git add .baton/archive/
git commit -m "[chore] glossary-fix archive"
git push

# [크루 B — 머신 2]
git pull

# A가 한 일 검색
~/.baton/current/bin/baton archive search "glossary"
# 결과: [glossary-fix_20260427_1530] feat/glossary-fix

# 상세 조회
~/.baton/current/bin/baton archive show glossary-fix_20260427_1530
# → PLAN.md, JOURNAL.md 전체 출력

# 압축 해제 후 직접 열람
~/.baton/current/bin/baton archive extract glossary-fix_20260427_1530
cat /tmp/baton-extracted/glossary-fix_20260427_1530/PLAN.md

# A의 결정 파악 완료 → 프론트엔드 작업 시작
/baton:wt-create glossary-fix-fe
```

### baton 없으면?
크루 A가 슬랙에 "내가 이렇게 했어요" 메시지 남겨야 함. B는 코드 diff만 보고 맥락 역추적.
결정 이유는 알 수 없음.

### baton + tmux로 해결되는 점
archive가 git-tracked. push 한 번으로 크루 전체가 "이전에 비슷한 거 했나?" 즉시 조회.
JOURNAL.md로 결정 이유까지 파악.

---

## 시나리오 5: 노트북 잠깐 닫고 회의 다녀온 후

### 상황

회의 30분 다녀오는 동안 Claude Code 세션 + tmux 세션 유지.
돌아와서 attach만으로 즉시 복원.

### ASCII 다이어그램

```
[회의 전]
      │
  tmux 세션 활성:
  baton-byz-feature-x
  Claude Code 진행 중
  JOURNAL.md Turn 7 기록 중
      │
  노트북 덮음 (또는 화면만 잠금)
      │
      ▼
┌─────────────────────────────────────────┐
│  tmux 서버 (백그라운드 계속 실행)        │
│  baton-byz-feature-x                   │
│                                         │
│  SessionStart 훅 (선택 활성 시):        │
│    → "작업이 일시정지 상태입니다"        │
│    → CURRENT.md status 확인             │
│    → NEXT.md 요약 출력 준비             │
└───────────────────────────┬─────────────┘
                            │ 30분 후
                            │
[회의 후]                   │
                            ▼
  노트북 열기
       │
  tmux a -t baton-byz-feature-x
  # 세션 즉시 복원
  # 커서 위치, 실행 중이던 프로세스 그대로
       │
  /baton:resume   (또는 그냥 "이어서" 타이핑)
  # NEXT.md 출력:
  # "Turn 7까지 완료. 다음: translate_raw.py:113 수정 후
  #  테스트 실행 필요."
       │
  즉시 작업 재개
```

### 명령 시퀀스

```bash
# [회의 전 — 작업 중]
# Claude Code + tmux 세션 baton-byz-feature-x 실행 중
# 노트북 화면만 잠금 (tmux 서버는 계속 실행)

# [회의 후 — 30분 뒤]

# 방법 1: tmux attach (세션 완전 복원)
tmux a -t baton-byz-feature-x
# → 세션 그대로. 커서 위치, 이전 출력 모두 보임.

# 방법 2: 새 Claude Code 세션에서 재개
cd .worktrees/feature-x
/baton:resume
# → NEXT.md 출력 → 즉시 재개

# 방법 3: 키워드만으로
"이어서"   # 또는 "go", "continue", "next"
# → baton이 자동으로 /baton:resume 호출

# SessionStart 훅 (활성 시) 출력 예시:
# ⏸ 일시정지 상태: feature-x
# 마지막 업데이트: 2026-04-27 14:22
# 다음 할 일: translate_raw.py:113 수정 후 테스트
# 재개: /baton:resume 또는 "이어서"
```

### baton 없으면?
새 세션 열면 컨텍스트 0. "어디까지 했지?" 코드 diff 뒤지거나 Claude에 다시 설명해야 함.

### baton + tmux로 해결되는 점
tmux로 세션 자체가 살아있어 하드웨어 절전 후에도 복원. NEXT.md가 "다음 할 일" 한 줄로 준비.
SessionStart 훅이 일시정지 상태를 자동 감지해 알림.

---

## 요약 비교표

| 시나리오 | 핵심 기능 | baton 없을 때 비용 |
|---------|-----------|-------------------|
| 1. 머신 이동 | tmux 세션 영속 + resume | 컨텍스트 재설명 10~20분 |
| 2. 자율 에이전트 위임 | 훅 자동 기록 + archive | 행적 파악 불가 |
| 3. 멀티 에이전트 동시 | 포트 자동 할당 + 독립 메모리 | 포트 충돌, 수동 조율 |
| 4. 크루 결정 공유 | git-tracked archive + search | 슬랙 설명, 맥락 유실 |
| 5. 회의 후 복귀 | tmux + NEXT.md 자동 준비 | 재파악 5~15분 |
