# REQ — 팀 구성 필수 요소 4(tester·checker·bts·poller) 실측 (ft-harness-arch#1 → ft-harness-nano#1 · 2026-10-05 · 조각 P7)

> 골 원문(GOAL-harness.md 복붙):
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
>
> 골의 축: 표 A(모니터) — 팀 구성에 시험·확인·대조·관측 넷이 빠지면 모니터가 성립하지 않는다(오빠 「tester, checker, bts, poller 놓치면 안 된다」). 발주 = ops#2 #57013.

읽기 전용 · 수정 0. 산출 `design/harness/issue-improvement/FACTS-team-essentials-20261005.md`(표 1개 = 4요소 × 팀 3(v65·cfo·ccu) + 정의 표 · [사실]/[추측] · 「파일:줄」) + 원본 `facts-raw/E*.txt`. 측정 시각 1줄.

## E1. 넷의 정체 — 좌석 / 스킬 / 도구 중 무엇인가
- **tester**: 에이전트 정의 `.claude/agents/ft-tester.md`(있으면 첫 10줄) · 좌석 실례 `ft-v65-tester-claude#13`(tmux 실재 Y/N · 명부 행) · 여는 명령(`ft-role-spawn.sh tester` 줄) · cfo·ccu 에 tester 좌석이 있었나(명부 6파일 grep `tester`).
- **checker**: `.claude/agents/ft-checker.md` · 명부 grep `checker` · 「checker 4축」이 적힌 정본(`~/.claude/archives/orchestration.md-full-20261001.md` :51~58 1줄 인용) · 지금 살아 있는 checker 좌석 수.
- **bts**: `.claude/skills/bts/SKILL.md` 첫 10줄(트리거 · 3자 대조 T · 나선 S) · `design/BTS-N-ROUND-LOOP-STANDARD.md` 머리 5줄 · 좌석인가 스킬인가(스킬이면 누가 어느 좌석에서 부르나 — 최근 mbox 로그에서 「BTS」 포함 건수·발신 좌석).
- **poller**: `tests/e2e/` 에서 poller 파일(`test_tcc8_multi_turn_and_poller.py` · `realtime_multi_e2e.py` 의 poller 함수명·`poller_dom.jsonl` 출력 경로) · `ft-press-gate.sh` 가 poller 를 요구하나(grep poller) · 누가 켜나(tester? 러너 자동?) · 최근 press 산출 `poller_dom.jsonl` 위치 1개.

## E2. 팀별 지금 상태 (표 · 셀 = 좌석명 또는 「스킬·러너 자동」 또는 「없음」 + 근거)
| 팀 | tester | checker | bts | poller |
| v65 | | | | |
| cfo | | | | |
| ccu | | | | |
- 근거 = 명부 행 · `tmux ls` · 최근 CLOSEOUT/READ 파일에서 「poller_dom」·「checker」·「BTS」 등장 여부(파일명 1개씩).
- cfo·ccu 는 오디오 press 가 없으면 poller 가 없는 것이 정상인지(DESIGN-ccu-stress-infra 에 화면 관측 대체 = SSE 수신 시각 등 1줄).

## E3. 여는 방식·시점
- `ft-role-spawn.sh` 가 받는 역할 목록(ROLE case 문 1줄 인용) — tester·checker 가 있나 · da·arch 와 같은 경로인가.
- P2 트리(`SPEC-main-orch-tree` §3)에 tester·checker 가 어느 팀에 그려져 있나(행 번호).
- 시험 lane 정본: P3 §3-B P3-3(press 석 = tester/오케) · single_set_testing §3 ③(시험 시작) · V6-IMPLEMENTATION-LOOP §7 ⑤「일괄검증(checker + tester)」 1줄 인용.

회신 mbox 3줄: 경로 · 못 한 항목 · 사실/추측 비율. 커밋 0.
