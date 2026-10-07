# 메인 팀 운영 정본 — 좌석 이름 규칙 + 이슈 진입로 3 + 컨펌 게이트 (fable-team 정본 · 오빠 2026-10-07)

> 이 파일이 정본이다. 프로젝트 쪽(`design/planner/GUIDE-planner.md` 등)은 «이 정본의 적용본» — 어긋나면 이 파일이 이긴다.
> 바꾸려면 오빠 값 1회(이 파일 머리에 날짜·판정 줄 추가). 자율 확대(컨펌 해제)는 §3 — harness 단위로만.
> 출처 원문: 오빠 10-07 「planner, harness, issue, v65, cfo 기동 이름 규칙부터 맞춰 …」 · 「이슈 자율 루프는 돌되 자동 승인 진행 하지는 말고 …」 · 「정본하는게 fable-team이잖아? 우리 개선하는게」

## 1. 좌석 이름 규칙 (P6 · 프로젝트 `design/harness/issue-improvement/SPEC-session-naming-20261005.md` §2 사본)
- 문법 `<프로젝트>-<팀>-<역할>[-<꼬리>]#<N>` · 역할 예약어 10 = master arch da tester checker analyst pm nano repro tool · 역할 좌석 꼬리 = 에이전트(claude|codex|opencode|cmd) 필수 · nano 꼬리 = 카드 slug · 소문자·숫자·`-` 만 · 길이 ≤ 60. 검사 = `ft-name-lint.sh <이름>`.
- **메인 팀 총괄(오케) 역할명은 전 팀 `master` 로 통일**(오빠 10-07 «master 가 메인오케다»): `byz-v65-master-claude` · `byz-cfo-master-claude` · `byz-planner-master-claude` · `byz-harness-master-claude` · `byz-issues-master-claude`(팀 글자 = 명부 파일명 `seats-<팀>.json` 과 같게).
- `#N` = 승계마다 +1 이며 **옛 이름의 번호를 이어받는다**(예 `ft-v65-master-claude#142` → `byz-v65-master-claude#143`). 승계 때 자연 교체 — 살아 있는 세션을 rename·kill 하지 않는다(구 세션 닫기는 오빠/팀 판단).
- 이 이름 규칙은 SKILL.md 의 구 규약 `ft-<slug>-<role>#0` 를 **신규 좌석부터 대체**한다.

## 2. 이슈 진입로 3 + 컨펌 게이트 (현재 유효)
역할: **planner** = 메인 PM(오빠와 직접 대화·AskUserQuestion 은 planner 만) · **issue-master** = 이슈 모니터·생성·종료·배분 총괄(하위 좌석 — 인터뷰 금지).
- issue-master 가 **스스로 하는 것**: 모니터 · 읽기 · 분류/우선순위 «안» · LOOP-LEDGER · 재현 스텝 조사. **오빠 컨펌 뒤에만**: 배분 · 착수 · 라벨 부착/변경 · 채택/배분 코멘트 · 닫기.

| 진입로 | 흐름 | 컨펌 |
|---|---|---|
| ① 밀어올리기 | issue-master 가 `[HIL]` 묶음 1통(이슈 내용 3줄 · 권장 우선순위·이유 · 진행 방식 · 선택지) → planner 가 AskUserQuestion 으로 설명·컨펌 → 값 회신 | 오빠 인터뷰 필수 |
| ② 당겨오기 | 오빠가 planner 에 「이 이슈 처리해」·「중요도 제일 높은 이슈 찾아와」 → planner 가 issue-master 에 요청 → 회신(내용 3줄·중요도 근거·재현 스텝 유무·권장 배분) → 다시 인터뷰로 설명·컨펌. 중요도 기준 미확정이면 issue-master 가 «기준 안»을 함께 보내 오빠가 고른다 | 오빠 인터뷰 필수 |
| ③ 신규 기획·피쳐 | 오빠와 논의해 정함 → planner 가 쪽지에 「오빠와 논의 끝남」을 적어 issue-master 에 **이슈 등록** 요청 → **구현 배정은 planner 가 직접**(issue-master 는 배분 코멘트 기록만) | 논의 자체가 컨펌 |
- 「논의 끝남」 표시 없는 건은 ③이 아니다 → ①·② 로 컨펌 전 착수 0. 컨펌 값이 오기 전 issue-master 는 다음 «안» 작성만(루프는 돌고 착수만 멈춘다).
- 컨펌 경로는 반드시 planner(사용자 인터뷰) — 하위 좌석은 사용자 pane 을 못 본다.

