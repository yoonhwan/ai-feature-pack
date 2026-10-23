---
name: code-intel
description: Code intelligence for any harness (claude, codex, opencode, pi, hermes) — replaces Serena. Use when you need to search a codebase by meaning or keyword, find a symbol's definition, list callers/references, check what a file depends on, see an outline before reading, judge refactor impact, or run structural (AST) patterns. Triggers - "serena", 코드 검색, 심볼 찾아, 참조/호출자 추적, 리팩터 영향도, 어디 정의됐어, 이 파일 구조, ast-grep, code search, find references.
---

# code-intel

코드베이스 탐색을 **인덱스 없이, 상주 프로세스 없이** 수행한다. Serena MCP를 대체한다.
정본: `~/.claude/skills/code-intel/` → `~/.agents/skills/`, `~/.codex/skills/`, `~/.config/opencode/skills/` 에 심링크.

## 0. 30초 규칙

```bash
ci doctor                              # 설치·버전·LSP·smoke (의심되면 항상 이걸 먼저)
ci search "realtime dispatch" .        # 뭐가 어디 있나 (의미/키워드)
ci sym dispatch --callers --scope .    # 누가 호출하나 (가장 빠름, 0.4s)
ci outline path/to/file.py             # 읽기 전 구조 + 토큰 수
```

`ci` 가 없으면 절대경로 폴백 → `~/.agents/skills/code-intel/scripts/ci`
(정본 `~/.claude/skills/code-intel/scripts/ci` 를 가리킨다. 어느 하네스에서든 동일 동작.)

도구가 없으면 **멈추지 않는다** — `rg` + `Read`로 계속 진행하고 1줄만 보고한다. (Serena의 "미활성이면 STOP" 규칙은 폐기됨)

## 1. 의사결정 트리

```
질문이 무엇인가?
├─ "개념/기능이 어디 구현됐나"      → ci search "<query>" <path>
│   └─ 결과 파일이 3개 이상 흩어짐 → 후보 파일마다 ci outline <file> → 필요한 구간만 Read
├─ "이 심볼 정의/호출자/의존성"      → ci sym <name> [--callers|--deps] --scope .
│   └─ 크로스파일 정확한 참조 위치    → ci refs "<file>#<sym>"      (LSP, 온디맨드)
├─ "이 파일 뭐가 들었나 (토큰 절약)" → ci outline <file> [--section "## Import"]
├─ "변수명 무관 구조 패턴"          → ci ast 'def $N($$$A): $$$B' <path> -l py
└─ "그냥 문자열/정규식"             → rg  (가장 빠름, 랭킹 없음)
```

도구 선택 요약:

| 도구 | 강점 | 비용(실측, 62k파일/49GB 워크트리) |
|---|---|---|
| `ci search` (probe) | BM25 랭킹 + AST 완결 블록, 정의/맥락 포함 | 단일어 4.6s / 다중어 11.3s, 149~490MB (1회성) |
| `ci sym` (tilth) | 정의 우선 정렬, 정의/언급 구분, 호출 체인 footer | 심볼검색 6.5s / **`--callers` 0.36s** / outline 0.00s |
| `ci refs` (probe LSP) | 크로스파일 정밀 참조, 오탐 0 | 0.75s (데몬 초기화 선행 0.3s) |
| `ci ast` (probe=ast-grep) | 구조 매칭, 변수명 무관 | 0.03s~ |
| `rg` | 최단, 랭킹 없음 | 6.0s/52MB (같은 트리) |

## 2. 필수 규칙 (MANDATORY)

1. **파일 수정 전 `[REALITY]` 확인**: 최소 1회 `ci sym <target> --callers` 또는 `ci refs` 로 영향 범위를 본다. (Serena 시절 "Serena MANDATORY" 자리)
2. **읽기 전에 아웃라인**: 3k 토큰 초과 파일은 `ci outline` → `--section` 으로 쪼개 읽는다. `Read` 풀스캔은 마지막 수단.
3. **토큰 예산**: `ci search` 는 기본 `--max 5`. 늘리기 전에 쿼리를 불리언으로 좁힌다(`A OR B`, `ext:py`, `-file:tests`).
4. **상주 금지**: `ci lsp up` 뒤 반드시 `ci lsp down`. 데몬 유휴 비용 112MB.
5. **편집은 네이티브**: `Edit`/`Write`. 심볼 단위 자동 편집 도구는 쓰지 않는다(실사용 0회 실측).

## 3. 알려진 함정 (반드시 숙지)

