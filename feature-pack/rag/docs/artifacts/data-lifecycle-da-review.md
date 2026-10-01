# 데이터 생애주기 기획 초안 — DA(적대검증) 리뷰

- 검토자: ft-airag-da-fable51#0 (Fable 5.1, 세션 인자 `--model claude-fable-5-1 --effort high`, `[1m]` 표기 없음 → 표준 창으로 확인)
- Serena: 이 좌석에 미노출. grep/sed 직독으로 대체했으며 심볼 참조 추적은 하지 않았다.
- 검토일: 2026-09-27 (메인 보완 반영: 신규 코드는 sibling `feature-pack/rag-consumer/` 외부 계층, P08A-01~08 순서, fixture 통과 ≠ 생산 완료). 대상: `artifacts/data-lifecycle-draft.md`, `PLAN.md`, `DECISIONS.md`(D-002/006/009/010), `examples/explicit_consumer.py`. 코드 대조: `src/airag/store.py`, `api.py`, `search.py`, `backups.py`, `db/schema.py`.
- 이 파일은 검토 산출물이다. 초안·PLAN·DECISIONS·코드·설정은 수정하지 않았다.

## 판정

**조건부 PASS (기획→개발 착수 기준).** 초안은 사용자 요구 세 축(외부 트리거 조건 트리 / 시간순 로그·N 활성 창·검색 청크 분리 / 중요 기억 상단 배치와 아카이브 순환)을 모두 다루고, core 계약(D-002 명시 요청, D-009 CAS·멱등성, D-010 원자 발행)과 충돌하는 주장이 없다. 아래 **핵심 blocker B1~B3(=M1~M3)** 을 초안 문장 수정으로 해제하고 **M4~M6** 을 반영하며 **미결 사용자 정책 U1~U8**을 임의 승인하지 않은 채 P08A-01(계약 확정) 착수 조건으로 넘기면 개발 착수가 가능하다. M1·M2·M3은 착수 전 필수, M4~M6은 P08A-01 안에서 확정하면 된다.

## 핵심 blocker 3건과 해제 조건 (착수 전)

| # | blocker | 해제 조건(수정 가능) | 상세 |
|---|---|---|---|
| B1 | memory·projection 의 저장 주체(core 소스인가, `rag-consumer/` 원장인가)가 미정이라 계약을 확정할 수 없다 | 초안 §3 표에 두 행 추가(제안 source_key 규칙 포함) 또는 U2 로 사용자 결정 | M1 |
| B2 | 백업 복원(DB 파일 전체 교체)이 그 이후의 delete·권한 철회를 되돌리는데 초안에 재대조 절차가 없다. tombstone 이 늦은 낮은 sequence create/edit 를 이기는 규칙도 없다 | §4 에 「복원 후 ledger 재적용 + 검색 차단 창」 절, envelope 절에 tombstone 우선 1문장 | M2 |
| B3 | eviction 게이트가 «archive 사본» 까지 요구해 채팅 입력에 backpressure 를 거는 형태라 구현 불가 | 게이트 = sealed raw 만, archive 는 `archive_pending`, 하드 상한 시 강제 seal | M3 |

세 건 모두 초안 문장 수정으로 해제되며 코드·설정 변경을 요구하지 않는다. M4~M6 은 P08A-01 안에서 확정한다.

## 주 검토 질문 A~H 요약

| 질문 | 결과 | 근거 |
|---|---|---|
| A 원본 segment / 검색 projection / engine chunk / context window / memory 구분 | 부분 통과 | 네 가지는 구분됐다. **memory 레코드의 저장 위치(core source인지 소비자 저장소인지)** 가 미정 → M1 |
| B 부활 방지(중복·역전·수정·삭제·권한철회·추출지연·백업복구) | 부분 통과 | core `add`는 삭제 소스에 `ALREADY_EXISTS_DELETED`, `reindex`는 `ALREADY_DELETED`로 거부(코드 확인). **백업 복원 후 재대조 절차와 tombstone 우선 규칙**이 없다 → M2 |
| C eviction 전 raw 보존 확인·archive/요약 실패·pin overflow·backpressure | 부분 통과 | pin overflow·요약 실패는 정해졌다. **「raw durable」과 「archive 사본」을 한 조건으로 묶어** eviction 게이트가 흐리다 → M3 |
| D source별 원자 발행 vs CDC 트랜잭션 원자성 / 범위 필터 vs ACL | 통과, 보강 필요 | 초안이 core 의 다중 source 원자성 부재를 명시했다. 코드도 같다(`api._run_batch` 는 항목별 독립 트랜잭션). **commit 묶음 부분 가시성의 처리 방식**이 미정 → M4. `search(source_keys≤100)` 만 있어 ACL 을 scope 로 흉내낼 수 없다 → M4 |
| E 지침 후보의 권한 승격 차단 | 통과, 보강 필요 | 자동 쓰기·복제 금지 명시. **응답 에이전트에 넣는 wrapper 형식과 validated 전환 조건(사람 reviewer)** 이 미정 → M5 |
| F 마스킹 이전 비밀 저장 / 다근거 권한 교집합 / archived projection 폐기 | 부분 통과 | 교집합은 명시. **redaction 이 durable write «앞» 인지, 도구 결과 포함인지** 불명. **projection 보존 기간·물리 폐기 정책 누락** → M6 |
| G 비용/지연/recall/active budget 수락 기준 | 미흡 | M6 운영 실측이 지표만 있고 **사전 고정 질문·기준선·임계 제안**이 없다 → M6(항목 G) |
| H 인덱스 배치 | 메인안 채택 가능, 조건 3 | 아래 「권장 인덱스 배치」 |

## Material findings (우선순위순)

### M1 (A) — memory 레코드와 projection 의 «저장 주체» 를 확정하라 [착수 전 필수]

- 관찰: 초안 §3 은 memory 레코드 필드를 정했지만 그 레코드가 core 의 `(collection, source_key)` 소스인지, 소비자 측 별도 저장소인지 적지 않았다. 「검색 가능한 근거 레코드」라면 검색은 core 가 하므로 core 소스여야 하고, 그러면 invalidation 은 core `update/delete` 여야 하며 CAS·request_id 규칙이 그대로 적용된다.
- 왜 material 인가: 저장 주체가 다르면 B(부활 방지)·F(권한 교집합)·C(pin overflow 예산 계산) 의 구현 위치가 전부 달라진다. 계약(P08A-01)을 이 결정 없이 확정할 수 없다.
- 구체 수정: §3 「세 가지 크기 단위」 표에 4·5행을 추가한다.
  - projection: core 소스, `source_key = session/<session_id>/segment/<segment_id>/view`, revision 은 overlay 버전마다 `update`.
  - memory: core 소스, collection `memory/<tenant>`, `source_key = memory/<memory_id>`, 무효화는 core `delete`(tombstone) + `status=invalidated` 메타 `update`. 소비자 저장소에는 «상태 원장(status/reviewer/anchors)» 만 두고 검색 본문은 core 에만 둔다.
  - 대안(더 단순): memory 를 core 에 넣지 않고 소비자 SQLite 원장에서 규칙 기반으로만 상단 배치. 이 경우 「검색 가능한 근거」 요구를 축소하는 것이므로 사용자 결정(U2).

### M2 (B) — 부활 경로 5개 중 2개가 막히지 않았다 [착수 전 필수]

코드로 확인된 것: `store.add` 는 삭제된 source_key 에 `ALREADY_EXISTS_DELETED`(store.py:1105 부근), `store.reindex` 는 삭제 소스에 `ALREADY_DELETED`, `delete/restore` 는 CAS 검사 후 `state_version` 증가. 이 셋은 초안과 일치한다. 막히지 않은 것:

1. **백업 복원(`manage restore-backup`)은 DB 파일 전체 교체다**(`backups.copy_database`). 백업 시점 이후의 delete 는 복원과 함께 사라지고, 소비자가 들고 있는 revision_token 은 전부 stale 이 된다. 초안 §4 는 「백업·외부 파일도 남을 수 있다」만 적었다.
   - 수정: §4 에 「백업 복원 후 재대조」 절 추가. 소비자 event ledger 는 core DB 밖에 durable 하게 두고, 복원 뒤 ①복원된 DB 의 마지막 반영 event offset 을 `status`/영수증으로 판별 ②그 이후 ledger 의 delete·update·restore·권한 철회 이벤트를 «순서대로 재적용» ③재적용 완료 전 검색 결과를 응답 에이전트에 넘기지 않는다(복원 직후 «검색 차단 창»). request_id 원장이 DB 안에 있어 재적용은 새 요청으로 처리되며 이는 의도된 동작임을 명시.
2. **tombstone 우선 규칙 부재**: 같은 message_id 의 delete 가 먼저 도착하고 낮은 sequence 의 create/edit 가 늦게 오면, 초안의 「늦게 온 사건은 별도 사건으로 수록」만으로는 projection 재계산 시 그 내용이 다시 들어갈 수 있다.
   - 수정: envelope 절에 「같은 message_id 에 대해 kind=delete 가 존재하면 source_version 이 낮은 어떤 create/edit 도 projection·요약·memory 입력에서 제외한다. 비교 키는 producer sequence/source_version 이며 ingested_at 이 아니다」 1문장 추가.
3. **historical 재생 경로**: `replay_manifest` 는 저장된 `results_json`(evidence 본문 포함)을 그대로 돌려주고 `fetch_original(revision_id)` 는 삭제 여부를 보지 않는다(코드 확인). 초안 §4 가 「소비자가 권한을 확인해야 한다」로 이미 적었으나, 수정: 「historical 재생·revision fetch 는 감사 경로이며 응답 에이전트 evidence 조립에는 절대 사용하지 않는다」를 체크리스트 항목으로 승격.
4. **추출 지연 fence 의 구체화**: 「옛 version 이면 발행 거부」의 version 이 무엇인지 적는다. 제안: 추출 시작 시 `(projection revision_token, invalidation_epoch)` 를 캡처하고, memory 발행 시 core `add/update` 의 `expected_revision` 이 아니라 소비자 원장 트랜잭션 안에서 두 값을 재검사(둘 중 하나라도 변했으면 폐기·재추출).
5. 이벤트 축에는 `restore` 어휘가 없다(kind = create/edit/delete/close/reopen). 삭제 취소나 권한 재부여를 지원할지 U3.

### M3 (C) — eviction 게이트를 «raw durable» 과 «archive 사본» 으로 분리하라 [착수 전 필수]

- 관찰: §4 흐름은 「archive 사본/참조 + raw hash 확인 → manifest 전환 → 퇴거」인데, §3 는 「보존 확인된 오래된 창 참조만 퇴거」·「보존을 확인하지 못했다면 입력 속도 제한」이다. 채팅 입력에 backpressure 를 거는 것은 사용자 메시지를 거부한다는 뜻이라 실행 불가능하다.
- 수정(구현 가능한 형태):
  - **durable raw** = 로컬 세그먼트 seal(fsync + manifest hash) 완료. 이것은 «수신 ack 전 동기» 조건이다. 이게 실패하면 그때만 intake 오류.
  - **eviction 게이트** = durable raw 만 요구한다. archive(원격/콜드 사본)는 eviction 조건이 아니라 «별도 보존 정책의 목표» 다.
  - archive 실패 시: eviction 은 진행하되 세그먼트 상태를 `archive_pending` 으로 남기고, retention 이 archive 완료를 요구하는 세그먼트는 로컬 삭제 대상에서 제외한다(로컬 디스크 상한 초과 시 경보, 삭제 아님).
  - 활성 창이 N_active 를 넘는 유일한 경우는 「seal 미완료 tail」뿐이며, 이때 하드 상한(`N_hard = 2·N_active` 제안)을 넘으면 가장 오래된 «미봉인» 창을 «강제 seal» 한다(입력 거부가 아니다).
- 「보존 확인」의 정의를 한 줄로 고정: `sealed = manifest 기록 + 세그먼트 hash 재계산 일치 + fsync 완료`.

### M4 (D) — CDC commit 묶음의 «부분 가시성» 처리 방식과 ACL 실현 수단을 정하라

- 코드 확인: `api.add_batch/update_batch` 는 항목별 독립 `BEGIN IMMEDIATE`, 발행도 source 단위. 즉 한 DB 트랜잭션의 N 행은 N 개 source 로 나뉘어 «일부만 검색 가능한 순간» 이 존재한다. `search()` 의 scope 는 `source_keys(≤100)`·`media_types` 뿐이고 메타데이터 필터가 없어 소비자가 「그룹 완결 항목만」을 core 쿼리로 걸 수 없다.
- 초안은 이 한계를 정직하게 적었으나 «그래서 어떻게 할지» 가 없다. 세 가지 중 하나를 P08A-01 에서 결정:
  1. **수용**: 행 단위 소스 + `commit_group_id` 메타데이터, 소비자 측 post-filter 로 미완결 그룹 제외(recall 이 그룹 완결까지 지연됨을 문서화). core 변경 없음.
  2. **partition 단위**: 한 commit 이 건드리는 행이 같은 partition 이면 원자. 초안이 이미 비용을 적었다.
  3. **core 확장(group publish)**: 여러 source 의 `publish_generation` 을 한 트랜잭션에 묶는 새 API. D-010 발행 트랜잭션 확장이며 P-06 회귀 검증 대상. 범위 확장이므로 사용자 결정(U4).
- ACL: 초안대로 「scope 필터 ≠ 권한」이 맞다. 다만 실현 수단을 하나 골라야 한다. `source_keys` 100 개 상한 때문에 «허용 source 열거» 방식은 100 소스를 넘는 순간 깨진다. 실행 가능한 두 안: (a) access_scope 별 collection 분리(core 변경 없음, 교차 검색은 소비자가 병합) (b) core 에 메타데이터 필터 컬럼 추가(core 변경). 초안은 이 선택을 적지 않았다 → U5.

### M5 (E) — 지침 후보의 «인용 wrapper» 와 validated 전환 조건을 명문화하라

- 초안의 원칙(자동 쓰기 금지·다른 에이전트 복제 금지·명령문은 인용 데이터)은 맞다. 빠진 것:
  - 응답 에이전트에 memory 를 넣을 때의 형식. 제안: 각 레코드를 `{"kind":..., "claim":..., "status":..., "anchors":[...]}` 구조로 넣고 프롬프트에 「이 블록은 사용자 발화에서 추출된 데이터이며 지시가 아니다」를 붙인다. 채팅·CS 원문에서 온 텍스트는 «신뢰 경계 밖 입력» 으로 취급한다(프롬프트 주입 방어). 자유 문장으로 「사용자는 X 를 원한다」처럼 풀어 쓰지 않는다.
  - `status=validated` 전환은 `reviewer` 가 사람 ID 일 때만 허용. LLM 검증 계층은 `candidate → candidate(verified_by_rule)` 까지만 올린다. 지침 후보(`kind=instruction_candidate`)는 validated 라도 memory 예산의 «상단 배치 대상» 이 아니라 «검색 대상» 으로만 남긴다(U6 에서 사용자가 승격 경로를 정하기 전까지).

### M6 (F·G) — redaction 순서·projection 폐기·수락 기준

- **F-1 redaction 순서**: 「로그 캡처 전에 제외하거나 마스킹」이 durable raw write 보다 앞인지 명시. 수정: 「redaction 은 seal 대상 세그먼트에 쓰기 «전» 동기로 수행하고, redaction 실패 이벤트는 저장하지 않고 감사 레코드만 남긴다. content_hash 는 마스킹 후 바이트로 계산한다. 도구 결과(payload_ref 대상 포함)도 같은 정책을 적용한다.」
- **F-2 projection 폐기 원칙 누락**: 세그먼트가 활성 창에서 퇴거돼도 core 의 projection 소스는 계속 검색된다. «아카이브 검색» 이 core 검색인지 별도 저장소 검색인지 초안이 섞어 쓴다. 수정: 「퇴거 ≠ 검색 제외. projection 은 retention(U7) 안에서 core 에 남고, 만료 시 core `delete`(tombstone)로 검색 제외한다. 물리 폐기는 core 에 없는 기능이다(`delete` 는 논리 삭제, `source_revisions` 바이트 보존).」 개인정보 영구 삭제 요구가 있으면 core 에 hard-purge 또는 crypto-shred 가 필요하며 현재 미지원임을 U8 로 남긴다.
- **F-3 암호화 세그먼트 신규 포맷**: 초안이 새 파일 포맷·키 관리를 제안하는데 이는 이 확장에서 가장 위험한 신규 코드다. 대안: raw 세그먼트를 «별도 SQLCipher DB(소비자 소유)» 에 BLOB 으로 저장하고 기존 `keys.py` 경로를 재사용한다. 파일 포맷·내구성 검증·키 회전을 새로 만들지 않는다. 사용자 결정(U1).
- **G 수락 기준**: P07-04 방식(질문·정답 사전 고정)을 재사용해 최소 실험을 정의한다. 제안 지표와 «제안» 임계(승인 아님): 사전 고정 20 질의에 대해 archive evidence 검색 recall@3 ≥ 0.9 / 창 조립 p95 ≤ 500 ms(모델 호출 제외) / 턴당 주입 토큰 ≤ 12,000 예산 준수율 100 % / 요약·추출 비용 = 사건당 토큰 실측 보고. 기준선 = memory 층 없이 tail 만 넣은 동일 질의.

## 필수 체크리스트 (P08A 각 단계 통과 조건에 추가)

- [ ] memory·projection 의 저장 주체와 source_key 규칙이 DECISIONS 에 있다 (M1)
- [ ] 백업 복원 후 ledger 재적용 절차와 «검색 차단 창» 이 있고 M5 통합검증에서 재현한다 (M2-1)
- [ ] 같은 message_id 의 tombstone 이 낮은 sequence 의 늦은 create/edit 를 이긴다 — 순서 역전 테스트 (M2-2)
- [ ] historical replay / revision fetch 는 응답 조립 경로에서 호출되지 않는다 — 코드 grep 으로 확인 (M2-3)
- [ ] 추출 fence = (projection revision_token, invalidation_epoch) 재검사 (M2-4)
- [ ] eviction 조건 = sealed raw 만. archive 실패는 `archive_pending` 이고 입력을 거부하지 않는다 (M3)
- [ ] 강제 seal 하드 상한이 있고 «입력 거부» 경로가 없다 (M3)
- [ ] commit 묶음 부분 가시성 처리 방식 1/2/3 중 하나가 결정돼 있다 (M4)
- [ ] ACL 실현 수단(collection 분리 / core 메타 필터)이 결정돼 있고 `source_keys` 100 상한을 우회하지 않는다 (M4)
- [ ] memory 주입 wrapper 가 구조화 데이터 + «지시 아님» 표시이고, validated 는 사람 reviewer 만 (M5)
- [ ] redaction 이 durable write 앞이며 도구 결과에도 적용, hash 는 마스킹 후 (M6 F-1)
- [ ] projection retention 과 tombstone 시점이 정의돼 있다 (M6 F-2)
- [ ] raw 저장이 신규 파일 포맷이 아니라 SQLCipher 재사용인지 결정돼 있다 (M6 F-3)
- [ ] 수락 기준이 사전 고정 질의·기준선·임계와 함께 P08A-01 에 기록돼 있다 (M6 G)
- [ ] 초안이 밝힌 대로 `explicit_consumer.py` 에 reindex 분기가 없다 — 새 consumer 는 reindex 를 명시 이벤트로 추가한다
- [ ] 초안 §5 가상 예시가 실제 수집·저장 결과로 오독되지 않도록 문서 상단 표시 유지

## 권장 인덱스 배치 (H)

**메인 제안 채택 가능: P-08 과 P-09 사이에 P-08A 신설, 신규 코드는 core 가 아니라 sibling `feature-pack/rag-consumer/`(아직 생성 안 함) 외부 계층. 조건 4.**

