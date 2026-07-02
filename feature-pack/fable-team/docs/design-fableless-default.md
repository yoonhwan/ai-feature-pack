# fable-less 디폴트 설계 — fable 부재 환경의 기본 구성 사다리

> 2026-07-03 · planner 산출. 목적: fable-5가 없는 환경(팩 일반 배포·타 계정·모델 미출시)에서 **최대한 동일한 품질·동작**으로 fable-team이 돌아가는 기본값 확정. fable 보유 환경은 영향 0 — 사다리의 최상단이 현행 구성 그 자체다.

## 1. 원인·요구 분석

- 현행 팩은 두 좌석이 fable에 묶여 있다: ① 오케스트레이터 = "ultracode 지원 최상위 모델(fable5 등)" (SKILL.md 역할 분리 표·허들 1) ② planner 브레인 = fable5 max (install-interview §2 기본값).
- brain-availability §2에 planner 대체 행이 이미 있으나 ① 세대 구식(1순위 opus-4-6, opus-4-8 미반영) ② planner 좌석의 "의도적 max 예외"(SKILL.md 허들 2)와 불일치(sonnet-5 **high**로 표기) ③ 오케스트레이터 대체 행 부재. **이 표가 확장의 자연 착지점**이다.
- 설계를 결정하는 관찰 3개:
  1. **오케스트레이터는 판단하지 않는다**(역할 분리 설계) → 모델 하향의 영향은 절차 준수 신뢰성(복원 §4·라운드 디스패치·형상 게이팅)에 국한. 품질 방어 우선순위 = **planner > DA > 오케스트레이터**. 가용 최상위 모델은 planner 좌석에 우선 배정한다.
  2. **ultracode는 '요건'이 아니라 '최상단 품질 설정'** — 허들 1의 본질은 ⓐ Workflow 오케스트레이션 가용 ⓑ 세션 최대 effort다. Workflow 호출은 스킬 지시에 의한 opt-in으로 충족되므로 ultracode 세션 없이도 가능. 스폰 경로 분리(planner effort 명시)는 전 단에서 유지 — 비-ultracode 세션의 함정은 400 즉사가 아니라 **무증상 effort 다운그레이드**(Agent 상속 = 세션 effort)다.
  3. **DA(codex gpt-5.5 xhigh)는 fable 부재와 독립** — fable-less에서 유일하게 남는 xhigh 브레인 = 품질 백스톱. 중요도가 '높음→치명적'으로 승격된다.
- effort 실측 제약(준수): claude-5 계열(fable-5/sonnet-5) = low/medium/high/max, xhigh 없음(워커 표준 high, planner 좌석만 의도적 max). **opus 계열 상한은 미확정**(과거 단서 "opus는 high까지") → 설치 프로브로 실측하는 절차로 설계. codex = xhigh 가능.

## 2. 대안 사다리

### 2-1. 오케스트레이터 (세션 모델 + effort)

| 단 | 모델 | effort | Workflow/ultracode 요건 충족 |
|----|------|--------|------------------------------|
| **O0 (현행)** | fable-5 | ultracode(xhigh) | 현행 그대로 — 변경 없음 |
| **O1** | opus-4-8 | ultracode 수락 시 유지, 미수락 시 프로브 실측 상한(기대 high) | Workflow 도구 존재 확인 — 스킬 지시 호출이 opt-in 충족 |
| **O2** | sonnet-5 | max (claude-5 유효 상한) | 동일 |
| 폴백 | 어느 단이든 Workflow 도구 부재 세션 | — | planner/tester 스폰을 **미들웨어 드라이버 서브에이전트 경유 `claude -p`**(SKILL.md 스폰 경로 3행 — 드라이버 sonnet4.6 low가 Bash 실행·SendMessage 릴레이, 오케스트레이터 직접 발사 금지)로 전환 — 계약 동일(프롬프트 파일→설계 파일), 파이프라인 형상 불변 |

- planner와 동일 모델 겸직 허용 — 역할 분리는 모델 분리가 아니라 **계약 분리**(오케스트레이터 판단 금지)다.
- 기각: 4.6 계열·haiku 오케스트레이터 — 게이트 무결성이 절차 준수 신뢰성에 직결이라 하한을 sonnet-5로 둔다.

