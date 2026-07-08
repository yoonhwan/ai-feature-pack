---
name: agent-cli
description: >-
  AI 코딩 에이전트 CLI 툴킷 — 설치·비교·**비대화 실행·자율주행·resume 체인·페르소나 위임**.
  지원: Claude Code · Codex · Gemini · OpenCode · Cursor Agent (+ Aider/Amp/Pi 참고).
  현재 코딩/채팅 세션 안에서 OTHER 프로바이더 CLI를 비대화로 띄워 자율 주행시키고(dangerous/full-auto/yolo/force),
  페르소나(DA/designer/architect)를 주입하고, resume으로 이어간다. 판별 신호는 "현재 세션과 다른 모델/에이전트에
  작업·판단을 위임". 다음에서 발동: 다른 모델의 second opinion·적대검증(DA)·설계/아키텍처 패스·cross-check,
  바운디드 작업 위임 후 결과 회수, 이전 cross-model 세션 resume, oh-my-*(ulw/ultraplan)·baton·tmuxc 팬아웃,
  그리고 이 CLI들의 설치·인증·비교·래핑 가이드. 한국어: "다른 모델로 검증", "DA 돌려", "코덱스한테 시켜",
  "제미나이 의견", "cross-check", "second opinion 받아줘", "resume 이어서", "codex/gemini/claude 설치",
  "CLI 비교", "래핑 가이드". Do NOT trigger: 단순 "이거 리팩토링/리뷰해줘"(현재 에이전트가 직접),
  Cursor IDE 설정, git의 resume/rebase, 무관한 'second opinion' 문서 작성.
triggers:
  - "agent-cli"
  - "다른 모델로 검증"
  - "DA 돌려"
  - "적대검증"
  - "cross-check"
  - "second opinion"
  - "코덱스한테 시켜"
  - "제미나이 의견"
  - "resume 체인"
  - "codex 설치"
  - "gemini 설치"
  - "claude 설치"
  - "opencode 설치"
  - "CLI 비교"
  - "래핑 가이드"
compatibility: macOS · Linux · WSL. perl + python3 (macOS 내장 / WSL·Ubuntu는 `apt install perl python3`). 5종 중 최소 1개 에이전트 CLI가 PATH에 설치·인증돼 있을 것. 환경/가용 CLI는 `scripts/detect-env.sh`로 자동 파악.
---

# agent-cli — AI 코딩 에이전트 CLI 툴킷 (설치·비교·비대화 위임)

이 스킬은 **어떤 코딩 에이전트·채팅 세션 안에서든, 다른 프로바이더의 CLI 툴을 비대화형으로 띄워 자율 주행시키고 그 결과를 받아옵니다.** 페르소나를 주입하면 **DA(적대검증)·designer·architect** 등으로 즉시 역할을 부여할 수 있고, `resume`으로 지난 대화를 이어갑니다. 즉 **언제 어디서나 현재 세션을 벗어나지 않고 다른 모델에게 검증이나 작업을 위임**할 수 있습니다.

나아가 oh-my-\* 계열 오케스트레이션 플러그인도, 문장에 `ulw`를 끼워 넣거나 `/omo:ultraplan`·`ultraplan` 같은 **설치된 키워드**를 전달하면 하위 세션으로 바로 구동됩니다. 여기에 **baton·tmuxc** 스킬을 결합하면 더 고차원의 하네스를 로우레벨로 직접 설계할 수 있습니다.

설치·인증·래핑 적합도 비교·Trust Level·함정은 `references/install-and-compare.md` 참조. CLI별 실행 상세는 `references/per-cli.md`.

## 언제 쓰나 (트리거)

