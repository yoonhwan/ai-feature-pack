model: gpt-6.1-sol
provider: headroom

# KakaoBot integration report — document DA r1

판정: **REJECT — blocker 0 / major 2 / minor 2**. 판정 범위는 발주 #2226의 서버 무관 문서 부분이며 제품 전체/운영 완료 판정이 아니다.

대상 `feature-pack/rag/docs/KAKAOBOT-INTEGRATION-REPORT.md`, 검토 HEAD `8837bcb`(267줄). 절 A, 절 B, 절 C의 published 칸 제외, 절 D를 검토했다. 세션 `ft-airag-da-codex#0`; Serena 프로젝트 활성화 및 api/collector/events/tick 심볼과 PLAN 검색 수행. 요청 allocation low fast; 실제 창 크기/서비스 tier는 확인하지 못했다.

사용자 확정 P08A-02 후속 범위, 투어 미수용 3건/보류 76건 범위 결정, published 수치는 서버 복구 뒤 보고 결정을 재론하지 않는다. 문서나 코드의 수정/구현은 수행하지 않았다.

## M1 — 현재 실행과 과거 실행의 구분이 문서 내부에서 모순됨

앵커: 보고서 **:6, :121, :125, :165, :200**. :6은 `[실행]`을 “이 문서 작성 중 현재 HEAD에서 실제로 확인”으로 정의한다. 그러나 :125와 :165는 consumer 364 passed를 `[실행]`으로 올리고, :121은 “이 두 회귀”를 현재 실행으로 설명한다. :200은 consumer의 이번 재실행을 범위 밖/미확인이라고 명시한다.

수치 364가 틀렸다고 판정하는 것이 아니다. **현재 consumer 재실행 근거와 과거 브랜치 실행 근거가 같은 표지로 섞였다는 문제**다. 428 passed는 10-02 Master 확인을 `[인용]`으로 적어 올바르게 구분했다. 364도 실행 시점/버전/근거를 붙여 `[인용]` 또는 명시적 과거 실행으로 분리하고 :121의 “두 회귀”를 실제 이번 실행 범위와 맞춰야 한다. P08A-03 행에 과거 회귀를 현재 확인처럼 붙이지 않아야 한다.

같은 표기 기준으로 :267의 `[실행: checker 사실 수집 #2152]`도 과거 checker 정적 판독을 인용한 것인지 작성자가 현재 소스를 다시 읽은 것인지 분리할 필요가 있다. 코드는 요구 필드만 확인했고 실제 Claude JSONL과 대조하지 않았다는 뒤쪽 한계 문구는 정직하다.

## M2 — 구체적인 권한 사건 미지원이 한계 목록에서 빠짐

앵커: 보고서 **:163, :165, :253–267**; HEAD `rag-consumer/src/airag_consumer/events.py:134–138`, `tests/test_events.py:31–32`; PLAN **:163, :184–185**, `artifacts/p08a03-ledger-verification.json`의 `not_implemented`.

HEAD의 `parse_event`는 **grant/revoke 사건을 `UNIMPLEMENTED_AUTHORITY_EVENT`로 명시 거부**한다. 해당 기대값 회귀를 독립 실행해 **2 passed / 32 deselected, 0.03s**를 확인했다. 과거 원장 산출물도 `grant_revoke_and_correction_reducer`를 미구현으로 기록한다. 그런데 보고서의 P08A-01/P08A-03 행과 D의 알려진 한계 목록에는 이 현재의 구체적 미지원이 없다. “운영 정책·인수 시험 남음”만으로 입력 사건 두 종류의 미지원을 알 수 없다.

이는 권한 검사 전체가 없다는 주장이나 fail-open 결함 판정이 아니다. **권한 사건을 받아 변경하는 지원 범위와 기존 정적 scope 검사를 구분해 적어야 한다**는 문서 지적이다. P09-01(:204)의 지원 한계 별도 기록 및 phase 9 `no_unreported_incomplete_capabilities` 기준에 따라 B/D에 명시해야 한다. 이번 리뷰는 구현이나 신규 사용자 결정을 요구하지 않는다.

아울러 PLAN :177의 “자동 에이전트 주입은 후속” 경계도 이 최종 통합 자료에서는 명시적으로 찾지 못했다. P08B 후속은 B.3에 잘 기록되어 있다. 자동 주입도 이미 정해진 후속 경계로 함께 기록하면 CLI/검색 결과 제공을 KakaoBot 컨텍스트 자동 주입까지 완료한 것으로 읽는 일을 방지할 수 있다. 해당 범위를 다시 열라는 뜻은 아니다.

## m1 — 미처리 예외 앵커와 종료코드 표의 표현

앵커: 보고서 **:79–80**; HEAD `rag/src/airag/cli/main.py:593–599`.