### 2-2. planner 브레인

| 단 | 모델/effort | 경로 | 비고 |
|----|-------------|------|------|
| **P0 (현행)** | fable-5 / max | Workflow | 변경 없음 |
| **P1 (추천 1순위)** | **opus-4-8 / 프로브 상한(max 시도→400 시 high)** | Workflow(model/effort 명시) 또는 미들웨어 드라이버 경유 `claude -p` | 비-fable 최상위 tier. 금지 규칙 예외의 일반화 필요(§5-B2) |
| **P2** | sonnet-5 / **max** | Workflow | 기존 표의 high를 max로 교정 — planner 좌석은 허들 2의 "의도적 max 예외"에 해당 |
| **P3** | opus-4-6 / max | Workflow | 계정에 4-8 부재 시 구세대 폴백 |

기각 옵션과 근거:
- **codex gpt-5.5 xhigh를 planner로** — 기각. ① DA 브레인과 동일 프로바이더가 되어 planner-게이트 축에서 **author-review 분리가 붕괴**(같은 모델의 맹점이 게이트를 통과 — brain-availability §2가 DA 대체에서 경계하는 원리와 동형) ② fable-less 환경일수록 codex 가용성 자체가 변수라 디폴트 부적격 ③ codex가 가용하면 그 xhigh는 DA 좌석(검증 게이트)에 두는 편이 전체 품질에 유리. planner=codex는 DA를 claude로 스왑해 분리를 복원하는 **명시적 opt-in 구성**으로만 허용.
- **sonnet-5를 1순위로** — 기각. 두뇌 좌석은 tier 우위(opus-4-8)가 세대 우위보다 우선 — 원인 분석 깊이·대안 기각 근거 생성은 최상위 tier 격차가 크다. opus-4-8 미가용 계정에선 P2가 자동 승계.

### 2-3. 나머지 로스터 — 무변경

checker(sonnet4.6 low)·implementer(opus4.6 max)·tester(sonnet5 high)·DA(codex xhigh + 드라이버 sonnet4.6 low) 기본값과 기존 대체 행(brain-availability §2)은 그대로. **fable-less에서 DA=codex 유지가 품질 1번 지렛대**(§1 관찰 3).

## 3. 기본 베이스 크루 세트 (fable-less 보강)

원칙: **opt-in 골격·기본값 완전 불변** — 기본값은 전 크루 [추가 안 함] 그대로 둔다. §0에서 planner substitution이 기록된 설치(=fable-less)에 한해, 감지된 해당 크루의 opt-in 질문에 **`★ fable-less 추천` 배지 + 근거 1줄**을 표시할 뿐이다(선택은 전적으로 사용자).

| 크루 | fable-less 표시 | 추천 근거(배지 옆 1줄) |
|------|-----------------|------------------------|
| **omo** (A형) | **★ fable-less 추천** | 두뇌 공백을 타 프로바이더(OMX 위 Codex 스킬 레이어) 시각으로 보강 — planner 설계 산출물의 second-opinion 채널(`$analyze`). 재기획 라운드 품질 상향 |
| **insane-search** (B형) | **★ fable-less 추천** | 수집(stage 1) 심층화로 설계 **입력** 품질 상향 — 브레인 하향의 직접 보상은 "재료를 더 좋게" |
| gstack / superpowers / ouroboros | 배지 없음 (현행) | 두뇌 공백과 직교(검증·프로세스는 DA·파이프라인이 커버). 로스터 비대화 방지 |

- da는 크루가 아니라 필수 로스터 — fable-less + codex 미가용의 **이중 공백** 시엔 기존 DA 대체 행을 따르되, **planner 대체 모델과 동일 모델·동일 계열 금지**(author-review 분리 — planner=opus 계열이면 DA 대체는 sonnet/gemini 계열 우선, §5-A5) + 설치 고지에 "품질 열세 구성" 명기.
- 크루 계약(resume/inject·요약-후-fork·WINDOW_PRESSURE)·산출물 외재화는 crew-support.md 그대로 — **배지는 추천 표시일 뿐, 기본값·opt-in 계약 모두 무변경(기본값 변경 구현 금지)**.