1. **DECISIONS 신규 항목(D-014 제안)** 으로 「범위 확장: 데이터 생애주기 소비자 계층 `rag-consumer/`」 를 사용자 결정으로 기록한다. D-002 는 워처·스케줄·트리거를 소비자 몫으로 정했고 이번 확장은 «그 소비자 계층의 표준 구현을 sibling 패키지로 추가» 하는 것이므로 D-002 의 대체가 아니다. core(`feature-pack/rag/`)에 워처·큐·메모리 코드를 넣지 않는다는 경계를 같은 항목에 적는다. 이 기록 없이 P08A 를 PLAN 에 넣으면 P09-01 요구 범위 대조에서 근거가 끊긴다.
2. **P09-01 문구 수정**: 「원래 범위(P-01~P-08)와 확장 범위(P-08A)를 «각각» 대조하고 각각의 완료 근거를 별도로 적는다」. 두 범위를 한 판정으로 뭉치면 확장 지연이 원 범위 완성 근거를 가린다.
3. **core 변경이 필요한 항목은 사전 분리**: M4 선택지 3(group publish)·ACL 안 (b)(메타 필터)·hard purge(U8) 중 하나라도 채택되면 그 항목은 `rag-consumer/` 가 아니라 「P-06 회귀 게이트를 통과하는 core 변경」으로 표시하고 P08A-01 에서 확정한다. P08A-02~07 은 core 변경 없이 진행 가능해야 한다.
4. **fixture 통과 ≠ 생산 완료**: 메인 보완대로 실제 서비스가 지정되지 않은 어댑터(문서 connector·CDC·채팅 수집)는 합성 fixture 통과만으로 «완료» 라 적지 않는다. P08A-02~06 의 완료 조건에 「합성 fixture 검증 완료(생산 connector 미지정)」 표기를 두고, P08A-08 에서 사용자가 실제 connector 를 선택한 뒤에만 «생산 완료» 로 바꾼다. P09-01 확장 범위 대조는 이 구분을 그대로 옮긴다.

메인이 제시한 P08A-01~08 순서와 이 리뷰의 대응:

| 항목 | 메인 내용 | 이 리뷰의 선행 조건 |
|---|---|---|
| P08A-01 | 계약/정책 확정 | B1~B3 해제 + M4~M6 확정 + U1~U9 결정(임의 승인 금지) + D-014 |
| P08A-02 | 자료 consumer | reindex 명시 이벤트 포함, T12 예제 상속 |
| P08A-03 | event/암호화 segment | U1(신규 포맷 vs SQLCipher 재사용) 결정, redaction 이 durable write 앞(M6 F-1) |
| P08A-04 | 수정·삭제 projection + N 윈도우 | tombstone 우선(M2-2)·강제 seal(M3)·추출 fence(M2-4) |
| P08A-05 | 근거 기억·우선순위 | 저장 주체(B1)·wrapper·validated 조건(M5)·pin overflow |
| P08A-06 | archive/checkpoint | `archive_pending`(M3)·백업 복원 재대조(M2-1)·projection retention(M6 F-2) |
| P08A-07 | 장애/권한/비용 통합 | 체크리스트 전체 + 경합 6종 재현 + G 수락 기준(사전 고정 질의·기준선) |
| P08A-08 | 실제 선택 connector + 사용자 시연 | 조건 4 의 «생산 완료» 전환은 여기서만 |

T08~T13 독립 진행: 가능하다. 단 T12(명시 이벤트 소비자)는 P08A-02 가 같은 예제를 확장하므로 T12 를 먼저 끝내고 P08A-02 가 그 결과를 상속하는 순서를 권장한다. 메인이 PLAN 의 오래된 「retry/reindex/backup 미구현」 요약을 최신 완료 근거에 맞게 정정한다고 했으므로 이 리뷰는 초안 §근거 마지막 항목의 「완료 항목 기준 해석」 을 그대로 인정한다.

**대안(참고, 비권장)**: P-09 를 원 범위만 판정하고 확장을 P-11 로 두는 안. 완성 판정을 빨리 닫을 수 있으나 매거진(P-10)이 두 번 필요해지고 사용자 요구(「기획 완성 공유와 개발 인덱스 배치」)가 하나의 완료 흐름을 전제하므로 메인안이 더 맞다.

## 미결 사용자 정책·설정 (임의 승인 금지 — P08A-01 착수 조건)

| ID | 결정 필요 사항 | 초안의 현재 표현 |
|---|---|---|
| U1 | raw 세그먼트 저장 방식: 신규 암호화 파일 포맷 vs 소비자 소유 SQLCipher DB 재사용 | 신규 포맷 제안 |
| U2 | memory 레코드를 core 소스로 둘지(검색 가능) vs 소비자 원장만(규칙 배치) | 미정 |
| U3 | 이벤트 축의 삭제 취소·권한 재부여 지원 여부 | 어휘 없음 |
| U4 | CDC commit 묶음 처리: 수용(post-filter) / partition 단위 / core group publish | 한계만 명시 |
| U5 | ACL 실현 수단: access_scope 별 collection 분리 vs core 메타 필터 추가 | 미정 |
| U6 | 지침 후보의 승격 경로(사람 검토 후 어디에 어떤 형식으로 두는가) | 「사용자 검토」만 |
| U7 | projection·세그먼트 retention 기간, 프로젝트 간 공유 범위, 백업 만료 | 초안 §8-4 질문 그대로 |
| U8 | 개인정보 영구 삭제 요구 시 core hard-purge/crypto-shred 신설 여부 | 미지원 명시만 |
| U9 | 첫 소비 대상(에이전트 채팅만 vs CS 동시), N_active=4·12,000 tokens 로 합성 실험 시작 여부 | 초안 §8-1·2 |

## 초안에서 확인된 정확한 서술 (수정 불요)

- core 는 워처·폴링을 갖지 않고 명시 요청만 처리한다(D-002, `explicit_consumer.py` 관측 이벤트 무시 분기 확인).
- 삭제 소스에 add 가 아니라 restore 를 요구한다(코드 `ALREADY_EXISTS_DELETED`).
- `expected_revision` 은 콘텐츠 해시가 아닌 상태 CAS 토큰이며 delete/restore 사이클 뒤 stale 이다(D-009).
- FTS5 는 발행 트랜잭션에서만 insert/delete 되어 미발행 세대가 순위를 오염시키지 않는다(D-010).
- 벡터 검색은 O(N) 전수 비교이며 초대형 규모는 별도 검증 대상이다.
- `explicit_consumer.py` 에는 reindex 분기가 없다(코드 확인).

---

## 재검토 (2차) — 최종안 `data-lifecycle-plan.md` v1.0 + PLAN P-08A

- 검토자: ft-airag-da-fable51#0 (Fable 5.1, `--model claude-fable-5-1 --effort high`, 표준 창). Serena 미노출, grep/sed 직독.
- 대상: `data-lifecycle-plan.md` §2/3/4/5/6/7/8/10/12, `PLAN.md` P-08A 절(151~170행). 코드 재대조: `backups.copy_database`(DESTINATION_EXISTS 거부·counts 반환·manifest 파일 없음), `store.add/delete/restore/reindex`, `api._run_batch`, `search.validate_scope`.
- 새 구현·모델 호출·설정 변경 없음. 초안·최종안·PLAN·DECISIONS 수정 없음.

### 최종 판정: **PASS (기획 완성 · 개발 착수 기준)**

기획 문장에 남은 blocker 는 **0건**이다. 1차 blocker B1~B3 는 아래와 같이 해제됐음을 확인했다. 아래 「비차단 정합 항목」 6건은 착수를 막지 않으며 P08A-01 닫는 증거 또는 PLAN 인덱스 손질로 흡수하면 된다.

### 1차 리뷰의 사실 정정 수용 (메인 지적 2건, 코드로 재확인)

| 1차 리뷰 표현 | 정정 | 근거 |
|---|---|---|
| 「백업 복원은 DB 파일 전체 교체」 | core `restore-backup` 은 **새 경로**에 복원하며 기존 DB 를 덮어쓰지 않는다. 소비자가 그 DB 로 «전환» 할 때 백업 이후 사건이 빠지는 것이 실제 위험이다 | `backups.copy_database` 가 destination 존재 시 `DESTINATION_EXISTS` 로 거부 |
| 「복원 뒤 CAS 토큰은 전부 stale」 | 보장 없음. `source_id/state_version` 이 우연히 일치할 수 있어 소비자 `restore_epoch` 로 분리해야 한다 | 토큰 = `base64("v1:<source_id>:<state_version>")`(D-009), DB 별 카운터라 충돌 가능 |

1차 B3 의 「채팅 입력에 backpressure」 표현도 최종안 §6 의 「durable write 실패 = 수집 cursor 정지, 원래 채팅 거부 아님」이 더 정확하다. 수용한다.

### B1~B3 해제 확인

| # | 확인 위치 | 판정 |
|---|---|---|
| B1 저장 주체 | §2 표 7행: projection·memory 본문 = core 소스(`session/…/view`, `memory/<memory_id>`), 이벤트 원장·후보·상태·활성 창 = 소비자 SQLCipher 원장. 「원장 검증이 끝나지 않은 core 결과는 응답으로 내보내지 않는다」로 권위 위치 명시 | 해제 |
| B2 복원·tombstone | §7 복원 8단계(read gate 닫기 → restore_epoch → applied offset 대조 → 외부 원장 재적용 → tombstone 규칙 재적용 → watermark 뒤 gate 열기), 재적용 request_id = `(event_id, operation, projection_version, restore_epoch)` 결정적. §4 「tombstone 보다 낮거나 같은 버전의 create/edit 는 늦게 와도 부활 못함, 더 높은 버전이 와도 별도 restore 사건 필요」. §5 4값 fence `(projection revision, source_version, invalidation_epoch, access_policy_epoch)` | 해제 |
| B3 eviction 게이트 | §6 조건 4개(durable commit → 봉인+manifest/hash/fsync → 새 참조 집합 원자 확정 → 옛 참조 제거), 원격 복제는 `archive_pending` 별도 목표, 창 초과 시 조기 seal, durable 실패 = cursor 정지 | 해제 |

M4~M6 도 최종안에 반영됐다: M4 = §3 dataset read-gate 기본안 + 가용성 대가 명시 + §7 scope 별 collection + facade 인증(100-ID 필터 회피). M5 = §5 `candidate → rule_checked → human_validated / rejected`, 데이터 레코드 wrapper, 자동 승격 경로 없음. M6 = §8 저장 전 redaction(도구 결과 포함, hash 는 마스킹 후), §2 SQLCipher 재사용, §7 projection retention·물리 삭제 미지원 명시, §10 사전 고정 수락 실험. 정책값(N=4·12,000 tokens·세그먼트 임계·recall 0.9·p95 500 ms)은 §4·§10·§11 에서 「제안·사용자 미승인」으로 일관되게 표시됐다.

### 비차단 정합 항목 (착수 전 손질 권장, 판정에 영향 없음)

1. **PLAN P-08A 서두가 초안만 가리킨다**(153행 `data-lifecycle-draft.md`). 최종안 §10 은 「정본은 PLAN」이라 하고 PLAN 은 초안을 기준으로 적어 순환이 초안에서 끊긴다. 서두 링크를 `data-lifecycle-plan.md`(기획 정본) + 이 리뷰로 바꾸고 초안은 이력으로 남긴다.
2. **PLAN 「실행 순서」 표(1~9행)에 P-08A 행이 없다.** P-08 과 P-09 사이에 「P-08A 확장 개발 · 기획 완료(DA PASS) · 구현 미착수」 행을 추가해야 P09-01 대조가 표에서 시작된다.
3. **P09 연동 문구 「기존 P08 과 새 P08A 의 완료 근거를 함께 대조」**(168행)는 「각각 대조하고 각각 기록」으로 바꾸기를 권장한다. «함께» 는 두 범위를 한 판정으로 읽힐 수 있고, 최종안 §10 자체는 이미 「각각 대조」라고 적었다.
4. **D-014(범위 확장 사용자 결정) 가 DECISIONS 에 아직 없다.** 1차 조건 1 그대로다. P08A-01 닫는 증거 첫 항목으로 「D-014 기록」을 넣으면 된다. 기획 완성 판정에는 영향 없다.
5. **「backup manifest」 의 실체**: core `copy_database` 는 manifest 파일을 쓰지 않고 검증 counts 만 반환한다(코드 확인). §7 의 「backup manifest 와 소비자 원장의 receipt 매핑에 checkpoint 저장」은 «소비자가 백업 파일 해시·생성 시각을 키로 자기 원장에 쓰는 레코드» 임을 P08A-01 계약에 한 줄로 못 박아야 한다. 그렇지 않으면 구현자가 core 에 manifest 출력을 추가하려 들 수 있다(core 변경 = 조용한 범위 확장).
6. **세그먼트 SQLCipher 파일의 키 소유**: §2 는 「검증된 SQLCipher 형식 재사용」까지만 적었다. core DB 키와 같은 키인지 소비자 별도 키인지, 세그먼트당 파일인지 단일 원장 DB 의 BLOB 인지를 P08A-01 에서 확정한다(P08A-03 선행 조건).

### 2차 절 작성 직후 확인된 반영 상태 (메인이 같은 시각에 PLAN·DECISIONS 갱신)

- 항목 1 해소: PLAN P-08A 근거 줄이 D-014·`data-lifecycle-plan.md`·이 리뷰를 가리킨다(154행).
- 항목 2 해소: 실행 순서 표에 「7A · P-08A · 기획 DA 재검토 중·개발 미착수」 행이 있다. 이 리뷰 판정 뒤 상태를 「기획 완료(DA PASS)·개발 미착수」로 바꾸면 된다.
- 항목 4 해소: DECISIONS D-014 가 사용자 요청·sibling 배치·D-002 비대체·P09 각각 대조를 기록했다.
- 항목 3 잔존: PLAN 169~170행은 여전히 「완료 근거를 함께 대조」다. D-014 본문은 「각각 대조」라 두 문서가 어긋난다. PLAN 쪽을 「각각」으로 맞추기를 권장한다.
- 항목 5·6 잔존: P08A-01 계약에서 확정.

판정은 변하지 않는다: **PASS, 남은 blocker 0건.**

### 범위 밖 확인

- 사용자 요청의 ELI5 HTML 매거진은 이 리뷰 대상이 아니다. D-004 선례대로 「매거진 통과 ≠ 엔진·소비자 계층 검증」이며 최종안 §12 마지막 문장이 이미 그렇게 적었다.
- 기존 T08~T13 core 투어의 독립 진행에 이 판정은 영향을 주지 않는다.

---

## 재검토 (3차) — 기획 v1.1 + P08A-01 계약 초안(`p08a01-contract.json` 0.1 · preflight)

- 검토자: ft-airag-da-fable51#0 (Fable 5.1, `--model claude-fable-5-1 --effort high`, 표준 창). Serena 미노출, grep/sed·python 직독.
- 대상: `data-lifecycle-plan.md` v1.1(§1.1·§4.1·§4.2·§12·§13), `p08a01-contract.json`(input·event·storage·window·core_bridge·memory·C01~C14, 메인의 세 차례 갱신 반영본), `p08a01-contract-preflight.json`, `PLAN.md` P-08A. 코드 대조: `normalize._build_conversation`, `search._resolve_eligible_sources`, `chunking` 앵커 전파.
- 지정 입력 실측(읽기 전용·본문 미출력): rollout JSONL 레코드 유형 분포·`session_meta.id`·assistant phase 집합·user 메시지 선두 태그 분포·`compacted` 레코드 위치와 키·`tour-session.json` 의 source 17개. reasoning/system/developer 본문은 읽지 않았고 구조 메타만 셌다.
- 새 구현·모델 호출·설정 변경 없음. 리뷰 파일만 편집.

### 판정: **조건부 PASS (구현 착수 기준) — 계약 문장에 남은 blocker 3건, 전부 계약 JSON·§13 수정으로 해제 가능**

v1.1 추가 요구(JSONL → 윈도우 → 기존 Docling/HybridChunker, 최근 N 밖 이력 검색, memory 없이 검색, 원문 anchor, 수정·삭제·권한 gate, raw SQLCipher)는 기획·계약 양쪽에 반영됐고 core 코드와 어긋나는 주장이 없다. 사용자 선택(현재 세션 rollout + 투어 DB 17 source)은 계약 input 에 exact path·session_meta ID·allowlist 쌍으로 고정됐다. 남은 blocker 는 «어디에 무엇으로 발행하는가» 와 «접근 범위 값» 이 계약에 비어 있는 것 3건이다. 운영 정책값은 임의 승인하지 않았다.

### Blocker (P08A-02/03 착수 전 계약에 채울 것)

| # | blocker | 왜 막히는가 | 구체 수정 |
|---|---|---|---|
| B4 | **projection 발행 대상 DB·collection 미지정.** 계약 어디에도 윈도우 문서를 넣을 core DB 경로와 collection 이름이 없다. 투어 DB 는 `read_mode=open_readonly`·`source_mutation=never` 라 발행 대상이 될 수 없고, 그러면 P08A-04 가 «새 DB 를 만들 것인가, 투어 DB 에 쓸 것인가» 를 스스로 정하게 된다 | 투어 DB 에 쓰면 T08~T13 투어의 DB 정합성(source 17개·manifest 번호)이 깨지고, 새 DB 면 「기존 문서와 같은 공간에서 통합 검색」(§4.1)이 그 DB 안에서는 성립하지 않는다 | `core_bridge` 에 `projection_db: "<새 경로, 투어 DB 와 다름>"`, `projection_collections: {"session": "conv-<stream>", "tour_mirror": null}` 추가. 투어 문서는 «읽기 대조 원천» 이며 재발행하지 않음을 명시(`tour_documents.republish: false`). 통합 검색 실험은 P08A-07 에서 «두 DB 결과의 병합» 으로 정의하거나 U 항목으로 남긴다 |
| B5 | **선택 입력의 `access_scope` 값 미배정.** `event.required` 에 `access_scope` 가 있고 합성 JSONL 은 `{tenant_id, project_id}` 를 갖지만, rollout 어댑터 매핑에는 access_scope 배정 규칙이 없고 tour_documents 에도 없다 | C09(권한 철회)·§7 facade 검사·다근거 교집합이 전부 이 값 위에서 동작한다. 비어 있으면 구현자가 상수를 박거나 검사를 건너뛴다 | `adapter_mapping.access_scope: {"tenant_id": "<사용자 지정>", "project_id": "airag-rag-transplant", "stream_scope": "session:<session_meta.id>"}` 와 `tour_documents.access_scope` 를 각각 명시. 값 자체는 사용자 승인 항목이므로 `pending_user_value` 로 두되 «필드 존재와 검사 지점» 은 계약에 고정 |
| B6 | **처리 프로필·redaction 정책 버전이 이름으로 고정되지 않았다.** `profile_selection = must_match_verified_installed_profile_no_implicit_fallback` 은 원칙이지 값이 아니다. `event_id` 해시 규칙이 `pinned_redaction_policy_version` 을 포함하는데 그 버전 식별자·규칙 목록이 계약에 없다 | 프로필 키가 없으면 P08A-04 가 어떤 embedding space 에 넣을지 정할 수 없고, redaction 버전이 없으면 C14 를 검증할 기준이 없다. 둘 다 replay fingerprint 에 들어가므로 나중에 바꾸면 C01(동일 사건 재생) 판정이 흔들린다 | `core_bridge.profile_key: "<투어 프로필 중 대화 호환 키 하나 또는 신규 등록 키>"` 를 명시(투어 `tour-session.json` 의 profile 목록에서 고른다). `storage.redaction_policy: {"version": "r1", "rules": ["api_key_like", "bearer_token", "private_key_block", "<user_shell_command> 태그 블록 전체"], "on_failure": "reject_record"}` 추가. 실측: user 메시지 72건 중 `<user_shell_command>` 선두 4건·`<environment_context>` 선두 7건이 있어 «주입 태그 블록» 을 마스킹 대상인지 제외 대상인지 정해야 한다 |

