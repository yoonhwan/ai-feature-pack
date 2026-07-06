# fable-team 검증 절차

## V1. 설치 검증 (install.sh 직후)

```bash
test -f ~/.claude/skills/fable-team/SKILL.md && echo SKILL_OK
ls ~/.claude/skills/fable-team/references/agent-templates/*.tpl | wc -l   # 기대: 11 (표준 5 + da-claude 대체 + 크루 5: omo/gstack/superpowers/insane-search/ouroboros)
```

## V2. 워커 프로브 (인터뷰 완료 후, 새 세션)

각 워커에 표준 질의 (orchestration-playbook.md §프로브). **경로 이원화 — Agent 프로브(checker/implementer/da/크루) + Workflow 프로브(planner/tester)**. probe 목록에 planner(기획 브레인)가 없으면 설치 미완:

| 체크 | 기대값 | 실측 근거 |
|------|--------|-----------|
| tools에 Agent/Task 없음 | ✅ | 서브의 서브 차단 |
| spawn_test | `NO_SPAWN_TOOL` | 워커가 직접 스폰 시도 후 보고 |
| 실제 모델 | 지정 모델과 일치 | `~/.claude/projects/<proj>/<session>/subagents/agent-*.meta.json`의 `model` |
| 금지 모델 | 워커 중 fable-5 없음 (planner 좌석 예외) | 동일 meta.json |

## V3. E2E 미니 사이클 (선택)

작은 버그 픽스처(예: 음수 미지원 mul)로 파이프라인 1회전:

1. checker → 버그 요약 JSON
2. planner(Workflow) → `DESIGN_WRITTEN <경로>` + 설계 파일 4섹션 존재
3. implementer(SendMessage) → `IMPLEMENTED` + 최소 diff
4. tester → `ALL_PASS`
5. DA → codex 헤더(`gpt-5.5/xhigh` 등) + `APPROVED`

기준: 오케스트레이터가 설계/판정 내용을 직접 쓰지 않고 완주하면 PASS.

## V4. 실패 모드 재현 (지식 확인)

- ultracode 세션에서 sonnet5 워커를 Agent 경로로 스폰 → `400 level "xhigh" not supported` 확인 (이게 Workflow 경로 분리의 근거)
- codex를 `< /dev/null` 없이 백그라운드 실행 → hang 확인 (권장하지 않음, 문서로 대체 가능)

## V5. fable-in/out 동등성 비교

fable 보유 환경에서 planner/오케스트레이터 모델 override로 fable-out 구성(P1+O1 또는 P2+O2)을 강제 재현 → 두 구성을 같은 픽스처로 비교. 기록처 = `.fable-team/state/v5-equivalence/` — `results.md`(케이스 판정 원장 · E5 재개 SSOT · E7 해시 기록처 — 판정 확정마다 write-through), `fixtures/`, `runs/<in|out>/`.

### 케이스 표

