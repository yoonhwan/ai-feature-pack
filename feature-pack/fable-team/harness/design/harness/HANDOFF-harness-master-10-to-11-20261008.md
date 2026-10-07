# HANDOFF — byz-harness-master-claude#10 → #11 (2026-10-08 · ctx 405k 증류)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
이 단위의 골 축: C(업그레이드·커밋·push·배포 발행·반영 — 닫는 증거 = RELEASE-<ver>.md 1장 + 머신별 「반영됨 <machine> <sha>」 행 · 반영 = 사용 경로 cmp 0 + 슬랙 ts) + 6-b(오케 개선요청 접수·협의 · 원장 R1~R23) + 원문 7(쪼개 동시에).
★승계 첫 일 = 골 대조 3줄 + 부팅 3항(세션명/모델·창/Serena) + i-have-adhd 를 현역 planner(`ft-harness-info.sh seats` · 지금 byz-planner-master-claude#7)에 mbox 보고 · 그 뒤 ★CronCreate 10분 틱(BOOT 16 · 보고에 cron=job id)★ — 없으면 착수 0. 오빠 보고 = 결론→할 일→바뀐 것→근거 + PR·Issue 는 번호로만 쓰고 맨 아래 각주 표.

## 운영 규칙 (main-team-governance §6·§7 · BOOT 15·17)
- master 손 = 집행뿐(랜딩·커밋·push·좌석·명부·원장·검증된 파일 cp+cmp). 코드·스크립트·훅·시안·카드 증거 줄 직접 편집 0 — 코드=나노 · 설계·카드=arch(★현역 byz-harness-arch-claude#8 · Opus 5.5 high · cron e692977e★ · 구 #7 정지 레디).
- 흐름: 발주(mbox · 골 3줄+축 1줄) → arch 안 → 집행 → 통지 → arch 닫힘 1줄. 나노 완료 시 master 독립 검증(시험 직접) → arch 닫힘 문안(증거 줄·정본 영향 줄·판정서 §N 초안 = `.fable-team/state/drafts-r21/OPS-VERDICT-N.md`) → 판정서 append → `ft-index-move … 완성 --da 'design/harness/OPS-VERDICTS-20261006.md#§N'` → `seats-harness.json` index 를 완성 경로로(python 으로 문자열 치환) → 나노 커밋 cherry-pick(ops/main-base) → 로컬 시험 → `git push origin HEAD:refs/heads/ops/<이름>` → `ft-gh-as-tank.sh pr-create` → CI → squash 병합 → (라이브 cp 필요 시) → `ft-nano-close`(유휴 3분 필요: 200~240초 sleep 뒤 백그라운드 스크립트) → 나노 원장 커밋.
- ★나노 spawn/close 는 키트 bin 으로★: `scripts/harness-install/fable-team/bin/ft-nano-spawn.sh`(추적본 scripts/fable-team-bin 엔 ft-index-lint 없음 → lint REJECT). close 는 `. .fable-team/bin-harness/harness-env.sh; export FT_NANO_FEAT=ops/main-base` 뒤 실행(팀 env 이름 자동 로드는 byz-<팀>-nano- 좌석만). cp 전 close 는 드리프트 BLOCK.
- 차단·사용자 실행 필요 = planner [HIL]. 훅 오탐(heredoc 글자) = Write 로 파일화 + `.fable-team/state/hil-falsepos.log` 기록 + 묶음 알림. `git add -A` 는 막힌다(경로 지정).
- ★fan-out 가드★: 같은 본문을 여러 좌석에 보내면 BLOCKED — 공지는 파일에 쓰고 좌석별 다른 본문으로.

## 오늘(10-07~08) 끝낸 것 (main 병합 · sha)
- PR 867 e16d52a871(WT 접두) · 869 b56365e381(R9 키트 동기) · 874 1840d5e9f6(R15 H press 게이트 ⑦⑧+허가 · 게이트 훅 TOP_MODELS 정합 · R21 role-spawn 고스트 · R22 cherry 게이트 원격 ref) · 876 16201f18ea(R6② gh 가드 PR 쓰기 5종+래퍼 pr-edit·pr-close) · 878 a3532619ba(Issue 816 ②③ 라이브 bin 드리프트 검사). 판정서 §34~§39.
- 라이브 설치: 홈 gh 가드(R6b) · v65 라이브 press 게이트(R9·R15H) · ★라이브 bin 전체 1:1(Issue 816 · tar `.fable-team/state/live-bin-pre-0.4-1007.tar`)★ · 드리프트 4파일(tar live-bin-pre-drift-1007.tar). RELEASE-0.4.md 「이 Mac」 = 반영됨(키트 51beb7be05 기준 — 드리프트 PR 이후 sha 갱신 필요).
- R21 고스트 서제스천: 홈 4파일(전역 CLAUDE.md 하드 룰 10 · codex AGENTS · BOOT 17 · context-management) + ai-feature-pack 커밋 5f01fc0 push · 백업 .bak-r21-1007.
- R18 cfo-env.sh 설치 + CFO 첫 실닫기 증거 완성(CFO 확인 5288f9b5f1) · R16 견본 feature 커밋됨 · FT_MBOX_SH 를 팀 env 4장에 추가(.bak-1007-r20) · harness-env FT_NANO_FEAT=ops/main-base · seats-*.json `_hil_route` planner #7.
- v65 티어 승격(판정 330): arch Fable 5.1 max(→ 자체 증류로 #174) · DA codex gpt-6.1-sol high #29.
- 워크트리 sweep 수동 1회: 4개 정리(ignored 보관 · 브랜치 보존).

## ★열린 일 (순서대로)★
1. 요청 원장 R23(GraphQL 실패 시 gh api REST 폴백 · planner #60677 · 낮은 우선 · 816 뒷정리 뒤) → arch#8 안 요청.
2. Issue 816: 드리프트 병합 sha(a3532619ba)+라이브 반영 증거를 issues master#2 로 보내 코멘트 · 닫기는 planner 값. RELEASE-0.4.md 이 Mac 행 sha 갱신(드리프트 포함) 후 커밋.
3. ★C 축 본 줄기 남은 것★: RELEASE 0.4 슬랙 게시(ts 를 반영 행에) → byzs-mac-mini(tailscale ssh · 홈 폴더 복사만 · 키트 install) → 「반영됨 byzs-mac-mini <sha>」 행. 슬랙 게시 방법은 arch#8/planner 에 확인(미확인).
4. launchd ft-tick/ft-tick-cfo/kakao 가 10-03 이후 미적재(planner#7 에 FYI 보냄 · 판단 대기). 영향: drift_watch tick 경고·wt-sweep 자동 재시도 꺼짐 → 닫기 뒤 wt-clean 계획이 쌓이면 `ft-wt-sweep.sh` 수동(표준승인 경로).
5. 후속 후보(기록만): bin-cfo/ft-tick.sh 같은 두 번째 자리 드리프트 · orchestration-gate 3사본 기능 정합(홈에 키트 생명주기 차단 반영은 816 뒤) · 인계 남은 R7(milestone)·R11(반송).
6. 구 좌석(정지 레디·종료는 오빠 판단): byz-harness-master-claude#9 · byz-harness-arch-claude#7·#6 · v65 arch #172·#173, DA #28.

## 함정 (실측)
- `ft-nano-close` 증거 줄 정규식: `- 세트: <40hex> · 시험: <명령 «1개» rc=<n> · 이슈: 0` (명령 2개 = 형식 REJECT) · 유휴 3분 · cherry 게이트(미랜딩 브랜치) = `--cherry-override "<사유>"` (브랜치 없음 검사는 못 넘음 → FEAT 는 반드시 존재하는 ref).
- 나노 커밋을 ops/main-base 에 cherry-pick 하면 patch-id 동일 → cherry 게이트 통과. 워크트리 `.serena/project.yml` 은 미커밋 M 노이즈(커밋 금지 · git diff HEAD~1 대신 git show --stat HEAD).
- `gh pr checks` 에서 Web Test 흔들림(v65 FE 시험) 1건 = 재실행(워크플로 끝난 뒤 `gh run rerun <id> --failed`).
- 잔존 환경: `FT_SEND_FROM` 은 harness-env.sh 에 #10 으로 박혀 있음 → ★#11 로 갱신(백업 후 python 치환 · 한글 주석 때문에 BSD sed 실패)★ + seats-harness.json `_master` 도 #11.
- 승계 이름 규칙: 발신 전 `ft-harness-info.sh seats` — planner #7 · v65 master #146 · CFO #55 · feature #1 · issues #2 · arch #8.

## 환경
- 워크트리 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops` (브랜치 ops/main-base · origin/main 병합본 + 로컬 문서 커밋 · PR 은 `git push origin HEAD:refs/heads/<새 브랜치>` 후 `ft-gh-as-tank.sh pr-create <제목> <본문파일> --base main --head <브랜치> --apply`).
- 좌석: arch#8(상시) · 하네스 나노 0석 · DA 좌석 byz-harness-da-codex#0(정지, 필요 시 arch 가 소환).
