# B1 Implementation Progress — `ft-lstsnap-impl#41`

> Authority: `design/B1-DIRECTION-VERIFICATION.md` (§3 conditions 1-8, §4 six steps, §5 PASS)
> Fence authority: `design/B1-FENCE-RESOLUTION.md` (choice D, §3 Step2 conditions 1-8, §4 boundaries)
> Baseline: `1abe1646` on `feat/v6-realtime-live`. All work UNCOMMITTED (Master gate).
> Serena MCP unavailable this session (ToolSearch miss) — caller enumeration done via exhaustive `grep -rn`.

## Status

| Step | State | Note |
|---|---|---|
| 1. structural-only (cutover DTO/protocol) | **DONE** | option (a) — absorbed into C0-allowed `contracts.py` |
| 2. durable owner authority (opaque snapshot) | **DONE** | 10/10 behavior cases verified on fakeredis real Lua |
| 3. out-of-C0 owner composite | **DONE** | `activation_subgate/release_owner_cutover.py` (new, C1 side) |
| 4. owner/reconcile threading | **DONE** | all three triggers take the port, default `None` |
| 5. production composition | **DONE** | seal amended per `B1-SEAL-RESOLUTION.md` (c)+(a+); bundle seam wired |
| 6. Q1 guards | **DONE** | 13 guards, 9 mutants all caught |
| 6b. same-SHA live | AWAITING GATE | env freshness (tester) + **Q3 full seal — do NOT self-judge** |

## Step 1 — DONE

`contracts.py` gained `ReleaseCutoverRoute/Request/Projection/Result/Port` (+ new `window_json`
field on the request, per condition 3 — same immutable readiness window, no re-read).
`release_ready.py` imports them from there and re-exports (so `release_finalizer.py` is untouched);
`activation_subgate/release_resolver.py` re-pointed to `contracts.py` per architect recommendation.
The rejected standalone `release_cutover_contracts.py` was deleted.

**Why not a new module**: any new `worker.graph.speech.pulse.v6.*` module is automatically
`C1_FORBIDDEN` (`tests/worker/unit/_v6_module_index.py`, exact-SHA `52498eb9` baseline), and a C0
root importing it breaks `test_v6_c1_rollout_fence.py`. Manifest amendment = MUST-OUT.

## Step 2 — DONE

Opaque durable owner-authority snapshot, per `B1-FENCE-RESOLUTION.md` §3. C0 stores and
byte-compares only; typed generation/validation stays out-of-C0.

- `release_intent.py` — `ReleaseIntent` gained `owner_authority_json` / `owner_authority_digest`
  (both `str`, default `""`). Deliberately untyped: importing `PressBinding` here would break the
  fence (`press_context` is C1-forbidden).
- `release_intent_lua.py` — `RELEASE_REGISTER_LUA` now compares **both** fields exactly inside the
  existing `identity_key` branch; either mismatch returns the **existing** `{4}`=CONFLICT. No new
  outcome code. Absent-on-both-sides compares equal (flag-off byte equivalence). Terminal Lua
  untouched.
- `release_intent_store.py` — both fields travel in the **same** `RELEASE_REGISTER_LUA` call
  (same registration payload as intent/owner-index/retry membership; no separate key, no
  follow-up write). `get()` reconstructs them, defaulting to `""` for pre-B1 intents.

### Verified behavior (fakeredis, real Lua)

| Case | Result |
|---|---|
| A1-A3 flag-off (no snapshot): new / replay / different entry | `new` / `same_owner` / `same_intent_different_entry` |
| A4 `get()` on snapshot-less intent | `""` / `""` |
| B1-B3 with snapshot: new / exact replay / different entry | `new` / `same_owner` / `same_intent_different_entry` |
| C1 digest mismatch | `conflict` |
| C2 canonical JSON mismatch | `conflict` |
| C3 snapshot dropped on replay | `conflict` |
| C4 stored snapshot after conflict | unchanged (owner authority never overwritten) |

Round-trip proof (recorded in `B1-FENCE-RESOLUTION.md` §2): real `PressBinding` →
`canonical_json_bytes` (305 B) → str → `model_validate_json` returns an object `==` the original,
with a stable recomputed digest. So the opaque string loses no information.

