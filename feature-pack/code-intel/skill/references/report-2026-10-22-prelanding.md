# [사전 공지] Serena 은퇴 · code-intel 스킬 도입 (2026-10-22)

**상태**: 도입 직전. Phase 0·1(스킬 구축 + 4개 하네스 심링크) 완료, Phase 2~5 순차 진행 예정.
**영향**: 모든 팀장/아키/워커/나노 세션. **진행 중 세션은 이 문서를 증류·승계 산출물에 반드시 포함**할 것.

---

## 1. 한 줄 요지

`mcp__serena__*` 계열 도구를 **전부 폐기**하고, 하네스 공통 스킬 **`code-intel`**(= `probe` + `tilth` CLI)로 대체한다.
**사전 활성화 절차(`activate_project`, `get_current_config`)가 사라진다** — 세션은 이제 코드 탐색 전에 아무것도 켜지 않는다.

## 2. 대체 도구 (외워야 할 것은 4줄)

```bash
CI=~/.claude/skills/code-intel/scripts/ci     # 어떤 하네스에서든 동일
$CI search "질의" <path>                        # 의미/키워드 검색 (BM25 + AST 완결 블록)
$CI sym <sym> --callers --scope .              # 호출자/정의 (0.36s)
$CI outline <file>                             # 읽기 전 구조 + 토큰 수
$CI refs "<file>#<sym>"                        # LSP 정밀 참조 (온디맨드)
```

| 기존 (Serena) | 신규 |
|---|---|
| `activate_project` / `get_current_config` / `initial_instructions` | **없음** (`ci doctor` 로 대체) |
| `search_for_pattern` | `ci search` |
| `find_symbol` / `find_referencing_symbols` | `ci sym` / `ci sym --callers` 또는 `ci refs` |
| `get_symbols_overview` | `ci outline` |
| `replace_symbol_body` / `insert_*_symbol` / `rename_symbol` / `safe_delete_symbol` | **`Edit`** (네이티브) |
| `write_memory` / `read_memory` | `docs/memory/*.md` |

## 3. 근거 (실측 · 2026-10-22)

**호출 계측 (최근 2일, claude 세션 전체: tool_use 134,911건)**
| serena 도구 | 호출 수 | 성격 |
|---|---|---|
| `search_for_pattern` | 1,050 | 검색 (가장 느림) |
| `activate_project` | 702 | **순수 오버헤드** |
| `initial_instructions` | 602 | **순수 오버헤드** |
| `find_symbol` | 138 | 탐색 |
| `get_symbols_overview` | 46 | 탐색 |
| `find_referencing_symbols` | 6 | 참조 |
| `replace_symbol_body`·`insert_*`·`rename_*`·`safe_delete` | **0** | 심볼 편집 = 미사용 |

→ serena 호출의 **50.8%가 사전 절차**(activate+instructions), 실사용 편집 도구는 **0회**.

**성능 (62k 파일 / 49GB 워크트리)**
| 작업 | Serena 2.1.1 | code-intel | 배율 |
|---|---|---|---|
| 의미검색 | 127.25s (빈 결과) | 4.6s (랭킹 결과) | 28× |
| 호출자 추적 | 4.2s+ (활성화 선행) | 0.36s | 6~12× |
| 상주 메모리 | 946MB → **5.1GB 누수**(peak 21GB) | **0MB** (CLI 원샷) | — |
| 디스크 | `.serena` 워크트리 367개 **1.5GB** | 0 | — |

참고: 이미 정리한 것 — serena 9493 중복 인스턴스 1GB, 5.1GB 누수 프로세스, `web_dashboard: false` 적용, codex의 headroom 경유 해제(`model_provider = cliproxy`).

## 4. 진행 중 세션이 지금 할 일 (3가지)

1. **이 문서를 컨텍스트에 남긴다** — 증류(`tmuxc distill`)/승계 6단계의 "상태·할 일·요약" 항목에 **§2 대체 도구 4줄**과 **§5 타임라인**을 포함한다. (경로만 넘기면 다음 세대가 못 읽는다)
2. **serena 도구를 새로 쓰지 않는다** — 지금 쓰던 흐름이 있으면 `ci` 로 바꿔서 이어간다. 활성화 대기로 멈추지 말 것(사전 절차 폐지).
3. **심볼 편집은 `Edit`** — 심볼 단위 자동 편집 도구는 0회 사용 실측으로 폐기. 리팩터 영향도는 `ci sym <sym> --callers` 1회로 확인.

## 5. 타임라인 (각 Phase 게이트 통과 시 다음 진행)

| Phase | 내용 | 상태 |
|---|---|---|
| 0 | 스킬 스캐폴드(`SKILL.md` + `ci` + `serena-audit` + references 5종) | **완료** |
| 1 | 심링크 랜딩: `~/.agents`(claude·pi), `~/.codex`, `~/.config/opencode` | **완료** |
| 2 | 지침 패치: repo `CLAUDE.md`(`[REALITY]` + Serena 섹션), `docs/rules/`, 전역 `~/.claude/CLAUDE.md`, **SessionStart 훅의 activate_project 제거** | 예정 |
| 3 | 하네스별 serena MCP/프로세스 제거 (claude → codex → 9493) | 예정 |
| 4 | 2주 관측: `serena-audit` 7일 연속 0 · `ci` 일 5회+ · p95 ≤5s | 예정 |
| 5 | **serena 완전 삭제 + 캐시·임시 전부 삭제** | 예정 |

**Phase 3 이후에는 `mcp__serena__*` 호출이 실패한다.** 그 시점에 serena 도구를 쓰는 세션이 있으면 작업이 끊긴다 → 미리 `ci` 로 갈아타는 것이 이 공지의 목적.

## 6. Phase 5 삭제 범위 (예고)

- 프로세스/기동: serena 9493, launchd/훅 등록, `~/.claude.json`·`~/.codex/config.toml`·`~/.config/opencode/opencode.json` 의 serena MCP 블록
- 설정/캐시: `~/.serena/`(config·logs·language_servers·memories·bridges), `~/.cache/serena`, `$TMPDIR/serena*`
- 프로젝트: 각 워크트리 `.serena/` **367개 1.5GB**, 메모리 4개는 `docs/memory/` 로 이관 후 삭제
- 설치본: uv tool 아카이브
> 메모리(4개/16KB)는 삭제 전 `docs/memory/` 로 이관한다. 그 외 `.serena` 내용물은 캐시로 판단(복원 불필요).

## 7. 롤백 / 문의

- 설정 백업: `~/.codex/config.toml.bak-headroom-off-*`, `~/.claude.json` 사본, `~/.serena` tar
- 스킬만 끄기: 심링크 제거 (`ln -sfn` 로 즉시 복구)
- 이의/우려는 플랜팀장 경유로 회신 — Phase 3 착수 전까지 반영 가능.
