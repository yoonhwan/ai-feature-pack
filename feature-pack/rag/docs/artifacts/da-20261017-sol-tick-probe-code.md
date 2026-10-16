골 원문(GOAL-LEDGER-airag.md 복붙):
최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 회복 관찰 + 6순위 C13(KakaoBot 통합 보고서) published 칸 채움.

# DA 판정 — tick.py 계측(probe)+상한 10.5/21.0 구현 심사 (1회성 codex exec · 실행 헤더 인용)
OpenAI Codex v0.159.3
model: gpt-6.1-sol
provider: headroom
reasoning effort: high
session id: 01a1454a-44eb-77e3-8bc0-e401e1b7b1d9

**최종 REJECT — blocker 0 / major 3 / minor 0 / note 2**

지정한 `e529d96..8532bd8`의 4개 파일 diff 전체와 설계 r16·정오표 1·2차·r3 note를 대조했다.

1. **Major 1 — 재시도 마감 계산 시점 변경으로 ⓐ 행위 불변과 ⓑ 남은 마감 계약이 깨진다.**

   [tick.py:339](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag-consumer/src/airag_consumer/tick.py:339)에서 잡은 `ended`를 기록 처리와 오류 분류 뒤에도 재사용한다. 기준 코드는 오류 분류 뒤 현재 시각으로 남은 마감을 계산했다.

   이전 커밋과 현재 커밋을 메모리에 로드하고 같은 합성 호출·시계를 적용한 결과:

   | 조건 | 기준 e529d96 | ⓐ 64b884c / 최종본 |
   |---|---|---|
   | 7.0/14.0, 첫 timeout까지 13.9초 + 오류 분류 지연 0.2초 | 호출 1회, exit 30 | 14.1초에 두 번째 호출, timeout 0.1초, 성공 |
   | 최종 10.5/21.0, 첫 timeout까지 20.9초 + 기록 지연 0.2초 | 재시도 금지 조건 | 21.1초에 두 번째 호출, timeout 0.1초, 성공 |

   따라서 마감 소진 뒤에도 재시도가 가능하며 업무 결과까지 달라진다.

   [test_tick_probe.py:59](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag-consumer/tests/test_tick_probe.py:59)의 `baseline=True`는 현재 코드의 probe 조립만 실패시킨다. 이전 `load_keys`와 비교하지 않으므로 이 변경을 증명하거나 탐지하지 못한다.

   **행위 불변 주장 불수용.** 시도 종료 계측값과 재시도 예산 계산을 분리하고, 기록 처리 뒤 현재 시각으로 남은 마감을 계산해야 한다. 이전 커밋과의 비교 및 위 경계 시험도 필요하다.

2. **Major 2 — `op_resident` 수집 전체의 1초 한도가 보장되지 않는다.**

   [tick.py:99](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag-consumer/src/airag_consumer/tick.py:99)는 `Popen` 생성 뒤 첫 `communicate`에만 1초를 적용한다. timeout 뒤에는 `kill()` 후 **한도 없는 `communicate()`**를 호출한다. 직접 확인한 timeout 인자는 `[1.0, None]`이었다.

   정오표 §3.3·§3.4의 계약은 **수집 전체 ≤1.0초**다. 생성·회수·파싱을 포함하는 전체 한도가 없으며, 무제한 회수가 끝나지 않으면 예외 처리에도 도달하지 못한다. 기존 시험은 첫 timeout 인자와 kill 여부만 확인한다.

   **설계 밖 결정 ⑴은 현재 구현으로 불수용.** `Popen` 사용 자체와 이름만 읽는 방식은 수용하지만, 기존 `subprocess.run` 스파이를 보존했다는 이유로 시간 계약을 충족한 것은 아니다. 수집 전체의 한도를 보장하거나 설계가 허용한 `op_resident` 필드 삭제가 필요하다.

3. **Major 3 — 최종 줄 직렬화 실패가 최소 probe 복구를 건너뛴다.**

   [tick.py:278](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag-consumer/src/airag_consumer/tick.py:278)는 정상 probe 검사 뒤 최종 payload를 다시 직렬화한다. 이 마지막 직렬화가 실패하면 바로 기준 줄을 반환한다.

   정상 probe가 들어간 최종 payload 직렬화만 실패시키고 최소 probe 직렬화는 허용했을 때, 실제 시도는 `['normal']`뿐이었다. 최소 probe를 시도하지 않고 기준 줄을 출력했다.

   정오표 2차 §2.3·§2.4는 직렬화 실패에도 **최소 probe → 그것도 실패하면 기준 줄**을 요구한다. 현재 직렬화 실패 시험은 `_probe_text`에만 오류를 주입한다.

   **복구 사슬 충족 주장 불수용.** 최종 합성 직렬화도 최소 probe 복구 경로에 포함하고 해당 실패 지점을 시험해야 한다.

**Note 1 — 직접 확인한 시험 증거**

- 관련 회귀: **261 passed, 0 failed, 403.05초**. `test_tick.py`, `test_tick_probe.py`, `test_reason_codes.py`를 재실행했다. `8532bd8`의 reason-code 수정은 줄 키 12개 이동뿐이며 관련 시험도 통과했다.
- 메모리 내 변이 **10종 모두 탐지, 생존 0**: 스키마 무조건 허용·반올림 후 검증·resident bool 허용·시도 기록 제거·상수 30·복구 예외 전파·남은 마감 무시·소진 후 재시도·출력 후 재시도·세 번째 시도 허용. 모두 원복했다. 이는 직접 선택한 10종의 결과이며 시험의 완전성을 뜻하지 않는다.
- 정상 8개 시나리오는 기준/ⓐ/최종본을 7.0/14.0으로 맞춘 독립 비교에서 호출·timeout·반환 코드·기존 로그 필드가 일치했다. 위 Major 1은 추가 경계 재현이다.

**Note 2 — 수용 항목과 범위**

- 정확한 숫자 타입·범위, 반올림 전 검증, `v`를 포함한 bool 거부, 301자리 정수 거부, 닫힌 스키마는 수용한다.
- 최대 폭 숫자와 오류 사유 32개 조합에서 최대 probe **729B**, 줄 증가분 **738B**였다. 큰 summary 절단은 없었다.
- 10.5/21.0 상수와 요구 주석은 일치한다. 운영 상한 대입에 600/300/70은 없으며 70은 천장 주석에만 있다.
- 알려진 실패 경로의 기록 보존과 값 비출력은 수용한다. 토큰·참조·환경 값·op 인자의 probe 유입은 발견하지 못했고 `keys[].name`은 NAMES 3종으로 제한된다.
- 설계 밖 결정 **⑵ 옛 상수 시험 삭제·새 시험 대체는 수용**, **⑶ 미시작 작업을 취소하는 기존 `pool.map` 동작 유지도 수용**한다. 실제 시작한 나머지 작업의 기록은 보존된다.

실제 `op`·launchctl·운영 plist·설치본·runtime.json·mbox·서브에이전트 사용은 0이다. 변이는 메모리에서만 적용했고 대상 파일은 `8532bd8`과 동일하다. 초기 미추적 `.claude/`, `CLAUDE.md`도 그대로다. Serena handshake를 확인했다.

**최종 REJECT. Major 3건 해소 후 구현 재심이 필요하며, 설치·재개 승인은 포함하지 않는다.**
