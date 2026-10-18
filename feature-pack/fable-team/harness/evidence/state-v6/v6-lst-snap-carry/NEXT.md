# NEXT — activation-subgate ARCHITECT HOLD rework handoff (write-through by ft-lstsnap-impl#30, 2026-07-23, distill boundary per architect#25 ctx directive)

> Successor = ft-lstsnap-impl#31. Base HEAD `34f6c23d` + uncommitted working tree.
> COMMIT/PUSH FORBIDDEN until DA#2 diff seal. mbox comm standard:
> `~/.claude/skills/tmuxc/COMM-GUIDE.md`, helper `.fable-team/comm/mbox.sh`,
> me=ft-lstsnap-impl#31, architect=ft-lstsnap-architect#25, orch=FB_Master#87.
> On boot: Read this file fully, then mbox recv + report boot to Master AND architect.

## COMPLETED THIS SESSION (impl#30) — HOLD 1/4 + 2/4 of architect #501/#502/#503

### HOLD 1/4 producer — DONE, architect component-ACK received
- `worker/graph/speech/pulse/v6/activation_subgate/producer.py` REWRITTEN:
  - `produce_one(psid, *, window: FrozenWindowJobIdentity, source_stream, source_group,
    source_entry_id, purpose)` — caller-invented job_id param REMOVED; job_id comes
    from frozen identity only.
  - Flow: WatchedEnqueue.run -> (non-committed => NOT_COMMITTED, no ack, no marker)
    -> classify_enqueue_marker -> DecisionStore.register -> guarded_xack (real
    xack_eligibility path). REPLAY_CONVERGED when outcome != queue_as_active.
- `tests/worker/unit/test_v6_activation_producer_red.py` REWRITTEN (4 passed):
  actual produce_one calls over real XREADGROUP delivery (deliver_source) +
  prepare_real_freeze; order spy (pipeline EXEC vs xack) proves enqueue<ack + PEL
  drained; enqueue-failure => PEL=1/marker None/no ack; injected ConnectionError
  after enqueue-commit => redelivery REPLAY_CONVERGED IDEMPOTENT same generation,
  ready entries all same job_id+generation (sealed C1b re-notify law: IDEMPOTENT
  replay of queued job re-XADDs ready notification — assert identity not count),
  final PEL=0.
