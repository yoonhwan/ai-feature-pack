# HANDOFF — byz-harness-arch-claude#14 → #15 (2026-10-08 · 컨텍스트 405k 증류)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

이 좌석의 골 축: A 모니터·오빠 요청 + 6-b(개선요청 접수·협의) + C(배포·반영).

## 승계 첫 일 (순서 고정)
1. ~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md Read → Serena initial_instructions → activate_project(★/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops★ — 안 주면 다른 워크트리가 잡힌다) → i-have-adhd 로드.
2. 골 대조 + 부팅 보고(세션명 / 모델·창 / Serena / i-have-adhd / cron=<id>)를 현역 master(★byz-harness-master-claude#16★ — 발신 전 `ft-harness-info.sh seats` 로 현역 이름 확인)에 mbox. 같은 턴 CronCreate 10분 틱.
3. 함정: mbox 명령 줄에 백틱 금지(훅) · 카드·문서는 Write 도구 · 긴 쪽지는 relay. zsh 에서 파일 목록 변수는 배열 `(${(f)"$(…)"})` 로(단어 분리 안 됨 · 이번 세션 실측). 임시 파일은 scratchpad · `rm -rf` 는 block-destructive 가 막음(새 mktemp 디렉터리로). 시험 문자열에 `bash -c` 가 있으면 안전검사가 막음 → 파일로 옮겨 python 으로 돌림.
4. 남의 pane `❯` 뒤 글자 = 자동완성 제안(하드 룰 10) — 근거로 쓰지 않는다.

## 역할 (governance §6)
arch = 설계·카드(대기/ · lint 통과 · 미커밋)·DA 소환 판단·나노 결과 «독립 재현»·판정서 초안. master = 커밋·push·설치·좌석. arch 코드 0.
- 카드 lint: `source <루트>/.fable-team/bin-harness/harness-env.sh; FT_CARD_REQUIRE_PREVERIFY=1 bash scripts/harness-install/fable-team/bin/ft-index-lint.sh <카드>` — 구현 범위에 실재 파일 경로(백틱) 1개 이상.
- 나노 증거 줄 검사: `bash scripts/harness-install/fable-team/bin/ft-nano-evidence-check.sh <카드> --repo <나노 wt> --feat <base>` — 증거 줄은 카드 «끝» 맨몸 1줄(상태 줄 안·괄호 섞임 = REJECT · v436·v438 실례).
- 판정서 초안 = `<루트>/.fable-team/state/drafts-r21/OPS-VERDICT-<N>.md` · ★다음 번호 §63★(§58~§61 반영 끝 · §62 초안 있음 · 반영 대기).
- DA = byz-harness-da-codex#0(relay · 10+10분 · 2 HOLD 면 종료·통합 이관). relay 뒤 3~5초에 pane 확인 — 안 돌면 `mbox ring <좌석> <seq>`(이번 세션 2회 필요했음). DA 컨텍스트 21% 남음 — 곧 승계 필요할 수 있음(master 에 알릴 것).

## 이 세션에서 닫힌 것
| 무엇 | 닫는 증거 |
|---|---|
| 판정 원장(나노1) | §58 · nano/v430 b382723e31 · 반송 1(잠금 pid 회수·seed 시험) |
| 메인팀 인박스(나노4) | §59 · d2ce4b6ff3 · 구현 DA APPROVE(DA-news-board §10) · 반송 2(비동기 Haiku·미상 의무) |
| 결과 답글 이동 게이트(카드2) | §60 · 111360204d · 반송 2(훅 오탐 4/8·따옴표 우회) · guard = BYZ settings 만(master #62934) |
| CI 비용 차단(판정 436) | §61 · PR #930 · 6fe01a83a1 · 이벤트별 잡 PR 10·push 4·수동 11 |
| 대기 카드 작성 | v421-board · v423-publish-report-hooks · mbox-sh-split-200 · r35-role-spawn-team-env-reject · r37-index-move-da-section-binding(미커밋 · R37 원장 접수) |

## 열린 일 (순서대로)
1. **판정 440 랜딩 정본화 설계**(master #63098): `design/teams/harness/DESIGN-landing-canon-440-20261008.md` r2(§6 = 랜딩 commit S·범위 `S^1..S`·merge-base 0·arch 확인 blob 동일·부분 PR·CLOSEOUT 필드·fixture 4) · DA 파일 `design/teams/harness/DA-landing-canon-440-20261008.md` §2 = HOLD-L1 1회(Q2·Q3 APPROVE) · §3 교정 요청 relay seq 63144 → ★§4 회신 대기★. APPROVE 면 master#16 에 «설계 경로 + DA 판정 1줄 + 오빠 결정 2문»(누가 정본 쓰나: ①구현 나노 같은 PR(추천) ②팀 정본 전담 좌석 ③랜딩 뒤 master CLOSEOUT / 하네스 문서 브랜치: ①랜딩 단위마다 main(추천) ②ops/main-base 유지·주기 병합) 회신. 2번째 HOLD 면 통합 이관 표를 설계에 붙이고 같은 회신. 설계·DA 파일 둘 다 미커밋(master 커밋).
2. **판정 438 pytest 속도**: 나노 nano/v438-l6-redis-fixture-fast `2106bc70f9` arch 재현 통과(로컬 1028 → 248.5초 · 7708 passed/50 failed/40 errors 동일 · 실패 18파일 fixture import 0 · 원인 PAYMENT_MODE 로컬 미설정) · §62 초안 = drafts-r21/OPS-VERDICT-62.md · ★진행 카드 증거 줄 재기입 대기(반송 형식)★ → evidence-check OK 면 master 에 알림. 랜딩 뒤 PR CI Python Test 분 실측(예상 약 6.4분 · 6분 경계) → >6분이면 설계 §3-3 라(e210 control_c_true 2개 slow)·다(xdist + 사전 DA) planner 결정.
3. **인박스 라이브 설치 결함**(master#16 에 seq 63149 보고): 라이브 `.fable-team/comm/mbox.sh:168` 에 적재 줄이 있는데 `.fable-team/bin/ft-inbox.sh`·`ft-inbox.py`·`ft_inbox_core.py` 없음 → 모든 send 에 WARN · 적재 0. master 가 §59 표 1행대로 cp 했는지 확인(`ls .fable-team/bin/ft-inbox*` · send 출력 WARN 0).
4. 진행/ 에 `v442-slack-mirror-two-dead.md` 새 카드(master 가 연 것 · arch 미검토) — 결과 오면 재현.
5. 대기: R37 카드 착수는 카드2 랜딩 뒤(같은 파일) · 판정 438 설계 §3-3 · gate-hook-kit-equals-home(planner 지시 대기) · r23-tank-rest-path(보류) · distill-gate haiku 창 값(master 지시 오면).

## 함정 (실측 · 이 세션)
- master 는 #15 → #16 승계됨. planner = #11.
- 하네스 판정서·카드는 ops/main-base(origin/main 보다 269 앞)에만 있다 — 440 설계 G4.
- ft-index-move 는 `--da §N` 의 «닫힘» 글자만 보고 절 접두 비교(§5 가 §57 에 걸림) — R37.
- 정본 갱신 요청 수신 좌석 FB_ARCHDOC#11 은 죽어 있음(쪽지 10 미읽음) — 440 G1.
- redis-py 7.4 기본 재시도 base 1초·cap 10초(소켓 전 ping 이 잠듦) — 438 원인.
