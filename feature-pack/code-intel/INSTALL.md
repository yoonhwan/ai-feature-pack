# Feature Pack: code-intel
> 에이전트 자율 설치 프롬프트 — 하네스 공통 코드 인텔리전스 (`ci`), Serena 대체

## 개요

`ci` 단일 진입점으로 **인덱스 없이, 상주 프로세스 0** 으로 코드 탐색을 제공한다.

**할 수 있는 것:**
- 의미/키워드 검색 (BM25 + AST 완결 블록) — `ci search "<q>" <path>`
- 심볼 정의·호출자·의존성 (정의 우선 정렬) — `ci sym <sym> --callers --scope <dir>`
- 읽기 전 아웃라인 + 토큰 수 — `ci outline <file>`
- LSP 정밀 참조/정의/구현 (온디맨드) — `ci refs "<file>#<sym>"`
- 구조 패턴 (ast-grep) — `ci ast '<pattern>' <path> -l py`
- 준수율 계측 — `ci-audit --days 1 --by-harness`

**대체하는 것:** Serena MCP (`mcp__serena__*`) — 상주 946MB → 누수 5.1GB(peak 21GB), 검색 127s. `ci`는 같은 워크트리에서 4.6s/상주 0.

## Prerequisites

| 항목 | 요구 | 확인 |
|---|---|---|
| OS | macOS(arm64/x86_64) · Linux | `uname -sm` |
| 기본 도구 | `curl`, `tar`, `python3` | `command -v` |
| 선택 | `ast-grep` (python 등 구조패턴 폴백) | `brew install ast-grep` |
| 선택 | `python-lsp-server` (ci refs python) | `uv tool install python-lsp-server` |

## 설치 (에이전트가 실행)

```bash
# 1) 이 모듈의 skill 을 각 하네스 스킬 루트에 연결
REPO=~/Project/ai-feature-pack/feature-pack/code-intel
ln -sfn "$REPO" ~/.claude/skills/code-intel
ln -sfn "$REPO" ~/.agents/skills/code-intel
ln -sfn "$REPO" ~/.codex/skills/code-intel
ln -sfn "$REPO" ~/.config/opencode/skills/code-intel

# 2) 바이너리 + 진입점 + 진단 (멱등)
"$REPO/skill/scripts/install.sh"          # 또는 --check 로 진단만
```

`install.sh` 가 하는 일:
1. `probe`(0.6.0-rc342) · `tilth`(0.12.0) 있으면 그대로, 없으면 설치 → `~/.local/bin`
2. 스킬 정본을 **claude / pi·hermes / codex / opencode** 스킬 루트에 심링크
3. `~/.local/bin/ci` · `ci-audit` 진입점 생성
4. `ci doctor` 최종 진단

## 검증 (설치 후 반드시)

```bash
ci doctor                                   # probe/tilth 버전 + LSP + smoke
ci sym <아무심볼> --scope <하위디렉토리>      # 0.4s 내 응답
ci outline <파일>                            # 헤더에 토큰 수
ci-audit --days 0.1 --by-harness             # (지침 랜딩 후) 준수율 계측
```

합격 기준: `ci doctor` 4줄 출력 + `ci sym` 응답 + `ci outline` 토큰 표시.

## 지침 연결 (필수 — 안 하면 에이전트가 안 씀)

각 하네스 지침에 아래를 추가한다(전역):

```markdown
**HARD RULE: 코드 심볼·참조·구조 탐색은 `ci` 우선. grep/rg/git grep 은 로그·설정·문자열·파일존재 확인에만.
`probe`/`tilth` 직접 호출 금지 — 반드시 `ci` 경유(타임아웃·scope 가드 내장). 사전 활성화 없음.**
```
- Claude Code: `~/.claude/CLAUDE.md` (하드 룰 인덱스)
- Codex: `~/.codex/AGENTS.md`
- OpenCode: `~/.config/opencode/AGENTS.md`
- pi: `~/.pi/agent/AGENTS.md`
- 프로젝트: `<repo>/CLAUDE.md` 의 `## 🔍 Code Intelligence` 섹션

## ⚠️ 함정

| 함정 | 대응 |
|---|---|
| **tilth 직접 호출 = 코어 폭주** (리포 루트 scope에서 585% CPU, load 139 실사고) | `ci` 경유 필수. scope 는 하위 디렉토리. 전체 스캔은 `CI_ALLOW_HEAVY=1 CI_TIMEOUT=600` |
| 한국어 마크다운에서 probe panic (SIGABRT) | `ci search` 가 자동 `-i '*.md'` 재시도 (직접 호출 시 `-i '*.md'` 필수) |
| 다중어 쿼리는 AND 해석 → 0건 | `ci search` 가 자동 `A OR B` 재시도. 직접 호출 시 불리언 명시 |
| Python 구조패턴 0건 (probe 버그) | `ci ast` 가 ast-grep 폴백 (설치 필요) |
| Python LSP = pylsp (pyright 아님) | `uv tool install python-lsp-server`, `call-hierarchy` 미지원 → 호출자는 `ci sym --callers` |

## 롤백

```bash
rm ~/.claude/skills/code-intel ~/.agents/skills/code-intel \
   ~/.codex/skills/code-intel ~/.config/opencode/skills/code-intel \
   ~/.local/bin/ci ~/.local/bin/ci-audit
# 바이너리 유지 가능 — probe/tilth 는 단독 CLI로도 쓸 수 있다
```