## 4. 동일성 비교 평가 프레임 (fable-in vs fable-out)

실행 전제: fable 보유 환경에서 planner/오케스트레이터 모델 override로 fable-out 구성(P1+O1 또는 P2+O2)을 강제 재현 → 두 구성을 같은 픽스처로 비교. verify.md **V5**로 수록(§5-E). 커버리지: E1=통합, E2=오케스트레이터 절차, E3·E4=planner 품질.

| 케이스 | 시나리오 | 측정 지표 | PASS(동등) 기준 | 실행·판정 |
|--------|----------|-----------|------------------|-----------|
| **E1** E2E 완주 | V3 미니 사이클(음수 미지원 mul 픽스처) 양 구성 각 1회 | 무개입 완주 + 단계 산출물 실재(checker JSON·design-v1·impl-round1·tester ALL_PASS·da APPROVED) + 오케스트레이터 직접 판단 0회(**기계 판정** — 아래) | 양 구성 완주 && 산출물 세트 동일 && 금지 패턴 grep 0건 | 표준 파이프라인. 산출물 존재 체크 = checker. **"직접 판단 0회" 기계 판정(V5 고정 스펙)**: 오케스트레이터 세션 transcript(`~/.claude/projects/<proj-slug>/<session-id>.jsonl`의 assistant text)를 금지 regex 3종(grep -E, 행 단위)으로 검사 — R1 판정 자체 생성 `^(VERDICT|SPOT): (APPROVED|CHANGES_REQUESTED)`(인용 프리픽스 `>`·워커명 인용 문맥 행 제외), R2 설계 헤더 자체 생성 `^# Design:|^## (원인 분석|해결 설계|확정 설계)`, R3 diff 블록 자체 생성 '^```diff|^diff --git|^@@ -[0-9]+'. 3종은 정상 릴레이 픽스처(판정 인용·경로 릴레이만 있는 transcript)로 **오탐 0 자가검증 후 고정** — 검증 실패 시 regex를 조정하되 고정 후 변경 금지 |
| **E2** 재기획 크로스오버 복원 | context-management 검증 시나리오 7의 state 픽스처 주입(v2 검토 CHANGES_REQUESTED 후 사망) → 복원 | 복원 분기 선택·카운터 승계·형상 게이팅 준수 | 양 구성 모두 **stage 2** 선택 && 카운터 diff 0 (v2 재구현 선택 = FAIL) | 각 구성의 **오케스트레이터 세션이 직접 복원 수행** — 하향 단의 절차 준수 신뢰성을 직접 측정. 판정 = checker |
| **E3** DA loop 등가 | 경계조건 누락을 심은 v1 구현 고정 → 재기획→재구현→재판정 루프를 planner만 교체해 실행(DA=codex xhigh 양 구성 공통) | DA 라운드 1 판정 일치율(잣대 자체 검증) + 라운드 수·판정 시퀀스(CR→APPROVED) | 라운드 1 판정 동일 && 시퀀스 동일 && 총 라운드 수 차 0(한도 2 내) | 파이프라인 stage 2~5. 대조 원본 = `state/<slug>/da-round<N>.md` |
| **E4** 설계 품질 루브릭 | 동일 checker JSON 입력으로 양 planner가 각각 설계 파일 생성 → 블라인드 채점 | 8점 루브릭: 원인 깊이(증상0/직접1/근본+재발방지2) · 대안 기각 근거(없음0/빈약1/대안≥2 각 근거2) · 검증 시나리오 수(<2:0, 2–3:1, ≥4:2) · 지시 구체성(방향0/파일1/파일:라인2) | 대체안 점수 ≥ fable 점수 − 1 | 채점자 = codex xhigh, 블라인드(산출 모델 미표기·제시 순서 교차). **채점은 증거 인용 JSON 체크리스트 필수** — 항목별 점수마다 설계 파일 라인 인용을 붙이고, **무증거 항목은 무효(0점 처리)**. 동점·경계(±1)면 **제2 채점자(sonnet-4-6 high) 추가 + 증거 인용 개수로 tie-break**. codex 부재 시 1차 채점자 = sonnet-4-6 high(제2 채점자는 opus-4-6) |

