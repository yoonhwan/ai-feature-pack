model: claude-sonnet-5-5
provider: claude-code session (ft-airag-arch-claude#0, effort=high)

# AIRAG U2 — 상시 틱 `published_attempted 10→14 / succeeded 0` 원인 판정·설계 (발주 #2043)

골 원문: 최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
골의 어느 축인가: A03·A02 5순위 U2 — 상시 서비스가 «수집은 되는데 발행(검색 가능화)이 0» 인 건. 입력: `.fable-team/state/airag/checker-published-facts.json` + Master 실측 2건. 이번 판정은 정적 코드 읽기만 했다(운영 DB·포트·키 미접촉, 코드·설정 미변경).

## ① 판정 (확정 / 가설 구분)

### 확정 (코드로 증명)
1. **«0» 은 예외가 아니라 모든 창이 `ok:false` dict 로 반환된 결과다.** `publish_pending_windows` 의 리스트 컴프리헨션에 try/except 가 없으므로(`bridge.py:388-395`) 예외였다면 틱이 exit 40 이었다. exit 0 + attempted>0 = 창마다 `_publish_window` 가 `{ok:False,error:…}` 를 반환(`bridge.py:307-321,333-348`). `runtime.py:686-687` 은 `ok is True` 만 센다.
2. **실패한 창은 영구 재시도 대상이다.** 실패 시 `publication_state='failed'`·`last_error=<code>`(`lifecycle.py:962-970`), 그리고 `failed` 는 `index_pending` 과 함께 pending 집합에 들어간다(`lifecycle.py:1221-1226`; `visible_pending`→`pending_publication_ids` `:1265`). **그래서 attempted 가 10→14 로 «누적» 된다 = 실패 창은 줄지 않고 신규 창만 얹힌다.** 이것은 백로그가 매 틱 커지는 구조다(300s 간격이면 계속 증가).
3. **false-ok 가시성 결함:** 요약은 `published_attempted/succeeded` 두 정수만 복사하고 실패 코드는 어디에도 남지 않는다(`_result.py:30-34`, checker item1). 발행이 100% 실패해도 틱은 `status: ok`·exit 0 이다 — 운영자는 이 건을 «눈치로» 발견했다.
4. **실패 사유 코드는 코드만으로 구분 불가.** 창별 `last_error`(consumer.db `airag_lifecycle_windows`)와 core job 의 `final_response_json`(projection DB)에만 있다.

### 가설 (순위 · DB 확인 전까지 «판정 아님»)
| 순위 | 가설 | 지지 | 약점/미확인 |
|---|---|---|---|
| H1 | **임베딩 provider 도달 불가**: core `add` 가 프로필의 embedding endpoint 로 호출(`embeddings.py:299-318`)하는데 연결 실패는 `PROVIDER_UNREACHABLE`(retryable True)이고 타임아웃은 `PROVIDER_TIMEOUT`(retryable True) → `_finish_failed` 로 `failed` 기록, 다음 틱에 재시도해도 서버가 없으면 계속 실패 | 18703·18712 현재 LISTEN 없음(Master 실측) · `runtime-result.json:132` «투어 원본 프로필 endpoint 는 stale, 18703/18712 테스트 프로필 필요» | 프로필 endpoint 는 projection DB 안이라 **18712 와 같은지 미확인**. run 당시(15:12·15:23) listen 상태는 미관측(15:24+ 만) |
| H2 | **terminal 고착**: provider 응답은 왔으나 `retryable:False`(예 HTTP 4xx `PROVIDER_REQUEST_ERROR`·`MODEL_MISMATCH`·`PROVIDER_BAD_RESPONSE`) → core job `failed`+final_response error.retryable=False → 이후 매 틱 `terminal_failure`(재시도 호출 없이 같은 응답 재생, `bridge.py:267-292`). **서버를 고쳐도 자동 회복하지 않는다** | stale 프로필 endpoint 가 HTTP 오류를 낼 가능성 | 확인 불가(DB) |
| H3 | 기타(`CORE_NOT_SEARCHABLE`·`WINDOW_INELIGIBLE_AFTER_CORE_PUBLICATION`·프로필 mismatch 등) | 코드 경로 존재 | 증거 없음 |

**포트 18703/18712 와 «0» 의 관계(내 판정):**
- 18703 은 runtime.json 의 `memory_endpoint`(기억 추출 LLM)와 `reference.llm_endpoint_override` 이고, 18712 는 `reference.embedding_endpoint_override`(투어 reference 검색 전용)다. **«발행» 이 쓰는 임베딩 endpoint 는 runtime.json 이 아니라 projection DB 의 프로필에 저장돼 있다**(`bridge.py:228-`, `profiles.py:62,81,143-161`). 따라서 «두 포트가 안 떠서 0» 은 **직접 증명된 인과가 아니라** «프로필 endpoint 가 이 두 포트 중 하나(또는 같은 서버군)일 것이라는 H1 의 간접 정황» 이다.
- 부수 정황: `memory_attempts 2·candidate 0` 도 memory provider(18703) 응답 실패와 모순이 없다(`memory_provider_called true` 는 «호출 경로 실행» 일 뿐 응답 성공이 아니다 — checker caveat). 같은 서버 부재가 두 증상을 함께 설명할 수 있다는 점에서 H1 이 최우선이나, **기억 쪽 실패 코드도 확인 전까지 가설**이다.
- **서비스가 300s 마다 틱을 돌리는 한 H1 이면 매 틱 같은 0 이 반복되고(재시도 실패), H2 이면 서버를 살려도 0 이 영구 고착**한다. 두 경우의 처방이 다르므로(서버 기동 vs 고착 창 정리) **창별 실패 코드 확인이 다음 한 수의 전제다.**

## ② 확인 방법 판정 — DB 열람이 필요한가
**필요하다(최소·읽기 전용·값 없는 집계만).** 코드·로그·포트 관찰만으로는 H1/H2 를 가를 수 없다(위 확정 4). 열람 범위를 이렇게 좁힌다(본문·키·검색어 비접촉):
1. consumer.db: `SELECT publication_state, last_error, count(*) FROM airag_lifecycle_windows GROUP BY 1,2` — **`document`·본문 컬럼을 select 하지 않는다**(코드 문자열과 개수만).
2. projection(core) DB: 프로필의 embedding endpoint **host:port 만**(경로·자격증명 제외 — URL 에 userinfo 가 있으면 마스킹), 그리고 실패 job 의 `final_response_json` 에서 `error.code`·`error.retryable` **만** 집계(메시지 본문 제외).
3. 둘 다 키(3키)가 필요하므로 **HELM 승인 사안**(운영 키 사용·운영 DB 열람). 승인되면 쓰기 없이 읽기 전용 연결(`file:…?mode=ro`)로. 값은 보고서에 코드명·개수·host:port 만 적는다.
- 대안(DB 비접촉): 아래 ④ 진단 개선을 먼저 배포해 **다음 틱 요약에서 코드 집계를 받는다** — 코드 변경·DA·배포가 필요해 직접 열람보다 느리다. 급하면 열람, 개선은 재발 방지로 병행.

## ③ 해결 선택지 (원인 확정 후 선택 — 지금은 결정 불가)
| | 조건 | 처방 | 승인 사안 |
|---|---|---|---|
| X1 | H1(retryable, 서버 부재) | 프로필 endpoint 가 가리키는 임베딩 서버를 기동(또는 이미 떠 있는 올바른 endpoint 로 프로필을 가리킴). 기동 후 **다음 틱에서 자동 회복**(failed 창이 pending 이라 재시도) | GPU·공유 vLLM 상시 부하(U4 와 같은 계열 — **인프라 기동은 HIL**) |
| X2 | endpoint 가 stale/잘못 등록 | projection DB 의 프로필 endpoint 갱신(등록 절차) | **운영 DB 쓰기 = HIL**(`runtime-result.json:132` 가 «immutable test profile 등록 필요» 라고 기록) |
| X3 | H2(terminal 고착) | 서버 복구만으로 회복 불가 — 고착 창/core job 의 정리(재생성)가 필요 | **운영 DB 쓰기·데이터 변경 = HIL**(백업 airag-set-20261001T141910-vtr794ux 있음) |
| X4 | 서버를 당장 못 올림 | 상시 서비스를 일시 정지(launchd bootout) — 백로그 증가·반복 실패 로그를 멈춤 | launchd 변경 = HIL |

**권고(지금): ① HELM 에 위 DB 열람 2쿼리 승인을 요청해 H1/H2 확정 → ② 확정 결과로 X1~X3 중 선택.** 확정 전에는 **어느 것도 실행하지 않는다.**

## ④ 코드 설계 — 진단 가시성(독립 건, 원인과 무관하게 필요)
false-ok(확정 3)는 원인이 무엇이든 재발한다. 이번 건과 별개로 **틱 요약에 발행 실패 코드 집계를 값 없이 남긴다**(Nano 구현 대상).
- `bridge`/`runtime._publish` 가 실패 항목의 `error.code` 를 이미 갖고 있다(`item["error"]["code"]`). `_publish`(`runtime.py:673-690`)의 반환 dict 에 `failed_codes: {code: count}` 를 추가(코드는 `[A-Z][A-Z0-9_]{0,127}` 정규식 통과분만, 아니면 `CORE_PUBLICATION_FAILED`로 집계 — `_finish_failed` 와 같은 규칙).
- `_result.py` 의 summarize 가 `published_failed_codes`(코드→개수, 값은 레지스트리·정규식 통과·개수 int)를 whitelist 로 복사. **frame 스키마(`SUMMARY_INT_KEYS` 형태)가 닫힌 집합이므로 dict 값을 허용하는 확장은 `validate_frame` 재설계를 요구**한다 → 단순화안: 상위 N(=3) 코드만 `published_failed_code_1..3` + `_count_1..3` 평탄 키로. (r3·r11 DA 가 승인한 값 비노출 경계라 **DA 소환 필수**.)
- 상태 정책: 전부 실패(`attempted>0 and succeeded==0`)일 때 틱을 `ok` 로 둘지 별도 status(예 `degraded`, exit 0 유지 vs 새 exit)로 둘지는 **운영 정책 결정**(launchd 는 exit≠0 에 별도 재시도를 하지 않으므로 exit 변경의 실익은 로그 가시성뿐) — 사용자 결정 사안으로 올린다. 권고: **exit 0 유지 + status `degraded`**(재시도 정책을 바꾸지 않고 로그만 구분).
- 테스트 명세(요약): 합성 bridge 가 일부/전부 `ok:false` 를 반환 → 요약에 코드 집계·`degraded`; 값 비노출(코드 정규식·레지스트리 밖은 치환); 기존 whitelist 회귀. 자세한 명세는 H1/H2 확정 후 코드 변경이 승인되면 별도 개정으로 쓴다(지금은 이번 판정의 범위 밖).

## ⑤ 한계
- 이 판정은 **정적 코드 읽기** 다. 운영 DB·포트·로그의 실제 내용을 직접 관측하지 못했다. H1·H2 는 가설이며 확정 4 만 코드로 증명된 사실이다.
- 18703/18712 가 run 당시(15:12·15:23 KST) 떠 있었는지는 관측되지 않았다(현재만 lsof).
- DA 소환: **이번 판정 자체는 불필요**(원인 미확정 단계). 진단 개선 코드(④)를 구현할 때 값 비노출 경계라 설계 DA 를 소환한다.
