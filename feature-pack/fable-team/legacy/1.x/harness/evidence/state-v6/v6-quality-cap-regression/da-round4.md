# DA Round 4 — v6-quality-cap-regression (cap hotfix rev5 simplified)

reviewed: rev5

**codex session-id**: 019f544b-0e54-7d12-ad60-e0078ae2b319  
**tokens used**: 351,860 (cumulative)  
**date**: 2026-07-12

---

## Verdict

**APPROVED w/COND** (조건 2건 — 랜딩 블로커 아님)

---

## codex VERDICT (원문)

```
VERDICT: APPROVE w/COND

- Cap selection is structurally aligned with translate.py through the shared detector;
  mixed presses conservatively receive 25s, while non-double-neg execution remains
  byte-for-byte on the 7s path.
- Rescue skip is consistent: a 25s QUALITY timeout terminates without an identical
  retry or reversed translation. The empty target slot/finalizing behavior is accepted
  as explicitly deferred scope.
- A 25s default is plausible emergency headroom, but "3x >7s" is not latency evidence.
  Require post-landing telemetry for QUALITY completion latency and timeout rate.
- Sequential HOL remains the condition: normal presses queued behind one QUALITY
  request can wait up to 25s despite retaining their own 7s cap. Monitor queue
  depth/next-press latency and rollback or detach if operational thresholds regress.
```

---

## DA Driver 종합

### 통과 항목
- **L1 cap 분기 정합**: SSOT 공유 감지 → translate.py와 결정적 동일 판정. 비이중부정 7s 경로 byte-for-byte 무변경 ✅
- **L2 rescue skip 일관성**: 25s QUALITY 타임아웃 → 동일 pro 재시도 없음, 반전 번역 없음. 빈 번역슬롯+finalizing은 명시 백로그(스코프 내 수용) ✅
- **FE 고착 백로그 강등**: 오빠 스코프 결정 수용, 별도 이슈 ✅

### 조건 2건 (랜딩 블로커 아님 — 운영 모니터링)

**COND-1 (사후 텔레메트리)**:  
25s 기본값은 합리적 비상 여유이나 "3배>7s"는 레이턴시 실증이 아님. **랜딩 후** QUALITY 완료 레이턴시 분포+타임아웃 발생률 수집 필수. 과다 초과 시 env 조정 또는 detach 증분 승격.

**COND-2 (HOL 운영 모니터링)**:  
일반 press가 QUALITY press 뒤에 큐잉되면 최대 25s 대기(7s cap 유지해도). 큐 깊이+후속 press 레이턴시 모니터링 + 운영 임계 회귀 시 rollback 또는 detach 계획 보유.

---

## Round 이력

| Round | Rev | Verdict |
|-------|-----|---------|
| r1 | rev1 | CHANGES_REQUESTED (CR-cap1/2/3) |
| r2 | rev2 | CHANGES_REQUESTED (CR-cap4/5) |
| r3 | rev3 | CHANGES_REQUESTED (CR-cap6/5b) |
| **r4** | **rev5** | **APPROVED w/COND ✅** |

VERDICT

**APPROVED w/COND**
