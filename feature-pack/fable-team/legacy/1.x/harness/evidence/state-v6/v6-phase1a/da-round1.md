# DA Review: V6 RT Original Lane (origloss) — Round 1

**reviewed: v1** (design file `.claude/plans/v6-origloss-iter1-design.md`)

**session-id: 019f28be-1343-7631-ad43-dff388eb4cff**

---

## VERDICT: CHANGES_REQUESTED

### Findings

1. **Design directionally sound**: `toBubble()` is the correct single edit point. Render component cannot safely reconstruct dropped non-diff segments; data layer aggregation is the only place where segment order is known. ✓

2. **Cycle coverage verified**:
   - No-diff cycle: `hasDiff=false` → `prevDiffs=[]` → `previousSourceText=undefined` (byte-identical to today). ✓
   - Single-segment diff: `forEach` 1 iter, `idx=0`, no boundary space → output identical. ✓
   - Mixed diff/non-diff (e.g., unit2 only): restores all segments in order. ✓

3. **No-regression claims confirmed**: 
   - `showPolishDiff` OFF uses `displayedOriginal=b.text` (independent of `previousText`). ✓
   - Translation lane uses `item.translations[]` from `mergeTranslations` (all segments, no `previousText` dependency). ✓
   - LST separate reducer/render, MR/Lecture/Note adapters never set `previousText`. ✓

4. **Critical design gap identified** ⚠️: The proposed `[{ kind: 'keep' as const, text }]` fallback for non-diff segments **must use trimmed text** (via `aggregateOrderedText` normalization), not raw `seg.text`. Reason:
   - `aggregateOrderedText(values.map(v => v.trim()).filter(Boolean))` normalizes segment boundary whitespace.
   - Raw `seg.text` may have leading/trailing spaces → space-keep token + raw segment text = double-space or mismatch vs `b.text` (line 99: `aggregateOrderedText(segments.map(item => item.text))`).
   - Example: segment `text=' unit '` → proposed `[{keep, ' unit '}]` + keep-space = `' unit  '` (double-space before next).

5. **Test coverage required**: Add/adjust jest cases for:
   - Mixed cycle (unit1/unit2-diff/split/unit4): all segments render, no doubling.
   - No-diff cycle: `previousSourceText=undefined`, render path unchanged.
   - Whitespace boundary: segment text with leading/trailing spaces → normalized keep tokens match `b.text`.
   - All-segments-diff multi-segment cycle.

---

## Recommendation

Revise the fix to normalize fallback keep tokens: use `visibleSegmentText(state, seg, lstEnabled)` result or raw `item.text` **after trim & filter** (matching `aggregateOrderedText` pipeline) instead of raw `seg.text`. Then update tests per item 5 above. Resubmit for round-2 DA verification.
