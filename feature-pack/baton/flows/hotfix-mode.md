# F: hotfix-mode

## 시나리오

main 브랜치에서 직접 작업해야 하는 긴급 수정 플로우다. 옵션 B 가드가 평소에는 main에서 `plan`, `save`, `finish` 등의 명령을 차단하지만, `hotfix-mode`는 이 가드를 일시적으로 해제하는 lite mode를 활성화한다.

워크트리를 생성하지 않으므로 setup 비용이 없다. 완료 후에는 `hotfix-mode finish`로 lite mode를 종료하고 archive에 `tag: hotfix`만 기록한다.

## 신호 (이 케이스 식별 방법)

- prod 장애, 치명적 버그 등 즉각 수정이 필요한 상황
- 워크트리 생성 비용(~1분)을 감수할 여유가 없을 때
- 수정 범위가 1~3파일, 10~30분 이내로 완결되는 단순 fix
- 사용자가 "그냥 main에서 바로 고치자", "hotfix" 신호를 줄 때

## 단계별 시퀀스

```
사용자                    baton                      git/하네스
  │                         │                           │
  │ /baton:hotfix-mode start │                           │
  ├────────────────────────▶│                           │
  │                         │ 옵션 B 가드 일시 해제     │
  │                         │ .baton/hotfix.lock 생성   │
  │                         │ JOURNAL.md 임시 섹션 열기 │
  │                         │   ## Hotfix Start         │
  │                         │                           │
  │ (코드 수정 + 커밋)       │                           │
  ├─────────────────────────────────────────────────────▶│
  │                         │                           │ main 직접 수정
  │                         │ PostToolUse: JOURNAL.md  │
  │                         │ ACTIONS 섹션 append       │◀─┤
  │                         │                           │
  │ /baton:hotfix-mode finish│                           │
  ├────────────────────────▶│                           │
  │                         │ JOURNAL.md 섹션 닫기      │
  │                         │ archive tar.gz 생성:      │
  │                         │   tags: ["hotfix"]        │
  │                         │ INDEX.jsonl 갱신          │
  │                         │ hotfix.lock 삭제          │
  │                         │ 옵션 B 가드 복원          │
  │                         │                           │
  │              "✓ hotfix 완료. archive ID: xxx" 출력  │
```

## 단계

1. **hotfix-mode 진입** — `/baton:hotfix-mode start`
   - 동작: 옵션 B 가드 일시 해제, `.baton/hotfix.lock` 생성(재진입 방지), JOURNAL.md 임시 섹션 열기
   - 산출물: `.baton/hotfix.lock`, JOURNAL.md에 `## YYYY-MM-DD HH:MM — Hotfix Start` 헤더

2. **수정 작업** — 직접 코드 수정 또는 경량 하네스
   - 동작: 파일 수정, 커밋, 푸시
   - 산출물: main 브랜치에 직접 커밋(또는 fast-track PR)

3. **hotfix-mode 종료** — `/baton:hotfix-mode finish`
   - 동작: JOURNAL.md 섹션 닫기, archive에 `tag: hotfix`로 압축, `hotfix.lock` 삭제, 가드 복원
   - 산출물: `.baton/archive/<hotfix-id>_hotfix_<ts>.tar.gz`, INDEX.jsonl 갱신, `hotfix.lock` 삭제

## 명령 시퀀스

```bash
# [main root에서]
/baton:hotfix-mode start
# → .baton/hotfix.lock 생성
# → 옵션 B 가드 일시 해제

# 수정 작업 (직접)
# 파일 수정 → git add → git commit -m "fix: ..." → git push

# 또는 경량 하네스 사용
/superpowers:executing-plans
# → JOURNAL.md에 ACTIONS 기록

# hotfix 완료
/baton:hotfix-mode finish
# → archive에 tag:hotfix로 보관
# → .baton/hotfix.lock 삭제
# → 가드 복원
```

## 메모리 흐름

hotfix-mode는 lite mode이므로 phase.json, PLAN.md, NEXT.md를 생성하지 않는다.

- **PLAN.md** ← 생성하지 않음. 간단한 fix 의도는 `hotfix-mode start` 시 JOURNAL.md 헤더에 한 줄로 기록.
- **JOURNAL.md** ← `hotfix-mode start` 시 임시 섹션(`## YYYY-MM-DD HH:MM — Hotfix Start`) 열고 ACTIONS만 기록. `finish` 시 섹션 닫음.
- **CURRENT.md** ← 생성하지 않음. hotfix는 main 브랜치에서 직접 작업하므로 세션 인계 불필요.
- **NEXT.md** ← 생성하지 않음. hotfix가 완료되면 종료이므로 다음 세션 인계 불필요.

archive 구조 (lite):
```
.baton/archive/
├── INDEX.jsonl   ← tags:["hotfix"] entry 추가
└── hotfix-2026042714_hotfix_20260427_1430.tar.gz
    └── JOURNAL.md  ← PLAN/CURRENT/NEXT 없이 JOURNAL만 포함
```

## 핵심 결정 포인트

- **PR vs 직접 push**: main 브랜치 보호 정책에 따라 다름. baton은 강제하지 않음 — 팀 규칙을 따를 것.
- **hotfix가 예상보다 커지면**: `hotfix-mode finish --abort`로 lite mode를 종료하고 **A: plan-first** 또는 **B: wt-first**로 전환. 작업 내용은 stash 또는 별도 브랜치로 이동.
- **hotfix.lock이 잔존하면**: 이전 hotfix-mode가 비정상 종료된 것 — **G: orphan-recovery**에서 lock 삭제.

## 다음 케이스로 전이

- 보통 → 완료 (archive에 tag:hotfix 기록 후 종료)
- hotfix가 커져서 워크트리가 필요해짐 → `hotfix-mode finish --abort` 후 **A: plan-first** 또는 **B: wt-first**
- `hotfix.lock` 잔존 → **G: orphan-recovery**

## Don't

- `hotfix-mode start` 없이 main에서 baton 명령을 사용하지 말 것 — 옵션 B 가드가 차단
- hotfix-mode 중에 `/baton:wt-create`를 실행하지 말 것 — lite mode 내에서는 워크트리 생성 불필요
- `hotfix-mode finish` 없이 세션을 종료하면 `hotfix.lock`이 잔존 — 다음 세션 진입 시 **G: orphan-recovery**로 lock 삭제 필요
