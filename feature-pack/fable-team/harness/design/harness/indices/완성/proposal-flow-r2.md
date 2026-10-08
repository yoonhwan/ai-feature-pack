# 인덱스: 제안서 흐름 r2 — Issue 본문 = 제안서 전문 · 제안서 md + eli5 HTML 세트 · 실험·예측 시뮬 절 (판정 357)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 판정 357(planner#8 → master#12·#13 #61756 · 설계 design/harness/DESIGN-proposal-flow-20261008.md «# r2»)
- 상태: 대기
- 선행: DA §r2 교정 1 APPROVE(아래)
- 시험 입력: 임시 git 리포 · 가짜 Tank · 가짜 gh 읽기(`FT_GH_READ`) · 가짜 Slack(`_proposal_fakes`·`_magazine_fakes`) · 가짜 LLM — 원격·실 LLM 0
- 기준값: r1 도구(main fd25e1a76b + R26 b2c1d09bc2) · 첫 사례 #887 은 r1 그대로

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: 6-b(요청 접수 → 사용자 협의 → 개선). 오빠 원문(10-08 11:5x): 「제안서는 풀 컨텍스트로 깃헙 이슈에 등록 · 제안서도 eli5 세트 · 실험과 예측 시뮬 포함 · 다음 제안서부터」.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
제안서 흐름 r1(판정 352 · 정본 docs/rules/proposal_flow.md)은 승인된 제안서를 Issue 로 등록할 때 본문에 경로·판정·검증 칸만 싣고, 슬랙에는 md 1개만 첨부하며, 템플릿에 실험 절이 없다. 판정 357 은 셋을 바꾼다: ①Issue 본문 = 제안서 전문(고정 식별자 · 60k 초과 분할 · 중복 0) ②제안서 슬랙 세트 = md + eli5 HTML(매거진 eli5 묶음 모듈 재사용) ③템플릿 「## 실험·예측 시뮬」 절. 계약 전문은 설계 «# r2» §r2-1~§r2-4 이고, DA §r2 교정 1 의 구현 조건(아래 완료 조건에 옮김)을 지킨다. 매거진 파일 변경은 magazine_attach.CONTENT_TYPES 의 md 1키뿐.

## 사전검증
- 소환: 예
- DA: design/harness/DA-proposal-flow-20261008.md

## 조사 근거
- `scripts/harness-install/proposal/ft-proposal-register.sh:38` — 본문 생성부(경로·판정·검증만)
- `scripts/harness-install/slack-mirror/byz_proposal_publish.py:119` — publish 상태 머신(posting→posted→md 첨부→done)
- `scripts/harness-install/slack-mirror/magazine_attach.py:29` — attach(제목 표식 채택 · sharing 불명 차단 · on_file_id 선기록)
- `scripts/harness-install/slack-mirror/magazine_eli5_batches.py:96` — explain(묶음·검증·보이는 생략)
- `docs/rules/proposal_template.md:29` — 검증 칸 뒤 = 실험 절 자리

## 구현 범위 (이 목록만 — 닫힌 목록)
1. `scripts/harness-install/proposal/ft-proposal-register.sh` — 설계 §r2-1: 본문 = 숨은 표식 ID 첫 줄 + 보이는 ID + 머리말 + 경로@sha + 판정 + 증거 폴더 + 전문 · 시도 기록 `~/.hermes/state/proposal_register.json`(경로는 env 로 바꿀 수 있게) · create 전 후보 본문 표식 대조(`FT_GH_READ`) · 60,000자 분할 comment. 200줄을 넘기면 판정·조회 부분을 같은 폴더 helper 로 먼저 분리([structure] 커밋).
2. `scripts/harness-install/slack-mirror/byz_proposal_publish.py` — 설계 §r2-2 publish 1~4. 200줄을 넘으면 상태 helper 를 `proposal_state.py` 로 먼저 분리([structure] 커밋 · 동작 변경 0).
3. 신규 `scripts/harness-install/slack-mirror/proposal_eli5.py`(≤120줄) · `proposal_eli5_template.html`(매거진 eli5 템플릿 사본에서 제목·결정 박스만 바꿈).
4. `scripts/harness-install/slack-mirror/magazine_attach.py` — `CONTENT_TYPES` 에 `"md": "text/markdown"` 1키만.
5. `scripts/harness-install/slack-mirror/install-magazine.sh` — COMPANION 에 `proposal_eli5.py`·`proposal_eli5_template.html`(그리고 helper 를 만들었으면 그것도).
6. `scripts/harness-install/proposal/ft-proposal-card.sh` — 완료 조건 1줄(실험 절 세 형식 · 산출물 `design/<팀>/evidence/proposal-<slug>/`) + 나노 범위 «evidence 폴더 쓰기 허용» 1줄.
7. `docs/rules/proposal_template.md`(실험 절 · 검증 뒤 · 근거 앞) · `docs/rules/proposal_flow.md`(§r2 요약 10줄 이내).
8. 시험: `tests/harness/test_proposal_register.sh` · `tests/scripts/test_proposal_publish.py`(+필요시 `test_proposal_publish_faults.py`) · 신규 `tests/scripts/test_proposal_eli5.py` · `tests/harness/test_proposal_card.sh` — 설계 §r2-4 전부.

