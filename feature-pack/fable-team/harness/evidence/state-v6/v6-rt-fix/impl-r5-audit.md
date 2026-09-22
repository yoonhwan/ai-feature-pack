# STEP 0 — PRE-CODE AUDIT (residual R5): source_lang / ev.lang consumers

> Contract R5: removing `source_lang` from **routing** (INV-2/C3) must NOT starve legitimate
> display/translation consumers. Classify every read: **KEEP** (display/translation/telemetry) vs
> **SEVER** (solo panel-routing dependence). Only the routing dependence is cut.

## FE — `clients/web/src/domains/realtime/`

| # | Location | Read | Purpose | Verdict |
|---|----------|------|---------|---------|
| 1 | `use-realtime-solo-v5.ts:493` | `side: sideForLang(ev.lang) ?? fallbackSide` | **SOLO panel routing** — side derived from BE lang | **SEVER (INV-2/INV-6)** |
| 2 | `use-realtime-solo-v5.ts:250-258` `sideForLang()` | maps `ev.lang`→side | routing helper, **solo-only** (this is the solo hook) | **DELETE** (only consumer is #1; not MR) |
| 3 | `use-realtime-solo-v5.ts:494` | `lang: ev.lang ?? activeLangs.source` | segCtx.lang = segment DISPLAY lang | KEEP (display) |
| 4 | `use-realtime-solo-v5.ts:481,504` | rtLog `lang: ev.lang` | telemetry | KEEP |
| 5 | `use-realtime-solo-v5.ts:240-244` `langsForSide()` | press-side source/target langs for `buildParams` + segCtx.lang fallback | press-time lang CONFIG (not event routing) | KEEP |
| 6 | `v5-segment-reducer.ts:103,109` | `current?.lang ?? ctx?.lang` (diff lang, segment lang) | DISPLAY | KEEP |
| 7 | `v5-segment-reducer.ts:53-54,122-123` | translate.result `p.lang` / `event.lang` | translation attach keys | KEEP (translation) |
| 8 | `v5-transcripts.ts:109`, `v5-timeline.ts:37` | `seg.lang ?? sourceLang` | bubble/timeline DISPLAY lang | KEEP |
| 9 | `v5-session-client.ts:116,154`, `mr-compat-chunk-form.ts:36`, `use-notes.ts`, `use-edit-correction.ts` | `source_lang` in POST bodies | transport (STT source config) | KEEP |
| 10 | `use-realtime-stt.ts:*` (V4/compat/MR hook) | `data.source_lang` display + `session→side` map | **different hook** (not solo-v5); MR uses own session→side map, not `sideForLang` | KEEP (out of solo scope) |
| 11 | `use-realtime-station-lifecycle.ts:220,227` | guest lang / language_pool | MR station wiring | KEEP (MR) |

**Net FE severance:** exactly ONE routing read (#1) + its now-dead helper (#2). Everything else is
display/translation/telemetry and is preserved. `source_lang` continues to arrive on every event
(worker keeps stamping `lang: source_lang`) and drives display (#3,#6,#8) — INV-2 display contract intact.

## Worker — `worker/`

| Location | Read | Purpose | Verdict |
|----------|------|---------|---------|
| `pulse_consumer.py:852-854` | `source_lang` required (raise if missing) | STT source + #0 RULE gate | KEEP |
| `pulse_consumer.py:1034,1151,1310,1327,...` | `source_lang` into graph state + `stt.translated`/`utterance.released`/room_snapshot payloads | STT/translation/display carrier | KEEP |
| `event_mapper.py:127,305,364,460` | `lang: source_lang` on segment.partial/confirmed/polish payloads | **display/i18n contract** (FE reads for display) | KEEP (this is INV-2's "present on every seat-bearing event") |
| `translate_raw.py`, `polish.py`, `segment_commit.py`, glossary | `source_lang` for translate/polish/term | translation | KEEP |

**Net worker severance:** NONE. The worker never routes panels on `source_lang` (routing is FE-side).
It only must keep EMITTING `source_lang` (`lang` field) so display/translation keep working — no change
needed to preserve that; INV-1's utterance_id stamp is ADDITIVE and does not touch the `lang` field.

## Conclusion
Routing dependence on `source_lang`/`ev.lang` exists at exactly ONE site (FE `use-realtime-solo-v5.ts:493`).
Severing it (+ deleting the solo-only `sideForLang`) satisfies INV-2/C3 without starving any
display/translation consumer. All other reads are preserved verbatim.