- :80의 `main.py:593–594`와 `cli/main.py:591–594`에는 예외 재던짐이 없다. 실제 `mapped is None` 검사/`raise`는 **:595–596**이다. 본문 동작 설명은 맞지만 근거 범위를 수정해야 한다.
- :79의 “envelope ok=false인 **모든** 실패는 4”는 :78의 ARGUMENT_ERROR envelope(ok=false)/exit 2 예외를 포함하면 성립하지 않는다. “인자 파싱 이후 일반 실행 응답” 등으로 한정해야 한다. 독립 실행에서 bogus/서브명령 누락은 envelope의 ARGUMENT_ERROR와 **exit 2**, 틀린 키/키 소스 누락은 **exit 4**였다.

## m2 — deselected 파일의 raw 줄 수

앵커: 보고서 **:123**. `regression-20261001-deselected.txt`는 **33줄**이며 주석 2줄 + test ID **31행**이다. integration 31건 자체와 문서의 502/1/31 계수는 맞다. “31행”을 “test ID 31행(주석 제외)”으로 적으면 파일 줄 수와 대조 가능하다.

## 코드 앵커 대조

보고서의 명시적인 파일:줄 인용 **23 occurrence**, shorthand **10 occurrence**, 발주에서 별도로 지정한 tick :100–110 **1 range**, 총 **34 range**를 HEAD 파일에 해석하고 내용 대조했다. 모두 파일/줄 범위가 존재한다. 위 m1의 재던짐 근거 범위 외에는 해당 범위가 핵심 주장과 맞았다. 상세 snapshot은 `/private/tmp/da2226-anchor-audit.json`이다. 일반적인 파일명만 있는 링크는 별도로 존재/역할을 확인했으며 이 34개 계수에 포함하지 않았다.

| 대조 대상 | 결과 |
|---|---|
| main :599, :64–73, :66–70, :369/:377/:487, :589–599, :603 | 성공/인자 오류/일반 실패/required subparser/진입점 대조 일치 |
| main :593–594 및 :591–594 | m1: 재던짐은 :595–596 |
| api :57–90, :182–184, :186–187 | 오류 매핑/저장 final error 재던짐/PROCESSING_FAILED fallback 일치 |
| pipeline :200–207, store :1982–1986, embeddings :315/:318 | 원인 error 저장 및 timeout/unreachable retryable=true 일치 |
| reason_codes :383 | PROCESSING_FAILED 목록 항목이며 생성 지점 아님 |
| collector :1–3, :266–280, :352–356, :441–445 | Codex 설명/session_meta·id/ordinal/response_item 조건 일치 |
| events :134–138, bridge :228–308 | 대화 사건 종류 및 대화 창 add/retry 연결 설명 일치; authority 미지원은 M2 |
| tick :100–110 | op timeout/OSError→OP_READ_UNAVAILABLE, 비0/형식 오류→OP_KEY_READ_OR_FORMAT_FAILED; 현재 kind 정제 추가 있음 |
| tests/test_embeddings :110 | 고정 placeholder skip 일치 |
| PLAN :164, 지시 원장 :45/:88/:94–95 | 후속 자료 consumer 요구 및 Claude 제한/HELM 수동 실행 기록 일치 |

PROCESSING_FAILED 선언은 core `api.py:187` **1곳**, retryable=False다. final error가 있으면 :184에서 저장된 code/message/retryable을 재던진다. 이 정정은 올바르다. :71의 두 문장이 마침표 없이 붙은 것은 가독성 문제지만 별도 기능/검증 finding으로 세지 않았다.

## 서버 없는 독립 CLI 실행

HEAD core의 실제 `ai-rag`/`krb-rag` 진입점을 Python 3.13.12로 실행했다. HOME/env를 격리하고 임시 디렉터리 DB와 랜덤 32-byte 키를 **pipe의 inherited fd**로만 전달했다. 문서의 key-fd 사용과 동등하며 키 파일/argv/env에 키를 쓰지 않았다. profile JSON은 인용된 operational-profile 구조를 사용했고 서버 호출은 필요 없었다.

**14개 모두 기대한 결과**:

| 명령 | 독립 결과 |
|---|---|
| init, manage profile/status/doctor/verify | exit 0, ok=true; schema_version 5, healthy=true, provider_connectivity=not_checked |
| backup → restore-backup → restored DB verify | 각각 exit 0, ok=true |
| 틀린 키 verify / 키 없이 verify | 각각 exit 4, KEY_OR_DB_VERIFICATION_FAILED / NO_KEY_SOURCE |
| bogus / 서브명령 누락 | 각각 exit 2, ARGUMENT_ERROR |
| ai-rag --help / krb-rag --help | 각각 exit 0 |

consumer CLI의 source 진입점 `python -m airag_consumer.cli --help`도 별도로 exit 0/문서의 subcommands를 확인했다. 탐색 차원에서 tick --help도 호출했으나 **exit 20 / INVALID_ARGUMENTS**다(기존 `_parser(add_help=False)`); 보고서가 tick help 성공을 약속하지 않으므로 별도 finding이 아니다. core/consumer CLI help와 wrapper help를 같은 것으로 세지 않았다.

