# E2-CORE 배선 갭 조사 (impl#45, 2026-07-28)

> 목적: E2-CORE(`eabb652e`)는 production wiring 0이라 **규율1 기준 미완**이다.
> architect 윈도우 지정이 오는 즉시 착수할 수 있도록 조사분을 고정해 둔다.
> 전부 읽기 전용 조사이며 코드 수정 0. 판정은 붙이지 않고 사실만 기록한다.

## 1. 현재 `segment.confirmed` 생산 경로 (2단)

| 단 | 위치 | 하는 일 |
|---|---|---|
| 1단 | `worker/graph/speech/pulse/v6/release_ready.py:137-145` | route별 `confirmed_text` 결정 — READY면 `projection.confirmed_text` 또는 `projection.source_raw`, LEGACY면 `decision.refined_raw` 또는 `source_raw` |
| 1단→2단 | `release_ready.py:148` | `_typed_event_mapper`로 dict 전달 |
| 2단 | `worker/services/v5/release_finalize_mapper.py:41-55` | `segment.confirmed` 이벤트 생성 |

- mapper 호출자는 `worker/services/v5/event_mapper.py:636` **하나뿐**이다.
- E2b로 전환할 지점은 `release_ready.py`다. mapper의 `segment.confirmed` 생산부(41-55)가 E2c 철거 대상이고, seal부(56행 이후 `utterance.finalized`)는 정본대로 유지 가능하다.

## 2. handoff 생산지와 confirmed 생산지가 서로 다르다

- handoff 생산: `worker/graph/speech/pulse/v6/activation_subgate/consumer.py:281` — `execute_d_wire`로 만들고 `DWireStore.commit_or_replay`로 durable 저장.
- 그 직후 `consumer.py:292`에서 `d_wire_handoff_shape`로 **row_count만 로깅하고 끝난다** — 소비자가 없다.
- `release_ready`가 `DWireStore`를 읽는 코드는 없다.

## 3. 배선에 지금 없는 것 — 넷 (공백 A 하나가 아님)

1. **`commit_candidate_or_replay` concrete 구현 0** — `worker/`·`shared/` 전수 grep에서 `e2b_segment_commit.py` 밖에 이 이름이 없다. tests double만 존재(공백 A).
2. **E1a/E1b/E1c 부재** — E2a 입력이 E1c의 ordered final row인데 그 생산자가 없다. 즉 E2a에 넣을 rows를 만들 곳이 없다.
3. **handoff 전달 통로 부재** — §2 참조.
4. **`SegmentLedger`가 V6 경로에 미주입** — 생성 지점은 `worker/main.py:574` 하나뿐이고, `release_ready`의 import 목록에 ledger가 없다(async Redis만 받는다).

## 4. 붙였을 때 깨지는 것 — 코드 근거

### 4a. sync/async 경계 (가장 주의 필요 — 과거 사고 기록 있음)

`worker/main.py:67-79` 주석이 명시한다:

> SegmentLedger is synchronous today; passing the async client makes Redis calls
> return coroutine objects and breaks final commit JSON parsing.

- `SegmentLedger`는 전 메서드가 **동기**(`alloc_order_index`, `commit_segment`, `claim_commit_hash` …)이고 전용 sync Redis 클라이언트를 쓴다.
- `release_ready`는 `redis.asyncio`를 쓰는 **async** 경로다.
- 즉 E2b를 여기 붙이려면 sync ledger를 async 컨텍스트에서 호출하게 되고, 이벤트 루프 블로킹이거나 `to_thread` 래핑이 필요하다. **현 구조로는 그냥 못 붙인다.**

### 4b. payload 계약 불일치 — 단일 세그먼트 → 다중 row

| 축 | 현재 mapper (`release_finalize_mapper.py:42`) | E2b |
|---|---|---|
| `segment_id` | `psid` 고정 (release당 1개) | row마다 다름 |
| `version` | `window_rev` | receipt |
| `order_index` | `release_watermark` | receipt |
| `source_hash` | 없음 | 추가됨 |

FE가 받는 이벤트 수와 identity가 통째로 달라진다.

### 4c. `prev_text` 의미 범위 차이

- mapper(`:46`): `accept_candidate`이고 `confirmed_text != source_raw`일 때 `prev_text = source_raw`. 주석에 **whole-segment provenance이고 row alignment가 아니라고 명시**.
- E2b: **row-local**.
- 같은 키 이름이지만 의미 범위가 다르다.

## 5. E1a 선행 조사분 (착수 전 중단 — 유실 방지용 기록)

