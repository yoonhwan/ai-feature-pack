reviewed: v2 (.claude/plans/v6-gpu-local-alive-design.md)
codex-session-id: 019f2b8b-f8c6-74b3-b6c8-4a3602fe2c97
note: resumed from round2 session (resume succeeded, no -C flag for resume subcommand)

VERDICT: APPROVE

- F1: CLOSED — `APP_ENV` defaults to `""` (not `"local"`) so unset env returns None → Redis path; `test_app_env_unset_falls_to_redis` confirms httpx 0 calls.
- F2: CLOSED — behavior switch is `DEV_GPU_STATUS_URL`; old prod-named env is absent.
- F3: CLOSED — TTL configurable via `DEV_GPU_STATUS_TTL_SEC`; `_invalidate_prod_status_cache()` wired in both `transcribe` and `synthesize` on ConnectError/TimeoutException/5xx.
- F4: CLOSED — suite covers gate, fail-closed, schema drift, cache success-only, TTL/refetch, K_SERVICE invariant; 16 cases pass.
- F5: CLOSED — `stt`/`tts` validated as `isinstance str` before cache; exact `state == "WARM"` comparison enforced.

Fresh attacks: CLOSED — no silent True/False masking anywhere; `K_SERVICE` is first check in `_prod_alive_base_url` blocking all prod paths; double-checked locking single-flight is correct; `_invalidate_prod_status_cache` is reachable from both `transcribe` and `synthesize` failure paths; `check_gpu_alive` returns `None` on success (raise-on-failure protocol correct).
