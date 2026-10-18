reviewed: v1 (.claude/plans/v6-gpu-local-alive-design.md)
codex-session-id: 019f2b85-0c93-70b2-81b4-2d1ea520b25e

VERDICT: CHANGES_REQUESTED

- K_SERVICE gate is too narrow: non-Cloud-Run prod/staging/CI with PROD_GATEWAY_URL set will hit prod status. Fix with explicit local-dev opt-in flag plus env allowlist.
- PROD_GATEWAY_URL as behavior switch is a footgun: config presence changes liveness semantics and can add 5s external dependency. Rename to explicit DEV_GPU_STATUS_URL and document fail-closed behavior.
- TTL can pass a dead GPU for up to 10s after WARM. Fix by lowering/configuring TTL and invalidating cache on downstream provider 5xx/connection failures.
- No regression tests cover the new fail-closed invariant. Add tests for timeout, non-200, invalid JSON, missing key, COLD, WARM, unknown service, and cache-only-on-success.
- Status API contract is implicit. Fix by validating response schema/types before caching and pinning expected keys: stt/tts must be present strings, not truthy loose values.
