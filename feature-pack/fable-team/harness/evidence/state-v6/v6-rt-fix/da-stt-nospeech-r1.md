# DA Gate — v6 STT No-Speech Root Fix

reviewed: v1 (`.claude/plans/v6-stt-error-root-fix.md`)
date: 2026-07-07
codex-session-id: 019f3b42-1325-7d82-93ea-e30cdf53da18
codex-tokens: 99,016
round: 1

---

## VERDICT: APPROVE

- `worker/graph/speech/pulse/nodes/stt.py:375-392` is the only runtime consumer of `transcribe_first_usable`, and `PulseState.stt_text` is still a `str` (`worker/graph/speech/pulse/state.py:63`). If `NO_SPEECH` is handled entirely inside `stt.py` before building the return dict, it will not leak into assemble/carry or corrupt confirmed text. Do not make the sentinel a string literal; keep it as a private object-like sentinel.

- Skipping `publish_node_error` for definitive no-speech should not starve the frontend. Error events are observability-only (`worker/graph/speech/pulse/nodes/v5_error.py:15-21`), the graph still runs `stt -> assemble` unconditionally (`worker/graph/speech/pulse/graph.py:118-128`), and `pulse_consumer` explicitly depends on `stt.complete` as the terminal fetch-closer (`worker/infrastructure/consumers/pulse_consumer.py:2146-2152`).

- The 8s safety pin is defensible as a conservative false-negative guard, not as a speech detector. It is well above the measured empty-tail distribution in `.claude/plans/v6-stt-error-root-fix.md:63-65`, and it matches the existing long-form-silence boundary already set to `8.0` in `worker/graph/speech/pulse/nodes/stt_fallback.py:104-120`.

- This does not violate the no-silent-fallback rule. A provider returning `text_len=0` is a successful "no speech" outcome, not an infrastructure failure. Real failure paths still surface through `stt_fallback.py:229-234` and `stt.py:463-475`; the fix only stops promoting a genuine no-speech signal into fake `stt_timeout` / `stt_hallucination`.

- Regression risk to `commit_carry` / INV-4 is low if the node contract stays `{"stt_text": "", "status": "completed"}`. `assemble`, `_after_assemble`, and `_commit_carry` already branch on empty `stt_text`, `prev_residual`, `assembled_text`, and `is_final` (`assemble.py:92-108`, `graph.py:49-59`, `segment_commit.py:126-176`). The must-have proof is to run the plan's cases #1, #3, and #5 plus one consumer-level check that `stt.complete` still emits on the no-speech path.

---

## 비고

- 최초 실행(session 019f3b39) xhigh 9분 hang → kill 후 재시도(session 019f3b42) 완료.
- 재시도 run 시 원본 배경 실행도 동시 완료되어 동일 APPROVE 판정 2회 확인.