정본 범위(`.omo/plans/v6-seam-polish-v5-prepend.md` §Unit E1a):
- typed D rows만 받는다.
- **`translate_raw_node`를 재사용하지 않고** V5 mode-agnostic translation kernel을 추출/재사용한다.
- 이미 요구되는 Loom/domain 인자를 보존한다.
- 기존 raw translation 계약을 내고 현행 live `stt.translated` SSE 표면에 bridge한다(`translate.result`만으로는 불충분).
- type① polish / retranslation / commit / strike / seal은 0.

관련 코드 좌표:
- `worker/graph/speech/pulse/nodes/translate_raw.py:326` `_do_translate_sentences` — V5 실제 번역 경로. Loom 3축(`loom_domain`/`audience`/`environment`)을 `_translate_single`로 전달.
- 같은 파일 `:395-413` **B-guard** — 빈 문자열 / `_TRANSLATION_UNAVAILABLE_SENTINEL` / source-echo(`translated.strip().lower() == src_cmp`) 차단. 2026-04-24 lecture VAD chunk 회귀 실측 기록. E1a RED의 "empty/source-echo/provider failures → typed terminal outcome, preview event 0" 축이 여기에 대응한다.
- `shared/services/translate.py:1780` `translate_smart` — 호환 래퍼. 메타 필요 시 `translate_smart_with_meta`.