## Step 3 — DONE

New out-of-C0 module `activation_subgate/release_owner_cutover.py`. No C0 root imports it, so the
fence is untouched (`activation_subgate` is already entirely outside the C0 baseline).

Public surface: `build_owner_authority_snapshot` (ACTIVE owner delivery → canonical JSON +
domain-separated digest), `load_owner_authority` (reparse + digest re-verify), `compute_binding_digest`,
`build_release_identity`, `build_transport_bytes`, `DurableOwnerReleaseCutover`, `OwnerAuthorityError`.

**`c_live_builder.build_c_live_identity` was NOT reused** — it calls `load_authority`
(`pulse_route`) and `load_entry` (owner stream) at build time, which is exactly the late re-load
the architect rejected. This composite instead rebuilds identity from the durable snapshot plus
the readiness `window_json` only, so it stays correct after route TTL expiry and owner-entry trim.

`ActivationProducer` is likewise not reused (condition 4): `producer.py:102-108` registers an
ingress decision marker and performs `guarded_xack`, but the owner RELEASE_CONTROL ACK belongs
solely to the release terminal Lua.

Enqueue outcome routing: durable-positive/idempotent/terminal-existing → delegate to the existing
`ActivationReleaseCutover`; `STALE_COALESCED_LOSER` → DEFERRED; `IDENTITY_CONFLICT` /
`STRUCTURAL_CORRUPTION` → raise (owner PEL entry and retry survive).

One typing note: `RedisReader` and `RedisHashReader` describe the same live client but declare
`hgetall` incompatibly (sync-or-awaitable vs strict coroutine), so they cannot be inherited
together. `ReleaseOwnerRedis` restates the union of methods actually called.

### Verified behavior

| Case | Result |
|---|---|
| snapshot build → reparse | object `==` original (301 B canonical) |
| absent / unparseable / wrong-digest snapshot | `OwnerAuthorityError` (fail-loud, zero-write) |
| valid-but-different binding swapped in | refused — digest divergence detected |
| digest domain separation | differs from a bare SHA-256 of the same bytes |
| `ReleaseOrigin` trigger | `purpose=release`, watermark carried from intent identity |
| `created_at` `1750000000123-0` → transport | float on the model, **int** `1750000000` in canonical bytes |
| transport projection | full — includes `job_id`, `semantic_payload_hash`, `audit` (1203 B) |
| determinism | same durable inputs → identical `job_id` (basis for three-trigger order-independence) |
| transport → `FrozenWindowJobIdentity` | revalidates, same `job_id` |

Condition 6 confirmed empirically: `AuditTrace.model_dump()` yields `1750000000.0` and
`canonical_json_bytes` rejects it with `integer-only violation at $.created_at` — hence the
explicit transport projection.

## Step 4 — DONE

The cutover port now reaches all three release triggers, each defaulting to `None` so the
flag-off path is unchanged:

- `release_finalizer.reconcile_release_suppressing` → forwards `release_cutover`
  (audio epilogue + direct-exhaustion wrappers).
- `release_finalizer.process_release_delivery` → forwards `release_cutover` to `reconcile_release`
  and captures the owner authority before registering (see the port note below).
- `ingress.process_v6_audio_entry` → accepts `source_handoff` / `release_cutover`, passes the
  former to `drain_contiguous` (which already had the parameter) and the latter to the epilogue.

### Design self-correction (recorded deliberately)

The owner snapshot was first added to `V6GraphDeps` as two build-time strings. That was **wrong**:
`V6GraphDeps` is built once per consumer, so one press's authority would have been pinned onto
every later session. Replaced with `OwnerAuthorityPort` in `contracts.py`
(`capture(envelope, entry_id) -> tuple[str, str]`), injected as a port and invoked **per owner
delivery**. Port absent → `("", "")` → registration byte-identical to pre-B1.

## Step 5 — DONE

### Seal amendment (per `B1-SEAL-RESOLUTION.md`, Q2 narrow: Architect + Checker)

