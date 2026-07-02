# Design: baton·cairn × fable-team 오케스트레이터 접목

## 1. 원인·요구 분석

**긴장의 실체**: 팩 배포 관점에선 fable-team(FT)이 baton·cairn 없이 완전 동작해야 하고(독립성·버저닝 절연), 사용자 로컬 환경에선 "메인 오케스트레이터가 워크트리·브랜치·작업리스트 관리에 baton·cairn을 무조건 사용"이 규범이다. 이 둘은 **기능의 문제가 아니라 강도(규범 레벨)의 문제**다 — 같은 연동 훅을 두고, 환경마다 off/on/required를 달리 선언할 수 있으면 해소된다.

**현행 갭**:
- context-management §5는 baton을 "비규범 참고"로만 두고 save/resume 포인터만 다룬다 — 워크트리 생성(wt-create), 종결(finish), 작업 원장(cairn)은 통합 지점이 비어 있다.
- FT 부팅 시퀀스는 현재 CWD에서 그대로 킥오프한다 — main root에서 트리거하면 main에 직접 구현하게 되며, 사용자 글로벌 워크트리 규칙(`.worktrees/{branch}/` 분리, PR 권고)과 충돌한다.
- FT 피처는 종결 후 어떤 원장에도 남지 않는다 — cairn의 계보(return_to)·overdue·reconcile이 FT 작업을 못 본다.
- tmuxc와의 경계가 어디에도 명문화돼 있지 않다.

**레이어 정의 (설계의 축 — 상태 중복 저장 금지의 근거)**:

| 레이어 | SSOT | FT와의 관계 |
|--------|------|-------------|
| FT state (`.fable-team/state/`) | 파이프라인 상태(stage·라운드·원장) | 유일한 파이프라인 SSOT — 불변 |
| baton (`.baton/`) | 워크트리·포트·세션 간 내비게이션(NEXT.md) | 앞(워크트리 생성)과 뒤(finish·정리)만. 중간은 포인터 |
| cairn (`.cairn/plan.yaml`) | 프로젝트 작업 원장·일정·복구 계보 | 피처 1건 = 태스크 1노드. 생명주기 경계에서만 터치 |
| tmuxc | 세션 기동·증류·리모트 | FT 파이프라인 밖 (경계 §3.6) |

## 2. 옵션 비교

**A안 — 강결합(필수 의존 내장)**: FT 부팅이 baton wt-create·cairn add-task를 무조건 수행, phase.json·plan.yaml을 FT가 직접 파싱.
→ **기각**. ① 팩 독립 배포 원칙 위반(미설치 환경 기능 저하). ② baton SPEC major 버전업이 FT를 깨뜨림(버저닝 결합). ③ phase.json/plan.yaml 파싱은 내부 스펙 참조 = 참조 복잡성 그 자체.

**B안 — 현행 유지(감지 시 포인터만, 전부 비규범)**: §5를 그대로 두고 cairn만 유사 문단 추가.
→ **기각**. ① 사용자 환경의 "무조건 사용" 규범을 표현할 방법이 없다(매번 감지-우연 의존). ② 부팅(워크트리 생성)·종결(finish·complete·PR 권고)이라는 실질 통합 지점이 계속 공백 — 사용자 요구 3을 못 만족.

**C안 — 프로파일 게이팅 + 포인터 연동 확장 (채택)**: install.json에 `integrations` 3값 선언(off/on/required), 연동 훅은 **생명주기 경계 4곳(킥오프·종결·재시작·블록)에만**, 교환하는 것은 상태 본문이 아니라 **포인터와 이벤트**. baton·cairn 참조는 명령 인터페이스(`/baton:*`, `cairn <verb>`) 수준으로 한정.
→ 팩 기본 off = 독립성 유지, 사용자 환경 required = 규범 강제, §5 포인터 원칙의 자연 확장.

## 3. 확정 설계

### 3.0 게이팅 모델 (SSOT: install.json)

`install.json`에 신규 키:

```json
"integrations": { "baton": "off|on|required", "cairn": "off|on|required" }
```

