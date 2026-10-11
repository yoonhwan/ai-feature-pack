# 인덱스: 이슈 닫기 게이트 — 원인 확정·같은 증상 보류 2칸 + 래퍼 close 거절 → «관찰 중» (R102 · 판정 1059·1060 · arch#28)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 요청 원장 R102(planner#26 쪽지 #75789 · 오빠 「하네스마스터 분석 개선요청」) · 분석 보고 design/harness/REPORT-g922-reopen-why-20261011.md
- 제안서: 없음 — 오빠 판정 1059 로 착수 승인된 하네스 내부 요청 R102(분석 보고 REPORT-g922-reopen-why-20261011.md · 판정 1060)
- 상태: 대기
- 선행: 없음 · 설계 = `git show 5147ca9c79:design/harness/PLAN-r102-close-gate-20261011.md`(DA APPROVE #75885 · 최종본 — ★나노 워크트리(origin/main)에는 이 파일이 없다 · 위 명령으로 읽는다★)
- 시험 입력: 임시 git 저장소 + `--from-json` 상태 파일 + 가짜 쓰기 스텁(상태 파일에 코멘트·라벨 추가) — 실 gh 호출·실 Issue 쓰기·루트 `.fable-team/` 쓰기 0
- 기준값(arch#28 실측 · 2026-10-11): #922 ClosedEvent actor=byz-tank · closer=없음(PR 아님) → Tank 래퍼 `close --apply` 가 아무 검사 없이 닫음. origin/main `ft-gh-as-tank.sh` 199줄 · `ft-issue-close-check.sh` 83줄(6항 · close «뒤» 사후 검사). 라이브 `<루트>/.fable-team/bin/ft-issue-close-check.sh` = main 과 diff 0 · sha256 앞12 `1a97393e87cc`. 라벨 `status:observing` 없음.

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 B / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」 — 행 = R102 · 값 = 판정 1059(설계 지시)·1060(3차 DA 허가 · 자동 close 재오픈) · 반영 sha = 이 카드 랜딩 sha.
하네스 GOAL 표 C / 닫는 증거(정본 복붙): 「RELEASE-<ver>.md 1장 + 머신별 「반영됨 <machine> <sha>」 행 전부」 — 라이브 bin 설치는 랜딩 뒤 master 집행(아래 완료 조건).
골의 축: B(메인 오케 개선요청 접수·협의) + C(도구 업그레이드·설치).

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
#922(폰 물결 하단 흰 잘림)가 «오빠 폰 인수 PASS 1회 + 랜딩 번호»만으로 닫혔는데, 마감 문서에는 이미 «원인 미확정»과 «바닥 빈 띠 수정 보류»가 적혀 있었고 닫은 뒤 같은 자리가 재현돼 재오픈됐다. 구멍은 둘이다: ①닫는 6항이 «원인이 확정됐나»·«같은 증상의 보류 항목이 남았나»를 안 본다 ②Tank 래퍼(`ft-gh-as-tank.sh close`)가 아무 검사 없이 닫는다(close-check 는 닫은 «뒤»에만 돈다). 이 카드는 닫는 항목을 8항으로 늘리고(7 `원인 확정: Y — <근거 ≥10자>` · 8 `같은 증상 보류: 0`), 래퍼 close 직전에 게이트를 돌려 두 칸이 비었거나 N·보류면 닫지 않고 «관찰 중»(코멘트 마커 + `status:observing` 라벨)으로 둔다. 관찰 중인 이슈는 «오빠 폰에서 서로 다른 판(sha) 2회 재현 0»(코멘트 `관찰: 판=<40hex> · 결과=재현 0 · 판정=<번호>` 2줄)이어야 닫힌다. 세부 규칙(마지막 줄 선택→검증 · 쓰기 순서 보존→마커→라벨 · fail-closed · pending · epoch 4조건 · 단계별 token · 7초+재시도 1 · 결과 불명 중복 방지)은 PLAN §1~§3 이 정본이다 — 카드와 PLAN 이 다르면 PLAN 이 이긴다.

## 사전검증
- 소환: 예 — DA byz-harness-da-codex#1 r1 HOLD #75853 · r2 HOLD #75868 · r3 APPROVE #75885(판정 1060 허가 3차) — arch 서명 byz-harness-arch-claude#28
- 조사 근거: origin/main `scripts/fable-team-bin/ft-gh-as-tank.sh`(close 분기 · case 끝 `esac`) · `scripts/fable-team-bin/ft-issue-close-check.sh`(6항 · `canon_lines`) · `design/harness/ISSUE-TRANSITIONS.md` §3·§4 · `.github/PULL_REQUEST_TEMPLATE.md` 「완료 6항」 · `tests/harness/test_issue_close_canon.sh`(시험 꼴)
- 7초 룰 점검(판정 666): 외부 호출 = gh issue view(`timeout 7` + 재시도 1) + 거절 apply 때 래퍼 쓰기 최대 3회(각 `timeout 7 bash ft-gh-as-tank.sh … --apply` + 재시도 1 · 재시도 전 token 확인). 래퍼 내부 기존 gh 호출 7초화는 범위 밖(별도 [structure] 카드).

## 구현 범위 (닫힌 목록 · 나노 · PLAN §7 순서 · 한 번에 하나)
1. ①시험 빨강 먼저 — 새 `tests/harness/test_issue_close_gate.sh` + `tests/fixtures/issue_close/gate-*.json` + 스텁 `tests/harness/stubs/fake-tank.sh`. PLAN §4 표 ①·①b·②·③·④·⑤(a)~(j)·⑥·⑦ 전부. 이 단계 커밋에서 새 시험 rc≠0 확인(빨강).
2. ②`scripts/fable-team-bin/ft-issue-close-check.sh` — PLAN §2-1 표 1행(①~⑥) + §3. 기존 1~6항·Closes 검사 무변경. 기존 PASS 픽스처 3개(`closed-with-6items-canon.json`·`closed-with-6items-no-impact.json`·`closed-partial-two-sha.json`)에 7·8 줄 추가(기대값 무변경).
3. ③새 `scripts/fable-team-bin/ft-issue-close-gate.sh`(PLAN §2-1 표 2행 · §2-2 문장 그대로 · §2-3 · env `FT_TANK_WRAPPER`·`FT_CLOSE_CHECK_FROM_JSON` 시험 훅) + `ft-gh-as-tank.sh` ★1줄★(PLAN §2-1 표 3행 그대로 · case 끝 `esac` 바로 뒤 · 199→200줄 · 그 밖 변경 0).
4. ④문서 2: `design/harness/ISSUE-TRANSITIONS.md` §1 라벨 표에 `status:observing` 1행 · §3 제목·표 «완료 8항»(7·8 2행 + 관찰 줄 모양) · §4 reopen 에 1줄(PR 병합 자동 close 라도 7·8항 FAIL 이면 재오픈 + 관찰 중 — 판정 1060 · 795 는 1~6항·Closes 만의 FAIL 에 그대로). `.github/PULL_REQUEST_TEMPLATE.md` 「완료 6항」→「완료 8항」 2줄 + 1줄(«원인 미확정·같은 증상 보류가 있으면 `Closes #N` 대신 `Refs #N`»).
5. ⑤미러: `scripts/harness-install/fable-team/bin/` 의 `ft-issue-close-check.sh`·`ft-issue-close-gate.sh`·`ft-gh-as-tank.sh` = fable-team-bin 과 `cmp` 0.

커밋은 자기 브랜치(단계별 · [test]→[feature]→[docs] · 구조·행위 분리), **push 금지**. **금지**: 실 gh 쓰기·`--apply` 실행 · 라벨 생성 · 루트 `.fable-team/` 쓰기 · #922 에 어떤 쓰기도 · graphics#4 의 #922 수리 파일(웹·물결·캔버스·스타일) 접촉 0 · 위 목록 밖 파일 수정 0.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_issue_close_gate.sh` rc=0 · `bash tests/harness/test_issue_close_canon.sh` rc=0 · `bash tests/harness/test_gh_as_tank.sh` rc=0 · 새·바뀐 sh 전부 `bash -n` · 미러 3쌍 `cmp` 0 · `ft-gh-as-tank.sh` 줄 수 200.
- 카드 증거 줄(«세트:» 로 시작 · 접두 없음): 세트: <40hex> · 시험: bash tests/harness/test_issue_close_gate.sh rc=0 · bash tests/harness/test_issue_close_canon.sh rc=0 · bash tests/harness/test_gh_as_tank.sh rc=0 · 이슈: 0
- 루트 지침: 완료 그 턴에 증거 줄 + arch#28 에 `[완료·휴식]` 1통(세트 sha 실재 확인 뒤).
- ★랜딩 뒤 master 집행(앞 단계 값이 다르면 멈추고 보고)★: DA⑥ → PR → CI 확인 → 병합(별 명령) → 라이브 설치(PLAN §6): `<루트>/.fable-team/bin/ft-issue-close-check.sh` cp 전 sha256 앞12 `1a97393e87cc`(다르면 cp 0 · arch 반송) → `.bak-r102-<UTC ts>` 백업 → origin/main 본 cp + cmp · `ft-issue-close-gate.sh` 신규 cp + chmod → 라벨 1회 `ft-gh-as-tank.sh label-create status:observing --color FBCA04 --description "관찰 중 — 서로 다른 판 2회 재현 0 뒤 close (R102)" --apply` → 라이브 사본으로 ③ dry-run rc 0 · ② rc 3 → issues master 에 «Tank 래퍼·gate·close-check 3개 재추출 + 닫는 코멘트 8항·관찰 줄·수리 랜딩 마커 모양» 1통 → 배포 공지(슬랙) → 요청 원장 R102 닫힘.

## 상태
- base_sha: 9d09c54fe51b830158978549213720216c34a1de (spawn 2026-10-11)
- base: origin/main 9d09c54fe51b830158978549213720216c34a1de (arch#28 카드 작성 시점 · spawn 때 `--base origin/main` 으로 다시 고정)
- 2026-10-11 — 대기/ 생성 (byz-harness-arch-claude#28 · R102 · 설계 PLAN 5147ca9c79 · DA APPROVE #75885).
- 정본 영향: 하네스 키트 close-check·gate·래퍼 3쌍 · ISSUE-TRANSITIONS · PR 템플릿 · 설치본 1(+신규 1) · 홈 정본 0.

## 결과
- 세트: d2ff250ebd702758116b76a2b850d41e8b3cd90f · 시험: bash tests/harness/test_issue_close_gate.sh rc=0 · bash tests/harness/test_issue_close_canon.sh rc=0 · bash tests/harness/test_gh_as_tank.sh rc=0 · 이슈: 0
정본 영향 없음: 제품 정본(docs/architect) 변경 없음 — 하네스 키트 3쌍·ISSUE-TRANSITIONS·PR 템플릿만(15b8920236)
- 2026-10-11 21:46 — 대기→진행 · 좌석 byz-harness-nano-r102-issue-close-gate#0
- 2026-10-11 22:50 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§117
