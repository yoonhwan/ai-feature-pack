# SPEC — 풀플로우 1장: 한 건이 들어와서 사라지기까지 (r2 · ft-harness-arch#2 · 2026-10-05 · 조각 P8)

> MERGED 반영 r+1 (C11 · 2026-10-06): 단계 1 입력자 = 4경로(C11++ · P11 §2·§6-5 · 「슬랙」 토큰 삭제) · 단계 7 ①④ = 세트 멤버 가입→하위 허가 획득·해제 역순(충돌 ⑪ · P9 3-D) · §3 브랜치 행 = 삭제 후보 목록 1구(C11++ · P11 §6-4). 충돌 ⑤ 「P8 단계 7 그대로」 = 보고 수신 architect 이미 일치(변경 0) · §4 충돌 후보 ①~⑤ 는 MERGED §1 로 확정·반영됨.

> r1→r2(DA r1 `DA-full-flow-r1.md` HOLD 4 반영): ①단계 1 닫음 = `접수`(A-n) + 등록 인계 · 단계 2 가 새 입력이면 Issue 를 **생성**하고 기존 Issue 면 대조한 뒤 Issue # 를 planner 에 회신 → `등록` ②단계 10 close ⑤ = **cherry 게이트 통과 결과(OK/PASS+사유) 승계** · 실제 REJECT 만 9 로 ③단계 11 ⑤ 에 **묶음 재사용 칸**(오케가 보존 묶음을 후보 sha 로 `reopen` → architect 분류 → push) · 후보 FAIL/미측정 → 8 → 11 ④ ④§3 역할 좌석 행의 keep-last-1 = 글로벌 CLAUDE.md 기존 표준승인(2026-09-11) 원문 복붙으로 출처 명시(새 허용 아님).

> **건드리는 정본**: 없음(P1~P7 확정분을 «한 줄기»로 다시 적은 것 · 새 규칙 0 · 삭제 규칙은 글로벌 HIL 그대로 복붙). 조각 간 충돌은 §4 에 «표시»만(합치기는 오빠 「합치자」 뒤).
> **전제 조각**: P1 `DESIGN-harness-composition`(e184bc1f57 · Issue 소유 = 메인 오케) · P2 `SPEC-main-orch-tree`(37e19724b5) · P3 `SPEC-roles-mission-flow`(r4 · 활성 1 + 예약석 · 클리어 ①~⑤) · P4 `GUIDE-human-report` · P5 `SPEC-planner-issue-queue`(r5 · 큐 7상태 · 수렴 7단계) · P6 `SPEC-session-naming` · P7 `SPEC-team-essentials`(r7 · 시험 묶음) · 오빠 값 = `VALUES-harness-composition` · `VALUES-pieces-P3-P5`(P3·P5·P6·P7 전부 확정).
> **핵심 한 줄 기여**(GOAL-harness 원문 7): 큰일을 쪼개 동시에 푸는 길은 「입력 → 큐 → Issue → 카드 N → 나노 N → 시험 묶음 → 수거 1 → 랜딩 1 → 삭제」 **한 줄기**다. 조각마다 따로 적힌 단계를 한 줄로 이어 «어느 단계에서 누가 무엇으로 닫고, 실패하면 어디로 돌아가나»를 한눈에 두면 병렬 폭(단계 5)과 수렴(단계 9~11)이 어디서 막히는지 보인다.
>
> 골 원문(GOAL-harness.md 복붙):
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
> 정말 많은 양의 이슈와 테스트, 그리고 큰 병렬적인 메인 플랜(메인 기획)을 얼마나 잘 수행해내느냐에 핵심이 달려 있는 거예요. 지금 이 골(Goal)들은 그 세부 항목들을 다 잘 처리해서, 결국엔 그 루트인 큰일을 얼마나 별개로 쪼개서 동시에 아주 잘 해결하느냐에 달려 있는 거죠. 이게 기획에 반영되어야 해요.
>
> 골의 축: 표 A(모니터·오빠 요청 → Issue) · 표 C(커밋·push·반영) · 원문 7. 발주 = ops#3 ORDER-full-flow(#57051). 오빠 원문(10-05): 「github issue 와 카드와 planner issuemgr 메인마스터들 분배해 나노워커에서 처리, 테스터에서 테스트 문제확인 수정 완료 시 워크트리 브랜치 정리 main 랜딩 삭제 과정을 지금 정리된 하네스로 정리 공유」 · 「삭제하고 arch 한테 풀플로우로 다시 쓰라해」. 닫는 증거 = DA APPROVE + 오빠 「맞다」. 사실 출처 = 기존 FACTS(composition·roles·planner·team-essentials·r6) — 새 측정 0.