### 실측으로 확인된 정확한 항목 (계약과 일치)

- `session_meta.id` 1건, 계약 `session_id` 와 일치. `response_item.message` 266건 = user 72 / assistant 179 / developer 15. assistant phase 집합 = `{commentary, final_answer}`, 계약 `allowed_assistant_phases` 와 일치(메인 보정 반영 확인). `final` 은 0건.
- 제외 대상 레코드 실재: `event_msg` 2279·`reasoning` 443·`world_state` 13·`turn_context` 48·`compacted` 1(4209행)·`inter_agent_communication_metadata` 44. 계약 `excluded` 목록이 실제 유형을 빠짐없이 덮는다. 부분 줄 0건.
- 도구 payload 는 `custom_tool_call(_output)` 468쌍·`function_call(_output)` 42쌍. 계약대로 «검증 전 제외» 가 맞다. 짝 매핑 키는 `call_id` 로 존재한다(본문 미확인).
- user 메시지 최대 6,434자, 20k 초과 0건 → 윈도우 40 events/2,000 tokens 기본값에서 «단일 메시지가 창을 넘는 경우» 는 이 입력에서는 드물지만, `<environment_context>` 블록은 반복 주입이라 중복 제거 규칙(§4.1 「원본 message ID/범위로 중복 제거」)이 여기서도 적용돼야 한다.
- 투어 DB: `tour-session.json` 의 `sources_and_latest_revision_tokens` 17개, `library-ko.txt` 는 `revision_id 19 / generation 23` 으로 T07 갱신 이후 head 다. 계약 `source_authority = current_non_deleted_head_revisions_not_old_T03_generator_literals` 가 정확하다.
- 대화 어댑터: `turns[i].id` 가 `conversation_turn` 앵커 `turn_id` 로, 위치가 `/turns/{i}/text` 로 보존되고 청킹까지 `turn_id` 가 전파된다(코드 확인). 빈 본문 turn 은 청크를 만들지 않는다. 시각·권한·revision 은 core 앵커에 없다는 계약 서술도 맞다(`OriginalAnchor` 필드 = kind/original_text/pointer/turn_id).
- 검색 scope 는 `source_key IN (...)` + `deleted_at_ms IS NULL` + `status='ready'` 의 SQL pre-filter 다. 「core 가 임의 메타 필터를 지원한다고 가정하지 않는다」(§4.1)와 일치한다.

### 비차단 정합 항목 (P08A-01 마감 전 손질 권장)

1. **`compacted` 레코드 이후 재개 규칙**: rollout 4209행에 `compacted` 가 있고 그 뒤 567행이 이어진다. 계약은 compacted 를 «제외» 만 한다. 「compacted 전후 메시지는 같은 stream 의 연속 ordinal 로 취급하며 `replacement_history` 본문은 절대 사건으로 만들지 않는다」 1문장을 adapter_mapping 에 추가. 그렇지 않으면 구현자가 압축 요약을 «assistant 메시지» 로 오독할 수 있다.
2. **checkpoint 3값의 우선순위**: `checkpoint = file_incarnation + next_byte_offset + ordinal_prefix_integrity + policy_version` 인데 «어느 값이 불일치하면 halt 인가» 가 없다. 제안: incarnation·policy_version 불일치 = halt+reconcile, byte_offset 만 뒤로 간 경우(파일 축소) = halt, ordinal 비단조 = 해당 레코드 quarantine 후 전진.
3. **윈도우 «닫힘» 과 rollout 의 «끝» 관계**: 이 세션은 아직 쓰이는 파일이다. 마지막 열린 윈도우가 30분·40 events 조건에 걸리지 않으면 검색에 안 들어간다. P08A-04 닫는 증거에 「사용자 시연 직전 명시 flush 로 tail 을 닫는다」 를 넣어 C05(10창 중 4 활성) 시험이 열린 tail 을 포함하지 않게 한다.
4. **`edit/delete/restore/grant/revoke` 사건의 «권위 채널» 실체**: rollout 어댑터는 create-only 다. 계약 `types` 에 6종이 있으나 이 입력에서는 create 만 나온다. C04·C09·C12 는 «합성 correction 채널» 로만 검증 가능함을 preflight `not_verified` 또는 C04/C09/C12 의 `input` 필드에 적는다. 실제 correction 채널이 없으면 P08A-08 시연에서 수정·삭제 순환은 «합성 주입» 임을 표시.
5. **`retrieval_top_k=5` 와 `recall@3`** 은 계약에 있으나 «기준선(tail-only)» 질의 20건이 아직 없다. P08A-07 착수 조건으로 질의 파일 경로를 계약에 예약(`acceptance.fixed_queries: null → 경로`).
6. **PLAN 7A 행 상태 문구** 「v1.1 JSONL·기본 이력 검색 요구 반영·개발 미착수」는 이 판정 뒤 「v1.1 DA 조건부 PASS(B4~B6 계약 보완 후 착수)·개발 미착수」로 갱신.

### 미결 사용자 정책 (임의 승인 금지 · 추가분만)

| ID | 결정 필요 | 현재 계약 표현 |
|---|---|---|
| U10 | projection DB 경로와 통합 검색 방식(별도 DB 병합 vs 투어 DB 공유) | 미지정(B4) |
| U11 | 선택 입력의 tenant_id/project_id 실제 값 | 미지정(B5) |
| U12 | `<user_shell_command>`·`<environment_context>` 주입 블록을 마스킹/제외/보존 중 무엇으로 할지 | 미지정(B6) |
| U13 | 소비자 SQLCipher 키 제공자(`key_provider: null`)·회전·복구 | `pending_deployment_policy` |
| U14 | 응답 모델 tokenizer 선정(정확 계수 모드 전제) | `requires_selected_response_model_tokenizer` |

기존 U1~U9 중 U1(raw 저장 = SQLCipher 재사용)·U2(memory = core 소스)·U5(scope 별 collection + facade)·U9(첫 입력)는 v1.1·계약으로 결정됐다. U3·U4·U6·U7·U8 은 그대로 남는다.

### 범위 밖 확인

- preflight 의 `existing_normalize_tests 26 passed` 는 기존 어댑터 회귀이며 소비자 계층 검증이 아니다. preflight 자체가 `not_verified` 에 이를 적었다.
- ELI5 매거진은 이 검토 대상이 아니다.

---

## 재검토 (4차) — B4~B6·비차단 대응 반영 최종 확인

- 검토자: ft-airag-da-fable51#0 (Fable 5.1, `--model claude-fable-5-1 --effort high`, 표준 창). Serena 미노출, python/grep 직독.
- 대상: 갱신된 `p08a01-contract.json`(input.session_identity·tour_documents·storage.redaction_policy·core_bridge·window), `data-lifecycle-plan.md` §13 「3차 DA 대응 — B4~B6」, `p08a01-contract-preflight.json`(selected_profile_readonly_probe 추가본), `PLAN.md` 7A 행. 대조: `tour-session.json` 의 profiles 19건과 `T03-effective-text-profile.json`(읽기 전용, 키·본문 미출력).
- 새 구현·모델 호출·설정 변경 없음. 리뷰 파일만 편집.

### 최종 판정: **PASS (운영 미결을 명시한 구현 계약 기준 · P08A-02/03 착수 가능)**

3차 blocker B4~B6 은 계약 JSON 과 §13 양쪽에서 필드 단위로 해제됐다. 비차단 6건도 계약 필드 또는 §13 문장으로 들어갔다. 남은 것은 «사용자 운영값» 뿐이며 계약이 그 미확정 상태를 «거부 동작» 으로 명시해 임의 승인 없이 구현이 진행되도록 만들어졌다. 이 판정은 계약 문장에 대한 것이지 C01~C14·H01~H20 의 실행 통과가 아니다. preflight 가 `not_verified` 에 이를 그대로 적었다.

### B4~B6 해제 확인 (필드 단위)

| # | 확인된 계약 필드 | 판정 |
|---|---|---|
| B4 | `core_bridge.projection_db = …/p08a/projections.db`(`planned_not_created`), `projection_collections = {session: airag-session-v1, memory: airag-memory-v1, tour_mirror: null}`, `consumer_ledger_db = …/p08a/consumer.db`, `tour_documents.republish = false`. §13: 두 DB 결과는 «구분된 결과 그룹» 이며 전역 순위·원자 snapshot 을 주장하지 않음. 대상 DB 별 키 제공 전 생성 거부 | 해제 |
| B5 | session·tour 양쪽 `access_scope = {tenant_id: pending_user_value, project_id: airag-rag-transplant, stream_scope: session:<id> / tour:<id>, unresolved_value: reject_real_ingestion_and_search_no_default_tenant}`. `core_bridge.scope_check_points` 4곳(수집 전·검색 전·문맥 확장 전·응답 직전). 입력이 보내온 scope 는 신뢰하지 않음 | 해제 (값은 사용자 승인 대기, 미확정 = 거부) |
| B6 프로필 | `profile_key = cb98…1633c`, `profile_basis = registered_tour_conversation_profile_readonly_verified_no_provider_call`, `target_profile_gate = 새 DB 에 동일 descriptor 등록 → 같은 fingerprint·대화 호환 확인 후 발행, fallback 없음`. 실측: 이 키는 투어 `text` 프로필이며 conversation.json 을 포함한 18개 source 가 같은 키·space_id 1 을 쓴다 | 해제 |
| B6 마스킹 | `storage.redaction_policy.version = airag-local-redaction-r1`, injected_blocks 2종 = balanced 블록 통째 typed placeholder / unbalanced = reject, secret_rules 5종, `on_failure = reject_record_before_durable_write_no_ack`, audit_fields 에 removed_text·secret_values 제외, `policy_change = 새 파생 projection 버전 + 명시 재처리`. `status = implementation_contract_not_runtime_validated` 로 정직하게 표시 | 해제 |

### 비차단 6건 반영 확인

| 3차 항목 | 계약·문서 위치 | 상태 |
|---|---|---|
| 1 compacted 이후 재개 | `compaction_rule = skip_compacted_record_and_any_embedded_replacement_history_continue_verified_original_file_offsets` | 반영 |
| 2 checkpoint 우선순위 | `checkpoint_priority = [세션·파일 incarnation·prefix 무결성 → committed byte offset 재개 → ordinal 단조·event_id dedup]` | 반영 |
| 3 시연 전 flush | `before_live_demo = explicit_flush_close_window_seal_raw_wait_for_searchable_then_query` | 반영 |
| 4 correction 합성 표기 | `correction_demo = synthetic_authoritative_correction_injection_only_not_live_rollout_edit_delete_support` | 반영 |
| 5 기준선 질의 예약 | §13: H01~H20 5범주×4, 질의·기대 message ID·허용 범위·정답 revision 동결 조건. 계약 JSON 에는 아직 필드 없음 | 문서 반영 · JSON 은 P08A-07 착수 시 추가하면 됨 |
| 6 PLAN 7A 문구 | 「P08A-01 진행·v1.1 3차 DA 지적 대응·구현 미착수」 | 이 판정 뒤 「v1.1·계약 DA PASS(운영값 미결)·구현 미착수」 로 갱신 권장 |

### 관찰 (판정 무관 · P08A-02/04 구현자가 알아야 할 것)

- 고정 프로필 `cb98…1633c` 는 임베딩만이 아니라 **LLM enrichment(의미 그룹·태그·요약·영어 번역)** 를 포함한다(`T03-effective-text-profile.json` 에 `llm` 절 존재). 따라서 윈도우 문서 발행은 «LLM 호출 + 임베딩 호출» 이고, C07(`embedding_failure_and_retry`)의 실패 지점은 둘 중 어느 쪽이든 «이전 ready 유지 + 부분 발행 없음» 이어야 한다(D-011 계약 그대로). C07 의 case 이름을 `provider_failure_and_retry` 로 넓히거나 설명에 LLM 단계를 포함하기를 권장한다. blocker 아님.
- 같은 이유로 대화 윈도우 하나의 발행 비용은 문서 하나와 같은 자릿수의 LLM 토큰이 든다. §10 「사건당 토큰·호출 수 실측」 항목이 이를 덮는다.
- `<environment_context>`·`<user_shell_command>` 블록을 placeholder 로 바꾸면 그 user 메시지의 «남는 공개 텍스트» 가 비어 있을 수 있다(실측 선두 태그 11건). 어댑터가 빈 turn 을 청크로 만들지 않는 것은 코드로 확인됐으니, 이 경우 «message_id 는 원장에 남고 projection 에는 turn 이 없음» 이 정상 동작임을 C14 기대값에 한 줄 적어 두면 구현자의 «누락» 오판을 막는다.

### 미결 사용자 정책 최종 목록 (임의 승인 없음)

U3 이벤트 축 restore/권한 재부여 지원 · U4 CDC 묶음 처리 · U6 지침 후보 승격 경로 · U7 retention/공유/백업 만료 · U8 hard purge · U11 tenant_id 실제 값 · U13 소비자 SQLCipher 키 제공자·회전·복구(대상 DB 별 키 포함) · U14 응답 모델 tokenizer. U10(projection DB 방식)·U12(주입 블록 처리)는 계약으로 결정됐다(별도 DB 그룹 병합 · placeholder 치환). 이 목록이 비어야 P08A-08 «생산 완료» 이며, 비어 있지 않아도 P08A-02~07 합성 fixture 구현은 진행 가능하다.

---

## 코드 리뷰 (5차) — `feature-pack/rag-consumer/src/airag_consumer/{events,jsonl,conversation}.py` + tests

- 검토자: ft-airag-da-fable51#0 (Fable 5.1, `--model claude-fable-5-1 --effort high`, 표준 창). Serena 미노출, 직독 + 실행 검증.
- 대상: 3개 모듈(events 149줄·jsonl 65줄·conversation 48줄), tests 4파일, `pyproject.toml`. 기준: 4차 PASS 계약 `p08a01-contract.json` 0.1 + `normalize._build_conversation` 접점.
- 실행: `../rag/.venv/bin/python -m pytest -q` → **44 passed (0.68 s)**. 추가로 7개 가설을 스크립트로 실측했다(아래 P1~P7). 코드·계약·테스트 어느 것도 수정하지 않았다.
- 경계 인정: 이 3모듈은 «검증·파싱·직렬화» 만 하는 순수 어댑터다. 원장·redaction·checkpoint 내구성·correction 축약·권한 gate 는 docstring 이 명시적으로 «하지 않는다» 고 적었고, 나는 그것을 완성으로 세지 않았다.

### 판정: **조건부 PASS — blocker 2건(계약 위반), 수정 권고 5건. 원장 구현 착수는 blocker 2건 해소 후.**

계약에서 잘 지킨 것이 많다: 입력이 자기 scope 를 고를 수 없음(`expected_scope` 강제, `pending_` 거부), 중복 JSON 키·NaN·미지원 필드·타임존 없는 시각 거부, replay fingerprint 에서 `ingested_at` 제외 + redaction 버전 포함, 부분 UTF-8 tail 미커밋, CRLF 포함 바이트 offset, 오류에 원문 미노출, 빈 본문은 turn 0 + 이벤트 보존(C14 대응), `turn_id` 가 실제 Docling 앵커까지 도달. 아래는 그 위에서 남은 «실제 결함» 이다.

### Blocker (계약 위반)

**K1 — `role: "tool"` 이 검증을 통과해 본문이 그대로 core turn 이 된다** (`events.py:130`, `conversation.py:45`)
- 실측 P3: `{"role":"tool","content":"raw tool output with token=SECRET"}` → `parse_event` 통과 → `create_only_conversation` 이 `{"role":"tool","text":"…SECRET"}` 를 core 페이로드로 직렬화.
- 계약: `session_identity.allowed_roles = [user, assistant]`, `tool_payloads = disabled_until_redaction_and_pair_mapping_verified`. 4차 판정은 «도구 본문은 마스킹·짝 매핑 검증 전 제외» 를 전제로 PASS 였다.
- 왜 blocker 인가: redaction 이 아직 없는 지금, 이 경로가 열려 있으면 원장 구현자가 «파서가 받아 줬으니 저장한다» 로 흐른다. 이 모듈이 정확히 «입력 검증» 담당이므로 여기서 막아야 한다.
- 수정: `events.py:130` 허용 집합에서 `tool` 제거(또는 `parse_event(..., allowed_roles=frozenset)` 인자로 받아 `conversation.py` 가 `{user, assistant}` 외를 `UNSUPPORTED_ROLE_FOR_CONVERSATION` 로 거부). `customer/support` 는 CS 계약용이면 남기되 테스트로 «어떤 role 이 core 로 가는가» 를 고정. 테스트 `test_invalid_fields_fail_explicitly` 에 `("role","tool",…)` 1행 추가.

**K2 — 순서 정보가 이벤트 스키마에 없어 윈도우 문서의 turn 순서를 «입력 리스트 순서» 로만 정한다** (`events.py:95~103`, `conversation.py:25`)
- 실측 P4: `sequence`/`ordinal` 필드는 `UNKNOWN_EVENT_FIELDS` 로 거부되고, 뒤집힌 리스트 `[b, a]` 는 그대로 `[m2, m1]` 순으로 직렬화된다. `occurred_at` 도 정렬에 쓰이지 않는다(계약대로 «시각으로 정렬 금지» 는 맞다).
- 계약: `adapter_mapping.ordering = top_level_ordinal_then_verified_byte_range_not_timestamp`, `window.membership = stable_message_ids_do_not_renumber_on_edits`. 즉 «정렬 키가 이벤트에 있어야» 윈도우 재구성·재시작 후 동일 순서·C08(창 경계 문맥) 이 성립한다.
- 왜 blocker 인가: `jsonl.read_batch` 는 `start_offset` 을 레코드에 붙이지만 `Event` 에는 없다. 원장이 이벤트를 저장했다가 다시 읽어 윈도우를 만들 때 순서 근거가 사라진다. `/turns/i/text` 앵커의 `i` 가 곧 순서이므로, 재구성마다 순서가 흔들리면 앵커도 흔들린다.
- 수정: 정규화 이벤트 스키마에 `sequence`(producer 내 단조 정수, `required`) 를 추가하고 계약 `event.required` 에도 반영. `create_only_conversation` 은 `(producer_epoch, sequence)` 로 정렬하고, 같은 epoch 안에서 `sequence` 중복이면 `DUPLICATE_SEQUENCE_REQUIRES_LEDGER`. 대안(스키마 미변경): `EventRecord.start_offset` 을 `Event` 로 내리고 정렬 키로 쓰되, 그러면 «파일 offset = 순서» 가 되어 다른 입력원(CS API) 에서 깨진다. 스키마 추가를 권장.

### 수정 권고 (blocker 아님 · 원장 구현 전 반영이 싸다)

**R1 — 배치 중간의 잘못된 한 줄이 «앞의 정상 레코드까지» 버리고, 오류에 위치가 없다** (`jsonl.py:62`)
- 실측 P1: 정상 2줄 + 깨진 1줄 + 정상 1줄 → `INVALID_JSON` 하나로 배치 전체 raise, 정상 2건 유실, 오류 문자열에 offset 없음.
- docstring 이 «invalid complete line fails the whole batch» 로 의도라고 적었고, 계약 `source_checkpoint_condition = contiguous_committed_prefix_only` 와 어긋나지는 않는다. 그러나 «어느 offset 에서 멈췄는가» 가 없으면 원장은 재시도할 때 같은 8 MiB 를 다시 읽어 같은 자리에서 또 죽는다(운영상 무한 재시도). 계약 `excluded_records = persist_skip_reason_then_advance_contiguous_checkpoint` 는 «건너뛰고 전진» 을 요구한다.
- 수정: `EventError` 에 `offset: int | None` 속성 추가(본문 아닌 숫자만), `read_batch` 가 `raise EventError(code, offset=start_offset+cursor)`. 그리고 «정상 prefix 반환 + 첫 오류 위치» 를 돌려주는 모드(`EventBatch.error: tuple[code, offset] | None`) 를 두어 원장이 prefix 를 커밋하고 오류 레코드를 quarantine 할 수 있게 한다. 원문은 여전히 오류에 넣지 않는다.

