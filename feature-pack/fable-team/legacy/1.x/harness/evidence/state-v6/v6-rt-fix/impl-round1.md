# impl-round1 — worker atomic fix (WORKER_COMMIT_DONE)

**commit**: b2752f53 `[fix] worker pulse: per-press carry key + polish REPLACE (INV-3/4/1/5 atomic)`
**note**: impl-rt-01(opus)이 4파일 316줄 작성 후 HIL 정지구간에 커밋 전 사망(transcript 18:20 이후 무활동). orch가 self-verify 후 커밋 마무리(코드 무편집, 검증+커밋만).

## 변경 (4파일, atomic 단일커밋 per [T-atomicity])
- `worker/infrastructure/consumers/pulse_consumer.py` (+91/-) — INV-3 carry full per-press key, INV-5 solo terminal carry clear, T-abort TOMBSTONE, §V 로그
- `worker/graph/speech/pulse/nodes/assemble.py` (+22) — INV-4 polish REPLACE + [T-boundary]
- `worker/services/v5/event_mapper.py` (+45) — INV-1 utterance_id 전 이벤트 emit (additive)
- `tests/worker/unit/test_pulse_consumer_rt_regression.py` (신규 170줄) — 회귀 가드

## self-verify (orch, green)
- ruff clean (변경 4파일)
- 신규 회귀테스트 7/7 PASS
- 기존 pulse/consumer/v5 193/193 PASS (무회귀)

## 잔여 (미착수)
- INV-2/INV-6 FE routing 커밋 (seat 눌린버튼 앵커) — R5 감사(impl-r5-audit.md) 반영
- 라이브 BTS 검증 (worker 재기동 후 v6_raw_first_solo_bts.py)
- codex DA (019f2739 resume) on diff+BTS로그
