reviewed: v6-rt-stress-fix-design.md

**VERDICT: APPROVE**

(Note: Codex resume+one-shot both timed out (120s) — verdict based on architect-level code review of design + actual code lines)

---

• **BUG 2 root (langsForSide null leak) VERIFIED CORRECT** — use-realtime-solo-v5.ts:262 uses TRANSIENT activeSideRef, langsForSide(null).source='ko' (line 246, sourceRef.current default), activeSideRef nulled at release. Fix anchors to durable lastPressedSideRef — matches routing pattern (lines 485-489 already durable). Line 275 ttsEnabled also needs same fix. No side effects on TTS/profile/target.

• **BUG 3 root (silence_flush mid-press carry-clear) VERIFIED CORRECT** — energy-vad-handlers.ts:81 emits is_final=true, flushReason='silence_flush' on EVERY intra-press VAD gap. pulse_consumer.py:1650-1664 INV-5 unconditionally deletes pulse_prev/trans/residual on terminal_is_final (which currently includes silence_flush for solo). First sentence lost, seam-dedup defeated. Fix press_end_final=terminal_is_final && flush_reason!="silence_flush" is correct boundary.

• **FIX 3 site scope CORRECT** — apply press_end_final ONLY at carry-clear (:1033 accum_ts, :1650/:1692/:1695 carry persistence). Leave output_is_final/TTS (:1830/1848/1927/1958) and released (:2100) unchanged (per-sentence rendering/dispatch not the bug). Broadcasting mode gate preserved at :874.

• **No regression on Finding-1 routing** — FIX 2 routing block (:485-494) untouched, already durable; FIX 3 doesn't touch routing. Independent fixes.

• **INV-3 prerequisite satisfied** — no :ppt: stripping found in current code (grep confirms fix b2752f53 completed carry keying on full id). press-end_final clears only current press's carry, no press-N→N+1 bleed risk.

• **Empty flush_reason (legacy compat) handled correctly** — `flush_reason != "silence_flush"` is True when field empty/falsy, counts as press-end. All carry-relevant sites covered.

---

Session: codex hang (resume 019f2739-f654-77a1-9315-c7856fbcbdab timeout, one-shot fallback also timeout)
Path: one-shot fallback + code review (codex unavailable)
