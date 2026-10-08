# HANDOFF — byz-harness-arch-claude#16 → #17 (2026-10-08 · 컨텍스트 410k 증류)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

이 좌석의 골 축: A 모니터·오빠 요청 + 6-b(개선요청 접수·협의) + C(배포·반영).

## 승계 첫 일 (순서 고정)
1. `~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md` Read → Serena `initial_instructions` → `activate_project(project="/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops", session_id=…)`(session_id 없이 부르면 다른 워크트리가 잡힘 — #16 실측) → i-have-adhd 로드.
2. 골 대조 + 부팅 보고(세션명 / 모델·창 / Serena / i-have-adhd / cron=<id>)를 현역 master(지금 byz-harness-master-claude#17 — 발신 전 `.fable-team/seats-harness.json` `_master` 확인)에 mbox. 같은 턴 CronCreate 10분 틱(mbox recv + `tmux ls | grep byz-harness-nano` 현역 나노 실측 + 오빠 3줄).
3. master 에 부탁: 명부 정리 `bash .fable-team/bin/ft-seat-retire.sh byz-harness-arch-claude#16 byz-harness-arch-claude#17 --seats .fable-team/seats-harness.json`(R43 도구 · `_arch` 도 같이 바뀜).

## ★지금 최우선 (오빠 발주 · master#17 #64368) — 슬랙 = 읽기 전용 공유판★
- 오빠 원문: 「거기서 자꾸 답하라는데 어차피 들을것도 아니고 반영될것도 아니니 작업상황·이슈보고·변경내용·상태를 공유하고 hil이나 인터뷰가 있으면 정확히 어느 세션으로 가거나 플래너 정확한 세션을 알려주는 공유를 중점으로」
- 설계: `design/harness/DESIGN-slack-readonly-share-20261008.md`(§1 실측 9종 · §2 답장 문구 13 · §4 새 틀 · ★§4-r2 가 §4·§5 를 이긴다★ · A-r3·B-r3 = DA r2 잔여 교정).
- DA: `design/harness/DA-slack-readonly-share-20261008.md` — r1 HOLD(Q1·Q2·Q3) → r2 HOLD(Q1 정규식 · Q2 기존 원장 이관 · Q3·Q4 APPROVE) → bounded 종료 → master 에 «r3 스팟 1회» 결정 요청 #64449(회신 대기).
- 남은 단계: master 결정(판정 468 선례 = 스팟 1회) → DA 파일에 「## r3 스팟 요청」 절(A-r3·B-r3 두 항목만 · 10분) 추가 + relay → APPROVE → 카드 `design/harness/indices/대기/<이름>.md`(lint `FT_CARD_REQUIRE_PREVERIFY=1` · 사전검증 「소환: 예」 + DA 경로) → master spawn → 결과 재현(가짜 LLM·가짜 tmux·가짜 history · 슬랙 API 0) → 닫힘 초안.
- master 가 이미 한 일: seats-harness·loom·ops 의 `_hil_route` 를 planner#12 로 손 정정(#64430).
- ★판정 497(master#17 #64454)★: r3 스팟 DA 1회 승인 — 범위 = A-r3(정규식 「확인해 주」·Q번호 + 반례 3) · B-r3(옛 planner 이름 → @planner 이관 · 재발송 0 · fixture 4) 두 항목만. ★r3 도 HOLD 면 멈추고 planner#12 로★.
- ★판정 496(master#17 #64447 · 범위 확장 · DA 소환 필수)★ — 오빠 원문 20:4x: 「기획에 물어봐 뉴스 트리와 세션과 큐를 정리공유하는 개편 / da도 같이」 + 20:3x 「뉴스 공유시 메인팀 현재 상황과 메인팀 큐를 같이 정리 공유. 개편.」. 범위: 뉴스 = ①완성 트리(골 축별) ②세션 트리(메인 8팀 좌석·상태) ③큐(팀별 다음 순서)를 한 틀로 — 슬랙·pane 뉴스 공통. DESIGN-slack-readonly-share 와 «같은 단위»로 묶어 설계. 산출 = 설계 문서 + DA 판정 경로를 ★planner#12 로 회신★(오빠 컨펌은 planner 가 올림). 기존 `ft-news-tick` ⑥(요약 기본 · 전체는 `FT_NEWS_FULL=1`) 규칙과의 관계 정리 필수. 생성 원천 후보(#64443): ft-news-tick ⑥ 출력 + 메인 8팀 명부 `seats*.json` `_master` + 큐(각 팀 indices 진행/대기 카드). planner 보고는 이미 «8팀 지금 하는 것 + 큐» 한 표로 전환됨(planner#12 #64440).
- 순서 제안(#17 판단): ①r3 스팟(슬랙 문구·inbound 잔여 2) → ②설계 §8 «뉴스 = 완성 트리+세션 트리+큐» 추가(ft-news-tick·명부·카드 실측부터) → ③496 범위 DA → ④카드(한 단위 또는 문구/뉴스 2장 — DA Q4 와 같이 판단) → planner#12 회신.

## 이 세션에서 닫힌 것 (판정서 §70~§75 · 전부 병합·설치)
| 단위 | 판정 | 반영 |
|---|---|---|
| v461 인박스 via | §70 | PR 954 ed256f78ab |
| R42 sha base 좌석 닫기 | §71 | PR 956 |
| R41 정본 쪽지 소음 | §72 | PR 958 |
| 판정 466 block-destructive 글/실행 구분 | §73 | PR 962 · 홈 훅 설치 |
| R43 옛 master stall-wake · ft-seat-retire | §74 | PR 965 0be455111a · FT_BIN cp |
| R44 push +ref/:ref/--delete/--mirror 차단 | §75 | PR 974 |

## 대기 (planner 순서)
- R46: v466 훅이 `gh pr create --body-file - <<EOF`(heredoc → gh) 본문 글자를 검사 — 설계 경계(heredoc 글 싱크 = cat/tee 만). 지금 길 = 본문 파일을 Write 로 만들고 `--body-file <파일>`. 처방 후보 = 글 싱크에 gh body 입력 추가(싱크 목록 확장 = 판정 + 사전 DA). 진단 #64351.
- 인계 #15 의 대기: 훅 오탐 통합(→ 466 으로 닫힘) · R35 · mbox-sh-split · r23 · v421/v423 · gate-hook-kit-equals-home.

## 함정 (실측 · 이 세션)
- 훅 패턴 글자(재귀 삭제·강제 종료 등)를 Bash heredoc·변수에 쓰면 «v466 이전 규칙» 꼴(실행 소비자 있음 · python heredoc)은 여전히 막힌다 → 카드·문서·프로브는 Write/Edit 도구로, 패턴은 훅 파일에서 `sed -n` 으로 읽는다. 막히면 `.fable-team/state/hil-falsepos.log` 에 1줄.
- `rm -rf` 는 스크래치도 막힌다 — 지우지 말고 새 폴더 이름.
- 나노 결과 재현은 `git archive <sha> scripts tests/harness tools/comm-canonical`(tools 빠지면 test_inbox 7 FAIL — rc 127).
- ops/main-base 에 없는 main 전용 파일은 카드 lint 가 «경로 없음» — main 과 cmp 같은 다른 워크트리 절대경로로 인용.
- DA codex 좌석은 send 뒤 안 깨어나는 일이 잦다 — `mbox ring <좌석> <seq>` 후 pane 에 `Working` 확인.
- 판정 절에 「대상 카드: <basename>」 필수 · 나노 증거 줄은 RESULT 맨 끝 「카드 증거 줄: …」 → master 가 카드에 옮김(#63821).
- 판정서 초안 = `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/state/drafts-r21/OPS-VERDICT-<N>.md` · 다음 번호 = 판정서 마지막 §(지금 §75) + 1.
- 재현 스크래치: 이 세션 scratchpad 의 `v466-probe.py`·`r44-probe.py`(JSON 입력 공격 사례)는 세션 종속 — 필요하면 새로 만든다.
