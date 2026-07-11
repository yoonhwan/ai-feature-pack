---
description: 현재 작업 상태를 handoff 파일에 즉시 저장
argument-hint: [--skip-spawn]
allowed-tools: Bash, Write, Read
---

# /baton:save (v1.2.6+)

NEXT.md는 **현재 세션이 직접 작성** (풀 컨텍스트 보유).
`.events.jsonl` → JOURNAL.md / CURRENT.md 정리는 헤드리스 에이전트가 처리.

## 사용법
```
/baton:save              # 정상 동작
/baton:save --skip-spawn # 메타데이터만 갱신 (긴급 상황)
```

## 동작 (2-step)

### Step 0: 기존 NEXT.md 보존 (덮어쓰기 전 — 먼저)

```bash
bash ~/.baton/current/bin/baton next-archive || true
```

덮어쓰기 전에 현재 NEXT.md를 `.baton/handoff/next-archive/NEXT-{timestamp}.md`로
스냅샷합니다(라이브 NEXT.md는 그대로 유지, 다음 단계에서 덮어씀). 최근 20개까지 자동 보관.
`|| true` 필수 — `next-archive` 서브커맨드가 없는 구버전 설치(v1.2.14 이전)에서는
"unknown command"로 exit 1 하는데, 이 단계는 부가 기능이라 실패해도 Step 1/2(본 save 동작)를
막으면 안 됩니다. 구버전에서는 조용히 스킵되고 v1.2.14+ 설치 후 자동으로 동작 시작.

### Step 1: NEXT.md 직접 작성 (현재 세션 — 필수)

헤드리스 에이전트는 `.events.jsonl`(intent + harness 이벤트만 기록)만 볼 수 있어서
파일경로, 명령어, 실험결과, 성능수치, 배포상태 등 구체적 컨텍스트를 담지 못합니다.
**현재 세션이 풀 컨텍스트를 보유하고 있으므로 NEXT.md를 직접 작성합니다.**

1. `.baton/handoff/CURRENT.md` frontmatter에서 `phase` 필드를 Read.
2. `.baton/handoff/NEXT.md`를 Write — 형식:

```
<phase> 이어서. .baton/handoff/ 의 PLAN.md, JOURNAL.md, CURRENT.md 먼저 읽고 시작.

<현재 세션에서 한 일과 핵심 컨텍스트 3-10줄.
파일경로, 명령어, 실험결과, 성능수치, 배포상태, 다음 단계 구체 지시 등
다음 세션이 컨텍스트 없이도 즉시 재개할 수 있는 사실만 포함.>

**즉시 이어서**: <다음 세션이 가장 먼저 할 작업 한 줄 — 구체적 명령어/파일 포함>
**오늘 끝내기**: <이번 세션 목표 한 줄>
**마지막 사용 하네스**: <하네스 이름 또는 ->
```

- ≤1KB. 추측·기획 금지, 구체적 사실만.

### Step 2: bash save 실행

```bash
bash ~/.baton/current/bin/baton save $ARGUMENTS
```

bash save가 처리하는 것:
- CURRENT.md frontmatter `status: paused`, `last_updated`, `last_commit` 갱신
- save lock 획득 → snapshot rotate → 헤드리스 에이전트가 JOURNAL.md 정리
- RESUME_MSG.md 자동 생성 (Step 1에서 작성한 NEXT.md 마커에서 추출)

## 주의 / 가드
- **옵션 B**: main/master 브랜치 root에서 실행 시 거부
- 동시 `/baton:save` 호출은 lock으로 직렬화됨
- Step 1에서 NEXT.md 작성이 불가능한 경우(컨텍스트 부족 등), Step 2만 실행해도 됨 — bash fallback이 최소한의 RESUME_MSG.md를 생성합니다.

## 참고
- SPEC: race-free sidecar pipeline (1.2.4)
- v1.2.6: NEXT.md 직접 작성으로 전환 (헤드리스 컨텍스트 부족 문제 해결)
- v1.2.14: Step 0 추가 — 덮어쓰기 전 NEXT.md를 next-archive/로 스냅샷 (`baton next-archive`, 최근 20개 보관)
- 자동 호출: `/baton:finish`, `/baton:wt-clean` (events_count > 0 시) — 이 경로는 bash-only RESUME_MSG.md 빌더 사용
- 마이그레이션: `/baton:migrate` (v1.2.2 이하 워크트리에서)
