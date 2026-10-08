# 인덱스: 제안서 흐름 ① 정본·템플릿·governance ④행 초안 (판정 352 · 문서 3 · 코드 0)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 판정 352(planner#8 → master#12 발주 · 설계 design/harness/DESIGN-proposal-flow-20261008.md)
- 상태: 대기
- 선행: DA 사전검증 APPROVE(아래)
- 시험 입력: 없음(문서) — 완료 조건의 형식 검사만
- 기준값: 지금 제안서 흐름 정본 0 · 템플릿 0 · governance §2 진입로 3행(①밀어올리기 ②당겨오기 ③신규 기획)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: 6-b(요청 접수 → 사용자 협의 → 개선: 컨펌 게이트) + C(랜딩) + 원문 7(나노 2석 병행). 핵심 한 줄: 판정 352 오빠 원문 「내가 이런식으로 요청하면 나노워커 돌려 기획 및 제안서 작업하고 내가 제안서 읽고 컨펌」 · 「컨펌하면 이슈로 등록하는 과정을 하네스마스터 발주해 추가 랜딩」.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
오빠가 «자료+한 줄 지시를 던지면 나노가 기획·제안서를 쓰고, 오빠가 읽고 컨펌하면 그 뒤에 Issue 를 등록해 구현한다»는 흐름을 표준으로 정했다(판정 352). 설계(design/harness/DESIGN-proposal-flow-20261008.md)는 문서 덩이와 도구 덩이로 쪼갰고, 이 카드는 문서 덩이 3개다: ①정본 proposal_flow(설계 §1 표 5단계·역할·상태 머리줄 5종·금지선 + §3 도구 사용법(★제안서 Issue 는 `ft-proposal-register.sh` 진입점으로만 등록 · raw Tank create 전역 차단은 범위 밖 «선언»이라고 명시 — 설계 §10 r1★) + §6 첫 사례 적용 순서) ②템플릿 proposal_template(설계 §2 칸 순서 그대로) ③홈 파일 `~/.claude/skills/fable-team/references/main-team-governance.md` 의 tracked 초안(홈 현재 파일 그대로 복사 + §2 표에 ④행 1개 · 문안은 설계 §4). 상태 머리줄 문자열·템플릿 칸 이름·도구 명령 이름은 도구 나노(proposal-tools)와의 계약이라 설계 문자 그대로 쓴다. 정본·템플릿은 자동 로드되지 않는 docs/rules 폴더에 둔다(#3 RULE — 자동 로드 예산).

## 사전검증
- 소환: 예
- DA: design/harness/DA-proposal-flow-20261008.md

## 조사 근거
- 설계 §1(표 5단계·상태) · §2(위치·템플릿 칸) · §4(④행 문안) · §6(첫 사례).
- `docs/rules/bounded_da_review.md:1` — docs/rules 정본 형식 예(머리 · 표 · 짧은 절).
- `design/harness/DESIGN-proposal-flow-20261008.md:22` — §1 표 5단계(정본 본문의 원천).
- `design/harness/issue-improvement/GUIDE-human-report-20261005.md` — 제안서 본문 틀(결론→할 일→바뀐 것→근거 · 번호는 맨 끝 각주표).
- 홈 `~/.claude/skills/fable-team/references/main-team-governance.md` §2(13–24행) — ④행을 넣을 표. 리포에 사본 없음(git ls-files 0) → tracked 초안 경로 `design/harness/drafts/proposal-flow/fable-team/references/main-team-governance.md`.

## 구현 범위 (이 셋만 — 닫힌 목록)
1. `docs/rules/proposal_flow.md` 신규(200줄 이하).
2. `docs/rules/proposal_template.md` 신규(템플릿 칸 + 칸마다 한 줄 안내).
3. `design/harness/drafts/proposal-flow/fable-team/references/main-team-governance.md` 신규 = 홈 현재 파일 cp + ④행 1줄 + 그 아래 「정본 docs/rules/proposal_flow.md」 1줄. 다른 줄 변경 0(`diff <홈> <초안>` 이 + 2줄뿐이어야 함).
(같은 폴더 기존 파일 `docs/rules/standard_workflow.md` 는 읽기만 — 수정 0.)

커밋은 자기 브랜치, **push 금지**. **금지**: 홈 파일 직접 수정(설치는 master cp) · .claude/rules·CLAUDE.md 수정 · 코드 파일.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `diff ~/.claude/skills/fable-team/references/main-team-governance.md design/harness/drafts/proposal-flow/fable-team/references/main-team-governance.md` = 추가 2줄뿐(출력 복붙).
- 정본에 상태 머리줄 5종 문자열이 설계 §0 과 같다(`grep -c` 출력 복붙) · 템플릿 칸 `## ` 제목 목록이 설계 §2 순서와 같다(`grep '^## '` 출력 복붙).
- 카드 증거 줄 형식(필수 · 문서 전용): `세트: <40hex> · 시험: 없음(문서) — 정본·템플릿·초안 3파일 · 이슈: 0`.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: cf1bc2e5321ebc4c000a5530ae54f81da8929585 (spawn 2026-10-08)
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#9 · 판정 352 · 설계 DESIGN-proposal-flow-20261008.md). spawn 은 master 판단 · DA APPROVE 전 lint 실패가 정상.
- 정본 영향: docs/rules 에 하네스 절차 정본 1장 신규(제품 정본 docs/architect 변경 없음).
- 2026-10-08 09:15 — 대기→진행 · 좌석 byz-harness-nano-proposal-docs#0
- 2026-10-08 — 완료 독립 검증 (arch#10 · 판정서 §46 초안) — 나노 e56fed8f3f: 3파일 161줄 추가 · governance diff 추가 2줄 · 상태 5종·템플릿 칸 순서 설계 그대로.
- 정본 영향 없음: docs/rules/proposal_flow.md 는 하네스 절차 정본 신규 1장이고 docs/architect 제품 정본 변경 없음.
세트: e56fed8f3f491f70d77f2900f0f9115c1263fbed · 시험: 없음(문서) — 정본, 템플릿, governance 초안 3파일 · 이슈: 0
- 2026-10-08 09:19 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§46
