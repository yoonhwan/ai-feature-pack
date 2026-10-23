# probe (probelabs/probe) — 0.6.0-rc342

Rust 단일 바이너리(57.7MB). 인덱스 없이 AST 파싱 + BM25 랭킹. 상주 프로세스 없음.
`~/.local/bin/probe`. RC 버전 → **버전 고정**.

## 서브커맨드
| 명령 | 용도 |
|---|---|
| `probe search "<q>" <path> --max-results N` | 의미/키워드 검색, AST 완결 블록 반환 |
| `probe symbols <path>` | 파일별 정의 목록 (경량) |
| `probe extract <path>` | 완결된 코드 블록 추출 |
| `probe query '<pat>' <path> -l <lang>` | **ast-grep 내장** 구조 패턴 |
| `probe lsp ...` | LSP 데몬 (아래 lsp.md) |
| `probe benchmark` | 내부 벤치마크 |

## 쿼리 문법 (핵심)
```
verify_credentials OR authenticate OR login     # 불리언
+required -excluded                             # 필수/제외
"exact phrase"                                  # 정확구
ext:py | lang:python | file:src/**/*.py | dir:tests | type:rust   # 필터 힌트
```
에이전트는 의도를 **불리언으로 번역**해서 던지는 게 정석 (임베딩 불필요).

## 랭커 (`-r`)
`bm25`(기본) · `tfidf` · `hybrid` · `hybrid2` · `ms-marco-*`(BERT 피처 빌드 필요 → 이 바이너리엔 없음)

## 토큰 예산
`--max-results N` (기본 5 권장) · `--max-tokens` · 세션 내 중복 결과 dedup 내장.
늘리기 전에 쿼리를 좁혀라.

## 실측 (62k 파일 / 49GB 워크트리, `-i '*.md'`)
| 쿼리 | 시간 | peak RSS |
|---|---|---|
| `dispatch` (단일어) | 4.57s | 149MB |
| `realtime publish dispatch` (다중어) | 11.27s | **490MB** |
| `query '<ast pat>'` 단일 파일 | 0.03s | 5MB |

## ⚠️ 알려진 버그 (RC)
- **한국어 마크다운 char-boundary panic**: `src/language/markdown.rs:240` → SIGABRT(134). 한국어 문서가 있는 리포에서 `probe search` 가 통째로 죽는다.
  - 회피: `-i '*.md'` (또는 `--ignore '*.md'`). `ci search` 는 abort 시 자동 재시도.
  - 업스트림 리포트 후보 (버전 올릴 때 재확인).
- `.codegraph` 같은 dangling 경로에서 `Error walking directory` 경고 → 결과에는 영향 없음(노이즈).
- AST 패턴은 본문 포함형이 안전: `def $N($$$A): $$$B`.

## MCP 모드 (선택)
`npx -y @probelabs/probe mcp` (raw tools) / `... agent --mcp` (에이전트 루프).
→ **Node 래퍼 상주 60~80MB**. 상주 0을 원하면 CLI를 쓴다(이 스킬의 기본).