`graph_runtime.py` left `_DOWNSTREAM_PATHS`; `_SEALED_PATHS` and the zero-diff seal on `graph.py`,
`nodes`, `d1_boundary.py`, `d2_assembly.py` and `gateway` are untouched. The removed zero-diff
protection was replaced with three semantic guards, not a bare exclusion:

- `test_graph_runtime_delta_is_limited_to_b1_port_forwarding` — `V6GraphDeps` may gain only
  `source_handoff` / `release_cutover` / `owner_authority`, each defaulting to `None`.
- `test_graph_runtime_never_references_d_wire_or_e_surfaces` — no D1/D2/E marker in the source.
- `test_graph_runtime_authority_wrappers_stay_transparent` — AST check: authority wrappers have no
  try/except, no loops, and return a literal `{}`; `refine_gate_identity` stays literal `{}`.

**Guards proven non-vacuous by four mutants** (each restored afterwards; file verified clean):

| Mutant | Result |
|---|---|
| extra non-port field on `V6GraphDeps` | 2 guards fail |
| port field without `None` default | delta guard fails |
| D-WIRE surface referenced | 2 guards fail |
| authority wrapper swallows exceptions | transparency guard fails |

### Composition wiring

- `worker/main.py` — new `ActivationBundle` protocol (root + three ports). `_activation_bundle_view`
  splits the bootstrap result into `(root, port kwargs)`: absent → nothing; bare root (pre-B1
  entrypoint) → still supported, no ports; partial bundle → **loud refusal**, never half-live.
  `run_worker` now builds the bundle **before** the consumer and owns **both inside the cleanup
  `try`**, so a consumer ctor/prepare failure still reaches the `finally` that shuts the started
  root down. `worker.main` still imports no concrete activation module.
- `worker/c2c_act_entrypoint.py` — constructs the concrete ports out-of-C0 and returns the frozen
  bundle: `CLiveSourceHandoff`, `DurableOwnerReleaseCutover`, `OwnerAuthorityCapture`.
- `v6_pulse_consumer.py` — accepts and stores the three ports (B3-seam pattern), forwards them into
  `V6GraphDeps`, and passes the **same** `release_cutover` instance on the due-claim path
  (`_reconcile_release_owner`) so all three triggers share one composite.
- `release_owner_cutover.py` — added `OwnerAuthorityCapture`, the `OwnerAuthorityPort`
  implementation. Stateless by construction: it cross-checks the current delivery against the
  loaded authority and returns a fresh snapshot per press, caching nothing.

### Verified

| Case | Result |
|---|---|
| bundle absent / bare root / full | `(None, {})` / root passthrough, no ports / root + 3 ports, instance identity preserved |
| partial bundle (each port missing) | `RuntimeError: activation bundle is incomplete: missing [...]` |
| consumer holds injected ports | all three by identity |
| deps + due-claim threading | same instances reach `_get_graph` and `_reconcile_release_owner` |
| flag-off defaults | consumer and `V6GraphDeps` all `None` |

### `flag-off` payload condition (HELM #529, architect §6) — DONE

Empty snapshot pairs are now **omitted** from the durable payload rather than written as empty
strings, so a flag-off registration stays byte-identical to a pre-B1 record. This closes a real
false-CONFLICT risk: B1 requires exact replay compare of both fields, so a pre-B1 record (keys
absent) versus a post-B1 flag-off record (keys present but empty) would otherwise have been judged
a conflict. `get()` still reads a missing key back as `""` for read compatibility.

Verified: flag-off payload keys are exactly the pre-B1 set; flag-off replay → `same_owner`;
flag-on replay → `same_owner`; dropping the snapshot on replay → `conflict`; registering without a
snapshot then replaying with one → `conflict`.

## Step 5 — original blocker (resolved)

`tests/worker/unit/test_v6_c2c_act_green_seal_red.py::test_c_live_d_wire_and_e_scopes_remain_outside_activation_green`
asserts `git diff --name-only HEAD` is empty for `_DOWNSTREAM_PATHS`, which includes
`worker/graph/speech/pulse/v6/graph_runtime.py`. But `B1-FENCE-RESOLUTION.md` §4 Step 5 explicitly
directs wiring `V6GraphDeps` / `make_audio_authority_node` / `make_release_authority_node` — i.e.
the design instruction and the existing seal are in direct conflict.

