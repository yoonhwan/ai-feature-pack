# Serena → code-intel 치환표 (은퇴 근거)

## 도구 1:1 매핑
| Serena MCP 도구 | 대체 | 실측 비교 |
|---|---|---|
| `activate_project` | **없음** (사전 활성화 폐지) | 2일간 10회 호출 = 순수 오버헤드 |
| `get_current_config` | `ci doctor` | 2.38s → 0.4s |
| `initial_instructions` | 스킬 SKILL.md 자동 로드 | 5회/2일 오버헤드 |
| `search_for_pattern` | `ci search` | **127.25s(빈 결과) → 4.6s** |
| `find_symbol` | `ci sym <name>` | 4.2~13.1s → 0.00~6.5s |
| `find_referencing_symbols` | `ci sym --callers` / `ci refs` | 4.2s+ → **0.36s / 0.75s** |
| `get_symbols_overview` | `ci outline <file>` | +토큰 수 표시 |
| `find_file` / `list_dir` / `read_file` | `rg` / `ls` / `Read` | 네이티브가 더 빠름 |
| `replace_symbol_body` · `insert_*_symbol` · `safe_delete_symbol` · `rename_symbol` | **`Edit`** (네이티브) | **2일간 사용 0회** |
| `replace_content` / `replace_in_files` | `Edit` / `sed`/스크립트 | 동일 |
| `write_memory` / `read_memory` / `list_memories` | `docs/memory/*.md` | 메모리 4개뿐(16KB) |
| `onboarding` | `docs/` 직접 읽기 | — |
| `open_dashboard` | 없음 | 대시보드는 `web_dashboard: false` 로 차단 |

## 은퇴 근거 (실측 요약)
| 지표 | Serena 2.1.1 | code-intel |
|---|---|---|
| 의미검색 | 127.25s, 빈 결과 | 4.6s, 랭킹 결과 |
| 호출자 추적 | 4.2s+ (활성화 선행) | 0.36s |
| 상주 메모리 | 946MB → **5.1GB 누수** (peak 21GB) | **0MB** |
| 사전 절차 | activate + config 확인 필수 | 없음 |
| 실사용(2일 583 tool_use) | 33콜(5.7%), 심볼편집 0 | — |
| 디스크 | `.serena` 367개 워크트리 **1.5GB** | 0 |

## Serena 완전 제거 순서 (Phase 5)
```bash
# 1) 메모리 이관
cp <repo>/.serena/memories/*.md <repo>/docs/memory/
echo ".serena/" >> <repo>/.gitignore

# 2) 워크트리 캐시 회수 (1.5GB)
rm -rf <repo>/.worktrees/*/.serena

# 3) 프로세스/기동 경로
grep -rn "serena" ~/.claude/settings.json ~/.claude/hooks ~/.codex/config.toml \
  ~/.claude.json ~/.config/opencode/opencode.json 2>/dev/null
# → 훅/MCP 등록 제거, 9493 프로세스 종료

# 4) 캐시·임시
rm -rf ~/.serena                        # config, logs, language_servers, memories, bridges
rm -rf ~/.cache/serena                  # (있으면)
rm -rf "$TMPDIR"/serena* /tmp/serena*   # 로그/소켓 잔여
rm -rf ~/Library/Caches/serena* 2>/dev/null

# 5) 설치본 제거 (uv tool 캐시)
uv tool uninstall serena-agent 2>/dev/null || true
rm -rf ~/.cache/uv/archive-v0/CZreCULOkArbDptSBCrL8   # serena 전용 archive (확인 후)
# ⚠️ CZreC... 는 serena 전용으로만 쓰인 것을 확인하고 삭제 (다른 툴 공유 가능성)

# 6) 검증
grep -rn "serena" ~/.claude ~/.agents ~/.codex ~/.config/opencode 2>/dev/null | grep -v DEPRECATED
ps -Ao command | grep -c "[s]erena"      # 0 이어야 함
```

## 롤백
- 설정: `~/.claude.json`, `~/.codex/config.toml.bak-headroom-off-*`
- 스킬: 심링크만 제거하면 code-intel 비활성(파일은 정본에 남음)
- Serena 복귀가 필요하면 `~/.serena` 백업 tar + MCP 등록 재삽입 (권장하지 않음 — 실측 근거)
