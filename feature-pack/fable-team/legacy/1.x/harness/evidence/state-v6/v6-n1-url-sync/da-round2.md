# DA Round 2: N1 URL Sync Design v2 — Codex Resume

**reviewed: v2**

**session_id**: 019f2d13-f309-7320-8fb4-29509161e141 (resume from r1)

---

## VERDICT: APPROVE

**R1 (hydration mismatch) — CLOSED**
- R1 is sound for the current route shape: `useSearchParams()` in `RealtimeStationV5` (`realtime-station-v5.tsx:111`) bails the client subtree to the nearest `<Suspense>` (`app/realtime/page.tsx:19`), so the lang labels (`realtime-station-v5.tsx:135`, `:138`) are not server-rendered and cannot mismatch.
- R1 hole to document: this depends on keeping that Suspense boundary above the `useSearchParams` consumer and not making the route dynamically server-render that subtree later.

**R2 (ttsVoice pre-catalog race) — APPROVED with trade-off documented**
- R2 is acceptable: invalid Supertonic voices self-heal (`gpu_supertonic.py:35`, `supertonic.py:69`); OpenAI also defaults invalid voice (`openai.py:48`, `:50`); Cartesia defaults non-UUID (`cartesia.py:14`, `:23`, `:67`).
- ElevenLabs invalid non-empty voice is visible failure, not silent (`elevenlabs.py:37`, `:92`, `:93`). Current code still shows localStorage-only at `use-tts.ts:43`, but `URL ?? localStorage` would use the same mount→ref→`buildParams` path (`use-realtime-solo-v5.ts:210`, `:287`).

---

## Design v2 Approved

- All 9 params ready for implementation (STT + 4 langs + 4 TTS)
- No hydration risk for client-only RT subtree
- Race condition pre-existing (localStorage same as URL)
- Code changes conform to "edit readStoredXxx only" constraint
- Unit + BTS increments in design §verification are ready