**R2 — `grant`/`revoke` 가 파서에서 거부되어 같은 배치의 나머지를 멈춘다** (`events.py:125`)
- 실측 P2: 계약 `event.types` 6종 중 `grant/revoke` 가 `UNSUPPORTED_EVENT_TYPE` → R1 과 결합해 배치 정지.
- 부분 구현 경계로 인정한다. 다만 «미구현» 과 «위반 입력» 을 같은 코드로 내면 원장이 구분 못 한다. 수정: `UNSUPPORTED_EVENT_TYPE` 은 6종 밖에만 쓰고, `grant/revoke` 는 `EVENT_TYPE_NOT_YET_HANDLED` 로 분리(R1 의 quarantine 대상). 테스트 `("event_type","grant",…)` 두 행의 기대 코드를 바꾼다.

**R3 — `restore` 가 `role/content` 를 «요구» 한다** (`events.py:128`)
- 실측 P5: `restore` + 본문 → 통과, `restore` 본문 없음 → `INVALID_ROLE`. 계약은 `create_required`·`edit_required` 만 정의하고 `restore` 는 «별도 승인된 restore 사건» 이다(§4). core `restore` 도 본문 없는 CAS 요청이다. restore 에 본문을 실으면 «복원하면서 내용을 바꾸는» 경로가 생겨 tombstone 규칙(낮은 버전 부활 금지) 검증이 복잡해진다.
- 수정: `restore` 를 `delete` 와 같은 «본문 없음» 그룹으로 옮기고 `RESTORE_BODY_NOT_ALLOWED`. 내용 변경은 restore 뒤 별도 `edit`.

**R4 — `turn_id` 에 `tenant_id`·`project_id` 가 평문으로 들어가 core DB·검색 evidence·expansion 참조에 남는다** (`conversation.py:33`)
- 실측 P7: `turn_id = '["synthetic","airag-contract","stream","epoch","m001"]'`. `chunking.py:111` 이 이를 청크 앵커로 저장하고 `expansion.py:131` 이 `turn_id` fragment 로 참조한다.
- 계약 `message_id = payload.id_scoped_by_tenant_project_stream` 이라 «scope 포함 ID» 자체는 계약대로다. 문제는 그것이 «core 가 반환하는 evidence» 에 그대로 실리는 것이다. tenant 문자열이 식별자에 불과하면 무해하지만, 실제 값이 이메일·고객명 계열이면 core 검색 결과에 노출된다. 판단은 U11(tenant 실제 값) 에 달렸다.
- 수정(저비용): `turn_id` 를 `sha256(canonical 5-tuple)[:32]` 또는 `"<stream>/<epoch>/<message_id>"` 로 만들고 tenant/project 는 소비자 원장 join 으로만 복원한다. 계약 `anchor_join` 이 이미 «원장 join 으로 시각·권한 복원» 을 정했으니 일관된다. 테스트 `test_synthetic_…anchors` 의 `json.loads(turn["id"])[-1]` 단정을 바꿔야 한다.

**R5 — 대소문자·정규화 미적용 식별자** (`events.py:15`)
- `_text` 는 공백만 거부한다. `event_id`·`message_id` 에 NFC/NFD 차이, 선행 0, 대소문자 차이가 있으면 다른 ID 로 본다. 계약 `event_id = sha256(canonical JSON array …)` 이 «소비자가 생성» 하는 값이면 문제없지만, 외부 CS 가 주는 값이면 정규화 규칙이 필요하다. 지금은 문서화만: docstring 에 «ID 는 바이트 동일성으로 비교, 정규화 없음» 1줄.

### 확인된 정확한 동작 (수정 불요)

| 항목 | 근거 |
|---|---|
| fingerprint 가 키 순서·ASCII escape 에 불변 | 실측 P6 `True`(`sort_keys` + `ensure_ascii=False` 재직렬화) |
| BOM 이 있는 파일 첫 줄 거부 | 실측 P5 `INVALID_JSON`. 계약이 BOM 을 허용하지 않으므로 맞다. 다만 rollout 파일에 BOM 이 없음을 어댑터가 전제한다 |
| `\ud800` 같은 lone surrogate 거부 | `test_escaped_invalid_unicode_is_rejected` + `_text` 의 encode 검사 |
| 스키마 버전 `True`(bool) 거부 | `type(...) is not int` 로 bool 배제 |
| CRLF 는 레코드 바이트에 포함, `\r` 이 JSON 파서에서 공백으로 소비 | `test_crlf_offsets_include_both_bytes` |
| `read_batch` 가 `start_offset` 을 절대 offset 으로 되돌림 | `test_offsets_are_bytes_…` (100 + len) |
| 빈 본문 create → turn 0, 이벤트 보존 | C14 최종 표기와 일치 |
| 서로 다른 scope 이벤트 병합 거부 | `MIXED_SCOPES` |

### 테스트 갭 (구현 전 추가 권장)

1. `role=tool` 거부(K1). 2. 순서 필드 존재·정렬·중복(K2). 3. 배치 중간 오류 시 «정상 prefix 보존 + offset 보고»(R1). 4. `restore` 본문 거부(R3). 5. 4 MiB 단일 레코드 경계값(`max_record_bytes` 정확히 같을 때 통과, +1 거부). 6. `content` 에 U+2028/U+0000 같은 제어 문자 — 현재 통과하며 Docling 에 어떻게 들어가는지 확인 필요(결함 아님, 관찰). 7. `test_synthetic_contract_reaches_real_docling` 가 `from airag import normalize` 를 하므로 `rag-consumer` 단독 설치에서는 실패한다. `pyproject` 의 dev 의존성 또는 `pytest.importorskip` 로 명시.

### 4차 계약 대비 요약

| 계약 항목 | 코드 | 판정 |
|---|---|---|
| `allowed_roles = [user, assistant]`, tool 제외 | `tool` 허용 | **K1 위반** |
| `ordering = ordinal_then_byte_range` | 순서 필드 없음 | **K2 위반** |
| `excluded_records = skip + advance` | 배치 전체 실패 | R1 (계약과 상충은 아니나 운영 불가) |
| `types` 6종 | 4종 | R2 (부분 구현, 코드 분리 권고) |
| `event_id_reuse_with_different_content = conflict` | conversation 에서 event_id 중복 거부(내용 비교 없음) | 원장 몫으로 인정. 파서에는 없어도 됨 |
| `partial_final_line = do_not_ack` | pending_tail 로 정확 | 준수 |
| `replay fingerprint excludes ingested_at` | 준수 | 준수 |
| scope 는 caller 가 준다 | `expected_scope` 강제 | 준수 |

### 다음 단계 조건

원장(ledger) 구현 착수 전에 K1·K2 를 닫는다. 둘 다 10줄 내외 수정 + 테스트 3~4행이다. R1·R3 은 원장 설계에 직접 영향(오류 offset 계약, restore 의미)이 있으니 원장 설계 문서에 먼저 반영하고 코드는 같이 고치는 것이 낫다. R4 는 U11 결정 뒤라도 되지만 `turn_id` 형식은 나중에 바꾸면 발행된 청크 앵커가 전부 바뀌므로 첫 발행 전에 정하는 것이 싸다.

---

## 코드 리뷰 (6차) — K1/K2·R1~R5 재확인 + 신규 `ledger.py`/`redaction.py`

- 검토자: ft-airag-da-fable51#0 (Fable 5.1, `--model claude-fable-5-1 --effort high`, 표준 창). Serena 미노출, 직독 + 실행 검증.
- 대상: `events.py`(161줄)·`jsonl.py`(76)·`conversation.py`(67) 갱신본, 신규 `redaction.py`(101)·`ledger.py`(224+, 검토 중 `ordering_key` 추가본까지 반영), tests 6파일.
- 실행: `pytest -q` → **88 passed (0.71 s)**. 추가 가설 34건을 임시 디렉터리 원장으로 실측(실제 데이터 미수집, 새 DB 는 tmp 에만). 선택 rollout 의 user/assistant 공개 메시지 271건에 `redact_text` 를 «집계만» 적용(본문·거부 사유 외 미출력).
- 코드·테스트·계약 미수정. 리뷰 파일만 편집.

### 판정: **K1·K2 해제. 어댑터 3모듈 PASS. ledger/redaction 은 조건부 PASS — blocker 1건(운영 정지 결함), 수정 권고 4건.**

### K1/K2·R1~R5 해제 확인 (실측)

| # | 실측 | 판정 |
|---|---|---|
| K1 | `role=tool` → `UNSUPPORTED_ROLE`, `customer` 도 거부. `conversation` 은 `canonical_json` 재파싱으로 위조 dataclass 차단(`EVENT_REPRESENTATION_MISMATCH`) | 해제 |
| K2 | `source_ordinal` 필수 int63. 역순 입력 `[ord 5, ord 2]` → 정렬 `[A, B]`. 중복 ordinal → `DUPLICATE_SOURCE_ORDINAL`, epoch 혼합 → `EPOCH_RECONCILIATION_REQUIRED`. ledger 는 `ordering_key UNIQUE` 로 배치 간 ordinal 재사용도 `SOURCE_ORDINAL_CONFLICT` | 해제 |
| R1 | `JsonlError("INVALID_JSON AT_BYTE_884")` 에 start/end offset 속성. 정책 = «정상 prefix 도 atomic 롤백» 으로 명시. 원문 미노출 유지 | 반영(정책 선택 인정, 아래 L1 참조) |
| R2 | `grant/revoke` → `UNIMPLEMENTED_AUTHORITY_EVENT` 로 분리 | 반영 |
| R3 | `restore`·`delete` 는 control-only, 본문 있으면 `CONTROL_EVENT_BODY_NOT_ALLOWED` | 반영 |
| R4 | `turn_id = "msg:" + sha256(5-tuple)`, tenant/project 평문 없음 | 반영 |
| R5 | `_identifier` 가 앞뒤 공백·제어문자(0~31, 127) 거부. 정규화는 안 하고 바이트 동일성 비교 | 반영 |

### Blocker

**L1 — «거부된 한 줄» 이 있으면 그 source 는 영원히 전진하지 못한다** (`ledger.py:146` + `jsonl.py` atomic 정책 + `redaction.py` fail-closed 의 결합)
- 실측: 정상 2줄 커밋(offset 768) 뒤 «닫힘 없는 태그» 1줄 + 정상 1줄을 넣으면 `UNBALANCED_INJECTED_BLOCK` 으로 배치 전체 롤백, checkpoint 768 유지. 여기까지는 설계대로다. 그런데 **호출자가 그 줄을 건너뛰려고 `start_offset = 768 + len(poison)` 으로 다시 부르면 `CHECKPOINT_CONFLICT`** 다(`row[5] != start_offset`). ledger 에 «이 바이트 범위를 사유와 함께 skip 하고 checkpoint 를 옮긴다» 는 API 가 없다.
- 실제 입력에서 발생한다: 선택 rollout 의 user 메시지 72건 중 **1건(ordinal 4840, 654자)** 이 `<user_shell_command>` 열림 → `<environment_context>` 열림 → 닫힘 없음 구조라 `AMBIGUOUS_INJECTED_BLOCK` 으로 거부된다. 이 줄 이후의 공개 메시지는 현재 코드로는 수집할 수 없다. 나머지 13건은 정상 치환됐다(environment_context 9·user_shell_command 4).
- 계약: `excluded_records = persist_skip_reason_then_advance_contiguous_checkpoint_without_indexing_content`, `redaction.on_failure = reject_record_before_durable_write_no_ack`. 두 조항은 «레코드는 저장 안 함, 그러나 커서는 사유를 남기고 전진» 을 뜻한다. 지금 코드는 앞 절반만 한다.
- 수정(구현 가능한 최소 형태): `Ledger.skip(source_id, start_offset, end_offset, reason_code, span_digest)` 를 추가한다. 같은 `BEGIN IMMEDIATE` 안에서 ①`next_offset == start_offset` 확인 ②`deliveries` 에 `record_count=0` + `skip_reason` 컬럼(또는 별도 `skips` 테이블)으로 기록 ③`next_offset=end_offset`, chain_digest 갱신. 저장하는 것은 offset·digest·사유 코드뿐이고 원문은 없다. 호출자는 `JsonlError.start_offset/end_offset` 를 그대로 넘긴다. 테스트: «거부 1줄 → skip → 다음 정상 줄 커밋 → 재시작 후 같은 skip 재적용은 멱등(같은 digest 면 replay, 다르면 conflict)».
- 스키마 변경(`deliveries` 컬럼 또는 새 테이블)이 필요하므로 `user_version` 을 2 로 올리거나, 아직 실 DB 가 없으니 v1 을 고쳐도 된다(계약 `projection_db_state = planned_not_created`). 지금 고치는 것이 가장 싸다.

### 수정 권고

**L2 — 정책 버전이 오르면 기존 source 가 `SOURCE_BINDING_MISMATCH` 로 막힌다** (`ledger.py:118,134`)
- 실측: `POLICY_VERSION` 을 r2 로 바꾼 뒤 같은 source 에 ingest → `SOURCE_BINDING_MISMATCH`. 계약 `redaction.policy_change = new_derived_projection_version_and_explicit_reprocessing_not_rewrite_old_receipt` 는 «옛 영수증은 그대로, 새 projection 버전» 이지 «source 를 잠근다» 가 아니다.
- 이것이 «의도된 잠금» 이면 해제 API(`Ledger.rebind_policy(source_id, new_version)`: 명시 호출, 기존 `events.policy_version` 은 유지, 이후 레코드만 새 버전)가 있어야 하고, 없으면 정책 개정 = 모든 source 재수집이다. 어느 쪽이든 문서화 + 테스트 1건.

**L3 — `redact_text` 가 «태그 이름의 산문 언급» 도 거부한다** (`redaction.py:13,62`)
- 실측: `"the <environment_context> tag is used"` → `UNBALANCED_INJECTED_BLOCK`. 이 세션의 대화 주제 자체가 이 태그들이므로 assistant 가 태그 이름을 문장에 쓰면 그 메시지가 거부된다(실측 271건 중 아직 0건이나, 이 리뷰 문서를 읽는 대화가 수집되는 순간 발생한다).
- 수정 선택지: (a) 인라인 코드 백틱 안의 태그는 리터럴로 취급 (b) `<tag>` 가 «줄 처음» 에 있을 때만 블록 시작으로 인식(rollout 실측: 주입 블록은 항상 메시지 선두 또는 줄 선두다) (c) 현행 유지 + L1 의 skip 으로 흡수. 최소 (b) 를 권장. 정책 변경이므로 r1 → r2 이고 L2 와 엮인다.

**L4 — `named_secret` 규칙이 `token=8000` 같은 일반 설정값을 비밀로 치환한다** (`redaction.py:22`)
- 실측: `"창 예산 token=8000 으로"` → `"창 예산 [REDACTED:named_secret] 으로"`. 이 프로젝트 대화는 token 예산 얘기가 많아 검색 품질(H01~H20) 에 직접 영향이 있다. 과탐은 비밀 유출보다 안전하므로 blocker 는 아니다.
- 수정: `\btoken\b` 단독 키를 제거하거나 값 쪽에 최소 길이·문자 클래스(예: 16자 이상 & 영숫자 혼합) 조건을 건다. 계약 `secret_rules` 의 `replace_named_api_key_token_password_secret_values` 문구도 «값 형태 조건» 을 추가.

**L5 — 위조 placeholder 가 `searchable_text` 에서 지워진다** (`redaction.py:27,99`)
- 실측: 원문에 사용자가 직접 쓴 `[REDACTED:bearer]` 는 `redact_text` 가 그대로 두고(rules 비어 있음) `searchable_text` 가 지운다. 결과: 그 메시지가 «비어 있음» 으로 turn 이 빠진다. 계약 위반은 아니고 유출도 아니지만, 원문에 있는 문자열이 검색에서 사라지는 «조용한 누락» 이다. 수정: `redact_text` 가 입력에 이미 있는 placeholder 형태를 `[LITERAL:…]` 로 escape 하거나, `RedactedEvent.audit_rules` 가 비어 있으면 `searchable_text` 를 적용하지 않는다.

### 트랜잭션·재시작·마스킹 경계 — 확인된 정확한 동작

| 항목 | 실측 |
|---|---|
| 같은 배치 재전송 → replay 영수증(inserted 0 / replayed 2), checkpoint 불변 | C01 준수 |
| 같은 offset 범위에 다른 바이트 → `CHECKPOINT_CONFLICT`(deliveries 가 없을 때) / `DELIVERY_CONFLICT`(있을 때) | C02·C03 준수 |
| offset 건너뜀 → `CHECKPOINT_CONFLICT`, 새 source 가 0 이 아닌 offset → `CHECKPOINT_GAP` | contiguous prefix 준수 |
| 같은 event_id 다른 내용(다른 source 경유) → `EVENT_ID_CONFLICT`, 같은 내용 → replay | 계약 `event_id_reuse_with_different_content = conflict` 준수 |
| 저장된 `redacted_json` 에 원문 비밀 부재(`password=SECRET123` 실측) | 마스킹이 durable write 앞 |
| `reply_to` 등 메타데이터에 비밀 → `SENSITIVE_EVENT_METADATA` 로 레코드 거부(앵커를 바꾸지 않음) | 정확한 선택 |
| `_identity(source_id/incarnation)` 도 redaction 검사 통과 필요 | 경로에 비밀이 있으면 거부 |
| 미완 PEM 블록 → `INCOMPLETE_PRIVATE_KEY` 거부 | fail-closed |
| 0바이트 기존 파일·평문 SQLite·잘못된 키 → `LEDGER_OPEN_FAILED`, 파일 미변경 | 계약 `never adopt plaintext/foreign/empty` 준수 |
| `BEGIN IMMEDIATE` → 검사·삽입·checkpoint 갱신 → `COMMIT`, 실패 시 `ROLLBACK`, sqlite 오류는 코드로 치환 | 단일 트랜잭션 |
| `journal_mode=DELETE`·`synchronous=FULL`, 파일 0600, symlink 거부 | 내구성·권한 |

### 관찰 (판정 무관)

- `test_concurrent_identical_delivery_commits_once` 가 있으나 실제 두 프로세스가 아니라 같은 프로세스의 두 커넥션으로 보인다(파일명만 확인, 본문은 안 열었다). `busy_timeout=5000` 은 있으니 실 동시성은 P08A-07 에서.
- `ledger.ingest` 는 배치 전체를 메모리에서 redaction 한 뒤 트랜잭션을 연다. 8 MiB 상한이 있으므로 문제없다.
- rollout 어댑터(native → 정규화 JSONL)는 아직 없다. 지금 ledger 가 받는 것은 «이미 정규화된 JSONL» 이며 `compaction_rule`·`file_incarnation` 검증은 그 어댑터의 몫이라고 docstring 이 맞게 적었다.

### 4차 계약 대비 요약

