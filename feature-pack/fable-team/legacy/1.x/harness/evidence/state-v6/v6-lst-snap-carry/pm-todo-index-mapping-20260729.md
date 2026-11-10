# 원래 계획 인덱스 ↔ 신규 TodoN 대응표 (2026-07-29, pm-v6#5)

> 오빠께 보여드리는 실측 보고. **실측**과 **추정**을 구분해 표기. 원본에 없는 것은 "없음"으로 적었고 지어내지 않았다.

## 확인한 정본 3개

| 정본 | 경로 | 성격 |
|---|---|---|
| ① 원 계획 | `.omo/plans/v6-window-reuse-isolation.md` | Todo1~8 + F1~F4 (전체 계획의 최상위 8개 작업항목) |
| ② 노드그래프 정본 | `.omo/plans/v6-graph-realign-c-to-e.md` | Todo 번호를 안 씀. C0/C1/C1b/C2/D/E0/E1/E2 게이트 이름 사용 |
| ③ Todo7 상세계획 | `.omo/plans/v6-todo7-complete-e1b-e1c-prevtext.md` | ①의 Todo7 항목 하나를 확장한 문서. **자체 Todo1~12 + F1~F4를 따로 가짐** |

**먼저 확인된 사실 — 번호가 문서마다 다르게 쓰인다(혼동의 실제 원인)**: ①의 Todo1~8과 ③의 Todo1~12는 **서로 다른 번호공간**이다. 예: ③의 "Todo1"(`stt.translated` payload builder 추출)은 ①의 "Todo1"(V5 canonical topology 복원)과 **완전히 다른 작업**이다. 또한 state.md·V6-CANONICAL-STATUS.md에서 실제로 쓰이는 "TodoN"은 **①의 번호공간**이며, ③ 내부 번호는 원장에서 쓰인 적이 없다(grep 확인, 아래 표에 반영).

추가로 **제3의 번호축**이 실측됨: state.md는 D-WIRE~E2c 구간을 "gate13~gate20"으로 **자체 재번호**해서 쓴다(①·③ 어디에도 없는 원장 자체 부여 번호). Todo와 gate는 별개 축이다.

## 대응표

