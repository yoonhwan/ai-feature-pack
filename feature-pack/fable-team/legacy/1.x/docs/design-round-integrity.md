# Design: fable-team 라운드 무결성 — 카운터 산술 제거 (R1/R2/R3/R5)

- 대상: `skill/references/context-management.md`(주 수정), `monitoring-loop.md`(1절 보강), `agent-templates/ft-da.md.tpl`(1줄), `docs/design-ctx-management.md`(포인터 1줄)
- 전제(불변): Option B(brain_sessions/resume 체인/요약-후-fork), P1-1 형상 게이팅, P1-2 ACTIVE 생명주기, 디스크 SSOT + self-contract. 본 설계는 이들과 충돌하는 문구를 만들지 않는다.

## 원인 분석

R1과 R2는 별개 버그가 아니라 **한 뿌리의 두 증상**이다: 현행 스펙이 "파일은 증거, 카운터는 한도 집행용"이라는 자기 원칙(§4-4 "state는 선언, 파일이 증거")을 라운드 처리에서만 스스로 어긴다 — 카운터 값을 파일 버전의 **인덱스**로 쓰고(R1), 카운터 증가를 파일 실재와 무관하게 **디스패치 횟수**에 결합한다(R2).

- **R1 (게이트 우회 클래스)**: §4-5가 `da-round<N>` CHANGES → `design-v<N+1>` 존재로 분기 — da 라운드 번호 N과 설계 버전 축을 동일시. 그러나 monitoring-loop §2의 mid-impl 재기획(implementer "설계 틀림" 근거 → DA 없이 architect_rounds만 +1)은 **da_round를 움직이지 않고 설계 버전만 올린다**. 시퀀스: v1 구현 중 재기획→v2→v2 구현→DA 라운드1이 **v2를 검토**해 CHANGES_REQUESTED→재기획 디스패치 전 크래시. 복원 공식은 N=1, `design-v2` 실재 → "수정 설계 완료"로 오판 → stage 3에서 **DA가 방금 거부한 v2를 재구현**. lockstep 가정(da 라운드 K ↔ 설계 vK)이 크로스오버 경로에서 붕괴.
- **R2 (오탐 에스컬레이션 클래스)**: "디스패치 시점 +1"(§1-2) + 복원 시 "카운터 승계"(§4-6) + "진행 중 단계 처음부터 재실행"(§4-5, 재디스패치=또 +1) = 같은 논리 라운드 이중 과금. 최초 기획 디스패치 직후(architect_rounds=1, DESIGN_WRITTEN 전) 크래시 1회 → 복원 재디스패치로 =2 → 실 재기획 1회 만에 한도(2) 초과 오탐. da_round 동형. "판정 대기 중 사망 시 라운드 소모 승계" 의도 자체는 옳으나, **닫힘 판정 없이** 증가만 승계해 열린 라운드를 새 라운드로 재과금.
- **R3**: frontmatter 예시가 `stage: 3`(구현 중=게이트 미진입)인데 `da_round: 1` — 디스패치-시-+1 시맨틱과 모순.
- **R5**: `tester-round<N>`의 N 미정의 — impl-round<N>("대응 설계 버전")과 정합 필요.

## 스코프 판정 — 선택안과 기각안

**선택: 하이브리드** — 카운터 산술을 파일-실재 기반으로 국소 교체(라운드 디스패치 규칙 + reviewed 버전 링크), 퓨전(라운드 레코드)은 v2 로드맵으로 기각.

- **기각(퓨전 — 라운드당 단일 레코드 외재화)**: 근본성은 인정하나 비용/리스크 초과. ① state.md frontmatter·write-through 4이벤트·§4 복원 7단계·검증 시나리오 5개 전면 재작성 — 이미 해소된 P1-1(형상 게이팅)·P1-2(ACTIVE 생명주기)와 Option B(brain_sessions) 문구에 전부 손대는 회귀 리스크. ② 퓨전이 통합하려는 4결합점 중 ②write-through ④브레인 resume 결정점은 현행 write-through #2·#3이 이미 같은 경계에 묶어놨다 — 남는 실익은 ①카운터 틱 ③체크포인트인데 이는 아래 두 규칙으로 동등하게 소멸한다. 수술적 변경 원칙(현재 실재하는 결함 R1/R2만) 우선.
- **선택(국소, 단 원리 승격)**: critic의 대안 국소 패치 2건을 채택하되 개별 땜빵이 아니라 **단일 원리 "파일이 라운드의 진실, 카운터는 한도 캐시"**로 묶어 명문화 — R1(reviewed 버전 링크로 두 축 분리)·R2(열린 라운드 재사용)가 이 원리의 두 귀결임을 문서가 스스로 말하게 한다. 향후 같은 클래스 재발(예: respawns) 방지.
- **v2 로드맵(비규범 메모)**: 라운드 레코드(round_id 전역단조, input_design_ver, verdict, window_state)는 다중 피처 병렬화 확장 시 재검토 — 현 단일 ACTIVE 스코프에선 파일 4종이 이미 레코드 역할.

