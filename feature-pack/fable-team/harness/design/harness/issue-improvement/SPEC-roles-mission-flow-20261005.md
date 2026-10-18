# SPEC — planner·issue-manager 역할 · 병렬 발주 · 나노 병렬 처리 · 미션 클리어 (r4 · ft-harness-arch#1 · 2026-10-05 · 조각 P3)

> MERGED 반영 r+1 (C11 · 2026-10-06): §2-B P2-3 = 허가 2종(충돌 ⑪ · P9 3-B) · §3-B P3-3 = press 는 시험 묶음 tester 만 · 보고 수신 architect(충돌 ⑤) · §1-C 소유 줄 = P2 표 1 반영 완료 표기(충돌 ①②). 슬롯 5(충돌 ⑥) 스크립트 정정은 C6 · 위 표의 P3-5 는 이미 5.

> **건드리는 정본**: planner GUIDE 8항 4·5(운영 대조) · issue-manager PROPOSAL §2(배분·완료 5항) · `ft-nano-slots.sh`(상한·점유 판정 · 후보 선택) · `ft-nano-spawn/close.sh`(카드 수락·정리 상태) · 팀 `indices/` 카드 머리줄. **코드 변경 0 — 설계만(PIECES 규칙 4).**
> **전제 조각**: P2 `SPEC-main-orch-tree-20261005.md`(37e19724b5 · 오빠 ↔ planner ↔ {v65·cfo·harness-ops 메인 · ccu·kk 위성} 동등 · issue-manager = planner 의 Issue 도구). P1 `DESIGN-harness-composition-20261005.md`(e184bc1f57) §3-2·§3-3 의 Issue 소유 규칙은 «고정 정본»으로 받는다.
>
> 골 원문(GOAL-harness.md 복붙):
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
>
> 골의 축: 표 A(모니터) 둘째 단위 「각 오케가 일을 어떻게 받고 병렬로 처리·클리어하는지」. 닫는 증거 = DA APPROVE + 오빠 「맞다」.
> 발주 = ops#2 `ORDER-roles-mission-flow-20261005.md`(eb5ca07b0e) · 조각 전략 = `PIECES.md`(#56972). 실측 14:46 KST(nano#1 `facts-raw/R*.txt` + arch 직접). [사실]/[제안]/[추측] 표기.
> ★planner 정본의 현행 사본은 `.worktrees/v6-realtime-live/design/planner/`(BOARD r42 5aa17f1430 · GUIDE 9bb929ae5f) — harness-ops 워크트리 사본은 10-04 09:23 판으로 한 판 뒤처짐★.
> 오빠 확정(#56970 「우리 방법대로 간다」): 구현자 자체 검증 생략 항은 넣지 않는다 — 현행(구현자 push 전 검증 + tester/DA lane) 유지.
> r3→r4(오빠 값 #57012 · VALUES-pieces-P3-P5): Q1~Q5 전부 추천안 확정 · P3-1b 「빈 석 채우기 = 메인 오케 핵심 책임」 추가.
> r1→r2: DA r1(`DA-roles-mission-r1.md` HOLD 5) 전부 반영 — ①슬롯 점유 = 코드 실측대로(주석과 불일치 = 결함 표기) ②보류/재개 상태 명시 + 활성 Issue 카드만 채움 ③press 석 = 나노 밖(tester/오케) + 공유 허가 1개의 획득·해제·중단 ④워커 닫힘·카드 수락·정리 상태 3분리 + 기록 간 ack ⑤랜딩 = tip 과 랜딩 sha 둘 기록 · squash 는 cherry/원장 증거. + ops #56972 머리 2줄 · §1-C 충돌 후보 2 대조.

## 1. planner · issue-manager 세부 수행 역할

### 1-A. 지금 [사실]
| | planner (`byz-planner-arch#3` · fable-5-1) | issue-manager (`ft-issue-manager#0` · sonnet-5-5) |
|---|---|---|
| 입력 | 오빠 지시 · 오케 «경로+sha+남은 일» 3줄 · 위성 «랜딩 요청/종료 요청/막힘» · `[HIL]`(seats-harness·seats-issues `_hil_route`) | GitHub Issue(정본) · 슬랙 접수 · CI 실패 · 라이브 경보 · planner 분류 값 5줄 |
| 하는 일 | 접수→분류(⓪→①~④)→**분류 값 1통 = 1 Issue → issue-manager**→운영(좌석·카드·보고 3자 대조)→베이스↔위성 연결·정리→메인 팀 추가 제안 (GUIDE 8항 1~4) | 모니터→생성·등록(라벨 6+마일스톤 · 비면 반려)→우선순위(①라이브 ②완성 전 골 축 ③완성 전 골 밖 ④완성 후)→**배분 1건(메인 오케 mbox 1통 + Issue 코멘트 1줄)**→진행 감시(10분·2 HOLD 상위화)→close 뒤 완료 5항 «대조»→LOOP-LEDGER 색인→다음 (PROPOSAL §2 · P1 §3-2) |
| 출력(정본) | `design/planner/BOARD.md`(배정·상태 인덱스 · r42) · STRUCTURE · GUIDE · PROPOSAL-team-<x> | Issue 코멘트(「배분 → <오케>」 · 5항 대조 결과) · `design/issues/LOOP-LEDGER.md`(12행) · 하위 `repro-e2e#0`(main HEAD 재현 · 코드 수정 0) |
| 하지 않는 일 | 코드·press·좌석 개설·타 경로 커밋/push · ★발주(10-04 16:2x 정정 「planner 는 발주하지 않는다」)★ · 하위 좌석 직접 송신 · AskUserQuestion(오빠가 pane 에 없을 때) | 규칙·예외 결정(골 밖·HIL·팀 추가 = planner) · 두 건 동시 진행 · 닫는 사건 없는 close · 점수·게이트·면제 목록 · **메인 배분 Issue 의 수정·랜딩·close 집행**(P1 오빠 Q1) |
| 실측 통신 | 발신 55건(10-04 16:40~10-05 12:29): →issue-manager 15 · →harness-ops 21 · →v65 9 · →ccu 6 · 수신 71 · 로그 전체 `[HIL]` 20 (R2) | LOOP-LEDGER 12행 · indices 대기 0 · 진행 0 · 완성 3 (`.worktrees/issue-manager`) |

경계 한 줄: **planner = 「어느 팀·어느 골 축·완성 전/후」를 정하는 거시 1통 / issue-manager = 그 값으로 Issue 1건을 열고→배분→감시→close 대조하는 루프.** 예외(GUIDE 4) = 위성 창 GO·[HIL] 하달 같은 «판정 값»만 planner 가 오케에 직접 1통.

### 1-B. 제안 [제안]
- P1-1 **planner 출력에 「운영 대조표」 1장 추가** — 매 수신 턴 BOARD 와 함께 ⟨팀 · 진행 카드 수 · 살아 있는 하위 좌석 수 · 어긋남⟩ 한 줄씩. 지금 BOARD 는 배정·상태만이고 §3 실측(v65 진행 28 vs 나노 2)을 아무 정본도 안 보여 준다.
- P1-2 **배분 = 쌍**: Issue 코멘트 1줄 + 메인 오케 mbox 5줄. 둘 중 하나만 있으면 «미배분». 수신자는 영역 오케 1좌석(나노·arch 직접 금지 = planner 와 같다).

### 1-C. 충돌 후보 2 대조 (PIECES 맨 아래 · 사실 → 해소안)
| 후보 | P1 §3-2 (오빠 Q1 값 · 고정) | P2 표 1 · GOAL-issues 원문 | 사실 대조 | 해소안 [제안] |
|---|---|---|---|---|
| issue-manager 의 일 | 등록 검사·라벨 전이·배분 1건·close 뒤 5항 «대조»·색인 — 해결·close = 메인 오케 | 「정의된 Issue 단위 폴링·**수정·테스트·랜딩**·클린업」 · 원문 「작은 이슈나 테스트 ci 수정등은 **매니저 하위로 위성**으로 진행」 | PROPOSAL §2 배분 원칙 = 「size:small(테스트·CI·문서·1파일)은 매니저 하위 위성 — 나노 1장을 자기 명부에 열고 PR → 랜딩 → 닫기」. LOOP-LEDGER 행 2(#745)는 「배분 없음 · 종료 검사만」 — 매니저가 수정한 실례는 아직 0 [사실] | **두 경로이지 모순이 아니다.** ⓐ 메인 배분 Issue(`team:v65/cfo/harness-ops/위성`) → 수정·랜딩·close = 그 오케 · 매니저 = 배분·대조·색인. ⓑ `size:small` Issue(`team:issue-manager`) → 매니저가 **메인 오케 역할을 겸해** 하위 나노 1장으로 수정·테스트·랜딩·클린업. P2 의 「수정·테스트·랜딩」은 ⓑ 경로를 적은 것으로 읽는다. 재현 e2e(`repro-e2e#0`)는 두 경로 모두 «재현·PASS 코멘트»만(수정 0). |
| Issue # 소유 | 메인 오케 1 | 매니저가 직접 랜딩하면 소유 둘 | 소유 표시 = `team:<x>` 라벨 1개 + 「소유 오케=<세션명>」 코멘트(P1 §3-1) [사실] | **Issue 1건 = `team:` 라벨 1개 = 소유 오케 1.** ⓑ 경로에서만 `team:issue-manager` 가 소유자이며 그때도 1이다. 매니저가 메인 Issue 를 대신 랜딩하는 경로는 두지 않는다. 합칠 때 P2 표 1 「issue-manager」 행 역할 문구에 「(size:small 한정)」 4자를 붙이면 끝 — 합칠 때까지 안 고친다(PIECES 규칙 6) → **MERGED 반영 r+1 에서 P2 표 1 에 반영됨**(§1-C 본문은 그대로 · 충돌 ②). |

## 2. planner → 메인팀 병렬 발주 관리

### 2-A. 지금 [사실]
- 발주 단위 = **Issue 1건**(issue-manager 경유) · planner 직접 1통은 판정 값만. 팀당 동시 = PROPOSAL §2 「★동시 열린 «진행» = 메인 하네스당 1★」.
- 상태 추적 = BOARD 행(수신 이벤트만 갱신 · 타이머 0 · GUIDE I1) + LOOP-LEDGER 행 + Issue 보드(BYZ Board projects/7).
- 자원 충돌: 오디오 press(BlackHole 1대)·GPU·공유 vLLM 은 **v65 master 가 순번**(STRUCTURE §1-3 보조규칙 · ccu 는 mbox 로 요청) · 포트 38301~38399 슬롯.
- 회수 = 오케 3줄(경로·sha·남은 일) → 같은 턴 BOARD 갱신. 2 HOLD·10분 초과·좌석 사망 = 상위화.
- [추측] R2 「같은 to 연속 send 48쌍」은 ring 아닌 겹침 후보 — 다건 발주를 쪼갠 정상 송신이 대부분으로 보이나 분리 집계가 없다.

### 2-B. 제안 [제안]
| 항 | 값 | 왜 |
|---|---|---|
| P2-1 활성 미션 | **메인 팀당 활성 Issue 1 · 대기 큐 N** — 두 번째 Issue 는 첫 Issue 의 «클리어»(§4 ①~⑤) 뒤에만 출범. **예외 1 = ①라이브 깨짐**: 활성 Issue 를 «보류»(P4-2)로 두고 라이브 Issue 가 «라이브 예약석»으로 들어온다 — 이때 활성은 잠시 2(보류 1 + 라이브 1) | PROPOSAL §2 그대로 · 병렬은 «팀 간»에서만, «팀 안»은 §3 나노로 · 예외 없이는 P4-2 와 모순(DA r2 ①) |
| P2-2 발주문 5줄 + 자원 줄 1 | 「Issue # · 골좌표(정본 복붙) · 닫는 증거 · 완성 전/후 · 담당 오케」 + 「press/GPU/vLLM 필요: 예/아니오」 | 자원 줄이 없으면 허가자가 순번을 잡을 근거가 없다 |
| P2-3 **허가 2종**(세트 허가 + 오디오 장치 허가 · 머신당 1) — P9 3-B 로 확정: 세트 허가(멤버 참조 수 · 멤버 상한 1 로 시작 · 실측으로 올림) + 장치 허가 + 브라우저 리스(inject 완성 후 · 값만 예약) + 쿼터 pending · 「press」 = mic 입력 시험을 가리키는 말 | 허가자 = v65 master 1손. 상태 = `free / held(팀·좌석·Issue · since)`(아래 획득·해제·중단 문장은 장치 허가 기준으로 읽는다 · 세트 허가의 멤버 가입/탈퇴·해제 조건은 P9 3-B). **획득** = 요청 mbox → 「GO · 끝 예정」 회신 · **해제** = 보유 좌석의 「press 끝 · 결과 경로」 mbox(끝 예정 시각은 해제가 아니다) · **중단** = 보유 좌석 사망·10분 무보고 → 허가자가 `tmux`·러너 pid 로 «press 가 실제로 멈췄나» 확인 뒤 free 선언(복구 소유 = 허가자) · 기록 = 허가자 팀 파일 1줄(NEWS-TREE 옆) | 10-04 CCU 실측: 창 대여에 끝 시각만 있어 두 좌석이 대기(원장 #0) · 팀별 1석 규칙만으로는 장치 1대를 보호하지 못한다(DA r1 ③) |
| P2-4 회수 신호 2종만 | ⓐ 「랜딩 sha + 닫는 증거」 ⓑ 「막힘(HOLD 2 / 10분 / 좌석 사망)」 — 진행보고는 파일(NEWS-TREE) | mbox 는 결정 통로 · 진행은 파일(COMM-GUIDE §1.5) |
| P2-5 겹침 집계 | mbox.log 에서 「답 없는 같은 to 연속 2건」을 ring 과 분리해 센다(`ft-reach-check.sh` 옆 1줄) | 지금은 48쌍이 정상인지 겹침인지 못 가른다 |

## 3. 메인팀 하위 나노·세션 병렬 처리 관리

### 3-A. 지금 [사실]
| 기계 | 값 | 출처 |
|---|---|---|
| 상한 | `FT_NANO_SLOTS` 기본 **6**(`ft-nano-slots.sh:12`) · 「항상 채운다 · 닫는 같은 턴에 대기/ 카드로 spawn」(:3) | R3-slots |
| **점유 판정(코드)** | `working` = 명부 석 중 «IDLE ≥ `FT_NANO_IDLE_MIN`(10분)» 이 아닌 것(:64) · `empty = MAX − len(working)`(:66) → **10분 넘게 노는 석은 빈 석으로 센다.** 주석(:47 「노는 석도 슬롯을 먹는다」)과 **정반대 — 결함 또는 미결 선택** · 이 스크립트는 «표시»만 하고 물리 상한을 강제하지 않는다 | arch 직접(DA r1 ①) |
| 후보 선택(코드) | `대기/` **전체**를 스캔 · `SB-` 제외 · 「press 0/불요/없음·서버 0·시험만·읽기 전용」 표기 카드만 · 앞 `empty×2` 장(:73~82) — **Issue 경계 없음** | arch 직접(DA r1 ②) |
| 상한 판정 | 오빠 「★트랙별 5 기본★ · 조건 = 끝난 나노 정리가 잘 돼야 함」(VERDICT-arch151 :31) — 스크립트 6 과 불일치 | arch 직접 |
| spawn | `대기/` 카드만(`:43`) → lint → 워크트리+심링크+`.worktree-info.json` → `tmuxc open` → `@zc_v65_active=1` → seats 등록 → **카드 대기→진행** → 첫 발주 mbox → 도달 확인 jsonl (`ft-nano-spawn.sh:5~6`) | R3-spawn |
| close | `ft-nano-close.sh <좌석> --result <경로> --recv <seq>` · ①~⑥ 조건(⑤ = cherry 게이트 · 좌석 브랜치 «+» 커밋 0 · :306~314) 미충족 = REJECT · 통과 = 명부 삭제·원장 append·태그 해제·**kill**(:378~380) → **같은 호출 안에서 `_wt_clean_run`**(:382 · `FT_WT_AUTOCLEAN` 기본 1) · 계획이 skipped(좌석/cwd 보유)면 `planned` 로 남아 `ft-wt-sweep.sh`(tick) 가 재시도 · **카드 완성/ 이동은 close 가 하지 않는다** | arch 직접(DA r1 ④) |
| freshness | `ft-nano-freshness.sh <브랜치>` → FRESH / STALE / STALE-OVERLAP / 미랜딩 0 — 착수·시험·랜딩 «전» 필수(single_set_testing) · **squash 는 조상 관계를 안 만든다 → 미랜딩 판정은 랜딩 원장(cherry)으로**(`ft-nano-slots.sh:7`) | R3-freshness·R3-slots(DA r1 ⑤) |
| 직렬 규칙 | **나노는 press 금지** · press 는 최신 루트 병합 «뒤» 그 워크트리 세트로만 · BlackHole 1대 = 오디오 press 동시 1 · 서버는 동시, press 는 순차 | single_set_testing :25 · 글로벌 규칙 |
| 스크립트 위치 | 실체 = `.worktrees/v6-realtime-live/.fable-team/bin/ft-nano-*.sh` · `~/.claude/fable-team/bin/*` 는 심링크 · `scripts/fable-team-bin/` 에는 없음(추적본 ≠ 라이브) | R3-nano-locations |
| **실재 대조** | v65 `진행/` **28장** ↔ 살아 있는 v65 나노 **2**(`ft-v65-temp-m7-*`) → 카드명↔세션명 일치 **0** · cfo `진행/` **17장** ↔ cfo 하위 세션 **0**. 원인 일부 = 10-04 20:3x 오빠 「작업 모두 정지 레디」(BOARD r40 · 좌석 kill 0 · 카드는 진행/ 에 그대로) — 즉 «보류»인데 보류 표기가 없어 고아와 구분이 안 된다 | R4-v65-card-session · FACTS :91 · arch 직접 |

### 3-B. 제안 [제안]
| 항 | 값 | 왜 |
|---|---|---|
| P3-1 한 팀 안 병렬 = 「활성 Issue 의 카드」만 | 카드 머리줄에 `Issue: #N`(spawn lint 항목 1 추가 · 나노는 번호를 몰라도 됨 — 오케·카드 매핑) · `ft-nano-slots.sh` 후보 = `대기/` 중 **활성 Issue 의 카드만** · 다른 Issue 카드는 후보에서 제외 | 지금 후보 스캔은 대기/ 전체(3-A) → 「닫는 같은 턴 다음 카드」가 Issue 경계를 못 지킨다(DA r1 ②) |
| P3-1b ★**핵심 책임 — 빈 석은 메인 오케가 그 턴에 채운다**★(오빠 10-05 #57012) | 나노가 끝나거나(close) 노는 석이 되면(IDLE≥10분) **메인 오케가 같은 턴 활성 Issue 의 다음 대기/ 카드로 spawn** · 노는 석 0 이 상태 목표 · **채울 카드가 없으면 「쪼개기 부족」 신호** → 오케가 활성 Issue 를 더 쪼개거나(분해표 갱신) 그 사실을 planner 큐 행에 1줄 적는다 · 이 책임은 arch 지정을 기다리지 않는다(`ft-nano-slots.sh:3~4` 규칙 그대로) | 오빠 「나노가 끝나거나 비면 메인 오케가 다음 카드로 채워 돌리는 것 = 가장 중요한 일 중 하나」 · 10-02 실측 9석 중 3석 대기 · 10-03 승계 뒤 일하는 석 1/5(원장 #0) |
| P3-2 슬롯 = **살아 있는 나노 세션 수** | 점유 = 명부 석 전부(일하는 석 + 노는 석). 빈 석 = MAX − 살아 있는 석. 노는 석은 「빈 석」이 아니라 «푸는 대상»(막힌 것 해소 → 완성 → close) · 교체 = close(kill) 뒤에만 | :64~66 코드가 노는 석을 빈 석으로 세어 상한 초과 spawn 을 권한다(DA r1 ①) · 오빠 「나노가 또 놀고 있네」의 반대 방향 결함 |
| P3-3 press 석 = **나노 밖** | press(mic·api 모두) = 시험 묶음 tester 만(오케·나노 press 0 · 나노 press 금지 그대로 · 바꾸려면 사람 승인) · 시험 결과 보고 수신 = architect(master 에는 집행·사람 판정만 — P7 Q2 · P9 Q3) · 팀의 press 는 §2 P2-3 허가(세트 허가 → 장치 허가)를 획득한 뒤만 · press 허가는 나노 슬롯 점유와 **별개 상태** | 팀별 1석 규칙은 장치 1대를 보호하지 못하고 나노 press 금지와 충돌(DA r1 ③) |
| P3-4 진행 카드 = 세션 실재 또는 «보류» | `진행/` 카드는 살아 있는 나노와 1:1, 예외 1 = 머리줄 `상태: 보류(Issue #N · since)` 카드(§4 P4-2). 세션 없고 보류 표기도 없는 진행 카드 = 매 틱 «대기/ 복귀 후보»로 표시 → 오케가 같은 턴 복귀 | 실측 28:2 · 17:0 — 「좌석 없는 진행 카드 = 남은 일」(GUIDE 5)이 집행되지 않고 있다 |
| P3-5 상한 값 1개로 | 스크립트 기본값을 오빠 판정 **5** 에 맞춤(또는 판정을 6 으로 갱신) · env 로 팀별 override 유지 | 정본 두 값은 경보가 안 울린다 |
| P3-6 정리 상태 3값 보고 + **이벤트 재시도** | 닫힘 보고에 `wt=swept / planned(사유) / none(워크트리 없음)` 중 하나를 적는다 · `planned` 면 소유 오케가 **타이머 없이** ㉠워커 close 직후 ㉡Issue 클리어 시도 직전 두 사건에 `ft-wt-sweep.sh` 를 1회 수동 실행하고 결과(swept/none/planned)를 읽는다 · planned 가 남으면 클리어 차단 유지(§4 ④) · 틱 sweep 은 후속 «선택 어댑터»(필수 아님) | close exit 0 ≠ swept(DA r1 ④) · 「다음 틱」만 믿으면 타이머 정지 환경에서 planned 가 영원히 남는다(DA r2 ②) · 09-25 +49/일 워크트리 잠식 |
| P3-7 **라이브 예약석** | 나노 상한 **밖** +1 석 · 라이브(①) Issue 카드 전용 · 평시 비어 있음 · 다른 Issue 카드는 못 쓴다 · 라이브 Issue 클리어 뒤 close 로 비움 | 상한이 꽉 찬 채 보류 워커를 살려 두면 라이브가 자리를 못 얻는다(DA r2 ①) — 보류 워커를 죽이지 않고 라이브를 받는 유일한 길 · 값은 Q2 |

## 4. 메인팀이 여러 미션을 받고 클리어하는 방식

### 4-A. 지금 [사실]
| 팀 | 미션 큐(인덱스) | 대기 | 진행 | 완성 | 「클리어」 표시 |
|---|---|---|---|---|---|
| v65 | `design/v65/indices/{inbox,대기,진행,완성}` | 29 (+inbox 4) | 28 | 32 | 카드 완성/ 이동 + CLOSEOUT(`CLOSEOUT-v65-main-landing-20261003.md`) |
| cfo | `.worktrees/c-level-planning/design/cfo/indices/{대기,진행,완성,지금아님}` + `orders/` 204 | 15 | 17 | 31 (+지금아님 18) | 카드 완성/ + `CLOSEOUT-cfo-accounts-20261003.md` |
| ccu(위성) | **indices 없음** — `ORDER-*.md` 78 + `ORDERS-oppa-ccu.md` 원장 | — | — | — | `CLOSEOUT-ccu-u-staircase-20261004.md` |
| harness-ops | `design/teams/harness/indices` + `REQUEST-LEDGER.md` | 0 | 0 | 1 | 완성/ 이동 + ops 통합 수락 |
| issue-manager | Issue 보드 + LOOP-LEDGER 12행 | 0 | 0 | 3 | Issue close + 완료 5항 대조 |

마감 정본 = `~/.claude/rules/closeout-policy.md`: 랜딩 → 배포 브랜치 push → CLOSEOUT 1장 → 전부 닫기 · 재개 = 이벤트 기반 · 위성 종료 = «활성 작업 0» 4항(미커밋 0 · 명부 종결 · 틱 정지 · 좌석 idle+진행 카드 0 · 세션 수 0 아님).

### 4-B. 제안 [제안] — 미션 큐 한 바퀴 (상태마다 «누가 · 어떤 사건으로 닫나»)
```
Issue(issue-manager 배분 쌍) ──▶ 오케 접수 ──▶ 활성 1 (나머지 = 큐 · 우선순위 ①라이브 ②완성 전 골 축 ③완성 전 골 밖 ④완성 후)
  활성 Issue ──▶ 카드 분해(대기/ N장 · 머리줄 Issue:#N · 골좌표+닫는 증거 복붙) ──▶ ft-nano-slots 채움(활성 Issue 카드만 · ≤상한 · 살아 있는 석 기준)
  ┌ 워커 닫힘   = ft-nano-close exit 0 (산출 경로 + recv seq · wt=swept|planned|none)                         — 닫는 손 = 오케(close 호출)
  ├ 카드 수락   = 오케가 산출을 읽고 카드 머리줄에 「수락 · sha · wt 상태」 적고 완성/ 로 이동 · 같은 턴 다음 활성 카드 spawn  — 닫는 손 = 오케
  └ 정리 확인   = planned 면 오케가 ㉠close 직후·㉡클리어 시도 직전 sweep 1회 수동 실행 → swept|none 을 읽음(타이머 0 · P3-6)        — 닫는 손 = 오케(sweep 결과)
  Issue 클리어 = ①카드 전부 수락(완성/) ②랜딩 증거(아래) ③repro PASS 코멘트(type:bug) ④wt 전부 swept|none ⑤완료 5항 코멘트 + CLOSEOUT 또는 LEDGER 행
    랜딩 증거 = 「워커 tip sha」와 「랜딩 결과 sha」 둘 기록 · 결과 sha 가 대상 브랜치에 있음(ff/merge = is-ancestor · squash = cherry 게이트 «+» 0 + 랜딩 원장 행) · 검증자 = 소유 오케
            ──▶ 오케 3줄(경로·sha·남은 일) → issue-manager close 대조(5항) → planner BOARD 행 닫힘 → **issue-manager 가 BOARD 갱신 seq 를 받은 뒤에만** 큐 다음 Issue 출범
```
- P4-1 **「클리어」 정의 1개** = ①~⑤ 전부 참 · 검증자 = 소유 오케. 카드 완성/ 이동만으로는 클리어가 아니고, Issue close 만으로도 아니다.
- P4-2 **보류/재개 상태** (우선순위 역전 1종 = ①라이브 깨짐만 · ops 결정 #56982 ①): 보류 = 오케가 활성 Issue 카드 머리줄에 `상태: 보류(Issue #N · since)` 적고 나노에 「WIP 커밋 → 보고 → 대기」 1통 · 나노 ack 뒤 **close 하지 않는다 — 살아 있는 채 슬롯 점유 유지**(카드는 `진행/` 에 그대로). 라이브 Issue 카드는 **라이브 예약석(P3-7)** 으로 spawn — 보류 워커를 죽여 자리를 만들지 않는다. 재개 = 라이브 Issue 클리어 뒤 오케가 같은 나노 세션에 「재개」 1통 → **같은 세션이 이어감**(브랜치 재사용·close 경로·cherry 게이트 우회 전부 없음 — 보통 close 는 미랜딩 «+» 커밋을 REJECT 하므로 WIP 를 close 로 보내지 않는다). 보류 중 새 카드 spawn 0 · 보류 나노가 죽으면(세션 소멸) 카드는 `상태: 보류` 그대로 `대기/` 로 복귀하고 재개는 새 spawn + freshness(브랜치 재사용은 그때도 spawn 의 미랜딩 REJECT 를 그대로 받는다 — 우회 0).
- P4-3 **큐 상한 = 완성 전/후 분리** — 「완성 후」 Issue 는 팀 큐에 넣지 않고 Issue 보드 phase:post-completion 에만(cfo `지금아님/` 18 이 그 전례). 팀 큐는 완성 전만.
- P4-4 **기록 간 ack·복구** — 오케 3줄 → issue-manager 「close 대조 결과 + LEDGER 행」 회신 → planner 「BOARD 행 닫힘 seq」 회신. 어느 회신이든 10분 무응답 = 상위화(기존 규칙) · 그 사이 다음 Issue 출범 0 · 복구 소유 = 각 기록의 쓰기 소유자.
- P4-5 **고아 진행 카드 일괄 정리(1회)** = v65 28·cfo 17 을 영역 오케가 「세션 있나 → 없으면 대기/ 복귀(보류 표기 없음) 또는 CLOSEOUT 「나중에 볼 것」」로 분류 · planner BOARD 1행에 결과 수치.
- P4-6 **위성(ccu)도 큐 폴더 1세트**(`design/<x>/indices/{대기,진행,완성}`) — ORDER 파일 78 은 내용 정본으로 두고 상태는 폴더로.

## 5. 오빠 값이 필요한 질문 (최대 5 · 추천안 첫째)
| # | 질문 | 추천 | 대안 |
|---|---|---|---|
| Q1 | 나노 상한 기본값 — 스크립트 6 vs 판정 5 · 점유 = 살아 있는 석 | **5 로 스크립트 기본 맞춤 + 점유를 살아 있는 석으로**(판정 ① 「정리가 잘 돼야 함」 조건 포함) | 판정을 6 으로 갱신 · 점유만 고침 |
| Q2 | 메인 팀 활성 Issue 수 + 라이브 자리 | **활성 1 + 라이브 예약석 1(나노 상한 밖 +1 · 라이브 전용 · 평시 빈 석)** — 보류 워커는 살려 두고 라이브는 예약석으로 | ⓐ활성 2 고정(라이브 1 + 완성 전 1 · 상한 안) ⓑ예약석 없음 · 라이브는 빈 석 생길 때까지 대기 |
| Q3 | 고아 진행 카드 45장(v65 28·cfo 17) 처리 집행 | **영역 오케가 1회 일괄 대기/ 복귀 · 결과 BOARD 1행** | 그대로 두고 신규만 규칙 적용 |
| Q4 | 위성(ccu) 큐 폴더 도입 | **도입**(위성 종료 4항 ④ 「진행 카드 0」을 셀 수 있게) | ORDER 파일만 유지 |
| Q5 | §1-C ⓑ 경로 — `size:small` Issue 를 issue-manager 가 자기 나노로 집행 | **유지**(GOAL-issues 원문 그대로 · 소유 라벨 1개) | 전부 메인 오케 배분(매니저 집행 0) |

## 6. DA 기록 (직렬 DA 종료 · 재DA 없음)
- r1 `DA-roles-mission-r1.md` HOLD 5 → r2 전부 반영(머리 r1→r2 줄). r2 `DA-roles-mission-r2.md`(c5b14e180d) HOLD 2 = 「WIP 보류가 close·cherry 게이트를 못 지난다」 · 「planned 정리에 타이머 없는 재시도 사건이 없다」 → **HOLD 2회 = 직렬 DA 종료**(ORDER·PIECES 규칙 2) → ops 통합 수락 경로.
- r2→r3(ops 결정 #56982 · 문서 정정만): ①보류 = close 안 함 · 살아 있는 채 슬롯 점유 · 재개 = 같은 세션(브랜치 재사용·close·cherry 우회 전부 삭제) · 라이브 = 예약석 +1(P3-7 · 값은 Q2) · P2-1 예외 1 명시 ②planned 정리 = 이벤트 재시도(㉠close 직후 ㉡클리어 시도 직전 · 틱은 선택 어댑터). DA r2 「수락된 계약 5」는 그대로 유지. **구현 후보**(합친 뒤 별도 발주 · 지금 구현 0): `ft-nano-slots.sh` 점유 판정·후보 필터·예약석 · spawn lint `Issue:` 머리줄 · close 보고 `wt=` 3값 · press 허가 파일 · 카드 `상태: 보류` 머리줄.
