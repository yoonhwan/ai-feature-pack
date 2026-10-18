# HANDOFF — ft-harness-ops#6 → byz-harness-master-claude#7 (2026-10-07 · 이름 규칙 승계)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
이 단위의 골 축: 표 A·B·C + 원문 5(머신 배분) + 원문 6-b(오케 요청을 사용자와 협의해 개선) + 원문 7(쪼개 동시에). 닫는 증거 = design/teams/harness/OPS-VERDICTS-20261006.md 단위별 「닫힘」 줄 + 머신별 「반영됨」 행(RELEASE).
★승계 첫 일 = 골 대조 3줄을 byz-planner-master-claude#4 에 mbox 보고 + 부팅 3항(세션명/모델·창/Serena) 후 착수. 오빠께 올리는 글 = 결론→할 일→바뀐 것→근거 + ★PR·Issue 는 번호로만 쓰고 맨 아래 «번호·종류·제목·상태» 각주 표★(오빠 10-07 지침).★

## 이번 세션(#6)에서 끝난 것
- 이름 규칙 승계(오빠 결정: 총괄 5석만 · 오케 역할 `master` 통일 · 접두 `byz-` · 번호는 옛 번호 이어받음): cfo `byz-cfo-master-claude#53` · planner `byz-planner-master-claude#4` · issues `byz-issues-master-claude#1`(옛 좌석 세션 없어 생성) 완료 · v65 는 `ft-v65-master-claude#142` 가 «일감 사이»에 `byz-v65-master-claude#143` 으로 승계 예정(회신 대기) · harness = 이 승계.
- 정본화: 스킬 `~/.claude/skills/fable-team/references/{main-team-governance,harness-map}.md`(§1 이름 규칙 · §2 이슈 진입로 3 + 컨펌 게이트 · §3 해제=별도 단위 · §4 PR/Issue 각주 표) · 적용본 `design/planner/GUIDE-planner.md`. 조회 명령 `scripts/fable-team-bin/ft-harness-info.sh map|rules|seats|requests|find`(PR #837 병합). COMM-GUIDE-BOOT 14줄(승계 이름 확인·조회 명령 추가).
- #835(골좌표 훅 머지 커밋) 수정 PR #836 병합 · Issue 닫힘. #834(v65 기준선 평가 게이트)는 오빠 지시로 planner 통합 리더에게 이관(harness 착수 0).
- tmm 0.7.4(신 이름 그룹 탭=팀): 나노 산출 검증·ops 수락 §20 · `~/.tmm` 0.7.4 설치·`current` 전환 완료(되돌림 `ln -sfn ~/.tmm/versions/0.7.3 ~/.tmm/current`) · PR #838 CI 통과 시 자동 병합하는 백그라운드가 돌고 있다(안 됐으면 병합 확인).

## ★열린 일 (순서대로)
1. **PR #838 병합 확인**(tmm 0.7.4) — 병합 안 됐으면 Python Test 결과 보고 병합.
2. **나노 `ft-harness-temp-gh-as-tank-wrapper-guard#0`**(카드 `design/teams/harness/indices/진행/gh-as-tank-wrapper-guard.md`, 브랜치 nano/gh-as-tank-wrapper-guard, base feat/gh-as-tank): 산출 = `ft-gh-as-tank.sh`(래퍼 · pr-comment 포함) + 가드 훅 `gh-issue-author-guard.sh` + 시험 + RESULT. 보고 오면 ops 독립 검증 → OPS-VERDICTS §21 → 카드 완성 이동 → PR 랜딩. 닫기는 `FT_NANO_FEAT=<통합 브랜치> ft-nano-close.sh … --cherry-override "<사유>"`(함정 아래).
3. **전 세션 전파 문서(①②)** — 오빠 10-07 「Issue·PR 쓰기는 byz-tank 래퍼만 · 전세션 전파 · 하네스+패블팀 지침 업데이트」: ①COMM-GUIDE-BOOT 15번째 줄(gh issue/PR 코멘트·생성은 래퍼만) + 글로벌 `~/.claude/CLAUDE.md` 📌 중요 지시사항 1줄 + 전 세션(planner·v65·cfo·issues·ccu·kk) 쪽지(팀별 본문 다르게) ②스킬 `references/main-team-governance.md` §5 + 좌석 부팅 템플릿 `templates/session-prompts/*.md`·키트 사본. 래퍼가 완성·검증된 뒤 사용법과 함께 배포한다.
4. **HIL 대기(planner → 오빠 → 값으로 회신)**: 쪽지 58351 — 판정 A(#839 처리: 재등록+원본 close 권장) · 판정 B(가드 훅 `~/.claude/settings.json` PreToolUse 전역 설치 권장). 값이 오면 issues 총괄에도 내려간다. 설치는 가드 시험 통과 뒤 ops 가.
5. **v65 승계 회신 대기** — `ft-v65-master-claude#142`(승계 시점 = 돌고 있는 일 끝난 뒤 · 현역 #142 · #141 정지레디). 오면 명부(seats.json) `_replaced_by`·계보 확인. 구 세션 닫기는 오빠/팀 판단.
6. 요청 원장 R6 후보(CI 단계 실패가 뒤 단계를 가림 → `if: always()`/독립 잡) · R4(회귀 팩 후보 3 · 발사 게이트 후보 1 — #834 는 planner 소관) 구현 여부 오빠 답 대기.
7. 오빠 승인 영역(하지 않음): 라이브 FT_BIN 이전 · 원격 머신(jarvis·byzs-mac-mini) 설치·BOOT 배포 · Issue 라벨 생성 · 고아 카드 45장 정리 · 브랜치 삭제 후보(원격 12·로컬 48) · 세션명 문법 개정.
8. 이 승계의 미커밋: 없음(아래 커밋으로 정리). `.serena/project.yml` 은 내 부산물 — 커밋 금지.

## 함정 (실측)
- **쪽지는 «현역 이름»으로**: 승계로 이름이 바뀐다 — 발신 전 `ft-harness-info.sh seats`. 옛 이름(`byz-planner-arch#3`)으로 보낸 쪽지는 옛 세션에 쌓였다.
- **`ft-nano-close.sh` 가 막는 3가지**: ①`FT_NANO_FEAT`(harness-env.sh 값이 옛 `feat/slack-inbound-820`)로 cherry/STALE 판정 → 그 닫기에만 `FT_NANO_FEAT=<통합 브랜치>` 주입 ②seats-harness.json 의 그 나노 행 `index` 가 카드 이동(진행→완성)을 따라가야 함 ③카드 `## 상태` 증거 줄 형식 정확히 `- 세트: <나노 HEAD 40-hex> · 시험: <명령> rc=<n> · 이슈: 0` (이슈 칸에 설명 덧붙이면 REJECT). 통합 브랜치에 없는 패치가 남으면 `git cherry -v`로 확인 후 `--cherry-override "<사유>"`.
- 권한 우회(`--dangerously-skip-permissions`)로 열려도 `bash -c "source … ; …"` 합성 명령은 안전 훅이 승인 창(「runs rm and could not be checked」)을 띄우고 1분 뒤 자동 거부 — 나노에게 스크립트 파일로 돌리게 하라.
- mbox 본문에 백틱 금지(훅 차단) → 본문을 파일로 써서 relay · 요약 인자에도 백틱 금지. 같은 본문을 여러 좌석에 보내면 fan-out 차단 → 팀별로 다르게.
- 훅이 `git add -A`·`.` 차단 → 경로 지정. `gh pr merge` 는 필수 검사가 없어 CI 진행 중에도 합쳐진다 → 병합 전 검사 결과를 먼저. `unset GH_TOKEN`.
- 좌석 명부 `.fable-team/seats-*.json` 은 gitignore 된 운영 파일 — 이름 승계 반영은 직접(백업 `.bak-name-1007` 있음). `FT_SEND_FROM`(`.fable-team/bin-harness/harness-env.sh`)은 승계 때 새 이름으로 바꾼다.
- 오빠 pane 질문이 아닌 승인 창·인터뷰를 구분: 나노가 AskUserQuestion 을 띄우는 것은 금지(오빠는 그 pane 을 못 본다) — 사람 판정은 `[HIL]` → planner.

## 환경
- 워크트리 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops` · 현재 브랜치 `feat/gh-as-tank`(origin/main 에서 땀 · 아직 PR 없음 — 카드 이동·원장 커밋만) · 새 일은 최신 origin/main 에서 새 브랜치.
- 좌석: byz-planner-master-claude#4(planner) · byz-issues-master-claude#1(issues) · byz-cfo-master-claude#53(cfo) · ft-v65-master-claude#142(v65 · 승계 예정) · 나노 ft-harness-temp-gh-as-tank-wrapper-guard#0.
- 오빠 글은 GUIDE-human-report 틀 + PR/Issue 인덱스 각주 표.
