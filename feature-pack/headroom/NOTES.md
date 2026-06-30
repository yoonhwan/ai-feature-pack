# headroom 패치노트

> 시계열 내림차순 (최신 위). headroom 자체 + 하류 체인(cliproxy) 변경에 따른 재검증 기록.

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