- **Architect caveat (#501 ACK)**: producer component approved, BUT HOLD4 integrated
  consumer/runtime E2E must prove actual delivery decoder/freezer feeds this
  producer to fully close blocker1.

### HOLD 2/4 provider — DONE incl. follow-up fence
- `worker/graph/speech/pulse/v6/activation_subgate/named_provider.py` REWRITTEN (124L):
  - Local HSETNX claim + infinite `_await_committed` poll REMOVED entirely.
  - `NamedProviderPort` Protocol: EXTERNAL port owns durable
    `invoke_or_replay(operation_id=...)` commit. `NamedProviderReply(operation_id,
    results: tuple, replayed)`.
  - Adapter validates reply: foreign operation_id / cardinality != 1 / non-bytes
    result => `ProviderProvenanceError` (fail-closed).
  - In-memory single-flight `_inflight[op_id] = ((psid,job_id,attempt_ordinal,
    receipt_digest), task)`; foreign caller tuple on live entry => raises BEFORE
    await; `_pop_if_owner` pops only if entry still owns that exact task.
- `tests/worker/unit/test_v6_activation_provider_red.py` REWRITTEN (6 passed):
  reply-loss = port raises AFTER remote commit; retry same op_id => byte-identical
  replay, port.work stays 1; crash leaves ZERO v6_activation_provider_result* keys +
  retry under wait_for(1.0); 4x concurrent => work=1; foreign op_id reply /
  empty/double/str results => ProviderProvenanceError; gated-port concurrent foreign
  job_id => ProviderProvenanceError before await.

### Gates run this session
- pytest producer 4 passed + provider 6 passed; ruff clean on all touched files.
- NOT yet re-run: full activation suite / regression 560 / real-Redis 73 /
  basedpyright / compileall — successor must run full gates after HOLD3+4.

## REMAINING — HOLD 3/4 + 4/4 (from architect #501/#502/#503, NOT STARTED)

### HOLD 3/4 resolver/runtime (architect text, verbatim intent)
Current `release_resolver.py` only checks run state + locator len/disposition and
returns published/sealed/acked=True with zero effects. Fix: full authority chain —
release intent -> binding by exact 6-tuple digest -> payload/run -> locator ->
broker -> C2b decision, decode envelope, cross-check job/hash/epoch/op/ordinal/
receipt/source_raw; return typed projection/drop/pending/fatal only; DROP only
dual-empty (bound frozen source AND current release source both empty, seal-only).
Runtime `validate_active` must byte-compare ALL 19 expected fields (not count+state)
— expected values come from HELM record contract (fixtures HELM_FIELDS +
helm_record_kwargs). REMOVE `v6_activation_release_expired` marker entirely —
expiry authority is EXISTING ReleaseIntent status/EXPIRED + typed ACK only
(resolver must read intent JSON `status` field via `_intent_key(psid)` =
`v6_release_intent:{psid}`, see release_intent_store.py).

Key surfaces studied (paths for successor):
- resolver: activation_subgate/release_resolver.py (69L, has _EXPIRED_MARK_PREFIX
  to remove; deadline_red + resolver_red tests reference mark_expired/
  EXPIRED_TERMINAL — those tests must be REWORKED to intent-status authority).
- runtime: activation_subgate/runtime.py — validate_active count+state only (fix);
  expire_pending_release already routes ReleaseIntentStore.expire (keep, but drop
  resolver.mark_expired call once marker removed).
- intent: release_intent_store.py — INTENT_KEY_PREFIX="v6_release_intent:",
  payload JSON has status pending/sealed/expired + identity 6-tuple + deadline_ts;
  ReleaseIntentStore.expire(psid, stream=, group=) => TerminalOutcome(transitioned,
  owner_entry_id, ack: AckOutcome).
- binding: binding_store.py release_identity_digest(6-tuple) + release_binding_key;
  binding record 22 fields incl job_id/authority_epoch/window_rev/
  semantic_payload_hash/source_hash.
- composite Lua: decision_locator_lua.py — locator 9 fields (schema_version,
  binding_digest, job_id, operation_id, attempt_ordinal, receipt_digest,
  decision_digest, terminal_class, disposition); decision key
  `v6_c2b_decision:{tag}:{op_id}` 5 fields (operation_id, job_id, attempt_ordinal,
  receipt_digest, envelope).
- envelope: c2b/decision_codec.py decode_envelope(bytes) -> ProviderResultEnvelope
  (disposition SUCCESS/RETRYABLE/FATAL, decision AcceptCandidateInput/
  IdentityRefineInput/DropProvenInput/FatalContractInput with source_raw/
  refined_raw/projection). Cross-check source_raw against bound frozen source.
- broker record: `v6_c2a_r0_provider_broker:{tag}:{op_id}` 14 fields COMMITTED.
- fixtures: tests/worker/unit/_v6_activation_fixtures.py (seed_binding),
  _v6_c2b_claimed.py (claimed_receipt, authorized_broker_invocation),
  _v6_c2b_fixtures.py (accept/identity/drop/fatal decisions),
  _v6_c2a_r1_fixtures.py (make_identity, READY_GROUP).

### HOLD 4/4 missing surfaces (verbatim from NEXT/#503)
(i) RED-first integrated `activation_subgate/consumer.py`: claim -> strict decode ->
binding CAS -> provider-start -> broker -> named provider replay -> composite
commit -> exactly ONE C2b terminal router; FrozenJobConsumer's direct terminal
branch must NOT run. (ii) ACTIVE-gated `start_if_active` runtime E2E: pre-ACTIVE
imports/groups/tasks/provider=0, post-ACTIVE producer+consumer startup — and per
architect #501 ACK caveat, prove actual delivery decode/freeze feeds
ActivationProducer (closes blocker1). (iii) approved NARROW release_ready.py
resolver injection/cutover RED+impl: pre-boundary byte-equivalent legacy; active
NORMAL_READY no inline provider; PENDING preserves owner; READY projection then
existing publish/seal; fatal/missing zero effects until deadline.
(release_ready.py touch ONLY on this explicit architect RED instruction — narrow
seam approved in #503(iii).)

### Gates after all fixes (before DA#2)
activation tests + regression `-k "v6_c1 or v6_c2a or v6_c2b or rollout_fence or
v6_activation"` (was 560 passed) + real-Redis integration c2a_r0 73 + ruff +
compileall + basedpyright 0 errors + no-excuse 0 + diff-check + all files <180L.
`test_pulse_audio_duration.py` collection error pre-existing — `--ignore` it.
Report waves via mbox to architect#25, STOP for DA#2 diff seal.

## Hard constraints (unchanged)
- NO-TOUCH: c2a_r0/**, c2b/**, c1c_ta/**, worker/c1c_ta_entrypoint.py
  (_SEALED=True), c2a_r0/activation.py (HOLD NotImplementedError), sealed C1
  queue/lifecycle Lua, D1/D2, release intent/barrier/terminal, release_polish.py,
  release_ready.py (seam only per approved #503(iii) narrow instruction).
- dirty4 무접촉: .claude/rules/troubleshoot.md, .serena/project.yml, .gstack/,
  design/C2A-R0-ROUND7-* + design/LOOMPACK-CHERRYPICK-*. NO stash/reset.
  NO commit/push.
- .venv: fakeredis[lua] (lupa) installed.

## C2b/C2a context (untouched, sealed — from impl#29 handoff)
1. C2b COMPLETE + DA sealed (c2b/ 7 files + tests). DO NOT touch.
2. C2c DEFERRED (architect ruling).
3. activation-subgate waves 1-8 base contracts (ACT-GREEN #501/#502): HELM 19f
   exact on `v6_activation_helm:{v6_pulse_requests}`; binding 22f; locator 9f;
   composite 8 KEYS/15 ARGV/7 tokens; resolver closed taxonomy; runtime restart
   gate. Wave2/Wave4 corrections applied. release_ready seam NOT yet injected.
