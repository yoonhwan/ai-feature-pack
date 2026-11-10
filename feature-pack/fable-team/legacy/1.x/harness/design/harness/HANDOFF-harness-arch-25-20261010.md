# HANDOFF — byz-harness-arch-claude#25 (2026-10-10 · 컨텍스트 400k 경고 · 열린 일 0)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

이 좌석의 골 축: A(모니터·오빠 요청) + B(개선요청 접수·협의) + C(업그레이드·배포·반영).

## 상태 = 완료·휴식 (열린 일 0 · 하네스 나노 0석)
이 세션에서 닫힌 단위(전부 main 랜딩 + 설치 cmp 확인 · 판정서 §110~§116 main 반영):

| § | 요청 | 랜딩 |
|---|---|---|
| 110 | 판정 690 그래픽스 팀장 체제 정본화 | PR 1093 `b158acbe83` |
| 111 | 판정 698 ① op675b ft-op-token 다듬기 3 | PR 1103 `4b8cfd2756` |
| 112 | 판정 698 ② R66 codex 좌석 Serena 부팅 경로(BOOT 1) | PR 1104 `b38dba04b2` |
| 113 | 판정 698 ③ R67 mbox-v2 추적 사본 가드 | PR 1109 `bba72c3a4e` |
| 114 | 판정 710 R68 Tank 래퍼 label-create | PR 1113 `780267aa4d` |
| 115 | R70 cherry 게이트 오탐(feat HEAD 동일 경로 PASS · spawn --cherry-override) | PR 1150 `02b45e8832` |
| 116 | R71 spawn ②-0 게이트 첫 인자 = 랜딩 브랜치(INFO_BASE) | PR 1151 `c1e5ef8912` |

- 오빠 판정 711: 하네스 휴식 · 가드 label 쓰기 차단 안 함 · 디스크 688 보류 · 그래픽스 도구 요청 오면 그때.

## 별 후보 (착수 0 — 지시 때만)
1. R72 — `--recheck` 대조 개선(v65 arch#192 #70308): 판정문 «기준 sha» 칸(`recheck_sha:`)을 정한 뒤 그 sha..CUR_HEAD 에 `_chg` 필터 재사용. 재대조 안전검사 의미 변경이라 별 설계.
2. cherry 게이트: merge-tree 충돌이 전부 design/ 이면 결과 트리로 delta 검사(①)를 살리는 개선.
3. `ft-nano-spawn.sh` 233줄(200줄 한도 초과 기존 부채) · 루트 `.fable-team/bin/ft-nano-spawn.sh`(`347db2a1a3c7`)는 키트와 다르고 옆에 게이트 없음.
4. mbox-v2 추적 사본(도어벨 분리 전 계보)과 정본 `tools/comm-canonical/mbox.sh` 계보 차이 정리.
5. codex Serena 판 정합 · 헤드룸 MCP 출력 압축 제외(설치·인프라 — 오빠 컨펌 필요).

## 함정 (실측 · 이 세션)
- 아카이브 재현은 «부분 아카이브» 로 하지 말 것 — 시험이 staged/ 예시 파일을 읽으면 부분 추출에서 거짓 FAIL(op675b T10).
- 나노 시험이 «글자 검사»(grep)만으로 패스스루를 확인하면, arch 가 그 줄을 스텁으로 실제 실행해 동작을 따로 확인한다(R70·R71).
- 실 v65 저장소 대조는 읽기 전용으로만(게이트·spawn 줄 실행 · 실 spawn·카드 이동·`--override` 실행 0).
- 같은 워크트리를 master 도 쓴다 → 커밋은 `git add -- <내 경로> && git commit -- <내 경로>` · push 는 master 몫 · 남의 미커밋 파일(REQUEST-LEDGER·NANO-LEDGER 등) 손대지 않음.
- 스크래치(#25) = `/private/tmp/claude-501/-Users-yoonhwan-Project-Agent-BYZ-Work-BYZ-Agents--worktrees-harness-ops/3f5c94ce-fbc3-42e6-a54c-4a47cb33037e/scratchpad/`.