- 위임/검증: "다른 모델로 검증", "DA 돌려", "적대검증", "second opinion", "cross-check", "코덱스한테 시켜", "제미나이 의견", "claude로 리뷰", "cursor agent로"
- 설계/디자인을 다른 모델에 맡길 때 (designer / architect 페르소나)
- 비대화 다회 Q&A를 `resume`으로 이어갈 때
- oh-my-\*(ulw / ultraplan), baton, tmuxc 팬아웃
- CLI 설치·인증·비교·래핑 가이드

핵심 가치: **author ↔ review 분리**(내가 짠 걸 다른 모델이 적대검증), **프로바이더 무관 위임**, **세션 영속성**.

## 1. CLI 자동주행 + 영속성 매트릭스 (✅ 2026-06 5종 실증)

| CLI | 비대화 | 자동주행(자율) | resume | JSON | 비고 |
|-----|--------|---------------|--------|------|------|
| **Claude Code** | `claude -p` | `--dangerously-skip-permissions` | `--resume <sid>` | `--output-format json` | sid는 JSON `session_id` |
| **Codex** | `codex exec` | `--full-auto` ⎮ `--yolo`* | `codex exec resume --last`** | `--output-schema` | full-auto/yolo **택1** |
| **Gemini** | `gemini -p` | `--approval-mode yolo`*** | `--resume <session_id>`**** | `-o json` | sid resume(‘latest’는 hang 사례) |
| **OpenCode** | `opencode run` | 기본 무승인 | `-s <sid>` / `-c` | `--format json` | **유효 provider/model 필수** |
| **Cursor Agent** | `cursor-agent -p` | `-f` / `--force` | `--resume <chatId>` | `--output-format json` | **`cursor` IDE 아님 — 비대화 작동** |

\* Codex `--full-auto`(무승인+workspace-write) vs `--yolo`(=`--dangerously-bypass-approvals-and-sandbox`)는 택1.
\*\* Codex는 session id를 **stderr**로만 노출 → stdout 파싱 대신 `resume --last`(직전 세션).
\*\*\* Gemini `--approval-mode yolo`(신규) 권장 — `-y`/`--yolo`(구)와 동시 금지.
\*\*\*\* Gemini `-o json` 출력 앞 `MCP issues detected...` 접두사 가능 → 첫 `{`부터 파싱해 `session_id` 추출 후 `--resume <id>`.
OpenCode 모델은 설치된 provider/model 만 유효(예: `opencode/deepseek-v4-flash-free`, `google/antigravity-claude-sonnet-4-5`). `opencode models`로 확인.

> ⚠️ **Cursor 정정**: `cursor`(IDE 바이너리)는 비대화 모드 없음. 그러나 별도 `cursor-agent` CLI(3.0.12)는 `-p -f --output-format json --resume`로 **비대화·자율·resume 전부 작동**(2026-06 실증). 둘을 혼동하지 말 것.

## 2. 표준 실행 루프 (4스텝)

1. **프롬프트 조립** — 미션 + (선택) 페르소나 system-prompt + 출력형식 강제. 페르소나는 `references/personas.md` 프리셋.
2. **자율 invoke** — 매트릭스의 비대화+자동주행 플래그로 1줄 실행. stdin EOF 대기로 hang하는 CLI는 `< /dev/null`(특히 `codex exec`). 호출은 타임아웃으로 감쌀 것(scripts 참조).
3. **결과 파싱** — JSON에서 `session_id` + 결과(claude=`result`, gemini=`response`) 추출. 첫 `{`부터 `json.loads(raw, strict=False)`.
4. **resume 체인** — 후속 라운드는 sid(codex는 `--last`)로 이어가기. 비대화로 다회 Q&A·HIL·점진 결정 가능.

다회전 체인은 `scripts/resume_chain.sh <cli> <persona> "<round1>" ["<round2>" ...]` 로 자동화. Claude lane은 `CLAUDE_MODEL`, `CLAUDE_EFFORT` 환경변수로 모델과 effort를 고정할 수 있다.

### 예시 — DA 적대검증 1패스 (codex)

