# DA(ft-lstsnap-da-fable#20) HANDOFF — 2026-07-21 distill (ctx 568k gate)

## Role
V6 DA(적대검증) boundary-seal gate. Final DA verdicts are issued by da-fable#20 lineage ONLY (HELM ruling; #21 output is not gate evidence).

## SEALED — do not reopen
### C1b DURABLE-COMPLETE SEAL (5 SHAs, all independently DA-verified)
- F6 claim/snapshot-classifier: 040be0db (12/12 fake==real, abort-on-mismatch injector)
- FAMILY-2 FINISH common active-slot pre-write gate: 103de88f
- C1b-R reconcile recovery: bddc46c2 + b4bf8974 (authoritative real-Redis ACL command-boundary XADD fault artifact, 3 runners all_assertions=PASSED)
- FAMILY-1 payload four-leaf raw-presence classifier: 48d23487 + d5244fc3 (RED-first independently re-proven 26->68)
- NORMALIZATION-1 stale decide_* oracle removal: bc761d2a (all 5 Lua r-string sha1 byte-identical to sealed baseline)
- SEAL-INTEGRITY: HEAD must remain bc761d2a lineage. 05059843 = REJECTED orphan (re-introduced FINISH_LUA text change; FINISH_LUA must stay sha1 b9e2d0365cefc1720562f7acf1b4a8e4a561785e). Commit authority single-owner: impl#22.
### Gate D DESIGN SEAL (da-fable#20 verdict, appended to .fable-team/state/v6-lst-snap-carry/design/D-AUTH-REV1.md)
- Q1-Q5 APPROVED + 3 binding pins: (P1) exact D1Request + strict no-coercion reconstruction (model_validate on primitive dumps, coercion OFF) before any field/hash byte; (P2) d-split-v1 edge RED: EOS terminal run, consecutive "?!", "3.14" no-split, protected-anchor boundary; (P3) C1a-style AST-transitive + runtime rollout/import fence, incl consumed RefineDecision type import side-effect 0.
- DA-1 amendment INCLUDED: DROP_PROVEN requires window.pending_seam is None (zero-offset seam also rejected); FATAL_CONTRACT carries seam, seam stays IN C1a identity (job_id/source_hash), split ignores it by explicit rule, always UPSTREAM_FATAL side-effects 0; ACCEPT/identity seam offsets <= len(source_raw); all reject paths before first hash byte.
- FatalContractInput routes to retained UPSTREAM_FATAL (closed 6-input transition table in authority file). D1 closed set = ROWS_COMPLETE/ROWS_WITH_RESIDUAL/RESIDUAL_ONLY/EMPTY_PROVEN/UPSTREAM_FATAL.

## NEXT DA WORK (successor)
- impl#22 is fixing architect REJECT B1-B5 on Gate D impl (SHA 0bef3dbd REJECTED — not evidence). When fix SHA lands: DA implementation seal in order D1 boundary/ownership -> D2 conservation/fail-loud, against the sealed design + 3 pins + DA-1. Determinism gate: fresh-process driver under >=2 PYTHONHASHSEED values, canonical bytes + IDs byte-for-byte. Tier-B: fake-only sufficient (no Redis) unless a new fake-real divergence risk appears.

## HOLD (owner/HELM gates — never self-release)
D impl activation, C2, Redis/ACK, D2 impl, translate/type1/commit/publish/seal, release bridge retirement, consumer/provider, main merge, main push.

## DA METHOD (hard-won lessons — apply always)
1. NEVER trust prose/green/checker-relay: read source, run pytest yourself, hash Lua r-string constants (this caught FINISH_LUA byte changes twice), re-run RED against pre-fix (git checkout <pre>^ -- files) yourself.
2. Verify MECHANISM of tests (why a RED fails), not just pass/fail counts.
3. Safety scan first on any runner/probe: FLUSHDB/passwordless ACL/endpoint guards (missed once — never again).
4. Comms: mbox.sh send/recv with [me->to] prefix; me=ft-lstsnap-da-fable#20. Roster: V6_HELM#22(orch), ft-lstsnap-architect#22, ft-lstsnap-checker-luna#1, ft-lstsnap-impl#22, FB_Master#84, FB_Tester#20.
5. Rule 6: >2 consolidated REJECT or direction dispute -> HELM/PM HIL, no internal loops. Boundary seal per gate, not per micro-fix.