커밋은 자기 브랜치, **push 금지**. **금지**: 실제 GitHub·Slack·LLM 호출 · 키트 bin·`.fable-team/` 수정 · 매거진 모듈의 다른 줄 변경 · 홈·`~/.hermes` 설치.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- 시험 rc=0: `bash tests/harness/test_proposal_register.sh` · `bash tests/harness/test_proposal_card.sh` · `python3 -m pytest tests/scripts/test_proposal_publish.py tests/scripts/test_proposal_publish_faults.py tests/scripts/test_proposal_eli5.py -q` · 매거진 회귀 `python3 -m pytest tests/scripts -q -k magazine`(.venv python) — PASS 줄 복붙.
- ★DA §r2 교정 1 구현 조건(각각 시험 1개 이상으로 고정)★: ①create «확정 거절»은 원격 생성이 없었다는 근거가 있을 때만 — 단순 rc≠0·번호 없는 출력·일반 오류 문구는 «불명»(creating 유지) ②기록에 이미 Issue 번호가 있으면(created·comment-k) 검색에서 안 보여도 새 create 0 — 그 번호를 직접 확인하거나 보이는 오류 ③모든 phase 저장이 md_hash·files·omitted 를 보존 ④AttachError 를 완료·새 업로드로 흡수 0 ⑤캐시 hit·키 판단 «전»에 rN 원문 불변 확인 · md 와 HTML 은 같은 읽기 스냅샷(한 번 읽은 바이트)으로 생성·첨부 ⑥md 중간 상태를 두면 files.md 완료와 같은 의미 — 옛 「md 상태」 시험 문구로 files 계약을 대체하지 않는다.
- `git diff --stat <base>..HEAD -- scripts/harness-install/slack-mirror/magazine_*` = magazine_attach.py 1줄뿐(출력 복붙) · 모든 파일 200줄 이하 · ruff·shellcheck 0.
- 카드 증거 줄 형식(필수 · 이유 칸에 가운뎃점 금지): `세트: <40hex> · 시험: bash tests/harness/test_proposal_register.sh rc=0 · 이슈: 0`.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 801e66649e7117344896dbea92547c5db217f877 (spawn 2026-10-08)
- base_sha: (spawn 때 기입 · ops/main-base)
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#11 · 판정 357 · DA §r2 HOLD 1 → 교정 1 APPROVE). spawn 은 master 판단.
- 정본 영향 없음: 하네스 제안서 도구·eli5 판·템플릿·흐름 정본과 시험이고 docs/architect 제품 정본 변경 없음.
- 2026-10-08 12:24 — 대기→진행 · 좌석 byz-harness-nano-proposal-flow-r2#0
- 2026-10-08 — 나노 산출 1f834a7536 · arch#11 재현(시험 register·register_r2·card ALL PASS · pytest publish/faults/eli5 33 · 매거진 185 · ruff 0 · 매거진 변경 magazine_attach 1줄 · DA 구현 조건 6 소스 대조 충족) → 판정서 §53 초안.
세트: 1f834a7536aa46732b59718d7a025ac403329444 · 시험: bash tests/harness/test_proposal_register.sh rc=0 · 이슈: 0
- 2026-10-08 12:43 — 진행→완성 · 좌석 byz-harness-nano-proposal-flow-r2#0 · DA design/harness/OPS-VERDICTS-20261006.md#§53
