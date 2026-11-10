# V6 RT-Solo BTS Baseline — 2026-07-03 18:57

**Command**: `BYZ_BTS_ENGINE=say PYTHONPATH=.:tests/e2e .venv/bin/python tests/e2e/v6_raw_first_solo_bts.py`

**Exit Code**: 1 (FAIL)

**Harness**: Executed successfully (runner completed, exit=1 indicates test assertion failure, not precondition abort)

---

## STEP 1: Pre-Execution State

| Item | Value |
|------|-------|
| CDP connectivity | ✓ Chrome/149.0.7827.201 |
| Open realtime tabs | 1 |
| Gateway log baseline | 46,727,347 lines |
| Worker log baseline | 6,524 lines |

---

## STEP 2: Execution Summary

- **Scenario**: `v6_raw_first_solo_lane_a_4stage`
- **Engine**: `say` (tts-say, trusted _real_click)
- **V6 Raw-First Feature**: OFF (v6_raw_first=0)
- **Test Result**: `pass=false`
- **Evidence Directory**: `.omo/ulw-loop/evidence/v6-raw-first-solo-bts/20260703-185710/`

### PTT Speech Log (5 utterances as designed)

```
[realtime_multi_e2e] ptt_raw utterance=1/5 ts=1783072648.401 lang=ko engine=say voice=Yuna text='안녕하세요, 오늘 날씨가 정말 좋네요.'
[realtime_multi_e2e] ptt_raw_done utterance=1/5 ts=1783072652.335 lang=ko engine=say

[realtime_multi_e2e] ptt_raw utterance=2/5 ts=1783072652.490 lang=ko engine=say voice=Yuna text='이번 분기 실적은 목표를 초과 달성했습니다.'
[realtime_multi_e2e] ptt_raw_done utterance=2/5 ts=1783072656.751 lang=ko engine=say

[realtime_multi_e2e] ptt_raw utterance=3/5 ts=1783072656.902 lang=ko engine=say voice=Yuna text='다음 회의는 금요일 오후 세 시로 잡겠습니다.'
[realtime_multi_e2e] ptt_raw_done utterance=3/5 ts=1783072660.746 lang=ko engine=say

[realtime_multi_e2e] ptt_raw utterance=4/5 ts=1783072660.901 lang=ko engine=say voice=Yuna text='프로젝트 일정은 예정대로 진행되고 있어요.'
[realtime_multi_e2e] ptt_raw_done utterance=4/5 ts=1783072664.631 lang=ko engine=say

[realtime_multi_e2e] ptt_raw utterance=5/5 ts=1783072664.786 lang=ko engine=say voice=Yuna text='질문이 있으면 언제든지 말씀해 주세요.'
[realtime_multi_e2e] ptt_raw_done utterance=5/5 ts=1783072668.252 lang=ko engine=say
```

---

## STEP 3: RAW EVIDENCE — Multi-PTT Accumulation (Worker Log)

### Evidence Chain: Each PTT text appends to previous residual, NOT creating new segments

**PTT 1 (chunk_seq=26)**
```
[PULSE-CONSUMER] 11e515a9-e634-463b-a66f-96d105092e6e cross_chunk_load pulse_session_id=v5_e862c7cb9d77449bbd5b20389fce91a7 previous_text_len=0 prev_residual_len=0 prev_residual_preview=''
[PULSE:STT] 11e515a9-e634-463b-a66f-96d105092e6e text=안녕하세요? 오늘 날씨가 정말 좋습니다.... provider=groq
[v5.assemble] phase=new_segment residual_len=21 text_preview="안녕하세요 오늘 날씨가 정말 좋습니다."
```

**PTT 2 (chunk_seq=27) — Accumulation Starts**
```
[PULSE-CONSUMER] d9ef0686-07d6-4f5b-8bba-c2c2b8b30da0 cross_chunk_load prev_residual_len=21 prev_residual_preview='안녕하세요 오늘 날씨가 정말 좋습니다.'
[PULSE:STT] d9ef0686-07d6-4f5b-8bba-c2c2b8b30da0 text=좋네요. 이번 분기 실제... provider=groq
[v5.assemble] phase=residual_carry residual_len=34 text_preview="안녕하세요 오늘 날씨가 정말 좋습니다. 좋네요 이번 분기 실제"
↑ PROBLEM: new UTT2 text appended to prev residual, NOT issued new segment_id
```

**PTT 3 (chunk_seq=28) — Accumulation Continues**
```
[PULSE-CONSUMER] 58a97098-2cd7-43bc-a212-a68f1a26dc14 cross_chunk_load prev_residual_len=34 prev_residual_preview='안녕하세요 오늘 날씨가 정말 좋습니다. 좋네요 이번 분기 실제'
[PULSE:STT] 58a97098-2cd7-43bc-a212-a68f1a26dc14 text=적은 목표를 초과 달성했습니다.... provider=groq
[v5.assemble] phase=residual_carry residual_len=52 text_preview="안녕하세요 오늘 날씨가 정말 좋습니다. 좋네요 이번 분기 실제 적은 목표를 초과 달성했습니다."
↑ PROBLEM: UTT3 appended to UTT2+UTT1, residual growing monotonically
```