| 케이스 | 시나리오 | 측정 지표 | PASS(동등) 기준 | 실행·판정 |
|--------|----------|-----------|------------------|-----------|
| **E1** E2E 완주 | V3 미니 사이클(음수 미지원 mul 픽스처) 양 구성 각 1회 | 무개입 완주 + 단계 산출물 실재(checker JSON·design-v1·impl-round1·tester ALL_PASS·da APPROVED) + 오케스트레이터 직접 판단 0회(기계 판정 — 금지 regex 3종) | 양 구성 완주 && 산출물 세트 동일 && 금지 패턴 grep 0건 | 표준 파이프라인. 산출물 존재 체크 = checker. **"직접 판단 0회" 기계 판정**: 오케스트레이터 transcript를 금지 regex 3종(R1 판정 자체 생성 `^(VERDICT\|SPOT): (APPROVED\|CHANGES_REQUESTED)` — 인용 프리픽스 `>` 제외, R2 설계 헤더 `^# Design:\|^## (원인 분석\|해결 설계\|확정 설계)`, R3 diff 블록 `^```diff\|^diff --git\|^@@ -[0-9]+`)으로 검사. 정상 릴레이 픽스처로 오탐 0 자가검증 후 고정. 양 구성은 **격리 픽스처 사본**(코드 원상 + 빈 `.fable-team/`)에서 각각 완주 |
| **E2** 재기획 크로스오버 복원 | context-management 검증 시나리오 7의 state 픽스처 주입(v2 검토 CHANGES_REQUESTED 후 사망) → 복원 | 복원 분기 선택·카운터 승계·형상 게이팅 준수 | 양 구성 모두 **stage 2** 선택 && 카운터 diff 0 | 각 구성의 오케스트레이터 세션이 직접 복원 수행. 픽스처 = 사전 제작 고정 `.fable-team/` 트리(양 구성 동일 바이트 — fixtures/ 보관본 주입). 카운터 판독 = 복원 재개 보고 직후 `state/<slug>.state.md` frontmatter 3종(da_round 1·planner_rounds 2·respawns 원값) vs 주입 픽스처. stage 2 선택 증거 = state.md stage 값 + 이벤트 로그 |
| **E3** DA loop 등가 | 경계조건 누락을 심은 v1 구현 고정 → 재기획→재구현→재판정 루프를 planner만 교체해 실행(DA=codex xhigh 양 구성 공통) | DA 라운드 1 판정 일치율 + 라운드 수·판정 시퀀스(CR→APPROVED) | 라운드 1 판정 동일 && 시퀀스 동일 && 총 라운드 수 차 0(한도 2 내) | 파이프라인 stage 2~5. 라운드 1 입력은 **공용 고정 픽스처**로 양 구성에 주입. 사전 등록 정답 = 라운드 1 CHANGES_REQUESTED. 양 구성 판정 불일치 = **실험 무효**(픽스처 결함 회귀, 1회 재실행) |
| **E4** 설계 품질 루브릭 | 동일 checker JSON 입력으로 양 planner가 각각 설계 파일 생성 → 블라인드 채점 | 8점 루브릭: 원인 깊이(0/1/2) · 대안 기각 근거(0/1/2) · 검증 시나리오 수(0/1/2) · 지시 구체성(0/1/2) | 대체안 점수 ≥ fable 점수 − 1 | 채점자 = codex xhigh, 블라인드(순서 교차). 증거 인용 JSON 체크리스트 필수 — 무증거 항목 = 0점. 동점·경계(±1)면 제2 채점자(sonnet-4-6 high) + 증거 인용 개수 tie-break. blind 유지 = 무작위 라벨 `A.md`/`B.md` 사본, 구성 토큰 grep 0건 기계 확인, 순서 교차 2회 채점 평균 |
| **E5** 실험 중단 복원 | E1 판정 확정·E2 진행 중 상태에서 강제 종료 → 새 세션에서 V5 재트리거(스테이지드 주입: 결과 원장에 E1 판정 + E2 진행 마커 기입 픽스처) | 결과 원장 기반 재개 — 완료 스킵·진행 재개 | E1 재실행 0회 && E2 재개·완주 && 재개 후 원장 최종 판정 diff 0 | 성립 전제 = 케이스 판정 확정마다 결과 원장 write-through |
| **E6** 프로브 4상태 전이 (A3) | §1-1 분류 4상태 각각 강제: ⓐ high 성공 ⓑ 400 `level ... not supported` ⓒ model-unavailable ⓓ rate-limit 픽스처 | 상태 분류 결과 + 후속 사다리 조치 | 4상태 오분류 0 && 조치 일치: ⓐ 확정 ⓑ medium 강등 재시도 ⓒ 사다리 하강(강등 금지) ⓓ 보류·재시도(강등·하강 금지) | ⓐⓒ 라이브, ⓑⓓ 분류기 픽스처 검증. **E1~E4에 선행 실행** |
| **E7** 지연 Write 덮어쓰기 검출 | 게이트 승인·E4 채점 확정 시 설계 파일 sha256을 결과 원장에 기록 → stale 덮어쓰기 의도 주입 → 재해시 대조 | 해시 불일치 검출 + 차단·에스컬레이션 | 불일치 검출 && 오염본 소비 0회 | 해시 가드는 V5 실험 절차 내 규정(파이프라인 전반 승격은 미결) |
| **E8** 하네스 교차 재검증 (D5) | 하네스 프롬프트 2종(완화형·지침형) 고정 픽스처 + E2 복원 시나리오를 3셀에 투입 — **필수** ① fable-5/완화형 ② opus/지침형, **진단** ③ opus/완화형 | 절차 위반 건수(E1 금지 regex 3종 + E2 stage 판정) | 필수 셀 둘 다 위반 0 = PASS. 진단 셀은 기록 전용(배정 규칙 지침형 유지) | 탁상 시뮬 선행. D5 재검증 규범: 완화형 기준 산물은 opus/지침형 PASS 없이 투입 금지 |
| **E9** 런타임 지침 로드·전환 (D5b) | 하네스 프로파일 2종 × 모델 × 로드방식 **전체 8셀**: 시작 로드 S1~S4 + 런타임 주입 R1~R4. 전환 시 `[HARNESS:SWITCH]` 마커 | ① 지침 준수율(C1~C6 6항/6) 비교쌍별 ② 8셀 완주 ③ 오염(구 프로파일 마커 grep) | ② 8셀 전부 완주(필수 전제) && ③ 오염 0 && ① 비교쌍별 차 ≤ 1항. 런타임 주입 하락 시 "전환 = 세션 재시작 필수" 확정 | 사전등록 `fixtures/e9-preregistration.md`에 C1~C6 패턴·마커·산식 등록 후 고정. 결과 = §2-4 배정 규칙 유지/개정 입력 |

### 종합 판정 규칙

- **E1·E2 PASS = 기능 동일성(필수)** — 하나라도 FAIL이면 디폴트 부적격, 설계 결함으로 회귀.
- **E3·E4까지 PASS = "동등" 등급.** E4만 미달 = "기능 동등·품질 열세" — 사다리 하향의 알려진 비용으로 설치 고지문에 명기.
- **E5~E9(견고성·하네스)는 등급 산정과 독립** — FAIL은 해당 메커니즘 결함으로 회귀·수정 후 재실행(단 E6 FAIL = fable-out 구성 확정 불가 → 전 케이스 중단).

### 실행 순서

E6 선행(fable-out 구성 확정 의존) → E1 → E2 → E3 → E4. E5·E7·E8·E9는 스테이지드 픽스처·탁상 시뮬 기반이라 E3·E4와 병렬 가능(E8·E9 라이브는 최소 회차). 조기 중단: E6 FAIL → 전 케이스 중단 / E1 FAIL → 나머지 스킵 / E2 FAIL → E3·E4 스킵.
