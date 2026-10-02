model: claude-sonnet-5-5
provider: claude-code session (ft-airag-arch-claude#0, effort=high)

# AIRAG 상시 틱 exit 40 `COLLECTOR_SOURCE_BINDING_MISMATCH` — 원인 규명·설계

개정: r2+DA PASS 보정(R2-m1 zero-prefix 원인 무관 설명·zero-capture 회귀 / R2-m2 승인 게이트는 명시 답 필요·DB 쓰기 문구 정합·원인 가설 한계·E 는 legacy 첫 전환 한정) · 개정: r2 — DA 설계 r1(`da-20261001-sol-binding-design-r1.md`, REJECT major 1·minor 1) 반영: **D1** «전체 물리 R7 유지» 주장 철회 → **내용 연속성 계약**으로 명시 수용(안정적 volume 식별자 대안은 검토 후 기각 — ② 선택지 E)·반례를 의도한 acceptance 회귀로 고정·R7 의 유지/비유지 범위 표 · **D2** 테스트 입력 정정(stored row fixture·pending+drift·committed-prefix 0·`reason_code_review.py` 줄키 갱신)·«DB 무쓰기» 문구 정정 · 원인 가설 한계 명시와 읽기 전용 확인 절차 추가.
골 원문: 최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
골의 어느 축인가: A03·A02 5순위 U1(C12·C07) — 사용자 재수동 1회 #2 가 exit 40 으로 멈춘 건(체인 3단계). 입력: `.fable-team/state/airag/checker-binding-facts.json`(HEAD f02a882). 이 설계는 HEAD f02a882 에서 `collector.py`·`ledger.py`·`runtime.py`·tour 계획 파일(`tour-04-plan.json`, 읽기 전용)·부팅 이력을 직접 다시 읽어 확인했다. 운영 DB 는 열지 않았고 코드·runtime.json·launchd 는 건드리지 않았으며 키 값은 열람하지 않았다.

---
## ① 원인 규명

### 한 줄 결론
**수집기가 «소스 파일의 같은 파일 여부»를 판정하는 지문에 `st_dev`(디스크 장치 번호)를 넣어 DB 에 영구 저장하는데, macOS 에서 `st_dev` 는 재부팅마다 바뀔 수 있는 값이다.** 10-01 17:20 재부팅 뒤 같은 파일(inode·경로·세션 동일)의 `st_dev` 가 16777231 → 16777232 로 바뀌었고, 저장된 binding·incarnation 과 달라져 수집기가 «다른 파일»로 거부했다. 상시 서비스는 재부팅할 때마다 같은 증상으로 멈출 수 있는 구조 결함이다(일회성 운영 사고가 아님).

### 근거 (파일:라인, HEAD f02a882)
| # | 사실 | 위치 |
|---|---|---|
| 1 | 던지는 곳(type EventError): 저장 행의 `(source_path, real_path, device, inode, session, tenant, project)` 가 현재 값과 다르거나, normalized id 가 다르거나, **incarnation 이 다르면** 던짐 | `collector.py:330-334` |
| 2 | incarnation = sha256(`codex-rollout-incarnation-v1`, real_path, session, **str(st_dev)**, str(st_ino)). 즉 device 가 binding 필드이면서 incarnation 해시 입력이다 → device 가 바뀌면 두 비교가 동시에 어긋난다 | `collector.py:304-308` |
| 3 | 행이 없을 때만 INSERT 하고 **이후에는 device 를 갱신하는 경로가 없다** — 첫 수집 때의 device 가 영구 기준 | `collector.py:318-328` |
| 4 | 이 incarnation 은 수집기 안에서 끝나지 않고 **ledger·이벤트 체인의 핵심 식별자**다: `producer_epoch=source.incarnation`(`collector.py:724,743,760`), `ledger.ingest(incarnation=...)` → `Ledger._bind_source` 가 ledger `sources.incarnation` 과 대조해 다르면 `SOURCE_BINDING_MISMATCH`(`ledger.py:116-127`). **따라서 incarnation 을 «새 device 로 다시 계산»하는 수정은 이미 저장된 이벤트 체인과 ledger binding 을 깨뜨린다** | `collector.py:564-570`, `ledger.py:114-127` |
| 5 | 파일 동일성 증거는 device 만이 아니다: 매 수집마다 ① `_verify_session_meta`(첫 줄 session id, `:682`) ② `SOURCE_TRUNCATED`(크기 < 체크포인트, `:690-691`) ③ **소비한 전체 prefix 의 sha256 재계산·비교** `SOURCE_PREFIX_REWRITTEN`(`:692-693`) ④ 레코드별 `native_sha256` 이 이미 통과한 뒤에야 진행한다. 즉 «같은 바이트를 이어받는다»는 사실은 내용 해시로 따로 강제된다 | `collector.py:266-282(_verify_session_meta)`, `:690-693`(TRUNCATED·PREFIX_REWRITTEN), `:721`(PENDING_NATIVE_RECORD_CHANGED) |
| 6 | 함수 내부의 `(st_dev, st_ino)` 비교(`_open_enrolled` :234, `_finalize_plan` :581)는 **같은 실행 중 열기 전후 경합** 검사라 재부팅과 무관하다 | `collector.py:234,581` |
| 7 | 부팅 이력: 직전 재부팅 9-18 21:47 → **10-01 17:20:27**. tour-04 plan(09-28 14:06)이 기록한 device=16777231 은 9-18 부팅 구간의 값. 마지막 성공 수집(consumer.db mtime 10-01 14:20)도 17:20 부팅 **이전**. 현재 device=16777232(checker). inode 1186756666 은 plan 과 동일 | `last reboot`, `kern.boottime`, `tour-04-plan.json`, checker item3 |
| 8 | 저장 행의 device 가 16777231 이었음은 DB 를 열지 않고 **투어 도구의 자체 검사로 간접 확인**된다: 투어 `first_collection.py:80-81` 은 plan device/inode 와 현재값을 대조해 다르면 `SOURCE_IDENTITY_CHANGED` 로 중단 → 첫 수집·이후 투어 14 가 성공했다는 것은 그 시점 device == plan(16777231)이었다는 뜻이고, 수집기가 행을 만든 시점도 그 구간이다 | `first_collection.py:58-59,80-81`, checker item4 |
| 9 | 비교 필드 중 device 외에는 모두 같다: path·session 은 runtime.json 과 투어 payload 가 동일(checker item4), tenant/project 도 동일, inode 동일 | checker item2·4 |
| 10 | 왜 지금 처음 났나: 10-01 18:52 첫 수동 1회는 reference 키 검사에서 먼저 멈췄고(별건, arch-refkey-design), 그 수정 뒤 두 번째 수동 1회에서 처음 수집기에 도달했다 — 실행 순서상 이 오류는 재부팅 뒤 **첫 수집 시도**에서 드러난 것 | `runtime.py:992-1002`, checker call_path |

### 이 판정의 불확실성(숨기지 않음)
- **DB 의 저장 device 값은 읽지 못했다**(운영 DB 직접 열기 금지). 근거 8 은 간접 증거다. «device 가 유일한 불일치 필드»라는 결론은 코드·투어 증거·부팅 시각이 일관되게 가리키지만 DB 값으로 직접 확인된 것은 아니다.
- **검증 방법(필요 시 Master 가 집행):** 운영 DB 를 열지 않고 확인하려면 ① 수정 후 사용자 수동 1회가 exit 0 으로 통과하는지로 사후 확인(권고) ② 정말 사전 확인이 필요하면 `consumer.db` **읽기 전용 합성 복제**(복제본 + 키는 환경변수, op 값 비출력)에서 `airag_rollout_collector_sources` 의 `device`·`inode` 두 컬럼만 조회. 값은 보고서에 숫자 두 개만 적는다.
- 다른 필드(경로·세션·tenant·project)도 어긋났을 가능성은 낮지만(근거 9) 로그가 불일치 필드를 기록하지 않아 직접 배제하지 못한다 → 아래 ⑥ 의 진단 개선 제안 참조.

### 배제한 가설
- «소스 파일이 교체/복사됐다» — inode 가 plan 과 동일하고 mtime·크기 증가는 정상적인 append(codex rollout 은 진행 중 세션이라 자란다: `ops-u3-source-options` «지금도 자라는 중»). 새 inode 였다면 이 오류는 정당한 R7 탐지다.
- «allow_gaps True 변경 때문» — `allow_gaps` 는 binding 비교 뒤 레코드 분류에서만 쓰인다(`_classify` :421-465, binding 은 :683→:334). 관여 없음.
- «tenant/project/session 설정이 달라짐» — runtime.json 과 투어 payload 값이 동일(백업 대조: 차이는 allow_gaps 뿐).
- «운영 DB 손상» — throw 시 ROLLBACK 이고 mtime·크기 불변이라 **새로운 쓰기로 인한 손상 징후는 없다.** 다만 이것이 기존 논리 행 값이 정상이라는 직접 증거는 아니다(DB 미열람 — ⑥-1 확인 사다리).

---
## ② 해결 선택지 비교

| | A. 코드: device 를 «불변 신원»에서 «참고값»으로 (권고) | B. 운영: collector sources 행·ledger binding 재작성(DB UPDATE) | C. 운영: 행 삭제 후 처음부터 재수집 | D. 재부팅 때마다 임시 우회(수동 DB 조작) |
|---|---|---|---|---|
| 내용 | binding 비교에서 device 를 제외하고, incarnation 은 «저장된 device 로 재계산해 무결성만 확인»(새 device 로 재계산하지 않음). 신원 = (real_path, inode, session, tenant, project) + prefix sha256 | 저장 device·incarnation 을 새 값으로 UPDATE | 행·plans·events 삭제 후 0바이트부터 | — |
| 코드 변경 | `collector.py` 약 10줄 + 테스트 | 없음(운영 SQL) | 없음 | — |
| 운영 DB identity 재작성 | **없음**(정상 수집의 offsets·prefix·plans·events 쓰기는 평소대로) | **있음**(+ ledger sources·이벤트 `producer_epoch` 와의 연쇄 불일치 → 사실상 불가능·위험) | **있음**(데이터 삭제 = 파괴적, 14 백업 이전 상태로 되돌림) | 있음 |
| 재부팅 재발 | **해소**(device 변동 무관) | 재발(다음 재부팅마다 같은 UPDATE) | 재발 | 재발 |
| 이벤트 체인 보존 | **보존**(incarnation 불변 → producer_epoch·ledger binding 그대로) | 깨짐 위험(근거 4) | 폐기 | — |
| 되돌리기 | 커밋 되돌리기 한 번 | DB 복원 필요(백업 airag-set-20261001T141910-vtr794ux) | 백업 복원 | — |
| 사용자 승인 | 승인 게이트 1건(R7 보장 범위 재정의 한 문장 — 위 권고 절, 명시 답 필요) | **필요**(운영 DB 쓰기) | **필요**(파괴적) | — |

**E. 안정적 volume 식별자(device 대체) 검토 — 기각(DA r1 D1 대안)**: ① 후보: APFS volume UUID(`getattrlist(ATTR_VOL_UUID)`/`diskutil`), `st_birthtime`, 마운트 포인트. ② 기각 사유: 파이썬 표준 라이브러리에 volume UUID 가 없어 `ctypes` 플랫폼 종속 코드가 필요하고, **기존 행에는 해당 값이 저장돼 있지 않아**(스키마 컬럼 없음) 기존 행의 신원은 여전히 device 뿐이다 — 새 컬럼 마이그레이션 = 운영 DB 쓰기(사용자 승인 사안)이며, 마이그레이션 시점에 «이 파일이 그 파일인가»를 보증할 근거가 prefix 해시뿐이라 결국 같은 내용 연속성 판정으로 돌아온다. 마운트 포인트는 같은 데이터 볼륨의 재부팅 뒤 안정적이나 «다른 볼륨의 동일 경로»를 구분하지 못하는 경우가 있고 저장된 값이 없다. ③ 결론: **legacy 행의 첫 전환 시점에는** 안정 anchor 를 기록할 근거가 prefix 해시뿐이라 내용 연속성과 같은 보증밖에 못 준다. 다만 anchor 를 한 번 기록한 뒤의 **미래 재방문에서는** 추가 구분 이득이 있을 수 있다 — 이번에 E 를 선택하지 않는 것은 범위·복잡도(ctypes 플랫폼 종속·스키마 마이그레이션 = 운영 DB 쓰기 승인 사안) 때문이며 «안정 식별자가 언제나 무용»이라는 뜻이 아니다. 필요해지면 별도 설계로 다룬다.

### 권고: A
- **원인(불안정한 값을 영구 신원에 사용)을 직접 고친다.** B·C·D 는 같은 사고를 재부팅마다 되풀이하거나 이벤트 체인을 깨는 우회다.
- **저장 identity 를 재작성하지 않는다**(운영 DB 의 sources 행·incarnation·ledger binding 을 UPDATE/마이그레이션하지 않음). 정상 수집이 offsets·prefix·plans·events 를 평소처럼 쓰는 것은 변하지 않는다. 근거 4 때문에 incarnation 값은 절대 건드리지 않는다.
- **R7 보장은 «전체 물리 동일성»이 아니라 «내용 연속성»으로 재정의된다**(DA r1 D1 수용 — 3.2 표 참조): 새 inode·다른 경로·다른 세션·tenant/project 변경·소비한 바이트의 재작성/절단은 계속 거부하지만, **같은 realpath·같은 inode 번호·같은 session id·같은 소비 prefix 를 가진 다른 볼륨의 파일**은 «같은 소스의 이어받기»로 수용한다(그 파일의 suffix 가 달라도). 이 수용 범위는 의도된 계약이며 반례 테스트로 고정한다.
- **사용자 결정 필요 여부: 승인 게이트 1건(되돌리기 쉬움).** 운영 DB 쓰기·runtime.json 변경·재설치는 없다. 다만 위 «R7 보장 범위 재정의»는 이전에 DA 가 검토한 안전 경계의 의미를 바꾸므로 **최상위 Master 가 사용자에게 아래 한 문장을 묻고 «명시 답(수용/비수용)» 값을 받아 Nano 발주에 실어야 한다 — 무응답·이의 없음은 승인 값이 아니다.** 설계 DA PASS 는 기술 판정일 뿐 이 승인을 대신하지 않는다. 묻는 문장: **«수집기의 같은 파일 판정이 물리 디스크 번호가 아니라 내용 연속성(경로·inode 번호·세션·이미 소비한 바이트)이 된다 — 다른 디스크로 복제한 같은 prefix 의 파일은 같은 소스로 이어받는다»** (되돌리기: 커밋 되돌리기 한 번) 선택지: ①수용(권고: 재부팅마다 수집이 멈추는 것보다 낫고, 내용 해시가 소비한 바이트를 계속 강제) ②device 엄격 유지(재부팅마다 운영 DB 수동 조작 필요 — 비권고) ③안정 식별자 도입(기각, 선택지 E). 되돌리기: 커밋 되돌리기 한 번.

---
## ③ 권고안 A — 변경 명세

### 3.1 불변식
- B1: 첫 수집(행 없음)은 지금과 같다 — device·inode·incarnation 을 지금처럼 저장한다(저장 스키마·값 불변. 마이그레이션 없음).
- B2: 재방문 시 **일치해야 하는 것**: `source_path`·`real_path`·`inode`·`expected_session_id`·`tenant_id`·`project_id`·`normalized_source_id`. 하나라도 다르면 `COLLECTOR_SOURCE_BINDING_MISMATCH`(지금과 동일 — 특히 inode 교체는 여전히 거부).
- B3: **device 는 일치를 요구하지 않는다.** 저장 device 와 현재 device 가 달라도 위 B2 가 모두 같으면 통과한다.
- B4: **incarnation 은 «저장 행 자체의 무결성»만 확인한다**: 저장된 incarnation 이 `sha256(seed(real_path, session, **저장된 device**, 저장된 inode))` 와 같아야 한다. 다르면(저장값이 변조·손상) `COLLECTOR_SOURCE_BINDING_MISMATCH`. 통과하면 **저장된 incarnation 을 그대로 사용**한다(재계산·갱신하지 않음) → `producer_epoch`·ledger binding 불변.
- B5: 이후 단계는 그대로다 — `SOURCE_TRUNCATED`·`SOURCE_PREFIX_REWRITTEN`(소비 prefix 전체 해시)·`PENDING_NATIVE_RECORD_CHANGED` 가 «같은 바이트를 이어받음»을 계속 강제한다. device 가 바뀐 경우에도 이 검사를 건너뛰지 않는다.
- B6: 새 DB 쓰기 없음(행 UPDATE·컬럼 추가 없음). 저장 device 는 «생성 당시 기록»으로 남는다.

### 3.2 계약: 내용 연속성(Content Continuity) — R7 의 유지/비유지 범위 (D1)
**수집기의 «같은 소스» 정의(개정):** `source_id` 한 개는 `(real_path, inode 번호, session id, tenant, project)` 가 같고, **이미 소비한 prefix 의 sha256 이 같고**, 행의 incarnation 이 저장 값으로 자기 일관적일 때 «이어받을 수 있는 같은 소스»다. 디스크 장치 번호(`st_dev`)는 재부팅·마운트 순서에 따라 바뀌는 값이라 **신원이 아니다.**

| 사건 | 현재(device 엄격) | 개정(A) | 근거 |
|---|---|---|---|
| 재부팅 등으로 device 만 바뀜(같은 파일) | 거부(결함) | **수용** | 이번 사고 |
| 새 inode 로 교체(같은 바이트 포함) | 거부 | **거부** | B2 inode 비교 |
| 경로·세션·tenant·project 변경 | 거부 | **거부** | B2 |
| 소비한 prefix 재작성 | `SOURCE_PREFIX_REWRITTEN` | **동일** | B5 |
| 절단(크기 < 체크포인트) | `SOURCE_TRUNCATED` | **동일** | B5 |
| **다른 볼륨의 동일 inode 번호 + 같은 경로·세션 + 소비 prefix 복제 + «다른 suffix»** | 거부 | **수용(기존 incarnation·producer_epoch 로 새 suffix 수집)** | **의도된 비보장**(아래) |
| 저장 행 자체 변조(device/inode/incarnation 한 필드만) | 거부 | **거부** | B4 |

**의도된 비보장(DA r1 D1 인정):** 개정 규칙은 «물리적으로 같은 디스크의 같은 파일»을 보증하지 않는다. «같은 prefix 를 가진 파일은 같은 소스의 이어받기»로 취급하므로, 다른 볼륨에서 prefix 를 복제한 뒤 다른 내용으로 이어 쓴 파일(분기된 사본)의 suffix 를 기존 epoch 로 수용한다. 이를 안전하다고 주장하지 않고 **계약으로 명시**한다:
- 수용 근거: 단일 사용자 로컬 수집기에서 이 입력은 ① 디스크 마이그레이션·복원 후 이어 쓰기(정당) ② 의도적 분기 복제(비정상, 사용자 본인의 파일 조작)이다. 위협 모델은 소비한 바이트의 무결성이지 악의적 파일 대체가 아니다(prefix 해시가 상위 증거).
- first-row(offset 0)·pending-plan 시점의 수용 조건: 행이 방금 생성돼 `next_native_offset=0`·prefix=빈 해시이면 prefix 검사는 자명하게 통과하므로 B2 필드(경로·inode·세션·scope) 일치만이 증거다 — **이 상태(zero-prefix existing row)는 원인과 무관하게 생길 수 있다** — 예외 중단뿐 아니라 **정상 `captured_byte_limit=0` 호출**(루프 없이 반환)이나 작은 capture/batch 로 첫 레코드를 완성하지 못한 경우에도 행이 offset 0·빈 prefix 로 남는다(DA r2 R2-m1 합성 확인). 이 상태에서 device 가 바뀐 재방문은 B2 필드만으로 수용되며 기존 epoch 가 보존된다. **이 상태에는 «과거에 소비한 내용이 검증됐다»는 의미를 부여하지 않는다**(소비한 바이트가 없다). 두 원인 모두 테스트로 동작을 고정한다. pending plan(`planned` 상태)은 `native_sha256`·`PENDING_NATIVE_RECORD_CHANGED` 가 해당 레코드 바이트를 다시 확인한다.
- 이 비보장은 `data-lifecycle-da-review.md:715` 의 R7 서술(«같은 바이트·새 inode → MISMATCH»)과 **모순하지 않는다**(새 inode 는 여전히 거부). 다만 «다른 볼륨의 파일 교체 일반»까지 거부한다는 확장 해석은 무효임을 구현 결과 문서(B6)에 적는다.
- **B4 의 의미 정정:** 저장 행의 «자기 일관성 검산»일 뿐 모든 컬럼의 인증이 아니다(unkeyed hash — 일관되게 다시 쓴 행은 못 잡음). offsets/prefix 는 파일 검사가, producer_epoch 는 ledger binding·plan replay 가 각각 책임진다.
- **백업 복원 후 재방문:** 복원된 snapshot 의 행도 같은 정책을 받는다(`_verify_ledger_links` 는 device 를 비교하지 않으며 현재 소스의 물리 동일성을 증명하지 않는다).


### 3.3 변경 위치 (HEAD f02a882)
| 위치 | 변경 |
|---|---|
| `collector.py:300-334` `_load_or_create_source` | ① 행이 없을 때는 현재 코드 그대로(INSERT). ② 행이 있을 때: `stored_incarnation_check = _incarnation(real_path, expected_session_id, row[9], row[10])`(헬퍼로 seed 계산 추출 — 구조 변경) 로 B4 검사; binding 비교는 **device(row[9]) 를 제외한** 6개 필드 + normalized id(B2); 통과하면 `_Source(row[:7])` 반환(`incarnation` = `row[2]` 저장값 그대로). 신규 행 생성 시의 incarnation 계산도 같은 헬퍼 사용(값 동일) |
| `collector.py:304-308` | seed 계산을 `_incarnation(real_path, session_id, device, inode)` 헬퍼로 추출(동작 불변 — 별도 구조 커밋) |
| `reason_codes.py` | **변경 없음**(`COLLECTOR_SOURCE_BINDING_MISMATCH` 값 불변) |
| `tests/reason_code_review.py` | **줄 키 갱신 허용**(`collector.py:443` 의 `EXCLUDED_NON_MESSAGE_RESPONSE`·`EXCLUDED_REASONING` 항목이 `_incarnation` 추출·binding 변경으로 이동). `python tests/_regen_reason_codes.py` 가 알려주는 키만 고친다. 줄 패딩으로 가리지 않는다. 검증: `reason_codes.py` 값 불변(diff 없음) + `test_reason_codes` 통과 |
| `runtime.py:1049`(status 의 등록되지 않은 source_id 거부) | 무관·무변경 |
| `tick.py`·`_pass_child.py` | 무변경 |

변경 유형 분리(Tidy First): ① 구조 커밋: `_incarnation` 헬퍼 추출(동작 불변, 전체 테스트 통과) ② 행위 커밋: 비교 규칙 변경 + 테스트.

### 3.4 범위 밖 / 하지 않는 것
- 운영 DB 의 identity(sources 행·incarnation·ledger binding) 재작성·행 삭제, runtime.json 변경, launchd 변경, 재설치. (정상 수집이 offsets·prefix·plans·events 를 쓰는 것은 범위 밖 변경이 아님)
- 투어 도구의 `SOURCE_IDENTITY_CHANGED`(`first_collection.py:80-81`)·`tour-04-plan.json` 의 device 비교 — 투어 재실행 경로는 별개이며 이번 상시 틱 경로가 아니다(⑤ 잔여).
- 다른 소스 유형(현재 `codex-rollout` 만 존재)·ledger `sources` 테이블 스키마.

---
## ④ 테스트 명세 (Nano Red→Green — 합성 fixture만, 운영 DB·실제 rollout 경로 접촉 금지)

`tests/test_collector.py` 의 기존 헬퍼(`write_rollout`·`run_collect`·`open_ledger`·`collector_scope`)를 쓴다. **device 변경 재현 헬퍼**(신규, 테스트 파일 내): 소스 파일의 inode 에 대해 `os.lstat`·`os.fstat` 결과의 `st_dev` 만 `+1` 한 `os.stat_result`(10-튜플 구성)로 돌려주는 `monkeypatch`(`collector.os` 의 `lstat`/`fstat` 를 감싸되 다른 파일·다른 fd 는 원본). `_open_enrolled` 의 열기 전후 비교(:234)와 `_finalize_plan` 의 `FILE_IDENTITY_CHANGED` 비교(:581)는 같은 실행 안에서 둘 다 shifted 값을 보므로 통과한다.

| ID | 방법 | 단언 (Red = 현 코드에서 실패) |
|---|---|---|
| T-bind-device-drift-ok | rollout 1건 수집 → 장치 번호 shift 상태로 **같은 파일에 1건 추가 기록 후** 재수집 | **성공**(현 코드는 `COLLECTOR_SOURCE_BINDING_MISMATCH` → Red). 새 이벤트 수집됨 · 두 번째 수집의 `producer_epoch` == 첫 수집의 값(incarnation 불변) · ledger `sources.incarnation`·행의 `device` 컬럼이 **변하지 않음**(B1·B6) |
| T-bind-device-drift-repeat | shift 상태에서 여러 번 재수집(두 번째 shift 값 포함) | 매번 성공 · 이벤트 체인 연속(`ledger.checkpoint` 단조) |
| T-bind-replacement-still-rejected | 기존 `test_detects_file_replacement_even_when_bytes_match` 유지 + **device shift 와 새 inode 동시** | `COLLECTOR_SOURCE_BINDING_MISMATCH`(B2 — inode 교체는 device 와 무관하게 거부) |
| T-bind-field-mismatch-matrix | 합성 ledger 에 수집 1회 후, **같은 `source_id` 를 유지한 채** 아래를 파라미터화(DA r1 D2: source_id 를 바꾸면 다른 PK 로 새 행이 생겨 이 경로를 시험하지 못함): ① 다른 별칭 경로로 `source_path`/`real_path` 변경 ② `expected_session_id` ③ tenant ④ project ⑤ **저장된 `normalized_source_id` 컬럼을 합성 ledger 에서 직접 UPDATE**(stored-row fixture) | 전부 `COLLECTOR_SOURCE_BINDING_MISMATCH`(B2) |
| T-bind-stored-row-tamper | 행의 `incarnation` 또는 `device`/`inode` 컬럼을 테스트 합성 DB 에서 직접 변조 후 수집 | `COLLECTOR_SOURCE_BINDING_MISMATCH`(B4 — 행 자체 불일치) |
| T-bind-prefix-still-enforced-on-drift | shift 상태에서 소비한 prefix 의 바이트를 재작성 | `SOURCE_PREFIX_REWRITTEN`(B5 — device drift 가 prefix 검사를 우회하지 않음) · 절단 시 `SOURCE_TRUNCATED` |
| T-bind-drift-pending-plan | 기존 `test_restart_after_ledger_commit_replays_stable_pending_plan`(lost ack) 를 복제해 **재시작 직전에 device shift** 적용 | 재수집 성공 · plan `finalized` · `first_seen_at`·`normalized_sha256`·`producer_epoch`·체크포인트 불변 · events 개수 중복 0(잘못된 구현이 `source.incarnation` 을 바꾸면 여기서 실패) |
| T-bind-drift-before-first-commit | 행이 생성됐으나 `next_native_offset=0` 인 두 경우를 파라미터화: **(a) 정상 `captured_byte_limit=0` 호출**(예외 없음) **(b) 예외 주입으로 첫 레코드 전에 중단** → 각각 device shift → 재수집 | 성공(prefix 빈 해시이므로 B2 필드만으로 통과) · 정상 이벤트 수집 · epoch 불변 — 3.2 first-row 조건 고정 |
| T-bind-cross-volume-clone-accepted (**의도된 수용 — 반례 고정**) | 1) 수집 2) `os.replace` 로 **다른 물리 파일**(기존 소비 prefix 복사 + 새 메시지 suffix)을 같은 경로에 두고, **그 새 파일의 lstat/fstat 만** `st_dev+1`·**기존과 같은 `st_ino`** 로 일관되게 돌려주는 shift 헬퍼 적용(실제 다른 볼륨 마운트 없음) | **수용**·새 suffix 이벤트 수집·`producer_epoch` 가 기존 값(DA r1 반례 그대로). 테스트 이름·docstring 에 «의도된 계약: 내용 연속성, 물리 볼륨 동일성 비보장» 명시. 같은 시나리오에서 **device 동일(shift 없음)+새 inode** 는 거부로 대조(T-bind-replacement-still-rejected) |
| T-reason-review-keys | 구조 커밋(B1)과 행위 커밋(B3) 각각 뒤 | `tests/reason_code_review.py` 의 collector.py 키가 새 줄 번호로 갱신돼 `test_reason_codes` 통과 · `reason_codes.py` git diff 없음 |
| T-bind-incarnation-helper-parity | 헬퍼 `_incarnation(...)` 값 == 리팩터 전 인라인 계산(고정 입력의 골든 문자열) | 동일(구조 커밋 동작 불변) |
| T-bind-existing | 기존 `tests/test_collector.py` 전체 | 통과(회귀 0) |
| T-tick-drift-integration (선택, 시간 허용 시) | `tests/test_tick.py` 합성 config 로 첫 수집 후 shift 상태에서 `tick.main` 재실행 | exit 0 · `status: ok` |