**PTT 4 (chunk_seq=29) — Accumulation Continues**
```
[PULSE-CONSUMER] bac9f89e-d0b5-4270-a214-bfcb11b81b7b cross_chunk_load prev_residual_len=52 prev_residual_preview='안녕하세요 오늘 날씨가 정말 좋습니다. 좋네요 이번 분기 실제 적은 목표'
[PULSE:STT] bac9f89e-d0b5-4270-a214-bfcb11b81b7b text=다음 회의는 금요일 오후... provider=groq
[v5.assemble] phase=residual_carry residual_len=66 text_preview="안녕하세요 오늘 날씨가 정말 좋습니다. 좋네요 이번 분기 실제 적은 목표를 초과 달성했습니다. 다음 회의는 금요일 오후"
↑ PROBLEM: Monotonic accumulation — segment never closes, grows with each chunk
```

---

## STEP 3: Raw Evidence — DOM Observation (Browser Console)

### Before Test
```json
"dom_before": {
  "original_count": 1,
  "translation_count": 1,
  "last_original": "ko사고가 언제 어떤 작업을 하다가 발생했는지발생했는지와 와안전 안전교육교육, 보호장비보호 장비 지급 여부를 먼저 확인하겠습니다.",
  "last_translation": "enI will first check when and during what task the accident occurred, as well as whether safety training and protective equipment were provided."
}
```

### After 5 PTT presses
```json
"dom_after": {
  "original_count": 1,
  "translation_count": 1,
  "last_original": "ko사고가 언제 어떤 작업을 하다가 발생했는지발생했는지와 와안전 안전교육교육, 보호장비보호 장비 지급 여부를 먼저 확인하겠습니다.안녕하세요 오늘 날씨가 정말 좋습니다. 좋네요 이번 분기 실제 적은 목표를 초과 달성했습니다. 다음 회의는 금요일 오후 3시로 잡겠습니다.",
  "last_translation": "enI will first check when and during what task the accident occurred, as well as whether safety training and protective equipment were provided. Hello, the weather is really nice today. Great. We exceeded our actual target for this quarter. The next meeting will be scheduled for Friday at 3 PM. The project schedule is proceeding as planned. Please feel free to ask any questions you may have."
}
```

**OBSERVATION**: 
- `original_count` remains 1 (no new bubbles created)
- `last_original` shows PREVIOUS stale text + all 5 new utterances concatenated into ONE bubble
- dom_original_delta=0, dom_translation_delta=0 (no new DOM nodes added — reuse/append pattern)
- This indicates **LEFT→RIGHT ROUTING FAILURE** (new utterances appended to existing bubble instead of new bubbles)

---

## STEP 3: Console Markers (Browser Events)

**bubble_rendered markers**: 14 found in console

**stage_paint markers**: 52 total
- partial: 10
- preview: 14
- polished: 14
- final: 14

**sentence_press_count**: 5 (runner completed all 5 PTT presses as designed)

---

## Symptom Summary

Three critical bugs reproduced in baseline:

1. **MULTI-PTT ACCUMULATION** (worker log): Each new PTT's text appended to previous residual instead of starting new segment. Residual grew monotonically: 21→34→52→66+ chars. No new `issued_segment_id=true`, only `residual_carry` phase.

2. **LEFT→RIGHT ROUTING FAILURE** (DOM): New utterances did not create new bubbles. All 5 utterances concatenated into the existing bubble. `dom_original_delta=0` (no new segment elements).

3. **RAW+POLISH CONCAT** (not yet visible in this baseline, but infrastructure setup confirms architecture set for the concat bug): Worker text_preview shows raw STT text mixed with processing fragments, not clean polished output.

---

## Test Failure Reason

`pass=false` because:
- `dom_original_delta=0` expected 5+ (one per new utterance) → **routing bug confirmed**
- `stage_paint_count=52` and distribution shows all stages got painted, but only for same segment (no new segment_ids issued) → **accumulation bug confirmed**

---

## Files

- Gateway tail: `.omo/ulw-loop/evidence/v6-raw-first-solo-bts/20260703-185710/gateway-tail.log` (1.2 MB)
- Worker tail: `.omo/ulw-loop/evidence/v6-raw-first-solo-bts/20260703-185710/worker-tail.log` (85 KB)
- Console: `.omo/ulw-loop/evidence/v6-raw-first-solo-bts/20260703-185710/browser-console.jsonl` (95 KB)

