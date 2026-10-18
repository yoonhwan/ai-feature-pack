# 인덱스: test_regress_pack 의 「예시 2행」 고정 기대를 «형식 검사»로 — 실데이터가 늘면 깨지는 시험 (야간 단위 3)
<!-- ledger: design/teams/harness/GOAL-harness.md -->
- Issue: 없음 → 야간 자율 안 design/teams/harness/PLAN-night-autonomy-20261008.md 단위 3
- 상태: 대기
- 선행: 없음
- 시험 입력: 저장소 tests/regression/issue_pack.jsonl(읽기만) + 기존 시험의 mktemp 리포
- 기준값: `bash tests/harness/test_regress_pack.sh` = FAIL 1건 「issue_pack.jsonl 예시 2행」(bash5·3.2 둘 다 · arch#8 실측) — 팩 실제 행 수 3

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: 6-b(하네스 감시 — 늘 빨간 시험은 진짜 회귀를 가린다). 핵심 한 줄: 야간 자율 단위 3 조사 결론 = «시험 기대가 낡음»(파일 결함 아님).

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
`tests/harness/test_regress_pack.sh` 마지막 검사(78행)는 저장소의 회귀 팩 `tests/regression/issue_pack.jsonl` 이 «정확히 2행»인지 본다. 이 시험은 10-06(3928822c16)에 «예시 2행(실제 1 + 합성 1)» 시절 쓰였고, 10-07 커밋 7b04fc2c4f 가 실제 회귀 행(#834)을 1개 추가해 지금 3행이다. 팩은 운영 데이터라 계속 늘어나는 것이 정상이다 — 고정 개수 검사는 행이 하나 등록될 때마다 깨진다. 3행 모두 같은 9개 키(added_at·closed_sha·expected·files·issue·mode·repro_cmd·retired_at·team)를 가져 파일 자체는 정상이다. 검사 의도(주석 76행: «jq 로 읽히는지»)대로 형식만 본다.

## 사전검증
- 소환: 아니오
- 면제: 시험 1줄의 기대만 바꾸고 제품·하네스 코드 변경 0이다. 되돌림 1커밋 revert. 최종 DA 는 완성 이동 때 1회. — arch 서명 byz-harness-arch-claude#8

## 조사 근거
- `tests/harness/test_regress_pack.sh:78` `[ "$(jq -s 'length' "$PK")" = "2" ]` — 고정 개수.
- `tests/harness/test_regress_pack.sh:76` 주석 「저장소의 예시 팩 형식 … 이 jq 로 읽히는지」 — 의도는 형식.
- `tests/regression/issue_pack.jsonl` — 3행(issue 799 · 900000 합성 · 834) · 키 9개 동일.
- 커밋 7b04fc2c4f(10-07) 「회귀 팩 #834 등록 1행」 — 행 증가 원인.

## 구현 범위 (이 하나만 — 닫힌 목록)
1. `tests/harness/test_regress_pack.sh` 78행을 다음 셋으로 바꾼다(라벨 문구도 바꿈): ①`jq -s 'length'` ≥ 1 ②모든 행이 위 9개 키를 가짐(`jq -s 'all(.[]; has("issue") and has("closed_sha") and has("repro_cmd") and has("expected") and has("files") and has("mode") and has("team") and has("added_at") and has("retired_at"))'` = true) ③합성 예시 행(issue 900000) 1개 존재. PASS 라벨 = `issue_pack.jsonl 형식(행 ≥1 · 키 9 · 합성 예시 1)`.

커밋은 자기 브랜치, **push 금지**. **금지**: issue_pack.jsonl 수정 · ft-regress-pack.sh 수정 · 다른 검사 변경.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_regress_pack.sh` rc=0 · `/bin/bash tests/harness/test_regress_pack.sh` rc=0.
- 음성 대조 1회(RESULT 에만): mktemp 복사 팩에서 한 행의 `repro_cmd` 키를 지워 PK 를 그 파일로 돌리면 FAIL — 시험 코드에 넣지 않아도 됨(PK 경로를 env `FT_REGRESS_PACK_FILE` 로 받게 하면 넣어도 됨 · 넣으면 그 env 1개만).
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_regress_pack.sh rc=0 · 이슈: 0`.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 293199de7566a8c583f629e85c3ad312020631a0 (spawn 2026-10-08)
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#8 · 야간 자율 단위 3 조사 결론). spawn 은 master 판단.
- 정본 영향 없음: 하네스 시험 1줄만 — docs/architect 제품 정본 변경 없음.
- 2026-10-08 01:46 — 대기→진행 · 좌석 byz-harness-nano-regress-pack-test-row-count#0
- 2026-10-08 — 증거(나노 regress-pack-test-row-count · 골 축 6-b · 야간 단위 3 · master#11 독립 검증 #60854 · arch#8 재현):
  - 변경: tests/harness/test_regress_pack.sh 1파일 — 78행 고정 「2행」 검사 → 형식 검사(행 ≥1 · 키 9 · 합성 예시 900000 1개) + 팩 경로 env FT_REGRESS_PACK_FILE 1개. 팩·ft-regress-pack.sh 변경 0.
- 세트: 4143c964f1bfad38991ce897c1967f64b640b656 · 시험: bash tests/harness/test_regress_pack.sh rc=0 · 이슈: 0
- 추가 시험: /bin/bash 3.2 로도 fail=0(master·arch) · 음성 대조(arch): 첫 행 repro_cmd 키를 지운 복사 팩을 FT_REGRESS_PACK_FILE 로 주면 `FAIL issue_pack.jsonl 형식(행 ≥1 · 키 9 · 합성 예시 1)` fail=1.
- 정본 영향: 하네스 시험 1파일만 — docs/architect 제품 정본 변경 없음 · 라이브 반영 불요(시험 파일).
- 2026-10-08 01:48 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§41
