model: gpt-6.1-sol
provider: headroom

# AIRAG U2 published 진단 설계 DA r2 — PASS (blocker 0, major 0, minor 2)

**판정: PASS — blocker 0, major 0, minor 2.** 발주 #2093의 r2는 r1의 두 major와 두 minor를 핵심 명세에서 닫았다. 단일 producer 정합 정책과 malformed protocol의 명시 거부, top-3 관계 검증, literal 출현/수기 키 갱신, list fixture 및 확정 입력 반영이 이루어졌다. 정합 발행 실패는 **exit 0/degraded(any-fail)** 그대로이고 malformed published protocol만 기존 RUNTIME_OUTPUT_INVALID 경로로 간다. 남은 minor는 positive fixture 숫자와 그룹 부재/legacy 경계의 설명이다.

- 세션: `ft-airag-da-codex#0`, 발주/직전 확인 gpt-6.1-sol low, provider=headroom. 창 크기·fast 서비스 등급은 미노출.
- 검토 HEAD: `8fb8c982a31fabfaaea07b1a694a893474fe8ae1`.
- 입력: `arch-20261002-published-diag-design.md`, 개정 r2. 이전 r1 판정 `da-20261002-sol-diag-design-r1.md`와 대조했다.
- Serena로 현재 runtime._publish/build_frame 및 기존 fixture를 확인했다. source/test/운영 DB는 수정하지 않았다. `90352c2..HEAD`의 consumer source/tests diff 0이다.

## r1 지적의 폐쇄

| 항목 | r2의 계약 | 판단 |
|---|---|---|
| D1 false-ok 및 top count 초과 | attempted/succeeded exact nonnegative int·items list·len/ok-count equality를 요구. 불일치는 ValueError→build_frame RUNTIME_OUTPUT_INVALID→tick exit 40. clamp 제거. | 닫힘 |
| D2 관계 검증 없음 | 네 base 키 전부/전무, rank code/count 짝·1..k 연속·양수 count·코드 중복 금지·엄격 정렬·총계 산술·other 관계를 parent에서 재검증. | 닫힘 |
| m1 기존 값의 새 literal 출현 | CORE_PUBLICATION_FAILED의 새 structural reference 및 이동한 수기 line key 갱신 허용. frozen 값/렌더/미분류·모순을 별도 확인. | 닫힘 |
| m2 fixture 반환·확정 입력 | bridge fixture가 list 반환, invalid data는 별도 direct frame 입력. any-fail/exit 0/비노출 및 low fast 재확인 문구 제거. | 닫힘 |

현재 runtime._publish는 같은 result list에서 attempted=len(result), succeeded=exact True 수, items=result를 만든다. `None`/비-dict item도 실패로 계산하므로 새 failed_items 분류와 맞다. 정상 producer 결과는 새 정합 검사를 만족한다. 실제 정상 발행 실패를 runtime error로 바꾸는 정책이 아니다.

## 합성 반례 및 정상 입력 검사

설계의 aggregate 및 _publish_group_ok만 별도 메모리 prototype으로 구성했다. 4개 기존 registry 코드의 각 실패 개수 0..3 × 성공 개수 0..2, **768개 정합 경우**를 생성해 요약 후 group 검증했다. 빈 발행·전부 성공·부분 실패·전부 실패·1~4종 코드·동률 순서·other 0/양수를 포함하며 모두 통과했다.

```text
COHERENT_RUNTIME_GROUPS_ACCEPTED 768
R2_INVALID_REJECTS r1_false_ok true
R2_INVALID_REJECTS r1_overflow true
R2_INVALID_REJECTS r1_noitems true
R2_INVALID_REJECTS bool true
R1_SCHEMA_COUNTEREXAMPLES_REJECTED true
NO_PUBLISH_GROUP_ACCEPTED true
```

정합 입력에서 failed=len(failed_items)=attempted−succeeded가 되어 counter sum이 total을 초과할 수 없다. top-3 밖은 정확히 other로 남는다. all-fail-only status mutation은 T3이, silent clamp 정책은 T9/T10이, pairing/rank/sort/sum 검사 omission은 T8/T11이 겨냥한다.

str 검사→regex→registry membership·fallback의 비노출 방향은 r1과 같다. dict/list code가 membership에서 TypeError를 만들지 않으며 부모의 재검증을 정제 전 파일 노출의 대체로 쓰지 않는다. T5가 반환 frame와 anonymous 결과 파일까지 관찰하도록 보강된 점이 적절하다.

## Minor

### R2-m1 — T7 positive 수치에 유효한 완성이 없다

- 앵커: §⑤ T7의 attempted=5/succeeded=0/failed=5/other=0, count_1=2/count_2=1 예시.
- top-3는 최대 세 slot이고 count 내림차순이므로 남은 count_3는 최대 1이다. 그 예시의 합은 최대 4여서 failed=5와 동시에 맞출 수 없다. count_3=2로 채우면 정렬을 깨뜨린다. ellipsis로 생략한 부분에도 정상 completion이 없다.

```text
T7_PARTIAL_EXAMPLE_HAS_VALID_COMPLETION false
```

