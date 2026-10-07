# HANDOFF — byz-harness-arch-claude#8 → #9 (2026-10-08 · 컨텍스트 404k 승계)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

이 좌석의 골 축: 6-b(오케 요청을 사용자와 협의해 개선) + C(배포·반영) + 원문 5(머신 독립 배분) + 원문 7(쪼개 동시에).

## 승계 첫 일 (순서 고정)
1. ~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md(17조항) Read → Serena initial_instructions → activate_project(★/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops★ — 부팅 때 v6-realtime-live 가 잡혀 있다) → i-have-adhd 로드.
2. 골 대조 3줄 + 부팅 보고(세션명 / 모델·창 / Serena / i-have-adhd / cron=<id>)를 현역 master(`bash scripts/fable-team-bin/ft-harness-info.sh seats` · 지금 byz-harness-master-claude#11)에 mbox.
3. 같은 턴에 CronCreate 10분 체크 틱 — 없으면 착수 0.
4. ★야간 자율 진행 중★ — 정본 design/harness/PLAN-night-autonomy-20261008.md(단위 8 · 금지선 · 정지 조건 · 브리핑 템플릿). arch 몫 = 카드·닫힘 문안·표.

## 역할 (governance §6 · 바뀐 것 없음)
arch = 안·카드(대기/ · lint 통과 · 미커밋)·닫힘 문안(카드 증거 줄·정본 영향 줄·판정서 §초안). master = 커밋·push·설치·좌석. arch 코드 0.
- 카드 lint: `source /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/bin-harness/harness-env.sh; FT_CARD_REQUIRE_PREVERIFY=1 bash scripts/harness-install/fable-team/bin/ft-index-lint.sh <카드>`.
- 증거 줄 확인: `bash scripts/fable-team-bin/ft-nano-evidence-check.sh <카드> --repo <나노 워크트리> --feat main`.
- 판정서 초안 = `.fable-team/state/drafts-r21/OPS-VERDICT-<N>.md` · ★다음 번호 §42★(R24 tmm 닫힘용).

## 이 세션에서 닫힌 것
| 무엇 | 닫는 증거 |
|---|---|
| RELEASE 0.4 + Issue 816 범위 축소 · 라이브 bin 1:1 | 816 CLOSED · RELEASE-0.4 이 Mac 행 |
| 드리프트 검사(키트↔라이브 · tick 경고 · spawn/close BLOCK) | PR 878 a3532619ba · §39 |
| R23 Tank 래퍼 REST 한 길 | 보류(GitHub 3분 장애 · 재현 불가) · 카드 대기/r23-tank-rest-path.md · 재개 트리거 = 같은 시각 다른 쓰기 성공 실측 |
| R15 T ① 나노 BODY press 금지 1문장 | PR 882 1a577c3aa7 · §40 |
| byzs-mac-mini 키트 0.4 설치 | kit_sha 38d57db630ea · diff 0 · RELEASE 행 |
| R25 슬랙 미러 요약기 cc(cliproxy) 경로 + 실패 원인 문구 | eaa7cae7df · 라이브 설치(.bak-r25-1008) · ★설치 뒤 첫 게시 3줄 확인은 아직★ |
| 야간 단위 3 test_regress_pack 기대 낡음 | 나노 4143c964f1 · §41 초안 보냄(#60856) |
| 야간 단위 8 게이트 훅 사본 표 | 0f816053c9 TABLE-gate-hook-copies-20261008.md |

## 열린 일 (순서대로)
1. **R24 tmm — 반송 r1 재작업 대기** — 카드 진행/r24-tmm-bash32-lowercase.md 끝 「반송 r1」. 나노 byz-harness-nano-r24-tmm-bash32-lowercase#0 이 같은 카드로 재작업(master 가 반송 전달). 결과 오면: 가드 동작 시험(3.2 rc≠0 문구 · bash5 후보 rc=0) 재현 + `${x,,}` 6곳 원복 확인 + cat_of 속도 원복(이름 150개 ≈0.5 s) → §42 초안. ★2번째 HOLD 면 정지 조건(안 §3)★.
2. **R25 확인** — 설치 뒤 첫 mbox 게시의 err 로그 「요약 실패」 새 줄 0 + 슬랙 3줄. `tail ~/.hermes/logs/byz_mbox_slack_mirror.err` · 실패면 이제 원인 문구가 남는다.
3. **아침 결정 대기(브리핑 후보)**: ①홈 게이트 훅 = 정본? ⓪ 생명주기 deny 켜기?(TABLE-gate-hook-copies §사람 판단) ②프로젝트 훅을 홈 위임 1줄로? ③mac-mini homebrew bash 설치(원격 쓰기) ④~/.tmm 새 버전 설치·current 전환.
4. R15 V(cdp_helper PTT 검사) · SEATBELT 211·single_set_testing 25 정본 충돌 = v65 몫(planner 통지됨).

## 함정 (실측 · 이 세션)
- tmm 은 bash 4 전용(declare -A) — 3.2 시험은 실행 경로를 봐야 한다. `bash -n` 은 `${x,,}` 를 못 잡는다.
- 좌석이 직접 치는 `gh api -X PATCH …/issues` 는 gh-issue-author-guard 가 막는다(test_gh_as_tank.sh:200) — REST 쓰기도 래퍼로만.
- ft-tick.sh 는 장기 루프 — 파일 cp 만으론 새 함수가 안 켜진다(재기동 = 금지선 · 사람). 미러도 같다(모듈 import 는 시작 때).
- 키트 bin 을 바꾸는 랜딩 뒤 라이브 cp 전엔 전 팀 spawn·close 가 BLOCK(드리프트 검사) — 야간엔 키트 bin 랜딩 0.
- install.sh 는 `find` 전부를 해시 — 워크트리 키트엔 git 밖 .pyc 가 있어 kit_sha 가 달라진다 → 설치 원본은 `git archive origin/main`.
- zsh 에서 `ls 패턴*` 매치 0 이면 명령 전체가 실패한다(no matches found).
- bash 3.2 비교 시험 도구: scratch 에 `ln -s /bin/bash <dir>/bash` 후 `PATH=<dir>:$PATH /bin/bash <test>`.
