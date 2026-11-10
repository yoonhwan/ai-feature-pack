## 문제해결 표준 체인 (2026-07-28 — 오빠 지시 박제)

**checker → 오케(Master) → architect → (DA) → 오케(Master) → impl**

| 단계 | 주체 | 하는 일 |
|------|------|---------|
| 1 | checker | 실측·정리. **사실만, 판정 안 붙임** |
| 2 | **오케(Master)** | checker 정리 + 의심 방향을 얹어 architect에 전달 — **관찰이지 판정이 아님을 명시** |
| 3 | architect | 원인 규명·설계 판정. **DA 소환 여부도 architect가 정한다** |
| 4 | DA | architect가 부를 때만 움직이고 **architect에 회신** |
| 5 | **오케(Master)** | 최종본을 impl에 라우팅 |
| 6 | impl | 구현 |

- **오케(Master)가 하지 않는 것 셋**: 원인 규명 / 수정 방향·위치 지정 / DA 직접 소환(architect·DA 동시 발주 포함).
- **오케(Master)가 하는 것**: 실측, 라우팅, 커밋·push 집행.
- **DA는 상시 대기시키지 않는다** — `DA approve loop` / `DA review`로 필요할 때만. 대기 유지 자체가 왕복과 조건 증식을 만든다(실증: 조건 7항 증식 → 라이브 지연).
- **checker 4축 실측**: FE 콘솔 / poller·DOM / worker(서버) / durable 저장소를 전부 본다. FE 미확인 전 "처리 실패" 판정 금지, poller·DOM 미확인 전 "출력 없음" 판정 금지. **사용자가 눈으로 본 것과 분석이 어긋나면 분석이 틀린 것** — 안 본 축부터 본다.

> 상세·실증·안티패턴은 `references/rapid-iteration-loop.md` §역할 체인 / §checker 4축 실측 규칙이 정본.
