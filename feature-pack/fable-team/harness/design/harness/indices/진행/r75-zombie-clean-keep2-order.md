# 인덱스: zombie-clean keep-last-2 — 순번을 가드 앞에서 · 하한 2 전 티어 · 세대 #N 정렬 (R75 · 판정 807)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → R75(판정 807 · master#25 발주 #71274 · 사전 DA r1 APPROVE #71393)
- 상태: 대기
- 선행: 없음
- 제안서: 없음 — 오빠 판정 807 직접 지시(「구 세션들은 리니지2 좀비 클린이 닫는다 · 따르라」) · 설계 design/harness/DESIGN-r75-zombie-clean-keep2-order-20261010.md
- 시험 입력: PATH 앞 스텁 `tmux`·`pgrep`·`ps` + 임시 `HOME` + `ZC_TIER` 고정 + `tmux-prune --dry-run` 출력의 `[dry] tmux kill` 줄 — 실 tmux 0
- 기준값: live `~/.claude/skills/zombie-clean/scripts/zombie-clean.sh` 522줄 · attached·preserve 가 순번 미소모 · RED 에서 keep 안 회수 · `ZC_TMUX_KEEP=1` 허용 · 정렬 = session_activity

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
골의 축: B 「메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의」 + C 「업그레이드하고 레포에 커밋 푸시 … 배포 발행(슬랙) 수신해 반영」. 판정 807 · 전역 스킬 zombie-clean 수정·설치.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
zombie-clean 의 `tmux_prune()` 은 세션 계보(베이스명 + `#N`)마다 최신 2개를 남기고 나머지 오래 쉰 세션을 닫는다. 지금 코드는 ①attached·active V65 task 세션이 순번(idx)을 세기 «전»에 continue 해서 최신 2칸을 쓰지 않고(실제 보존이 «2 + attached·preserve 전부»), ②RED 압력에서 최신 2개 안도 6시간 방치면 회수하고 `ZC_TMUX_KEEP=1` 도 받아서 하한 2가 깨지고, ③«최신»을 입력 시각으로 정해 옛 세대에 질문하면 최신 세대가 닫힐 수 있다. 설계(사전 DA r1 APPROVE)는 순번을 가드 앞에서 세고, 하한 2를 모든 티어에 고정하고, 세대 번호 `#N` 내림차순으로 줄 세운다. kill 을 막는 가드(idle·attached·라이브 서버·active V65 task·유일 세대)는 하나도 빼지 않는다. 바꿀 줄의 diff 는 설계 §2·§2-r1 이 정본이다.

## 사전검증
- 소환: 예
- DA: design/harness/DESIGN-r75-zombie-clean-keep2-order-20261010.md §2-r1 — da-codex#1 r1 APPROVE (#71393 · 895ab137c1)

## 조사 근거
- `~/.claude/skills/zombie-clean/scripts/zombie-clean.sh:409` keep · `:419` 정렬 · `:428` 유일 세대 RED 우회 · `:432` read · `:439`~`:447` preserve·attached 뒤 idx · `:451`~`:453` RED ABANDON — 리포 추적본 없음(origin/main grep 0).
- 패치 사본(동작 확인용 · `bash -n` OK): 스크래치 `zc-r1.sh` 의 diff = 설계 §2-r1 코드 블록과 같다.

## 구현 범위 (닫힌 목록 · 나노 브랜치는 origin/main 기준)
1. `[structure]` 커밋: live 파일을 그대로 `scripts/harness-install/zombie-clean/zombie-clean.sh` 로 들인다(바이트 동일 · `cmp` 로 확인 · 리포 추적본 신설).
2. `[fix]` 커밋: 그 추적본에 설계 §2(순번 이동) + §2-r1 B1(keep 하한 2 + 출력 · `:428` RED 우회 제거 · keep 안 RED ABANDON 제거) + B2(`#N` 내림차순 · 같은 번호는 activity · `read -r gen activity name att`)를 넣는다. 주석은 바뀐 동작에 맞춘다(DA 비차단 정정: 옛 RED·activity 설명 주석 정리). 다른 함수는 건드리지 않는다.
3. 시험 `tests/harness/test_zombie_clean_tmux_prune.sh`(새 파일): 설계 §5 표 T1~T10 + T7b = 11건. PATH 스텁 `tmux` 가 fixture 표로 `list-sessions`·`show-options`·`list-windows`·`list-panes` 에 답하고, `pgrep`·`ps` 스텁이 T6 의 uvicorn 을 흉내 낸다. 임시 `HOME` 으로 로그를 가둔다. 시험 파일 모양(PASS/FAIL 줄·rc)은 기존 `tests/harness/test_role_spawn_name.sh` 를 따른다. `ZC_TIER`·`ZC_TMUX_IDLE_MIN=30` 고정 · `tmux-prune --dry-run` 의 `[dry] tmux kill <이름>` 줄 집합 = 기대 집합. 같은 시험을 1번 커밋 판(현행)에 돌리면 T1·T2·T7·T8·T9·T10 FAIL 이 나와야 한다(RED→GREEN 기록).

커밋은 자기 브랜치, **push 금지**. **금지**: live `~/.claude/skills/zombie-clean` 직접 수정 · 실 tmux 세션 kill · `kill-server` · 브랜치 삭제 · plist·SKILL.md·전역 CLAUDE.md 수정(문서 정정은 별 경로).

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_zombie_clean_tmux_prune.sh` rc=0 (11/11) · 1번 커밋 판에서 6건 FAIL 기록 · `bash -n` · `shellcheck` 가 새로 내는 경고 0(있으면 기록).
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_zombie_clean_tmux_prune.sh rc=0 · 이슈: 0`.
- 랜딩 뒤 master 집행(카드 밖): live `cp zombie-clean.sh zombie-clean.sh.pre-r75-order-20261010.bak` → 추적본 `cp` → `cmp` · `tmux-prune --dry-run` 1회(목록 기록) · 다음 launchd auto 로그의 `tmux 정책 정리:` 줄 확인 · 최종판정 DA.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
대기 — 사전 DA APPROVE · master spawn 대기

## 결과
(닫을 때 증거 줄)