| 계약 | 코드 | 판정 |
|---|---|---|
| `allowed_roles`, `tool_payloads disabled` | user/assistant 만 | 준수 |
| `ordering = ordinal` | `source_ordinal` 필수 + UNIQUE | 준수 |
| `excluded_records = skip + advance` | skip API 없음 | **L1 위반** |
| `policy_change = 새 projection 버전, 옛 receipt 유지` | source 잠금 | L2 (해석 필요) |
| `on_failure = reject before durable write` | 준수 | 준수 |
| `ack_condition = redacted record + receipt durably committed` | COMMIT 뒤 Receipt 반환 | 준수 |
| `partial_final_line = no ack` | pending_tail 미저장 | 준수 |
| `event_id_reuse_with_different_content = conflict` | `EVENT_ID_CONFLICT` | 준수 |

### 다음 단계 조건

L1 을 닫기 전에는 선택 rollout 을 끝까지 수집할 수 없다(1건에서 멈춤). L3·L4 는 정책 r2 로 묶어 한 번에 고치고 L2 의 재바인딩 경로로 적용하는 순서가 자연스럽다. L5 는 저비용이라 같이.

---

## 코드 리뷰 (7차) — L1/L5 대응 최종 확인 + L2~L4 계약 기록

- 검토자: ft-airag-da-fable51#0 (Fable 5.1, `--model claude-fable-5-1 --effort high`, 표준 창). Serena 미노출, 직독 + 실행 검증.
- 대상: `ledger.py`(스키마 v3 · `rejections` 테이블 · `skip_rejected_record` · `_bind_source`), `redaction.py`(`RedactedEvent.has_public_text`, `_redact_text(public_only)`), `conversation.py`(`redacted_conversation`), 갱신 tests, `p08a01-contract.json` 의 `rejected_record_recovery`·`redaction_policy` 추가 항목.
- 실행: `pytest -q` → **96 passed (0.83 s)**. 추가 가설 18건을 tmp 원장으로 실측. 실제 데이터·운영 DB 없음. 코드·계약 미수정.

### 판정: **PASS — L1·L5 해제, L2~L4 는 계약에 결정으로 기록됨. ledger/redaction 포함 5모듈 전부 구현 계약 기준 통과. 남은 blocker 0건.**

### L1 해제 확인 (`skip_rejected_record`, 실측 12건)

| 실측 | 결과 |
|---|---|
| ack 없이 호출 | `EXPLICIT_GAP_ACKNOWLEDGEMENT_REQUIRED` |
| digest 불일치 | `REJECTED_RECORD_DIGEST_MISMATCH` |
| 검증상 «유효한» 레코드를 skip 시도 | `VALID_RECORD_CANNOT_SKIP` |
| 두 레코드를 한 번에 | `ONE_COMPLETE_RECORD_REQUIRED` |
| checkpoint 와 다른 offset | `CHECKPOINT_CONFLICT` |
| 정상 skip | `SkipReceipt(committed_offset=1181, reason='UNBALANCED_INJECTED_BLOCK', replayed=False, accepted_events=0, coverage_gap=True)` |
| 같은 skip 재전송 | `replayed=True`, checkpoint 불변 |
| skip 뒤 정상 레코드 ingest | `Receipt(1565, inserted 1)` — **6차 blocker 의 «영원히 전진 못 함» 해소** |
| `INVALID_JSON` 줄·빈 줄 skip | 각각 `reason=INVALID_JSON` / `EMPTY_JSONL_RECORD` 로 전진 |
| `rejections` 컬럼 | `source_id, start_offset, end_offset, span_digest, reason_code, policy_version` — 원문 없음 |
| `events` 에 거부 본문 저장 여부 | 없음(태그 문자열 검색 0건) |
| chain_digest | skip 도 `["rejected", reason]` 를 섞어 갱신하므로 «skip 을 빼고 이어붙인» 체인과 구분됨 |

계약 `rejected_record_recovery` 4항(api·result·caller_obligation·normal_batch_error)과 코드가 일치한다. 특히 «정상 batch 오류는 자동 skip 없음, 사람·정책이 호출» 이 `acknowledge_gap=True` 강제로 구현됐다.

### L5 해제 확인 (`has_public_text`, 실측 5건)

| 본문 | `has_public_text` | 검색 turn |
|---|---|---|
| `x [REDACTED:bearer] y` (위조 placeholder + 공개 텍스트) | True | 보존, 원문 그대로 |
| `[REDACTED:bearer]` (위조 placeholder 단독) | True | 보존 — 사용자가 쓴 문자열은 공개 텍스트 |
| 실제 `<user_shell_command>` 블록만 | False | 제외(청크 0, C14 정상) |
| 실제 블록 + 위조 placeholder | True | 보존 |
| DB `events.has_public_text` | `[1, 1, 0, 1]` | 저장 확인 |

`redacted_conversation` 은 빈 본문을 빼기 «전에» 전체 이벤트를 `create_only_conversation` 에 한 번 통과시켜 ordinal·중복·scope 검증을 먼저 한다(69~74행). 검색 제외가 검증 우회가 되지 않는다. 6차의 «조용한 누락» 은 사라졌다.

### L2~L4 — 계약 결정으로 기록됨 (코드 변경 없이 종결)

| # | 계약 필드 | 판정 |
|---|---|---|
| L2 | `policy_change = new_encrypted_ledger_generation_and_explicit_replay_from_verified_source_no_in_place_source_rebinding_or_old_receipt_rewrite` | 수용. `SOURCE_BINDING_MISMATCH` 가 «잠금» 이 아니라 «새 원장 세대로 가라» 는 신호임이 명문화됐다. 재바인딩 API 를 만들지 않은 선택이 옛 receipt 불변성에는 더 안전하다 |
| L3 | `ambiguous_tag_prose = fail_closed_with_explicit_audited_gap_option_not_silent_ignore` | 수용. L1 skip 이 있으므로 산문 언급 거부는 «감사된 gap» 으로 흡수된다. 실측 rollout 1건(ordinal 4840)도 이 경로로 처리 가능 |
| L4 | `numeric_named_secret_values = conservatively_redacted_including_token_equals_8000_numeric_value_does_not_prove_nonsecret` | 수용. 과탐이 검색 recall 에 주는 영향은 P08A-07 H01~H20 에서 측정될 것이며, 그때 값이 나쁘면 r2 정책으로 다시 논의 |

### 관찰 (판정 무관)

- `skip_rejected_record` 는 skip 판정을 위해 `read_batch + redact_event` 를 «다시» 실행해 거부 사유를 얻는다. 호출자가 6차 `JsonlError` 에서 받은 사유와 다를 수 있는 경우는 정책 버전이 바뀐 사이뿐이며, 그때는 `_bind_source` 가 먼저 `SOURCE_BINDING_MISMATCH` 로 막는다. 일관됨.
- `rejections.end_offset` 은 `start + len(data)` 로 계산하고 `data` 는 개행 포함 1줄이라 `ingest` 의 `end_offset` 규칙과 같다. 다음 ingest 의 `start_offset` 이 맞물리는 것을 실측(1181 → 1565)으로 확인했다.
- 스키마 `user_version=3`. 계약 `projection_db_state = planned_not_created` 이므로 마이그레이션 없이 v3 로 시작하는 것이 맞다. 운영 DB 생성 전 마지막 스키마 변경으로 기록해 두면 P08A-03 에서 «v1/v2 파일이 왜 없는가» 를 묻지 않는다.

### 누적 판정 요약

| 차수 | 대상 | 판정 |
|---|---|---|
| 1 | 나노 초안 | 조건부 PASS (B1~B3) |
| 2 | 기획 v1.0 | PASS |
| 3 | 기획 v1.1 + 계약 0.1 | 조건부 PASS (B4~B6) |
| 4 | B4~B6 반영 | PASS |
| 5 | 어댑터 3모듈 | 조건부 PASS (K1·K2) |
| 6 | K1·K2 반영 + ledger/redaction | 조건부 PASS (L1) |
| 7 | L1·L5 반영 | **PASS, blocker 0** |

구현 계약 기준으로 `rag-consumer` 5모듈은 P08A-03(세그먼트·원장)·P08A-04(projection) 착수 조건을 충족한다. 미결 사용자 운영값(U3·U4·U6·U7·U8·U11·U13·U14)은 그대로이며, 계약 `status = DA4_PASS_implementation_contract_pending_operational_policy` 가 그 상태를 정확히 표현한다.

---

## 정책 검토 (8차) — 인터뷰 운영 정책의 필수 일관성 (`p08a01-contract.json` storage·interview·window·memory)

- 검토자: ft-airag-da-fable51#0 (Fable 5.1, `--model claude-fable-5-1 --effort high`, 표준 창). 직독만. 코드 리뷰 7차 PASS 는 그대로 보존한다.
- 대상: 90일 활성 만료 → 무기한 암호화 아카이브(별도 조회) / 같은 소유자·프로젝트 공유 / 환경변수 키 / 매일 03:00 KST 백업·누락 1회 보충·매일 임시 복원 검증·검증 성공 후 30일 백업 정리. 사용자 선택은 재질문하지 않고 «필드 간 모순» 만 본다.
- 계약 상태 `DA4_contract_PASS_DA7_implemented_boundary_PASS_operational_policy_pending`, `runtime_enabled=false` 전부 확인. 실수집·예약·정리 미활성.

### 판정: **조건부 PASS — blocker 1건. 나머지 정책은 상호 일관.**

### Blocker

**P1 — 백업 복원 뒤 «이미 만료된 항목» 의 부활을 막는 규칙이 없고, 계약 안의 두 필드가 서로 반대다.**

- `storage.archive_on_active_expiry.active_use = exclude_expired … from_normal_search_and_context`, `automatic_reactivation = false`.
- `window.archived_projection = remains_searchable_subject_to_current_policy` — 이 값은 v1.0(1~4차)의 «퇴거 ≠ 검색 제외» 시절 문장이다. 90일 만료 정책이 들어온 지금은 «만료 전 archived projection 은 검색됨 / 만료 후는 제외» 두 상태가 한 필드에 섞여 있다.
- `storage.expiry_policy_pending` 에 `backup_restore_active_expiry_reconciliation` 이 «미결» 로 남아 있고, `backup_policy` 에는 복원 뒤 만료 재적용 조항이 없다. 백업 보존 30일 < 활성 90일이므로 «백업 시점엔 활성, 복원 시점엔 만료» 인 항목이 매일 생긴다. 복원본을 그대로 열면 그 항목이 일반 검색에 돌아온다. PLAN P08A-09 닫는 증거의 «백업 복원 후 비부활» 과 `interview.first_completion_requires` 의 `restart_failure_expiry_and_restore_non_resurrection_tests` 가 요구하는 바로 그 상황이다.
- 왜 blocker 인가: ops-sol(`operations.py`)이 백업/복원을, life-sol(`lifecycle.py`)이 만료를 따로 짠다. 둘을 잇는 규칙이 계약에 없으면 각자 «자기 쪽은 맞게» 만들고 통합에서 부활한다. 사람 결정이 필요한 것이 아니라 «안전한 명시 설정» 으로 닫을 수 있다.
- 수정(코드 아님, 계약 3필드):
  1. `window.archived_projection` → `"remains_searchable_until_creation_time_expiry_then_archive_only"`.
  2. `backup_policy.restore_expiry_reconciliation` 신설: `"after_any_restore_run_lifecycle_expiry_pass_with_current_clock_before_opening_read_gate_expired_items_go_archive_only_never_reactivated"`. 7차 계약의 read-gate·restore_epoch 흐름(§7 8단계)에 «만료 재적용» 한 단계를 끼우는 것이다.
  3. `expiry_policy_pending` 에서 `backup_restore_active_expiry_reconciliation` 을 제거하고 위 필드로 «결정됨» 표시. 검증 사례 C15 `restore_backup_containing_now_expired_items → expired_items_archive_only_not_in_normal_search` 추가.

### 일관성 확인 — 통과 (기록만)

| 축 | 확인 | 결과 |
|---|---|---|
| 만료 시계 | `retention_clock = original_message_created_at`, 재수집·수정으로 연장 없음, 시각 불신 시 격리, 최초 수입 시 이미 만료면 archive-only | 상호 일관. 코드의 `occurred_at` 이 이 시계다 |
| 만료 vs 아카이브 실패 | `transition = … expired_results_hidden_even_if_archiving_fails`, 보존 검증 전 활성 참조 미해제 | 6차 B3 원칙과 일관(«숨김» 과 «참조 해제» 분리) |
| 아카이브 보존 | `indefinite`, 자동 purge 없음, 정리는 명시 요청 + 보존/파괴 구분 | 백업 30일 정리 범위가 `primary_archive_files` 를 제외하므로 충돌 없음 |
| 백업 정리 gate | 새 세트 «검증 성공» 뒤에만, `minimum_verified_backups=1`, 실패 시 보존, 성공 기준 = 마지막 «검증된» 성공 | 누락 판정 기준과 일관 |
| 검증 복원 | 격리 임시 경로, 수집·발행·스케줄러 비활성, 공간 부족 = 실패(검사 축소 없음) | P1 수정 뒤에는 «임시 복원에도 만료 pass 를 돌리지 않음(검증용이라 read gate 자체가 없음)» 을 한 줄 적으면 충분 |
| 키 | 3개 store 별 환경변수 64-hex, 누락 = 열기 전 실패, 자동 생성·폴백 없음, 로그·자식 프로세스 제거. 현재 `open_ledger(key: bytes)` 시그니처가 그대로 받을 수 있음 | 로더 미구현은 `implementation_status` 로 정직하게 표시됨. 투어 키 이전 «없음» 도 명시 |
| 공유 | `same_owner_same_project_across_explicitly_enrolled_sessions`, 교차 프로젝트 기본 거부, 공유 정책이 세션 탐색·등록 권한이 아님, 아카이브도 같은 경계 + 별도 조회 | tenant 값은 여전히 `pending_user_value`(U11) — 정책은 일관하고 값만 미결. 재질문 대상 아님 |
| 색인 시점 | `index_flush_triggers = [task_unit_completed, explicit_save, oldest_unindexed_event_age_300s]`, `max_open_seconds=300`, 새 사건 없으면 flush 없음 | 4차의 «시연 전 명시 flush» 와 일관 |
| 기억 자동 선택 | decision·progress·verified_solution 자동(`rule_checked`), 선호·지침은 확인 필요, 재오픈 시 선택 해제 | 5차 M5 와 일관 |

### 미결 중 «안전한 명시 설정» 으로 닫을 수 있는 것 (재질문 금지 대상, 제안값만)

| 항목 | 현재 | 제안 명시값 |
|---|---|---|
| `archive_file_layout` | pending | `~/.local/share/airag/archive/<project-id>/<stream_id>/<YYYY-MM>/segment-<n>.sqlcipher` + `manifest.json`(hash·범위·policy_version). 세그먼트 = 7차 ledger 와 같은 SQLCipher 형식 |
| `derived_indexes_and_caches_deactivation` | pending | 만료 시 core `delete`(tombstone) + 소비자 원장 `expired_at` 기록. core 물리 삭제는 U8 그대로 |
| `key_rotation_and_recovery` | pending | 회전 = 새 키로 새 store 세대 생성 + 명시 재처리(7차 L2 와 같은 패턴), 복구 runbook 은 `remaining_configuration` 유지 |

이 셋은 사용자 선택을 바꾸지 않는 구현 기본값이므로 메인이 계약에 적고 진행해도 된다.

### 범위 밖

P08B(프로젝트 코드 RAG)와 `operations.py`/`lifecycle.py` 코드는 이 검토 대상이 아니다. 코드가 나오면 P1 의 C15 가 그 리뷰의 첫 실측 항목이다.

### 8차 P1 재확인 — PASS (blocker 0)

계약 원문 확인:
- `window.archived_projection = searchable_when_outside_active_N_but_only_until_90_day_expiry_then_explicit_archive_only` — `archive_on_active_expiry.active_use`(만료 제외)·`automatic_reactivation=false` 와 같은 방향.
- `backup_policy.restore_expiry_reconciliation = restore_read_gate_closed_until_current_clock_creation_time_expiry_pass_deactivates_expired_conversation_memory_and_projection_cache_then_rechecks_scope_and_tombstones` — 복원 → gate 닫힘 → 현재 시계 만료 pass(대화·기억·projection 캐시) → scope·tombstone 재검사 → gate 열기. 7차 §7 복원 8단계에 만료 단계가 끼워졌다.
- `expiry_policy_pending = [archive_file_layout, derived_indexes_and_caches_deactivation]` — `backup_restore_active_expiry_reconciliation` 제거됨.
- C15 `restore_backup_whose_formerly_active_message_is_now_older_than_90_days → read_gate_stays_closed … expired_message_memory_and_cached_projection_never_return_in_normal_search_archive_remains_explicit_only` 추가됨. `interview.first_completion_requires` 의 `restore_non_resurrection` 항목과 대응.

운영 정책 8차 최종: **PASS**. ops-sol(`operations.py`)·life-sol(`lifecycle.py`) 코드가 나오면 C15 가 첫 실측 항목이다.

---

## 코드 리뷰 (9차) — `operations.py`(ops-sol#1) + `archive.py`(메인) 독립 리뷰

- 검토자: ft-airag-da-fable51#0 (Fable 5.1, `--model claude-fable-5-1 --effort high`, 표준 창). 직독 + 실행 검증.
- 대상: `operations.py`(444줄)·`tests/test_operations.py`(8 tests), `archive.py`(233줄)·`tests/test_archive.py`(5 tests), `.fable-team/airag/operations-result.json`. 기준: 8차 정책 PASS 계약(03:00 KST·catchup 1회·검증 성공 기준·30일 정리 gate·격리 임시 복원·환경변수 키·아카이브 무기한·명시 조회·C15).
- 실행: 전체 `pytest -q` → **136 passed (0.87 s)** (ops-sol 보고 시점의 lifecycle 2 fail 은 이후 해소됨). 추가 가설 25건을 realpath tmp 경로로 실측. 운영 경로·실제 데이터 없음. 코드·테스트 미수정. 리뷰 중 두 모듈 동결 인지.

### 판정: **PASS — blocker 0. 수정 권고 3건(비차단), 관찰 3건.**

### 정책 대조 (실측)