회귀: consumer 디렉터리 `../rag/.venv/bin/python -m pytest tests -q -p no:cacheprovider` 전체. 기준선 수는 Nano 가 S0 에서 기록(이 설계는 테스트를 실행하지 않았다).

---
## ⑤ Nano 구현 단계

| 단계 | 내용 | verify |
|---|---|---|
| B0 | 기준선 전체 테스트 + `grep -rn "COLLECTOR_SOURCE_BINDING_MISMATCH\|_load_or_create_source\|incarnation" feature-pack` 호출자 확인 | 통과 수 기록 · 호출자 = collector·테스트·문서뿐 |
| B1 (구조) | `_incarnation` 헬퍼 추출 + T-bind-incarnation-helper-parity(골든은 B1 이전 코드로 계산해 고정) | 전체 통과 · 동작 불변 · 단독 커밋 |
| B2 (Red) | T-bind-device-drift-ok·T-bind-device-drift-repeat·T-bind-prefix-still-enforced-on-drift(+ 선택 T-tick) 추가 | drift 계열 Red(이유: 현 코드 `COLLECTOR_SOURCE_BINDING_MISMATCH`) |
| B3 (Green) | `_load_or_create_source` 의 비교 규칙 변경(B2~B4 불변식) | B2 Red 전부 Green |
| B4 | T-bind-replacement-still-rejected·field-matrix·stored-row-tamper·**drift-pending-plan·drift-before-first-commit·cross-volume-clone-accepted·T-reason-review-keys** 추가(보존·경계·의도 수용 확인) | 처음부터 Green 이어야 하는 것은 보존·거부 계열(아니면 규칙 과완화). cross-volume-clone-accepted 는 A 적용 뒤 Green(현 코드는 거부) |
| B5 | 전체 회귀 + `git diff --stat`: `collector.py`·`tests/test_collector.py`·`tests/reason_code_review.py`(줄 키만) (+선택 `tests/test_tick.py`) 만 | N passed · exit 0 · `reason_codes.py`·`tick.py` 무변경 |
| B6 | `docs/artifacts/nano-…-binding-result.md` 에 B1~B6 각 불변식의 «닫는 테스트» 매핑 + **3.2 표(유지/비유지 범위)·의도된 비보장 문장을 그대로 인용**(«물리 볼륨 동일성은 보장하지 않는다») | 코드 DA 대조용 |