**해결됨 (architect#27 판정, 2026-07-28)**: (가) 확정 — `_translate_single` 본문을 generation-neutral `worker/graph/speech/pulse/translation_kernel.py`로 추출하고 V5가 실제로 같은 leaf를 re-export 호출한다. V6는 typed adapter로 직접 호출. 금지: `translate_smart` 전환, V6 복제. 필수: V5 output + usage byte-equivalence 핀. → RED 랜딩 완료(아래 §7).

## 6. E1b 사전 조사 (읽기만 — 착수 금지 상태에서 수집)

정본 범위(`.omo/plans/v6-seam-polish-v5-prepend.md` §Unit E1b):
- D row마다 **type① 1회씩 순차** 호출, `context_stage="in_progress"`.
- 첫 row는 frozen prior-confirmed context, 이후 row는 **직전까지 성공한 staged row만** 포함.
- ordered room context + Loom triple을 명시 인자로 전달.
- row conservation/coverage/anchor guard 적용, expected reject는 typed identity로.
- aligned row outcome 저장, **새 event taxonomy 발행 0**. DOM은 E1a의 raw-translation/source view 유지.

### 6a. ★주의 — 기존 `release_polish.py`는 type②이고 E1b는 type①이다

`worker/graph/speech/pulse/v6/release_polish.py`는 이미 loop10b 방어선을 갖고 있으나 **성격이 다르다**:

| 축 | 기존 `release_polish.py` | E1b 요구 |
|---|---|---|
| 타입 | **type②** (`_call_window_polisher(is_release=True)`) | **type①** |
| 단위 | window 전체 joined candidate, **no row split/alignment**(모듈 docstring 명시) | **row마다 1회** |
| 호출 횟수 | release당 1회 | D row 수만큼 |

즉 E1b는 이것을 재사용하는 게 아니라 **row 단위 type① 경로를 새로 세우는 것**이다. 다만 방어 **원리**는 참고 가치가 크다 — 이 모듈이 polisher의 `polished` 주장을 믿지 않고 **어댑터 레벨에서 독립 재검증**한다. 정본이 요구하는 "polisher가 polished를 주장해도 guard가 identity reject할 수 있어야 한다"가 이 패턴이다.

### ★architect#27 확정 (2026-07-28) — 위 이해가 승인되고 경계가 못박혔다

- `release_polish.py`는 **protected compatibility file**이다. E1b에서 **수정·import·runtime 재사용 모두 금지**, **참고만 허용**.
- E1b는 **신규 V6 row-type① path**다. provider 본체는 `nodes/polish.py::_call_polish_llm` 표면을 소비한다(§6b 좌표가 그대로 정본이 됨).
- **재사용 금지 대상 명시**: type② `_call_window_polisher` / `_join_candidate` / whole-window decision.
- **재현할 것은 원리만** — row별 독립 conservation/coverage/anchor, provider `polished` 주장 불신, reject→typed identity.
- **structural row identity/order/provenance mismatch는 fatal**이다.
- ★**`_MIN_NORMALIZED_COVERAGE = 0.85`는 E1b 정본값이 아니다** — 복사 금지이고, 신규 숫자를 임의로 고르는 것도 금지다. RED는 **loop10b 29→2 shrink와 anchor/conservation을 "행위"로 핀한다(숫자가 아니라 행위)**.
- 실제 E1b 제품 구현은 **E1a landing 뒤**다.

### 6b. type① 진입점 좌표

- `worker/graph/speech/pulse/nodes/polish.py:1040` `_call_polish_llm` — `context_stage: Literal["in_progress","final"]`, Loom 3축(`domain`/`audience`/`environment`), `confirmed_context`, `guard_text`를 이미 keyword로 받는다. E1b가 요구하는 인자 표면이 대체로 갖춰져 있다.
- `polish.py:460` `_diff_guard_is_anchored` — anchor 판정(정확 일치 + edit distance ≤ 2 fuzzy). anchor guard 재료.
- 기존 loop10b RED 선례: `tests/worker/unit/test_v6_release_polish.py:108` `test_loop10b_shrink_rejected_even_when_polisher_claims_polished` — monkeypatch로 polisher를 위조해도 guard가 막는지 보는 구조. E1b RED도 같은 적대 패턴이 필요하다(row 단위로).

## 6c. E1c 사전 조사 (읽기만 — 착수 금지 상태에서 수집)

정본 범위(`.omo/plans/v6-seam-polish-v5-prepend.md` §Unit E1c):
- unchanged/identity row는 **provider 호출 0**.
- changed row는 accepted final source를 쓰고 **같은 segment/version 유지**.
- 재번역 실패가 changed source에 **stale raw translation을 붙이지 않는다**.
- 기존 final translation 계약을 내고 polished `stt.translated`에 bridge. **새 public event type 0**.

### ★E1a와 E1c는 같은 이벤트 표면을 공유하고 `is_polished`로만 갈린다

이게 두 단위의 경계를 정하는 축이다. `stt.translated` 하나에 두 번 실린다:

| 단계 | 발행 시점 | `is_polished` |
|---|---|---|
| **E1a** raw 번역 | 빠른 1차 (`translate_raw` 대응) | `false` |
| **E1c** changed-only 재번역 | polish 확정 후 | `true` |

`legacy_graph.py:13-14`가 V5 쪽 같은 구조를 명시한다 — `translate_raw → stt.translated(is_polished=false)`, `retranslate_polished → stt.translated(is_polished=true, is_final+polish 변경 시만)`. 정본이 E1c에 요구하는 "same-version polished `stt.translated`가 **같은 `.translation-text` 버블의 raw preview를 upgrade**한다"가 이 메커니즘이다.

**따라서**: E1a의 남은 `stt.translated` bridge 작업과 E1c의 bridge는 **같은 표면을 다른 플래그로 쓰는 것**이라, 한쪽을 만들면 다른 쪽 배선이 대체로 따라온다. 다만 `is_polished=true` 발행 조건(변경된 row만)은 E1b의 accept 판정에 의존하므로 E1c는 E1b 뒤여야 한다.

### 6d. V5 선례 — `retranslate_polished.py`

E1c와 대응하는 V5 노드이며, 이미 같은 계열 방어를 갖고 있다:
- `:73` **unchanged skip** — `polished_sentences`가 비면 스킵. 정본의 "unchanged row는 provider 호출 0"과 같은 취지(단 V5는 문장 리스트 단위, E1c는 **row 단위**).
- `:181-199` **빈 결과/source-echo skip** — 빈 `polished_translations`는 이벤트를 아예 안 내보내 UI가 raw를 유지한다. 정본의 "재번역 실패가 stale translation을 붙이지 않는다"에 대응.
- `:81` `previous_text`/`room_context`를 **의도적으로 전달하지 않는다**(HOTFIX 2026-04-18) — E1c가 맥락 인자를 넣으려 할 때 이 결정을 먼저 확인해야 한다.

**주의**: V5는 문장 리스트를 join해 한 번에 번역하고(`:80` `" ".join(state.polished_sentences)`), E1c는 row 단위 changed-only다. E1b와 마찬가지로 **재사용이 아니라 row 단위 경로를 새로 세우는 것**이다.

## 7. E1a RED 랜딩 상태 (impl#45, 미커밋)

| 파일 | 건수 | 상태 |
|---|---|---|
| `tests/unit/worker/graph/_e1a_translate_harness.py` | — | `llm_translate` 결정적 double |
| `tests/unit/worker/graph/test_e1a_translate_byte_equivalence.py` | 8 | **의도적 GREEN**(현 HEAD 특성화 = 추출 감시핀) |
| `tests/unit/worker/graph/test_e1a_translation_kernel_contract.py` | 6 | **RED**(`translation_kernel` 모듈 부재) |

GREEN 잔여 작업: `translation_kernel.py` 신규 + `translate_fanout.py` re-export 수정 — 둘 다 worker 하위라 라이브 창 닫힘 후 착수.