## 3. 게이트 해제 = 별도 단위
이름 정리·이 게이트가 전부 랜딩된 뒤의 «자율 확대(컨펌 해제 범위)»는 harness(ops) 가 별도 단위로 진행한다(오빠 10-07 「완전히 랜딩되면 그후 자율은 따로 harness에서 추가 진행」). 그 전에 planner·issue-master 가 스스로 풀거나 넓히지 않는다.

## 4. 오빠께 올리는 글에서 PR·Issue 표기 (오빠 2026-10-07 지침)
PR·Issue 는 본문에서 번호 인덱스(`#836`)로만 부르고, 글 맨 아래에 **인덱스 각주 표**(번호 · 종류 · 제목 한 줄 · 상태)를 항상 붙인다. 본문에 쓴 번호는 전부 표에 있어야 한다. 세션끼리 주고받는 mbox 는 예외.

## 6. 하네스 기획 arch 상시 좌석 (오빠 2026-10-07 「작업들 arch 검토 받고 결정 진행. 독단으로 하지 말고」 · arch 안 byz-harness-arch-claude#5)
- 좌석: `byz-harness-arch-claude#N` · 모델 Opus 5.5 high 상시 · Fable 5.1 은 에스컬레이션(같은 건 2회 수렴 실패·신규 구조 설계)만, 닫히면 Opus 5.5 로 복귀.
- 역할: arch = 설계·검토·판정 «안» · master = 집행(커밋·push·설치·좌석 개설/닫기·명부). arch 는 커밋·push·설치·좌석 조작을 하지 않는다(설계 초안 파일 Write 만, 커밋은 master).
- arch 검토 대상(안 없이 집행 0): ①설계·새 스크립트/훅 기능 ②가드·차단 훅(설치·등록 포함) ③설치·배포(홈 디렉터리·settings.json·~/.tmm·원격 머신) ④정본 변경(governance·COMM-GUIDE·BOOT·스킬 SKILL.md·전역/프로젝트 CLAUDE.md) ⑤좌석·모델·이름 규칙 변경 ⑥PR 랜딩 순서·되돌림.
- master 직접(검토 불요): 조회(seats·map·gh view) · 문서 오타 · 원장 행 추가(결정 없는 기록) · 나노 생존 확인 · «집행».
- ★«집행» 정의(arch#5 판정 10-07)★: 랜딩·커밋·push·검증된 파일의 설치 복사(cp+cmp)·.bak 복원·머지 충돌의 문서 줄 순서 정리·좌석 개설/닫기·명부·원장 기록. ★파일 «내용을 쓰는 것»은 집행이 아니다★ — 코드·스크립트·훅·시험 = 나노, 시안·설계 = arch. 나노 증거 줄 REJECT = 그 나노에 반송(닫힌 나노면 재spawn). arch 안이 있어도 master 가 «손으로» 쓰지 않고, 안 없이 집행하지도 않는다(오빠 「독단 금지」 둘 다). 전역 「한 턴 코드 2파일」 은 팀 좌석 없는 단독 세션용이고 팀 master 는 0.
- 흐름: master 발주(mbox · 골 원문 3줄 + 골 축 1줄) → arch 안(결론 1줄 · 승인/수정/반려 · 이유 3줄 · 근거 경로 · 긴 것은 design/harness/ 초안 파일) → master 집행 → master 가 결과(sha·설치 위치·되돌림 명령)를 arch 에 통지 → arch 닫힘 확인 1줄.
- 사후 검토: 긴급(라이브 장애·권한 사고)으로 master 가 먼저 집행했으면 같은 턴에 arch 에 사후 검토 발주 + 되돌림 명령을 함께 적는다.
- 오빠 값을 arch/master 판단으로 뒤집지 않는다 — 다르게 가자는 안은 §7 경로(planner [HIL])로 값을 다시 받는다.
- 나노 접두 = 팀 env 파일의 `FT_NANO_PREFIX`(`byz-<팀>-nano-`) — spawn·close·카드 키가 같은 값을 쓴다. 옛 이름(`ft-<팀>-temp-`) 나노가 살아 있으면 그 한 건만 명령 앞에 접두를 주입한다.

## 7. 차단·사용자 실행 필요 명령은 planner 로 (오빠 2026-10-07 「hil 이나 rm 모든 차단은 나에게 명령을 전달하고 인터뷰 걸어서 알리는걸 지침화」 · 「대부분 사용자 실행 필요 명령은 플래너 총괄로 보내서 수행요청하고 인터뷰를 플래너에 걸자」)
- 훅(block-destructive·gh-issue-author-guard 등)이나 승인 창이 명령을 막으면 ★우회하지 않는다★ — 명령 분해·경로 바꿔 같은 효과 내기·다른 도구로 대체·재시도 반복 금지.
- 막힌 그 턴에 현역 planner 에 mbox `[HIL]` 로 올린다. 쪽지에 반드시: ①막힌 명령 «원문 그대로» ②막은 훅·사유 한 줄 ③무엇이 지워지거나 바뀌는지 + 되돌림 가능 여부 ④선택지(승인해서 내가 실행 / 오빠가 `!` 로 직접 실행 / 하지 않고 대안). planner 가 AskUserQuestion 으로 오빠께 묻고 값으로 회신한다. 승인은 «그 한 건»에만 — 같은 종류의 다음 명령은 다시 올린다.
- planner 가 없는 세션(개인 리포 등)은 그 세션이 직접 AskUserQuestion. 오빠가 이 pane 에서 직접 값을 주는 중이면 그 자리에서 받아도 된다.
- 경계 — 기준은 주제가 아니라 «누가 손을 대야 하나»: ⓐ좌석이 «막힘 없이» 할 수 있는 하네스 작업(스크립트·훅·설치·홈 settings.json 을 Write/Edit 로 바꾸기)은 master+arch 가 결정·집행(planner 0) ⓑplanner [HIL] = 훅·승인 창이 막은 명령(내용 무관) · 오빠 손이 필요한 것(`!` 실행·1Password·토큰 재발급·GitHub org 설정·권한 변경·원격 머신 접속) · 오빠가 준 값과 다르게 가자는 안. 예: settings.json 수정 = ⓐ, 그 수정이 rm·kill 을 포함해 훅에 막히면 그 순간 ⓑ.
- 면제(안 막히는 정상 경로): 이 세션이 띄운 백그라운드 작업은 TaskStop/Monitor 정지가 정상 경로 — 대체 우회 아님 · tmux kill-session · nano-close 경로의 표준승인.
- 하위 좌석(워커·나노·tester·checker·arch)은 AskUserQuestion 금지 — 같은 `[HIL]` 을 master 경유 또는 직접 planner 에 올린다.
- 오탐(명령이 아닌 본문·grep 패턴에 글자만 들어가 훅이 막은 경우 · 실제 파괴 동작 없음) = ★파일 기록 + 실행 허용 + 묶음 알림★(오빠 값 10-07 planner 인터뷰): 명령을 파일에 써서 실행하고, 원문·사유를 한 줄씩 `.fable-team/state/hil-falsepos.log` 에 남기고, 묶음으로 planner 에 알린다. ★진짜 파괴(rm·kill·force push·DB/인프라 삭제)만 사람에게 올린다★. 오탐인지 애매하면 진짜로 취급해 올린다.