## 0. 본선 한 줄기 (13단계 · 갈림길은 ⓐ~ⓖ 로 표시 · §2)
```
입력(오빠 말 · GitHub Issue) ─1→ planner 큐 행(접수 A-n → 등록) ─2→ issue-manager Issue 등록·배분 쌍 ─3→ 메인 오케 접수(활성 1 · 큐 N)  ⓐ라이브  ⓕsize:small
 ─4→ 카드 분해(대기/ N장 · 분해표 · 웨이브) ─5→ 나노 N 병렬(자리 5 + 라이브 예약석 1 · 빈 자리 같은 턴 채움) ─6→ 나노 완성·freshness
 ─7→ 시험 묶음(press 필요 카드만 · tester 1 겸임 · bts·poller · architect 직접 보고)  ⓑFAIL/미측정  ⓖ비-press 대체 축
 ─8→ 문제 확인 → 수정(나노) → 재시험 루프(architect 소유 bts N회차)
 ─9→ 수거(cherry-pick -x → feat/<team> · cherry 게이트)  ⓓ겹침 직렬 ─10→ 나노 close · 워크트리 정리(wt=swept|planned|none)
 ─11→ main 랜딩(대상 동기화 → 후보 1 → 후보 sha 게이트 → push → 라이브 1회)  ⓒmain 이동 ─12→ 마감(CLOSEOUT · Issue close · 큐 클리어 3회신)  ⓔack 누락
 ─13→ 삭제(워크트리·나노 세션 = 자동 · 브랜치·그 외 = HIL)
```