**종합 판정 규칙**: E1·E2 PASS = 기능 동일성(**필수** — 하나라도 FAIL이면 디폴트 부적격, 설계 결함으로 회귀). E3·E4까지 PASS = "동등" 등급. E4만 미달 = "기능 동등·품질 열세" 등급 — 차단이 아니라 사다리 하향의 알려진 비용으로 설치 고지문에 명기.

## 5. 확정 설계 — 파일별 반영 지시

### A. brain-availability.md (주 착지점)

- **A1.** §2 표 planner 행 교체: 1순위 `claude-opus-4-8`(effort 프로브: max→거부 시 high), 2순위 `claude-sonnet-5 max`(Workflow — 기존 high 표기를 **max로 교정**, planner 좌석 max 예외), 비고에 3순위 `claude-opus-4-6 max`.
- **A2.** §2 표에 **오케스트레이터 행 신설**: 기본 `fable-5 ultracode` | 1순위 `opus-4-8`(ultracode 수락 시 유지, 아니면 실측 상한) | 2순위 `sonnet-5 max` | 비고: Workflow 도구 존재가 선결 — 부재 시 planner/tester는 미들웨어 드라이버 경유 `claude -p`(스폰 경로 표 3행). planner 겸직 허용.
- **A3.** §1 프로브 추가 — **claude effort 상한 프로브**: 대체 후보로 확정된 claude 모델은 1회 실측(`claude -p --model <m> --effort max` 한 줄 질의 `< /dev/null`) 후 결과를 **4상태로 분류**해 처리한다: ⓐ **success** → 그 effort로 확정 ⓑ **400 `level ... not supported`** → 한 단계 강등(high) 재시도 — effort 강등은 이 오류 유형에서만 ⓒ **model-unavailable·auth 오류** → effort 문제가 아니므로 강등 금지, **사다리 다음 단으로 하강** ⓓ **budget·rate-limit 등 일시 오류** → 판단 보류·재시도(강등·하강 모두 금지). 확정 결과를 `install.json.effort_ceilings`에 기록(FT 업데이트 시 재프로브 생략).
- **A4.** §4 JSON 예시에 `"effort_ceilings": {"claude-opus-4-8": "<probe_result>"}` 필드 추가 — 값은 자리표시자로 표기(실측 전 특정 값을 예시가 암시하지 않게).
- **A5.** §2 DA 대체 행에 겹침 금지 조건 신설: "DA 대체 모델은 **planner(대체 포함) 모델과 동일 모델·동일 계열 금지** — planner=opus 계열이면 sonnet/gemini 계열 우선(author-review 분리)".

### B. install-interview.md

- **B1.** §2 PLANNER 행 비고 보강: "fable-5 미가용 시 §0이 사다리 1순위(opus-4-8, 프로브 상한)를 기본 선택지로 제시".
- **B2.** 금지 검증 일반화: "planner만 최상위 모델(fable5) 허용" → "**planner(최상위 브레인 좌석)만 사다리 상단 모델(fable-5, 대체 시 opus-4-8) 허용**". 워커 금지(fable-5/opus-4-8)는 현행 유지.
- **B3.** 오케스트레이터 게이트 문구: "ultracode 지원 최상위 모델 세션" → "오케스트레이터 사다리 최상위 가용 단(brain-availability §2) 세션 + Workflow 오케스트레이션 가용".
- **B4.** §4-2 크루 opt-in 보강: "§0에서 planner substitution 기록 시(=fable-less) omo·insane-search 질문에 **`★ fable-less 추천` 배지 + 근거 1줄 표시** — 기본값은 [추가 안 함] 그대로(§3 원칙: 기본값 변경 구현 금지)".

### C. SKILL.md