- **off** (팩 기본): 연동 훅 전부 미실행. 미설치 환경과 동일 = 기능 저하 없음.
- **on**: 매 부팅 허들에서 가용성 프로브 → 성공 시 훅 실행, 실패 시 **graceful degrade**(이벤트 로그에 `integration degraded: <이유>` 1줄 기록 후 독립 모드 속행 — 파이프라인 차단 금지).
- **required** (사용자 환경 규범): 프로브 실패 시 부팅 허들에서 **사용자 보고 후 대기**(무단 독립 진행 금지 — "무조건 사용" 규범의 강제 지점). 사용자가 "이번만 독립 진행" 승인 시에만 degrade.

가용성 프로브(버저닝 절연 — 존재+응답만 확인, 내부 스펙 불파싱): `bash ~/.baton/current/bin/baton status < /dev/null` exit 0, `bash ~/.cairn/current/bin/cairn status < /dev/null` exit 0.

### 3.1 install-interview.md — §4.5 신설 「연동(integrations) 감지·선언」

§4(크루)와 §5 사이에 추가. 크루 opt-in과 동형 패턴:

1. 감지: 위 프로브 2종 Bash 실측.
2. 감지된 것마다 AskUserQuestion: "baton/cairn 연동 레벨? [off] / on / required" — 기본 [off]. 미감지면 질문 생략(off 고정).
3. 답변을 `install.json.integrations`에 기록 (§5-3-1 스냅샷에 포함 — "FT 업데이트"가 보존).

### 3.2 SKILL.md — 부팅 시퀀스·허들 수정 (문구 수준)

- **허들 4번 추가**: "integrations(install.json)가 on/required면 가용성 프로브 — required 실패 시 보고 후 대기, on 실패 시 degrade 기록 후 속행 (`references/integrations.md`)."
- **부팅 시퀀스 4(부팅 보드) 항목 추가**: "⑥ 작업 공간: 워크트리 경로·브랜치(baton on 시 wt-create 예정 표시) + cairn 태스크(등록 예정 id 또는 기존 태스크 링크)".
- **부팅 시퀀스 5(컨펌 게이트) 뒤 문장 추가**: "킥오프 확장 훅(워크트리·원장 등록)은 `references/integrations.md` §킥오프를 따른다."

### 3.3 신규 레퍼런스 `skill/references/integrations.md` (연동 상세 SSOT)

기존 문서들엔 위 포인터 문구만 넣고, 절차 본문은 이 파일 하나에 집중(수술적 변경 + 참조 최소화). 목차:

```
# fable-team 연동 — baton·cairn 프로파일 게이팅
## 0. 게이팅 모델 (off/on/required + 프로브 + degrade 규칙)   ← §3.0 내용
## 1. 킥오프 훅 (컨펌 직후, stage 0 직전)
## 2. 종결 훅 (stage 6)
## 3. 세션 재시작 — 발견 채널 vs 복원 정본
## 4. 블록 훅
## 5. tmuxc 경계 (FT가 대체하는 것 / tmuxc에 남는 것)
## 6. 버저닝·절연 규칙
```

**§1 킥오프 훅** (baton on/required 시):
- 현 CWD가 main/master root이고 피처가 코드 변경 형상(check-only 제외)이면: `/baton:wt-create <slug>` 실행 → `cd .worktrees/<slug>` 후 킥오프. `.fable-team/`은 워크트리 루트에 생성(현행 §5 worktree 정합 그대로 — main에 `.fable-team/` 잔존 금지). 이미 워크트리 안이면 wt-create 생략(그 워크트리 사용).
- 워크트리 생성 직후 사용자 글로벌 규칙 준수 확인: `.worktree-info.json`(baton이 생성)·심링크 — baton이 이미 수행하므로 FT는 재수행하지 않고 존재만 확인.
- cairn on/required 시: `cairn add-task <project> <milestone> ft-<slug> [--days N]`(부팅 보드에서 확정한 값) 또는 사용자가 기존 태스크를 지정하면 add-task 생략. 이어 `cairn link <task> --execution-ref .worktrees/<slug> --session-ref fable-team:.fable-team/state/ACTIVE`. 발급 task id를 state.md frontmatter `cairn_task: <id>`에 write-through(포인터 1개 — cairn이 FT 상태를 갖는 게 아니라 FT가 cairn 주소를 갖는다).
- **stage 전이·라운드는 cairn에 절대 기록하지 않는다** (이중 기록 금지 — cairn 원장에서 FT 피처는 "열림→닫힘" 2상태만 가진다).

