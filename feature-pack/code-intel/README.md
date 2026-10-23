# code-intel

하네스 공통 코드 인텔리전스 — **`ci` 단일 진입점** (probe + tilth). Serena MCP 대체.

| 항목 | 값 |
|---|---|
| 진입점 | `ci` (`~/.local/bin/ci`), `ci-audit` |
| 지원 하네스 | Claude Code · Codex · OpenCode · pi · Hermes (동일 명령) |
| 상주 프로세스 | **0** (CLI 원샷) |
| 인덱스 | 없음 (필요 시에만 `ci lsp up`) |

## 30초
```bash
ci doctor                                  # 설치·버전·LSP·smoke
ci search "dispatch" <path> --max 5        # 의미/키워드 (BM25 + AST 블록)
ci sym dispatch --callers --scope <dir>    # 정의/호출자 (0.36s)
ci outline <file>                          # 읽기 전 구조 + 토큰
ci refs "<file>#<sym>"                     # LSP 정밀 참조 (온디맨드)
ci ast 'def $N($$$A): $$$B' <path> -l py   # ast-grep 구조 패턴
ci-audit --days 1 --by-harness             # 지침 준수율
```

## 왜 만들었나 (실측, 62k파일/49GB 워크트리)
| 작업 | Serena | code-intel |
|---|---|---|
| 의미검색 | 127.25s (빈 결과) | **4.6s** (랭킹 결과) |
| 호출자 추적 | 4.2s+ (활성화 선행) | **0.36s** |
| 상주 메모리 | 946MB → 5.1GB 누수(peak 21GB) | **0MB** |
| 사전 절차 | activate_project + config 확인 필수 | **없음** |

## 설치
`INSTALL.md` 참조 (에이전트 자율 설치 프롬프트 + 검증 + 지침 연결 + 함정·롤백).

```bash
ln -sfn ~/Project/ai-feature-pack/feature-pack/code-intel/skill ~/.claude/skills/code-intel
~/.claude/skills/code-intel/scripts/install.sh --check
```

## 안전장치
- **타임아웃 60s + 리포루트 scope 경고** (`CI_TIMEOUT`, `CI_ALLOW_HEAVY=1` 예외)
- 한국어 마크다운 panic 자동 우회(`-i '*.md'`), 다중어 0건 시 `A OR B` 재시도
- Python 구조패턴 ast-grep 폴백
- `probe`/`tilth` **직접 호출 금지** — 반드시 `ci` 경유 (2026-10-23 폭주 사고 대응)
