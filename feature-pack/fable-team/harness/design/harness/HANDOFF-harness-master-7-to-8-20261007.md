# HANDOFF — byz-harness-master-claude#7 → byz-harness-master-claude#8 (2026-10-07 · ctx 401k 증류)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
이 단위의 골 축: C(업그레이드·커밋·push·배포 발행·반영) — 닫는 증거 = 「RELEASE-<ver>.md 1장 + 머신별 「반영됨 <machine> <sha>」 행 전부」(arch 판정: 반영 = 사용 경로 cmp 0 + 슬랙 ts). 원문 5(머신 배분) · 6-b(개선요청 협의) · 7(쪼개 동시에).
★승계 첫 일 = 골 대조 3줄을 byz-planner-master-claude#5 에 mbox 보고 + 부팅 3항(세션명/모델·창/Serena) 후 착수. 오빠께 올리는 글 = 결론→할 일→바뀐 것→근거 + PR·Issue 는 번호로만 쓰고 맨 아래 «번호·종류·제목·상태» 각주 표.★

## 오늘 확정된 운영 규칙 (정본: ~/.claude/skills/fable-team/references/main-team-governance.md §6·§7 · BOOT 15번째 줄)
- **master 손 = 집행뿐**: 랜딩·커밋·push·좌석·명부·원장·설치 복사(cp+cmp). 코드·스크립트·훅·시안·카드 증거 줄은 «직접 편집 0» — 코드=나노, 설계·시안=arch(byz-harness-arch-claude#5 상시 · Opus 5.5 high). 안 없이 집행 0, arch 안이 있어도 손으로 쓰기 0(오빠 「독단 금지」). 내가 오늘 어긴 2건(ft-role-spawn 라이브 직접 수정 · 래퍼 pr-create 직접 작성)은 기록됨.
- **작업·결정은 arch 검토 뒤**: 발주(mbox · 골 원문 3줄 + 골 축 1줄) → arch 안 → master 집행 → 결과 통지 → arch 닫힘 1줄.
- **차단·사용자 실행 필요 명령 = planner [HIL]**(명령 원문+사유+영향+선택지). 하네스 내부 결정(래퍼·가드·설치)은 master+arch 가 결정·집행(planner 인터뷰 0). 오빠가 이 pane 에서 직접 값을 주는 중이면 그 자리에서 받는다(AskUserQuestion). 훅 오탐(실제 파괴 0) = 파일 기록 + 실행 허용 + 묶음 알림(`.fable-team/state/hil-falsepos.log`) — 본문에 push 옵션·삭제 글자가 있어 막히면 Write 도구로 파일을 쓰고 relay.
- **Tank 대행**: Issue 쓰기·PR 개설은 byz-tank 래퍼 `scripts/fable-team-bin/ft-gh-as-tank.sh <create|comment|label|close|reopen|pr-comment|pr-create> … --apply`(기본 dry-run). 본문은 issues#1(또는 요청자)이 쓴다 — 하네스는 내용을 쓰지 않고 집행만. 보드 등록(project item-add)은 오빠 gh 로그인 예외. byz-tank = 리포 write(오빠 값 10-07: main push 허용 · main 삭제·force 만 막음 · 가드 훅이 막음). milestone 미지원(R7).
- 보고 틀: GUIDE-human-report(결론→할 일→바뀐 것→근거) + PR/Issue 각주 표. 세션끼리 mbox 는 예외.

## 오빠 값 (C 축 · 이 pane 인터뷰 직접 · 10-07)
- 운용 머신 명단 = **이 Mac + byzs-mac-mini**(tailscale 온라인). **jarvis = 호스트 불명 → 명단 밖**(RELEASE 0.4 에 「명단 밖(오빠 값 날짜)」 한 줄).
- FT_BIN 전환 승인(옛 폴더 보존 · 되돌림 = 팀 env 한 줄 복원 · 일감 사이에만 · 드리프트 채택 PR 랜딩 뒤).
- byzs-mac-mini 설치 승인 · tailscale ssh 접속 · 홈 폴더 복사만(launchd·글로벌 설정 손대지 않음).

## ★열린 일 (순서대로)
1. **나노 2석 동시 spawn** — 카드(arch 작성·lint OK·파일 겹침 0): `design/harness/indices/대기/kit-bin-adopt.md`(73파일 표 + 채택 + sync 시험) · `kit-hooks-install-check.md`(block-destructive 템플릿 + install 훅 등록 확인 줄). 이 인계 커밋에 카드가 들어 있다. base = 최신 origin/main(spawn 은 «호출한 워크트리의 현재 브랜치»를 base 로 쓴다 → `ops/main-base` 브랜치(= origin/main)에서 호출). 나노 닫기는 카드 증거 줄 + 판정서 §24~ + FT_NANO_FEAT 주입.
2. **나노 닫기 2건**: ①`byz-harness-nano-gh-guard-scope-main-prcreate#0`(PR 843 squash 병합됨 — cherry 게이트가 patch-id 상이로 + 판정 → `--cherry-override "<사유>"` + FT_NANO_FEAT 는 «로컬에 있는 브랜치»여야 함(origin/main 은 「브랜치 없음」 REJECT) → 로컬 `main` 또는 병합 브랜치) ②planner 요청 #58629 `byz-planner-nano-cfo-issues-triage#0`: planner env 를 source 하고 `FT_NANO_PREFIX=byz-planner-nano-` · `--result design/planner/TRIAGE-cfo-issues-20261007.md --recv 58621 --kill`(유휴 3분 필요). embeddinggemma2 나노는 진행 중 — 닫기 보류.
3. **C 축 순서(arch 안)**: ②채택 PR 랜딩 → RELEASE 0.4 1장(오늘 변경표: 이름규칙·governance 6·7·arch 상시·게이트 master·Tank 래퍼+가드·ft-role-spawn·tmm 0.7.4 등 + 설치 명령 + 머신 표) → 이 Mac 반영(install --apply → FT_BIN 전환 → 홈 훅 설치 → 사용 경로 cmp 0 → 「반영됨 이 Mac <kit_sha>」) → 슬랙 게시(mbox→Slack 미러로 #byz-planner · 새 데몬 0 · ts 를 반영 행에) → byzs-mac-mini 같은 절차(ssh). 홈 settings.json 훅 등록은 키트가 편집하지 않고 머신마다 master 집행(백업+블록 추가).
4. **② 랜딩 뒤 후속 카드 3(arch 승인)**: ①ft-role-spawn 기본 접두 byz-팀 + 번호 계산 byz-·ft- 두 계보 합산 ②ft-nano-spawn 에이전트 codex 인데 모델 미지정이면 claude 모델이 들어감 → gpt 기본 ③ft-nano-spawn `--base` 인자 + close 가 worktree-info base 읽기. (v65 총괄 #143 보고. 임시 우회 안내함: FT_ROLE_BASE_PREFIX=byz-v65- · codex 나노는 --model 명시.)
5. 래퍼 확장 요청 원장 R6②(PR 쓰기 5종 훅 미차단) · R7(milestone) · 게이트 사본 3개(홈·프로젝트·키트) 정합 · 프로젝트 게이트 훅은 각 워크트리가 main 을 병합해야 효과(v65 에 안내 필요).
6. block-destructive 추적본 0 + 오탐 처리 메시지 → kit-hooks 카드가 추적본까지. 홈 가드 훅은 이미 PR 843 판으로 교체됨(백업 .bak-1007-pre-scope).
7. 옛 이름 세션 ~15개(ft-harness-ops#5/#6 · ft-harness-arch#3/#4 · byz-planner-arch#3 등) 정리는 오빠 판단 — 하네스는 kill 하지 않는다. 구 `byz-harness-master-claude#7` 종료도 오빠 판단.
8. 요청 오는 대로: Tank 대행(issues#1) · 요청 원장 등록 · planner [HIL] 값 집행.

## 함정 (실측)
- 쪽지는 «현역 이름»으로: `ft-harness-info.sh seats`. planner 는 `#5`(명부 `_master`·`_hil_route` 이미 갱신, 백업 .bak-planner5-1007).
- `ft-nano-spawn.sh`·`ft-nano-close.sh` 는 라이브 FT_BIN(v6-realtime-live/.fable-team/bin)을 쓴다 — 추적본(scripts/fable-team-bin)은 뒤처짐. 호출은 harness-env.sh 를 source 한 스크립트 파일로(`bash -c "source …"` 합성은 승인 창에 걸림). 나노 닫기 헬퍼: source `.fable-team/bin-harness/harness-env.sh` → `FT_NANO_FEAT=<로컬 브랜치>` → `bash $FT_BIN/ft-nano-close.sh <좌석> --result <판정문> --recv <seq> --kill [--cherry-override "<사유>"]`. spawn 헬퍼도 같은 꼴.
- force push 는 HIL — 충돌 땐 rebase 대신 origin/main 병합. 브랜치 삭제 HIL(`git branch -D` 훅 차단) — 임시 브랜치(tmp-rebased-841 · feat/gh-as-tank-pr-create 등)는 남겨 둔다.
- 훅이 `git add -A` 차단 → 경로 지정. `gh pr merge` 는 필수 검사가 없어 CI 중에도 합쳐진다 → CI 확인 뒤. `unset GH_TOKEN`. 병합은 `--squash`(브랜치 삭제 옵션 없이).
- mbox 본문에 백틱 금지 · 같은 본문 fan-out 금지 · 긴 본문은 Write 도구로 파일 → relay.
- 문서 전용 나노의 증거 줄: `- 세트: <나노 HEAD 40-hex> · 시험: 없음(문서) — <이유에 가운뎃점 금지> · 이슈: 0`. 코드 카드: `… · 시험: <명령> rc=0 · 이슈: 0`.
- `ft-index-move.sh <카드> 완성 --da <판정문#§N>` 이 판정문 절에 「닫힘」 필요. 명부 `seats-harness.json` 의 나노 행 `index` 가 카드 이동을 따라가야 닫힌다(gitignore 운영 파일 — 직접 sed, 백업).
- 이 인계 커밋(카드 2장·초안 2건·원장 줄 포함)은 로컬 `ops/main-base` 위에 올라가 있고 원격 `docs/harness-handoff-7to8` 로 push 했다 — PR 은 후계가 `pr-create`(base main · head docs/harness-handoff-7to8)로 연다. 나노 spawn 은 이 브랜치에서 호출하면 카드가 보인다.
- 미커밋·미완 브랜치: 로컬 `ops/main-base`(= origin/main + 이 인계 커밋) · `feat/gh-as-tank`(PR 841 병합됨 · 로컬 잔존) · `feat/orch-gate-master`(PR 843 병합됨).

## 환경
- 워크트리 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops` · 좌석: byz-harness-arch-claude#5(arch 상시) · byz-planner-master-claude#5(planner·HIL) · byz-issues-master-claude#1 · byz-cfo-master-claude#53 · byz-v65-master-claude#143(+arch #166 fable) · 나노 위 2건.
- 판정서 `design/harness/OPS-VERDICTS-20261006.md` §1~§23 닫힘 · 요청 원장 `REQUEST-LEDGER.md` R1~R7 · RELEASE 0.1~0.3(0.4 작성 예정).