증거: `/private/tmp/da2226_cli.py`, `da2226-cli.log`, `da2226-cli-results.json`, `da2226-consumer-help.log`, `da2226-tick-help.log`, `da2226-authority.log`. 첫 probe의 None 키 처리 실수를 임시 script에서 고친 뒤 전체 14개를 재실행했고 최종 results에 모두 보존했다. 제품 소스 변경은 없다.

## 수치·과거 증거 대조

- `p07-independent-install-final-20260913.json`: trace **13개**, 모두 exit 0; 문서 인용과 일치. `p07-quality-final-review`: **12문서/24질의**, scale JSON: **1000 sources/5000 chunks**. 해당 작은 합성/과거 근거를 현재 일반 품질/성능 보장으로 올리지 않았다.
- `p08a03-ledger-verification`: consumer **96 + 기존 normalize 26 = 총122**; 보고서의 인용 수치와 일치. 과거 `final-integration-result`의 `final_regression`: **691 passed/1 skipped/31 integration deselected**. selected collection: **442건/28,156,963B/gap1/coverage_complete=false**, counts: **28 indexed/4 active/337 memories**, extraction complete **118**. restore ages **89/91**. tour reference: **17출처/11그룹**. 모두 인용과 일치.
- tour catalog: **user_accepted true12 / false3**. 51+25=76은 `phase89-report-draft-20261002.md` 및 지시 원장의 사용자 보류 근거와 일치. 이 결정은 재론하지 않았다.
- core 최신 실행 근거: Nano r1 relay `/private/tmp/mbox/20261004T122923-ft-airag-nano-r1#3-to-ft-airag-master-claude#2-r1-report.md`가 가리키는 scratch `s7/pytest-default.log`에서 **502 passed, 1 skipped, 31 deselected, 8 warnings, 177.77s** 확인. 이번 DA는 full suite를 다시 돌리지 않았다.
- 같은 scratch s4의 빌드/설치/help 로그 및 파일 metadata: 새 consumer wheel **94,628B**, core **129,721B**; consumer 단독 설치의 registry dependency 실패, 동반 설치/core-only 설치 및 help 기록 일치. 로그는 repository 밖이라는 문서 설명도 맞다. 전체 wheel 설치를 이번 DA에서 반복하지 않았다.
- C.4의 과거 설치 sha/크기는 mbox **#2131** 본문과 정확히 일치: consumer `c99bcea…0b0d1`/**94,584B**, core `d909cb…1a35`/**129,721B**. 새 s4 core wheel의 실제 SHA-256도 문서의 core 전체 해시와 일치. 새 consumer는 94,628B의 다른 버전이므로 과거 94,584B/hash와 혼동하지 않았다. HEAD package .py count **core27 + consumer19 =46**, `63ed629..87a1225` source diff0 확인. 운영 설치 파일을 이번 DA에서 읽어 재해시하지 않았다.
- C.2의 UTC→KST, 등록 뒤 **6줄 중 exit30 1건**, 전체 **8줄**, pass 반올림은 `checker-op30-facts.json`의 8개 기록과 일치. accepted746/818·offset 수치는 기존 checker-published/phase89 사실 자료와 대조했다. 15:12 수동 실행 주체/“3회 vs 로그1줄” 차이는 원장 :88/:94–95를 정직하게 병기했다. 실제 운영 로그를 이번 DA에서 다시 읽지 않았다.
- B.5 목록 자체는 닫힌 **6개**/남은 **7개**로 올바르게 계수했다. M1은 계수 문제가 아니라 표지/현재 실행 범위 모순이다.

## 범위·한계와 보존

P08A-02 미구현/후속 결정은 B.2와 D.11에 명시되어 **조용한 제외가 아니다**. P08B 후속, 투어 미수용/보류, live 모델 회귀·memory 도달 미확인도 명시했다. A.7의 add/search/fetch/reindex를 현재 검증으로 올리지 않았고 C.7은 서버 복구 뒤 기록으로 남았다. draft/미완/과거 fixture 한계 문구는 대체로 적절하며 운영 완료 선언을 발견하지 못했다. 수정 요구는 M1/M2 및 m1/m2의 문서 정합성이다.

P04의 보호 HWP/렌더 좌표/수식 재계산/임시 파일 한계는 B.1에 있다. 원본 `p04-completion.scope_and_limits`에는 DOCX non-bitmap 경고, embedded document image의 자동 standalone vision 미적용, OCR의 제한된 fixture/정확도 범위도 있다. 이 상세 지원 경계는 추가 중복 구현 요구 없이 해당 scope_and_limits를 명시적으로 안내할 수 있다. 기존 인용 파일에 있으므로 별도 major로 올리지 않았다.

운영 런타임·키·DB·rollout·op/1Password·launchd 및 서버 endpoint에 접근/변경하지 않았다. 임시 CLI fixture와 repository/peer 증거만 사용했다. report/source/test 수정, commit/push 없음. unrelated untracked `.claude/`, `CLAUDE.md` 보존. 본 요청된 판정 파일만 추가한다.