## 확정 설계 (구현 노트 — 파일별 수정 지시)

### A. `skill/references/context-management.md` (주 수정 7건)

**A1. §1 write-through 규율 항목 2 — R2 핵심.** 현행 "카운터(da_round/architect_rounds)는 **디스패치 시점에 +1 기록**(판정 대기 중 사망해도 라운드 소모가 승계되도록)"를 다음으로 교체:

> 카운터(da_round/architect_rounds)는 디스패치 직전 갱신하되 **파일 실재로 열림/닫힘을 판정**한다(라운드 디스패치 규칙): 현재 카운터 값 N의 산출물(architect: `design-<slug>-v<N>.md`, DA: `da-round<N>.md`)이 **실재하면 닫힌 라운드 → +1 후 디스패치**(N=0 포함 — 0은 산출물이 없으므로 항상 +1), **부재하면 열린 라운드 → 카운터 재증가 없이 번호 N을 재사용해 디스패치**(크래시·재시작 후의 재디스패치가 여기 해당 — 같은 논리 라운드 이중 과금 금지). +1이 디스패치 전에 기록되므로 판정 대기 중 사망해도 라운드 소모는 승계된다.

**A2. §1 디렉토리 주석 2건 — R1 링크 + R5.**
- `da-round<N>.md` 줄: `# DA 판정 + 증거 (라운드별 — 첫머리에 검토한 설계 버전 'reviewed: v<M>' 명기, §4-5 복원 분기의 키)`
- `tester-round<N>.json` 줄: `# tester 결과 (<N> = impl-round<N>과 동일 규칙 — 대응 설계 버전, 축약 형상은 1)`

**A3. §1 frontmatter 예시 — R3.** `da_round: 1` → `da_round: 0`으로 교정하고 주석 교체: `# 게이트 라운드 — 라운드 디스패치 규칙(§1)로 증감 (한도 2). 예시=stage 3 구현 중이라 게이트 미진입 0`. `architect_rounds: 1` 주석도 `# 기획 라운드 — 동일 규칙 (한도 2)`로 교체(v1 설계 실재와 정합, 값 유지).

**A4. §4-4 산출물 실재 검증 — 카운터 인덱싱 제거.** 현행 `design-<slug>-v<architect_rounds>.md`(2), `impl-round<architect_rounds>.md`(3)의 버전 인덱스를 카운터가 아닌 **디스크 실재 최대 버전 M**으로 교체:

> `design-<slug>-v<M>.md`(2 — M = 실재하는 최대 설계 버전. 카운터가 아니라 파일이 증거), `impl-round<M>.md`(3 — 현재 최대 설계 버전 M 대응만 유효, 이전 버전 파일은 stale로 무시. 축약 형상은 impl-round1), `tester-round<M>`/da 라운드 파일(4-5)

**A5. §4-5 stage 5 복원 분기 — R1 핵심.** 현행 "마지막 `da-round<N>.md`가 CHANGES_REQUESTED이고 `design-<slug>-v<N+1>.md` 없음→stage 2, 있음→stage 3" 문장을 교체:

> stage 5 도중이면 **파일 존재로 분기**: 마지막 `da-round<K>.md`의 판정과 그 파일 첫머리의 **검토 설계 버전 `reviewed: v<M>`**(필드 부재 시 실재하는 마지막 `impl-round<M>`의 M으로 도출)을 읽어 — CHANGES_REQUESTED && `design-<slug>-v<M+1>.md` **없음** → stage 2 재진입(재기획 전), **있음** → stage 3(수정 설계 완료). **DA 라운드 번호 K와 설계 버전 M은 독립 축**(mid-impl 재기획은 K를 움직이지 않고 M만 올린다) — K 기반 `v<K+1>` 산술 금지.

**A6. §4-6 카운터 승계 보강.** "카운터는 state.md 값을 승계" 문장 뒤에 추가:

> 승계 시 열린 라운드(카운터 N의 산출물 부재)는 §1 라운드 디스패치 규칙에 따라 **재증가 없이 번호 N 재사용**. 복원에 따른 워커 재스폰은 계획적 재스폰(세션 사망 ≠ 워커 failure)으로 respawns 한도 비소모 — 이벤트 로그로만 추적.

**A7. 검증 시나리오 6·7 추가** (기존 1~5 유지 — 아래 「검증 기준」 S1·S2 문구 그대로).

### B. `skill/references/monitoring-loop.md` (2건)

- **§2** "설계 자체가 틀렸다는 근거가 오면 → architect에 재기획 라운드" 뒤에 괄호 추가: `(architect_rounds만 소모, da_round 불변 — 설계 버전 축과 DA 라운드 축은 독립)`.
- **§5** 끝에 1문장 추가: `라운드 소모 판정은 카운터 산술이 아니라 파일 실재 기준(context-management §1 라운드 디스패치 규칙) — 열린 라운드(산출물 부재) 재디스패치는 한도 비소모.`