---
## ⑥ 잔여·한계·사용자 관찰 항목 (과대 보장 금지)
1. **«device 단독 원인»은 우선 가설이다**(저장 행을 열지 못함 — 운영 DB 열기 금지). 코드·투어 검사·부팅 이력이 일관되게 가리키지만 plan 과 inode 가 같다는 것이 «다른 볼륨의 동일 inode 번호 사례»를 배제하지는 않는다. **확인 사다리:** ① 수정 후 사용자 수동 1회가 exit 0 → 가설 사후 확증. ② 같은 코드로 다시 막히면 B2 의 다른 필드나 B4(저장 행 incarnation 일관성) 문제 → ③ **읽기 전용 확인(필요 시 Master 집행, 운영 DB 직접 열기 아님):** `consumer.db` 를 scratch 로 복제한 복제본에 키를 환경변수로 주입해 `airag_rollout_collector_sources` 한 행을 읽고, **값은 출력하지 않고 필드별 «현재와 동일/상이» 불리언 7개 + incarnation 자기 일관성 불리언 1개만** 보고한다(예: `source_path:eq real_path:eq device:NE inode:eq session:eq tenant:eq project:eq incarnation_self_consistent:true`). 이 출력이 어느 필드가 다른지 직접 확정한다. 복제본은 작업 후 Master 가 정리(삭제 HIL).
2. **진단 한계(제안만 — 이번 범위 아님):** 오류가 어떤 필드 불일치인지 기록하지 않아 이번 같은 건이 사실 수집·추론에 의존했다. «불일치 필드 이름만(값 없음)» 을 틱 로그에 남기는 별도 개선을 후속으로 제안한다(값 비노출 경계와 충돌하지 않게 이유 코드 하위 필드 한정). 이번 수정에는 포함하지 않는다(인접 개선).
3. **수정 후 첫 패스의 운영 영향(별건, 정보 제공):** 마지막 수집 offset 은 투어 한도(plan 254,203B 근방)이고 소스는 현재 46,457,618B 라 첫 통과 후 큰 증분이 한꺼번에 들어온다. `max_batch_bytes`=8 MiB 라 여러 틱에 나눠 소화되며 기억 추출(U4, 공유 vLLM 부하)이 따라 붙는다. 이는 이미 사용자가 U3/U4 로 수락한 상시 운영 범위지만 **수정 후 첫 수동 1회가 평소보다 오래 걸리거나 gaps 를 보고할 수 있음**을 Master/사용자에게 알린다(`allow_gaps=true` 로 gap 은 메타 기록되고 진행).
3. **투어 도구 재실행 경로(`first_collection.py:80-81`)** 는 plan device 를 그대로 비교하므로 재부팅 뒤 투어 재실행 시 `SOURCE_IDENTITY_CHANGED` 가 날 수 있다. 상시 틱과 무관한 별도 경로라 이 설계 범위 밖이다.
4. **내용 연속성 계약의 의도된 비보장**(3.2): 다른 볼륨의 동일 inode 번호·경로·세션·소비 prefix 를 가진 «분기된 사본»의 suffix 를 기존 epoch 로 수용한다. 사용자에게 한 문장으로 알리고(② 사용자 결정 1건) 반례 테스트로 고정한다. 이 설계를 «전체 물리 R7 유지»로 표현하지 않는다.
5. **설계 DA 소환: 권고(1~2라운드).** 파일 신원 판정 규칙(R7 계열 안전 경계)을 완화하는 변경이므로 코드 DA 게이트만으로는 «규칙 완화의 타당성»이 늦게 검토된다. 이 설계는 정적 읽기만 수행했고 코드·테스트를 실행하지 않았다.
