# 인덱스: 판정 번호 원장 — ft-verdict.sh(seed·new·done·todo·list) · 루트 단일 물리 파일 · 단일 호스트 발급 (판정 421 설계 §2-1 · N1)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 판정 421·430(planner #62745) · 원장 R34 합침
- 상태: 대기
- 선행: 없음(안 = design/harness/DESIGN-news-tree-workqueue-viz-20261009.md §2-1 · §3 나노 1) · 나노 4(인박스)와 병렬
- 시험 입력: 임시 디렉터리 FT_ROOT(가짜 명부 seats-planner.json · 가짜 hostname 은 env FT_VERDICT_HOSTNAME 주입) — 실제 루트 원장 쓰기 0
- 기준값: 지금 판정 번호 원장 파일 0 개(design/planner/orders 1장뿐) · 408·410 번호 충돌 2회(구 planner 와 후계가 각자 발급)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: A(모니터·오빠 요청 — 판정 번호표를 오빠 상태판에). 핵심 한 줄: 판정 번호를 한 파일·한 머신에서만 발급해 충돌 0.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
planner 가 매기는 «판정 N» 번호는 지금 어디에도 원장이 없어(대화·BOARD 문장 안에만) 승계 때 구 좌석과 후계가 같은 번호를 두 번 냈다(408·410). 상태판(나노 2)의 «오늘 판정표»도 읽을 곳이 없다. 그래서 메인 루트 런타임 파일 하나(`<FT_ROOT>/.fable-team/state/verdicts.jsonl` · mailbox.jsonl 과 같은 자리)를 판정 번호의 유일한 권위로 두고, `ft-verdict.sh` 만이 쓴다. 번호는 lock 안에서 «max+1» · 사건은 append-only(new = 새 번호 · done/todo = 같은 번호 상태 갱신 → 조회는 n 으로 fold). 발급 권위는 명부 seats-planner.json 의 `_verdict_host`(호스트명)·`_verdict_root`(절대 경로)와 둘 다 같을 때만 · 아니면 거부(두 번째 머신·워크트리 사본 발급 0). 처음엔 planner 가 검증한 마지막 번호로 seed 1줄을 넣어야 발급이 열린다.

## 사전검증
- 소환: 아니오
- 면제: 사전 DA 는 소환됐고 2 HOLD 로 리뷰 종료(bounded_da_review · 판정문 design/harness/DA-news-board-20261009.md §2~§8 · N1·N3 APPROVE · N2 잔여는 설계 §8 정본 술어로 고정) → 오빠 컨펌 GO 판정 430·431(planner #62745 · master #62749) · 잔여는 완료 조건 시험으로 닫고 구현 DA 에서 재확인 — arch 서명 byz-harness-arch-claude#13

## 조사 근거
- `design/harness/DESIGN-news-tree-workqueue-viz-20261009.md:30` 판정 원장 계약(물리 파일·lock·사건 2종·권위 키·seed).
- `design/harness/DESIGN-news-tree-workqueue-viz-20261009.md:68` 나노 배분 순서(나노 1 = 시험 목록).
- `tools/comm-canonical/mbox.py:61` 같은 런타임 디렉터리에서 창·상한을 env 로 받는 꼴(경로·env 이름 관례).

## 구현 범위 (닫힌 목록 · 추적본 + 키트 사본 같은 바이트)
1. `scripts/fable-team-bin/ft-verdict.sh`(+ `scripts/harness-install/fable-team/bin/` 사본):
   - `seed <n> --by <좌석>`: 파일에 seed 가 이미 있으면 rc 1 · 없으면 `{ev:"seed",n,ts,by}`.
   - `new --title "<한 줄>" --teams a,b [--seq 62xxx,…] [--oppa-todo "<한 줄>"]`: 권위 검사(hostname == `_verdict_host` ∧ realpath(FT_ROOT) == realpath(`_verdict_root`) · 다르면 rc 1 「발급은 <host> planner 에게」) → flock(`verdicts.lock`) 안에서 read-max(seed 포함) → append → fsync → 번호 stdout. seed 없으면 rc 1.
   - `done <n> [--note]` · `todo <n> --oppa-todo "<한 줄>"|--clear`: 없는 n 이면 rc 1 · 새 번호 0.
   - `list [--today] [--json]`: n 으로 fold(state open/done · oppa_todo 최신).
   - 파일 손상(JSON 아닌 줄) = rc 1 + 줄 번호(조용한 건너뜀 0).
   - 인자·원장·rc 꼴은 기존 원장 도구 `scripts/fable-team-bin/ft-hil-ask.sh` 를 따른다(새 관례 0).
2. 시험 `tests/harness/test_verdict_ledger.sh`: 같은 원장 두 프로세스 동시 new 20회 → 번호 중복 0 · 연속 · 호스트 불일치 거부 · 루트 불일치(워크트리 경로) 거부 · seed 없음 거부 · seed 425 뒤 첫 new = 426 · done 이 새 번호 안 만듦 · fold 결과 · 손상 줄 rc 1 · `test_kit_bin_sync.sh` PASS.

커밋은 자기 브랜치, **push 금지**. **금지**: 실제 루트 `.fable-team/state/verdicts.jsonl` 쓰기 · 명부 수정 · 분산 발급(다른 파일 문자열 일치로 권위 인정) · 손상 줄 건너뛰기.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_verdict_ledger.sh` rc=0 · `test_kit_bin_sync.sh` PASS · 사본 cmp · bash -n.
- RESULT 에 «동시 new 20회 번호 중복 0» 출력 2줄 복붙.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_verdict_ledger.sh rc=0 · 이슈: 0`.
- 랜딩 뒤 master·planner 집행(카드 밖): 명부 `_verdict_host`·`_verdict_root` 추가 · planner 검증 마지막 번호로 seed 1회 · 라이브 FT_BIN cp · planner 판정 발급을 ft-verdict.sh new 로 전환.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: d21481fe6cfb31a37c0be00020755cc36844a0e1 (spawn 2026-10-08)
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#13 · 판정 421·423·425-B 설계 r2 §8 · 오빠 컨펌 판정 430·431).
- 정본 영향 없음: 하네스 도구·훅·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-08 14:43 — 대기→진행 · 좌석 byz-harness-nano-v430-verdict-ledger#0

- 2026-10-08 — 증거: 세트: b382723e315be685535d4b9048c45f0fd019582c · 시험: bash tests/harness/test_verdict_ledger.sh rc=0 · 이슈: 0
- 2026-10-08 14:58 — 진행→완성 · 좌석 byz-harness-nano-v430-verdict-ledger#0 · DA design/harness/OPS-VERDICTS-20261006.md#§58
