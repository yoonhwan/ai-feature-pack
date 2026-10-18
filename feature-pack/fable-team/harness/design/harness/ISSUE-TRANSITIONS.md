# Issue 전이표 5 + Closes 규약 + close 5항 + reopen (C4)

> 정본: `issue-improvement/MERGED-20261005.md` §4 C4 · `DESIGN-harness-composition-20261005.md` §3-6 3 · 골 축: 하네스 GOAL 표 A(이상 1건 = Issue 1건 · 검토).
> **이 문서는 설계 파일이다 — GitHub 라벨 생성·삭제·변경은 하지 않았다**(외부 상태 변경). 아래 매핑은 소유 오케 확인 뒤 별도 승인으로 집행한다.

## 1. 상태 라벨 5 (현행 `status:*` 11개 → 5개)

| 번호 | 상태 라벨 | 뜻 | 현행에서 오는 것 |
|---|---|---|---|
| S1 | `status:needs-triage` | 접수 — 아직 배분 전 | needs-triage · research-needed · da-validation-needed · evidence-needed · needs-repro |
| S2 | `status:ready-for-dev` | 배분됨 — 소유 오케 확정, 착수 전 | ready-for-dev · blocked-no-seat(+`phase:hold`) |
| S3 | `status:in-progress` | 소유 오케가 카드 분해·나노 작업 중 | in-progress · blocked(+`phase:hold`) |
| S4 | `status:needs-review` | 랜딩 PR(Closes #N) 올라감 · 검증 대기 | needs-review |
| S5 | `status:done` **(신규 1개)** | close 뒤 5항 대조 통과 | — |
| 수식 | `status:observing` **(신규 · R102)** | 관찰 중 — 원인 미확정·같은 증상 보류라 닫기를 거절한 상태 · 서로 다른 판 2회 재현 0 뒤에야 close(§3) · 상태 5개를 늘리지 않는 수식 | — |

전이(누가 · 닫는 사건):

| 전이 | 집행 손 | 닫는 사건 |
|---|---|---|
| S1→S2 | issue-manager | 배분 쌍(Issue 코멘트 「소유 오케=<세션명>」 + mbox) |
| S2→S3 | 소유 오케 | 카드 분해 후 첫 나노 spawn |
| S3→S4 | 소유 오케 | 랜딩 PR 생성(본문 `Closes #N`) |
| S4→S5 | issue-manager | PR 머지로 close → `ft-issue-close-check.sh <N>` exit 0 |
| S4/S5→S3 | 소유 오케(+reopen) | check exit 1 또는 회귀 → §4 reopen |

막힘은 상태가 아니라 **`phase:hold` 수식**이다(5상태를 늘리지 않는다).

## 2. Closes 규약

- 랜딩 PR 본문 첫 줄 `Closes #N`(`.github/PULL_REQUEST_TEMPLATE.md`). 여러 Issue 면 줄마다.
- 소유 = 그 Issue 를 받은 메인 오케(오빠 Q1) · 나노는 Issue 번호를 몰라도 된다.
- 연결 여부는 `closedByPullRequestsReferences` 로 읽는다 — 목표: 메인 오케가 받은 Issue 의 Closes 연결률 ≥ 80%.

## 3. close 완료 8항 (Issue 코멘트에 「항목: 값」 줄 · 값이 비거나 `<…>` 자리표시면 미기재)

| 항 | 값 예 |
|---|---|
| 닫는 사건 | 재현 스텝 PASS 증거 한 줄 |
| PR | `#N` 랜딩 PR |
| 재현 PASS | repro-e2e 코멘트·sha |
| 정리 | 워크트리·나노 세션 정리 확인 |
| 기록 | CLOSEOUT·LOOP-LEDGER 경로 |
| 기준값 대비 | baseline 코멘트 값 → 같은 세트로 다시 잰 값(없으면 「없음 → 대체 축」) — `BASELINE-TEMPLATE.md` (C20 · `ft-issue-close-check.sh` 5항 검사는 무변경) |

| 원인 확정 (7) | `원인 확정: Y — <근거 ≥10자>` (R102 · 판정 1059) |
| 같은 증상 보류 (8) | `같은 증상 보류: 0` (보류가 있으면 `같은 증상 보류: <경로>[, <경로>]`) |

7·8항은 키로 «가장 마지막 줄»을 먼저 고른 뒤 그 줄만 검증한다(수리 뒤 새 닫는 코멘트의 Y·0 이 옛 N·보류를 덮는다 · 마지막 줄이 비었거나 `<…>` 면 앞 줄로 내려가지 않고 빈 칸). 빈 칸·`원인 확정: N`·보류 0 아님이면 Tank 래퍼 `close`(completed)가 닫지 않고 «관찰 중»(코멘트 마커 `관찰 시작:` + 라벨 `status:observing`)으로 둔다 — `scripts/fable-team-bin/ft-issue-close-gate.sh`(`--reason not-planned` 는 게이트 생략).
관찰 중 이슈의 close 조건 = 현재 구간에서 «서로 다른 판(sha) 2회 재현 0»: 이슈 코멘트에 `관찰: 판=<40hex> · 결과=재현 0 · 판정=<번호>` 2줄(판이 서로 달라야 함 · `재현 있음` 1줄이라도 있으면 거절 · 수리 랜딩 뒤 `관찰 시작: <UTC> · 수리 랜딩=<40hex>` 로 새 구간). 해제는 planner 값 뒤 `관찰 해제: 판정=<번호>`. 관찰 조건으로 닫을 땐 7·8항을 사실대로(N·보류 허용).

검사: `scripts/fable-team-bin/ft-issue-close-check.sh <Issue#>` (읽기 전용 · exit 0 통과 / 1 미비 / 2 조회 실패). 미비면 issue-manager 가 소유 오케에 1통. close 전 게이트 = `--gate`(7·8항+관찰 조건만 · exit 0 / 3).

## 4. reopen

`scripts/fable-team-bin/ft-issue-reopen.sh <Issue#> <랜딩sha>` — 기본 dry-run(명령만 출력), `--apply` 일 때만 실행. 동작: 원 Issue 재오픈 + `status:needs-review` 부여(`status:done` 제거) + 깬 랜딩 sha 역링크 코멘트. 소유 = 소유 오케.
PR 병합 자동 close 라도 7·8항이 FAIL 이면 그 틱에 재오픈 + «관찰 중»(마커 → 라벨)으로 둔다 — 판정 1060 · 판정 795(자동 close 재오픈 0)는 1~6항·Closes 만의 FAIL 에 그대로(사후 코멘트).

## 5. 현행 라벨 72 → 매핑 (누락 0 · 소유 오케 확인칸 ☐ = 확인 전)

| 현행 라벨 | 매핑 | 처리 | 확인 |
|---|---|---|---|
| `status:needs-triage` | S1 | 유지 | ☐ |
| `status:research-needed` | S1 | 대체 후 삭제 후보 | ☐ |
| `status:da-validation-needed` | S1 | 대체 후 삭제 후보 | ☐ |
| `status:evidence-needed` | S1 | 대체 후 삭제 후보 | ☐ |
| `status:needs-repro` | S1 | 대체 후 삭제 후보(재현은 repro-e2e 코멘트) | ☐ |
| `status:ready-for-dev` | S2 | 유지 | ☐ |
| `status:blocked-no-seat` | S2 + `phase:hold` | 대체 후 삭제 후보 | ☐ |
| `status:in-progress` | S3 | 유지 | ☐ |
| `status:blocked` | S3 + `phase:hold` | 대체 후 삭제 후보 | ☐ |
| `status:needs-review` | S4 | 유지 | ☐ |
| `status:hil-needed` | 상태 아님 → `hil:needed` | 대체 후 삭제 후보 | ☐ |
| `hil:needed` · `hil:approved` · `hil:rejected` | 축 hil(상태 5와 별개) | 유지 | ☐ |
| `decision:proceed-to-evidence` · `decision:ready-for-hil` · `decision:hold` · `decision:reject` | 축 decision(DA 판정 기록) | 유지 | ☐ |
| `type:bug` | 축 type | 유지 | ☐ |
| `type:feature` | 축 type | 유지 | ☐ |
| `type:research` | 축 type | 유지 | ☐ |
| `type:test-request` | 축 type | 유지 | ☐ |
| `type:pr-review-finding` | 축 type | 유지 | ☐ |
| `type:agent-ops` | 축 type | 유지 | ☐ |
| `type:task` | 축 type | 유지 | ☐ |
| `type:perf` | 축 type | 유지 | ☐ |
| `team:planner` · `team:v65` · `team:ccu` · `team:cfo` · `team:kk` · `team:shared-harness` · `team:harness-ops` | 축 team = 소유 1 | 유지 | ☐ |
| `scope:main` · `scope:direct` · `scope:satellite` | 축 scope | 유지 | ☐ |
| `phase:post-completion` · `phase:pre-completion` · `phase:hold` | 축 phase(완성 전/후 · hold 수식) | 유지 | ☐ |
| `priority:p0` · `priority:p1` · `priority:p2` | 축 priority | 유지 | ☐ |
| `size:small` | 축 size(매니저 직접 경로) | 유지 | ☐ |
| `source:user-report` · `source:hermes-e2e` · `source:sentry` · `source:trend-monitor` · `source:ai-review` · `source:community-research` · `source:feature-research` | 축 source(출처 기록) | 유지 | ☐ |
| `area:realtime` · `area:chatroom-v2` · `area:lecture` · `area:gateway` · `area:worker` · `area:frontend` · `area:infra` | 축 area | 유지 | ☐ |
| `epic:auth` · `epic:credit` · `epic:e2e` · `epic:guest` · `epic:deploy` · `release:v1.0` | 구 릴리즈 계획 라벨 | 유지(전이표 밖 · 소유 오케 판단) | ☐ |
| `bug` | → `type:bug` | 대체 후 삭제 후보 | ☐ |
| `enhancement` | → `type:feature` | 대체 후 삭제 후보 | ☐ |
| `documentation` | → `type:task` | 대체 후 삭제 후보 | ☐ |
| `question` | → S1 + 코멘트 | 대체 후 삭제 후보 | ☐ |
| `duplicate` · `invalid` · `wontfix` | close 사유(GitHub 기본) | 유지 | ☐ |
| `good first issue` · `help wanted` | 사용 0(단일 팀 리포) | 삭제 후보 | ☐ |
