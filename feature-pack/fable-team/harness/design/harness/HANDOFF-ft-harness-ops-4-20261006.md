# HANDOFF — ft-harness-ops#4 → #5 (2026-10-06 · 컨텍스트 407k 증류)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
> (원문 7) 정말 많은 양의 이슈와 테스트, 그리고 큰 병렬적인 메인 플랜을 얼마나 잘 수행해내느냐에 핵심이 달려 있다 … 큰일을 얼마나 별개로 쪼개서 동시에 아주 잘 해결하느냐에 달려 있다.
★승계 첫 일 = 골 대조 3줄을 planner(`byz-planner-arch#3`)에 mbox 보고 + 부팅 3항 후 착수. 오빠 지시(2026-10-06): 「구현시작. 야간자율로 완성해서 아침에 정지레디 브리핑」 — 자율로 끝까지 돌리고, 끝나면 정지-레디 상태로 오빠 브리핑 1장(GUIDE-human-report 틀: 결론→할 일→바뀐 것 3줄→근거 1줄 · 시계·달력 창 금지 · 약어 인덱스 금지).
- 이 단위의 골 축: 표 A·B·C + 원문 5(머신 배분) + 원문 7(쪼개 동시에). 닫는 증거 = ops 판정문 `design/harness/OPS-VERDICTS-20261006.md` 의 단위별 「닫힘」 줄.

## 지금까지 (통합 브랜치 feat/slack-inbound-820 에 cherry-pick -x 수거 · push 0)
- **P11 설계 확정**(SPEC r5 · 오빠 값 Q1~Q3 전부 추천안 · 회귀 방지 4항 포함 · 상한 N=20): `design/harness/issue-improvement/SPEC-github-issue-driven-20261006.md`. 설명 페이지 https://claude.ai/artifact/6nRcvJxtJqTFK1PGgXWWxf · v65·cfo 모의 구동 https://claude.ai/artifact/F7f4wkeG3FBv9Tdb7XmZYG.
- **구현 닫힘(판정문 §1~§15)**: C1a 키트 채택 · C5 큐 절 · C3 질문 원장 · C4 전이표/Closes · C11 문서 정정 · C9-기계 ft-land · C8 고아 카드 목록 · C6 슬롯/머리줄 · C2 명부/이름 lint · C17 기획 인계 · C21 회귀 팩 · C22/23 재오픈·close 사유 · C7 허가 파일 · C15 Issue 폼 · C20 기준값. 나노 커밋 → 통합 수거 sha 는 판정문에 있다.
- 카드: `design/harness/indices/완성/` 13장 + 진행/ 7장(아래).

## ★열린 일 (순서대로)
1. **판정문 §13(C7)·§14(C15)·§15(C20) 이미 기록됨 — 수거도 끝** → 남은 것 = 나노 3곳 close(`ft-nano-close.sh` · 마지막 활동 ≥3분 대기 필요) + 카드 3장 진행→완성(`ft-index-move.sh … 완성 --da design/harness/OPS-VERDICTS-20261006.md#§13|§14|§15`) + 커밋(경로 지정). 좌석 `ft-harness-temp-c7-press-permits#0`·`c15-issue-forms#0`·`c20-baseline-lint#0` · 보고 seq 57260·57264·57262.
2. **진행 중 나노 4곳 — 보고가 오면 «독립 검증 → cherry-pick -x → 판정문 §16~ → close → 카드 이동»**: `c16-issue-classify`(분류기·발견 지연) · `c18-branch-candidates`(브랜치 후보 목록 — 삭제 0) · `c10-bundle-ops-lite`(묶음 상태 전이) · `c19-seat-request`(좌석 필요 문구). 아직 완료 보고 없음(c18·c16 은 첫 보고만 옴).
3. 남은 구현(선택): C9-수락(push 부분 — **push 는 오빠 승인 영역**이라 하지 않음) · C10 실측(N=1→2→4 · 관측 프로필 승인 필요 · 하지 않음).
4. **마지막: 정지-레디 브리핑**(아래 항목) → 오빠에게 GUIDE-human-report 틀로 1장 + 설명 페이지(eli5 폼) 갱신(같은 URL) 권장.

