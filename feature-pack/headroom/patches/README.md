# headroom 운영 패치 (patches/)

PyPI `headroom-ai` 를 그대로 `pip install` 하면 운영에 필요한 결함 수정/기능이 빠져 있다. 이 폴더는 검증된 패치를 site-packages에 멱등 적용한다. 운영 기준 베이스: **`headroom-ai==0.33.0`**. ML extras(`headroom-ai[ml]`/`[all]`, Kompress)는 이 운영 경로에 포함하지 않는다.

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

**F. buffered Anthropic 요청의 재시도·timeout 계약 불일치** *(0006 legacy / 0009 for 0.33.x)*
buffered `stream:false` 요청이 일반 프록시 retry budget을 공유하면 upstream 429/5xx·transport timeout에서 같은 대형 요청을 반복 전송해 rate-limit과 latency를 불필요하게 키울 수 있다. 반대로 caller deadline을 넘긴 timeout은 정본 오류로 관측되지 않는다.
→ `0006-buffered-timeout-retry-contract.patch`는 구형 0.32 계열용, `0009-buffered-timeout-retry-contract-033.patch`는 0.33.x 소스 위치용이다. buffered Anthropic 경로를 1회 시도·deadline 제한으로 고정하고, timeout은 typed 504로 반환하며 upstream 429/500 등 status/body는 fallback 없이 보존한다.

**G. compression cache stats 키 드리프트** *(0007)*
0.33 계열에서 compression cache가 보고하는 `tokens_saved`와 기존 집계 코드가 기대하는 `total_tokens_saved`가 달라 stats 합계가 0으로 오인될 수 있다.
→ `0007-compression-cache-stats-key.patch`: canonical 키를 우선 읽고 legacy 키를 보조해 운영 통계를 보존한다.

**H. hidden child lineage가 ancestor cache tracker를 덮어씀 → sibling cold-start** *(0008, critical)*
같은 Claude session 안에서 hidden child branch가 ancestor tracker의 prefix를 덮어쓰면, 이후 real sibling이 ancestor의 provider-cache checkpoint를 이어받지 못하고 cold-start한다. 증상은 정상 연속 요청의 `cache_read↑ / cache_write↓ / frozen>0` 대신 `cache_read` 급락·대형 `cache_write`·`frozen=0`으로 나타나며, 재전송 토큰과 rate-limit 소모가 급증한다.
→ `0008-prefix-tracker-sibling-lineage.patch`: ancestor tracker를 bounded checkpoint로 보존하고 sibling이 가장 긴 일치 prefix에서 branch-local tracker를 복원한다. hidden branch의 bytes와 maturation state가 sibling/ancestor로 누출되지 않도록 분리한다.

> **0.33 패치 분기 주의**: 0.32용 0006은 0.33.0의 `server.py`/Anthropic handler 문맥과 맞지 않는다. `apply.sh`는 `headroom-ai` 버전을 읽어 0.33.x에는 0009, 그 외에는 0006을 선택한다. 패치 파일을 삭제하고 upstream main만 따라가는 것으로 H의 결함이 자동 해결된다고 가정하지 않는다. upstream이 동일 수정사항을 흡수했는지는 marker와 회귀 계약으로 확인해야 한다.

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
- 현재 운영 로그 코드는 제거하지 않는다. 내부 rotating `~/.headroom/logs/proxy.log`는 cache hit/write/frozen과 canonical upstream 경로를 사후 입증하는 운영 증거이며, launchd stdout/stderr 캡처와 구분된다.

## 검증

- 빈값 경로(0002): 400 0 (원본 fallback 확인)
- server-side tool 결과(0004): tool 다수(29개) 요청 SSE 502 0
- 세션ID 격리(0005): 재시작 후 UUID 헤더 요청 `session_id==그 UUID`, cross-session 붕괴 0
- retry contract(0009): timeout 1회·typed 504, upstream 429/500 status/body passthrough
- cache stats(0007): `tokens_saved`/legacy key 집계 계약
- sibling lineage(0008): ancestor prefix 보존, hidden branch bytes 유입 금지, sibling frozen checkpoint 보존
