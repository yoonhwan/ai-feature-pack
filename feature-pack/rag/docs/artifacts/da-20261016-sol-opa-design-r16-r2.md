골 원문(GOAL-LEDGER-airag.md 복붙):
최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 회복 관찰 + 6순위 C13(KakaoBot 통합 보고서) published 칸 채움.

# DA 판정 — 설계 r16 정오표 재심 (1회성 codex exec · 실행 헤더 인용)
OpenAI Codex v0.159.3
model: gpt-6.1-sol
provider: headroom
reasoning effort: high
session id: 01a144cd-78a8-7240-9d29-c062837b5fea

**최종 판정: REJECT — blocker 0 / major 2 / minor 2 / note 2**

대상은 r16 원문과 정오표다. 원문은 커밋 `b138dc4`와 diff 0임을 확인했다. 규칙 12의 기존 PASS는 재개방하지 않았다.

1. **Major 1 — M2의 정정 뒤에도 Q4 근거에 단정 문장이 남는다.**

   [정오표:44](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag/docs/artifacts/arch-20261016-opa-popup-design-r16-errata.md:44)는 “21.0에 잘렸다는 사실만 기록되며 유한한 느린 호출과 멈춤은 구별되지 않는다”고 올바르게 한정한다. F2·§4.1의 예산 표현도 수용한다.

   그러나 [원문:85](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag/docs/artifacts/arch-20261016-opa-popup-design-r16.md:85)의 다음 문장은 명시적으로 대체되지 않았다.

   - “이 단위가 «느린가·멈췄나»를 가른다”
   - “계측만 넣으면 … 재개가 다시 실패해 재개 1회를 헛쓴다”
   - “상한만 바꾸면 실패해도 이유가 안 남는다”

   21초에서의 중도절단도 느림과 멈춤을 구별하지 못한다. 계측만 적용한 다음 재개의 실패 여부도 현재 자료로 확정할 수 없다. 상한만 변경해도 기존 실패 코드·유형은 남으며, 부족한 것은 키별 경로와 원인 구분 자료다.

   **필요 정정:** Q4의 추천 선택과 커밋 두 개는 유지하되, 위 근거 전체를 “완료된 호출의 소요와 중도절단된 호출의 경로를 기록한다. 재개 결과와 멈춤 여부는 미확인”으로 낮춘다. 이는 기존 Q4 추천 단위나 규칙 12 PASS를 재심하는 지적이 아니다.

2. **Major 2 — M3의 최악 크기 보장과 직렬화 실패 복구 계약이 아직 닫히지 않았다.**

   [정오표:77](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag/docs/artifacts/arch-20261016-opa-popup-design-r16-errata.md:77)는 배열 길이·허용 문자열·소수 셋째 자리 반올림으로 상한을 보장한다고 하지만, 숫자의 타입·정수부 폭·표기 방식은 제한하지 않는다. 반올림은 정수부 길이를 제한하지 않는다.

   메모리 내 반례 계산에서, 현재 시간 조건을 만족하는 **유한·비음수 301자리 정수**를 12개 시간 칸에 넣은 `probe`는 compact JSON으로 **4,181바이트**였다. 정상적인 짧은 숫자를 사용한 같은 구조는 689바이트였다. 이는 운영 관측이 아니라 **문서의 상한 보장에 대한 스키마 반례**다.

   또한 “행 ≤2,048바이트”가 `probe` 증가분인지 전체 로그 행인지 불명확하다. 기존 [결과 검증기:183](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag-consumer/src/airag_consumer/_result.py:183)는 summary 정수의 자릿수를 제한하지 않는다. 따라서 전체 행 상한이라면 기존 필드 불변 조건과 충돌할 수 있다.

   [정오표:75](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag/docs/artifacts/arch-20261016-opa-popup-design-r16-errata.md:75)의 실패 불변 원칙은 수용하지만, 스키마 검증·크기 검사·probe 직렬화가 실패했을 때 **어떤 유효한 최소 레코드를 내보내는지**는 없다. `try/except`와 `probe_error/null`만으로는 필수 숫자 필드와 기존 로그 보존을 함께 인수하기 어렵다.

   **필요 정정:** 크기 제한의 대상을 명시하고, 숫자 직렬화 규칙과 초과 처리 경로를 정한다. probe 처리 실패 시 기존 로그 필드·반환 코드가 보존되는 복구 경로를 정하고, 합성 시험에서 실제 최종 로그의 기존 필드까지 비교한다. 기존 summary를 잘라 상한을 맞추면 안 된다.

