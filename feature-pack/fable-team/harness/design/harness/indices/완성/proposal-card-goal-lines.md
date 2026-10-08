# 인덱스: ft-proposal-card.sh — 팀 골 줄 수 따라가기 · 닫는 증거를 골 줄에서 · 경로 기준 = 호출 워크트리 (R22 10-08 행)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 요청 원장 R22(10-08 행 · byz-cfo-master-claude#57 #61555 · master#13 #61560)
- 상태: 대기
- 선행: 없음(main fd25e1a76b 에 도구 랜딩됨)
- 시험 입력: 임시 git 리포 · 가짜 팀 env · goal-lines 2·3·4줄 · 머리 인용 줄이 있는 가짜 원장 — 원격 0
- 기준값: CFO 카드 손 보정본 = docs/cfo-main ca66614a53 design/cfo/indices/대기/proposal-toss-payments-review.md(골 4줄 · 골좌표 손으로 고침)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: 6-b(위성·메인 오케 개선요청 접수 → 개선). 핵심 한 줄: 제안서 카드 도구가 팀 골 원문을 팀 정본대로(줄 수 그대로) 싣고, 어느 브랜치에서 돌려도 lint 를 통과해야 한다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
`scripts/harness-install/proposal/ft-proposal-card.sh` 는 팀 master 가 제안서 나노 카드를 만드는 도구다(main fd25e1a76b). CFO 가 처음 써 보니 세 군데가 틀렸다: ①골좌표의 닫는 증거를 «원장에서 20자 이상인 첫 줄»로 고르는데(49-56행) CFO 원장 3행 인용 머리줄 「> 확정 2026-09-15 · 발행 FB_CFO#8」이 걸렸다 ②골 원문을 `sed -n '1,3p'` 로 3줄만 싣는다(67-68행) — CFO 골은 4줄이고 GOAL-cfo.md 9행이 4줄 바이트 일치를 요구한다 ③구현 범위·조사 근거가 main 에만 있는 파일(docs/rules/proposal_template.md · design/harness/DESIGN-proposal-flow-20261008.md)만 인용해, 그 파일이 없는 docs/cfo-main 브랜치에서 lint ⑥·⑧ 이 REJECT 했다. 설계 판정(arch#11): 4줄 골 허용은 설계와 어긋나지 않는다 — 설계의 「골 3줄」은 «팀 골 원문 복붙»의 서술일 뿐이다. 안 전문: design/harness/PLAN-r22-proposal-card-goal-lines-20261008.md.

## 사전검증
- 소환: 아니오
- 면제: 도구 1개의 카드 생성 문안 교정 + 시험 추가(제품 코드·키트 bin·lint 변경 0 · 원격 0) — arch 서명 byz-harness-arch-claude#11

## 조사 근거
- `scripts/harness-install/proposal/ft-proposal-card.sh:49` — 닫는 증거 = 원장 20자+ 첫 줄(머리 인용 줄이 걸림)
- `scripts/harness-install/proposal/ft-proposal-card.sh:68` — 골 원문 `sed -n '1,3p'` 3줄 고정
- `scripts/harness-install/proposal/ft-proposal-card.sh:89` — 구현 범위가 main 전용 파일만 인용
- `scripts/harness-install/fable-team/bin/ft-index-lint.sh:32` — path_exists = 호출 워크트리 기준(⑥·⑧)
- `tests/harness/test_proposal_card.sh:16` — 픽스처 goal-lines 3줄 · 원장에 골 줄 없음

## 구현 범위 (이 목록만 — 닫힌 목록)
1. `scripts/harness-install/proposal/ft-proposal-card.sh` — ①골 원문 = goal-lines 파일 전체 줄(제목 「(항상 이 N줄)」 · N<3 이면 REJECT) ②닫는 증거 = goal-lines 줄을 위에서부터 「 」 로 나눈 조각 중 공백 정규화 20자+ 첫 조각의 앞 50자 · lint `norm` 과 같은 정규화의 원장에 들어 있지 않으면 REJECT · 원장 첫 줄 고르기 삭제 ③구현 범위에 `$LEDGER_REL` «읽기: 팀 골 원장» 줄 추가 · 조사 근거 기본 인용 = `$LEDGER_REL:<골 1줄이 있는 줄 번호>` · 설계·템플릿 파일은 워크트리에 있으면 경로, 없으면 「`git show origin/main:<경로>` 로 읽기」 문장(경로:줄 형식 아님).
2. `tests/harness/test_proposal_card.sh` — PLAN §시험 6항목 추가 · 픽스처 원장에 골 줄을 넣는다 · 기존 항목은 그대로 통과.
3. 그 외 파일 변경 0(goal-lines-cfo.txt 4번째 줄 설치는 master 몫).

커밋은 자기 브랜치, **push 금지**. **금지**: 키트 bin(`scripts/harness-install/fable-team/bin`)·ft-index-lint 수정 · `.fable-team/` 라이브 파일 수정 · 실제 팀 카드 생성.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_proposal_card.sh` rc=0(출력 PASS 줄 복붙) · `shellcheck -S warning` 0 · 파일 200줄 이하.
- 실제 팀 env 5개로 dry 확인: 임시 리포에 각 팀 원장(origin/main 판) + 그 팀 goal-lines 를 두고 카드 생성 → lint OK 5개(cfo 는 4줄 goal-lines 사본으로) — 출력 복붙.
- 카드 증거 줄 형식(필수 · 이유 칸에 가운뎃점 금지): `세트: <40hex> · 시험: bash tests/harness/test_proposal_card.sh rc=0 · 이슈: 0`.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: ece07d7eef56869c26a833453c024d0f55398dd0 (spawn 2026-10-08)
- base_sha: (spawn 때 기입 · ops/main-base)
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#11 · 원장 R22 10-08 행). spawn 은 master 판단.
- 정본 영향 없음: 하네스 제안서 카드 도구와 그 시험만이고 docs/architect 제품 정본 변경 없음.
- 2026-10-08 11:24 — 대기→진행 · 좌석 byz-harness-nano-proposal-card-goal-lines#0
- 2026-10-08 — 나노 산출 #61602 · arch#11 독립 재현(시험 28 ALL PASS · shellcheck 0 · 실 CFO 원장(docs/cfo-main 판)·ops 원장으로 임시 리포 dry: CFO 4줄 카드 · 닫는 증거 = 골 2줄 · 템플릿 없는 브랜치에서 lint OK) → 판정서 §52 초안.
세트: 091fc811d20ea429de3cee9b650752b1250b7289 · 시험: bash tests/harness/test_proposal_card.sh rc=0 · 이슈: 0
- 2026-10-08 11:32 — 진행→완성 · 좌석 byz-harness-nano-proposal-card-goal-lines#0 · DA design/harness/OPS-VERDICTS-20261006.md#§52
