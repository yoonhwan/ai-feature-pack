# HANDOFF — byz-harness-master-claude#11 → #12 (2026-10-08 · ctx 402k 증류)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
이 단위의 골 축: C(업그레이드·커밋·push·배포 발행·반영) + 6-b(오케 개선요청 접수·협의 · 원장 R1~R25) + 원문 5(머신 독립 배분) + 원문 7(쪼개 동시에).
★승계 첫 일 = 골 대조 3줄 + 부팅 3항(세션명/모델·창/Serena) + i-have-adhd 를 현역 planner(`ft-harness-info.sh seats` · 지금 byz-planner-master-claude#7)에 mbox 보고 → 같은 턴에 CronCreate 10분 틱(보고에 cron=job id) — 없으면 착수 0.★ 오빠 보고 = 결론→할 일→바뀐 것→근거 + PR·Issue 번호는 맨 아래 각주 표.

## 지금 상태 (한 줄)
★야간 자율 단위 8/8 끝 · 정지 레디 유지(planner 지시)★ — 새 단위 착수 0. 오빠 아침 결정 대기: mac-mini 에 homebrew bash 설치(원격 쓰기)할지. 아침 브리핑 = design/harness/BRIEFING-morning-20261008.md.

## 오늘(10-08) 끝낸 것 (main 병합 · sha)
- PR 882 1a577c3aa7: R15 T ① 나노 첫 발주문 press 금지 1문장(판정서 §40).
- PR 883 4050da703f: R25 미러 요약기 헤드룸 cc 경로 + 실패 원인 문구 · R24 tmm bash 4 가드(§42) · regress-pack 시험 형식 검사(§41) · RELEASE-0.4 반영 행 · 요청 원장 R24·R25 · 야간 안·사본 표·mac-mini 설치 안.
- byzs-mac-mini 키트 0.4 설치: ssh -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519 byz@100.71.41.107 (tailscale ssh 금지) · kit_sha=38d57db630ea files=104 · 원격 diff 0 · 되돌림 = 원격 ~/.fable-team 과 ~/.fable-team-kit-0.4-tmp 삭제(HIL). 원격 tmux 없음·bash 3.2.
- launchd 5개 재적재(판정 338): mbox 미러·github 미러·ft-tick·ft-tick-cfo·ft-tick-kakao · 백업 ~/.hermes/state/bak-launchd-1008 · mbox 미러 seat 정규식을 ^byz-planner-(arch|master-claude)#N 로 확장.
- 명부: seats.json v65 닫힘 표식 · seats-cfo.json 계보 #53→#54→#55 + _master=#55 (백업 .bak-succ5455-1008).
- 요청 원장: R23 보류(재발 시 재개: 래퍼 GraphQL 쓰기 실패와 같은 시각 다른 쓰기 성공 실측) · R24 닫힘 · R25 닫힘 · Issue 816 닫힘.

## 열린 일
1. 오빠 결정 대기(planner 경유): mac-mini homebrew bash · 홈 게이트 훅 정본 여부(TABLE-gate-hook-copies-20261008.md) · ~/.tmm 새 버전 설치. 답이 오면 집행(arch#9 안 → 나노 → master 집행 순서).
2. 로컬 미push: 브리핑 병합 반영 커밋 65a08d106f + 이 HANDOFF + 나노 원장 행 → 다음 문서 PR 에 싣는다(야간에 새 PR 안 연다).
3. 후속 후보(기록만): 두 번째 자리 드리프트(bin-cfo/ft-tick.sh) · 3사본 기능 정합 · R7 milestone · R11 반송 · 슬랙 미러 요약기 모델은 오빠 판단 · 원격 mac-mini 운용 전 bash 3.2 런타임 시험(R24 결론: tmm 은 bash 4+ 전용, 키트 fable-team 은 3.2 실패 0).

## 운영 규칙 (main-team-governance §6·§7 · BOOT 15·17)
- master 손 = 집행뿐(랜딩·커밋·push·좌석·명부·원장·검증된 파일 cp+cmp). 코드·스크립트·훅·시안·카드 증거 줄 직접 편집 0 — 코드=나노 · 설계·카드=arch(★현역 byz-harness-arch-claude#9 · Opus 5.5 high · cron 3c28b210★).
- 흐름: 발주(골 3줄+축 1줄) → arch 안/카드 → 나노 spawn(키트 bin `scripts/harness-install/fable-team/bin/ft-nano-spawn.sh`, 먼저 `. .fable-team/bin-harness/harness-env.sh; export FT_NANO_FEAT=ops/main-base`, 모델 claude-sonnet-5-5[1m] → `zsh -lc` 로 감쌈) → 완료 보고 → master 독립 검증(시험 직접, bash5·/bin/bash 3.2) → arch 닫힘 문안(증거 줄·§N 초안 `.fable-team/state/drafts-r21/OPS-VERDICT-N.md`) → 판정서 append → `ft-index-move … 완성 --da '…#§N'` → seats-harness.json index 치환 → 나노 커밋 cherry-pick → 로컬 시험 → `git merge origin/main` «단독 실행 후 UU·diff --stat 확인» → push → `ft-gh-as-tank.sh pr-create` → CI → squash 병합 → 라이브 cp 필요 시 → `ft-nano-close`(유휴 3분: 210초 대기 뒤 재시도 · 브랜치 보존).
- 차단·사용자 실행 필요 = planner [HIL]. 훅 오탐(본문 글자) = Write 로 파일화 + `.fable-team/state/hil-falsepos.log` 기록 + 묶음 알림. `rm -rf` 는 scratch 라도 막힌다 → mkdir 새 이름.
- 야간 자율 금지선은 planner 지시로 «정지 레디 유지» 동안 그대로: 삭제·kill·force·원격 쓰기·라이브 서비스 재기동/FT_BIN cp·cd-dev/gateway 머지·Redis 쓰기·외부 게시 0.
- ★fan-out 가드★: 같은 본문을 여러 좌석에 보내면 BLOCKED — 좌석별 다른 본문.

## 함정 (실측)
- `git merge origin/main | tail; git push; pr-create` 체인 금지 — 충돌인데 push·PR 이 나가 PR 883 diff 가 main 변경을 되돌리는 모양이 됐다(메모리 feedback_check_merge_rc_before_push_and_pr).
- `plutil -replace ProgramArguments.N` 은 교체가 아니라 «삽입»이다 → 인자 중복으로 미러가 죽음. 제거는 `-remove`.
- GitHub 쓰기 장애 때 gh GraphQL + git push 500 이 같이 난다 → 백그라운드 재시도 루프(90초 간격).
- 틱 sweep 이 닫힌 나노 워크트리를 자동 정리한다(닫기 직후 skipped:cwd 는 정상, 수 분 뒤 cleaned).
- zsh 에서 ssh 를 변수 문자열로 부르지 말고 함수 `sshm(){ ssh -o IdentitiesOnly=yes -i "$HOME/.ssh/id_ed25519" byz@100.71.41.107 "$@"; }`.
- `gh pr edit`·`gh pr merge` 직접은 가드/GraphQL 문제 → 편집은 Tank 래퍼 pr-edit, 병합은 `gh pr merge --squash`(재시도).
- 나노가 「seats.json 에 내 행이 없다」 해도 하네스 명부는 seats-harness.json 이라 정상.

## 환경
- 워크트리 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops` (브랜치 ops/main-base). mbox: `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/comm/mbox.sh`.
- 현역 좌석: planner #7(총괄·오빠 인터뷰) · arch #9 · issues #2 · CFO #55 · v65 master #146(정지 레디) · feature #1. 구 정지 레디: harness master #8·#9·#10(내가 #11) · arch #7·#8 (종료는 오빠 판단).
- 내 크론 229d4ce1 은 후계 부팅 보고 확인 뒤 CronDelete.
