# 인덱스: airag-detector-s0s1 — 끝: 안 B 카드 2 «탐지기 S0·S1» 터미널 시험 계획 파일 1개(.fable-team/state/airag/detector-s0s1-plan.sh)가 bash -n 통과 · OPPROBE_DRY=1 점검 집계 줄 원문이 있고 · master 가 ft-hil.sh --add 로 사람 한 줄 실행을 걸어 판정표 행이 채워진다
<!-- ledger: design/aifp/GOAL-LEDGER-airag.md -->
- Issue: 없음 — 2026-11-05 airag 팀 안 B 카드(이 카드 r1410 정본 꼴 재작성 · 내용·범위 그대로)
- 제안서: 없음 — 새 안 0 · 안 B 설계(arch-20261029-appB.md §7 카드 2)의 남은 몫
- 담당: airag (aifp-airag-master-claude#10) · 줄 주인: master#10
- 선행: DA r2 닫힘(35347c52 · feature/rag-transplant)
- 발주문 전문: /Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/.fable-team/prompts/nano-airag-detector-s0s1-20261105.md (첫 3줄 = 원래 골 원문·축 · 디스크에만 있음 · 가지 미추적 → 절대경로로 읽는다)
- 개설 필수조건: 나노 개설 = `ft-nano-spawn … --base feature/rag-transplant` 만 쓴다(판단 여지 0). origin/main 개설은 금지다 — origin/main 에는 정본 문서 2개(arch-20261028-appreg.md · arch-20261029-appB.md)가 없다(git cat-file -e rc128 · feature/rag-transplant 는 rc0 · DA aifp 4096 R1).
- 쓰기 자리: 새 나노 worktree(feature/rag-transplant 에서 갈라진 것) 하나뿐 · 산출 = `<나노 worktree>/.fable-team/state/airag/detector-s0s1-plan.sh`(state 폴더 = ignore · 나노가 폴더를 만든다)
- 읽기 출처(쓰기 0): /Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant — 기존 rag-transplant worktree 는 읽기만 한다. state 파일(opread-rh-terminal-test.sh · tcc-log-20261018-0945.txt)·발주문 전문은 가지 미추적이라 새 worktree 에 없다 → 이 절대경로에서 읽는다
- 상태: 대기 · 2026-11-05 airag master#10 작성 · 2026-11-12 정본 꼴 재작성(aifp-ft-arch-pi#1 · aifp 4093 · r1410 실사건 선행)
- 설치: 없음 — 계획 파일 1개(state 폴더 · ignore 대상) · 사람 실행은 ft-hil h
- 정본 영향 없음: 정본 판정표(arch-20261028-appreg.md §4)는 바꾸지 않는다 · 계획 파일만

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
airag 골 원장(design/aifp/GOAL-LEDGER-airag.md) A03 / 닫는 증거(원장 복붙): 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 · 골의 축: A03 C12 — 안 B 카드 2 «탐지기 S0·S1»: 앱 시험(h-A·h-B) 기대값을 정하는 터미널 시험 계획 파일. 이 카드의 증거 = 계획 파일 bash -n · 점검 집계 줄 원문 · 판정표 행.

## 배경 (한 단락)
원래 골(airag 원장 · 발주문 첫 줄): «최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.» 위 «골 원문» 3줄은 aifp 팀 env 의 골(r1410 · 하네스 골)이라 lint 가 요구하는 문면이다. 안 B 는 앱 시험 전에 터미널에서 같은 판정을 먼저 재는 계획 파일이 필요하다. 정본 = arch-20261028-appreg.md §4(탐지기 · S0 기준 · S1 판정 · 집계 칸 · 결과 판정표) · 안 B 문서 arch-20261029-appB.md §5 «전제»·§7 카드 2.

## 구현 범위 (나노 1 · 쓰기 = 새 나노 worktree · 읽기 = rag-transplant worktree)
- 산출 1개(쓰기): `<나노 worktree>/.fable-team/state/airag/detector-s0s1-plan.sh`(사람이 `! bash /tmp/h<N>` 한 줄로 돌린다)
- 재사용(읽기만): /Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/.fable-team/state/airag/opread-rh-terminal-test.sh(10-18 R-H 터미널 시험 · 값 1비트·TCC 집계·OPPROBE_DRY 점검 모드) + §4 의 `sandbox-exec` 탐지기(기본 허용 + `~/Library/Group Containers`·`~/Library/Containers` 읽기·쓰기 거부)와 Sandbox deny 줄 집계
- 정본 읽기(읽기만 · 같은 파일이 나노 worktree 에도 있음): /Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag/docs/artifacts/arch-20261028-appreg.md §4 · /Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag/docs/artifacts/arch-20261029-appB.md §5·§7

## 계약
1. 값(키·토큰) 출력·기록 0. 값은 «64자 hex 형식 여부» 1비트만.
2. 각 op 호출 `timeout 10.5`(로컬 도구 · 판정 4114 로컬 25초 이내) · `log show` 각 45초 이하 · 전체 70초 이하 목표 · 넘으면 구간을 나눈다.
3. 집계 줄(구간별): Sandbox op deny 줄 수 · TCC op AppData/AllFiles 줄 수 · PROMPTING 줄 수 · rc · 형식 통과 1비트 · op-home 아래 `.config/op` 사용 1비트. 끝 줄 1개 = 판정표의 «행 이름» 만(판정은 master).
4. 어느 구간이든 PROMPTING ≥ 1 이면 즉시 중단 메시지.
5. 하지 않는 일: launchctl·plist·runtime.json·설치본·DB 변경 0 · 대화형 입력 0 · 임시 파일은 끝에 지움 · HOME 은 op 자식에만.
6. 점검 모드 `OPPROBE_DRY=1`: op·토큰 읽기·log show 0. 정본 로그 사본(`.fable-team/state/airag/tcc-log-20261018-0945.txt`)과 가짜 Sandbox deny 줄로 집계 로직 확인 · `bash -n` 통과.

## 범위 밖
- 실제 op 호출·실제 log show·sandbox-exec 실제 실행(점검 모드 밖) · 앱 실행·설치 · feature-pack 아래 코드 변경 · push · DA 소환 · 커밋(state 폴더는 ignore 대상 · master 가 등록)

## 완료 조건
1. [x] .fable-team/state/airag/detector-s0s1-plan.sh + bash -n — 나노 끝선 aifp 3535 «bash -n rc 0» · 2026-11-12 재대조: rag-transplant worktree 같은 파일(18185B · sha1 b6577ecce8e3) bash -n rc0
2. [x] OPPROBE_DRY=1 점검 결과 집계 줄 원문(걸린 초 포함) — aifp 3535: rc 0 · 걸린 초 0.0(벽시계 0.16) · 'sample: … Sandbox op deny=2(GroupContainers=1 Containers=1) | TCC op AppData=1 AllFiles=6 PROMPTING=1 | op요청 7건 분포={AllFiles/preflight=yes:6, AppData/preflight=no:1}' · 행 이름 9건 ok · 기대값 일치=True
3. [x] master 가 ft-hil.sh --add → 사람 한 줄 → 판정표 행 — h9 오빠 실행 2026-11-07 08:08 rc 0 · 16.9초 · /tmp/h9.out 끝 줄 '행 이름: S0 deny 0'(S0·S1 모두 Sandbox deny 0 · PROMPTING 0) · 판정표 = arch-20261028-appreg.md §4 69행 «S0 deny 0 → 판정 불가» · planner arch#43 판정 «h9 = 판정 불가 · 안 B 경로 그대로 · h-A·h-B 막지 않음»(state/team-main/airag/verdict-h8-h9-h10-arch43-20261107.md:12·32-37) · 사실 팩 facts-h8-h9-20261107.md §h9 · CLOSEOUT origin/main 433c2216 design/aifp/CLOSEOUT-airag-20261109.md:23 «판정 불가 확정 · 끝 줄 3 채움 → 완성»
- 나노 끝선(5줄 이내): 계획 파일 경로 + bash -n 결과 · 점검 모드 집계 줄 원문·초 · 정본 판정표와 다르게 해석한 점(없으면 «없음») · 사람 실행 예상 초

## 계약↔시험 대응표
| 계약 | 시험 |
|---|---|
| 1 값 출력 0 · 1비트만 | 점검 모드 출력에 64hex 문자열 0(grep) |
| 2 시간 상한 | 계획 파일의 timeout 값 대조 · 점검 모드 걸린 초 |
| 3 집계 줄 꼴 | 점검 모드 집계 줄 원문 |
| 4 PROMPTING 중단 | 가짜 PROMPTING 줄 1개 넣은 점검 → 중단 메시지 |
| 5 하지 않는 일 | 계획 파일에 launchctl·plist·runtime.json 쓰기 0(grep) |
| 6 점검 모드 | OPPROBE_DRY=1 실행 rc0 · bash -n rc0 |

## 상태
- 2026-11-05 · airag master#10 카드 작성(대기)
- 2026-11-12 · 정본 꼴 재작성 — aifp-ft-arch-pi#1(aifp 4093 · harness#207 4092 · r1410 실사건 선행) · 내용·범위 = 원래 카드 3줄 + 발주문 전문의 계약·금지·끝선 그대로 옮김 · 새 범위 0
- 2026-11-12 · DA REJECT 보정(aifp 4096 R1) — aifp-ft-arch-pi#2 · base = feature/rag-transplant 필수 · 쓰기 = 새 나노 worktree · rag-transplant worktree = 읽기 출처만
- 2026-11-12 · 끝 줄 1·2·3 원래 증거 대조·기입(aifp-ft-arch-pi#2 · aifp 4119 · DA 4116 상태 의견) · 나노 새로 열지 않음(재작성 0) · 다음 = DA 닫힘 판정문 → 완성 이동