3. **Minor 1 — 닫힌 스키마의 필수·선택 필드가 경로별로 일치하지 않는다.**

   [정오표:50](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag/docs/artifacts/arch-20261016-opa-popup-design-r16-errata.md:50)는 `v/load1/op_resident`를 포함한 구조를 제시하지만, :65는 환경에 키가 모두 있으면 “`keys: []`·`tick_total_s`만”이라고 한다. :73은 `op_resident` 필드 자체 삭제를 허용한다.

   **필요 정정:** `v` 등 항상 필요한 필드, 생략 가능한 필드, `null`을 허용하는 필드를 한 표로 확정한다. `tick_total_s`의 유한·비음수 조건과 각 객체의 추가 키 거부도 명시하면 구현 DA의 해석 차이를 줄일 수 있다.

4. **Minor 2 — attempts 개수는 생성된 자식 프로세스 수가 아니다.**

   [정오표:71](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag/docs/artifacts/arch-20261016-opa-popup-design-r16-errata.md:71)는 이 틱이 만든 자식 수를 attempts 개수가 대신한다고 설명한다. 하지만 스키마는 `OSError`도 attempt로 기록한다. 실행 파일 부재·권한 오류라면 자식 생성에 실패해도 attempt는 한 건이다.

   **필요 정정:** attempts를 **호출 시도 수**로 한정한다. `op_resident`를 틱 시작 시 관측된 `op` 명령 이름의 프로세스 수로 정의한 방향은 수용한다.

5. **Note 1 — M1 재계산은 PASS다.**

   네 로그를 timezone-aware `ts` 순으로 연결하고, 반올림 전 값에 임계값을 적용해 독립 재계산했다.

   | 표본 | 건수 | >7초 | >10.5초 | >14초 | >21초 | 중앙값 |
   |---|---:|---:|---:|---:|---:|---:|
   | A: 10-02·11·12·13 | 54 | 31 | 14 | 11 | 3 | 7.352414초 |
   | B: 10-11·12·13 | 51 | 29 | 13 | 11 | 3 | 7.495724초 |

   A의 구성은 ok 3·degraded 51이며, 간격 필터로 제외된 성공 쌍은 15건이다. 마지막 성공 행은 다음 `ts`가 없어 간격 쌍을 만들지 못한다. 경계값 7.047215초·14.002439초도 재현했다.

   F5는 전체 **231건**, 범위 **26.357445~130.952956초**, 중앙값 **31.131145초**다. 필터 후 **230건**, 범위 **26.357445~57.963089초**, 중앙값 **31.110418초**다. 제외 행과 10-13 시간대별 **10/10·3/12·0/10**도 일치한다.

   표본 조건·날짜 경계 연결·식·제외 기준·비교 전 반올림 금지·추정치 한계는 충분히 서술됐다.

6. **Note 2 — 나머지 정정과 승인 경계는 수용한다.**

   m1의 H3~H6 근거 한정과 순차안의 중앙값 오독 정정, N2의 과거 부하 재검증 한계·프로세스 표본 확대 금지는 수용한다.

   R-2의 설치 위임 범위 확인과 범위 밖 별도 승인, R-3의 “또는 오빠 판정” 보존과 위험 고지, R-5의 **연속 3틱 즉시 중단 보고** 및 중단 집행 승인 분리는 일관된다. 직전 7/14 설치본 백업을 기본 복원 대상으로 삼고 30초 백업을 이력 증거로 한정한 것도 수용한다.

   새 문장의 금지어 네 개는 점검 대상 이름을 열거한 메타 문구에서만 확인됐다. 원인 판정에 사용한 사례나 실제 키·토큰·참조·환경 값 출력은 발견하지 못했다.

**최종 REJECT.** M1은 닫혔으나, Q4에 남은 관측 초과 단정과 M3의 크기·직렬화 실패 계약을 정정해야 한다. 이 판정은 코드 변경·설치·재개 승인이 아니다.

파일 쓰기·실제 `op` 실행·운영 파일 변경·launchctl·mbox·서브에이전트 사용은 모두 0이다. Serena는 노출되지 않아 문서·로그 직접 읽기와 grep으로 대조했다.