| # | 정본①의 항목(Todo 인덱스) | 항목 요지 | 현재 상태 | 대응 TodoN(현재 원장·V6-CANONICAL-STATUS 표기) | 대응 없다면 이유 |
|---|---|---|---|---|---|
| 1 | **Todo1** | V5 canonical topology 복원 + 옛 release marker 격리(V6 activation 안 건드림) | **완료** — `1a1e64e0` 랜딩, T1 PASS로 라이브검증 CLOSED (gate14로 등재) | **없음** | **번호가 빠졌다(누락 아님, 다른 이름으로 대체됨)** — 실측: state.md·V6-CANONICAL-STATUS.md·V5-CANONICAL-STATUS.md 어디에도 "Todo1" 문자열 0건. 현재는 "V5정상화" 또는 "gate14"라는 별도 이름으로만 지칭됨 |
| 2 | **Todo2** | V6 source-plane authority 동결 + node/side-effect 불변식 확정 | **완료** — `db54b311`, architect 최종판정 PASS(DA 불필요) | **Todo2** (번호 그대로 유지) | 해당 없음 — 그대로 대응 |
| 3 | **Todo3** | persisted D-to-E dispatch, 7-variant 전수 처리 + RELEASE-only 잔여승격 | **완료** — `17902376`+`93752f06`, worker 로그 `V6-D:d_to_e` 6건 실측 | **Todo3** (번호 그대로 유지) | 해당 없음 — 그대로 대응 |
| 3-보충 | **(원 계획에 없음)** | terminal-intent residue terminalizer | **완료** — `885850d2` | 원장에서 **"Todo3b"**로 지칭됨 | **원 계획 3개 정본 어디에도 "Todo3b" 문자열이 없다(grep 0건) — 구현 중 새로 만들어진 번호.** *추정*: 원 Todo3의 7-variant 표에 있는 `residual_only` 변형 처리와 같은 영역(잔여/종결 판정)이라 Todo3의 후속 보완으로 보이나, 이것이 문서에 명시적으로 근거를 둔 연결은 아니다 — 추정으로만 표기 |
| 4 | **Todo4** | E2-CORE 프로덕션 배선 완성(E1c 실제 행 → Redis-Cluster-safe 원자적 commit 권위 하나) | **미착수/진행 중** — E2a/E2b 자체는 GREEN(`eabb652e`)이나 실제 배선은 0(`배선 0, 미완`) | **Todo4** (번호 그대로 유지, 지금 "완성정의 3항목" 중 하나 = "재시도해도 중복되지 않는 것") | 해당 없음 — 그대로 대응, 아직 열려있음(W2) |
| 5 | **Todo5** | E1a `translate_refined` — 첫 공개 LST enrichment 단계, 화면에 번역 버블 노출까지 원 계획 인수조건에 포함됨 | **랜딩, 완료 아님** — 배선 존재 확인(`a78327c8`), 재기동+라이브발화 2회 테스트 완료, **D단계(splitter) 결함으로 화면 미도달** = W0-A DEFECT 판정 | **Todo5** (번호 그대로 유지, 지금 "완성정의 3항목" 중 하나 = "발화가 끝까지 가서 화면에 뜨는 것", 원장에서 **W0**으로도 지칭) | 해당 없음 — 그대로 대응, 아직 열려있음(W0) |
| 6 | **Todo6** | E1b row/room-context type① polish, conservation·provenance 가드 | **랜딩, 라이브 미검증** — `3fe11ae9`, GREEN 30/30 | **Todo6** (번호 그대로 유지, HELM 지시로 "그 뒤로 미뤄도 된다"에 해당) | 해당 없음 — 그대로 대응 |
| 7 | **Todo7** | E1c changed-only retranslation + same-identity 번역결과 노출 | **설계 확정, 구현 미착수** — SHA `b7415cf1` DA APPROVE 완료, 원장에서 **W1**로 지칭 | **Todo7** (번호 그대로 유지, 지금 "완성정의 3항목" 중 하나 = "취소선이 실제로 뜨는 것") | 해당 없음 — 그대로 대응하되 **주의**: 원 Todo7 항목 자체가 정본③(`v6-todo7-complete-e1b-e1c-prevtext.md`, 자체 Todo1~12)으로 **상세화·확장**됐다. *추정*: 지금 강조되는 "취소선"은 이 확장 문서의 prev_text 처리(변경분 표시)에 해당하는 것으로 보이나, 정본① 원문에는 "취소선/strikethrough" 단어가 직접 나오지 않는다(원문은 "changed-only retranslation and same-identity polished visibility") — 이 연결은 추정이지 실측이 아니다 |
| 8 | **Todo8** | E2 enrichment/terminal seal cutover, 구 window-v2 참조 은퇴, 단일 라이브 Release-A 증명 | **미착수** | **Todo8** (번호 그대로 유지, HELM 지시로 "그 뒤로 미뤄도 된다"에 해당) | 해당 없음 — 그대로 대응, gate20(E2c seal cutover)이 이 항목의 일부로 보임(*추정*) |
| F1~F4 | **F1.Plan-compliance / F2.Code-quality / F3.Live-QA / F4.Scope-fidelity** | 최종검증 웨이브(전체 8개 Todo 완료 후 일괄 심사) | **미착수** | **없음** | 실측: state.md·V6-CANONICAL-STATUS.md에 이 F1~F4 문자열 사용 0건(다른 트랙인 `v6-three-polisher-node-validation.md`의 F1~F4와 혼동 주의 — 그건 별개 백로그 문서다) |

## 정리 — 특히 중요하다고 하신 세 가지

**① 완성정의 셋(Todo5/Todo7/Todo4)에 원 계획 나머지가 흡수됐는가 밀렸는가**: **밀렸다, 흡수가 아니다.** Todo1(V5정상화)은 이미 완료돼 번호 밖으로 나갔고, Todo2·Todo3(+Todo3b)도 완료돼 번호 밖으로 나갔다. Todo6·Todo8은 **뒤로 미뤄진 것이 실측**(HELM 지시 원문 "Todo6·Todo8은 그 뒤"). 즉 완성정의 3항목은 "전체 8개 중 남은 것을 추린 결과"이지 다른 항목을 흡수해 몸집을 키운 게 아니다 — **번호도 원 계획과 전부 그대로 일치**한다(Todo4/5/6/7/8 모두 번호 유지).

**② Todo6·Todo8이 원 계획 어느 항목인가**: Todo6=원 Todo6(E1b type① polish) 그대로, Todo8=원 Todo8(E2 cutover+seal+retire+Release-A 증명) 그대로. 둘 다 번호 변경 없음.

**③ Todo3b 출처**: 원 계획 3개 정본 어디에도 없는 번호다. 구현 과정에서 새로 붙은 이름이며(누가·언제 명명했는지는 원장에 기록 없음), 내용은 완료됐고(`885850d2`) Todo3 계열의 잔여처리 보강으로 보이나 그 연결은 추정이다.

**부가 실측(요청 항목은 아니나 중요)**: 원 계획 Todo1(V5정상화)이 완료됐는데도 **"Todo1"이라는 번호로 원장에 한 번도 등장하지 않는다** — 완료된 항목이 번호를 벗고 별명("V5정상화"/"gate14")으로만 남으면서, "TodoN 목록만 보면 8개 중 몇 개가 끝났는지"를 원장에서 바로 셀 수 없게 됐다. 이것이 지금 번호 혼동의 실제 원인 중 하나로 보인다(추정).
