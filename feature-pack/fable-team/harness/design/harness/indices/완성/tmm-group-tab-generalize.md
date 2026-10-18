# 인덱스: tmm 그룹 탭 일반화 점검 + 개선 — 신 이름 규칙(byz-<팀>-<역할>-<에이전트>#N)에서 팀별 탭이 갈라지게
<!-- ledger: design/teams/harness/GOAL-harness.md -->

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「RELEASE-<ver>.md 1장 + 머신별 「반영됨 <machine> <sha>」 행 전부」.
골의 축: 원문 5(머신별 독립 배분) · 원문 7. 핵심 한 줄: 좌석 이름을 새 규칙으로 바꾸면 tmm 탭이 «byz» 한 곳으로 뭉쳐 팀을 못 찾는다 — 규칙 추가 없이 일반 규칙 하나로 팀별 탭이 나와야 한다. 오빠 원문(10-07): 「tmm 나노 워커 열어서 그룹핑 탭 일반화 점검 개선해줘」.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
tmm(tmux 세션 선택기, 설치본 `~/.tmm/versions/0.7.3/core/bin/tmm`)의 그룹 탭 라벨은 `cat_of()`(약 182행)가 정한다: ①`~/.tmm/categories` 글롭 규칙 첫 매치 → ②없으면 «역할 접두»(`TMM_CAT_STRIP` 기본 `FB_ ft-`)를 떼고 첫 토큰(`-`/`_` 앞 8자·소문자). 새 이름 규칙(`<프로젝트>-<팀>-<역할>-<에이전트>#N` · `design/teams/harness/issue-improvement/SPEC-session-naming-20261005.md` §2-A·§2-C tmm 행 · 정본 `~/.claude/skills/fable-team/references/main-team-governance.md` §1)에서는 첫 토큰이 프로젝트(`byz`)라 `byz-v65-master-claude#143`·`byz-cfo-master-claude#53`·`byz-planner-master-claude#4` 가 전부 `byz` 한 탭으로 뭉친다. 구 이름(`ft-v65-…`·`FB_CFO#52`·`KakaoBot#14`)과 신 이름이 한동안 같이 살아 있으므로 둘 다 올바른 탭이어야 한다.

## 구현 범위 (이 셋만 — 닫힌 목록)
1. **점검표**: 현재 `tmux ls` 세션 전부(읽기 전용)에 대해 «현행 0.7.3 라벨 → 개선 후 라벨»을 표로 만든다(`source tmm __lib; cat_of <이름>` 사용 · 격리 `TMM_CATEGORIES`). 뭉침·갈라짐·충돌(서로 다른 프로젝트가 같은 팀 글자)을 «사실»로 적는다. `design/teams/harness/RESULT-tmm-group-tab-<날짜>.md` 에 둔다.
2. **개선(일반 규칙 1개)**: 이름이 P6 형태(앞에서 3번째 토큰이 역할 예약어 master arch da tester checker analyst pm nano repro tool)면 라벨 = «둘째 토큰(팀)». 아니면 기존 폴백 그대로. 구 `ft-v65-master-claude` 도 같은 규칙으로 `v65` 가 되고, `ft-harness-ops`·`FB_CFO#52`·`KakaoBot` 은 기존 경로 그대로여야 한다(회귀 0). `categories` 글롭 규칙은 계속 최우선. 프로젝트별 규칙 추가 요구는 0. 서로 다른 프로젝트가 같은 팀 글자를 쓰는 충돌(SPEC Q6)은 «실제 충돌이 있을 때만» 프로젝트 첫 글자 접두 — 충돌 없으면 팀 글자만. 구현은 `cat_of()` 한 함수 안에서(그룹 키 8자·열 5자 규칙 불변). 역할 예약어·문법 판정은 기존 `scripts/fable-team-bin/ft-name-lint.sh` 의 ROLES 목록과 같은 값을 쓴다(수정 금지·읽기만).
3. **산출·시험**: 수정본을 설치본 직접 수정이 아니라 **추적 사본** `scripts/harness-install/tmm/tmm`(0.7.3 복사 + 패치 · VERSION 0.7.4-candidate)으로 둔다. 시험 `tests/harness/test_tmm_group.sh`(신 이름 6 · 구 이름 6 · 충돌 1 · 규칙파일 우선 1 · 회귀 `bash -n`). 커밋은 자기 브랜치, **push 금지**. 
**금지**: `~/.tmm/` 아래 수정(설치·`current` 전환은 오빠 승인 영역) · tmux 세션 변경 · 기존 `seats-*.json` 수정 · tmm 외 다른 도구 수정.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- 점검표 첨부(현재 세션 전부 · 전/후 라벨) + 신 이름 팀별 탭 분리 시험 통과(`test_tmm_group.sh` 출력).
- 구 이름 회귀 0(시험 출력) · `~/.tmm` 변경 0(`find ~/.tmm -newer <카드> ` 0건) · 기존 `test_*` 영향 0.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: b2e67156f5928e7a725d5b804a4b4140d8cb3a70 (spawn 2026-10-07)
- 2026-10-07 — 대기/ 생성 (ft-harness-ops#6 · 오빠 지시).
- 정본 영향 없음: 하네스 도구 추적 사본·시험·보고서만 추가 — docs/architect 제품 정본 변경 없음
- 2026-10-07 10:57 — 대기→진행 · 좌석 ft-harness-temp-tmm-group-tab-generalize#0
- 2026-10-07 11:01 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§20
- 세트: da5685b995d5c017f0973c98fd4bf8bf12be493d · 시험: bash tests/harness/test_tmm_group.sh rc=0 · 이슈: 0