## 1. 본선 — 단계마다 4칸 (누가 · 시작 사건 · 닫는 증거 · 실패 시 복귀) · 출처 = 괄호
| # | 단계 | 누가 | 시작 사건 | 닫는 증거 | 실패 시 복귀 |
|---|---|---|---|---|---|
| 1 | **입력 → planner 큐 행** | planner(쓰는 손 하나) · 입력자 **4경로**(P11 §2 · 전부 Issue 로 일원화 · 「Issue 먼저 → 큐 행」): ①오빠 임의 기획 세션(임시 마스터 `byz-planner-master-claude#N` · 정리본 → issue-manager 에 mbox 1통 → 매니저가 Issue N건 생성) ②세션 에이전트 직접 등록(`gh issue create` + 매니저에 mbox 1통 쌍) ③오빠가 GitHub 폼으로 직접 등록(버그) ④사내 멤버 GitHub 버그 확인 요청(`from:member`) · 별도로 issue-manager 모니터가 CI·라이브 경보를 가져온다(입력 4경로와 별개 감시) | 오빠 말 1건 또는 Issue 생성 1건 | BOARD 큐 절 행 1(8칸: 순번·종류 즉시/일반·접수 번호 `A-n`·Issue #·골좌표 복붙·완성 전/후·상태·닫는 증거) 상태 **`접수`**(새 입력 = Issue # 빈칸 · 기존 Issue 입력 = Issue # 기입) + issue-manager 에 「큐 갱신 · 행 번호 · 종류」 통지 1통 = **등록 인계** (P5 Q-1·Q-3·Q-6) — `등록` 전이는 단계 2 의 Issue # 회신을 받은 뒤 planner 가 쓴다 | 골좌표 복붙 정본 없음(cfo·ccu `GOAL-<x>.md` 부재) → 영역 오케가 GOAL 1장 먼저(P5 Q-7) · 중복 의심 = 표시만, 닫기 0(P5 Q-1b) · 완성 후 항목 = 팀 큐에 넣지 않음(P3 P4-3) |
| 2 | **Issue 생성/대조 → 등록 · 배분 쌍** | issue-manager | 큐 행 `접수` 통지 수신 | ⓐ 새 입력(Issue # 빈칸) → **Issue 생성**(type·team·재현 스텝 · 라벨 6+마일스톤) / ⓑ 기존 Issue → 라벨·중복 **대조**(같은 일 판정은 매니저 제안 → planner 확정) → **Issue # 를 planner 에 회신** → planner 큐 행 `등록` → `ready` → **배분 쌍** = Issue 코멘트 1줄 「배분 → <오케>」 + 메인 오케 mbox 5줄(Issue # · 골좌표 · 닫는 증거 · 완성 전/후 · 담당) + 자원 줄 1(press/GPU/vLLM 예·아니오) — 둘 중 하나만 있으면 «미배분» (P1 §3-3 ①② · P3 P1-2 · P2-2) | 라벨 비면 `needs-triage` 반려 코멘트 → 입력자 보정 → 2 재진입 · `size:small` 이면 ⓕ |
| 3 | **메인 오케 접수** | 팀 master(Issue # 소유자) | 배분 쌍 도착 | 「접수」 회신 seq → 큐 행 `활성`(팀당 활성 1 · 나머지 큐) · Issue `in-progress` + `team:<x>` 라벨 1개 (P1 Q1 · P3 P2-1 · P5 Q-4) | 활성이 이미 1 → 큐 `대기`(즉시=라이브면 ⓐ) · 10분 무회신 → 매니저 상위화(ⓔ) |
| 4 | **카드 분해** | arch 설계 · 오케 작성 | 큐 행 `활성` | `대기/` N 장(머리줄 `Issue:#N` · 골좌표+닫는 증거 복붙 · 파일 집합 겹침 0 우선 · `선행` 1줄 · **「press 필요」 표기**) + 분해표 1(카드·파일 집합·선행) · 상한보다 큰 행은 웨이브로 (P5 ②-B ① · Q-8 · P3 P3-1) | 채울 카드 없음 = **쪼개기 부족 신호** → 분해표 갱신 또는 큐 행 1줄(P3 P3-1b) · 겹침 카드 → ⓓ |
| 5 | **나노 N 병렬** ★핵심 책임★ | 오케(spawn 호출) | 빈 자리(상한 **5** · 점유 = 살아 있는 석 전부 · + 라이브 예약석 1 = 상한 밖) | `ft-nano-spawn`(카드 lint → 워크트리+심링크 → `tmuxc open` → 명부 등록 → 카드 대기→진행 → 첫 발주 mbox → jsonl 도달) · 활성 Issue 카드만 후보 · **빈 자리는 같은 턴에 채움**(노는 석 0) · 나노 press 금지 (P3 §3-A·P3-1b·P3-2·P3-3 · 오빠 값 P3 Q1·Q2) | 노는 석(IDLE≥10분) = 빈 석 아니라 «푸는 대상»(막힘 해소 → 완성 → close) · 세션 소실 → 카드 `대기/` 복귀(보류 표기 없으면) → 재spawn + freshness · 진행 카드 ↔ 세션 1:1 아니면 매 틱 복귀 후보(P3 P3-4) |
| 6 | **나노 완성 · freshness** | 나노 | 카드 작업 끝 | 커밋(WIP 0) → `ft-nano-freshness.sh <브랜치>` **FRESH** 1줄 → 보고 mbox 1통(산출 경로 · tip sha) (single_set §3 · P5 3-B ①) | STALE → 최신 루트 병합 → 재시험 → 6 재진입 · STALE-OVERLAP → 자동 병합 금지 · arch 1줄 재대조(ⓓ) · 미랜딩 0 판정은 cherry 원장으로(squash 는 조상 관계를 안 만든다) |
| 7 | **시험 묶음**(press 필요 카드만) | 묶음 = tester 좌석 1(checker 역할 겸임) + bts·poller · 여는 손 = 오케 · 보고 수신 = **architect** | 「press 필요」 카드 `활성` → 오케가 `ft-role-spawn tester` + 명부 `test_bundle{card, seat, state=open, open_event}` · 카드당 묶음 1(멱등) | ①세트 멤버 가입 → 카드가 요구하는 하위 허가(장치/브라우저 리스) 획득(허가자 v65 master · `free/held` · P3 P2-3 · P9 3-B · 해제는 역순) ②**같은 세트**(서비스·러너·FE = 같은 HEAD · 최신 루트 병합 뒤) ③press → 4자 표(`축\|사실\|시간` × 아키텍처 문서·코드·worker 로그·화면 poller) + 분모(유효 n/m) + 유효 poller 표본(그 회차 세트의 press 구간 ≥1) ④하위 허가 해제 → 멤버 탈퇴(「press 끝 · 결과 경로」) ⑤architect 가 결과 분류 → PASS 수락 = `close_event` seq · `state=closed` (P7 §1-B·§1-C · 오빠 값 P7 Q1~Q3) | FAIL/미측정 → ⓑ(`state=reopen` → 8) · ack 누락 → `pending`(ⓔ) · 좌석 소실 → `pending` · 오케 복구 · 「관측 0」은 「정상」이라 쓰지 않는다 · 비-press 팀 → ⓖ |
| 8 | **문제 확인 → 수정 → 재시험 루프** | architect(bts 루프 소유 · N·회차·계속 여부·DA 소환) · 수정 = 나노(정정 카드 · 같은 Issue) · 재시험 = 묶음 | 7 의 FAIL/미측정 분류 또는 11 의 게이트 FAIL | 회차마다 3자 대조(스펙↔코드↔로그 + 화면) → 원인 1건(발생 위치 먼저) → 정정 카드 1장 `대기/` → 5 로 spawn → 6 → 묶음 `reopen` → 7 → PASS 분류 · 2 HOLD 같은 원인 = 고정 구현 + 기계 증거로 닫음 (BTS-N-ROUND-LOOP · P5 ②-B ④ · P7 §3) | 2회 수렴 실패 → 티어 상향(arch fable max · DA high) 뒤 닫히면 복귀 · 판정 10분 초과 = 결함 신호 → ops `[HIL]` · 레거시 늪(§0-B 신호 4) → 벽 세우고 V65 신규 |
| 9 | **수거**(N 브랜치 → feat/<team>) | 오케(통합 좌석) · 순서 판정 = arch | 카드 PASS 수락 | `cherry-pick -x`(기본 · squash 는 커밋 많을 때 예외) → **cherry 게이트 통과 출력**(OK / PASS content_landed_via_merge_tree / PASS content_landed_then_superseded + 사유) + 결과 sha 가 feat 에 도달(`is-ancestor`) → `LANDING-LEDGER.md` 행(카드 · 워커 tip · 결과 sha · 방식 · 시각 — 감사 기록) (P5 ②-B ③ · L-1 · L-3 · 오빠 값 P5 Q3·Q4) | REJECT → 나노에 되돌림(수정 → 6) · 충돌·delta → arch 1줄 판정(ⓓ) · 「랜딩됨」은 매 갱신 HEAD 재확인(09-17 오판 3) |
| 10 | **나노 close · 워크트리 정리** | 오케(`ft-nano-close.sh <좌석> --result <경로> --recv <seq>`) | 수거 sha 확인 | ①~⑥ 조건(⑤ = **9 의 cherry 게이트 통과 결과를 승계** — OK(«+» 0) / PASS content_landed_via_merge_tree / PASS content_landed_then_superseded + 사유 중 하나 · «+» 0 은 그중 한 경우) 통과 → 명부 삭제 · 원장 append · 태그 해제 · **세션 kill**(자동 · §3) → 같은 호출 안 `_wt_clean_run`(**tar 보관 → 워크트리 제거 · 브랜치 보존**) → 보고 `wt=swept\|planned(사유)\|none` → 카드 머리줄 「수락 · sha · wt」 + `완성/` 이동 → **같은 턴 다음 카드 spawn**(5) (P3 §3-A close · P3-6 · P4-B) | 게이트 **실제 REJECT**(내용이 feat 에 없음) 만 → 9 의 복구 소유(오케·arch 1줄) 로 · `planned` → ㉠close 직후 ㉡Issue 클리어 직전 `ft-wt-sweep.sh` 1회 수동(타이머 0) → swept/none 읽음 · planned 남으면 12 차단 |
| 11 | **main 랜딩**(통합 tip → 대상) | 소유 오케 집행(push) · planner = 순번·통지·기록 · 게이트 = 묶음 + DA | 활성 Issue 카드 전부 `완성/` · 통합 tip 1 · planner 랜딩 순번 창 | ④ 대상 동기화 → **후보 1**: fetch → T=origin/main 기록 → `is-ancestor T feat` 참 = ff 후보 / 거짓 = `merge-tree --write-tree T feat`(충돌 = 중단) → OID 기록 → `commit-tree OID -p T -p feat` → `후보^{tree}==OID` ∧ `is-ancestor T 후보` 아니면 중단 → 겹친 경로 결정 1줄 ⑤ **묶음 재사용**: 오케가 이 플랜의 보존 묶음(`closed-retained`)을 후보 sha 로 `state=reopen`(`open_event` = 후보 sha · 새 묶음 0 · press 허가 재획득) → **후보 sha 에서** 차분 → 전체 세트 1회 → 3버블 1회(묶음 · 서비스·러너·FE = 후보 sha 한 세트 · 4자 표) → **architect 결과 분류 PASS**(P7 §1-B ⓐ) → DA⑥ 증분(판정문이 후보 sha 를 이름) → 소유 오케 수락 → push 그 후보만(force 0) → **원격 sha == 후보 sha** → 묶음 `closed` ⑥ 라이브 1회(CD 리비전 commit-sha == 원격 sha · 4자 표) (P5 3-B ④~⑥ · L-2 · L-5 · 오빠 값 P5 Q5 · S10 교훈) | non-ff 거부 · T 이동 → ⓒ(④ 재진입 · ⑤ 전부 다시) · **후보 게이트 FAIL/미측정** → 묶음 `reopen` 유지 → 8(정정 카드 → 5·6·9·10) → **11 ④ 부터 다시**(7 의 원카드 시험으로 돌아가지 않는다) · DA 2 HOLD → 고정 구현 + 기계 증거 · 다른 팀이 같은 대상에 push 중 → planner 순번 대기(동시 push 금지) |
| 12 | **마감** | 오케(CLOSEOUT·5항·PR) → issue-manager(대조) → planner(큐) | 11 ⑥ 라이브 증거 | CLOSEOUT 1장(골 원문 · 축별 닫는 증거 sha · 배포 브랜치 sha · 다른 트랙 랜딩 때/완성 후 · 다시 여는 법) → 완료 5항 코멘트(닫는 사건·PR·재현 PASS·정리·카드) → 랜딩 PR 「Closes #N」 머지 = Issue close → 오케 3줄(경로·sha·남은 일) → 매니저 「close 대조 결과 + LOOP-LEDGER 행」 → planner 큐 행 `클리어` + BOARD seq 를 매니저에 회신 → 다른 팀 큐에 「루트 이동 sha」 행 → **그 seq 뒤에만** 다음 큐 행 `활성` (P1 §3-3 ⑤⑥ · P3 P4-1·P4-4 · P5 Q-4·Q-5 · closeout-policy) | 5항 미비 → 매니저 1통 → 오케가 reopen + `status:review` + 사유 코멘트(소유 = 오케) · 어느 회신이든 10분 무응답 → ⓔ · 미커밋 ≠ 0 / 원격 sha 불일치 → 11 로 |
| 13 | **삭제** | 자동 = nano-close 경로 · HIL = 오빠 | 12 의 CLOSEOUT push | §3 표 그대로 — 나노 워크트리·나노 세션은 10 에서 이미 자동 · 묶음 좌석은 논리 `closed` 뒤 `closed-retained`(물리 kill = master · keep-last-2) · 역할 좌석은 keep-last-2 하한 · **브랜치 삭제·kill-server·인프라 = HIL** | 자동 조건 미충족(좌석 살아 있음 · branch 가 `nano/*` 아님) → 스크립트 생성 + 사람 `!` 실행 경로 · 삭제 전 미push 커밋 확인(`git log origin/main..HEAD`) |

## 2. 갈림길 7 (어디서 갈라지고 어디로 돌아오나)
| 갈림길 | 조건 | 길 | 복귀 지점 | 출처 |
|---|---|---|---|---|
| ⓐ **라이브 깨짐** | 큐 종류 `즉시`(고객 영향·회귀 1종만) | 활성 Issue 를 **보류**(카드 머리줄 `상태: 보류(Issue #N · since)` · 나노에 「WIP 커밋 → 보고 → 대기」 1통 · ack 뒤 **close 하지 않음** · 슬롯 점유 유지) → 라이브 카드를 **라이브 예약석**(상한 밖 +1)으로 spawn → 라이브 Issue 클리어(1~12) → 오케 「재개」 1통 → **같은 세션이 이어감**(브랜치 재사용·close·cherry 우회 0) · 보류 나노가 죽으면 카드 `대기/` 복귀 → 새 spawn + freshness | 단계 5 | P3 P2-1 예외 1 · P3-7 · P4-2 · 오빠 값 P3 Q2 |
| ⓑ **시험 FAIL / 미측정** | 7(원카드) 또는 11 ⑤(후보 sha) 의 분류가 PASS 가 아님(미측정 = 빈 파일·press 전 표본만·타 회차 파일·창 밖) | 묶음 `state=reopen`(같은 카드/플랜 · 새 묶음 열지 않음) → 8 루프(architect) → 정정 카드 → 5·6 → 재시험 | 7 에서 왔으면 단계 8 → 7 · 11 에서 왔으면 단계 8 → 9·10 → **11 ④** | P7 §1-B ⓑ · r3 「측정된 관측」 |
| ⓒ **main 이 움직임** | 11 ④ `is-ancestor T feat` 거짓 또는 push non-ff / T 재이동 | merge-tree 후보 재생성(feat 트리 그대로 쓰기 금지 — S10: 16 파일 삭제) → OID 재기록 → ⑤ 전부 다시(차분·전체 세트·3버블·DA) | 단계 11 ④ | P5 3-A「main 이 움직였을 때」· L-5 |
| ⓓ **같은 파일 겹침** | 분해표 파일 집합 교집합 ≠ 0 · 수거 충돌 · freshness STALE-OVERLAP | 분해 때 같은 석 또는 `선행` 지정 → 수거는 **직렬**(겹침 카드끼리) → STALE-OVERLAP 은 자동 병합 금지 · arch 1줄 판정 뒤 진행 | 단계 4(분해) / 9(수거) | P5 L-4 · P3 3-A freshness |
| ⓔ **ack 누락** | 접수·보고·close 대조·BOARD seq 중 어느 회신이든 **10분 무응답** · 2 HOLD · 좌석 사망 | 상위화(매니저→planner→오빠 `[HIL]`) · 그 사이 다음 Issue 출범 0 · 묶음은 `pending` · 복구 소유 = 그 기록의 쓰기 소유자(큐=planner · Issue=매니저 · 카드·명부=오케) | 끊긴 단계 그 자리 | P3 P4-4 · P5 Q-4 · P7 §1-B ⓒ |
| ⓕ **size:small** | Issue 라벨 `size:small`(테스트·CI·문서·1파일) | `team:issue-manager` 소유(소유 라벨 1개 그대로) → 매니저가 메인 오케 역할을 겸해 **자기 명부에 나노 1장** → 4~12 축소판(카드 1 · 묶음 0 또는 대체 축 · PR → 랜딩 → 닫기) · `repro-e2e#0` 은 재현 PASS 코멘트만(수정 0) | 단계 2 → 4(매니저 경로) | P3 §1-C ⓑ · 오빠 값 P3 Q5 · **충돌 후보**(§4 ①) |
| ⓖ **비-press 팀** | 카드에 「press 필요」 표기 없음 · 팀 명부 `test_bundle.mode=alt\|none` | 묶음 열지 않음 → 7 대신 **대체 축 표**(cfo = API 응답·PG 행 · ccu = SSE 수신 시각 · issues/harness = Issue 코멘트·단위 시험 출력) · 최종 게이트(11 ⑤)도 같은 프로필(전체 세트 + 대체 축 증거 + DA · 오디오·DOM 요구 0) | 단계 7(대체) → 9 | P7 §2·§3 · r3 |

## 3. 삭제 단계 — 현행 글로벌 그대로 (새로 허용하는 말 0)
| 대상 | 자동 / HIL | 경로 · 조건 | 보존·복원 |
|---|---|---|---|
| 나노 **워크트리** | **자동**(표준승인 2026-09-25) | `ft-nano-close.sh` → `baton wt-clean` 만 · 조건 3: ①tmux 세션 없는 좌석 ②미커밋은 `[wip] nano close <seat>` 커밋 «먼저» 성공 ③**브랜치는 삭제하지 않는다** · 좌석 살아 있거나 branch 가 `nano/*` 아니면 스크립트 생성 + 사람 `!` 실행 | `.baton/archive/nano_wtclean-<seat>_<ts>.tar`(node_modules 제외 · `baton archive:prune`) + 브랜치 → 복원 `git worktree add <경로> <브랜치>` |
| 나노 **세션 kill** | **자동**(표준승인 2026-10-02) | nano-close 경로 하나뿐 · CLOSED 처리 직후 `@zc_v65_active` 해제 → kill · ★나노 계보는 keep-last-2 면제★ | — |
| **역할 좌석** 세션(master·arch·DA·tester·pm) | 자동이되 **keep-last-2 하한**(2026-07-11) | `tmux kill-session`/`tmuxc kill` 상시 허용 · 계보(베이스명 + `#N`)당 최근 2 보존 · **기존 표준승인 원문 복붙**(글로벌 `~/.claude/CLAUDE.md` 「⛔ 파괴·비가역 작업 HIL 필수」 tmux 항): 「**예외 — zombie-clean 자동 정리는 keep-last-1 (2026-09-11)**: `zombie-clean.sh` 의 `tmux-prune`/`auto` 경로는 `ZC_TMUX_KEEP=1` 로 동작한다(idle≥120분·라이브서버·attached 가드는 그대로 유지). **사람·에이전트가 손으로 정리할 때는 keep-last-2 하한이 그대로 적용된다.**」 — 이 문서가 새로 넓힌 것 0 · 시험 묶음 좌석 = 논리 `closed` 뒤 `closed-retained` · 물리 kill = master | — |
| **브랜치** `git branch -D` (나노·feat·main 전부) | **HIL** | 어느 경로도 자동 삭제 0 · `block-destructive.sh` 차단 그대로 · issue-manager = 삭제 후보 목록(브랜치·랜딩 sha·게이트 결과·tar)을 정렬 회차마다 갱신 → 오빠가 HIL 1회 일괄 집행(P11 §6-4 · 다시 묻지 않음) | 브랜치 = 워크트리 복원의 유일한 조상 경로 |
| `kill-server` · `pkill` · `kill -9` · DB/인프라/GPU 삭제·drop · force push | **HIL** | `block-destructive.sh` 차단 · 「종료/증류」 모호하면 보존인지 닫기인지 먼저 확인 | — |
| 자기 세션이 띄운 테스트 러너·Monitor | 자동 | 정지·재실행 HIL 없음 | — |
삭제 전 공통: `git log origin/main..HEAD`(미push 커밋) · 그 워크트리를 가리키는 외부 심링크(`node_modules`·`.env.local`) 점검 · 삭제 뒤 CLOSEOUT 「다시 여는 법」에 브랜치명 1줄.

## 4. 충돌 후보 — 본선에서 부딪히는 자리에 표시만 (고치지 않음 · 합치기는 오빠 「합치자」 뒤)
| # | 자리 | 한쪽 | 다른 쪽 | 본선에서 어떻게 읽었나 |
|---|---|---|---|---|
| ① | 단계 2 · ⓕ | P1 §3-2 issue-manager = 등록·배분·대조·색인(수정·랜딩 0) | P2·GOAL-issues 「수정·테스트·랜딩」 · 오빠 값 P3 Q5 size:small 직접 처리 | 두 경로(ⓐ 메인 배분 · ⓑ size:small)로 읽음 · 합칠 때 P2 표 1 매니저 행에 「(size:small 한정)」 |
| ② | 단계 1·12 | P1 §3-2 「planner 는 Issue 읽기만」 | P5 「큐 관리·투입·랜딩 지원」 | 투입 = 큐 행 + 통지(Issue 쓰기 0) · 지원 = 순번·통지·기록(집행 0) → 모순 아님 · 합칠 때 P1 planner 줄 1구 |
| ③ | 단계 7·11 ⑤ | P3 P3-3 「press 석 = tester **또는 오케**」 | P7 「press 는 묶음 tester 만 · 오케 press 금지」 · 보고 수신 = architect(현행 v65 tester→master 11행) | 본선은 P7(오빠 값 P7 Q1·Q2 확정)으로 적음 · 합칠 때 P3 P3-3 문구 교체 |
| ④ | 단계 5 | `ft-nano-slots.sh:12` 기본 6 · :64 노는 석 = 빈 석 | 오빠 값 P3 Q1 「5 · 노는 세션도 자리 차지」 | 본선은 오빠 값 · 구현 조각에서 스크립트 정정 |
| ⑤ | 단계 10 | close exit 0 | wt=swept 아님(planned 잔존) | P3 P3-6 이벤트 재시도로 읽음 · 틱 sweep 은 선택 어댑터 |

## 5. 오빠 값이 필요한 질문 (최대 3 · 추천안 첫째 · ops 인터뷰)
| # | 질문 | 추천 | 대안 |
|---|---|---|---|
| Q1 | 단계 13 **브랜치 삭제** — 랜딩이 확인된(cherry 게이트 통과 + 원격 sha 도달) `nano/*` 브랜치도 지금처럼 HIL 로 둘지 | **HIL 그대로**(현행 · 브랜치 = 복원 조상 · tar 보관만으로는 역사 복원 불가) | 「랜딩 확인된 nano/* 만」 nano-close 경로에서 자동 삭제(새 표준승인 필요 · block-destructive 예외 추가) |

## 6. DA 기록
- r1 `DA-full-flow-r1.md` **HOLD 4**(①접수→Issue 생성 경로 공백 ②close ⑤ 가 게이트 결과를 좁힘 ③후보 sha 시험에 묶음 재사용 칸 없음 ④keep-last-1 출처 미확인) → r2 전부 반영 → r2 `DA-full-flow-r2.md` **APPROVE · HOLD 0**(④ 는 글로벌 CLAUDE.md:123 직접 확인으로 「기존 표준승인」 확정). 범위 = 조합·문서 정합만(조각 내부 재검증 0 · 집행 승인 아님) → ops 수락 → `/eli5` 발행 → 오빠 「맞다」.