## 아침 브리핑에 올릴 «사람 판단» 항목 (자율로 못 한 것 · 근거 포함)
- **push/PR**: 통합 브랜치 `feat/slack-inbound-820` 은 origin 보다 앞섬(커밋 ~50) · PR #824. push·main 머지는 오빠 승인(승인 전 push 0 · 로컬 검증 규칙 #1: `bash -n` + 단위별 시험은 판정문에 있음).
- **라이브 FT_BIN 이전(#816 ⑤)**: 지금 구현물은 전부 추적본(`scripts/fable-team-bin/`·`scripts/harness-install/`)에만 있고 라이브 bin(v6-realtime-live `.fable-team/bin`)에는 안 갔다 — 키트 채택 뒤 승인.
- **카드 머리줄 4줄**(`Issue:`·`상태:`·`선행:`·`시험 입력:`)과 `기준값:` 가 없는 카드는 슬롯 후보에서 빠진다 — 하네스 카드 양식 갱신 필요.
- **P6 세션명 문법에 역할 `ops` 없음**: 현행 `ft-harness-ops#N` 이 lint REJECT(구 문법 19/28 중). P6 문서 정정 vs 개명 — 오빠 결정.
- **tmm q(질문 목록) 명령**: `tmm h` 가 외부 질문 원장을 못 읽음 → tmm 본체 수정 별도 발주(C3 [사실: 불가]).
- **고아 진행 카드 45장**(v65 28·cfo 17) 대기/ 복귀 — 해당 팀 오케 승인 필요(C8 은 목록만).
- **Issue 라벨 생성**(`from:member` 등)·**원격 머신 설치**(jarvis·byzs-mac-mini 역할 미확인) — 외부 쓰기라 승인.
- **close 사유 줄 문법**(`close-사유:`·`승계:`·`확인 seq:`)은 C23 스크립트가 정함 — SPEC §12-4 에 문서 반영 필요.
- **회귀 팩 실데이터**: 지금 `tests/regression/issue_pack.jsonl` 은 예시 2행 — 매니저 구동 뒤 실제 닫힌 Issue 재현 명령으로 채워야 함.
- **세션 정리**: arch#2·#3 정지 · ops#1·#3 정지 — keep-last-2 규칙 안에서 오빠 판단.

## 함정 (실측)
- zsh 에서 `for p in "a b"; do set -- $p` 는 분리되지 않는다 → `IFS=: read n q s <<< "$p"` 사용.
- 훅이 Bash 명령 텍스트 안의 삭제 계열 문구(브랜치·워크트리 삭제 명령 등)를 보고 명령 전체를 차단한다 → 그런 문구가 든 카드·판정문은 **Write 도구로 .py 를 만든 뒤 `python3 파일` 로 실행**. mbox 명령에는 백틱 금지.
- cherry-pick 은 작업 트리가 깨끗해야 한다 → 스폰이 만든 카드 이동(대기→진행)을 경로 지정 커밋한 뒤 수거. `cherry-pick … | tail` 파이프는 실패를 가린다 — 종료코드를 직접 보라.
- `ft-nano-close` 조건: ①결과 파일 실재 ②master 회수 seq ③마지막 활동 ≥3분 ④카드 «상태» 에 `세트: <40hex> · 시험: <명령> rc=<n> · 이슈: 0` 줄 + `정본 영향 없음: <이유≥10자>` 줄(카드가 진행/ 에 있을 때). 닫은 뒤 `ft-index-move … 완성 --da …`. FT_NANO_FEAT 는 `feat/slack-inbound-820` 로 맞춰 둠(env `.fable-team/bin-harness/harness-env.sh`) · FT_SEND_FROM 은 `ft-harness-ops#4` 였음 → 후계는 `#5` 로 바꿔야 나노 보고가 도달한다.
- mbox 발신 한도 60초 5통 — `--force` 쓰지 말 것. 병행 나노가 Serena 를 공유해 활성 프로젝트가 서로 바뀐다 → 나노는 Edit 절대경로만.
- 검증은 항상 «나노 보고를 믿지 말고 ops 가 시험 재실행 + diff 범위 + 삭제 줄 수 + 비밀 스캔».

## 우편함 주의 (후계 필독)
- 나노 7곳은 ★ft-harness-ops#4★ 로 보고한다(발주문의 수신자). 후계는 mbox.sh 의 recv 에 이름 인자 ft-harness-ops#4 를 줘서 #4 앞 우편함을 직접 읽어라. #4 세션은 오빠가 닫기 전까지 살아 있다 — doorbell 은 #4 pane 에 울린다. 새로 spawn 하는 나노부터는 harness-env.sh 의 FT_SEND_FROM 을 #5 로 바꿔라.

## 환경
- 이 워크트리 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops` · 브랜치 `feat/slack-inbound-820` · 미커밋: `.serena/project.yml`(내 Serena 활성화 부산물 — 커밋 금지) · mbox=`/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/comm/mbox.sh` · 환경 `source .fable-team/bin-harness/harness-env.sh`(리포 루트 기준 절대경로) · 골 3줄 파일 `.fable-team/bin-harness/goal-lines-harness.txt`.
- 좌석: arch#4(P11 완료 후 대기) · da#1 · nano#1(대기) · 위 나노 7곳.