- **C1.** 허들 1 재작성(일반화): "현재 세션이 ⓐ Workflow 오케스트레이션 가용(도구 존재 — 스킬 지시 호출로 opt-in 충족) ⓑ 오케스트레이터 사다리 최상위 가용 모델 + 그 단의 최대 유효 effort(fable-5는 `/effort ultracode` 현행, 그 외는 실측 상한)인가? ⓑ 미달 시 설정 안내 후 진행, ⓐ 부재 시 planner/tester 스폰을 미들웨어 드라이버 서브에이전트 경유 `claude -p`(스폰 경로 표 3행)로 전환 선언 후 진행."
- **C2.** 역할 분리 표 모델 셀 2곳: 오케스트레이터 "ultracode 지원 최상위 모델 (fable5 등 — 일반화)" → "사다리 최상위 가용 모델(기본 fable5 ultracode — brain-availability §2)". planner "기본 fable5 + effort max" 뒤에 "(미가용 시 사다리: opus-4-8 프로브 상한 → sonnet-5 max)".
- **C3.** 표준 로스터 공통 불변 문구: "(planner의 fable5만 예외)" → "(최상위 브레인 좌석 planner만 예외 — 사다리 모델 fable-5/opus-4-8)". ft-planner 행 브레인 셀에 사다리 포인터 각주.
- **C4.** 스폰 경로 분리 표 planner 행 이유에 1문장 보강: "effort 명시는 모든 세션에서 필수 — ultracode 세션은 400 즉사, 비-ultracode 세션은 무증상 effort 다운그레이드".

### D. orchestration-playbook.md (개정 최소)

- **D1.** 첫 문단 "(ultracode 지원 최상위 모델)" → "(사다리 최상위 가용 모델 — brain-availability §2)". 그 외 무변경 — 파이프라인·프로브·스폰 규칙은 모델 비의존.

### E. test/verify.md

- **E1.** **V5 신설** "fable-in/out 동등성 비교": §4의 표 + 종합 판정 규칙 + "fable 보유 환경에서 override로 fable-out 재현" 실행 지침.
- **E2.** V2 금지 모델 행의 예외 문구를 B2와 동기화("planner 제외" → "planner 좌석 예외 — 사다리 모델").

### F. 무변경 확인 목록

context-management.md · monitoring-loop.md · integrations.md · feature-interview.md · update.md · agent-templates/*.tpl — **무변경**. 전부 모델 비의존 설계(E2가 이를 검증)이고, ft-planner.md.tpl은 placeholder 구조라 §0 치환이 사다리를 흡수한다.

**불변 제약 정합**: 디스크 SSOT·라운드 디스패치 규칙·형상 게이팅·크루 계약·integrations 게이팅은 어느 것도 수정하지 않는다(기본값 표·문구·검증 케이스 추가만). fable 보유 환경은 §0 프로브가 fable을 감지하면 사다리 최상단 = 현행 구성 → **diff 0**.

## 6. 리스크·미결

- **opus-4-8 effort 상한·ultracode 수락 여부 미실측**(과거 단서 "opus는 high까지", 2026-06-19) → A3 프로브가 설치 시 확정. 실측 전 문서 표기는 "기대 high".
- **Workflow 도구 가용성이 배포 채널·하네스에 따라 다를 수 있음** → 허들 1 ⓐ 프로브 + 콘솔 분리 폴백이 흡수(형상 불변). 단 planner 좌석의 미들웨어 드라이버 경유 E2E 완주는 B형 크루 실측에 준거한 추정 — V5 실행 시 함께 실측 권장.
- **E4 단일 심판(codex) 편향** — 블라인드·순서 교차로 완화하나 한계 잔존. 필요 시 3-lens 채점(원인 정합/구체성/검증성 별도 프롬프트)으로 확장 가능(미결).
- **sonnet-5 max planner 비용** — planner_rounds 한도 2로 유계, 별도 통제 불요.
- **"동일성"의 정의** — 모델이 다르므로 완전 동일은 불가. 본 설계는 "기능 동일(E1·E2 필수) + 품질 −1점 이내(E4)"를 '동등'으로 정의해 판정 가능성을 확보했다(정의 채택 — 미결 아님).