| 정책 | 코드 | 실측 | 판정 |
|---|---|---|---|
| 매일 03:00 Asia/Seoul | `backup_due`: 현지 날짜 03:00 slot, 03:00 이전이면 전날 slot | S2 정각 → due·catchup False. S5 UTC 18:00 입력 → KST 28일 slot 정확 | 준수 |
| 누락 1회 보충 | `catchup = due and (now > slot or previous < slot-1d)`. 누락 일수만큼 반복 없음 | S3 첫 실행 10:00 → due·catchup True, slot 1개 | 준수 |
| 성공 기준 = 검증된 성공 | 인자 이름이 `last_verified_success`, 호출자가 `create_backup_set` 반환 뒤에만 기록(docstring) | S6 미래 시각 입력 → due False(시계 역행 시 «건너뜀», 아래 O1) | 준수 |
| online SQLCipher 백업 | `_copy_database`: 읽기 전용 연결 + `BEGIN` + `Connection.backup(pages=256)` → 대상 integrity → fsync | B1 세트 생성. 원본 DB 미변경 | 준수 |
| 격리 임시 복원 검증 | `_verify_contents`: `TemporaryDirectory` 로 복사 → digest → DB integrity → `link_check(restored, now)`. 운영 경로 인자 자체가 없음 | B3 변조 → `BACKUP_DIGEST_MISMATCH`. B4 콜백 raise → 세트 미검증 | 준수 |
| C15 훅 | `link_check` 가 «현재 aware now» 를 받고 raise 하면 세트가 `verified` 로 넘어가지 않음. 세트 생성 시에도 1회 호출 | B1 `calls=1`, 경로 `['arch','consumer']` | 준수(재대조 «내용» 은 lifecycle 몫, 훅 계약은 정확) |
| 30일 정리 gate | `prune_backup_sets(newest_verified=…)`: 최신 세트 manifest·내용 검증 후에만, `completed_at` 기준, 최신·in_use 보존, 소유자 manifest 없으면 skip | P1 40일 전 세트 삭제, P2 최신이 31일이어도 보존, P3 잔류 staging 미삭제, P4 staging 을 newest 로 주면 `INVALID_NEWEST_SET` | 준수 |
| 정리 제외(주 아카이브·원천·키·외부 파일·사용 중) | 후보 = root 직계 `airag-set-*` 디렉터리 + 소유 manifest + 내용 정확 일치. 원천은 `SOURCE_INSIDE_BACKUP_ROOT` 로 애초에 root 밖 | test 의 `foreign` 세트 보존 확인 | 준수 |
| 환경변수 키 | `load_store_keys`: 64-hex 정규식, store 별 필수, 중복 키 거부, 자동 생성 없음. `unrelated_child_environment` 가 3개 변수 제거 | K1 대문자 hex 통과(정규식 `[0-9a-fA-F]`), K2 동일 키 → `STORE_KEYS_MUST_BE_DISTINCT`, K3 정확히 3개만 제거 | 준수 |
| 키 비노출 | 오류 문자열에 키 없음, manifest 에 `sha256`·이름만, 로그 없음 | manifest 키 = owner/state/created_at/completed_at/components/checkpoints | 준수 |
| 아카이브 불변·암호화 | `write_archive`: staging → COMMIT → 자체 verify → `os.link` 로 원자 발행(덮어쓰기 불가) → 실패 staging 잔류. bundle_id = 내용 해시 | A4 변조 뒤 같은 번들 재작성 → `ARCHIVE_RECORD_DIGEST_MISMATCH`(덮어쓰기 안 함). 평문 sqlite3 로 열면 `DatabaseError` | 준수 |
| 명시 조회 + 권한 콜백 | `lookup_archive(explicit_request=True 강제, authorize_record 필수)`, 레코드별 콜백 | `explicit_request=False` → 거부, 콜백 False → 빈 결과 | 준수 |
| 아카이브 마스킹 | `_clean` 이 문자열 값에 `redact_text`, 키 이름에 비밀 있으면 거부, id·scope 가 마스킹으로 바뀌면 거부 | A3 `token=8000` → `[REDACTED:named_secret]`(8차 L4 보수 정책 그대로) | 준수 |

### 수정 권고 (blocker 아님)

**O1 — 시계 역행 시 «영원히 due 아님»** (`operations.py:87`)
- 실측 S6: `last_verified_success` 가 `now` 보다 미래면 `due=False`. NTP 보정이나 잘못 기록된 성공 시각이 있으면 그 시각이 지날 때까지 백업이 서지 않는다. 계약 `schedule_success_basis = last_verified_successful_backup` 은 «성공 기록을 믿어라» 지 «미래 시각도 믿어라» 는 아니다.
- 수정: `previous > local` 이면 `OperationsError("SUCCESS_TIME_IN_FUTURE")` 로 호출자에게 알리거나, `due=True`+`catchup=True` 로 안전 쪽으로 기운다. 어느 쪽이든 테스트 1행.

**O2 — 아카이브 컴포넌트는 백업 검증에서 «바이트 digest» 만 본다** (`operations.py:327`)
- 실측 B2: `verify_backup_set` 에 archive 키를 안 줘도 `verified`. `kind=archive` 는 `_integrity` 를 건너뛰고 digest 만 대조한다. ops-sol 이 `limitations` 에 «link_check 가 `archive.verify_archive` 를 호출해야 한다» 고 정직하게 적었고, 8차 정책 `verification_policy.checks` 에는 `archive_manifest_hashes_and_provenance_links` 가 있다.
- 지금 구조에서는 그 검사가 «콜백 안에 넣어야 하는 관례» 다. 관례는 잊힌다. 수정: `verify_backup_set(..., archive_keys: Mapping[str, bytes] | None)` 를 받아 `kind=archive` 이고 키가 주어지면 `archive.verify_archive(target, key, scope)` 를 직접 호출하고, 키가 없으면 `MISSING_ARCHIVE_KEY` 로 실패. scope 는 manifest 컴포넌트에 `scope` 필드를 추가하거나 콜백에 남긴다. `operations → archive` import 가 생기지만 방향은 맞다(운영 계층이 아카이브 계층을 쓴다).

**O3 — `lookup_archive` 의 substring 검색이 id·scope·키 이름에도 걸린다** (`archive.py:228`)
- 실측 A1·A2: `query="e1"` 이 레코드 id 에, `query="message_id"` 가 필드 이름에 매치. 계약 `access = explicit_separate_archive_lookup` 은 «본문 검색» 을 뜻한다. 결함이라기보다 «너무 넓은» 검색이고, 8차 미결 `archive_file_layout` 과 함께 정해질 항목이다. 수정: 매치 대상을 `payload` 하위 문자열 값으로 한정하거나, 현행을 «전체 JSON 문자열 검색» 이라고 docstring 에 명시.

### 관찰 (판정 무관)

- `archive_meta.created_at` 은 `datetime.now(timezone.utc)` 벽시계다(A5). `operations` 는 `now` 를 주입받아 결정론적인데 `archive` 는 아니다. bundle_id 계산에는 안 들어가므로 재현성 문제는 없고, 테스트에서 시각을 고정하고 싶을 때만 걸린다.
- `create_backup_set` 의 세트 이름은 `now` 초 단위 + staging 난수 8자라 같은 초의 두 세트도 충돌하지 않는다(B5). `BACKUP_DESTINATION_EXISTS` 는 사실상 방어 코드다.
- `_copy_database` 는 원본 연결에 `BEGIN`(deferred) 을 열고 `backup()` 을 돌린다. SQLite online backup 은 원본에 쓰기가 들어오면 처음부터 다시 시작하므로 대형 DB + 활성 쓰기에서는 길어질 수 있다. 8차 정책 `restore_environment = collection_and_publication_and_schedulers_disabled` 는 «복원 시험» 에 대한 것이고 «백업 생성 중 수집 중지» 는 아니다. 03:00 은 수집이 뜸한 시각이니 실무 문제는 작지만, P08A-07 성능 검증에 «수집 중 백업 소요» 를 1개 넣어 두면 좋다.

### 테스트 갭 (구현 전 추가 권장)

1. O1 시계 역행. 2. O2 archive 키 누락 시 실패(구조 변경 뒤). 3. `prune` 이 `minimum_verified_backups=1` 을 «최신 보존» 으로만 만족하는데, 최신 세트가 «검증 실패한 세트» 일 수는 없는지(현재 `_manifest(state='verified')` 가 막는다 — 테스트로 고정). 4. `backup_due` 의 경계 `local == slot`(S2 실측 정확, 테스트에는 없음).

### 계약 대비 요약

| 계약 항목 | 판정 |
|---|---|
| `schedule_time_and_timezone 03:00 Asia/Seoul` · `missed_schedule one_catchup` · `schedule_success_basis verified` · `scheduler_concurrency one_per_project`(flock) | 준수 |
| `format encrypted_consistent_backup_set` · `key_material_in_backup false` | 준수 |
| `verification_policy` restore_destination 격리 · checks(digest·reopen·integrity) · 실패 시 미검증 보존 | 준수. `archive_manifest_hashes_and_provenance_links` 는 콜백 관례(O2) |
| `backup_retention 30d` · `cleanup_gate` · `cleanup_scope/excludes` · `minimum_verified_backups 1` · `on_failure retain` | 준수 |
| `key_environment_contract` 전 항목 | 준수 |
| `archive_on_active_expiry` format_baseline·access·automatic_reactivation false·source_file_mutation never | 준수 |
| `restore_expiry_reconciliation`(C15) | 훅 계약 준수. 실제 만료 pass 는 lifecycle 리뷰 대상 |

### 누적 판정

| 차수 | 대상 | 판정 |
|---|---|---|
| 5·6·7 | events/jsonl/conversation/ledger/redaction | PASS |
| 8 | 운영 정책 | PASS |
| **9** | **operations/archive** | **PASS (O1~O3 권고)** |

lifecycle.py(1247줄)·collector.py(765줄)는 이번 범위 밖이며 별도 발주가 오면 C15 실측을 첫 항목으로 검토한다.

---

## 코드 리뷰 (10차) — `collector.py` + `lifecycle.py` 독립 리뷰

- 검토자: ft-airag-da-fable51#0 (Fable 5.1, `--model claude-fable-5-1 --effort high`, 표준 창). 직독 + 실행 검증.
- 대상: `collector.py`(765줄)·`tests/test_collector.py`(16), `lifecycle.py`(1247줄)·`tests/test_lifecycle.py`(12), `.fable-team/airag/{collector,lifecycle}-result.json`. 기준: 4차 계약(session_identity·adapter_mapping·excluded)·8차 정책(C15·90일·소유자 공유)·9차 archive 접점.
- 실행: 전체 `pytest -q` → 첫 실행 1 fail·136 pass, 이후 14회 연속 **137 passed**(캐시 `lastfailed` 비어 있음, 실패 이름 미포착 — 아래 관찰). 추가로 collector 는 **선택 rollout 의 tmp 사본(22.5 MB)** 으로, lifecycle 은 테스트 헬퍼로 가설 17건 실측. 원본 파일 미변경, 운영 경로·실수집 없음. 코드·테스트 미수정, 동결 존중.

### 판정: **조건부 PASS — blocker 1건(collector 의 native 유형 목록이 실제 파일과 어긋나 «완료» 가 영원히 False). lifecycle 은 PASS. 수정 권고 4건.**

### Blocker

**G1 — `token_usage_record`·`inter_agent_communication_metadata` 가 excluded 목록에 없어 «gap» 으로 떨어지고, 그 결과 실제 rollout 은 `complete_through_snapshot` 이 될 수 없다** (`collector.py:28~34`, `641`)

- 실측(실파일 사본, `allow_gaps=True`, 10회 호출로 EOF 도달): accepted 354 · skipped 5138 · **gap 766** · complete **False**. gap 의 native 유형 = `token_usage_record` 721 + `inter_agent_communication_metadata` 44 + `response_item` 1(진짜 gap, ordinal 4840 의 `AMBIGUOUS_INJECTED_BLOCK`). `allow_gaps=False`(기본값)이면 **14번째 줄**(첫 `token_usage_record`)에서 `UNKNOWN_NATIVE_RECORD_TYPE` 로 정지한다.
- 계약 `session_identity.excluded` 는 `inter_agent_metadata` 를 명시하고, 4차 실측표에 `token_usage_record 553` 이 있었다. 코드 `_EXCLUDED_TOP_LEVEL` 은 6종(`session_meta, metadata, event_msg, compacted, world_state, turn_context`)뿐이다. `metadata` 는 실파일에 없는 유형이고, 있는 두 유형이 빠졌다.
- 왜 blocker 인가: ①기본 정책(fail-closed)으로는 실제 입력을 «한 줄도» 못 지나간다 ②`allow_gaps=True` 로 돌려도 766 gap 이 «감사된 커버리지 구멍» 으로 ledger `rejections` 에 남는다. 진짜 구멍 1건이 가짜 765건에 묻힌다 ③`complete_through_snapshot = … and not gaps` 라 P08A-08 시연에서 «완료» 를 보일 수 없다. 이것은 collector 의 자기 테스트(합성 fixture 에 두 유형이 없음)로는 잡히지 않는 결함이고, 정확히 «fixture 통과 ≠ 생산 완료»(3차 조건 4) 사례다.
- 수정(코드 3줄 + 테스트 1건): `_EXCLUDED_TOP_LEVEL` 에 `"token_usage_record": "EXCLUDED_TOKEN_USAGE"`, `"inter_agent_communication_metadata": "EXCLUDED_INTER_AGENT_METADATA"` 추가. 테스트 fixture 에 두 유형 1줄씩 넣고 `skipped_count` 에 세어지는지 단정. 계약 `excluded` 에도 `token_usage_record` 를 추가해 코드와 1:1 로 맞춘다.

### collector — 확인된 정확한 동작 (실파일 사본 실측)

| 항목 | 실측 |
|---|---|
| 경로 allowlist | 상대 경로·`/.` 접미 → `EXACT_ABSOLUTE_SOURCE_PATH_REQUIRED`. 미등록 → `UNENROLLED_SOURCE_PATH`. symlink·realpath 불일치·open 중 inode 변경 각각 거부 |
| session_meta | 첫 줄 `payload.id` ≠ 기대 → `SESSION_SCOPE_MISMATCH`. `expected_scope.stream_id` 와 session id 불일치도 거부 |
| 커밋 prefix 변조 | 바이트 1개 flip → `SOURCE_PREFIX_REWRITTEN`(R4) |
| 절단 | 커밋 offset 보다 작아지면 `SOURCE_TRUNCATED`. 마지막 5000B 만 잘라 커밋 offset 보다 크면 정상 진행 후 pending(R5, 설계대로) |
| 증분 | 1줄 append 뒤 재실행 → 그 1건만 추가(R6) |
| 파일 교체 | 같은 바이트·새 inode → `COLLECTOR_SOURCE_BINDING_MISMATCH`(R7). 계약 `producer_epoch = incarnation bound to session+file` 준수 |
| scope 변경 | 같은 source_id 에 다른 tenant → `COLLECTOR_SOURCE_BINDING_MISMATCH`(R8) |
| 재실행 | 완주 뒤 재실행 → 같은 카운트, 새 event 0(R3) |
| plan → ledger 2단계 | plan 을 `planned` 로 커밋 → ledger ingest/skip → `finalized`. 재시작 시 `_pending_plan` 재구성이 원래 분류와 7값 대조(`PENDING_PLAN_RECONSTRUCTION_MISMATCH`) |
| 공개 메시지 수용 | native user 117·assistant 239 → ledger user 116·assistant 239. 차이 1 = ordinal 4840 의 `AMBIGUOUS_INJECTED_BLOCK` gap(6차·7차 예측과 정확히 일치) |
| 마스킹 | ledger `events` 에 `<environment_context>`·`<user_shell_command>` 원문 0건. collector 테이블에는 offset·sha256·사유 코드만(컬럼 목록 확인) |
| 타임스탬프 | `occurred_at` = native top-level `timestamp`, `ingested_at` = 주입 clock, `source_ordinal` = native `ordinal`. 계약 adapter_mapping 그대로 |
| 배치 상한 | 호출당 8 MiB 진행, 22.5 MB 파일은 3~4회 호출. `pending_bytes` 로 미완 표시 |

### lifecycle — 확인된 정확한 동작 (헬퍼 실측)

| 항목 | 실측 |
|---|---|
| read gate 초기 상태 | refresh 전 `open=False, closed_reason=current_time_expiry_pass_required`. claim → `CURRENT_TIME_EXPIRY_PASS_REQUIRED`(L1). C15 의 «gate 는 만료 pass 전 닫힘» |
| C15 (테스트 그대로 재현) | 89일 → 창 발행·pinned memory → 91일로 시계 이동 → gate `retention_boundary_reached`, searchable·visible memory 빈 목록 → refresh 뒤 창 invalidated·memory `source_expired`·archive 후보 생성 → 잘못된 receipt `ARCHIVE_RECEIPT_CONTENT_MISMATCH` → 실제 `write_archive` receipt 로 confirm. `events` 테이블 불변 |
| 만료 시계 | +80일에 edit 이 와도 `created_at` 은 최초 create, +91일에 expired(L2). 계약 `retention_restart_on_reingest_or_edit=false` |
| 소유자 격리 | 같은 tenant/project/stream 이라도 owner 가 다르면 서로의 창을 못 보고 claim 도 `WINDOW_NOT_FOUND_OR_SCOPE_DENIED`(L3). 창 ID 에 owner 가 들어가 같은 메시지로 별도 창 생성 |
| 미등록 stream | `enrolled_streams` 밖은 load 단계에서 제외, eligible 0(L4) |
| N=4 분리 | 10창 모두 searchable, `active_window_ids` 4개(L5). 계약 «N 은 활성 상한이지 색인 개수 아님» |
| archive confirm | 같은 receipt 로 2회 → 둘 다 confirmed(멱등). 배치 부분 confirm 도 허용(L6, 아래 L-2 참조). `events` 불변 |
| tool_call_id 메시지 | eligible 0, 창 미생성(L7) |
| exact 토큰 모드 | tokenizer 없으면 `EXACT_TOKENIZER_REQUIRED`(L8) |
| 수정·삭제 순서 | `reduce_events`: 같은 version 두 번 → `AMBIGUOUS_MESSAGE_VERSION`, create 아닌 첫 사건 → `MESSAGE_CREATE_REQUIRED`, delete→delete → `INVALID_DELETE_TRANSITION`, restore 는 별도 사건만 |

### 수정 권고 (blocker 아님)

**L-1 — ledger 의 rejection 사유가 collector 의 진짜 사유를 덮어쓴다** (`collector.py:348`, `ledger.py skip_rejected_record`)
- 실측: collector plan 은 `UNKNOWN_NATIVE_RECORD_TYPE` 767 / `AMBIGUOUS_INJECTED_BLOCK` 1 로 정확한데, ledger `rejections.reason_code` 는 **768건 전부 `MISSING_EVENT_FIELDS`**. collector 가 gap 을 `{"collector_gap": {...}}` 한 줄로 ledger 에 넘기고, ledger 가 그 줄을 «다시 파싱해서» 사유를 얻기 때문이다.
- 결과: ledger 만 보는 감사자는 «왜 빠졌는지» 를 알 수 없다. 사유의 정본이 두 곳에 다르게 있다.
- 수정: `skip_rejected_record(..., reason_code: str | None = None)` 를 받아 호출자가 준 사유를 저장하고, 없을 때만 재파싱. 또는 `_gap_line` 에 `"reason_code"` 를 넣고 ledger 가 그것을 읽는다. 테스트 1건.

**L-2 — `confirm_archive` 가 receipt 의 번들과 «부분 집합» 후보를 승인한다** (`lifecycle.py:1086~`)
- 실측 L6: 2건 번들 receipt 로 후보 1건만 confirm → `confirmed=True`. `expected_bundle` 은 «넘긴 후보들» 로만 계산되므로 receipt 가 그 부분 집합과 우연히 맞을 일은 없어 실제로는 `ARCHIVE_RECEIPT_CONTENT_MISMATCH` 가 나야 하는데, 이 실측에서는 receipt 자체가 1건 번들이었다(내가 후보 1건으로 write_archive 를 한 뒤 confirm). 재검토하면 «receipt 번들 = 넘긴 후보 집합» 이 강제되므로 결함이 아니다. 다만 «아카이브된 번들에 들어 있지만 confirm 되지 않은 후보» 가 남을 수 있는 경로(다른 receipt 로 일부만 confirm)는 막혀 있지 않다. 수정: receipt 의 `records` 수와 pending 후보 수가 다르면 경고 필드(`unconfirmed_in_bundle`)를 돌려주거나 문서화.

**L-3 — `_read_gate` 의 `retention_boundary_reached` 가 «다음 만료 시각» 하나로만 닫힌다** (`lifecycle.py:542~`)
- `expiry_valid_until = min(미만료 메시지의 만료 시각)`. 메시지가 하나도 없으면 `None` → gate 가 시간으로는 영원히 안 닫힌다. 새 메시지가 ledger 에 들어오면 `ledger_checkpoint_changed` 로 닫히므로 실무 구멍은 아니다. 문서화만: «빈 scope 는 checkpoint 변경으로만 재대조».