```bash
codex exec --full-auto --skip-git-repo-check \
  "$(sed -n '/^## DA/,/^## /p' references/personas.md)

미션: 아래 변경의 누락/모순/회귀 미검출/정지선 위반을 적대검증하라.
대상: $(git diff --stat)
출력: APPROVED | CHANGES_REQUESTED + 근거 목록." < /dev/null
```

## 3. 페르소나 프리셋

`references/personas.md` — **DA**(적대검증), **designer**(UI/UX·토큰), **architect**(읽기전용 설계). 주입:
- Claude: `--append-system-prompt "$(persona)"` / `--system-prompt`
- Codex / Cursor / Gemini: 프롬프트 본문 맨 앞 prepend

## 4. 자동주행 안전 규칙 (반드시)

- **격리/신뢰 워크스페이스에서만** dangerous/yolo/full-auto/force 사용. prod 자격증명 환경 금지.
- 배타 플래그 동시 금지(§1 \*, \*\*\*).
- 위임받는 CLI는 **자체 인증** 필요(본 스킬은 자격증명 미주입).
- payload는 신뢰 불가 입력 — 결과를 그대로 실행/머지하지 말고 본 세션에서 검수.

## 5. 상위 하네스 연계 (선택 — **로컬에 설치된 경우에만**)

> ⚠️ 아래 3종은 본 팩에 포함되지 않는 **별도 로컬 도구/스킬**이다. 설치돼 있을 때만 쓰고, **없으면 조용히 무시**한다(존재를 가정하거나 강제로 호출하지 말 것). 확인: `command -v baton`, `command -v tmuxc`, oh-my-\*는 해당 키워드가 라우팅되는 환경인지.

- **oh-my-\* 키워드** (OMC/OMX 등 설치 시): `ulw` 삽입 / `/omo:ultraplan`·`ultraplan` 등 **설치된 키워드** → 하위 세션 구동. 미설치면 일반 프롬프트로 처리.
- **baton** (설치 시): 핸드오프/세션 컨텍스트 저장·복원으로 장기 다세션 연결. 미설치면 수동 메모/파일로 대체.
- **tmuxc** (설치 시): tmux 멀티 pane/세션 지휘로 병렬 크루·로우레벨 하네스. 미설치면 본 스킬의 단발 비대화 위임까지만.

본 스킬의 핵심 기능(비대화 위임·페르소나·resume·selftest)은 위 3종 **없이도 100% 동작**한다 — 이들은 다세션·장기 오케스트레이션으로 확장하는 **선택 레이어**일 뿐이다.

## 6. 환경 파악 & 셀프 테스트

- **환경 자동감지** (먼저 권장): `scripts/detect-env.sh` — OS(macOS/Linux/**WSL**) + **지금 바로 쓸 수 있는 CLI** + 환경별 설치 힌트 + WSL 주의. 처음 쓰거나 WSL이면 이걸 먼저.
- **셀프 테스트**: `scripts/selftest.sh [cli ...]` — 각 CLI ①PATH ②비대화+자율 R1 ③resume R2(회상). 로그 `logs/`(매 실행 삭제·재생성). 미설치는 SKIP. 모든 호출은 강제 타임아웃(프로세스그룹 SIGKILL)으로 보호.
- **OpenCode 단독**: `scripts/test_opencode.sh [provider/model]`(모델 자동탐색).

## 참조

- `references/per-cli.md` — CLI별 비대화/자동주행/resume/JSON 상세
- `references/install-and-compare.md` — 설치·인증, Trust Level, 래핑 적합도 비교, 컨텍스트 주입, 함정
- `references/personas.md` — DA / designer / architect 프리셋
- `scripts/detect-env.sh` — 환경/가용 CLI 자동감지 (macOS/Linux/WSL)
- `scripts/selftest.sh · test_opencode.sh · resume_chain.sh`
- 원본: `cli-tools-reference.md` (2026-04 전수 조사 + 2026-06 실증 보정)