### C. `agent-templates/ft-da.md.tpl` (1줄)

「실행 규칙」 resume 체인 bullet 앞에 추가:

> - 판정·증거는 지시받은 `state/<slug>/da-round<N>.md`에 직접 기록(Bash heredoc 가능)하되, **첫머리에 검토한 설계 버전을 `reviewed: v<M>`로 명기**하라(전달받은 설계 파일 경로의 v — 세션 복원 분기의 키).

### D. `docs/design-ctx-management.md` (소급 미러 안 함 — 포인터 1줄)

문서 상단(전제 목록 아래)에 추가: `> 개정: 라운드 카운터·복원 분기 산술은 design-round-integrity.md로 개정됨 — 정본은 skill/references/context-management.md.` 이력 문서 본문은 소급 수정하지 않는다(미러 유지비·드리프트 리스크 > 이득).

## 검증 기준 (tester 실행 케이스)

**정적 정합 (grep — 전부 0건이어야 통과)**:
- G1: `references/` 내 `v<N\+1>` 패턴 잔존 0건 (da 라운드 번호 기반 설계 버전 산술 제거 확인 — `v<M+1>`만 허용).
- G2: `context-management.md`에서 `da_round: 1`과 `stage: 3`이 같은 예시 블록에 공존 0건.
- G3: `디스패치 시점에 +1` 단독 문구(열림/닫힘 판정 없는 구버전) 잔존 0건.
- G4: `tester-round<N>` 정의 존재(§1 주석) + `reviewed: v<M>` 문구가 context-management.md와 ft-da.md.tpl **양쪽에** 존재.

**시나리오 워크스루 (개정 문서만 보고 각 단계의 규범 판정을 재현 — 오케스트레이터 시뮬)**:
- **S1 (R2 — 크래시-중-디스패치 이중 과금 방지)**: stage 2 최초 architect 디스패치 직후(architect_rounds=1 기록, DESIGN_WRITTEN 전) 세션 사망 → 복원 → 재디스패치. 기대: design-v1 부재=열린 라운드 → architect_rounds **1 유지**로 v1 산출 → 이후 실 재기획 1회에 =2로 정상 진행. 복원 재디스패치가 =2를 만들거나, 실 재기획 1회에 한도 초과 에스컬레이션이 뜨면 **실패**. da_round 동형 케이스(stage 5 디스패치 직후 사망) 1회 반복.
- **S2 (R1 — mid-impl 재기획 크로스오버 복원)**: v1 구현 중 "설계 틀림" 근거 → 재기획 v2(architect_rounds=2, da_round=0 유지) → v2 구현(impl-round2) → DA 라운드 1이 v2 검토, CHANGES_REQUESTED(`da-round1.md`에 `reviewed: v2`) → 재기획 디스패치 전 세션 사망 → 복원. 기대: 분기가 M=2를 읽어 design-v3 부재 → **stage 2** 선택. design-v2 존재를 이유로 stage 3(거부된 v2 재구현)으로 가면 **실패**(게이트 우회).
- **S3 (회귀 — 기존 시나리오 3·4·5 재판정)**: 세션 넘는 한도 승계(닫힌 라운드 1 → 복원 → 라운드 2 CHANGES → 한도 초과 에스컬레이션), 축약 형상 복원(형상 게이팅), 브레인 resume 승계가 개정 후에도 동일 결론 — 하나라도 결론이 바뀌면 회귀 **실패**.
- **S4 (R5)**: tester-round 파일명 N이 mid-impl 재기획 후 재검증 경로에서 impl-round N과 일치하는지(둘 다 설계 버전 2) 문서만으로 유도 가능해야 통과.

## 리스크·미결

- **reviewed 필드 self-contract 의존**: DA 드라이버가 명기를 누락할 수 있음 → §4-5에 impl-round 최대 버전 폴백을 내장해 완화(폴백도 파일 기반). 잔여 리스크: impl-round까지 부재한 비정상 상태 — §4-4 롤백이 선행 흡수.
- **열린 라운드 오판(산출물이 부분 기록된 채 크래시)**: 파일이 실재하나 불완전한 경우 닫힌 라운드로 오판 가능. 쓰기 순서 불변식("산출물 완전 기록 후 포인터 전진")이 전제이나 산출물 파일 자체의 원자성은 미보장 — 현 스코프 수용(발생 시 해당 라운드 산출물 삭제 후 재디스패치가 수동 복구 경로).
- **respawns 비소모 판정 확장**: A6의 "세션 사망 ≠ failure"는 복원 경로 한정 — 일반 failure 판정 기준의 정밀화는 미결(현행 monitoring-loop §3 유지).
- **라운드 레코드(퓨전)는 v2 로드맵**: 다중 피처 병렬(ACTIVE 목록화) 착수 시 재평가.