**§2 종결 훅** (stage 6 — playbook의 status:done 기록·ACTIVE 제거 **후**):
1. baton: `/baton:save`(NEXT.md엔 현행 §5 규칙 그대로 **한 줄 포인터만**) → `/baton:finish`. `wt-clean`은 **자동 실행 금지** — 머지 여부는 사람 게이트.
2. cairn: `cairn complete <cairn_task>` → 출력의 return_to(복귀점)를 종결 보고에 포함.
3. PR 권고 보고(사용자 글로벌 규칙): `.worktree-info.json` 생성일 경과·`git log main..HEAD --oneline | wc -l` 커밋 수 + "PR → 머지 → `/baton:wt-clean --merged`" 안내 1줄.
4. 훅 실패는 종결을 막지 않는다 — FT 종결은 이미 완료(순서가 그 보장), 실패는 degrade 기록 + 보고.

**§3 세션 재시작 — 정본은 항상 FT §4**:
- 복원 **정본** = `.fable-team/state/ACTIVE` + state.md (context-management §4, 불변). baton NEXT.md·cairn return_to는 **발견 채널**일 뿐 — 둘 다 "fable-team 재트리거하라"는 포인터로 수렴하므로 이중 복원이 구조적으로 불가(포인터엔 stage·카운터 본문이 없어 복원 재료가 못 된다).
- main root에서 재트리거된 경우(워크트리 밖이라 ACTIVE 미발견): baton on이면 `baton status`로 활성 워크트리 목록 → `.worktrees/*/.fable-team/state/ACTIVE` 존재 확인 → 발견 시 해당 워크트리로 이동 후 §4 복원. cairn on이면 `cairn map`의 execution-ref가 동일 발견을 제공. 둘 다 off/미감지면 현행대로 신규 플로우(기능 저하 아님 — 사용자가 워크트리에서 재트리거하면 됨).
- `cairn reconcile`은 복원 시 자동 실행하지 않는다 — 불일치 의심(예: ACTIVE 있는데 cairn_task가 이미 done, 또는 그 역) 시에만 1회 실행해 orphan 목록을 사용자에게 보고하고 결정 위임(FT가 cairn 원장을 자동 교정 금지 — cairn은 직렬 writer 원장, 교정 주체는 사용자).

**§4 블록 훅** (status: blocked 진입 시, cairn on): 상태 동기화가 아니라 **가시성 이벤트 1줄** — `cairn link <cairn_task> --session-ref "blocked:<사유 한 줄>"`. set-status 등 상태 필드 조작 금지(2상태 원칙 유지).

**§5 tmuxc 경계 (명문화)**:

| 영역 | 담당 | 근거 |
|------|------|------|
| 파이프라인 워커 오케스트레이션·모니터링·원장 | **FT** (Agent/Workflow + state/) | tmuxc UC9-11 fan-out을 FT가 대체 완료 |
| FT 오케스트레이터 세션 자체의 기동·리모트(모바일 attach)·tmux 복원 | tmuxc | FT는 세션 안에서 도는 스킬 — 자기 세션을 못 만든다 |
| 세션 증류(distill) | tmuxc | FT의 세션 재시작 안내(§2 표) 시 실제 증류 수단 |
| FT 밖 신규 작업 세션 기동 | tmuxc | FT 스코프 밖 |

금지: FT 파이프라인 내부에서 워커를 tmuxc 세션으로 스폰하는 것(스폰 경로 분리 규칙과 원장 체계 밖 — 크루 B형 `claude -p`가 이미 콘솔 분리를 담당).

**§6 버저닝·절연 규칙**: ① 참조는 명령 인터페이스만(`~/.baton/current/bin/baton <verb>`, `~/.cairn/current/bin/cairn <verb>`, 슬래시 명령) — phase.json·plan.yaml·NEXT.md 스키마 파싱 금지(읽는 것은 명령의 stdout 요약뿐). ② 명령 실패·인터페이스 변경은 전부 degrade 경로로 흡수(FT 파이프라인 무영향). ③ FT가 baton/cairn에 쓰는 것은 그들의 공식 명령 경유만 — 파일 직접 Write 금지.

### 3.4 context-management.md — §5 교체

