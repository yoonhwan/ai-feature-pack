# headroom 패치노트

> 시계열 내림차순 (최신 위). headroom 자체 + 하류 체인(cliproxy) 변경에 따른 재검증 기록.

---

## [2026-07-21] 0005 — prefix-tracker 세션ID를 CC UUID로 격리 (세션간 컨텍스트 오염 근본수정)

**증상(알림)**: 여러 Claude Code 세션에서 새 메시지가 없는데도 오래된 대화 요약/expansion 블록(`headroom_*` system-reminder 계열)이 매 턴 재주입되고, 서로 다른 세션의 대화·히스토리가 섞여 보임(한 세션이 다른 세션에 한 말을 자기 것으로 오인). mbox 등 상위 통신 계층 무죄 — headroom 프록시(8790) 레벨.

**원인**: `compute_session_id`(`cache/prefix_tracker.py`)가 세션 격리 키로 CC가 매 요청 보내는 `x-claude-code-session-id`(세션 고유 UUID)를 쓰지 않고, `x-headroom-session-id`(CC는 안 보냄) → `md5(model + leading system prompt)` fallback으로만 유도. 같은 worktree에서 동일 CLAUDE.md/스킬 로드아웃(system prompt)을 공유하는 세션·서브에이전트가 **동일 fallback id로 붕괴** → per-session compression cache + frozen-prefix tracker 공유 → 요약 블록·히스토리 누출 + provider prompt cache 매 호출 재작성(주석 #2085 명시).

**실증**(0.32.1, `~/.headroom/logs/proxy.log`): `x-headroom-session-id` 출현 0회(fallback 100%). 17개 fallback 버킷을 2~8개 서로 다른 CC UUID가 공유(최악 한 버킷 8세션). compression `hit_rate` 17.1%(thrash와 정합).

**수정**: `0005-prefix-tracker-cc-session-id.patch` — `compute_session_id` 우선순위에 `x-claude-code-session-id` 추가(`x-headroom-session-id` 다음, model+system-prompt fallback **앞**). `apply.sh` 등록(marker=`x-claude-code-session-id`, 멱등).

**검증**: `kickstart` 재시작 후 proxy.log — UUID 헤더 요청 11건 전부 `session_id==그 UUID`(FIXED), 붕괴(header≠session_id) 0건. `active_sessions` 30→2(오염 in-memory 캐시 클리어).

**영향**: 멀티세션 팬아웃(v6 realtime 등, 다수 세션·서브에이전트가 같은 worktree/CLAUDE.md 공유)에서 세션간 컨텍스트 오염 + prompt cache thrash로 토큰을 낭비하던 결함. UUID 격리로 세션별 독립 tracker/cache 확보.

**부수 정리**: 같은 작업에서 0.32.1 기준 정합성 점검 → `0001`(tree-sitter thread-local, upstream 흡수 `threading.local()`)·`0003`(file-logging off toggle, 0.32.1이 `HEADROOM_FILE_LOGGING` 미참조 = proxy.log 상시 ON)을 `apply.sh`/`patches`에서 제거. proxy.log 상시 ON을 정식 채택(프록시 레벨 간헐 버그의 사후 진단 소스, 60MB rotate 상한).

---

## [2026-06-30] 하류 cliproxy 7.2.47 업그레이드 — 체인 재검증 + Codex provider env 의존 제거

headroom 바이너리/패치(0001~0003) **변경 없음**. 하류 cliproxy를 7.2.15→7.2.47로 올린 뒤(429 쿼터 failover — `../cliproxyapi/NOTES.md`) headroom 경유 전 체인 재검증.

### 재검증 (2026-06-30)
- `/health` → `ready`, `anthropic_api_url=http://127.0.0.1:8317` (cliproxy 7.2.47).
- `claude-hr.sh` **fail-open** 유지(health 실패 시 직결).
- **Codex 경로**: `~/.codex/config.toml` `[model_providers.headroom]` `base_url=http://127.0.0.1:8790/v1`, `wire_api=responses` → `/v1/responses` `completed`.

### Codex provider — env_key → experimental_bearer_token (케이스 H)
TUI/GUI(Cursor·IDE)는 `.zshrc`/`.zshenv`를 안 읽어 `env_key="CODEX_DUMMY_API_KEY"`가 비면 `Missing environment variable: CODEX_DUMMY_API_KEY`로 기동 실패(GUI 변종). 영구 해소를 위해 env_key 대신 **inline `experimental_bearer_token = "dummy"`** 로 전환 — codex가 env를 조회하지 않으므로 어떤 실행 컨텍스트에서도 동작. 실제 구독 인증은 cliproxy OAuth upstream이 처리(더미 토큰은 로컬 프록시용).

```toml
# ~/.codex/config.toml  [model_providers.headroom]
base_url = "http://127.0.0.1:8790/v1"
# env_key 제거 → inline bearer (TUI/GUI에서 env 미주입돼도 안전)
experimental_bearer_token = "dummy"
wire_api = "responses"
```
