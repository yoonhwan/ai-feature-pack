model: claude-sonnet-5-5[1m]
provider: claude-code session (ft-airag-arch-claude#1, effort=high)

# AIRAG U2 — 발행 실패 진단 가시성 (false-ok 제거) 구현 설계 (발주 #2079)

골 원문: 최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
골의 어느 축인가: A03(Nano 구현·Sol DA 루프) · A02 5순위 U2 — 닫는 증거 = 「발행 실패 N건이 있는 틱이 `status: degraded` 로 남고 요약에 실패 코드 집계(값 없이)가 남는다」는 코드·테스트가 DA PASS 후 Nano 로 구현·통과.
확정 입력: 전임(#0) 설계 `arch-20261002-published-design.md` §④ · 원인 H1(임베딩 서버 18712 도달 불가) 확정 · **사용자 결정(HELM #2055, 변경 불가): 틱 exit 0 유지 + status `degraded` + 발행 실패 코드 집계(값 없이)**.
범위: 설계만. 코드·테스트·운영 DB·launchd 미접촉. 읽은 코드: `_result.py`·`tick.py`·`runtime.py:_publish/run_once`·`bridge.py:_publish_window/publish_pending_windows`·`reason_codes.py`·`tests/test_tick.py`·`tests/test_runtime.py:SyntheticBridge`.

---
## ① 한 줄 진단 (확정 3건, 코드로 증명)
1. 발행이 100% 실패해도 틱은 exit 0 · `status: ok` 다. `tick.main` 은 `frame["exit"] != 0` 일 때만 실패로 보고(`tick.py:236-244`), `_result.summarize` 는 `published.attempted/succeeded` 두 정수만 복사한다(`_result.py:30-34`).
2. 실패 사유는 이미 `published["items"][i]["error"]["code"]` 로 `summarize` 입력 안에 들어와 있다(`runtime._publish` 가 `items` 를 그대로 반환, `runtime.py:686-690` · 각 항목 형태 `bridge.py:307-321,333-348`). **그래서 코드 수집은 `_result.py` 순수 필터 안에서 끝난다 — `runtime.py`·`bridge.py` 는 바꾸지 않는다.**
3. 코어가 내는 핵심 코드(`PROVIDER_UNREACHABLE`·`PROVIDER_TIMEOUT`·`PROVIDER_REQUEST_ERROR`·`PROVIDER_BAD_RESPONSE`·`MODEL_MISMATCH`·`CORE_NOT_SEARCHABLE`·`CORE_PUBLICATION_FAILED`·`WINDOW_INELIGIBLE_AFTER_CORE_PUBLICATION`)는 **전부 이미 레지스트리 528 안에 있다**(`reason_codes.py` 77·78·350·392·397·401·403·529행). → 새 reason code 를 만들 필요가 없고 `REASON_CODES` 는 동결 그대로.

## ② 선택 — 평탄 키안 vs 확장안
| 안 | 내용 | 평가 |
|---|---|---|
| E1 확장안: `published_failed_codes: {코드: 개수}` dict | summary 값에 dict 허용 | **기각.** `validate_frame` 이 «값은 int/bool 뿐» 인 닫힌 스키마(`_result.py:110-115`)라 값 타입 규칙 자체를 바꿔야 하고, dict 키 수가 무제한(레지스트리 528 최대)이라 로그 줄이 커지며 r3·r11 DA 가 승인한 «닫힌 집합» 성질을 잃는다. |
| E2 키=코드 안: `published_failed__<CODE>: n` | int 값만 | 값은 int 지만 **키 이름이 동적**(레지스트리 기반 패턴 검증 필요) → 닫힌 집합이 «레지스트리로 닫힌 집합» 으로 약해지고 jq 소비도 불편. 기각. |
| **E3 평탄 top-3 (채택)** | 고정 키 8개: `published_failed`(int 총계) · `published_failed_code_1..3`(str, 레지스트리 코드) · `published_failed_count_1..3`(int) · `published_failed_other`(int, top-3 밖) | 키 집합이 정적으로 닫힘(고정 8개). 값 종류는 int + «레지스트리 코드 문자열» 하나만 추가. 로그 줄 크기 상한 고정. 판별에 충분(H1 `PROVIDER_UNREACHABLE` ↔ H2 `PROVIDER_REQUEST_ERROR` 는 top-1 만으로 갈림). |

**E3 가 경계를 어떻게 지키나:** 문자열 값은 지금까지 summary 에 없었지만, 값 비노출 경계가 지키는 것은 «대화·기억 본문·인용·경로·키» 이지 «문자열 타입» 이 아니다. 새 문자열은 **레지스트리 안의 알려진 코드명만** 통과(`_safe_code` 가 `error_fields` 에서 이미 쓰는 같은 게이트, `_result.py:55-59`; frame 의 `code` 필드도 이미 `FRAME_CODES` 문자열이다). 레지스트리 밖 문자열은 값을 버리고 `CORE_PUBLICATION_FAILED` 로 치환 — **오류 메시지는 데이터이지 코드가 아니다**(기존 원칙 그대로).

## ③ 구현 명세 (정확한 변경 지점)

### 3.1 `_result.py` (순수 필터 · stdlib + `reason_codes` import 만 유지)
1. **새 상수:** `PUBLISH_FAILED_TOP = 3`, `SUMMARY_CODE_KEYS = frozenset({"published_failed_code_1","…_2","…_3"})`. `SUMMARY_INT_KEYS` 에 `published_failed`, `published_failed_other`, `published_failed_count_1..3` 추가(합 5개 추가, 정수 키 총 21개).
2. **새 헬퍼 `_publish_failure_code(item) -> str`:** `item` 이 dict 가 아니면, `item.get("error")` 가 dict 가 아니면, `error.get("code")` 가 `str` + `_CODE.fullmatch` + `in REASON_CODES` 가 아니면 → `"CORE_PUBLICATION_FAILED"`. 아니면 그 코드. (기존 `_safe_code` 의 폴백이 `RUNTIME_FAILED` 인 것과 달리 **발행 문맥 폴백은 `CORE_PUBLICATION_FAILED`** — 둘 다 레지스트리에 있다.)
3. **`summarize` 의 published 블록 확장:**
   ```
   attempted/succeeded 기존 그대로 복사
   items = published.get("items"); 있으면 list 로 취급, 아니면 []
   failed_items = [i for i in items if not (isinstance(i, dict) and i.get("ok") is True)]
   # 총계는 attempted/succeeded 가 둘 다 int 일 때 max(0, attempted - succeeded), 아니면 len(failed_items)
   summary["published_failed"] = <총계>
   Counter(코드 for failed_items) → (count 내림차순, code 오름차순) 정렬 → 상위 3개를 code_1..3 / count_1..3 로
   summary["published_failed_other"] = 총계 - 상위3개 count 합 (0 이상)
   ```
   - 실패 0건이면 `published_failed` 는 `0`, `code_*`·`count_*` 키는 **쓰지 않는다**(키 부재 = 해당 순위 없음). `published_failed_other` 도 0 이면 쓴다(일관된 항상-쓰기 키는 `published_failed` 만).
   - 총계와 항목이 어긋나면(`items` 길이 ≠ attempted) 총계는 attempted-succeeded 우선, 코드 집계는 items 기준 — **집계 합이 총계를 넘지 않도록 `other = max(0, 총계 - top3합)`.** 어긋남 자체는 이번 범위에서 따로 신호하지 않는다(과설계).
4. **`validate_frame`:** 기존 루프에 한 분기 추가 —
   `key in SUMMARY_CODE_KEYS and isinstance(value, str) and value in REASON_CODES` 이면 통과. **`isinstance(value, str)` 를 `in` 앞에 둔다**(비해시 값이 `frozenset.__contains__` 에서 `TypeError` → 부모 내부 오류가 되는 경로 차단 — 기존 `test_a_non_string_code_is_a_rejected_frame_not_an_internal_error` 와 같은 계열). 나머지 분기는 그대로.
5. `FRAME_KEYS`·`RESULT_MAX_BYTES`(64 KiB)·`FRAME_CODES` 불변. 새 키 8개 최악 크기 < 400 바이트.

### 3.2 `tick.py` (status 결정만)
- 상수 `STATUS_DEGRADED = "degraded"` 추가(`STATUS` 딕셔너리는 exit 코드 키라 그대로).
- `main` 의 `line` 조립부(`tick.py:249`): `"status": STATUS_DEGRADED if exit_code == EXIT_OK and summary.get("published_failed", 0) > 0 else STATUS[exit_code]`. 이게 전부다 — **exit 코드는 0 그대로**(사용자 결정), 락·재시도·launchd 동작 불변.
- `summary` 는 이미 `dict(frame["summary"])` 로 새 키를 포함해 줄에 실린다. 추가 코드 없음.
- degraded 는 `exit_code == 0` 일 때만. exit≠0(키·구성·런타임 오류)에서는 summary 가 비어 있어 발동하지 않는다(요약이 `{}`).

### 3.3 건드리지 않는 것
`runtime.py`·`bridge.py`·`lifecycle.py`·`reason_codes.py`(528 동결)·`_pass_child.py`·`cli.py`·launchd plist. `tests/_regen_reason_codes.py` 재생성 불필요(새 코드 리터럴 없음 — 새 키 이름은 소문자 문자열이라 «reason code 로 선언된 리터럴» 이 아니다; 구현 후 `test_reason_codes` 가 stale 을 알리면 그것이 신호).

## ④ degraded 조건 판정
**`published_failed > 0` (부분 실패 포함)을 권고한다.** `attempted>0 and succeeded==0` 만이면 부분 실패(예: 10건 중 1건 `PROVIDER_TIMEOUT`)가 조용히 `ok` 로 남는다 — 지금 증상의 축소판이다.
- 근거: 실패 창은 `failed` 로 영구 pending 집합에 남아 매 틱 재시도 대상(`lifecycle.py:1221-1226`). 부분 실패도 «검색 가능화가 되지 않은 창이 존재» 한다는 뜻이라 운영자가 알아야 한다.
- 대가: 일시적 1건 타임아웃 틱이 한 번 `degraded` 로 보일 수 있다. status 는 신호이지 알림이 아니고(로그 줄 구분만, exit 0·재시도 불변) 다음 틱이 회복하면 `ok` 로 돌아온다 → 수용 가능한 노이즈.
- **사용자(HELM) 확인 1건:** 이 조건(any-fail)이 사용자 결정 「degraded」의 의도와 맞는지. 전부-실패 한정이 맞다면 3.2 의 비교 한 줄(`published_failed > 0` → `published_succeeded == 0 and published_attempted > 0`)만 바뀐다 — 나머지 설계 영향 없음.

## ⑤ 테스트 명세 (Red 먼저 · `tests/test_tick.py` 에 추가, 기존 픽스처 `synthetic_service`·`component_for` 재사용)
합성 bridge 확장이 필요하다 — 테스트 파일 안에 실패를 내는 변형을 둔다(`SyntheticBridge` 서브클래스 `publish_pending_windows` 가 지정 코드로 `{"ok": False, "window_id": w, "error": {"code": X, "retryable": True, "message": "MARKER_SECRET"}}` 를 반환). 테스트 컴포넌트(`_tick_component.py`)가 런타임 hooks 의 bridge 를 바꾸는 방식은 Nano 가 기존 `mode` 인자 패턴을 따라 `mode="publish_fail_*"` 로 확장한다 — **설계가 요구하는 것은 동작이지 픽스처 모양이 아니다.**

| # | 입력 | 기대 (Red→Green) |
|---|---|---|
| T1 | 전부 실패, 코드 `PROVIDER_UNREACHABLE` 3건 | exit 0 · `status=="degraded"` · `published_attempted==3, succeeded==0, published_failed==3` · `code_1=="PROVIDER_UNREACHABLE", count_1==3` · `code_2`·`count_2` 키 없음 · `published_failed_other==0` |
| T2 | 혼합 5건: A×2, B×1, C×1, D×1 (모두 레지스트리 코드, 개수 동률 포함) | 상위3 정렬 = (개수 내림차순, 코드 오름차순): A(2), B(1), C(1); `other==1`; 합 `count_1+2+3+other == published_failed` |
| T3 | 일부만 실패 (성공 2·실패 1) | `degraded` (any-fail 조건) · `published_failed==1` |
| T4 | 실패 0건 (기존 정상 틱) | `status=="ok"` · `published_failed==0` · `code_*`/`count_*` 키 없음 · 기존 `test_normal_tick…` 의 단언(`ok`, `published_attempted` 존재) 그대로 통과 |
| T5 | 실패 항목의 `error.code` 가 레지스트리 밖 (`XX_UNKNOWN_CODE`·소문자·키 모양 64hex·오류 메시지 문자열) | 그 값은 어디에도 안 남음, 집계는 `CORE_PUBLICATION_FAILED` · 줄 전체/로그에서 `MARKER_SECRET`·원 값 부재(`everything_written` 으로 확인) |
| T6 | 항목이 dict 아님 / `error` 없음 / `error.code` 가 int·list(비해시) | 폴백 `CORE_PUBLICATION_FAILED` · 예외 없음 |
| T7 | `validate_frame`: `{"summary": {"published_failed_code_1": "NOT_A_KNOWN_CODE_ZZ"}}`·`…: 3`·`…: ["PROVIDER_TIMEOUT"]`(리스트)·`…: True` | 전부 `None`; 같은 키에 `"PROVIDER_UNREACHABLE"` 이면 통과. 기존 `bad` 목록 전부 계속 `None`(회귀) |
| T8 | 부모 위조 frame: 자식 결과 파일에 `code_1="…KEYLIKE…"` | 기존 `test_parent_rejects_a_forged_frame…` 계열대로 `RUNTIME_OUTPUT_INVALID` — 새 키도 같은 경로 |
| T9 | status 단독: exit≠0 경로(키 오류·런타임 오류) | `status` 는 기존 값(`key_error`·`runtime_error`) 그대로, `degraded` 로 오표기 안 됨 |
| T10 | 구조: `_result.py` 가 여전히 stdlib+`reason_codes` 만 import(기존 `test_tick_parent_never_imports_the_component_stack` 유지) · `reason_codes.REASON_CODES` 개수 528 불변 | 기존 테스트 통과 |

실행 범위: `pytest tests/test_tick.py tests/test_reason_codes.py` + `tests/test_runtime.py -k publish` 정도. **전체 `tests/` 를 넓게 돌리지 않는다**(troubleshoot 09-23 디스크 폭주 — 이 repo 는 해당 없지만 습관 유지: 파일 지정 실행).

## ⑥ 회귀 영향
| 대상 | 영향 | 근거 |
|---|---|---|
| 레지스트리 528 동결 | 없음 | 새 코드 리터럴·새 reason code 없음; 기존 코드만 참조 |
| `SUMMARY_INT_KEYS`/whitelist | 정수 키 5 추가 + 문자열 코드 키 3 추가 | 모두 정적 집합 |
| 기존 줄 소비자(jq·뉴스 틱) | 새 필드는 추가만(기존 필드 불변). **`status` 값 집합에 `degraded` 가 새로 생김** | `ft-news-tick-airag.sh` 등 `.fable-team/bin` 에서 틱 로그 status 문자열을 조건 비교하는 코드는 이번 확인에서 못 찾음; Nano 는 구현 전에 `grep -rn '"status"\|status.*ok' ops/ .fable-team/bin/` 로 재확인할 것 |
| exit 코드·락·재시도·launchd | 없음 | exit 0 유지 |
| 런타임/브리지 | 없음 | `_result.py`·`tick.py` 만 변경(약 40줄 + 테스트) |

## ⑦ 한계·주의
- 이 설계는 «실패가 보인다» 까지다. **H1 의 실제 복구(18712 임베딩 서버 기동·프로필 endpoint)는 별건이며 HIL 사안.** 이 변경을 배포해도 서버가 죽어 있는 한 틱은 `degraded` 로 남는 것이 정상 동작이다.
- 부분 집계는 «이번 틱이 시도한 창» 기준이다. 시도되지 않은(아직 pending 이 아닌) 창은 보이지 않는다.
- `published_failed` 총계는 `attempted - succeeded` 이므로 미래에 `_publish` 가 `ok` 가 아닌 다른 비성공 상태(예: skipped)를 도입하면 의미가 바뀐다 — 지금은 `ok is True` 아니면 전부 실패.
- 로그 줄에 코드명이 남는다는 점은 새로 노출되는 정보다(값 아님). 코드명은 소스에 공개된 레지스트리 리터럴이다.

## ⑧ DA 소환 판단
**소환한다 — 설계 DA 1회(적대 공격 3점 지정).** 이유: 값 비노출 경계(r3~r11 가 같은 경계에서 반복 구멍)이고, 이번에 «문자열 값 허용» 이라는 경계 확장이 처음 들어간다.
- 공격 요청 3점: ① 문자열 코드 키가 우회 통로가 되는가(레지스트리 게이트 + `isinstance` 순서 + 폴백 치환의 빈틈) ② `validate_frame` 확장이 닫힌 스키마를 약화하는가(키 집합·정렬·`other` 산술 불변식) ③ degraded any-fail 조건·`attempted-succeeded` 총계가 items 와 어긋나는 반례.
- 방식: 기존 DA 좌석 `ft-airag-da-sol#1`(high, 경계 경험 최신) 우선 — 발주에 적힌 `ft-airag-da-codex#0` 는 effort 미지정이라 high 지정이 가능하면 그쪽도 가능. **경계 문제라 low/fast 는 권하지 않는다**(Master 가 effort 선택).
- 병렬 가능: KakaoBot 보고서 DA 는 별도 좌석으로(⑨ 참조).

## ⑨ 별건: KAKAOBOT-INTEGRATION-REPORT.md DA 대조 시점
**권고: 지금 절 A·B 먼저 DA, C·D 는 서버 복구 뒤 증분 1회.**
- A(사용법)·B(요구↔증거 추적표)는 코드·문서 대조라 임베딩 서버 상태와 무관 — 지금 DA 를 거치면 잘못된 추적(예: 근거 오인용)을 복구 대기 동안 미리 걷어낸다. 전체를 복구 뒤로 미루면 A·B 의 오류 발견이 늦고 복구 직후 대조량이 한꺼번에 몰린다.
- C(운영 상태)·D(한계/미완: published 0 처리 결과 포함)는 서버 복구 뒤에만 사실이 확정되므로 그때 한 번 채우고 DA 증분 대조(전체 재대조 아님).
- 이번 U2 변경이 KakaoBot 보고서 A.5(오류·재시도 계약)에 영향을 주지 않는다: A.5 는 core CLI 호출 계약이고, 이번 변경은 consumer 틱 요약뿐이다. 단 C(운영 상태)에는 `degraded` 의미 한 줄을 넣어야 한다 — C 작성 시 반영.
- 주의: A·B DA 좌석을 U2 설계 DA 와 같은 좌석에 쌓지 말 것(컨텍스트 혼선) — 별도 좌석 또는 순차.

## ⑩ 사용자 결정으로 올릴 것 (1건)
1. degraded 조건: **any-fail(권고)** vs 전부-실패 한정 — ④ 참조. 나머지는 사용자 결정(exit 0 + degraded + 코드 집계)대로 확정.
