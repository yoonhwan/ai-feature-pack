# Nano item4 결과 — 기억 확인 투어(14-memory-confirmation)

- 세션: `ft-airag-nano-r1#0` · 모델: claude-sonnet-5-5[1m]
- 골의 어느 축인가: A03 — A02 트리 4순위(후보 C05·C06). 닫힘 = 사용자가 투어로 직접 처리 + catalog 수용(사용자 몫). 이 결과는 «구현+격리 검증» 까지이며 수용은 아니다.
- 커밋·push 안 함. 실운영 저장소·키·백업·기억 후보는 읽지도 쓰지도 않았다(합성 fixture 만). 키 값·기억 본문은 로그·결과·mbox 에 쓰지 않았다.
- 최종 pytest (`feature-pack/rag-consumer`, `../rag/.venv/bin/python -m pytest tests -q -p no:cacheprovider`): `217 passed in 6.95s` (기준선 212 + 신규 5)

## ① 대조 결과 — master 조사표는 코드와 맞다
| 경로 | 코드 확인 |
|---|---|
| 지침·선호 승인 | 있음 — `memory.py` `confirm_candidate` · `runtime.py` `memory_confirm` · CLI `memory-confirm`. 재사용(변경 없음) |
| 후보 거절 | 없음 확인 → 신규 |
| 해결책 사용자 검증 | 없음 확인 — `lifecycle.create_memory` 는 verified_solution 에 `explicit_confirmation` 을 금지(`AUTOMATIC_MEMORY_CANNOT_CLAIM_HUMAN_VALIDATION`)하므로 verifier 콜백과 같은 materialize 경로(`explicit_confirmation` 없음)를 사용자 결정으로 호출 → 신규 |
| 후보 본문·인용 조회 | 없음 확인(`status()` 는 id 만) → 신규 |
- 표에 없던 사실: ⓐ verifier 경로·사용자 검증 경로 모두 기억의 `approval_state` 는 `rule_checked` 다(코어 설계상 자동 종류는 `human_validated` 를 주장할 수 없음). 사용자가 검증했다는 사실은 기억 레코드가 아니라 투어 결정 로그(`tour-14-decisions.json`, id·행동만)에 남는다. ⓑ `.fable-team/` 는 `.gitignore` 대상이라 투어 파일(`notebook.py` 수정 포함)은 git 변경 목록에 나타나지 않는다.

## ② 구현한 API/경로
- `memory.py:1593 list_candidates(lifecycle, scope, *, disposition, limit, skip)` — 읽기 전용. 후보 id·종류·본문·원문 인용·상태·사유·`source_current`·(해결책) 성공 근거 원문(`proof_messages`). scope 필터는 confirm 과 동일. 페이지(limit≤50·skip).
- `memory.py:1645 reject_candidate` — awaiting_confirmation/unverified → `rejected` + `USER_REJECTED`. **터미널**: 이후 `confirm_candidate` 는 기존 `CANDIDATE_NOT_AWAITING_CONFIRMATION` 으로 거부(다시 승인 불가). 이미 rejected 는 기존 사유 그대로 멱등 반환, materialized 는 `CANDIDATE_ALREADY_MATERIALIZED`.
- `memory.py:1665 verify_candidate` — unverified 해결책 1건만, 기존 `create_memory(kind=verified_solution, proof_anchor_ids)` + 같은 트랜잭션 경계. 원문 변경 시 `SOURCE_CHANGED_BEFORE_CONFIRMATION` 으로 rejected(confirm 과 동일). 해결책 아님 → `CANDIDATE_NOT_A_SOLUTION`.
- `memory.py:1578 _scoped_candidate_row` 공용 조회(신규 함수들만 사용 — 기존 `confirm_candidate` 는 건드리지 않음).
- `runtime.py:1253-1281 _memory_decision`·`memory_candidates`·`memory_reject`·`memory_verify` (기존 `memory_confirm` 과 같은 lock·ledger·refresh 패턴, hooks.memory 시임 유지).
- CLI `cli.py:52-60,129-134`: `memory-candidates --state {awaiting_confirmation|unverified} [--limit N --skip M]` · `memory-reject <id>` · `memory-verify <id>`.
- 자동·bulk 승인 없음: 모든 쓰기는 id 1건 단위. 예외 메시지는 코드만(본문 미포함).

## ③ 추가 테스트·Red
- `test_memory.py`: `test_candidate_listing_shows_text_quotes_and_proof_without_writing`(:961) · `test_user_rejection_is_terminal_and_never_creates_memory`(:987) · `test_user_verification_materializes_only_the_named_solution`(:1010) · `test_user_verification_rejects_a_solution_whose_source_changed`(:1026)
- `test_runtime.py`: `test_cli_lists_then_rejects_or_verifies_only_named_candidates`(:965)
- Red: memory 4건 = `ImportError: cannot import name 'list_candidates'`(파일 수집 단계), runtime 1건 = 새 CLI 명령이 argparse 거부(`assert 2 == 0`).

