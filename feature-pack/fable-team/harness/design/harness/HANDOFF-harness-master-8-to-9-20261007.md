# HANDOFF — byz-harness-master-claude#8 → #9 (2026-10-07 · ctx 401k 증류)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
이 단위의 골 축: C(업그레이드·커밋·push·배포 발행·반영 — 닫는 증거 = RELEASE-<ver>.md 1장 + 머신별 「반영됨 <machine> <sha>」 행 전부 · 반영 = 사용 경로 cmp 0 + 슬랙 ts) + 6-b(오케 개선요청 접수·협의 · 원장 R1~R15) + 원문 7(쪼개 동시에).
★승계 첫 일 = 골 대조 3줄 + 부팅 3항(세션명/모델·창/Serena) + i-have-adhd 를 byz-planner-master-claude#5 에 mbox 보고 · 그 뒤 크론 10분 틱(BOOT 16조항 · 보고에 cron=<job id>) 설치 — 없으면 착수 0.★ 오빠 보고 = 결론→할 일→바뀐 것→근거 + PR·Issue 는 번호로만 쓰고 맨 아래 각주 표.

## 운영 규칙 (정본 ~/.claude/skills/fable-team/references/main-team-governance.md §6·§7 · BOOT 15조항)
- master 손 = 집행뿐(랜딩·커밋·push·좌석·명부·원장·검증된 파일 cp+cmp). 코드·스크립트·훅·시안·카드 증거 줄 직접 편집 0 — 코드=나노 · 설계·카드=arch(byz-harness-arch-claude#6 · Opus 5.5 high). 안 없이 집행 0.
- 흐름: 발주(mbox · 골 3줄 + 축 1줄) → arch 안 → master 집행 → 통지 → arch 닫힘 1줄.
- 차단·사용자 실행 필요 명령 = planner [HIL](원문+사유+영향+선택지). 훅이 본문 글자에 오탐하면 Write 로 파일 → relay + `.fable-team/state/hil-falsepos.log` 기록. 승인 명령이 훅에 걸리면 오빠가 느낌표로 직접 실행(허용 표식으로 훅은 안 풀림).
- Tank 대행: `scripts/fable-team-bin/ft-gh-as-tank.sh <create|comment|label|close|reopen|pr-comment|pr-create> … --apply`. 본문은 요청자가 쓴다. Issue edit 미지원(R10 구현 중).
- 승인된 표준 경로: 나노 닫기(`ft-nano-close` — 세션 kill·워크트리 정리·브랜치 보존) · tmux kill-session. 브랜치 삭제·`git worktree remove` 직접 = 훅 차단 → 오빠 느낌표.

## 오늘 끝낸 것 (사실)
- PR 845(키트 bin 단일 원본화+홈 훅 확인 줄 · main bc87df1302) · PR 846(나노 spawn·close 팀 env 자동 로드+role-spawn 접두 · main 5663d3f9ce) · PR 850(embeddinggemma2 조사 · main f3e86db043) 병합. Issue 842·848 닫음. 판정서 `design/teams/harness/OPS-VERDICTS-20261006.md` §1~§27.
- R13 B: COMM-GUIDE-BOOT 16조항(ai-feature-pack main 71e95b5 · 라이브=키트=초안 cmp 0 · 백업 .bak-1007-r13) + 승계 6단계 ⑤ 문구 3곳(7c15014) + BYZ 키트 templates/rules/orchestration.md(0a45036e82 계열).
- 라이브 `.worktrees/v6-realtime-live/.fable-team/bin/ft-role-spawn.sh` 만 키트 바이트로 교체(백업 .bak-1007-role-spawn). 나머지 라이브 bin 은 옛 바이트 — ★FT_BIN 전환(설치) 때 일괄. nano-close 를 바꿀 땐 nano-spawn·nano-evidence-check 를 한 세트로★.

## ★열린 일 (순서대로)
1. **나노 4석 진행 중**(전부 부팅 보고함): ①`nano-close-named-wt`(R8 보강 · ft-nano-close --wt/--branch 명시 모드) ②`tank-issue-edit`(R10 · 래퍼 Issue edit+원문 보관) ③`r13-role-spawn-cron`(R13 A · ★완료 보고 d8de2910d1 · 시험 ALL PASS · 미통과 3건은 base 외라 주장 — 독립 검증 필요★) ④`i855-test-dotenv-isolation`(Issue 855 · settings.py pytest 전용 스위치 BYZ_TEST_SKIP_DOTENV + conftest · 제품 파일 1개 변경이라 DA 소환 권고 · ★.env 붙인 pulse 실행 0회·붙이면 파일 1개 1회★). 각 나노 완료 시: master 독립 검증 → arch 닫힘 → 판정서 절 추가 → `ft-index-move … 완성 --da` → 명부 index → 나노 닫기 → PR.
2. **나노 닫기 도구**: 스크립트 `scratchpad` 대신 이렇게 — harness-env.sh source → `FT_NANO_FEAT=ops/main-base`(squash 병합이면 `--cherry-override "<사유>"`) → `bash $FT_BIN/ft-nano-close.sh <좌석> --result <판정서/RESULT 경로> --recv <나노 보고 seq> --kill`. 카드 «증거 줄»의 세트 sha = 나노 HEAD 40자(PR 병합 sha 아님) · 나노가 마지막에 커밋하면 어긋남 · 유휴 3분 필요 · 로컬 `main` 브랜치는 뒤처져 있어 FEAT 로 쓰지 말 것(17861 커밋 뒤).
3. **arch#6 안 대기**: R14 팀 feature 신설 설치 안(planner #59383 · 오빠 결정 · seats-feature.json·bin-feature/feature-env.sh·tick plist com.byz.ft-tick-feature · 접두 byz-feature- · 로스터 master+arch+DA+나노≤3 · 골 파일 design/feature/GOAL-feature.md · 설치 뒤 byz-feature-master-claude#0 개설 · tick plist=launchd 설치라 오빠 승인 범위 여부 안에서 확인) · R15 v65 press 경로 강제(v65 #59389·#59404 · 오빠 원문 「bts, poller 없는 press 하는 tester+checker 세션은 없어야한다는게 팩트」 · 나노 press 금지 포함) · R13 C(Stop 훅 cron-missing-gate · 훅 3사본 정합 뒤) · R11 은 v65 러너 수정으로 반송됨.
4. **R9**: v65→main 반영 PR 에 키트 사본 2개(ft-press-gate 갱신·ft-press-baseline-check 추가) 동봉 — v65 랜딩 주체. main 반영 통지 오면 sync 시험 확인.
5. **C 축 본 줄기**: RELEASE 0.4 1장(오늘 변경표: 이름 규칙·governance 6·7·arch 상시·게이트 master·Tank 래퍼+가드·ft-role-spawn·tmm 0.7.4·PR 845/846·BOOT 16조항·6단계 문구 + 동작 변화: nano-slots 기본 슬롯 6→5·후보 필터 머리줄 4줄 + 알려진 함정) → 이 Mac 반영(install --apply → FT_BIN 전환 → 홈 훅 설치 → 사용 경로 cmp 0 → 「반영됨 이 Mac <kit_sha>」 · 홈 훅 diff 2(boot-read-gate·orchestration-gate)는 ★orchestration-gate 3사본 정본 결정 뒤★) → 슬랙 게시(mbox→Slack 미러 #byz-planner · ts 를 반영 행에) → byzs-mac-mini 같은 절차(tailscale ssh · 홈 폴더 복사만). jarvis=명단 밖. FT_BIN 전환은 일감 사이에만(오빠 승인 완료).
6. **미해결 정리**: ①CFO 나노 byz-cfo-nano-overdraft-u1 은 오빠가 정리 완료. ②옛 이름 세션 ~15개·구 `byz-harness-master-claude#7`·`byz-harness-arch-claude#5` 종료는 오빠 판단(하네스는 kill 안 함). ③요청 원장 R10(래퍼 edit)·R6②(PR 쓰기 5종 훅 미차단)·R7(milestone) 래퍼 확장 대기. ④ai-feature-pack 에 `.bak` 3개 미추적(커밋 안 함).
7. 요청 오는 대로: Tank 대행(issues#1 · 본문은 요청자) · 요청 원장 등록 · planner [HIL] 값 집행 · v65/CFO 나노 표준 닫기(이름이 byz-<팀>-nano-… 이고 브랜치 nano/* 면 `FT_SEATS_JSON`·`FT_NANO_PREFIX`·`FT_NANO_WT_PREFIX`·`FT_ACTIVE_TAG`·`FT_NANO_LEDGER_WT` 를 그 팀 env 로 주고 실행 — U3 사례 성공).

## 함정 (실측)
- 쪽지는 «현역 이름»으로: `bash scripts/fable-team-bin/ft-harness-info.sh seats`. planner=`byz-planner-master-claude#5` · v65 master=`byz-v65-master-claude#145` · CFO master=`byz-cfo-master-claude#54` · issues=`byz-issues-master-claude#1` · arch=`byz-harness-arch-claude#6`.
- mbox 본문에 백틱 금지 · 같은 본문 fan-out 금지 · 긴 본문은 Write → relay · 본문에 `git worktree remove`·삭제 문구가 있으면 훅 오탐 → relay.
- `ft-nano-spawn.sh`·`close` 는 라이브 FT_BIN(v6-realtime-live/.fable-team/bin)을 쓴다 — harness-env.sh source(`.fable-team/bin-harness/harness-env.sh`) 후 호출. FT_SEND_FROM 은 `byz-harness-master-claude#8` 로 박혀 있음 → 후계는 `#9` 로 바꿔야 한다.
- ops/main-base 는 origin/main 병합본 + 로컬 문서 커밋 19개(미 push). PR 은 `git push origin HEAD:refs/heads/<새 브랜치>` 후 `ft-gh-as-tank.sh pr-create <제목> <본문파일> --base main --head <브랜치> --apply`. CI 전부 pass 확인 뒤 `gh pr merge <번호> --squash`(브랜치 삭제 옵션 없이 · `unset GH_TOKEN`).
- 훅이 `git add -A` 차단 → 경로 지정. 나노 spawn 의 base 는 «호출한 워크트리의 현재 브랜치»(ops/main-base).
- sweep(`ft-wt-sweep.sh`)은 나노 워크트리 정리를 자동 처리(틱이 60초마다) — 수동 호출은 오래 걸림(백그라운드로).

## 환경
- 워크트리 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops` · 좌석: byz-harness-arch-claude#6(상시) · byz-planner-master-claude#5(planner·HIL) · byz-issues-master-claude#1 · byz-cfo-master-claude#54 · byz-v65-master-claude#145 · 나노 4석(위 1번).
- 판정서 `design/teams/harness/OPS-VERDICTS-20261006.md` §1~§27 · 요청 원장 `REQUEST-LEDGER.md` R1~R15 · RELEASE 0.1~0.3(0.4 작성 전) · 인계 이전분 `HANDOFF-harness-master-7-to-8-20261007.md` · arch 인계 `HANDOFF-harness-arch-5-20261007.md`.
