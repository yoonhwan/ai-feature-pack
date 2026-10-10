# 인덱스: 제안서 발행기가 「승인 — 판정 N」 제안서도 «기록»으로 발행 (R76 · 판정 809)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → R76(판정 809 · master#25 발주 #71288 · arch 카드 byz-harness-arch-claude#26)
- 상태: 대기
- 선행: 없음
- 시험 입력: 기존 가짜 슬랙 fixture(`tests/scripts/_proposal_fakes.py` `make_md(status=…)` · `slack` · `t`) — 실 슬랙 0
- 기준값: 지금 `- 상태: 승인 — 판정 351` 제안서는 `byz_proposal_publish.py` `parse_text` 72행에서 PublishError(「발행 대상이 아니다」) — 기존 시험 `test_bad_proposal_raises_before_any_post[상태 승인]` 이 그 거부를 고정하고 있다

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
골의 축: B 「메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의」 + C 「업그레이드하고 레포에 커밋 푸시 … 배포 발행(슬랙) 수신해 반영」. 업그레이드 대상 = 하네스 도구 `byz_proposal_publish.py` · 판정 809. 핵심 한 줄: 이미 승인·구현된 제안서를 슬랙에 «기록»으로 남길 수 있게 하고, 그 글이 결정 요청으로 읽히지 않게 첫 줄에 «기록» 표식을 단다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
`byz_proposal_publish.py` 는 제안서 md 를 슬랙에 올린다(뿌리 글 3칸 + md·쉬운 판 첨부). 머리 `- 상태:` 줄이 `초안|컨펌 대기|수정 요청 rN` 일 때만 발행한다(37행 `STATUS_OK` · 72행 검사). 그래서 오빠가 이미 승인해 구현까지 끝난 제안서(머리 `- 상태: 승인 — 판정 N`)는 슬랙에 기록으로 남길 길이 없다. 이 카드는 그 상태 하나를 더 받게 한다. 받은 글은 «결정 요청이 아님»이 첫 줄에서 보여야 하므로, 첫 줄을 `*제안서 <팀>/<slug> · 기록 판정 N*` 으로 바꾸고 결정 자리 줄(현역 planner 이름)을 싣지 않는다. 초안·컨펌 대기·수정 요청 rN 흐름은 바이트 단위로 그대로다.

## 사전검증
- 소환: 아니오
- 면제: 허용 상태 1개 추가 + 그 상태에서만 타는 분기(첫 줄·결정 줄·다음 칸) · 기존 흐름은 기존 시험 전부 PASS 로 닫음 · arch 서명 byz-harness-arch-claude#26

## 조사 근거 (live `~/.hermes/scripts/` == `origin/main` 추적본 `scripts/harness-install/slack-mirror/` — cmp 확인 2026-10-10)
- `byz_proposal_publish.py:37` `STATUS_OK` · `:59`~`:76` `parse_text`(상태 1줄 검사 · 칸 3개) · `:86`~`:94` `_root_ts`(rN 이 뿌리 글을 `first_line(key, "r0")` 로 원격에서 찾음) · `:96`~`:131` `publish`(`:102` 에서 `first_line` 으로 r0 중복 찾기 줄을 만듦) · `:157`~`:161` `block_of`(다음 칸 기본 = 「결정 대기 — …」).
- `proposal_text.py:14` `first_line(key, rev)` · `:23`~`:26` `text_of`(`:24` 에서 `first_line` 호출)(3째 줄 `decision_line(seats=…)`).
- `tests/scripts/test_proposal_publish.py:45` 「상태 승인」 거부 케이스 — 이 카드가 뒤집는다.

## 구현 범위 (닫힌 목록 · 추적본 `scripts/harness-install/slack-mirror/` 에서 수정 · 나노 브랜치는 origin/main 기준)
1. `byz_proposal_publish.py`
   - `STATUS_OK` 에 `승인 — 판정 [1-9]\d*` 추가. 대시는 U+2014 하나만 받는다.
   - `parse_text` 반환에 `"record": "<N>" | ""` 칸을 더한다.
   - `run`: record 제안서에 `--revision` 이 오면 `ERROR 기록 제안서는 rN 없음 — 새 제안서로` 를 내고 rc 1 로 끝낸다(게시 0). 이 규칙이 있으면 `_root_ts` 의 원격 찾기는 바꿀 필요가 없다.
   - `block_of`: record 면 다음 칸 기본값을 `기록 — 판정 N 승인 · 결정 대기 아님` 으로 한다.
2. `proposal_text.py`
   - `first_line(key, rev, record="")`: record 면 `*제안서 <key> · 기록 판정 N*` 이고 머리표는 그대로(`tag("작업상황", …)`) 둔다.
   - `text_of`: record 면 3째 줄을 `결정할 것: 없음 — 판정 N 으로 승인됨` 으로 바꾸고 `decision_line` 줄을 뺀다.
   - `first_line` 호출 2곳(`byz_proposal_publish.py:102` · `proposal_text.py:24`)에 모두 record 를 넘긴다 — 게시하는 첫 줄과 r0 중복 게시 방지 찾기 줄이 같아야 한다.
3. 시험(`tests/scripts/test_proposal_publish.py`)
   - ①「상태 승인」 거부 케이스를 지우고, 대신 `승인 - 판정 351`(하이픈) 과 `승인 — 판정 0` 거부 케이스를 넣는다.
   - ②신규: `승인 — 판정 351` 제안서 r0 발행 → 뿌리 글 첫 줄 = `*제안서 <KEY> · 기록 판정 351*` · 결정 자리 줄 0 · md·html 첨부 2 · 같은 r0 재실행 skip(게시 추가 0).
   - ③신규: record 제안서 + `--revision r1` → rc 1 · 게시 0.
   - ④기존 시험 전부 PASS(`test_proposal_publish.py` + `test_proposal_publish_faults.py` + `test_thread_post.py`).
4. 200줄 한도: `byz_proposal_publish.py` 는 지금 193줄이다. 넘으면 새 분기를 `proposal_text.py` 로 옮긴다(파일 분리 금지 · 기존 모듈 안에서).

커밋은 자기 브랜치, **push 금지**. **금지**: 초안·컨펌 대기·수정 요청 흐름의 글 모양 변경 · `mirror_share.HEADS` 변경(다른 발행기 공용) · 실 슬랙 호출 · 라이브 `~/.hermes/scripts` 직접 수정.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `python3 -m pytest tests/scripts/test_proposal_publish.py tests/scripts/test_proposal_publish_faults.py tests/scripts/test_thread_post.py -q` rc=0 · `ruff check` 변경 파일 0 · 두 파일 200줄 이하.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: python3 -m pytest tests/scripts/test_proposal_publish.py tests/scripts/test_proposal_publish_faults.py tests/scripts/test_thread_post.py -q rc=0 · 이슈: 0`.
- 랜딩 뒤 master 집행(카드 밖): 라이브 `~/.hermes/scripts/{byz_proposal_publish.py,proposal_text.py}` 를 `.bak-r76-<날짜>` 로 백업 → `cp` → `cmp` · `--dry-run` 1회(record 제안서 1개로 첫 줄 확인) · loom#11 에 R76 닫힘 1줄.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 991160ae970c5e6c85133a2b0eb48baae1484750 (spawn 2026-10-10)
대기 — master spawn 대기

## 결과
(닫을 때 증거 줄)
- 2026-10-10 08:50 — 대기→진행 · 좌석 byz-harness-nano-r76-proposal-publish-approved-record#0
