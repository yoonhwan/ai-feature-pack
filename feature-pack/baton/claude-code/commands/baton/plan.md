---
description: 워크트리 안에서 phase.json 빈 stub 생성
argument-hint: <phase-id> [title]
allowed-tools: Bash
---

# /baton:plan

현재 워크트리에 `phase.json` 빈 stub을 생성합니다.
phase-id는 slug 형식(소문자+하이픈)을 사용하며, 외부 플래닝 하네스(superpowers:writing-plans, oh-my-claudecode:deep-interview 등)를 호출할 하네스 후보를 안내합니다.

## 사용법
```
/baton:plan <phase-id> [title]
```

## 동작 (v2 — PLAN.md 트리거 책임)
1. 옵션 B 가드 — main/master root에서 거부
2. `phase.json` 없으면 stub 생성 (보통 `/baton:wt-create` 가 이미 만들어 둠 → 통과)
3. PLAN.md 상태 점검:
   - 비어 있음/stub → 외부 plan 하네스 추천
   - 이미 작성됨 → 기존 섹션 헤더 표시 + 추가 작성 안내
4. `config.json.harnesses.preferred_plan` 우선 표시 + 다른 옵션 안내

## 실행
```bash
bash ~/.baton/current/bin/baton plan $ARGUMENTS
```

## 주의 / 가드
- **옵션 B**: main 또는 master 브랜치 root에서 실행 시 즉시 거부. 반드시 `/baton:wt-create <name>` → `cd .worktrees/<name>` 후 이 명령을 호출하세요.
- phase.json은 `.baton/` 내부에만 생성. 프로젝트 root에 잔존 금지.
- title 미입력 시 phase-id를 title로 사용.
- **선택 사항**: 가벼운 작업은 plan 없이 `wt-create` 후 바로 작업해도 됩니다 (B 케이스). plan은 큰 작업(2시간 이상, PR 여러 개)에만 사용합니다.

## 올바른 호출 순서
```bash
# [main 루트에서]
/baton:wt-create v5-pr-a3       # ① 항상 먼저

# [워크트리 안에서]
cd .worktrees/v5-pr-a3
/baton:plan v5-pr-a3            # ② 여기서 호출 (선택, 큰 작업만)
```

## 참고
- Flow A (plan-first): `flows/plan-first.md`
- 외부 하네스 추천: README.md "외부 하네스 추천" 표 (baton이 표준 instruction 동적 주입, yaml 카탈로그 없음)
- SPEC Rule 2: phase.json 스키마
