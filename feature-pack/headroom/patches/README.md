# headroom 운영 패치 (patches/)

PyPI `headroom-ai` 를 그대로 `pip install` 하면 운영에 필요한 결함 수정/기능이 빠져 있다. 이 폴더는 검증된 패치를 site-packages에 멱등 적용한다. 현재 베이스: **`headroom-ai==0.32.1`**.

## 결함과 운영 패치

**B. 빈 압축 출력 → Anthropic 400** *(0002)*
`content_router.compress()`가 non-empty 입력을 빈 문자열로 압축해 반환하면, 프록시가 빈 user-message content를 Anthropic에 보내 `400 messages.N: user messages must have non-empty content`로 **요청 전체가 거부**된다.
→ `0002-content_router-empty-output-guard.patch`: 반환 직전 **빈값 가드** — non-empty 입력인데 결과가 비면 원본 fallback. (upstream PR #771로 제출; main 미반영이라 현행 버전에도 필요한 독립 안전망)

**D. server-side `tool_search_tool_result` → SSE 502** *(0004, 0.31.0+ 2026-07-21)*
tool이 많은 요청(~15개+)에서 Anthropic이 server-side tool search를 트리거해 응답에 `tool_search_tool_result` 등 신규 content block을 넣는데, headroom `_response_to_sse`(`proxy/handlers/streaming.py`)가 이 block type을 몰라 502 `Unable to safely convert buffered response to SSE`. cliproxy/upstream 무죄, headroom 단독.
→ `0004-streaming-server-tool-result-sse.patch`: server-side tool 결과 계열(`tool_search_tool_use/result`, `web_search`/`code_execution_tool_result`, `mcp_tool_use/result`)을 `server_tool_use`처럼 content_block passthrough.

**E. 세션ID 붕괴 → 세션간 컨텍스트 오염 + prompt cache thrash** *(0005, 2026-07-21)*
`compute_session_id`(`cache/prefix_tracker.py`)가 CC의 `x-claude-code-session-id`(세션 고유 UUID)를 무시하고 `x-headroom-session-id`(CC 미발신) → `md5(model + leading system prompt)` fallback으로만 세션을 식별. 같은 worktree/CLAUDE.md/스킬 로드아웃을 공유하는 세션·서브에이전트가 동일 fallback id로 붕괴 → per-session compression cache + frozen-prefix tracker 공유 → 요약/히스토리 누출 + prompt cache 매 호출 재작성(#2085). 실증: 17개 fallback 버킷을 2~8개 CC UUID가 공유(최악 8세션), `hit_rate` 17.1%.
→ `0005-prefix-tracker-cc-session-id.patch`: `compute_session_id` 우선순위에 `x-claude-code-session-id` 추가(`x-headroom-session-id` 다음, fallback 앞). marker=`x-claude-code-session-id`, 멱등.

## 제거된 패치 (이력)

- **0001 tree-sitter thread-local** — 0.23.0에서 `ThreadPoolExecutor` 워커가 pyo3 `unsendable` Parser를 스레드 공유하다 `PanicException`(→500/400)나던 것을 `threading.local()`로 격리하던 백포트. **0.24.0+ upstream이 흡수**(`_tree_sitter_local = threading.local()`)해 불필요 → **2026-07-21(0.32.1 확인) 제거.**
- **0003 file-logging off toggle** — `HEADROOM_FILE_LOGGING=off`일 때 rotating file handler를 안 붙이던 패치. 0.32.1은 이 env를 아예 보지 않고 `_setup_file_logging`이 무조건 실행 = **proxy.log 상시 ON**. **상시 ON을 채택** — 프록시 레벨 간헐 버그는 사후 로그가 유일 증거(0005 진단이 그 실증)이고 60MB rotate 상한이라 비용이 무시할 수준 → **2026-07-21 제거.**

## 적용

```bash
bash patches/apply.sh                            # 기본 venv: ~/.headroom-venv
bash patches/apply.sh /path/to/venv/bin/python   # 다른 venv 지정
# 또는: HEADROOM_PYTHON=/path/to/python bash patches/apply.sh
```

- **멱등**: marker가 이미 있으면(적용됐거나 upstream 흡수) 건너뛴다.
- 각 파일은 적용 전 `.bak-<timestamp>`로 백업.
- 적용 후 프록시 재기동 권장: `launchctl kickstart -k gui/$(id -u)/com.headroom.proxy`

## 검증

- 빈값 경로(0002): 400 0 (원본 fallback 확인)
- server-side tool 결과(0004): tool 다수(29개) 요청 SSE 502 0
- 세션ID 격리(0005): 재시작 후 UUID 헤더 요청 `session_id==그 UUID`, cross-session 붕괴 0