- **한국어 마크다운 panic**: `probe search` 가 `markdown.rs:240` char-boundary 로 SIGABRT(134) 하는 버그가 있다(RC 버전). `ci search` 는 자동으로 `-i '*.md'` 재시도한다. 직접 probe를 부를 땐 `-i '*.md'` 를 붙인다.
- **Python LSP = pylsp**: probe는 pyright를 쓰지 않는다. `uv tool install python-lsp-server`. `call-hierarchy` 미지원 → 호출자는 `ci sym --callers`(AST) 사용.
- **다중어 쿼리는 비싸다**: 11s/490MB. 단일 심볼명이나 불리언으로 쪼갠다.
- **⚠️ tilth 직접 호출 = 코어 폭주 (2026-10-23 실사고)**: tilth 는 파일 워크를 **병렬(rayon)** 로 돌린다. 리포 루트급 scope 로 심볼검색을 걸면 **한 프로세스가 550~580% CPU**, 2건이면 약 11~12코어, load average **139**까지 치솟았다(4분 28초 지속, codex 세션이 날것 tilth 호출).
  - 반드시 `ci` 경유: `ci sym`/`ci outline`/`ci ast` 에 **`CI_TIMEOUT`(기본 60s) + 리포루트 scope 경고** 가드가 내장돼 있다.
  - scope 는 하위 디렉터리로: `ci sym dispatch --callers --scope shared/services` ✅ / `--scope .`(리포 루트) ❌
  - 전체 스캔이 정말 필요할 때만 `CI_ALLOW_HEAVY=1 CI_TIMEOUT=600`.
- **probe LSP 데몬은 진단 후 자동 종료**: `ci doctor` 는 status 호출로 데몬이 기동되면 즉시 `shutdown` 한다(유휴 112MB 남기지 않음).
- **AST 패턴은 본문 포함형으로**: `def $N($$$A):` 보다 `def $N($$$A): $$$B` 가 안전.

## 4. 참조 문서

| 파일 | 내용 |
|---|---|
| `references/probe.md` | 쿼리 문법, 랭커, 플래그, 토큰 예산, RC 주의 |
| `references/tilth.md` | 심볼/호출자/deps/섹션, 토큰 헤더 |
| `references/lsp.md` | 데몬 수명주기, 언어별 서버 요구표 |
| `references/harness.md` | claude/codex/opencode/pi/hermes 호출법·설치 경로 |
| `references/migration.md` | Serena 도구 1:1 치환표 (은퇴 근거·실측) |

## 5. 설치 — 제네릭 (4개 하네스 한 번에)

```bash
~/.claude/skills/code-intel/scripts/install.sh          # 바이너리 + 심링크 + ci 링크 + doctor
~/.claude/skills/code-intel/scripts/install.sh --check  # 변경 없이 진단
```

`install.sh` 가 하는 일(멱등):
1. `probe`(0.6.0-rc342) · `tilth`(0.12.0) 있으면 그대로, 없으면 설치 → `~/.local/bin`
2. 스킬 정본을 **claude / pi·hermes(`~/.agents`) / codex / opencode(`~/.config/opencode`)** 스킬 루트에 심링크
3. `~/.local/bin/ci` 단일 진입점 생성 (PATH에 이미 걸려 있음)
4. `ci doctor` 로 최종 진단

수동 설치(오프라인/특수환경)는 `references/harness.md` 참조. Python LSP는 선택: `uv tool install python-lsp-server`.

## 6. 준수율 측정 (`ci-audit`)

하드룰 16("코드 탐색은 `ci` 우선, grep은 문자열 한정")이 실제로 지켜지는지 계측한다.

```bash
~/.claude/skills/code-intel/scripts/ci-audit                  # 최근 24h 요약
ci-audit --days 0.25 --by-harness                             # 하네스별
ci-audit --days 1 --csv ~/.claude/skills/code-intel/references/ci-audit.csv   # 일별 추이 누적
```

출력: **준수율 = ci / (ci + 소스확장자grep)** · ci 서브커맨드 분포 · 위반 후보 샘플
- `grep_src` = 인자에 `.py/.ts/.go/...` 가 걸린 rg/grep/git grep/find → **위반 후보**
- `grep_other` = 로그·설정·문자열 grep → 정당(카운트에서 제외)
- `serena` = 은퇴 후 0이어야 함 (파일 mtime 기준이라 짧은 창으로 재확인)

목표선(권장): 준수율 **주 30% → 월 60%**. 낮을 때 조치 = 좌석 증류 시 5줄 재주입 + 하드룰 리마인드.
