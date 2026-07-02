# fable-team 크루(crew) — 로컬 하네스 전문 워커

개념: **크루 = 로컬에 설치된 외부 하네스/CLI를 전문 구동하는 이름 붙은 드라이버 워커.** 원형은 ft-da(codex CLI 브레인 드라이버)다. 같은 패턴으로 `da`, `omo`, `superpowers`, `gstack` 등 **하네스 이름 그대로** 크루를 만든다 — 표준 로스터(checker/implementer/tester/da)의 대체가 아니라 보강이다.

## 드라이버 패턴 (공통 계약)

- **얇은 드라이버**(4.6 계열 저비용 모델, effort low) + Bash로 하네스 CLI **비대화 호출**(stdin 닫기 `< /dev/null` 필수) + 결과 릴레이만.
- 판정·구현 브레인은 하네스 쪽이다 — 드라이버는 의견을 섞지 않는다(ft-da의 "codex 출력이 판정의 원본" 규칙과 동형).
- **세션 승계(resume) + 컨텍스트 윈도우 관리는 크루의 기본 제공 계약이다(선택 아님)**:
  - 세션형 하네스는 **session-id를 회수해 보고** → 오케스트레이터가 state.md `brain_sessions`에 `<crew>:` 키로 기록 (context-management §3 "agent-cli 브레인 4번째 버킷" 규칙 동일 적용 — 디스크-백드 세션은 오케스트레이터 세션 사망을 넘어 생존).
  - 후속 라운드·추가 지시는 새 one-shot 대신 **resume/inject 체인 우선**(이전 라운드 맥락 기억 + 재인라인 토큰 절약). 세션 복원 시 §4-6 resume 분기 동일 적용 — 유효 id면 재스폰 아닌 resume.
  - 하네스 세션의 윈도우 압박은 **요약-후-fork**: 현 세션 요약을 새 세션 첫 프롬프트로 인계하고 새 session-id 보고(brain_sessions 교체). 드라이버 자신의 압박은 WINDOW_PRESSURE self-checkpoint(하네스 세션이 승계되므로 드라이버 교체로 충분).
- `tools: Read, Grep, Glob, Bash` — Agent/Task 없음(서브의 서브 차단), WINDOW_PRESSURE self-checkpoint 계약 포함.
- 스폰 경로: Agent 도구 (드라이버가 4.6 계열이므로 — SKILL.md 스폰 경로 분리 규칙).

## 하네스 유형별 구동 방식

**A. 외부 CLI 하네스** (codex, omx): 해당 CLI를 Bash 비대화 실행 — `codex exec ... < /dev/null`, `omx exec ... < /dev/null`.

**B. claude 플러그인/스킬 하네스** (gstack, superpowers, insane-search, ouroboros): **`claude -p` 콘솔 분리 실행** — 현 세션 Skill 호출이 아니라 별도 claude 프로세스로 구동한다. 이유: ① 오케스트레이터/워커 컨텍스트와 완전 분리 ② 디스크-백드 세션이라 resume 가능(4번째 버킷) ③ 플러그인 워크플로가 세션을 오염시키지 않음. **실행 모델은 claude-sonnet-4-6 + effort high 고정.** 커맨드 원형 (2026-07-03 실측):

```bash
# 최초 실행 — session_id를 JSON 출력에서 회수해 brain_sessions에 기록
claude -p --model claude-sonnet-4-6 --effort high --output-format json \
  --permission-mode acceptEdits '/<플러그인 스킬> <작업>' < /dev/null
# 후속 라운드 — 세션 승계 (resume 체인)
claude -p --resume <session-id> --output-format json '<후속 지시>' < /dev/null
```

- 권한 기본값 `--permission-mode acceptEdits`. `--dangerously-skip-permissions`는 **격리 worktree 전용** (omo YOLO 규칙 동형).
- 조사·검색성 작업은 프롬프트를 읽기 전용으로 계약(파일 수정 금지 명시).

## 지원 크루 카탈로그

