# DA Round 2 — fulltext polish pipeline rev3

reviewed: v3 (`.claude/plans/v6-fulltext-polish-pipeline-review.md` ## rev3, line 229+)
timestamp: 2026-07-10
codex-session-id: 019f49a4-33a7-70c1-a1a8-ca9bdb3b6de4
model: gpt-5.6-sol (headroom default, reasoning xhigh)
tokens: 9,532

## VERDICT: REJECT

## 판정 불릿 (codex 원문)

- **R1 RESOLVED**: allowlist, reducer case, MR listener, cycle_key normalization, dedupById, overlay ordering — 3-point wiring fully specified.
- **R2/point6-A CRITICAL REMAIN**: Redis Lua is isolated but not rollback-transactional. If ZREM succeeds and ZADD errors, the removal persists (entry lost). GETDEL is unnecessary/inapplicable to ZSET, but the script must guarantee ZADD succeeds before removing the old member (ZADD-first pattern).
- **R3 INCOMPLETE**: Adaptive max_tokens fixes the 512 limit, but rev3 never removes or revises the INV-F2d 6-second cap (still present from rev2). "Local/no-network" Gemini count_tokens also needs explicit API validation note.
- **R6 + D5 RESOLVED** — provided SET NX executes before evaluating or scheduling either task; make that ordering explicit in the design text.
- **point6-C NOT FULLY RESOLVED**: `STRING(JSON)` description implies a blob but does not explicitly mandate `SET` or prohibit `APPEND`. Design must specify `SET key payload EX 86400` (not APPEND).

## 수정 요구사항 (rev4 대상)

1. **R2 Lua 스크립트 순서 역전**: `ZREM`→`ZADD` 순서를 `ZADD`→`ZREM`(또는 ZADD first + 성공 확인 후 ZREM)으로 교체 — ZREM 성공/ZADD 실패 시 엔트리 소실 방지.
2. **R3 INV-F2d cap 개정**: rev3 §3에서 6s 고정 cap을 길이 비례 공식(`min(20, 6 + len/500)`)으로 교체하는 문안이 누락됨 — rev2 §R3 설계안을 rev3에 명시적으로 반영 또는 cap 제거 근거 명기.
3. **point6-C 명시**: `pulse_revision:{room}:{utterance_id}` 키 기록을 `SET key JSON EX 86400`으로 명시, APPEND 불가 이유 1줄 추가.
4. (권고) R6 SET NX 실행 순서: "결정점 직렬화 → SET NX → create_task" 순서를 설계 문안에 명시(현재는 암묵적).

## r1 → rev3 해소 현황 요약

| 이슈 | 상태 |
|------|------|
| R1 FE wiring 3지점 | ✅ RESOLVED |
| R2 Lua 원자화 | ❌ ZADD-after-ZREM 순서 버그 잔존 |
| R3 토큰 카운팅 clamp | ⚠️ max_tokens 개선되었으나 INV-F2d cap 미개정 |
| R6 press-end 직렬화 | ✅ RESOLVED (SET NX 순서 명시 필요) |
| D5 계약 분리 | ✅ RESOLVED |
| point6-A GETDEL | ✅ Lua로 대체 충족 (GETDEL 불필요) |
| point6-C APPEND/SET | ❌ SET 명시 누락 |

---

## DA r3 — rev4 보정 3건 재판정

reviewed: v4 (`.claude/plans/v6-fulltext-polish-pipeline-review.md` ## rev4, line 306+)
timestamp: 2026-07-10
codex-session-id: 019f49a7-e293-7621-8e18-5ffcaef0a960
model: gpt-5.6-sol (headroom default, reasoning xhigh)
tokens: 8,180

## VERDICT: APPROVED

## 판정 불릿 (codex 원문)

- **r2#2 RESOLVED**: ZADD-first preserves the old member if ZADD fails; a later ZREM failure leaves only a recoverable duplicate, not data loss.
- **r2#3 RESOLVED**: INV-F2d now has an authoritative adaptive 6–20s cap; count_tokens no longer relies on an unvalidated locality claim and has complete fallback behavior.
- **r2#5 RESOLVED**: SET with EX is explicitly mandatory, while APPEND is explicitly prohibited.
- **r2#4 RESOLVED**: §4 unambiguously mandates decision → SET NX → create_task and prohibits reversal.
- **Caveat**: duplicate cleanup remains desirable, but the existing FE preference rule (revised:true 우선) makes it non-critical.
