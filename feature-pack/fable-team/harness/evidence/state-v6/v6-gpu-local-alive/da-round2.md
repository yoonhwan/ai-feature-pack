reviewed: v2 (.claude/plans/v6-gpu-local-alive-design.md)
codex-session-id: 019f2b8b-f8c6-74b3-b6c8-4a3602fe2c97
note: resume of 019f2b85-0c93-70b2-81b4-2d1ea520b25e failed — one-shot fallback used

VERDICT: CHANGES_REQUESTED

- F1: STILL-OPEN — `os.getenv("APP_ENV", "local")` defaults to "local" when APP_ENV is unset; CI/staging without K_SERVICE but with DEV_GPU_STATUS_URL set still leaks to prod status path. Fix: remove the default ("local") so unset APP_ENV fails the allowlist check.
- F2: CLOSED — renamed to DEV_GPU_STATUS_URL; fail-closed semantics documented in _prod_alive_base_url docstring.
- F3: CLOSED — TTL configurable via DEV_GPU_STATUS_TTL_SEC; _invalidate_prod_status_cache() wired on 5xx/ConnectError/Timeout.
- F4: CLOSED — 12 pytest cases specified covering all required failure paths.
- F5: CLOSED — isinstance str check on stt/tts before caching; exact == "WARM" comparison used.