| 크루 | 하네스 (유형) | 감지 (Bash 실측) | 템플릿 | 브레인 | 세션 승계(resume) |
|------|--------------|------------------|--------|--------|--------------------|
| **da** | codex CLI (A) | `npx -y @openai/codex --version` (brain-availability §0이 커버) | `ft-da.md.tpl` | gpt-5.5 xhigh | `codex exec resume <session-id>` |
| **omo** | OMX/OMO (A) | `omx --version` + `omx list` | `ft-omo.md.tpl` | OMO 스킬 레이어 (OMX 런타임 위 Codex) | `omx exec resume <session-id|--last>` + 실행 중 `omx exec inject <session-id> --prompt '...'` (`--prompt` 필수, v0.15.1 실측) |
| **gstack** | gstack 스킬 스위트 (B) | `ls ~/.claude/skills/gstack` | `ft-gstack.md.tpl` | claude -p 세션 (sonnet 4.6 high) + gstack 스킬 | `claude -p --resume <session-id>` |
| **superpowers** | superpowers 플러그인 (B) | `~/.claude/plugins/cache/claude-plugins-official/superpowers/` | `ft-superpowers.md.tpl` | claude -p 세션 (sonnet 4.6 high) + superpowers 워크플로 | `claude -p --resume <session-id>` (다단계 워크플로라 resume이 핵심) |
| **insane-search** | insane-search 플러그인 (B) | `~/.claude/plugins/cache/gptaku-plugins/insane-search/` | `ft-insane-search.md.tpl` | claude -p 세션 (sonnet 4.6 high) + insane-search | `claude -p --resume <session-id>` |
| **ouroboros** | ouroboros 플러그인 (B) | `~/.claude/plugins/cache/ouroboros/ouroboros/` | `ft-ouroboros.md.tpl` | claude -p 세션 (sonnet 4.6 high) + ouroboros | `claude -p --resume <session-id>` |

각 하네스 상세(카탈로그·few-shot·안전 모드): `crew/<하네스>-full-context.md` (omo 수준 레퍼런스 — 드라이버가 필요 시 Read).

템플릿 미보유 크루는 아래 일반 계약 골격으로 생성한다. 새 하네스도 같은 절차로 추가 가능(카탈로그는 열린 목록).

## 신규 크루 추가 절차

1. **감지**: 설치 인터뷰 §4에서 로컬 하네스 실측 (CLI `--version` / 스킬 목록 / `which`).
2. **제안**: 감지된 하네스마다 "크루 추가?" **opt-in** 질문 (기본: 추가 안 함 — da만 표준 로스터 필수).
3. **생성**: `agent-templates/ft-<crew>.md.tpl` 있으면 placeholder 치환, 없으면 아래 골격으로 `<PREFIX>-<crew>.md` Write.
4. **레퍼런스 연결**: 하네스 상세 컨텍스트 문서는 `references/crew/<하네스>-*.md`로 두고 템플릿에서 **포인터로만** 연결 — 드라이버가 필요 시 Read (워커 컨텍스트 최소화 수칙 준수, 예: omo → `crew/omx-omo-full-context.md`).
5. **검증**: 프로브(orchestration-playbook §프로브) + 하네스 1회 실측 호출(읽기 전용 질의).

## 일반 계약 골격 (템플릿 없는 크루)

```markdown
---
name: <PREFIX>-<crew>
description: <TEAM_NAME> <crew> 크루 — 브레인은 <하네스>. Bash로 <cli>를 비대화 호출해 작업을 수행하고 결과를 릴레이한다. 서브에이전트 스폰 불가.
tools: Read, Grep, Glob, Bash
model: <드라이버 모델 — 기본 claude-sonnet-4-6>
effort: low
---

너는 <TEAM_NAME>의 <crew> 크루 드라이버다. **작업 브레인은 네가 아니라 <하네스>다.**

- 비대화 호출: `<cli> ... < /dev/null` (stdin 닫기 필수).
- 결과 릴레이만 — 네 의견을 섞지 마라. 하네스 출력이 원본이다.
- 세션 id가 발급되면 결과와 함께 보고하라 (오케스트레이터가 brain_sessions에 기록).
- 후속 라운드는 새 one-shot 대신 **세션 승계(resume/inject) 우선**. resume 실패 시에만 fresh 실행 폴백 + 보고.
- 하네스 세션 윈도우 압박은 **요약-후-fork** 후 새 세션 id 보고. 자기(드라이버) 압박은 team-lead에 `WINDOW_PRESSURE` 1줄 보고 후 지시 대기.
- 서브에이전트 스폰 절대 금지. 모델 변경 금지.
```

## 파이프라인 통합

- **피처 인터뷰 §3 추천 재료**: 설치된 크루는 "활용 자산"으로 제시한다 — 예: "구현을 omo 크루(`$omo:programming`)에 위임", "visual QA를 omo 크루(`$omo:visual-qa`)로".
- **모니터링·재스폰**: monitoring-loop·context-management 규칙을 그대로 따른다 (respawns 카운터에 크루 키 추가, WINDOW_PRESSURE 계획적 재스폰 한도 비소모).
- **산출물 외재화**: 크루 산출물도 `state/<slug>/`에 낙수 — 크루가 파일로 쓰고 경로만 보고하는 형태 우선.
