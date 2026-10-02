model: claude-sonnet-5-5[1m]
provider: claude-code session (ft-airag-arch-claude#1, effort=high)

# AIRAG U2 — 발행 실패 진단 가시성 (false-ok 제거) 구현 설계 · r2 (발주 #2079 → #2091)

골 원문: 최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
골의 어느 축인가: A03(Nano 구현·Sol DA 루프) · A02 5순위 U2 — 닫는 증거 = 「발행 실패 N건이 있는 틱이 `status: degraded` 로 남고 요약에 실패 코드 집계(값 없이)가 남는다」는 코드·테스트가 DA PASS 후 Nano 로 구현·통과.
개정 r2: DA 설계 r1(`da-20261002-sol-diag-design-r1.md`, REJECT major 2·minor 2) 반영 — **D1** 총계/items 정합 정책을 «단일 출처 + 불일치는 protocol-invalid»로 확정(③ 3.1-3) · **D2** `validate_frame` 에 진단 그룹 관계 검증(짝·연속 순위·정렬·양수·산술) 추가(③ 3.1-4) · **m1** 새 literal 출현에 따른 `reason_code_review.py` 키 갱신(③ 3.3) · **m2** fixture 는 list 반환·재확인 문구 제거(⑤·⑩). T1~T10 → T1~T18 갱신.
확정 입력(재론 없음): degraded = `published_failed > 0`(부분 실패 포함) · exit 0 유지 · 값 비노출 · DA low fast. 범위: 설계만. 코드·테스트·운영 DB·launchd 미접촉.

---
## ① 한 줄 진단 (확정, 코드로 증명)
1. 발행이 100% 실패해도 틱은 exit 0 · `status: ok` 다 (`tick.py` frame["exit"]!=0 만 실패 취급 · `_result.summarize` 는 `attempted/succeeded` 두 정수만 복사).
2. 실패 사유는 이미 `published["items"][i]["error"]["code"]` 로 요약 입력 안에 있다(`runtime._publish` 가 `attempted=len(result)`, `succeeded=sum(ok is True)`, `items=result` 를 **같은 list 에서** 만든다). 그래서 수집은 `_result.py` 순수 필터 안에서 끝난다 — `runtime.py`·`bridge.py` 불변.
3. 필요한 코드(`PROVIDER_*`·`MODEL_MISMATCH`·`CORE_NOT_SEARCHABLE`·`CORE_PUBLICATION_FAILED`·`WINDOW_INELIGIBLE_AFTER_CORE_PUBLICATION`)는 이미 레지스트리 528 안에 있다 → 값 집합 불변.

## ② 키 방식 — E3 평탄 top-3 (r1 과 동일, DA 가 방향 타당 확인)
고정 키 10개(전부 닫힌 집합):
| 키 | 타입 | 의미 |
|---|---|---|
| `published_attempted`, `published_succeeded` | int | 기존 |
| `published_failed` | int | 실패 창 수 = attempted − succeeded = 실패 items 수 |
| `published_failed_other` | int | top-3 밖 실패 수 |
| `published_failed_code_1..3` | str | 레지스트리 코드(순위 1..k) |
| `published_failed_count_1..3` | int | 그 코드의 실패 수(양수) |
확장안(dict)·키=코드안(동적 키)은 r1 사유로 기각 유지.

## ③ 구현 명세

### 3.1 `_result.py` (순수 필터 · stdlib + `reason_codes` import 만 유지)
1. **상수:** `SUMMARY_INT_KEYS` 에 `published_failed`·`published_failed_other`·`published_failed_count_1..3` 추가. `SUMMARY_CODE_KEYS = frozenset({"published_failed_code_1","…_2","…_3"})` 신설. `PUBLISH_FALLBACK_CODE = "CORE_PUBLICATION_FAILED"`.
2. **`_publish_failure_code(item) -> str`:** item 이 dict 아님 / `error` 가 dict 아님 / `error["code"]` 가 `str` + `_CODE.fullmatch` + `in REASON_CODES` 아님 → `"CORE_PUBLICATION_FAILED"`; 통과하면 그 코드. (`isinstance(…, str)` 을 `fullmatch`·`in` 보다 앞에 둔다 — 비해시 값 TypeError 차단.)
3. **D1 정책 — 단일 출처 + 불일치는 protocol-invalid (알려진 «silent 조정» 없음):**
   - `published` 가 dict 이면 `attempted`·`succeeded` 는 **bool 아닌 int(0 이상, succeeded ≤ attempted)** 이고 `items` 는 **list** 여야 한다.
   - items 에서 `ok_count = Σ(item is dict and item.get("ok") is True)`, `failed_items = 나머지`. 정합 조건: `len(items) == attempted` **그리고** `ok_count == succeeded`. 이때만 요약을 만든다.
   - **하나라도 어긋나면(attempted/succeeded 가 int 아님·bool·음수·succeeded>attempted·items 가 list 아님·길이 불일치·ok 수 불일치) 요약을 만들지 않고 `ValueError` 를 올리고, `build_frame` 이 잡아 `{"exit":0,"summary":{},"code":"RUNTIME_OUTPUT_INVALID","type":""}` 를 반환한다** → 기존 경로 그대로 tick 은 `EXIT_RUNTIME`(`RUNTIME_OUTPUT_INVALID`)로 **크게 실패**한다. 정상 producer 에서는 절대 일어나지 않고(위 ①-2), 일어나면 결함이므로 `ok`·`degraded` 로 조용히 넘기지 않는다. 정당한 발행 실패(coherent)는 그대로 exit 0/degraded.
   - 정합일 때: `published_failed = len(failed_items)` (= attempted − succeeded). 코드 집계 = `Counter(_publish_failure_code(i) for i in failed_items)` → 정렬 키 `(-count, code)` → 상위 3개를 `code_k`/`count_k`(k=1..), `other = published_failed − Σ상위3 count`. 실패 0건이면 `code_*`·`count_*` 는 쓰지 않고 `failed=0, other=0`.
   - `published` 키 자체가 없으면 진단 그룹 전체를 쓰지 않는다(기존 동작).
   - 이 정책으로 DA r1 의 반례(성공 수 어긋남·count 합>총계·items 비어 total>0)는 전부 invalid 로 닫히고, `max(0, …)` 클램프는 쓰지 않는다.
4. **D2 — `validate_frame` 진단 그룹 관계 검증.** 기존 per-key 루프에 `key in SUMMARY_CODE_KEYS and isinstance(value, str) and value in REASON_CODES` 분기를 더한 뒤, 루프 후 `_publish_group_ok(summary)` 를 호출하고 False 면 `None`:
   - **전부-또는-전무:** `published_attempted`·`published_succeeded`·`published_failed`·`published_failed_other` 네 키가 모두 있거나 모두 없어야 한다. 없으면 `code_*`·`count_*` 도 하나도 없어야 한다.
   - **산술:** 네 값 모두 0 이상 int(bool 은 per-key 루프에서 이미 배제), `succeeded ≤ attempted`, `failed == attempted − succeeded`.
   - **순위:** 존재하는 `code_i` 집합 = 존재하는 `count_i` 집합 = `{1..k}` (k = 0..3, 연속·짝). 각 `count_i` 는 양수. 코드는 서로 달라야 한다.
   - **정렬:** `(-count_1, code_1) < (-count_2, code_2) < (-count_3, code_3)` 엄격 증가(개수 내림차순, 같으면 코드 오름차순).
   - **합:** `Σcount_i + other == failed`. 추가로 `k < 3 → other == 0`(코드가 3개 미만이면 전부 보여준 것), `failed == 0 → k == 0`.
   - 이 함수는 «이 모양의 프레임만 통과» 를 보장하는 것이지 임의 외부 데이터를 인증하는 것이 아니다(기존 신뢰 범위 유지 — 자식은 정제 필터를 거친 frame 만 쓴다).
5. `FRAME_KEYS`·`RESULT_MAX_BYTES`(64 KiB)·`FRAME_CODES` 불변. 새 키 6개(문자열 3 + int 5 + 기존 2) 최악 크기 < 500 바이트.

### 3.2 `tick.py` (status 결정만)
- `STATUS_DEGRADED = "degraded"` 추가. `main` 의 line 조립에서 `"status": STATUS_DEGRADED if exit_code == EXIT_OK and summary.get("published_failed", 0) > 0 else STATUS[exit_code]`.
- exit 코드·락·재시도·launchd 불변. exit≠0 경로는 summary 가 `{}` 라 degraded 가 발동하지 않는다.

### 3.3 reason-code 참조 키 갱신 (m1)
`_publish_failure_code` 의 `return "CORE_PUBLICATION_FAILED"`(그리고 `PUBLISH_FALLBACK_CODE` 상수)는 **값은 레지스트리 기존 코드이지만 새 literal 출현**이라 AST 가 `structural` 로 분류하고 `unclassified 1` 이 된다. 따라서:
- `tests/reason_code_review.py` 에 새 출현을 `("airag_consumer/_result.py", <line>, "CORE_PUBLICATION_FAILED"): ("reference", "fallback code for an unrecognized publish failure; declared by the bridge")` 로 추가(요소가 상수 한 곳이면 한 줄).
- `_result.py` 59/66/83행과 `tick.py` 31/42/237행의 기존 수기 키는 줄이 밀리면 **줄 번호만** 갱신. generator 전역 규칙은 넓히지 않는다(`python tests/_regen_reason_codes.py` 가 알려주는 stale/unplaced 키만 고친다).
- 확인 세 가지: ① `REASON_CODES` **값 집합 528 불변** ② 레지스트리 렌더 일치 ③ unclassified 0·contradiction 0 (`test_reason_codes` 통과).
- 소문자 `"degraded"` 는 reason code 가 아니므로 레지스트리와 무관.

### 3.4 건드리지 않는 것
`runtime.py`·`bridge.py`·`lifecycle.py`·`reason_codes.py`·`_pass_child.py`·`cli.py`·launchd plist.

## ④ degraded 조건 — 확정 입력
`published_failed > 0` 일 때 status `degraded`(부분 실패 포함, exit 0). 다음 틱이 전부 성공하면 `ok` 로 돌아온다. **사용자 결정으로 확정, 재론 없음.**

## ⑤ 테스트 명세 (Red 먼저 · `tests/test_tick.py`)
**fixture 형태(m2):** 실패는 `SyntheticBridge` 서브클래스의 `publish_pending_windows` 가 **list 를 반환**해 만든다 — `[{"ok": False, "window_id": w, "error": {"code": X, "retryable": True, "message": "MARKER_SECRET"}}, …]`. (실패 dict 하나를 직접 반환하면 `INVALID_BRIDGE_RESULT` 로 끝나 exit 0/degraded 경로를 시험하지 못한다.) 위조/불일치 입력은 `_result.build_frame`/`validate_frame` 단위 호출로 직접 만든다.

| # | 대상 | 입력 | 기대 |
|---|---|---|---|
| T1 | tick 전체 | list 3건 전부 `PROVIDER_UNREACHABLE` 실패 | exit 0 · `degraded` · attempted 3/succeeded 0/failed 3 · `code_1==PROVIDER_UNREACHABLE,count_1==3` · `code_2`·`count_2` 키 없음 · `other==0` |
| T2 | tick 전체 | 5건: A×2,B×1,C×1,D×1(레지스트리 코드, 동률 포함) | 상위3 = (개수↓,코드↑): A(2),B(1),C(1) · `other==1` · `Σcount+other==failed` |
| T3 | tick 전체 | 성공 2·실패 1 | `degraded` · `failed==1` (any-fail) |
| T4 | tick 전체 | 실패 0 (기존 정상) | `ok` · `failed==0,other==0` · `code_*`/`count_*` 키 없음 · 기존 `test_normal_tick…` 단언 그대로 통과 |
| T5 | `build_frame` + tick | 실패 `error.code` 가 레지스트리 밖(`XX_UNKNOWN_CODE`·소문자·64hex 키 모양·오류 문장) 또는 `message=MARKER_SECRET` | **반환 frame(= 자식이 결과 파일에 쓰는 값) 자체**에 원 값 부재 · 집계는 `CORE_PUBLICATION_FAILED` · tick 출력/로그/결과 파일에 `MARKER_SECRET`·원 값 부재(`everything_written`+결과 파일 직접 조사) |
| T6 | `build_frame` | item 이 dict 아님 / `error` 없음 / `error.code` 가 int·list·None | 폴백 `CORE_PUBLICATION_FAILED` · 예외 없음 (실패 신호 보존) |
| T7 | `validate_frame` 긍정 | 완전한 정상 그룹: attempted 5/succeeded 0/failed 5/other 0/code_1=A,count_1=2/code_2=B,count_2=1… 합 맞음 | 통과 · 그룹 없는 기존 `GOOD_OK` 도 통과 |
| T8 | `validate_frame` 부정(D2) | ① 짝 없음(`code_1` 만) ② 순위 구멍(`code_3` 만) ③ `failed=0` 인데 `code_1` ④ `failed=-1`/`other=-1` ⑤ `count_1=5`,`failed=1` 합 불일치 ⑥ 정렬 위반(count 1 이 2 앞) ⑦ 같은 코드 중복 ⑧ `count=0` ⑨ k<3 인데 `other>0` ⑩ `failed≠attempted−succeeded` ⑪ 네 키 중 일부만 존재 ⑫ 코드 키가 레지스트리 밖·int·list·True | 전부 `None` · 기존 `bad` 목록 전부 `None` 유지 |
| T9 | `build_frame` 불일치(D1) | ① attempted=1,succeeded=1,실패 item 1 ② attempted=1,succeeded=0,실패 item 5 ③ attempted=3,succeeded=0,items=[] ④ items 가 list 아님/없음 ⑤ attempted 가 bool/음수/문자열 ⑥ succeeded>attempted | 전부 `RUNTIME_OUTPUT_INVALID` frame (`exit:0, summary:{}`) · `published_*` 키 없음 · 조용한 `ok` 없음 |
| T10 | tick 전체 | T9 의 합성 결과를 내는 컴포넌트 | exit 40(`EXIT_RUNTIME`)·`code=RUNTIME_OUTPUT_INVALID` — 불일치가 `ok`/`degraded` 로 새지 않음 |
| T11 | 부모 위조 | 자식 결과 파일에 T8 의 부정 사례·key-like 코드를 담은 frame | 기존 `test_parent_rejects_a_forged_frame…` 경로로 `RUNTIME_OUTPUT_INVALID` |
| T12 | status | exit≠0 경로(키 오류·런타임 오류) | `status` 는 `key_error`·`runtime_error` 그대로, degraded 로 오표기 안 됨 |
| T13 | status | `published_failed` 없는(기존) 정상 요약 | `ok` |
| T14 | 구조 | `_result.py` import 가 stdlib+`reason_codes` 뿐(기존 `test_tick_parent_never_imports_the_component_stack` 유지) | 통과 |
| T15 | 레지스트리(m1) | `test_reason_codes` | 값 집합 528 불변 · 렌더 일치 · unclassified 0 · contradiction 0 · stale 수기 키 0 |
| T16 | 경계값 | 실패 정확히 3종 / 정확히 4종 / 한 종 100건 | 3종: `other==0` · 4종: 4번째가 other · 한 종: `count_1==100,k==1,other==0` |
| T17 | 순서 안정 | 같은 입력의 items 순서만 바꿈 | 요약 동일(정렬 결정적) |
| T18 | 회귀 | `tests/test_tick.py`·`tests/test_reason_codes.py` 전부, `tests/test_runtime.py -k publish` | 기존 단언 통과(`published_attempted in summary` 포함) |

변이(mutation) 점검 의도: T2·T16·T17 = 정렬/절단/other 오류, T3 = all-fail 한정 오류, T8 = D2 각 불변식 누락, T9·T10 = D1 클램프/silent 조정 회귀, T5 = 정제 전 노출(파일 직접 관찰), T7 = 긍정 사례가 관계 검증을 약화시키지 않음.
실행 범위: 위 파일 지정 pytest 만. 전체 `tests/` 광범위 실행 금지.

## ⑥ 회귀 영향
| 대상 | 영향 | 근거 |
|---|---|---|
| 레지스트리 528 | **값 집합 불변**, 참조 키 1건 추가·줄 번호 키 갱신 | ③ 3.3 |
| whitelist/SUMMARY 키 | 정수 5 + 문자열 3 추가(정적) | |
| 기존 summary 소비자 | 새 필드는 추가만. `status` 값 집합에 `degraded` 신설 | 틱 로그 status 문자열 조건 비교 코드는 `.fable-team/bin` 에서 못 찾음 — Nano 가 구현 전 `grep -rn '"status"\|status.*ok' ops/ .fable-team/bin/` 로 재확인 |
| exit 코드·락·재시도·launchd | 없음 | exit 0 유지 |
| 기존 published 입력 허용 범위 | **더 엄격**: published dict 가 있으면 정수 정합·items list 필수(정상 producer 는 항상 만족, 기존 테스트도 published 부분 입력을 `build_frame` 에 넣지 않음 — Nano 가 `grep build_frame\|summarize tests/` 로 재확인) | ③ 3.1-3 |
| 런타임/브리지 | 없음 | |

## ⑦ 한계·주의
- 이 설계는 «실패가 보인다» 까지다. H1 의 실제 복구(18712 임베딩 서버·프로필 endpoint)는 별건 · HIL 사안. 서버가 죽어 있는 한 `degraded` 는 정상 동작.
- 집계는 «이번 틱이 시도한 창» 기준이다.
- `failed = attempted − succeeded` 는 `ok is True` 아니면 전부 실패로 센다는 현재 계약에 의존한다. 미래에 `_publish` 가 skipped 같은 제3 상태를 도입하면 정합 조건을 함께 바꿔야 한다.
- 로그 줄에 코드명이 남는다 — 소스에 공개된 레지스트리 리터럴이며 값이 아니다(DA r1 이 값 누출로 분류하지 않음).

## ⑧ DA 재소환
r2 개정 반영 후 **DA r2 1회**(Master 발주·`ft-airag-da-codex#0` low fast 유지 — 사용자 확정). 공격 요청 3점: ① D1 불일치 처리 — 불일치가 어떤 경로로도 `ok`/`degraded` 로 새지 않는가, 정합 입력에서 `failed==Σcount+other` 가 깨지는 반례 ② D2 `_publish_group_ok` 가 닫힌 관계를 빠짐없이 막는가(전부-또는-전무·연속 순위·정렬·산술, 이 목록에 없는 구멍) ③ m1 참조 키 갱신이 레지스트리 값 불변과 충돌하지 않는가·T5 가 정제 전 노출을 관찰하는가.

## ⑨ KakaoBot 보고서 DA 시점 (변경 없음)
지금 절 A·B 먼저 DA(별도 좌석), 절 C·D 는 서버 복구 뒤 증분 1회. C 작성 시 `degraded` 의미 한 줄 반영.

## ⑩ 사용자 결정으로 올릴 것
없음 — degraded 조건·exit 0·값 비노출·DA 강도는 확정 입력으로 고정.