- 보정: total 4·ranks 2/1/1·other 0, 또는 total 5·ranks 3/1/1·other 0 등 **구체적인 완전한 정상 frame**으로 고친다. 모든 코드는 실제 registry literal을 사용한다. validator를 완화해 잘못된 positive를 통과시키면 안 된다.

### R2-m2 — published 부재·잘못된 타입·legacy 두 총계의 경계를 구분한다

- 앵커: §3.1(3)의 “published가 dict이면”, “키 자체가 없으면”; T13의 “published_failed 없는 기존 정상 요약”.
- published 키가 **있지만 None/list/string**인 경우를 명시한다. 현 summarize의 `if isinstance(published, dict)` 패턴만 남기면 잘못된 present 값이 그룹 부재로 무시될 수 있다. absent key는 기존 호환 경로, present malformed type은 protocol-invalid로 보내는 분기를 권한다. normal runtime은 dict를 만들어 이 보정 때문에 오거부되지 않는다.
- 새 validator는 기존 `published_attempted/published_succeeded` 두 키만 있는 summary를 네 키 부분 존재로 거부한다. 따라서 T13의 “failed 없음”은 아무 legacy frame이나 뜻하지 않는다:

```text
LEGACY_TWO_TOTALS_GROUP_ACCEPTED false
NO_PUBLISH_GROUP_ACCEPTED true
```

- 보정: T13의 positive를 `{sources:1}` 등 **발행 그룹 전체가 없는** summary로 특정한다. 두 총계만 있는 old-wire frame을 계속 허용할 것인지, same-version parent/child 배포에서 strict하게 거부할 것인지도 명시한다. fresh child가 새 summarize로 만든 정상 runtime 출력은 네 키를 모두 가져 문제없다. malformed field를 조용한 ok로 처리하거나 relation 검증을 무력화하는 호환 분기는 요구하지 않는다.

## protocol-invalid와 기존 흐름

현재 build_frame은 JSON/data shape를 검사하고 summarize를 호출한다. 구현 시 새 ValueError를 **summarize 호출까지 감싼 범위**에서 잡아 문서의 exit=0/summary={}/code=RUNTIME_OUTPUT_INVALID frame으로 변환해야 한다. 현재의 JSON parse try만 바꾸면 호출 밖 예외가 child process failure로 바뀔 수 있다. T9 direct build_frame와 T10 actual child/tick에서 exact code/exit를 확인하는 명세가 이를 잡는다.

그 invalid frame은 기존 tick.main이 code를 보고 EXIT_RUNTIME로 처리한다. 사용자가 확정한 exit 0 유지 대상인 **정합 publication 실패**와 구분되므로 fixed 정책을 재론하지 않는다. key/config/runtime의 기존 nonzero status도 T12에서 그대로 보존한다.

정렬·짝·정확한 int·합계 검증은 protocol shape/자기 일관성 검증이다. hidden omitted code의 실제 분포나 임의 외부 데이터의 진실성을 인증하는 기능은 아니다. 같은 버전의 실제 producer Counter가 top-3 선택을 수행한다는 범위에서 T2/T16/T17을 검사한다.

## T1~T18 및 registry

- T1~T4는 확정 status/exit와 정상 집계의 긍정 경로다.
- T5/T6/T11은 raw 값·비-hash code·forged frame의 파일/parent 경계를 확인한다.
- T8은 r1 semantic group 반례를, T9/T10은 malformed aggregate의 direct frame 및 실제 tick 경로를 검증한다.
- T14/T15는 pure parent import와 새 reference/이동 키 처리이며, CORE_PUBLICATION_FAILED 값이 이미 frozen에 있는 것과 새 occurrence 검토는 분리된다.
- T16/T17의 3/4종 경계·tie·item permutation은 producer 순서 비결정성 mutation을 잡는 적절한 사례다. T7/T13은 위 minor대로 구체화해야 한다.

정적 코드 문자열과 기존 528 값을 유지하는 방향은 맞다. 필요한 reference 수기 항목을 갱신하면 registry 값을 새로 늘릴 필요가 없다. 설계 단계이므로 아직 source의 새 helper를 실행하거나 T1~T18 구현을 통과 판정한 것은 아니다.

## 증거 범위

이번 round는 현재 code anchor 재확인·r1 counterexample의 개정 정책 거부·768개 정합 요약/group 검증이다. source/tests가 r1과 동일해 r1의 frame/registry 기준선 **9 passed/94 deselected**를 기존 증거로 대조했으며 반복 실행했다고 주장하지 않는다. 새 구현의 실제 child/tick protocol 및 배포 호환성은 Nano 구현/코드 DA가 확인해야 한다.

합성 코드/입력만 사용했다. 운영 DB·실제 op·endpoint·서버 기동·source/test/설계/registry 수정, commit/push/일반 프로세스 종료를 하지 않았다. 신규 산출물은 이 판정서 하나다.

**최종: PASS (blocker 0, major 0, minor 2).** r1의 주요 모순은 닫혔다. T7의 정상 수치와 present/absent/legacy 경계를 보정한 뒤 실제 구현에서 정합 publication failure의 exit 0/degraded와 invalid protocol의 기존 오류 경로를 검증한다.
