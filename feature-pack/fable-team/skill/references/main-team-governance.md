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
