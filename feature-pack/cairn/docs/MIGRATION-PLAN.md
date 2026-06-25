# cairn 마이그레이션 계획 (byzplan → feature-pack/cairn 설치형 패키지)

> 작업 워크트리: `ai-feature-pack/.worktrees/cairn` (브랜치 `feat/cairn`)
> 원본 v0: `BYZ-Plan/.worktrees/dogfood` (feat/dogfood, P1-P4 완성, DA APPROVED, 34커밋)
> 패키징 모델: baton install.sh 메커니즘 + **Python core**(cairn.py 단일). baton의 bash lib/*.sh는 불필요.
> 테스트: `cd feature-pack/cairn && /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Plan/.venv/bin/python -m pytest test/ -q` → 98 passed

## ✅ 1차 완료 (커밋 3c89207)
- 패키지 골격: `core/`(cairn.py, VERSION=0.1.0, bin/cairn, requirements), `test/`, `claude-code/hooks/`, `docs/`
- conftest core 경로 재배선
- **PKG_DIR 분리**: self-test golden 등 패키지 자산 = `PKG_DIR`(__file__ 기준), 런타임 원장 = `REPO`
- 98 passed + self-test OK

## 🎯 결정사항 (확정)
- 제품명/도구명 byzplan·BYZ-Plan → **전면 cairn**. 프로젝트 id `byz-plan`도 임시 테스트라 **데이터 초기화로 소멸**(치환 불필요)
- `.cairn/plan.yaml` 테스트 마일스톤 전부 삭제 → 빈 시드(`version: 1, projects: []`)로 시작
- BYZ-Plan 워크트리/브랜치 정리 + `.baton` 갱신은 마지막 단계

## 📋 남은 단계 (순서대로)

### 2.5 [핵심] REPO를 cwd 탐색으로 (TDD)
설치본이 **어느 프로젝트 cwd에서 실행되든** 그 프로젝트 `.cairn/`을 대상으로 동작해야 함. 현재 `REPO = Path(__file__).parent.parent`(패키지 루트)는 설치 시 `~/.cairn/...`을 가리켜 깨짐.
```python
def _find_repo():
    p = Path.cwd()
    for d in [p, *p.parents]:
        if (d / ".cairn").is_dir():
            return d
    return Path.cwd()
REPO = _find_repo()
```
- RED: cwd 하위 디렉토리에서 실행 시 상위 `.cairn` 탐색 검증
- 기존 테스트는 `_mp`로 REPO override라 대부분 안전, self-test는 PKG_DIR라 무관

### 3. claude-code/commands/cairn/*.md (슬래시 커맨드)
baton 패턴: 프론트매터 `description`/`argument-hint`/`allowed-tools: Bash` + 실행 블록 `bash ~/.cairn/current/bin/cairn <cmd> $ARGUMENTS`.
명령 목록(cairn.py dispatch 기준): status, show, overdue, render, set-status, set-date, set-priority, add-task, add-milestone, new-project, spawn, complete, return, map, link, reconcile, validate, self-test, revert, remove-task, remove-milestone, remove-project.

### 4. claude-code/skills/cairn/SKILL.md
name: cairn, description(트리거: "일정", "마일스톤", "복구 그래프", "spawn/complete" 등), 명령 매핑 테이블, 복구 메타 정책, Don't 규칙. references/에 cairn-design 요약.

### 5. install.sh / uninstall.sh (baton 기반 cairn화) — ⚠️ Python 의존성이 난점
baton install.sh를 베이스로:
- `GLOBAL_BASE="$HOME/.cairn"`, `TARGET="$HOME/.cairn/versions/$VERSION"`, current 심링, PATH `~/.cairn/current/bin`
- **Python 의존성**: cairn.py는 ruamel.yaml 필요. baton은 무의존 bash라 이 부분이 cairn 고유 과제. 방안:
  - `~/.cairn/venv` 생성 + `pip install -r requirements.txt` → `bin/cairn`이 `CAIRN_PYTHON=~/.cairn/venv/bin/python` 사용
  - 또는 시스템 pip(취약). venv 권장.
- core/ 복사 시 `core/cairn.py`가 `~/.cairn/current/cairn.py`로 가야 bin/cairn의 `$CAIRN_HOME/cairn.py`와 일치 (baton은 lib/, cairn은 단일 파일)
- ~/.claude/commands/cairn/ 복사 + ~/.claude/skills/cairn/SKILL.md 심링 + settings.json hooks(선택)
- 검증: `cairn doctor` ← **doctor 명령 신규 추가 필요**(cairn.py엔 없음). 또는 `cairn self-test`로 대체

### 6. manifest.json
name=cairn, version=0.1.0, title, description, category="planning", os, dependencies(cli: python3, pip: ruamel.yaml), supported_agents, spec_version.

### 7. README.md / INSTALL.md
baton 골격(README 16섹션, INSTALL 에이전트 자동수행 프롬프트). cairn 내용으로.

### 8. byzplan 전면 리네임 (docs)
대상(BYZ-Plan에서 가져올 문서 중): design-v1.md, REPORT-v1.5.md, NEXT.md, OPERATIONS-GUIDE.md, phase1.5-verification.md. byzplan/BYZ-Plan/plan.py → cairn. **단 역사 참조("전신")는 맥락 유지 판단**. 프로젝트 id byz-plan 언급은 데이터 초기화로 무의미해지므로 예시만 cairn 프로젝트로 교체.

### 9. .cairn 데이터 초기화
빈 시드 `.cairn/plan.yaml`(`version: 1\nprojects: []`). golden.yaml/view.md는 패키지 자산(test/)이라 **유지**(self-test용).

### 10. test/verify.sh
패키지 무결성 검증(core 파일 존재, manifest jq, pytest 98, bash -n install.sh, self-test).

### 11. 설치 검증
`bash install.sh` → `cairn self-test`(or doctor) → 임의 프로젝트 cwd에서 `cairn status` 동작 확인.

### 12. ai-feature-pack PR
feat/cairn → main PR (origin 있음).

### 13. BYZ-Plan 정리
- dogfood 워크트리 `.baton/handoff` 갱신("cairn → ai-feature-pack 이전 완료, BYZ-Plan deprecated")
- BYZ-Plan/.worktrees/dogfood 워크트리 제거, feat/dogfood 브랜치 처리
- BYZ-Plan repo 자체의 처리(아카이브?) 사용자 확인

## 핵심 난점 요약
1. **Python 의존성(ruamel)** — install.sh가 venv 구성. baton 무의존과 다른 cairn 고유 과제.
2. **REPO cwd 탐색** — 설치본이 cwd 프로젝트 .cairn 대상.
3. **doctor 명령 부재** — 설치 검증용 추가 또는 self-test 대체.