## ④ 투어 셀 구성·런처
- `.fable-team/bin/tour/14-memory-confirmation.py` · 런처 `14-memory-confirmation.command`(11-memory 와 동일 형식, 실행권한) · helper `memory_confirmation.py`(reviewed_memory 패턴: `work(action, app=None, …)`, runtime 공개 API 만 사용) · `catalog.json` 에 `14-memory-confirmation` 추가(`user_accepted:false`, `awaiting_user_run`).
- 공통 `notebook.py`: `Cell.requires_enter` 추가(기본 False — 기존 투어 영향 없음). 켜진 셀은 «전체실행» 상태에서도 멈추고 Enter 를 받으며, 그 셀에서 전체실행을 입력해도 자동 진행을 켜지 않는다.
- 셀: ①운영 키 자동 연결 → ②후보 현황(읽기) → ③**백업 생성+격리 복원 검증**(쓰기·Enter) → ④지침·선호 후보 승인·거절·보류(쓰기·Enter; 후보를 본문·원문 인용·원문변경 여부와 함께 10개씩 표시, 승인·거절 번호를 사용자가 직접 입력, Enter=보류, 같은 후보 양쪽 선택은 전부 보류) → ⑤해결책 근거 검증(쓰기·Enter; 성공 근거 원문 표시, «검증됨 확정»·거절) → ⑥결과 정리(코어 재조회 대비표) → ⑦되돌리기 안내.
- 안전 게이트: helper `decide` 는 이번 투어의 검증된 백업 영수증(`tour-14-backup.json` + `verified_backup_ids` 일치)이 없으면 `CREATE_VERIFIED_BACKUP_FIRST` 로 거부. 한 번에 최대 20 id·중복·겹침 거부. 영수증·결정 로그에는 id·행동만 저장(본문 없음).

## ⑤ 격리 실행 결과 (합성 fixture, 운영 미접촉)
방법: scratchpad 하네스(미커밋)가 `tests/test_runtime.py` fixture 로 합성 프로젝트를 만들고(후보 5개: 지침·선호 3 + 해결책 2), 실제 helper 를 합성 런타임(`first_collection.runtime` 만 교체)으로 서브프로세스 실행, 실제 `notebook.run_notebook` 으로 7셀을 처음부터 끝까지 구동(`notebook.STATE` 도 scratchpad 로 우회).
- 백업 전 `decide` → exit 1 `CREATE_VERIFIED_BACKUP_FIRST`, 쓰기 0 ✔
- 전체실행 입력 → 셀①②자동, 셀③ 앞에서 «전체실행을 멈추고 Enter 확인» 출력 후 정지 ✔
- 셀③ 백업 생성·검증 통과 ✔ / 셀④ 범위 밖 번호 입력 → 재질문 ✔, 승인 2·거절 1 ✔, 재실행 → 후보 없음 ✔ / 셀⑤ 검증 확정 1·거절 1 ✔ / 셀⑥ 대비표 ✔ / 셀⑦ 안내 ✔ → `투어 완료` 7/7 `[완료]`
- 코어 재조회: 기억 0→3(승인 2+검증 1), 확인 대기 3→0, 검증 대기 2→0 ✔
- 영수증·결정 로그에 기억 본문·인용 문자열 없음 ✔
- 운영 저장소 미접촉: `find ~/.local/share/airag -newer <시작 마커>` 결과 0건 ✔
- 되돌리기 절차 실증(합성): DB 2개 이름 보관 후 백업의 `consumer.bin`·`projection.bin` 복사 → status 기억 0·확인 대기 3 (= 백업 시점) ✔
- 셀① 은 운영 키를 쓰는 11-memory 와 동일 셀(합성 환경에서는 합성 키가 env 에 있어 키 입력 단계 없이 env 점검만 수행). 실운영 1Password 경로는 실행하지 않았다.

## ⑥ 되돌리기 경로 사실
- 코어에 «승인한 기억 되돌리기» 없음. 해결책에만 `lifecycle.reopen_solution`(invalidated_reason 표시)이 있으나 runtime·CLI 에 노출되지 않았고 이번에도 노출하지 않았다. 거절은 번복 불가.
- 따라서 유일한 되돌리기 = 셀③의 검증된 백업으로 복원. 투어 셀⑦ 이 사용자 수행 절차(프로세스 정지 → 현재 DB 이름 보관(삭제 금지) → 백업의 consumer.bin·projection.bin 복사 → status 대조)를 명시하고 복원은 대신 실행하지 않는다. 복원 CLI 는 없다(`verify` 는 격리 검증만).

## ⑦ master 가 알아야 할 선행조건
- **설치 런타임이 새 코드를 갖고 있지 않다**: `~/.local/share/airag/runtime` 의 `airag_consumer` 는 복사본(비 editable)이며 `list_candidates` 가 없다(grep 0건). 투어 14 의 `.command` 는 이 설치 파이썬을 쓰므로 사용자가 실행하기 전에 설치 런타임에 rag-consumer 최신(212→217 커밋 포함)을 재설치해야 한다. 나는 운영 설치를 건드리지 않았다.
- 투어 파일은 gitignore 대상 — 보존·배포가 필요하면 master 판정(`git add -f` 여부).

## 변경 파일
- git 추적: `feature-pack/rag-consumer/src/airag_consumer/{memory,runtime,cli}.py` · `tests/test_memory.py`(+4) · `tests/test_runtime.py`(+1)
- gitignore 영역(`.fable-team/bin/tour/`): `14-memory-confirmation.py` · `14-memory-confirmation.command` · `memory_confirmation.py` · `notebook.py`(requires_enter) · `catalog.json`(항목 추가)