**L-4 — 간헐 실패 1건 미포착**
- 첫 전체 실행에서 `1 failed, 136 passed` 가 났고 이후 14회 통과. pytest 캐시 `lastfailed` 가 비어 있어 이름을 못 잡았다. 후보: `test_collector.py::test_concurrent_collectors_converge_on_one_receipt`(ThreadPoolExecutor 사용) 또는 `test_operations.py::test_backup_restore_wrong_key_and_cleanup_boundary`(시각 비교). 수정: CI 에 `-p no:cacheprovider --tb=short` 로 이름을 남기고, 동시성 테스트는 `busy_timeout` 을 명시하거나 결정적 순서로 바꾼다. blocker 아님(재현 0/14).

### 4차·8차 계약 대비 요약

| 계약 | 코드 | 판정 |
|---|---|---|
| `excluded` 8종 | 6종 + 누락 2종 | **G1 위반** |
| `allowed_assistant_phases {final_answer, commentary}`·`missing_phase quarantine` | `UNVERIFIED_ASSISTANT_PHASE` | 준수 |
| `tool_payloads disabled` | `custom_tool_call*`·`function_call*` → `EXCLUDED_NON_MESSAGE_RESPONSE` | 준수 |
| `producer_epoch = incarnation(session+file)` · `identity_check exact realpath` · `source_replacement halt` | inode/dev/realpath 바인딩 | 준수 |
| `checkpoint_priority`(incarnation → offset → ordinal) | prefix sha → pending plan → ordinal 단조 | 준수 |
| `compaction_rule skip + continue offsets` | `EXCLUDED_COMPACTED_HISTORY` | 준수 |
| `excluded_records = persist_skip_reason + advance` | plan 에 정확, ledger 에는 덮어쓴 사유 | L-1 |
| `retention_clock original create` · `restore_expiry_reconciliation` · C15 | `reduce_events`·`_read_gate`·`refresh` | 준수 |
| `sharing_scope same_owner_same_project_enrolled` · `cross_project deny` · `session_discovery not authorized` | `AuthenticatedScope.permits` + owner 컬럼 | 준수 |
| `automatic_selection {decision, progress, verified_solution}` rule_checked · `confirmation_required {preference, instruction}` | `create_memory` 분기 | 준수 |
| `index_flush_triggers {task, save, 300s}` | `_build_windows` 3 사유 | 준수 |

### 다음 단계 조건

G1 은 3줄 수정이고 실파일로 «complete=True, gap=1(ordinal 4840)» 이 나오는지가 닫는 증거다. 그 값이 나오면 P08A-08 시연의 첫 화면(수집 커버리지)이 성립한다. L-1 은 감사 정확성이라 P08A-07 전에 넣기를 권장한다.

### 10차 G1·L-1 재판정 — **PASS (collector blocker 0)**

실파일 사본(tmp, 22.9 MB 현재 크기) 재실측, 본문·키 미출력:
- 기본 fail-closed(`allow_gaps=False`): 8,384,942 바이트까지 진행(첫 8 MiB 배치 완주) — 이전의 «14번째 줄 정지» 해소.
- `allow_gaps=True` 완주: accepted 360 · skipped 6022 · **gap 1** · pending 0 · `complete_through_snapshot=True` · `coverage_complete=False`. gap 1 = `AMBIGUOUS_INJECTED_BLOCK`(ordinal 4840). 두 플래그 분리로 «전 바이트 처리됨 / 무결손은 아님» 이 정직하게 표시된다.
- skipped 사유에 `EXCLUDED_TOKEN_USAGE 731`·`EXCLUDED_INTER_AGENT_METADATA 44` 가 별도 코드로 집계됨. 계약 `excluded` 와 코드 사전이 1:1.
- L-1: `rejections` 가 `(reason_code='AMBIGUOUS_INJECTED_BLOCK', validation_code='MISSING_EVENT_FIELDS')` 로 native 사유와 정규화층 판정을 분리 저장(스키마 v4, `source_reason_code` 정규식 검증). 감사 정본이 하나로 맞았다.
- ledger `events` 에 원문 태그 블록 0건. user 120 / assistant 240 수용(파일이 계속 자라 4차 실측보다 늘었다).
- 전체 테스트: 첫 실행 `1 failed, 166 passed`, 이후 `-p no:cacheprovider` 3회 연속 **168 passed**. L-4(간헐 1건)는 여전히 이름 미포착이며 재현 0/3 — 권고 유지, blocker 아님.

10차 최종: collector·lifecycle **PASS**. P08A-08 시연의 «수집 커버리지 화면» 은 `gap=1(ordinal 4840, 사유 AMBIGUOUS_INJECTED_BLOCK)` 을 있는 그대로 보이면 된다.

---

## 코드 리뷰 (11차) — `bridge.py` 독립 리뷰 (lifecycle 창 → 기존 core 색인·하이브리드 검색)

