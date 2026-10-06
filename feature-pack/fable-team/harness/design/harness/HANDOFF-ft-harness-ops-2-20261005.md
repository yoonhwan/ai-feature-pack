# HANDOFF — ft-harness-ops#2 → #3 (2026-10-05 · 컨텍스트 400k 증류)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
> (원문 7 핵심 한 줄) 정말 많은 양의 이슈와 테스트, 그리고 큰 병렬적인 메인 플랜을 얼마나 잘 수행해내느냐에 핵심이 달려 있고, 큰일을 얼마나 별개로 쪼개서 동시에 아주 잘 해결하느냐에 달려 있다. 이게 기획에 반영되어야 한다.
★승계 첫 일 = 골 대조 보고★: 위 원문과 아래 열린 단위 각각이 «골의 어느 줄·표 A/B/C 의 어느 닫는 증거»인지 3줄로 planner(`_hil_route` = byz-planner-arch#3)에 mbox 보고 후 착수. 이 단위는 오빠가 harness-ops pane 에서 직접 지휘 — AskUserQuestion 허용(끝나면 원복).

## 방식 (오빠 확정 · 정본 = design/harness/issue-improvement/PIECES.md)
- 오빠 요청 1개 = 조각 1개 = 문서 1개. nano 사실(읽기 전용) → arch 작성 → da#1 1회 10분 → ops 수락 → /eli5 설명 페이지 → 오빠 인터뷰(AskUserQuestion) → 값 확정. DA HOLD 2회면 직렬 DA 종료·ops 가 결정 후 arch 에 정정 발주. 구현 0 — 합치기(오빠 「합치자」) 뒤에 구현 조각.
- 오빠에게 가는 글 = `GUIDE-human-report-20261005.md` 틀(결론 → 오빠가 할 일 → 바뀐 것 3줄 → 근거 1줄). 글로벌 CLAUDE.md 응답 스타일에 설치됨. 내부어는 첫 등장에 괄호 풀이.
- 문서 폴더 = `design/harness/issue-improvement/`(분류 폴더). 값 원장 = `VALUES-pieces-P3-P5-20261005.md`.

## 조각 현황 (PIECES.md)
P1 구성 설계 · P2 오케 지도/mbox · P3 역할·병렬·미션 · P4 보고 지침 · P5 planner 이슈 큐·병렬 분할·랜딩 · P6 세션명 · P7 팀 필수 구성 — 전부 수락. 오빠 값: P3·P5 10건 + P6 6건 확정(VALUES). **열린 것 = P7**.

## 열린 단위 (순서대로)
1. **P7 r6 정정**(발주 `ORDER-essentials-bundle-20261005.md`): 오빠 「tester+checker(bts·poller) 하나의 구성으로 v65 에서 단순화해 빠르게 수집→architect 보고, press test 필요한 작업·플랜에 유효 · 필요 시 메인 하네스가 배분」. 담당 = ft-harness-arch#2(부팅 완료·nano#1 사실 발주 중) → da#1 1회 → **ops 수락**. 정정 끝나면 PIECES.md·관련 문서 갱신 → /eli5 페이지(기존 https://claude.ai/artifact/AJVaj7Ltqa8QaXdP2GNrFr 갱신) → **오빠 인터뷰로 P7 질문(≤3) 결정**(오빠 지시 「정리되면 문서 업데이트하고 인터뷰해서 결정」).
2. 오빠 「합치자」 대기 — 합치기 = arch 가 MERGED 1장(충돌 표: P1↔P3 issue-manager 일·Issue # 소유, P7 전용 tester 필수 vs P3, P5 큐↔P1 §3-2) · da 는 조각 간 충돌만 1회.
3. 구현 조각은 합친 뒤 오빠 확정 받고 별도 발주. (구현 후보 목록은 각 SPEC 끝 「구현 후보」.)

## 좌석
ft-harness-arch#2(active · fable-5-1) · ft-harness-da#1(codex sol low · 대기형) · ft-harness-nano#1(opencode deepseek flash · 대기) · arch#0(327k 정지)·arch#1(409k 정지)·ops#0·#1 잔존 — 닫기(kill)는 오빠 판단(keep-last-2 하한). 새 arch 는 «다음 발주 시점»에 열기(빈 세션 상시 대기 금지). `seats-harness.json` `_master` = #3 로 갱신됨(gitignore 경로).

## 발행한 설명 페이지(eli5 · 비공개)
P1 https://claude.ai/artifact/46x8TkJBPysXubVqssha7J · P2 …/VhMxEh5fEkThaw1k2HLcwH · P3 …/Frimwcou8UMCUGSYXNzw8k · P5 …/RRa7aguy4ucpWE57V2yj6W · P6 …/LHZ53BtfdLwBZqxzp4yXVZ · P7 …/AJVaj7Ltqa8QaXdP2GNrFr (경로 앞 https://claude.ai/artifact/).

## 함정 (실측)
- `mbox.sh relay` 파일 경로는 **워크트리 루트 기준 상대 경로**에서 실행(design/harness/issue-improvement/… 에서 실행하면 NO_SUCH_FILE).
- nano 가 「커밋 요청」하면: 비밀 문자열 스캔 → 경로 지정 add(`git add -A` 금지) → 회신. «이미 커밋됐다»고 단정 전 `git ls-files` 로 확인(10-05 오류 1회 — facts-raw E 미커밋).
- arch/da 컨텍스트: arch 는 ~400k 에서 새 세션으로. DA 결과 파일은 `DA-*-r1/r2.md` 로 커밋됨.
- 글로벌 규칙 변경(응답 스타일)은 이미 오빠 승인으로 반영됨. GOAL 원문 7 도 오빠 승인으로 GOAL-harness.md 에 추가됨.
- 슬랙은 이 단위에서 제외(launchd 3개 bootout 상태 · 오빠 지시 시에만 `hermes send --to slack:C0C6MJGRR89` 1회 게시).
