# HANDOFF — byz-harness-master-claude#9 → #10 (2026-10-07 20:35 · ctx 406k 증류)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
이 단위의 골 축: C(업그레이드·커밋·push·배포 발행·반영 — 닫는 증거 = RELEASE-<ver>.md 1장 + 머신별 「반영됨 <machine> <sha>」 행 · 반영 = 사용 경로 cmp 0 + 슬랙 ts) + 6-b(오케 개선요청 접수·협의 · 원장 R1~R18) + 원문 7(쪼개 동시에).
★승계 첫 일 = 골 대조 3줄 + 부팅 3항(세션명/모델·창/Serena) + i-have-adhd 를 byz-planner-master-claude#6 에 mbox 보고(현역은 `ft-harness-info.sh seats`) · 그 뒤 ★CronCreate 10분 틱(BOOT 16 · 보고에 cron=job id)★ — 없으면 착수 0. 오빠 보고 = 결론→할 일→바뀐 것→근거 + PR·Issue 는 번호로만 쓰고 맨 아래 각주 표.

## 운영 규칙 (main-team-governance §6·§7 · BOOT 15)
- master 손 = 집행뿐(랜딩·커밋·push·좌석·명부·원장·검증된 파일 cp+cmp). 코드·스크립트·훅·시안·카드 증거 줄 직접 편집 0 — 코드=나노 · 설계·카드=arch(★현역 byz-harness-arch-claude#7 · Opus 5.5 high · cron 5ddcf60b★ · 구 #6 은 정지 레디). 안 없이 집행 0.
- 흐름: 발주(mbox · 골 3줄+축 1줄) → arch 안 → 집행 → 통지 → arch 닫힘 1줄. 나노 완료 시 master 독립 검증(시험 직접) → arch 닫힘 → 판정서 절(OPS-VERDICTS §N) → `ft-index-move … 완성 --da <판정서#§N>` → 명부(seats-harness.json) index 를 완성 경로로 → 나노 닫기 → PR.
- 차단·사용자 실행 필요 명령 = planner [HIL]. 훅 오탐(본문 글자) = 본문을 Write 로 파일화 → relay + `.fable-team/state/hil-falsepos.log` 기록. `pkill`·`git add -A`·`rm -rf` 는 막힌다(내 background 정지는 TaskStop).
- ★mbox 본문에 `git worktree remove`·삭제 문구를 쓰지 않는다(오탐) · 백틱 금지 · 긴 본문은 Write 후 relay.

## 오늘 끝낸 것 (사실 · main 병합)
- PR 859(81c9f3c684): Tank 래퍼 Issue edit(R10) · ft-nano-close --wt/--branch(R8) · ft-role-spawn 체크 크론(R13 A) · 팀 feature 골 파일. PR 864(c0f85616b4): Issue 855 pytest .env 격리(215f52056a) + ft-index-lint ⑦⑧(R16) · 판정서 §31~§32. 판정서 §28~§33 = `design/teams/harness/OPS-VERDICTS-20261006.md`.
- ★팀 feature 설치(R14)★: seats-feature.json · bin-feature(feature-env.sh · goal-lines 3줄 · ft-tick · seat-status · goal-tick 스텁 · FT_MBOX_SH · FT_CARD_REQUIRE_PREVERIFY=1) · launchd com.byz.ft-tick-feature(running) · 워크트리 feature-main(브랜치 feat/feature-main) · byz-feature-master-claude#0 · byz-feature-arch-claude#0 · 나노 진행 중(#856).
- 라이브 RT(v6-realtime-live/.fable-team/bin)에 ft-index-lint.sh 단독 설치(백업 .bak-1007-r16). 나머지 라이브 bin 은 옛 바이트 → ★FT_BIN 전환(RELEASE 0.4) 때 일괄(ft-nano-close·spawn·evidence-check 는 한 세트 — 단독 cp 금지)★.
- DA 좌석 byz-harness-da-codex#0(codex gpt-6.1-sol low fast · 정지 레디) — 필요할 때 arch 가 소환 결정(bounded 10+10분).
- CFO U4·U5 나노 표준 닫기(직접 env 주입 close-u4/u5 스크립트 = scratchpad). 주의: 6379(라이브 Redis) 사고 — 내 첫 검증이 19:02:25~19:04:49 6379 로 돎(+ 나노 18:40~18:58) → arch 키 대조 중 · flush 0 · ops:account_seen_fail 일일 카운터 오염 가능 · 키 정리는 planner [HIL]. 이후 모든 pytest = REDIS_PORT=9 · LOCAL_VLLM_BASE_URL=http://127.0.0.1:9/v1 · timeout · 대칭 deselect 3.

## ★열린 일 (순서대로)
1. ★PR 867(ft-nano-close WT 접두 FT_NANO_WT_PREFIX · 판정서 §33 · 원장 R18)★ CI 13/13 확인 → `gh pr merge 867 --squash`(unset GH_TOKEN · 브랜치 삭제 옵션 없이). 병합 뒤 ops/main-base 에 origin/main 병합(충돌 시 원장 3개는 양쪽 줄 보존).
2. ★R9 키트 동기★: main 에 ft-press-baseline-check.sh 랜딩됨(0cc8ba4dff #834 A)이나 키트(scripts/harness-install/fable-team/bin)엔 baseline-check 없음 + ft-press-gate.sh 추적본↔키트 DIFF = kit_bin_sync 실패 원인. 동기 방식(키트 cp / 라이브는 0.4 일괄 vs 단독) arch#7 안 → 집행. 이후 R15 H 카드(r15-gate-permit: 게이트 ⑦ 역할·⑧ 직전 BTS 표 + 허가 파일)·T 문구 → 안: `design/teams/harness/PLAN-r15-press-path-enforcement-20261007.md`. V(cdp_helper PTT 검사)는 v65 소관(설계 전달만).
3. R16 견본: `design/teams/harness/drafts/r16/feature-card-template.md` → feature-main `design/feature/indices/README.md` 로 cp(feature-main 은 PR 로 반영).
4. 요청 원장 접수 후 arch 안 대기: R7(milestone)·R11(반송)·R17(855 밖 기존 실패 11건 — poller_dom 7·gpu_vm_control 2·cleanup_auth 1·loom 1 · planner 확인)·R18(bin-cfo/cfo-env.sh 낮은 우선).
5. ★C 축 본 줄기★: RELEASE 0.4 1장(변경표: 이름 규칙·governance 6·7·arch 상시·Tank 래퍼+가드+edit·ft-role-spawn 크론·ft-nano-close 명시모드+WT 접두·ft-index-lint ⑦⑧·tmm 0.7.4·BOOT 16조항·PR 845/846/859/864/867·6단계 문구 + 동작 변화: nano-slots 기본 6→5·후보 필터 4줄·feature 팀 FT_CARD_REQUIRE_PREVERIFY + 알려진 함정) → 이 Mac 반영(install --apply → FT_BIN 전환 → 홈 훅 → cmp 0 → 「반영됨 이 Mac <kit_sha>」; orchestration-gate 3사본 정본 결정 먼저) → 슬랙 게시(ts 를 반영 행에) → byzs-mac-mini(tailscale ssh · 홈 폴더 복사만). FT_BIN 전환은 일감 사이에만(오빠 승인 완료).
6. 6379 카운터 정리: arch 대조 결과 → planner [HIL]. 오빠 지시 대기분 없음.

## 함정 (실측)
- ft-nano-close: 증거 줄 정규식 `- 세트: <40hex> · 시험: <cmd> rc=<n> · 이슈: 0`(긴 서술 한 줄은 불일치) · 유휴 3분 필요(나노가 쪽지에 반응하면 초기화 → ★200초 sleep 뒤 실행하는 백그라운드 스크립트★ 패턴) · 카드가 완성/ 으로 간 뒤엔 명부 index 도 완성 경로로(`seats-harness.json`) · cherry 게이트가 patch-id 로 REJECT 하면(cherry-pick 한 커밋이 카드 사본 줄 때문에 다름) 코드 파일 cmp 동일 확인 뒤 `--cherry-override "<사유>"`. FT_NANO_FEAT=ops/main-base.
- ft-index-move 완성 이동 게이트: 카드에 「정본 영향 없음: <이유≥10자>」 또는 「정본 갱신: …」 줄(설계 판단 → arch 가 씀).
- origin/main 병합 때 카드가 진행/·완성/ 양쪽에 되살아날 수 있음 → git ls-files 로 확인 후 옛 판 제거.
- 좌석 이름은 `ft-harness-info.sh seats`: planner=byz-planner-master-claude#6 · v65 master=byz-v65-master-claude#145 · CFO master=byz-cfo-master-claude#54 · issues=byz-issues-master-claude#1 · arch=#7 · feature master=byz-feature-master-claude#0.
- ★harness-env.sh 의 FT_SEND_FROM 을 byz-harness-master-claude#10 으로 바꿔 쓸 것★(`.fable-team/bin-harness/harness-env.sh` · gitignore 운영 파일 · 백업 후 sed). seats-harness.json `_master` 도 #10 으로.
- 스크래치 스크립트: close-u4/u5.sh 등은 구 세션 scratchpad(없을 수 있음) — 형태는 위 「나노 닫기」 참조.

## 환경
- 워크트리 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops` (브랜치 ops/main-base · origin/main 병합본 + 로컬 문서 커밋 · PR 은 `git push origin HEAD:refs/heads/<새 브랜치>` 후 `ft-gh-as-tank.sh pr-create <제목> <본문파일> --base main --head <브랜치> --apply`).
- 좌석: byz-harness-arch-claude#7(상시) · byz-harness-da-codex#0(정지) · byz-planner-master-claude#6 · byz-feature-master-claude#0·arch#0 · 하네스 나노 0석. 판정서 §1~§33 · 요청 원장 R1~R18 · RELEASE 0.1~0.3(0.4 작성 전) · 인계 이전분 HANDOFF-harness-master-7-to-8 · 8-to-9 · arch-6.