Current state: **1443 passed, 1 failed** (this seal only). The `graph_runtime.py` changes are
deliberately NOT reverted so work can resume immediately once judged. The remaining Step 5 work
(`main.py` bundle seam, consumer injection) is on hold.

Options put to the architect: (a) exempt `graph_runtime.py` from `_DOWNSTREAM_PATHS` for B1 only,
keeping the D-WIRE/E intent; (b) avoid touching the file — appears impossible, since the authority
node bodies live there; (c) treat the seal as a C2c-ACT-era snapshot that B1 legitimately updates.
Recommended (c), pending judgment. Weakening a seal test unilaterally is not acceptable.

## Step 6 — Q1 guards DONE

`tests/worker/unit/test_v6_b1_production_wiring_guards.py` — 13 tests, all green. Existing C-LIVE
fixtures were reused (`_v6_c_live_red_fixtures`) rather than writing new setup.

### Mutant matrix — every guard proven non-vacuous

| # | Mutant (production defect simulated) | Detected by |
|---|---|---|
| M1 | write empty snapshot keys instead of omitting them | guard 1 (flag-off byte equivalence) |
| M2 | digest-only compare, skip stored JSON | guard 5 |
| M3 | emit float `created_at` in transport | guard 5 |
| M4 | accept a partial activation bundle | guard 2 |
| M5 | due-claim builds its own composite | guard 3 |
| M6 | readiness ignores durable snapshot (late re-load) | guard 4 (+1 more) |
| M7 | entrypoint stops constructing the producer | guard 6 |
| M8 | silent DEFERRED on identity conflict | guard 6 (after fix — see below) |
| M9 | delegate reached on stale-coalesced loser | guard 6 |

**M8 initially escaped and the guard was rewritten.** The first version of guard 6 asserted on
source text (`"raise OwnerAuthorityError" in source`), so a mutant that returned DEFERRED while
leaving the raise statement on an unreachable branch still passed. It now drives a real
`resolve()` with a stubbed enqueue outcome and asserts the raise actually happens, plus that the
delegate is never reached for refused/deferred outcomes. This is exactly the false-green class the
guards exist to prevent.

### Known flake (NOT caused by this work)

`test_v6_c2a_r0_contract_red.py::test_ready_entry_accepts_exact_four_field_schema_only` failed once
in six runs, then passed 8 consecutive times. It is an integration test whose harness does
`docker run` for an ephemeral Redis (`_ensure_ephemeral_redis`), so it is sensitive to container
startup/port timing. It passes in isolation, and the code path is untouched by B1 — deselecting the
new guard file changes nothing about it.

## Step 6 — original guard plan

Six guards, matching `B1-DIRECTION-VERIFICATION.md` §4.6 and `B1-FENCE-RESOLUTION.md` §5. Each one
must map to a production edge — no harness that merely restates existing coverage (stop-loss rule
4). Every guard names the mutant that must kill it, so a vacuous pass is detectable.

| # | Guard | How it is checked | Mutant that must fail it |
|---|---|---|---|
| 1 | flag-off `None` equivalence | Inactive bootstrap ⇒ all three bundle members absent; `process_release_delivery` / `reconcile_release_suppressing` / `process_v6_audio_entry` behave byte-identically to pre-B1 (registration payload without the snapshot pair, zero enqueue, zero provider) | Make any port default to a live composite instead of `None` |
| 2 | root cleanup / all-or-none | Bootstrap succeeds, then consumer ctor or `prepare()` raises ⇒ `activation_root.shutdown()` still runs (no started-root leak); ACTIVE ⇒ all three members present, inactive ⇒ all absent (never partial) | Move `V6PulseConsumer(...)` construction outside the cleanup `try` |
| 3 | same composite object identity across the three triggers | Owner delivery, due claim and audio epilogue each receive the **same instance** (assert `is`, not equality) | Construct a second composite in any one path |
| 4 | durable seed survives trim + TTL removal | After registration, delete `pulse_route:{psid}` and trim the owner stream entry, then drive readiness from each trigger ⇒ identical `job_id` enqueued every time | Re-read owner entry / `pulse_route` at readiness (the rejected late exact-load) |
| 5 | full canonical decoder | Stored JSON reparses to `PressBinding`, digest recomputes; parse/canonical/digest mismatch ⇒ loud, zero-write, zero-provider. Transport bytes carry `job_id` + `semantic_payload_hash` + `audit`, `created_at` as whole-second int | Compare digest only (skip JSON), or emit `model_dump()` float `created_at` |
| 6 | producer-removal mutant | Removing the owner producer/composite from production composition makes the reachability gate fail — proves the guard suite is non-vacuous | Delete the composite wiring; suite must go red, not stay green |

