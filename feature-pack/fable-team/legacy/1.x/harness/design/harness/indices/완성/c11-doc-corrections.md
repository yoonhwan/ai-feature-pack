# 인덱스: C11 문서 정정 — MERGED 충돌 표 «반영할 조각·칸» 전부 + P11 정정 후보(C11++)
<!-- ledger: design/teams/harness/GOAL-harness.md -->

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: 표 A·원문 7. 핵심 한 줄: 확정된 값이 조각 문서마다 어긋난 채 남으면 구현 카드가 옛 문장을 읽는다 — 정본을 한 번에 맞춘다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
합치기 문서의 충돌 표(§1 · 16행)는 행마다 «반영할 조각·칸»을 적어 두었고 오빠 값이 전부 확정됐다. 지금 각 조각 문서(P1~P9·P10)에는 옛 문장이 남아 있다. 이 카드는 문서만 고친다(코드 0). 정본: `design/teams/harness/issue-improvement/MERGED-20261005.md` §1 · `design/teams/harness/issue-improvement/SPEC-github-issue-driven-20261006.md` §6·§8(C11++ 줄: P5 Q-6 · P8 단계 1 입력자 4행 · P1 §3-3 ①② 1구씩 · P10 §4-B 1구 · P8 §3 브랜치 행) · `design/teams/harness/issue-improvement/PIECES.md`. 오빠 값 원장은 `design/teams/harness/issue-improvement/VALUES-pieces-P3-P5-20261005.md`(.md 인용 4개 한도라 경로만 적음 — 읽기 전용).

## 구현 범위 (이 셋만 — 닫힌 목록)
1. MERGED §1 충돌 표 16행을 위에서 아래로 — 각 행의 «반영할 조각·칸»에 적힌 문서의 그 칸을 확정 문장으로 교체하고, 그 조각 문서 머리에 「MERGED 반영 r+1」 1줄을 추가한다. 의미를 바꾸지 말고 확정값(VALUES 원장)만 옮긴다 · 확정값이 불분명한 행은 고치지 말고 보고서의 「미반영」 표에 사유와 함께 적는다. 대상 폴더 `design/teams/harness/issue-improvement/`.
2. SPEC-github-issue-driven §8 의 C11++ 줄이 가리키는 5곳(P5 Q-6 · P8 단계 1 입력자 · P1 §3-3 ①② · P10 §4-B · P8 §3 브랜치 행)을 같은 방식으로 정정 · PIECES.md 상태 칸 «합침»으로 갱신 · 「완성 후」 행은 CFO 원장(`design/v65/PENDING-cfo-async-sync-io-canon.md` 있으면)에 행 추가.
3. 회귀: `git diff --stat` 로 변경이 `design/` 아래 .md 만임을 첨부 · 표 열 수 불변(`awk -F'|'` 전후 비교) · 보고서 `design/teams/harness/issue-improvement/C11-REPORT-20261006.md` 1장(반영 표 + 미반영 표). 커밋은 자기 브랜치, **push 금지**. 금지: 코드·스크립트·`.claude/skills/**` 수정(byz-e2e 스킬 문구는 오빠 값이 «현행 유지»라 건드리지 않는다).

## 완료 조건 (닫힘 판정 기준 — master+DA 테스트 소관)
- 충돌 표 16행 전부가 반영 표 또는 미반영 표에 한 줄씩 있다(누락 0).
- diff 가 design/ 아래 .md 뿐이고 표 열 수가 변하지 않았다(출력 첨부).
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>` — ops 가 수락 판정문을 남긴다.

## 상태
- base_sha: a2be1d4633a3c1ec31ef9680ec43cf6a6537be54 (spawn 2026-10-05)
- 2026-10-06 — 대기/ 생성 (ft-harness-ops#4).
- 2026-10-05 23:57 — 대기→진행 · 좌석 ft-harness-temp-c11-doc-corrections#0
- 정본 영향 없음: 하네스 설계 문서 정정만 — docs/architect 제품 정본 변경 없음
- 세트: c592d9abbc0c2558c4ef4fe7e9582a1b2a4931e7 · 시험: 없음(문서) — 코드 변경 0 · diff 가 design 아래 .md 뿐 rc=0 · 이슈: 0
- 2026-10-06 00:06 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§5
