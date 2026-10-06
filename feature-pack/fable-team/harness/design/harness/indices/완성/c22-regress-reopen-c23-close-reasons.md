# 인덱스: C22 회귀 재오픈 절차 + C23 close 사유 3종 검사
<!-- ledger: design/harness/GOAL-harness.md -->

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: 원문 7 · 표 A. 핵심 한 줄: 회귀는 새 Issue 가 아니라 원 Issue 재오픈 + 깬 랜딩 역링크로, 교체·불필요 닫기는 확인 없이 닫히지 않게 한다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
회귀가 확인되면(회귀 팩 FAIL · 기준값 악화 · 라이브 경보) 원 Issue 를 재오픈하고 코멘트 「regression: 깬 sha · 발견 경로 · LEDGER 행」을 남기며 LANDING-LEDGER 행에서 깬 sha 를 역링크한다. 라이브가 깨졌으면 큐 `즉시` 행 요청 1통. revert 는 소유 오케가 손으로 하고(스크립트는 안내만 — force push 0) 그 revert 후보도 랜딩 ④~⑥ 전부를 거친다. close 사유는 완성(5항)·교체됨→#N(대체 번호 필수)·불필요(근거 필수) 3종이고 후 둘은 소유 오케 확인 seq 가 코멘트에 없으면 매니저가 반려한다. 정본: `design/harness/issue-improvement/SPEC-github-issue-driven-20261006.md` §12-3·§12-4 · §8 C22·C23 · `design/harness/LANDING-LEDGER.md`.

## 구현 범위 (이 셋만 — 닫힌 목록)
1. `scripts/fable-team-bin/ft-regress-reopen.sh <issue> <깬 sha>` — 기본 dry-run(명령만 출력) · `--apply` 때만 gh reopen/edit/comment · LANDING-LEDGER 에서 깬 sha 행을 찾아 역링크 문구 생성 · `--live` 면 큐 `즉시` 행 요청 문구도 출력 · revert 명령은 «안내만»(실행 0).
2. `scripts/fable-team-bin/ft-close-reason-check.sh <issue>` — 읽기 전용: 사유 3종 분류 · 교체됨/불필요인데 「확인 seq」 코멘트가 없으면 exit 1 · 완성이면 기존 `ft-issue-close-check.sh` 결과를 인용.
3. 회귀: `bash -n` · fixture(`tests/fixtures/issue_close/` 확장 3개: 교체+seq 있음/없음 · 불필요+근거 없음)로 check 시험 · reopen dry-run 출력 첨부. 기존 도구 예: `scripts/fable-team-bin/ft-nano-close.sh`. 커밋은 자기 브랜치, **push 금지**. 금지: `--apply` 실행 · gh 쓰기 · force push · revert 실행.

## 완료 조건 (닫힘 판정 기준 — master+DA 테스트 소관)
- close-reason-check 가 fixture 3개에서 exit 0/1 을 바르게 낸다(출력 첨부).
- reopen dry-run 출력에 gh reopen·edit·comment 명령과 역링크 문구가 있고 아무것도 실행되지 않는다.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>` — ops 가 수락 판정문을 남긴다.

## 상태
- base_sha: eafbbaa4563e2fb6c59bbfd8e0ed28cea02f4625 (spawn 2026-10-06)
- 2026-10-06 — 대기/ 생성 (ft-harness-ops#4).
- 2026-10-06 00:10 — 대기→진행 · 좌석 ft-harness-temp-c22-regress-reopen-c23-close-reasons#0
- 정본 영향 없음: 하네스 스크립트·시험만 추가 — docs/architect 제품 정본 변경 없음
- 세트: 3f8fdc8b5aeb9fc0ecf8d6a2b22fb6f23fbebfef · 시험: bash -n 2종 + fixture 3개 exit 0/1/1 rc=0 · 이슈: 0
- 2026-10-06 00:16 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§12
