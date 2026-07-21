# headroom 0.23.0 핫픽스 (patches/)

PyPI 최신 `headroom-ai==0.23.0` 을 그대로 `pip install` 하면 운영에 치명적인 결함이 살아 있다. 이 폴더는 검증된 패치를 site-packages에 멱등 적용한다.

## 왜 필요한가 (버전 퍼즐)

| 시각(UTC) | 사건 |
|---|---|
| 2026-06-03 16:46 | upstream main에 thread-local tree-sitter fix 커밋(`38aefc1d`) |
| 2026-06-04 14:21 | **v0.23.0 릴리스 — 그러나 fix가 빠진 갈래에서 태깅**(`v0.23.0...38aefc1d` = diverged) |
| 이후 | fix는 main에만, **0.24.0 미릴리스** |

→ `pip install headroom-ai`(=0.23.0) 사용자는 **fix를 못 받는다.** 0.24.0이 PyPI에 뜨면 이 패치는 불필요(`pip install -U headroom-ai`).

## 결함과 운영 패치

**A. tree-sitter `unsendable` panic → 500 / 400**
`code_compressor.py`가 tree-sitter Parser(pyo3 `#[pyclass(unsendable)]`)를 **모듈 전역 dict로 스레드 공유**한다. 압축은 `ThreadPoolExecutor`에서 도므로, 한 스레드가 만든 파서를 다른 워커가 재사용하면 `pyo3_runtime.PanicException("Parser is unsendable, but sent to another thread")`. panic은 `BaseException` 상속이라 `except Exception`을 통과 → "No response returned" → **500**(대용량 요청), 또는 빈 content → **400**.
→ `0001-code_compressor-thread-local-parser.patch`: 파서 캐시를 `threading.local()`로 **스레드별 격리** + `except (Exception, _Pyo3PanicException)`로 잔여 panic도 passthrough degrade. (upstream main의 fix와 동일 근본 대응을 0.23.0에 백포트)

**B. 빈 압축 출력 → Anthropic 400**
`content_router.compress()`가 non-empty 입력을 빈 문자열로 압축해 반환하면, 프록시가 빈 user-message content를 Anthropic에 보내 `400 messages.N: user messages must have non-empty content`로 **요청 전체가 거부**된다.
→ `0002-content_router-empty-output-guard.patch`: 반환 직전 **빈값 가드** — non-empty 입력인데 결과가 비면 원본 fallback. (upstream PR #771로 제출됨; main에는 미반영이라 0.23.0뿐 아니라 현 main에도 필요한 독립 안전망)

**C. 기본 rotating file log → 불필요한 대용량 로그**
`headroom.proxy.server`는 앱 생성 시 `~/.headroom/logs/proxy.log` rotating file handler를 무조건 붙인다. 운영 표준은 평상시 파일 로그 OFF, 이슈 대응 때만 launchd stdout/stderr 캡처 ON이다.
→ `0003-proxy-file-logging-env-toggle.patch`: `HEADROOM_FILE_LOGGING=off`일 때 내부 rotating file handler를 붙이지 않는다.

**D. server-side `tool_search_tool_result` → SSE 502** *(0.31.0+, 2026-07-21)*
tool이 많은 요청(~15개+)에서 Anthropic이 server-side tool search를 트리거해 응답에 `tool_search_tool_result` 등 신규 content block을 넣는데, headroom `_response_to_sse`(`proxy/handlers/streaming.py`)가 이 block type을 몰라 502 `Unable to safely convert buffered response to SSE`. cliproxy/upstream 무죄, headroom 단독.
→ `0004-streaming-server-tool-result-sse.patch`: server-side tool 결과 계열(`tool_search_tool_use/result`, `web_search`/`code_execution_tool_result`, `mcp_tool_use/result`)을 `server_tool_use`처럼 content_block passthrough.

**E. 세션ID 붕괴 → 세션간 컨텍스트 오염 + prompt cache thrash** *(2026-07-21)*
`compute_session_id`(`cache/prefix_tracker.py`)가 CC의 `x-claude-code-session-id`(세션 고유 UUID)를 무시하고 `x-headroom-session-id`(CC 미발신) → `md5(model + leading system prompt)` fallback으로만 세션을 식별. 같은 worktree/CLAUDE.md/스킬 로드아웃을 공유하는 세션·서브에이전트가 동일 fallback id로 붕괴 → per-session compression cache + frozen-prefix tracker 공유 → 요약/히스토리 누출 + prompt cache 매 호출 재작성(#2085). 실증: 17개 fallback 버킷을 2~8개 CC UUID가 공유(최악 8세션), `hit_rate` 17.1%.
→ `0005-prefix-tracker-cc-session-id.patch`: `compute_session_id` 우선순위에 `x-claude-code-session-id` 추가(`x-headroom-session-id` 다음, fallback 앞). marker=`x-claude-code-session-id`, 멱등.

## 적용

```bash
bash patches/apply.sh                       # 기본 venv: ~/.headroom-venv
bash patches/apply.sh /path/to/venv/bin/python   # 다른 venv 지정
# 또는: HEADROOM_PYTHON=/path/to/python bash patches/apply.sh
```

- **멱등**: 이미 적용됐거나 0.24.0+ 로 이미 thread-local이면 건너뛴다.
- 각 파일은 적용 전 `.bak-<timestamp>`로 백업.
- 적용 후 프록시 재기동 권장: `launchctl kickstart -k gui/$(id -u)/com.headroom.proxy`

## 패치 베이스

`headroom-ai==0.23.0` (cp312, sdist 동일). 다른 버전엔 `apply.sh`가 dry-run 실패로 멈추니 버전 확인: `~/.headroom-venv/bin/headroom --version`.

## 검증

- 크로스스레드 12워커 parse: panic 0
- 526KB 대용량 요청: 500/abort 0, 재시도 없이 통과
- 빈값 경로: 400 0 (원본 fallback 확인)
- `HEADROOM_FILE_LOGGING=off`: RotatingFileHandler 0