Guards 1-5 run on fakeredis with real Lua (same harness as Steps 2-3, which already exercised
register replay and snapshot lifecycle). Guard 6 follows the existing non-vacuity pattern in
`test_v6_c1_rollout_fence.py:89` (inject the mutant, assert it is detected).

Deliberately **excluded** (B1b / R-C5 per §5): empty-source and degraded-fatal-hole paths,
multi-worker concurrency, long-outage/reply-loss expansion, the full enqueue-outcome matrix,
cluster/Redis 7.4 replay, and exhaustive cold-replay canonical equivalence. Any of these is pulled
back into B1 only if it actually breaks the first trusted-PTT vertical trace.

After these six are green: no further unit rounds — go straight to the same-SHA trusted-PTT live
run. That live cutover is **Q3 full seal**; Master convenes DA and this session does not self-judge
the result.

## Verification (2026-07-27, this worktree)

```
.venv/bin/python3 -m pytest tests/worker/unit -q -p no:randomly -k v6 \
  --ignore=tests/worker/unit/test_pulse_audio_duration.py
=> 1444 passed, 792 deselected
ruff check worker/graph/speech/pulse/v6/  => All checks passed!
```

Pre-existing, unrelated to this work: full (non-`v6`) unit run shows 49 failures caused by local
`.env` overrides (e.g. `GPU_EXCLUDED_LANGS=['uz']` vs expected `['zh','ja']`) — none of the failing
tests reference any module changed here (grep-verified) — plus `test_pulse_audio_duration.py`
failing to import `soundfile` (module not installed).

## Constraints carried into Steps 3-6

1. Snapshot generation/validation lives ONLY in the out-of-C0 composite; on consumption it
   reparses to `PressBinding` and recomputes canonical bytes + digest — mismatch is fail-loud,
   zero-write, zero-provider.
2. After registration, never re-read the owner stream entry or `pulse_route:{psid}` (trim/TTL
   bound). The durable snapshot is the only authority — this is what makes the three triggers
   order-independent.
3. Digest input needs an explicit domain/version prefix (not interchangeable with other digests).
4. Do NOT reuse `ActivationProducer` — `producer.py:102-108` performs the ingress decision marker
   and `guarded_xack`; owner RELEASE_CONTROL ACK belongs solely to the release terminal Lua.
5. Pass full canonical `FrozenWindowJobIdentity` bytes to `JobQueueStore.enqueue` (semantic fields
   plus `job_id`/`semantic_payload_hash`/`audit`), not the candidate-only semantic preimage.
6. `AuditTrace.created_at` must be a whole-second integer taken from the owner stream ID
   milliseconds — `model_dump()` yields a float, which integer-only CanonicalJSON rejects.
7. Step 5 uses the EXISTING reverse-injection seam: `worker/main.py` keeps only the generic
   `c2c_activation_bootstrap` protocol (L468-476) and `c2c_act_entrypoint.install_c2c_activation()`
   injects into it. `worker.main` must never import the concrete module (precedent: the B3
   `applied_store_factory` seam). Bundle construction and consumer ctor/prepare both belong inside
   the root cleanup `try/finally`.
8. The final same-SHA trusted-PTT live cutover is **Q3 full seal** — Master convenes DA; this
   session must not declare the live pass alone.

## Live environment (tester-measured, ready)

Three services health 200 from this worktree's CWD; audio loopback (Multi-Output + BlackHole)
waveform-confirmed; room `room-req-a7cb` / realtime entered with PTT present.
