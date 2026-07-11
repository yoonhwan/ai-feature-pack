# fable-team 설치 가이드

## 1. 스킬 파일 배치

```bash
cd feature-pack/fable-team
./install.sh user                   # 또는 project:/abs/path
```

install.sh는 ① claude CLI 필수 체크 ② codex/cursor-agent/gemini 가용성 프로브(참고용) ③ `SKILL.md` + `references/`를 대상 위치에 복사까지만 한다. **에이전트 .md 생성은 대화형 인터뷰**에서 진행된다.

## 2. 설치 인터뷰 (Claude Code 안)

새 세션(ultracode 권장)에서:

```
fable-team 설치 인터뷰 진행해줘
```

인터뷰 순서 (`skill/references/install-interview.md`):
1. **§0 브레인 가용성 체크** — codex 인증까지 실측. 미가용이면 `brain-availability.md` 추천표의 대안이 기본 선택지로 제시됨 (예: DA → claude-opus-4-6 high + `ft-da-claude.md.tpl`)
2. 팀명/접두사/설치 위치 (사용자 레벨 vs 프로젝트)
3. 워커별 브레인·effort (기본값: architect=fable5/max, checker=sonnet4.6/low, implementer=opus4.6/max, tester=sonnet5/high, DA=codex gpt-5.5/xhigh)
4. 프로젝트 커스텀 (`{{EXTRA_INSTRUCTIONS}}` — 프로젝트 스킬 호출 규칙 등)
5. 템플릿 치환 → 에이전트 .md Write → 설치 기록(`install.json`)

## 3. 검증

**새 세션에서** (에이전트 등록은 세션 시작 시 스냅샷):

```
fable-team 프로브 돌려줘
```

각 워커에 도구 목록 + spawn_test 질의 → 기대값: Agent/Task 없음, `NO_SPAWN_TOOL`, meta.json 모델 일치. 상세: `skill/references/orchestration-playbook.md` §프로브

## 함정 (반드시 읽기)

- ultracode(xhigh) 세션에서 claude-5 계열 워커는 Agent 경로로 스폰하면 400 에러 — **Workflow 경로 필수** (SKILL.md 스폰 경로 분리 규칙)
- 에이전트 .md 수정 후 같은 세션에서 재스폰 금지 — 구정의 스냅샷으로 뜬다
- codex 호출은 `< /dev/null` 필수 (stdin hang)
