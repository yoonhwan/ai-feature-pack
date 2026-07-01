# cairn agent-lifecycle hook — design

Date: 2026-07-01
Origin: SingleRT_ORCH#3 세션에서 `set-status task active` 실패 리포트 → 근본 원인 추적 중 "agent가 cairn 상태를 안 챙긴다"는 더 큰 문제로 전환.

## 문제

1. Claude Code / Codex 세션이 task를 시작·완료해도 `cairn set-status`를 부르지 않아 `.cairn/plan.yaml`이 실제 진행상황과 어긋난다. 시작(doing 전환)과 완료(done 전환) 양쪽 다 동등하게 방치된다.
2. `cairn-auto-progress` 훅(완료 쪽 evidence 감지 + apply)이 이미 존재하지만, `~/.claude/settings.json`·`~/.codex/hooks.json` 어디에도 wiring되어 있지 않다 — 만들어놓고 연결을 안 한 상태.
3. task status 어휘(`todo/doing/done/blocked`)가 milestone 어휘(`planned/active/done/blocked`)와 달라, 사람·에이전트가 관성적으로 `active`를 task에 썼다가 `bad task status: active`로 실패한다. 에러 메시지도 valid 값을 안 보여준다.
4. 이 wiring은 per-machine dotfile(`~/.claude/settings.json`, `~/.codex/hooks.json`)에 들어가므로 git으로 전파되지 않는다 — 새 머신/재설치 시 수동으로 다시 걸어줘야 하는데 그 절차가 없다.

## 범위 밖

- Hermes(`~/.hermes/`)는 이번 범위 밖. `~/.hermes/hooks/`는 비어 있고, Hermes의 역할은 task-monitor/watchdog류 감시·알림이지 cairn task를 직접 진행하는 코딩 에이전트가 아니다. 훗날 Hermes가 내부적으로 Codex CLI를 셸아웃해 실개발을 시키게 되면 그 머신의 `~/.codex/hooks.json`을 통해 동일 로직을 자동으로 타게 되므로 별도 통합이 필요 없다.
- blocking gate(상태 미갱신 시 커밋/종료 차단)는 채택하지 않는다 — 오탐 시 작업이 막히는 리스크가 이득보다 크다.

## 설계

### 아키텍처

`cairn-auto-progress` 스크립트 하나를 확장해 시작/완료 양방향을 처리한다. 어느 하네스(Claude Code vs Codex)가 불렀는지는 스크립트가 몰라도 되도록, 방향은 **wiring 설정이 환경변수로 명시**한다(하네스별 stdin JSON 스키마 차이에 의존하지 않음).

```
~/.claude/settings.json   SessionStart → CAIRN_HOOK_EVENT=session-start cairn-auto-progress
                           Stop         → CAIRN_HOOK_EVENT=stop         cairn-auto-progress
~/.codex/hooks.json        SessionStart → (동일)
                           Stop         → (동일)
```

기존 baton 훅(SessionStart/UserPromptSubmit/PreCompact/SessionEnd/PostToolUse) 배열에 엔트리를 추가하는 것이며, 기존 엔트리는 건드리지 않는다.

### 컴포넌트

**1. `resolve_task_id()` (기존 로직 재사용, 공유화)**
branch명의 `t<N>` → 없으면 단일 `doing` task → 없으면 `CAIRN_TASK_ID` env. 시작/완료 양쪽에서 동일 함수 사용.

**2. `session-start` 분기 (신규)**
- task 특정 성공 + 현재 status가 `todo`일 때만 `doing`으로 전환.
- evidence 텍스트 검사 없음 — 시작에는 "증명"이 필요 없다.
- 모호하면(브랜치에 `t<N>` 없고 `doing` task도 0개 또는 2개 이상) 무음 스킵. 원장을 잘못된 값으로 덮어쓰지 않는다.

**3. `stop` 분기 (기존 그대로, 무변경)**
BTS/verification pass 텍스트 감지(stdin + `.baton/handoff/*`) + task 특정 → `CAIRN_AUTO_PROGRESS=apply`면 `cairn complete` 호출. 기존 candidate-only 기본값·안전 경계(force 플래그 등) 그대로 유지.

**4. `set-status` status alias (cairn.py)**
- `kind=task`일 때 입력값 `active`를 저장 전에 `doing`으로 정규화. `STATUS_TASK` 내부 canonical 값은 그대로 `doing` 유지(데이터 마이그레이션 불필요, `_task_tag` 등 기존 비교 로직 무변경).
- validate/set-status 에러 메시지에 valid 목록 노출: 예) `bad task status: active (valid: todo, doing, done, blocked; alias: active→doing)`.

**5. installer 멱등 wiring + 업데이트 가이드 (신규)**
- `install.sh`가 재실행돼도 안전하도록 — `~/.claude/settings.json` / `~/.codex/hooks.json`의 다른 엔트리(baton 등)를 건드리지 않고 cairn 엔트리만 upsert(동일 command 문자열 기준 존재 확인 후 추가/스킵, 중복 삽입 방지).
- `INSTALL.md`에 "## 기존 설치 업데이트" 섹션 신설: `bash install.sh` 재실행 한 줄로 새 wiring이 들어간다는 안내 + 확인 커맨드(`cairn self-test`, wiring 확인용 grep).
- 버전업 안내 문구: "cairn Xu → Yu: agent-lifecycle hook 추가됨, `bash install.sh` 재실행 필요."

### 데이터 흐름

세션 시작 → hook이 branch로 task 추론 → todo면 doing 전환 커밋(git add plan.yaml/view + commit, 기존 `transaction()` 재사용). 작업 중 사람/agent가 수동으로 `cairn set-status`를 부를 일이 줄어든다. 세션 종료(Stop) → evidence 감지 → done 전환 커밋. 양쪽 다 실패 조건(모호/증거없음)에서는 조용히 스킵 — 자동화가 원장을 그릇된 값으로 덮어쓰는 경로는 없다.

### 에러 처리

- 훅 스크립트 자체 실패는 exit 0으로 흡수 — 세션 시작/종료를 절대 막지 않는다(fail-open이 맞는 편의 자동화 영역, `#0 RULE` 대상 아님 — 외부 신뢰 경계가 아니라 UX 자동화이므로).
- git commit 단계 실패는 기존 `transaction()`의 rollback 로직(`git reset` + `git checkout` on `plan.yaml`/`view`) 그대로 재사용, 신규 코드 없음.

### 테스트

- `test/test_cairn.py`에 status alias 정규화 케이스 추가(`active` 입력 → `doing` 저장 확인, 에러 메시지 valid 목록 포함 확인).
- `session-start` 분기: 테스트 워크트리에서 `CAIRN_HOOK_EVENT=session-start` 직접 실행 → todo→doing 확인. 모호 케이스(브랜치 무관/복수 doing) → no-op 확인.
- `stop` 분기: 기존 동작 회귀 없는지 재확인(변경 없음이므로 기존 테스트로 충분).
- installer: 재실행 후 settings.json/hooks.json에 cairn 엔트리가 중복 없이 정확히 1개씩만 있는지 확인.

## 결정 로그 (Q&A)

| 질문 | 결정 |
|------|------|
| 시작 vs 완료, 뭐가 더 아픈가 | 둘 다 동등 → 양방향 훅 |
| 개입 강도 | 자동 반영(apply) 우선, 모호하면 알림만 |
| 접근법 | A안(양방향 훅 + 전역 wiring + status alias) |
| Hermes 범위 포함 여부 | 제외 — 코딩 에이전트가 아님 |
| installer wiring 포함 여부 | 포함 |