- 검토자: ft-airag-da-fable51#1 (Fable 5.1, `--model claude-fable-5-1 --effort high`, 1m 창). 이전 좌석 #0 의 판정(7·8·9·10차)은 그대로 보존, 재검토하지 않았다.
- 대상(소스 펜스): `bridge.py` 560줄 md5 `fbcf0f389888c2d35ff1497f5dd935ae` · `tests/test_bridge.py` 431줄 md5 `99c285f761afa4739ddd2fe442776703` · `lifecycle.py` md5 `dc2566f3e308867b8af58c6bb5df1470`(읽기 대조용, 소유 life-sol#0). 대조 기준: `bridge-implementation.txt`(발주) · `bridge-result.json`(워커 보고) · 8차 C15 · 계획 §7(«source_keys 는 인증이 아니다 · 100개 필터에 밀어 넣지 않는다»).
- 실행: `test_bridge.py` 단독 `-p no:cacheprovider` → **7 passed (4.88s)**. 독립 프로브 5건(`.fable-team/airag/da11-bridge-probes.py`, 합성 fixture·실 프로바이더 0·실 기록 0). 전체 스위트는 1회만 돌렸고(`da11-full-suite-run1.txt`) 실행 중 소스 md5 가 바뀌었다(runtime/test_runtime 동시 작성) — 그 1 fail 은 `test_runtime.py::test_memory_provider_key_is_optional_for_unauthenticated_local_server` `NameError: extractor`(11차 범위 밖, 이름·trace 파일 보존). 코디네이터 지시대로 전체 재실행은 하지 않았다.

### 판정: **조건부 PASS — blocker 1건(B1: 재시도 job 처리 중 크래시 후 창이 영구 `failed` 고착). 수정 권고 3건. 프로필·펜스·C15·격리·파티션 정책은 실측 PASS.**

### Blocker

**B1 — core `retry` 가 만든 두 번째 job 이 `running` 상태로 크래시(리스 만료)하면 bridge 는 그 job 을 다시 못 잡고, 원래 실패 요청의 캐시 응답만 영원히 재생한다** (`bridge.py:260~283`)

- 실측(프로브 `test_h2_crash_during_retry_job_then_recovery`): ①프로바이더 실패 → job1 `failed`, 창 `failed` ②재시도 진입: `core_api.retry(job1)` 가 job2 를 만들고 `running`+리스 부여 → `process_and_publish` 에서 크래시(합성 RuntimeError) → job2 `running` 잔류, 창 `index_pending/processing`(attempt 2) ③리스 만료 ④프로바이더 정상화 뒤 bridge 3회 재실행 → **3회 전부 `add_replay` → `PROVIDER_UNREACHABLE`, 프로바이더 호출 0, 창 `failed`, searchable 0**.
- 왜 그런가: `status.latest_job` 은 job2(`running`) 인데 bridge 분기는 `{"failed","pending"}` 만 retry 로 보내고 그 외는 `core_api.add(add_request_id)` 로 떨어진다(`bridge.py:277~283`). `add_request_id` 는 창·문서해시·프로필로 고정된 멱등 키라 core 는 **job1 의 최종 실패 응답을 캐시에서 되돌려 준다**(`store.add` 의 `_check_idempotency`). 즉 «실패한 job 이 그 실패 요청의 재생 뒤에 영구 고착되면 안 된다»는 발주 항목 2 를 정확히 위반하는 경로가 하나 남았다.
- core 쪽은 복구 수단이 있다(프로브 `test_h2b`): `api.retry(job2)` 는 `running` 분기에서 `_finish_ingestion` → `reclaim_stale_job` 으로 리스를 회수해 완주한다(실측: `searchable=True`, `executed_job_id=2`, 프로바이더 1회). 그 뒤 bridge 는 `ready_replay` 로 정상 마감된다. 결함은 bridge 가 이 분기를 안 타는 것.
- 수정(코드 3~5줄 + 테스트 1건): `latest_status in {"failed","pending","running"}` 으로 retry 분기 확장 — `running` 이면 core 가 리스 유효 시 `IN_PROGRESS(retryable)` 를 돌려주므로 bridge 는 그대로 `_finish_failed` 로 흘려 다음 주기에 재시도하면 된다(리스 만료면 회수·완주). retry request_id 는 이미 `(window, profile, job_id, attempt)` 라 안정. 테스트: H2 시나리오 그대로(재시도 중 크래시 → 리스 만료 → 재실행 → `searchable`).

### 확인된 정확한 동작 (실측)

| 항목 | 실측 |
|---|---|
| 프로필 정확 복사 | 임베딩·normalizer·chunker·LLM 디스크립터 4항 대조 + `profile_key` 동일 강제, 불일치 시 `BEGIN IMMEDIATE` 롤백(테스트 2: 행 수·기존 충돌행 불변). `profile_key` 가 DB-로컬 `space_id` 를 해시하는 한계는 워커 보고와 일치 — 디스크립터 대조로 키 문자열 신뢰 안 함 |
| endpoint override | 캡처값과 다르면 `ENDPOINT_OVERRIDE_UNSUPPORTED_BY_CORE_API` 로 «대상 변경 전» 거부. 근거: `api.add/search` 는 `PipelineConfig.from_profile` 만 쓰고 per-call endpoint 인자가 없다(`pipeline.py:29~32`) — fail-closed 가 맞다 |
| 크래시 후 재생 | core publish 뒤 `finish_publication` 크래시 → 재실행 `ready_replay`, sources/revisions/generations 1·1·1, 프로바이더 0(테스트 3). ★단 B1 의 «재시도 job 중 크래시» 는 별개 경로★ |
| 소스 펜스 | 기존 source 가 있으면 `fetch_original(include_bytes)` 로 바이트·media_type·origin_uri 3항 대조 후에만 진행 — 절대 `update` 로 덮지 않음(발주 «불변 창» 과 일치) |
| 만료 in-flight (C15) | 프로브 `test_h12`: core `add` 직후 시계를 91일로 → bridge 는 `WINDOW_INELIGIBLE_AFTER_CORE_PUBLICATION(retryable=False)`, 창 `invalidated/source_expired`, `finish_publication(success)` 미호출. 검색 프로브: **core 직접 검색은 그 source 를 eligible 1 로 보지만 bridge `search_history` 는 eligible 0·결과 0** — 창 ID 화이트리스트가 정확히 가린다. 검색 중 시계 이동(테스트 6)은 `ELIGIBILITY_CHANGED_DURING_SEARCH` |
| 한글 UTF-8 왕복 | 프로브 `test_h4`: `"설정 오류를 확인해 주세요 — 한글 "` → 창 문서(`ensure_ascii=False` 정규화, lifecycle 과 동일 규약이라 `document_sha256` 재계산 일치) → core → 검색 hit 의 `original_text`/`embedded_text` 에 원문, anchor `turn_id=msg:…`·`pointer=/turns/0/text`·`granularity=exact` |
| 소유자·프로젝트 격리 | 검색은 `lifecycle.refresh(scope)` 의 `searchable_window_ids` 만 `source_keys` 로 넘김 + 결과 `source_key ∉ 파티션` 이면 `CORE_SEARCH_SCOPE_VIOLATION`. 외부 source(테스트 5 `foreign`) 결과 0 |
| >100 파티션 | 205창 → `[100,100,5]` 파티션, 누락 0, `mode=partitioned_core_hybrid_bridge_rrf` + limitation 문구. 라벨된 double 사용을 docstring 에 명시(테스트 7). 계획 §7 의 «100개 필터에 임의 ID 를 밀어 넣지 않는다» 는 facade 인증을 대체하지 말라는 뜻이고, 여기서는 인증이 `AuthenticatedScope`→lifecycle 에서 끝난 뒤의 «가시성 필터» 라 위반 아님 |
| 검색 전후 재대조 | `refresh` 전·후 + `verify_projection_links` 전·후 4회. 각 창의 generation.profile_key·origin_uri·media_type 대조 |

### 수정 권고 (blocker 아님)

**R-1 — 등록 스트림을 늘리면 그 전에 닫힌 창을 영원히 발행할 수 없다** (`bridge.py:133~135`, `lifecycle.py:_store_window` provenance)
- 프로브 `test_h26`: `streams=("stream",)` 으로 창을 닫은 뒤 `streams=("stream","stream-2")` 로 refresh → 그 창이 `pending_publication_ids` 에 나오는데 bridge 는 `provenance.scope != scope.to_dict()` 로 `WINDOW_SCOPE_MISMATCH` 를 **raise** 하고, 창은 `index_pending/processing` 에 남는다(`finish_publication` 미호출 → 다음 주기에 같은 예외 반복, 게다가 예외라 같은 배치의 다른 창 발행도 중단).
- 판단: owner/tenant/project 불일치를 막는 의도는 맞지만 `enrolled_streams` 는 «권한 집합» 이라 확장이 정상 운영 경로다(계약 `sharing_scope same_owner_same_project_enrolled`). 수정: 비교를 `owner_id/tenant_id/project_id` 3항 + «창의 `stream_id` ∈ 현재 `enrolled_streams`» 로 바꾸고, 불일치는 raise 대신 그 창만 `finish_publication(success=False, error_code=...)` 로 표시해 배치를 계속한다. 테스트 1건.

**R-2 — `_finish_failed` 가 core 오류 코드를 그대로 `error_code` 로 넘겨 lifecycle `_identifier` 검증에 걸릴 수 있다** (`bridge.py:205~215`)
- core `map_exception` 은 코드가 고정 문자열이라 현재는 통과하지만, `CORE_STATUS_FAILED:{code}` 처럼 bridge 자신이 콜론을 붙이는 형식은 `error_code` 로 안 들어가고(raise 경로), 반대로 core 코드가 공백·제어문자를 포함하면 `INVALID_PUBLICATION_ERROR_CODE` 로 finish 자체가 실패해 창이 `processing` 에 남는다. 수정: `_finish_failed` 에서 `re.sub(r"[^A-Z0-9_]", "_", code)[:64]` 정도로 정규화. 현 코드로 재현되는 값은 없어 권고.

**R-3 — `search_history` 의 `verify_projection_links` 는 창 수만큼 `status`+`generations`+`fetch_original` 3쿼리를 «검색 전후 두 번» 친다** (`bridge.py:478, 537`)
- 205창이면 검색 1회에 ~1,230 쿼리. 기능 결함은 아니고 P08A-07 성능 검증(창 조립 p95≤500ms)에서 잡힐 항목. 수정 방향: 검색 후 재검증은 `searchable_window_ids` 동일성 + hit 에 등장한 창만 링크 검증으로 축소. 지금은 기록만.

### 미결 가설 (실측 못 함 — 후계가 이어받을 것)

- H-A: `publish_pending_windows` 가 `refresh(task_completed/explicit_save)` 로 «새 창을 닫으면서» 발행한다 — 발행 실패가 나도 창은 이미 닫혀 있어 정상(불변 창). 확인만 필요, 결함 의심 없음.
- H-B: 두 프로세스가 같은 창을 동시에 `claim_publication` → 둘 다 `add_request_id` 동일 → core 는 한쪽 `IN_PROGRESS(retryable)` 반환 → `_finish_failed` → 다음 주기 `ready_replay` 예상. B1 수정 뒤 같은 프로브로 함께 실측 권장.
- H-C: 아카이브 전환된 창(`source_expired`)의 core source 는 **삭제되지 않고 남는다**(프로브 h12 에서 `deleted_at_ms=None, ready_generation_id=1`). bridge 는 가리지만 core 직접 검색·백업에는 계속 존재. 이것은 bridge 의 범위가 아니라 계획 §7 «만료·삭제는 core delete 로 현재 검색에서 제외» 를 누가(runtime? P08A-09?) 구현하는가의 문제 — 11차는 관찰만 기록, 판정은 코디네이터.

### 다음 단계 조건

B1 은 분기 1줄 + 테스트 1건이고 닫는 증거는 프로브 H2 시나리오에서 `searchable_window_ids` 에 창 1개·프로바이더 호출 1회다. R-1 은 실제 운영(스트림 추가 등록)에서 바로 만나는 경로라 P08A-08 시연 전 처리 권장. memory.py(12차)는 별도 좌석에서.

### 11차 B1·R-1·R-2 재판정 — **PASS (bridge blocker 0)**

수정본 펜스: `bridge.py` md5 `ffa5891ba7f73bee59fd55a9fe8ce59f` · `test_bridge.py` md5 `b5739393ebc0998c1fbc2260336833b6`(21:44:12). diff 직독 + 실행, 실행 전후 md5 동일.
- **B1**: `latest_status in {"failed","pending","running"}`(`bridge.py:272`) — `running` 도 core `retry` 로 보내 리스 회수. 워커 회귀 `test_crash_during_retry_recovers_after_lease_expiry` 는 크래시→리스 만료→회복→`action=retry`→재실행 `[]`(pending 소진) 을 단정. 11차 독립 프로브 H2 재실행: 이전 `add_replay×3·프로바이더 0·failed` → 지금 **`retry` 1회·프로바이더 1회·job2 done·창 searchable**. 닫힘.
- **R-1**: `_window_content` 가 `owner_id/tenant_id/project_id` 3항 + `provenance.stream_id ∈ scope.enrolled_streams` 로 비교(`bridge.py:136~143`). 회귀 `test_new_stream_enrollment_does_not_reject_existing_window` + 프로브 H26 재실행: 이전 `WINDOW_SCOPE_MISMATCH` raise → 지금 **`add` 성공**. 다른 owner/project 는 여전히 거부(3항 비교 유지). 닫힘.
- **R-2**: `_finish_failed` 가 `[A-Z][A-Z0-9_]{0,127}` 정규식에 안 맞는 코드를 `CORE_PUBLICATION_FAILED` 로 대체 — lifecycle `_identifier` 를 통과하지 못해 창이 `processing` 에 남는 경로 제거. 닫힘.
- **H-C 결정(코디네이터)**: core 는 불변 근거 저장소, 사용자·agent 의 normal search 는 consumer facade 만. 만료는 facade eligibility·current-time gate 로 제외하고 core 원문 보존을 «물리 삭제» 로 오인하지 않는다 — 프로브 h12 관찰(bridge eligible 0 / core 직접 eligible 1)과 정합. 판정 종결.
- 실행: `test_bridge.py` **9 passed (4.50s)**. 프로브 5건 5 passed(H2 프로브는 «재실행이 빈 목록을 돌려준다» 를 반영해 1줄 보정 — 로직 변경 아님). R-3(링크 검증 쿼리량) 은 P08A-07 성능 항목으로 유지.

11차 최종: bridge **PASS**. 이 좌석(ft-airag-da-fable51#1, ctx 97%)은 여기서 판정을 닫고 memory 12차는 후계 좌석에서.

---

## 코드 리뷰 (12차) — `memory.py` 독립 리뷰 (증거 검증 배치 메모리 추출)

- 좌석: ft-airag-da-fable51#2 (claude-fable-5-1[1m] · high · Serena 미노출→grep) · 계약 `da-memory-runtime.txt` · 구현 좌석 ft-airag-collect-sol#0 (`memory-result.json` PASS 주장).
- 펜스: `memory.py` md5 `d662b143ac7ae09b9215947739bfdd3b` · `test_memory.py` md5 `01aa7c72ac76d57c907e41fa7c127a60` — 리뷰·프로브 전후 동일. 소스 무편집.
- 실행: `test_memory.py` **18 passed (0.11s)**. 독립 프로브 6건(P1~P6, 합성 provider 만 · 실 엔드포인트 0회) — 스크래치 `da12_memory_probes.py`, 출력 `da12_probes_run1.txt`.

### 판정: **조건부 PASS — blocker 2건(B12-1 unverified 후보 1건이 lineage 선두를 영구 점유 · B12-2 결정적 실패 무한 재시도 + `retryable` 플래그 미소비). 정확 인용·앵커·스코프·확인 게이트·중복 방지·시크릿 비저장은 실측 PASS.**

### Blocker

**B12-1 — verifier 가 있으면 `unverified` 후보가 든 완료 배치가 매 호출마다 선두로 재선택되고 새 배치는 절대 생성되지 않는다.**
- 경로: `extract_memories` 가 `_active_batch` 없음 → `verifier is not None` 이면 `_unverified_batch`(state=complete + disposition=unverified 존재) 를 잡는다(`memory.py:~1000`). 그 배치는 `state == "complete"` 분기로 `_materialize` 만 다시 돌고 `continuation_required=more` 를 돌려주며 **`_create_next_batch` 로 가는 경로가 없다**(`memory.py:~1041`). verifier 가 계속 False 면 다음 호출도 같은 배치.
- 재현(P1): eligible 3건, `max_messages_per_batch=1`, provider 가 `verified_solution` 1건 반환, verifier 항상 False. 6회 호출 결과 `batch_ordinal` 전부 0 · state complete · `continuation_required=True` · provider 1회 · DB 배치 1개. m2·m3 는 영원히 추출되지 않는다.
- 운영 영향: runtime `run_once` 는 매 사이클 `extract_memories(..., verifier=self.hooks.memory_verifier)` 를 1회 호출한다(`runtime.py:685~715`, 참고만·미동결). verifier 가 설정된 운영에서 «검증 못 한 해결책 1건» 이 그 scope 의 메모리 추출 전체를 막는다. 계약 `first_completion_requires` 「decision_progress_and_verified_solution_memory」 위반.
- 수정 방향(설계 판단은 architect): unverified 재검증은 «새 배치 생성 뒤» 또는 «별도 호출(`recheck_unverified`)» 로 분리해 선두 점유를 없앤다. 회귀 = P1 조건에서 6회 호출 후 ordinal 0·1·2 전부 생성.

**B12-2 — 결정적 실패에 시도 상한이 없고 `MemoryProviderError.retryable=False` 가 어디서도 소비되지 않아, 실패 배치가 프로바이더를 무한 재호출하며 lineage 를 막는다.**
- 경로: `state == "failed" and retry_failed` → 무조건 `attempts+1` 후 재호출(`memory.py:~1043`). `retryable` 은 정의·raise 만 있고 grep 소비처 0. `retry_failed` 는 runtime 이 넘기지 않아 기본 True.
- 재현(P3): provider 가 매번 같은 fabricated quote(temperature 0 이면 실모델도 결정적) → 25회 호출 모두 ordinal 0 · state failed · attempts 25 · 배치 1개. `PROVIDER_REQUEST_TOO_LARGE(retryable=False)` 도 5회 호출 5회 재시도.
- 계약 대조: C07 「single publication for each failure stage」· 「retry/no-duplicate calls」 위반. `memory-result.json` limitations 는 «ambiguous pending 미재발행» 만 적고 이 무한 재시도는 문서화 없음.
- 수정 방향: non-retryable 코드는 즉시 terminal(`failed_terminal` 또는 `rejected`) · retryable 은 상한 N 뒤 terminal · terminal 배치는 `_active_batch` 에서 제외하고 결과 `reasons` 에 노출(운영자 skip/quarantine 은 명시 API). 회귀 = P3 조건에서 호출 수 ≤ N+1 이고 ordinal 1 이 생성.

### 확인된 정확한 동작 (실측)
- 정확 인용·앵커: `quote not in by_anchor[anchor].text` 는 «그 프래그먼트에 보낸 텍스트» 기준 substring · 앵커·proof 전부 현재 배치 멤버여야 함 · 커버리지 불일치 거부(테스트 4종 + 코드 직독).
- 버전 펜스: 프래그먼트 identity 에 `version_signature` 포함, `_batch_context` 가 sha·길이·버전 재검증 → 편집 시 stale + 새 버전 프래그먼트 재생성. 소스 성장은 새 배치만(테스트 `sealed_message_batches…`).
- 중복 호출 방지: P6 — materializing 중 크래시(2번째 create_memory 에서 KeyboardInterrupt) 후 재실행 → provider 0회 · materialized 3 · 메모리 3(중복 0, `create_memory` 결정적 id + INSERT OR IGNORE).
- 스코프: P5 — 다른 owner · streams 상위집합 모두 `MEMORY_CANDIDATE_NOT_FOUND_OR_SCOPE_DENIED`. lineage 가 `scope.to_dict()` 전체에 고정.
- 확인 게이트: preference/instruction_quote 는 `awaiting_confirmation` 만 · `confirm_candidate` 가 `explicit_confirmation=True` 로 lifecycle 에 넘겨 `human_validated`. 자동 승격 경로 없음. 만료 뒤 확인은 `SOURCE_CHANGED_BEFORE_CONFIRMATION`.
- 해결책 게이트: verifier 없음 = `unverified`(`VERIFICATION_EVIDENCE_REQUIRED`) · 모델 주장만으로 verified 불가 · verifier 예외는 `VERIFIER_FAILED`.
- 한계값: 요청 바이트·응답 바이트(`read(n+1)`)·max_tokens·timeout·후보 50·텍스트/인용 16KiB·strict JSON(중복 키·NaN 거부)·모델 에코·finish_reason=stop·tool_calls 거부.
- 시크릿: 실패는 코드만 저장(테스트 `TOP_SECRET` 부재 확인) · 후보 텍스트에 `redact_text` 적용.

### 수정 권고 (blocker 아님)
- **R12-1 pending 영구 점유(P2)**: provider 호출 중 크래시 → `pending` 이 소스 변경/만료 전까지 lineage 를 막고 provider 0회. 문서화된 한계지만 운영자 재발행 API 나 lease 가 없다 — 14차에서 runtime 이 이 상태를 «관측·해소» 하는 경로가 있는지 확인. (P2 의 89일차 `stale` 는 만료 때문이고 append 뒤 `source_complete` 는 프로브의 occurred_at 기본값 탓 — 결함 아님.)
- **R12-2 refresh 부작용(P4)**: 후보 3건 1배치 추출에 `lifecycle.refresh` **6회**. refresh 는 창 생성·만료 큐·read gate 를 «쓰는» 함수라 메모리 추출이 창 생성 부작용을 낼 수 있다(`_current_sources` 가 매번 refresh). 읽기 전용 reduction 사용 권고.
- **R12-3 엔벨로프 화이트리스트**: `id/object/created/model/choices/usage/system_fingerprint` 외 키가 하나라도 있으면 `INVALID_PROVIDER_ENVELOPE`. vLLM 계열은 `prompt_logprobs`·`kv_transfer_params` 등을 넣을 수 있어 main 의 IAP 18703 실모델 격리시험에서 전건 실패로 보일 수 있다 — 격리시험 결과로 판별(관용 vs 엄격은 정책).

### 다음 단계 조건
B12-1·B12-2 수정본 md5 + 회귀 테스트 2건 + P1·P3 프로브 재실행으로 재판정. 소스 무편집 유지.

### 12차 B12-1·B12-2 재판정 — **PASS (memory blocker 0)**

수정본 펜스: `memory.py` md5 `543168718e68fccc7312be9f56502a41`(22:09:47) · `test_memory.py` md5 `133725546de10b739689c4042ab3a59f`(22:10:04). 코디네이터 지시대로 «기존 프로브 6건 재실행 + 변경 지점 직독»만, 새 검토 없음. 실행 전후 md5 동일. 출력 `da12-probes-run2.txt`.
- **B12-1**: 선두 선택 순서가 `_active_batch` → **`_create_next_batch`** → (없을 때만) `_unverified_batch` 로 바뀜(`memory.py:1020~1029`). P1 재실행: 이전 6회 전부 ordinal 0 → 지금 **ordinal 0·1·2 생성, provider 3회, 이후 3회는 unverified 재검증만(provider 0)**. 회귀 `test_unverified_completed_batch_does_not_starve_later_batches`. 닫힘.
- **B12-2**: 실패 시 `airag_memory_failure_policy(extraction_id, retryable)` 에 분류를 durable 기록(`memory.py:1095~1125`) — `MemoryProviderError.retryable` 소비 · `MemoryExtractionError`(검증 실패)는 non-retryable. non-retryable 은 `attempts` 증가·재호출 없이 `continuation_required=False, source_complete=False` 로 반환(`1067~1071`). P3 재실행: 이전 25회 호출 attempts 25 → 지금 **provider 1회 attempts 1**, non-retryable 코드도 1회. 회귀 `test_non_retryable_provider_failure_is_not_reissued_or_continued`. 닫힘.
- 실행: `test_memory.py` **20 passed (0.15s)**. P2·P5·P6 결과 이전과 동일(회귀 없음).
- **잔여 관찰 R12-4(판정 무관 · 설계 선택 기록)**: non-retryable 배치는 state `failed` 로 남아 `_active_batch` 가 계속 선두로 잡는다 → 그 lineage 는 «멈춤»(P3 에서 배치 1개, m2·m3 미추출). 무한 재시도는 없어졋고 상태가 `continuation_required=False ∧ source_complete=False` 로 구분되므로 fail-closed 로 인정. 다만 운영자가 이를 풀 API(skip/quarantine)는 없다 — R12-1(pending 영구 점유)과 같은 계열로 runtime 운영 정책 항목. 또 `except Exception`(분류 불명) 은 retryable=True 로 남아 매 poll 1회씩 재호출된다(상한 없음 · poll 당 1회이므로 폭주는 아님).
- **실모델 오류 — 두 현상 동시 존재(코디네이터 진단, 정정 2026-09-27)**. 앞 판정문의 「엔벨로프 가설 기각」은 **철회**한다. 새 review 확장 없음, 사실 정정만.
  - ① `memory-exact-diagnosis.log`: 공개 8문장 batch(입력 1794B) → extractor 1회 **60.01초 → `PROVIDER_UNAVAILABLE`**. `timeout_s=60.0` 기본값 타임아웃(`urlopen` TimeoutError, retryable=True). runtime 은 timeout 을 넘기지 않아 60초 고정(`runtime.py:~707`). 운영 환경(IAP 실모델 응답 지연) 항목.
  - ② `memory-single-diagnosis.log`: 동일 자료 batch 1문장(186B) → **18.14초 HTTP 응답 뒤 `INVALID_PROVIDER_ENVELOPE`**, DB `failed/attempts 1`, non-retryable 이라 `continuation_required=false`. 코디네이터 keys-only POST(0.79초 HTTP 200 · finish_reason stop) 실측: 응답 root 에 `service_tier / prompt_logprobs / prompt_token_ids / prompt_text / kv_transfer_params / ec_transfer_params / metrics` 존재 → `memory.py:281~283` 화이트리스트(`id/object/created/model/choices/usage/system_fingerprint`) 밖 키로 거부. **R12-3 은 가설이 아니라 실결함(별도)** — `memory-result.json` 이 «OpenAI-compatible» 을 주장하지만 vLLM 계열 표준 응답을 전건 거부한다. owner 가 «필수 필드 검증 유지 + 미사용 메타 무시» 로 수정 중(수정본 md5·`test_memory` 회귀 1건 통보 시 P-엔벨로프 프로브 1회로 확인 — 새 검토 아님).
  - 두 현상은 같은 실모델에서 입력 크기에 따라 갈린다(8문장=타임아웃, 1문장=응답 도착 후 엔벨로프 거부). ①은 운영, ②는 코드.

12차 최종: memory **PASS(B12-1·B12-2 닫힘)** + **R12-3 엔벨로프 화이트리스트 실결함 별건 오픈(owner 수정 중)**.

### 12차 R12-3 재확인 — **닫힘 (memory 최종 PASS · 12차 종료)**

수정본 펜스: `memory.py` md5 `7b28b4f6053bda8b02642155a1cadd0a` · `test_memory.py` md5 `c6ca889c6c8c0d02374a2e7e99b481b8`. 코디네이터 지시대로 엔벨로프 회귀 1건만 재확인, 새 검토 확장 없음. 실행 전후 md5 동일.
- 직독(`memory.py:281~297`): root 키 화이트리스트(`set(envelope) - {...}`) 제거 → `isinstance(envelope, dict)` 만. 필수 검증 유지 = model 에코 일치 · choices 정확히 1개 dict · `finish_reason == "stop"` · message dict + tool_calls 없음 · content str · strict JSON 파싱. 미사용 메타(`service_tier/prompt_logprobs/prompt_token_ids/prompt_text/kv_transfer_params/ec_transfer_params/metrics`)는 읽지 않고 무시.
- 회귀 `test_openai_adapter_ignores_unused_vllm_metadata_without_persisting_prompt_text`(`test_memory.py:414`): vLLM 계열 root 메타 포함 픽스처 → 추출 성공 + `prompt_text` 값이 durable 행 어디에도 없음 단정. 단독 1 passed · 전체 **21 passed (0.15s)**.
- 코디네이터 실측(owner 보고): 실 BYZ 엔드포인트 batch1 **7.082초 complete / candidates 1 / materialized 1 / errors 0** — ② 현상 해소. prompt v3(proof/non-solution `[]`·conflict bool 명시)는 후보·인용 검증 무변경이라 기존 프로브 판정 유지.
- 잔여: ① 8문장 타임아웃은 운영 항목(timeout 60초 기본값) — main 이 업데이트 wheel CLI 8문장 batch 4실행 1회 확인 중, 그 값은 14차 착수 시 인용.

**12차 종료: memory PASS.**

---

## 코드 리뷰 (13차) — `reference.py` 독립 리뷰 (readonly 기존 tour 참조 검색 · 암호화 스냅샷)

- 펜스: `reference.py` md5 `3a3892d87ecd603bff70b8003969adf2` · `test_reference.py` md5 `ad421c79c7e80bddc0f27ccc9ec90255` — 전후 동일. 구현 좌석 ft-airag-ops-sol#1.
- 실행: `test_reference.py` **4 passed (6.21s)**. 프로브 Q1~Q6(합성 core DB, 원본 tour.db·실 GPU 미접촉) — `da13_reference_probes.py`, `da13_probes_run2.txt`, `da13_q2_run.txt`.

### 판정: **PASS — blocker 0. 관찰 4건(14차 runtime 확인 항목으로 이관).**

### 확인된 정확한 동작 (실측)
- 원본 readonly: `open_readonly`(`mode=ro`+`query_only`) + `copy_database`(source 는 readonly backup API) → 원본 바이트 sha256 전후 동일 · 원본 `search_manifests` 0(Q4 + 테스트). 스냅샷 키는 호출자 명시 32B, 폴백 없음 · 잘못된 키는 `REFERENCE_SNAPSHOT_FAILED` 로 스냅샷 파일 미생성.
- frozen 17 allowlist: `_capture_state` 가 17쌍만 조회 · 미승인 소스·삭제 소스 제외(테스트). **stale ready 제외(Q2)**: `api.update` 를 provider 실패로 중단시켜 head_rev 6 ≠ ready_rev 2 상태를 만들자 `refund-policy.md` 가 결과에서 빠짐.
- 현재 소스 펜스: 스냅샷 상태 == 원본 상태 검증 → 검색 → 원본 재조회 == 최초 상태 + sha256 재비교(테스트 `revision_change_during_query` REJECT).
- 엔드포인트 override: 저장 프로필 불변(테스트가 원본·스냅샷 `chunker_config` 동일 단정) · 임베딩은 `fingerprint_space` 동일성, LLM 은 endpoint 제외 descriptor 동일성으로 거부 · 라우팅은 provenance 로 반환.
- transient manifest: `snapshot_only=True, original_database_manifest=False` 명시 · 그룹은 collection×space 로 분리, `global_merge=False`, 동일 space 다중 profile 은 `sorted()[0]` 결정적 + `compatible_profile_keys` 노출.
- 자격 일치 강제: core eligible count ≠ allowlist 그룹 크기면 `REFERENCE_ELIGIBILITY_MISMATCH`.

### 관찰 (14차 이관 · 판정 무관)
- **O13-1 스코프는 에코만(Q1)**: 무관한 owner/tenant/stream 스코프로 호출해도 그룹 2개 반환. 구현 노트가 「trusted caller provenance」로 명시한 한계 — 계약 `scope_check_points` 의 `before_retrieval` 는 **runtime 이 져야 한다**. 14차 확인 항목 ①.
- **O13-2 심링크 부모 거부(R-A)**: `_safe_paths` 가 부모 체인 심링크를 전부 거부 → macOS `tempfile` 기본 `/var/folders`(`/var`→`/private/var`) 는 `SYMLINK_REFERENCE_PATH_REJECTED`. 계약 allowed_real_paths 는 실경로라 무관하나 runtime `snapshot_root` 가 tempfile 이면 전건 실패. 14차 확인 항목 ②.
- **O13-3 WAL 사각(Q3)**: `_digest` 는 main 파일만 해시(-wal 미포함). allowlist 내 변경은 상태 재조회가 잡으므로 실질 가드는 상태 비교. 기록만.
- **O13-4 override 스킴 미검증(Q6)**: `not-a-url` 이 `_require_text` 를 통과해 core `config_from_profile` 에 위임됨(memory 쪽 config 는 `http(s)://` 검증). 일관성 권고.
- 스냅샷은 전체 DB 복제·자동 삭제 없음(문서화) → runtime 의 `snapshot_root` 위치·정리 소유·누적 관리는 14차 확인 항목 ③.

---

## 코드 리뷰 (14차) — `runtime.py` + `cli.py` (예약 · 동결 통보 수신 2026-09-27)

- 동결 펜스(수신 시점 실측): `runtime.py` md5 `2a4b5ac61444a2f9958508a8a8864e6c` · `cli.py` md5 `58aa8db6f81aa17d52e68b474e0628a1` · `test_runtime.py` md5 `a1752ef6c72dcda7d9f3477b9964dd1f`. 코디네이터 보고: `runtime-result.json` 17/17 · 전체 187/187 · CLI 독립 install/help 정상.
- 사전 확인 항목: ① reference 호출 «전» 스코프 게이트(O13-1) ② `snapshot_root` 심링크·tempfile·정리 소유(O13-2·O13-4) ③ memory pending/failed 관측·해소 경로(R12-1·B12-2) ④ `extract_memories` 재호출 정책(B12-1 영향) ⑤ 키 env 주입·누락 거부·자식 프로세스 env 제거 ⑥ 실모델 격리시험(IAP 18703/18712 · test 키 명시 · 별도 test profile) 결과의 엔벨로프 관용(R12-3) ⑦ 03:00 KST 백업·catchup·verified 게이트 연결.
- **보류(코디네이터 지시 2026-09-27)**: 사용자 시간 지적에 따라 14차 새 검토는 착수하지 않는다. 현재 집중 = memory B12-1·B12-2 수정 + 실모델 오류. 동결 시점 1회 실행값만 기록: `test_runtime.py` 17 passed(8.71s) · 전체 187 passed(7.49s) · md5 위와 동일.
- 사전 관찰 1건(판정 아님 · 착수 시 확인 항목 ⑧로): `runtime.search` 가 reference 스냅샷 키로 `self.keys["projection_db"]` 를 재사용한다(`runtime.py:~1125`). 계약 `target_key_gate` 「distinct keys … never reuse」의 정신과 대조 필요 — 스냅샷은 전체 tour DB 복제본이라 projection 키 유출 시 노출 범위가 합쳐진다.
