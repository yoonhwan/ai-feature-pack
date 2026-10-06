# 인덱스: C1a 설치 키트 정본 채택(#816 ⓪) + install.sh + MACHINES·RELEASE 템플릿
<!-- ledger: design/harness/GOAL-harness.md -->

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「RELEASE-<ver>.md 1장 + 머신별」.
골의 축: 표 C(업그레이드·배포·머신별 반영) · 원문 5(머신 독립 배분). 핵심 한 줄: 세트끼리 병렬이 되려면 머신마다 같은 키트를 1회로 설치할 수 있어야 한다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
GitHub Issue #816(`gh issue view 816`)의 ⓪→⑤ 중 ⓪(라이브 하네스 bin 을 main 추적본으로 «채택» · 구조 커밋 · 행위 0)와 ①(설치 스크립트)이 이 카드의 몫이다. 라이브 사본(FT_BIN = v6-realtime-live 워크트리 `.fable-team/bin` · gitignored)이 추적본보다 최신인 10개를 덮지 않고 채택한다. 정본: `design/harness/issue-improvement/MERGED-20261005.md` §4 행 C1 · `design/harness/issue-improvement/DESIGN-harness-composition-20261005.md` §3-4. ⑤ FT_BIN 이전·③ [BLOCK]·④ 규칙은 이 카드 범위 밖.

## 구현 범위 (이 셋만 — 닫힌 목록)
1. `scripts/harness-install/fable-team/{bin,templates}` 에 라이브 사본(`~/.claude/skills/fable-team/scripts` + v6-realtime-live `.fable-team/bin`)을 «채택» — 라이브가 최신인 파일은 라이브 내용으로, `mbox.py` 는 의도적 비추적(심링크 dangling 금지)이라 제외, v65 리터럴은 이 카드에서 바꾸지 않는다(구조 커밋·행위 0). 채택 파일 목록 + 라이브 대비 diff 0 증거를 `design/harness/KIT-ADOPT-20261006.md` 1장에.
2. `scripts/harness-install/fable-team/install.sh` — `HOME` 을 인자/env 로 받아 빈 홈에 키트를 복사하고 팀 1개 부팅 보고(설치 파일 목록·sha·machine 이름)를 출력. `--dry-run` 기본 · 원격(jarvis·다른 머신) 접속은 이 카드에서 하지 않는다(= 사람 승인). `design/harness/MACHINES.md`(머신 배분표 · 행: 이 Mac · jarvis · byzs-mac-mini[tailscale] · 값 모르면 «미확인») + `design/harness/RELEASE-TEMPLATE.md`(변경·설치 명령·머신별 「반영됨 <machine> <sha>」 행).
3. 회귀: `bash -n` 전 파일 · `HOME=$(mktemp -d) bash scripts/harness-install/fable-team/install.sh` 1회 통과 · 기존 `slack-mirror` 설치물 무변경. 기존 설치물 예: `scripts/fable-team-bin/ft-nano-close.sh`. 커밋은 자기 브랜치, **push 금지**(master). 금지: 라이브 FT_BIN 변경 · launchd · 글로벌 설정 · 다른 머신 접속.

## 완료 조건 (닫힘 판정 기준 — master+DA 테스트 소관)
- 빈 HOME(mktemp)에 install.sh 1회로 팀 1개 부팅 보고 출력 + MACHINES.md 행 + RELEASE-TEMPLATE.md 「반영됨 <machine> <sha>」 행 형식 존재.
- KIT-ADOPT-20261006.md 의 채택 파일 표에서 라이브 대비 diff 0 — 명령 출력 그대로 첨부.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>` — ops 가 수락 판정문을 남긴다.

## 상태
- base_sha: 866f3c1f9b5c7fc0d472c5f27140a74d40359108 (spawn 2026-10-05)
- 2026-10-06 — 대기/ 생성 (ft-harness-ops#4).
- 2026-10-05 23:55 — 대기→진행 · 좌석 ft-harness-temp-c1a-kit-adopt-install#0
- 정본 영향 없음: 하네스 키트 채택 파일과 템플릿만 추가 — docs/architect 제품 정본 변경 없음
- 2026-10-05 23:59 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§1
- 세트: 89171f202d93d5822a1df2f51a8756fdf2faf44b · 시험: bash -n 전 .sh + 빈 HOME install.sh --apply rc=0 · 이슈: 0
- 2026-10-06 00:02 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§1