현행 §5 「baton 선택 연동 (비규범)」을 「§5 baton·cairn 연동 — `references/integrations.md` 참조 (프로파일 게이팅)」으로 교체: 계층 분리 원칙 문단(현행 첫 문단)과 worktree 정합 항목은 유지하고, 감지·훅 절차는 integrations.md 포인터로 대체. frontmatter 예시에 `cairn_task: none` 1줄 추가(§1 스펙). "항상 디스크에 있어야 하는 상태" 목록에 `cairn_task 포인터(연동 on 시)` 추가.

### 3.5 orchestration-playbook.md·feature-interview.md — 각 1줄

- playbook 파이프라인 0(킥오프)과 6(종결) 줄 끝에 `(+연동 훅 — integrations.md §1/§2)` 추가.
- feature-interview §4 킥오프 항목에 "integrations on 시 부팅 보드에 워크트리·cairn 태스크 항목 포함(integrations.md §1)" 1줄.

## 4. 검증 시나리오

1. **미설치 무저하**: integrations 전부 off(팩 기본) 또는 baton·cairn 미설치 환경에서 피처 1건 부팅→종결. 현행 동작과 diff = 허들 프로브 0회·추가 명령 0회여야 통과(off는 프로브조차 안 돈다).
2. **required 강제**: `integrations.baton: required` + `~/.baton/current` 임시 리네임 → FT 트리거. 허들에서 보고·대기해야 통과 — 무단 독립 킥오프하면 실패.
3. **main root 킥오프**: baton on + main root 트리거 → wt-create → 워크트리에서 파이프라인 → main 루트에 `.fable-team/` 부재 확인. main에 생기면 실패.
4. **이중 복원 방지**: stage 3 중 세션 사망 → 새 세션에서 `/baton:resume` 먼저 실행 → NEXT.md 한 줄 포인터만 노출 → FT 재트리거 → §4 복원 1회. NEXT.md에 stage/카운터 본문이 있거나 복원이 2경로로 중복 수행되면 실패.
5. **종결 순서·안전**: stage 6에서 ①FT done+ACTIVE 제거 → ②baton save/finish → ③cairn complete(return_to 보고) → ④PR 권고(경과일·커밋수). wt-clean이 자동 실행되거나, ②③ 실패가 FT 종결을 롤백시키면 실패.
6. **reconcile 불일치**: cairn_task done인데 ACTIVE 잔존 상태 조작 → 복원 시 FT가 reconcile 1회 실행·orphan 보고·사용자 결정 대기해야 통과 — cairn 원장을 자동 수정하면 실패.
7. **degrade 속행**: on 상태에서 cairn 바이너리 제거 후 킥오프 → 이벤트 로그 degraded 1줄 + 독립 모드 정상 킥오프. 파이프라인이 차단되면 실패.

## 5. 리스크·미결

- **cairn add-task의 project/milestone 사전 존재 필요** — 프로젝트에 `.cairn/` 미초기화면 add-task가 실패한다. degrade로 흡수되나, 부팅 보드에서 "cairn 원장 미초기화 — init 할까요?" 1회 질문을 넣을지는 구현 시 판단(자동 init은 원장 오염 리스크로 비권장).
- **baton 훅(UserPromptSubmit/PostToolUse)이 FT 세션에서도 JOURNAL.md에 turn을 쌓음** — 무해(append-only, FT 상태와 무관)하나 노이즈. baton 자체 동작이라 FT가 끄지 않는다(절연 원칙).
- **main root 재트리거 시 워크트리 스캔 비용** — `baton status` 1회로 제한, 활성 워크트리 다수면 사용자에게 선택 질의.
- **required 레벨의 팩 배포 시 노출** — install.json은 로컬 산물이라 배포엔 안 실리지만, 문서 예시가 required를 기본처럼 보이게 하면 안 됨 → integrations.md §0에 "팩 기본 off" 명기로 방어.
- **check-only 형상의 워크트리 생략 판정** — 코드 변경 없는 피처에 wt-create는 낭비. §1에서 check-only 제외로 규정했으나 abbrev/standard 내 "문서만 수정" 케이스는 경계 모호 — 부팅 보드에서 워크트리 항목을 사용자가 끌 수 있게(항목별 조정은 기존 컨펌 게이트가 이미 지원).
