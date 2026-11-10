# R20 안 — CFO 나노 카드 lint 가 v65 골 3줄로 검사되는 문제 (byz-harness-arch-claude#11 · 2026-10-08)

골 원문:
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
골의 축: 6-b(위성·메인 오케 개선요청 접수 → 개선) · 요청 원장 REQUEST-LEDGER R20(byz-cfo-master-claude#56 #61317).

## 원인 (실측)
- `ft-index-lint.sh:14-20` — `FT_GOAL_LINES_FILE` 이 비어 있으면 v65 골 3줄을 기본값으로 쓴다.
- `.fable-team/bin-cfo/cfo-env.sh` 에는 `FT_GOAL_LEDGER` 만 있고 `FT_GOAL_LINES_FILE` 이 없다(harness·feature·kk·planner env 는 있음).
- 재현: `source cfo-env.sh` 뒤 `ft-index-lint.sh design/cfo/indices/진행/757-knowledge-p95.md` → 「골 1줄 불일치 · 골 2줄 불일치 · 골 3줄 불일치」. 같은 카드에 `FT_GOAL_LINES_FILE=<GOAL-cfo.md 13~15행>` 지정 → 「OK … (ledger=design/cfo/GOAL-cfo.md)」.

## 안 (harness·feature env 와 같은 패턴 · 코드 변경 0)
1. `goal-lines-cfo.txt` = `design/cfo/GOAL-cfo.md`(c-level-planning 워크트리) 13~15행 그대로 3줄 → `.fable-team/bin-cfo/goal-lines-cfo.txt` 로 설치.
2. `cfo-env.sh` 끝에 `export FT_GOAL_LINES_FILE=…/bin-cfo/goal-lines-cfo.txt` 1줄 추가(설치 초안 = 이 폴더 `cfo-env.sh` · 현행과 diff 는 `13a14` 추가 1줄뿐).

## 설치 절차 (master)
1. 현행 대조: `shasum -a 256 .fable-team/bin-cfo/cfo-env.sh` 앞 16자 = `003d63d296cb5045`. 다르면(승계로 FT_SEND_FROM 갱신 등) 초안을 쓰지 말고 현행에 위 1줄만 추가한다.
2. 백업 `cfo-env.sh.bak-1008-r20` → cp 2개(goal-lines-cfo.txt · cfo-env.sh) → cmp.
3. 확인: `source cfo-env.sh; bash "$FT_BIN/ft-index-lint.sh" design/cfo/indices/진행/757-knowledge-p95.md`(c-level-planning 에서) → OK 줄.
4. CFO master 에 「다음 나노 개설부터 따로 export 안 해도 됨」 통지 · 원장 R20 반영 sha.

## 한계 (그대로 둠)
- CFO 골은 4줄(13~16행)인데 lint 는 3줄만 본다 — 4번째 줄 「작업은 파일로 남아서 …」 는 검사 밖. 줄 수를 늘리려면 키트 lint 코드 변경(전 팀 영향)이라 이 요청 범위 밖. 필요하면 별도 요청.
- issues 팀 env(`bin-issues/issues-env.sh`)에도 `FT_GOAL_LINES_FILE` 이 없다 — issues 팀이 카드 lint 로 나노를 여는 경우가 있는지 확인 전이라 이 안에 넣지 않았다.
