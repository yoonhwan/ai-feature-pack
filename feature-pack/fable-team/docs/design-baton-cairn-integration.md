# Design: baton·cairn × fable-team 오케스트레이터 접목 (v2 — DA·critic 게이트 반영)

## 1. 원인·요구 분석

**긴장의 실체**: 팩 배포 관점에선 fable-team(FT)이 baton·cairn 없이 완전 동작해야 하고(독립성·버저닝 절연), 사용자 로컬 환경에선 "메인 오케스트레이터가 워크트리·브랜치·작업리스트 관리에 baton·cairn을 무조건 사용"이 규범이다. 이 둘은 **기능의 문제가 아니라 강도(규범 레벨)의 문제**다 — 같은 연동 훅을 두고, 환경마다 off/on/required를 달리 선언할 수 있으면 해소된다.

**현행 갭**: context-management §5는 baton save/resume 포인터만 다루고 워크트리 생성·종결·작업 원장(cairn) 통합 지점이 공백. FT 부팅은 현재 CWD에서 그대로 킥오프해 main 직접 구현과 충돌. FT 피처는 종결 후 어떤 원장에도 안 남음. tmuxc 경계 미명문화.

**cairn 실측 제약 (v2 신규 — 설계의 전제, cairn.py 정본)**:
- 원장 위치는 **실행 CWD의 `git rev-parse --show-toplevel`**로 해석(cairn.py:19-42) → 워크트리에서 실행하면 워크트리 로컬 `.cairn`을 봄. add-task/complete/link/spawn엔 `--file` 오버라이드 없음(cairn.py:1965-2001).
- `complete`는 return_to 없으면 `--force` 없이는 ValueError(cairn.py:1040-1043). `add-task`는 return_to를 만들지 않음(965-982). `spawn`만 return_to·execution_ref·session_ref를 생성 시 설정(986-1018).
- `link --session-ref`는 **대입 덮어쓰기**(cairn.py:1143-1144), 누적은 `--add-session`(session_chain 누적 + session_ref 최신 갱신, 1145-1152).
- `reconcile`은 execution_ref를 `git worktree list --porcelain`의 **브랜치명**(`branch refs/heads/` 프리픽스 스트립)과 대조(1106-1117, 1095-1103) → execution_ref에 경로를 넣으면 활성 워크트리도 orphan 오보.
- `map`은 recovery-map **파일 경로만 stdout 출력**(1067-1072) → 발견 채널로 부적합.

**레이어 정의**: FT state(`.fable-team/state/`)=파이프라인 유일 SSOT / baton(`.baton/`)=워크트리·세션 내비게이션(앞뒤 경계만) / cairn(`.cairn/plan.yaml`)=프로젝트 작업 원장(피처 1건=1노드, 열림→닫힘 2상태) / tmuxc=FT 밖(§3.3-§5).

## 2. 옵션 비교

**A안 — 강결합(필수 의존 내장)**: 기각 — 팩 독립 배포 위반, 버저닝 결합, 내부 스키마 파싱 복잡성.
**B안 — 현행 유지(전부 비규범)**: 기각 — 사용자 환경 "무조건 사용" 규범 표현 불가, 킥오프·종결 통합 공백 지속.
**C안 — 프로파일 게이팅 + 포인터 연동 (채택)**: install.json `integrations` 3값(off/on/required), 훅은 생명주기 경계(킥오프·종결·재시작·블록·**언블록**)에만, 교환은 포인터·이벤트만, 참조는 명령 인터페이스 수준.

## 3. 확정 설계

### 3.0 게이팅 모델 (SSOT: install.json — 양 리뷰 합의 유지 + required 범위 확장)

`install.json`(**발동된 FT 스킬 설치 위치**의 파일 — install-interview §3-1 스냅샷과 동일 파일이 SSOT)에 신규 키:

```json
"integrations": { "baton": "off|on|required", "cairn": "off|on|required", "headless_override": "deny|allow-degrade" }
```

- **SSOT·우선순위**: FT는 발동된 설치본의 install.json **단일 파일만** 읽는다(병합 금지). project 설치본과 user 설치본이 공존하면 claude 스킬 로딩 규칙과 동형으로 **project가 우선**(발동된 쪽이 곧 정본).
- **off**(팩 기본): 훅 전부 미실행, 프로브조차 안 돔 — 미설치 환경과 동일.
- **on**: 부팅 허들에서 가용성 프로브 → 성공 시 훅 실행, 실패(프로브·훅 명령 모두) 시 **graceful degrade**(이벤트 로그 1줄 기록 후 독립 속행 — 차단 금지).
- **required**: **프로브 실패뿐 아니라 킥오프 생명주기 훅 명령 실패(wt-create·spawn/add-task·link)도** 사용자 보고 후 대기 — 무단 독립 진행 금지. 사용자 "이번만 독립 진행" 승인 시에만 degrade. 종결 훅 실패는 FT 종결을 롤백하지 않되(§3.3-§2-4) required면 "연동 종결 미완(cairn 미닫힘)"을 이벤트 로그에 기록하고 다음 행동 전 사용자 보고·대기.
- **required × 무인(headless) 데드락 방지**: AskUserQuestion 채널이 없는 실행(`claude -p` 등)에서 required 실패 시 — `headless_override: allow-degrade`가 **사전선언**돼 있으면 degrade 허용하되 **요란한 기록**(이벤트 로그 + 종결 보고 첫 줄에 `⚠ required-integration degraded (headless override)` 명기). 기본 `deny`면 **fail-fast 중단 + 롤백** — 허들 프로브 실패면 ACTIVE·state 생성 전이라 그대로 종료, **킥오프 훅 실패면(§1 순서상 state 선생성 뒤) 생성된 state.md·ACTIVE와 부분 cairn 부작용(spawn된 노드 → `remove-task <project> <milestone> <task>` 3인자)을 롤백 후 종료**. 어느 경로든 "durable 부작용 없음" 계약이 유지되고 재트리거 시 신규 플로우(orphan ACTIVE 잔존 금지). 무한 대기 데드락 금지. 종결 훅 실패의 required 대기(위 항목)도 headless면 동일 override 정책 — `deny`는 대기 대신 "연동 종결 미완" 기록 후 종료(FT 종결은 이미 완료라 무해).

가용성 프로브(존재+응답만, 내부 스펙 불파싱): `bash ~/.baton/current/bin/baton status < /dev/null` exit 0, `(cd "$MAIN_ROOT" && bash ~/.cairn/current/bin/cairn status < /dev/null)` exit 0.

### 3.1 install-interview.md — §4.5 신설 「연동(integrations) 감지·선언」

§4(크루)와 §5 사이. ① 프로브 2종 Bash 실측 → ② 감지된 것마다 AskUserQuestion "연동 레벨? [off]/on/required"(미감지면 생략=off) + required 선택 시 headless_override 추가 질문 1개(기본 deny) → ③ `install.json.integrations` 기록(§3-1 스냅샷 포함 — "FT 업데이트"가 보존).

### 3.2 SKILL.md — 부팅 시퀀스·허들 수정 (문구 수준)

- **허들 4번 추가**: "integrations(install.json)가 on/required면 가용성 프로브 — required 실패 시 보고 후 대기(headless는 §0 override 정책), on 실패 시 degrade 기록 후 속행 (`references/integrations.md`)."
- **부팅 시퀀스 1(복원 체크) 확장 — integration-aware discovery 실삽입**: "1. 복원 체크: 현 위치 기준 `.fable-team/state/ACTIVE` 존재 → context-management §4 복원. **없고 integrations가 on/required이며 현 위치가 main 워크트리 내부(판정: integrations.md §3)면 discovery 수행 — `baton status`(1순위) 및 `<MAIN_ROOT>/.worktrees/*/.fable-team/state/ACTIVE` glob(보조)으로 활성 FT 워크트리 탐색 → 발견 시 해당 워크트리 **절대경로 운용**으로 §4 복원(cd 금지).** 둘 다 없으면 2로."
- **부팅 보드 항목 추가**: "⑥ 작업 공간: 워크트리 경로·브랜치(baton on 시 wt-create 예정) + cairn 노드(spawn parent 후보 — `cairn status` 요약에서 제시 — 또는 add-task 폴백 표시)".
- **컨펌 게이트 뒤 문장 추가**: "킥오프 확장 훅은 `references/integrations.md` §1의 **순서**를 따른다."

### 3.3 신규 레퍼런스 `skill/references/integrations.md` (연동 상세 SSOT)

목차: §0 게이팅 모델(=§3.0) / §1 킥오프 훅 / §2 종결 훅 / §3 재시작—발견 vs 복원 / §4 블록·언블록 훅 / §5 tmuxc 경계 / §6 버저닝·절연·CWD 규칙.

**§공통 — CWD·경로 규칙 (전 훅 적용)**:
- **세션 CWD는 절대 바꾸지 않는다**(cd 금지 — 오케스트레이터 실무 불변). 워크트리 작업은 절대경로 변수로: `MAIN_ROOT=$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')`(첫 항목=main 워크트리), `WT="$MAIN_ROOT/.worktrees/<slug>"`.
- **cairn 명령은 항상 프로젝트 루트 CWD 고정 서브셸**: `(cd "$MAIN_ROOT" && bash ~/.cairn/current/bin/cairn <verb> ...)` — cairn이 CWD의 git toplevel로 원장을 해석(cairn.py:19-42)하고 `--file` 오버라이드가 없어(1965-2001), 워크트리 CWD 실행은 워크트리 로컬 `.cairn` **원장 파편화**를 만든다(baton 기본 shared_links에 `.cairn` 없음). 서브셸이라 세션 CWD 불변.
- **baton verb는 워크트리 CWD 고정 서브셸**: `(cd "$WT" && bash ~/.baton/current/bin/baton <verb>)` (baton SPEC: main root에선 wt-create 등만 허용, save/finish는 워크트리 안).
- **main 워크트리 내부 판정**: 경로 문자열이 아니라 `git rev-parse --show-toplevel` == `$MAIN_ROOT` **&&** `git branch --show-current` ∈ {main, master}. main 하위 디렉토리 CWD도 내부로 판정된다.

**§1 킥오프 훅 — 순서가 규범 (degrade 기록 휘발 방지)**:
0. **check-only 형상은 워크트리·baton·cairn 훅 전체 skip** — `$WT`/`$BRANCH` 미정의이므로 §2(PR 권고 포함)·§4도 전체 skip. 현행 독립 동작 그대로.
1. (baton on/required && main 내부 && 코드 변경 형상) `/baton:wt-create <slug>` → `WT` 확정. **이미 워크트리 안이면**: 그 워크트리의 `state/ACTIVE` 확인 — **타 피처 ACTIVE 존재 시 무단 재사용 금지**, 보고 후 사용자 결정(기존 복원 / 새 워크트리 생성). `.worktree-info.json`·심링크는 baton이 생성 — FT는 존재 확인만.
2. **FT 킥오프 선행**: `$WT/.fable-team/state/ACTIVE` + state.md 생성(워크트리 없으면 현 루트 — 현행 동작). `.fable-team/`은 워크트리 루트에, main 잔존 금지.
3. **1의 실패·degrade를 state.md 이벤트 로그에 소급 기록**(기록처가 state.md 생성 뒤로 강제돼 휘발 없음). required 실패로 §0 fail-fast 중단하는 경우만 세션 보고로 종결(durable 부작용 없음).
4. cairn 훅(state.md 생성 후 — 실패 즉시 이벤트 로그 기록 가능):
   - **정본 경로 = spawn (채택)**: 부팅 보드에서 확정한 parent 노드로 `cairn spawn ft-<slug> --from <parent> --return-to <parent> --worktree "$BRANCH" --session "fable-team:$WT/.fable-team/state/ACTIVE"` 1명령 — 계보(return_to) 유지로 complete가 `--force` 없이 정상 닫히고(cairn.py:1040-1043), execution_ref·session_ref를 생성 시 원자 설정(별도 link 불요). `BRANCH=$(git -C "$WT" branch --show-current)` — **execution_ref의 canonical 형식은 경로가 아니라 브랜치명**(reconcile이 `branch refs/heads/<branch>`와 대조, cairn.py:1106-1117).
   - **폴백 = add-task (parent 부재·사용자 미지정 시에만)**: `cairn add-task <project> <milestone> ft-<slug> [--days N]` → `cairn link <tid> --execution-ref "$BRANCH" --session-ref "fable-team:$WT/.fable-team/state/ACTIVE"`(**--session-ref는 이 1회뿐** — 이후 재사용 금지, 대입 덮어쓰기라 킥오프 포인터가 소실됨). 종결 시 `complete --force`가 필요해 `forced_complete` 표식이 남음 — 트레이드오프(계보 없음·복귀 안내 없음)를 이벤트 로그에 명기. 트레이드오프 요약: spawn=계보·정상 닫힘·1명령 원자성 ↔ parent 필요 / add-task=무전제 ↔ force 닫힘·link 1회 추가.
   - 발급 tid를 state.md frontmatter `cairn_task: <id>`에 write-through. **stage 전이·라운드는 cairn에 절대 기록하지 않는다**(2상태 원칙).
5. **required 훅 실패 분기**: 대화형이면 보고·대기(§0). **headless `deny`면 롤백 후 종료** — 생성된 state.md·ACTIVE 삭제 + spawn된 cairn 노드 제거: `(cd "$MAIN_ROOT" && cairn remove-task <project> <milestone> <tid>)` (**3인자 시그니처** — project/milestone은 킥오프 §1-4 확정값, **3번째 인자는 spawn이 발급한 실제 task id(`tN`) = frontmatter `cairn_task` 값** — 태스크 이름 `ft-<slug>` 아님. §0 롤백 규칙). `allow-degrade`면 이벤트 로그 요란한 기록 후 독립 속행.

**§2 종결 훅** (stage 6 — playbook status:done 기록·ACTIVE 제거 **후**, 양 리뷰 합의 순서 유지):
1. baton: `save`(NEXT.md 한 줄 포인터만) → `finish` — 워크트리 CWD 서브셸. `wt-clean` 자동 실행 금지(사람 게이트).
2. cairn: `cairn complete <cairn_task>`(spawn 경로 — return_to 복귀점을 종결 보고에 포함) / add-task 폴백이면 `complete <cairn_task> --force`.
3. PR 권고 보고: `.worktree-info.json` 경과일 + `git -C "$WT" log main..HEAD --oneline | wc -l` 커밋 수 + "PR → 머지 → `/baton:wt-clean --merged`" 1줄.
4. 훅 실패는 FT 종결을 막지 않는다(순서가 보장). on=degrade 기록, required=§0 종결 미완 보고·대기.

**§3 세션 재시작 — 정본은 항상 FT §4 (합의 유지) + 발견 채널 교정**:
- 복원 **정본** = `.fable-team/state/ACTIVE` + state.md. 발견 채널의 포인터엔 stage·카운터 본문이 없어 이중 복원이 구조적으로 불가(합의 논증 유지).
- **발견 채널 = baton status(1순위) + `.worktrees/*/.fable-team/state/ACTIVE` glob(보조 — FT 자기 자산이라 절연 무관)**. **cairn은 발견 채널에서 제외** — `map`은 파일 경로만 출력해(cairn.py:1067-1072) 조회 표면이 아님. cairn에 공식 조회 표면이 생기면 재검토(보류 명시).
- main 워크트리 내부 재트리거(ACTIVE 미발견) 시 §3.2의 discovery 수행 → 발견 워크트리로 **절대경로 운용** 복원(cd 금지). 활성 다수면 사용자 선택 질의. off/미감지면 신규 플로우.
- `cairn reconcile`은 자동 실행 금지 — 불일치 의심 시에만 1회, orphan 목록을 사용자 보고·결정 위임(원장 자동 교정 금지).

**§4 블록·언블록 훅** (cairn on/required 시 — 상태 동기화가 아니라 가시성 이벤트):
- 블록(status: blocked 진입): `cairn link <cairn_task> --add-session "fable-team:blocked:<ts> <사유 한 줄>"` — **누적**(session_chain, cairn.py:1145-1152). `--session-ref` 사용 금지(킥오프 포인터 덮어쓰기). 값에 `fable-team:` 프리픽스 강제 — --add-session이 session_ref 최신을 갱신해도 발견 가능성 유지.
- **언블록(대칭 훅)**: blocked 해제 시 `--add-session "fable-team:active:<ts>"` 1줄. set-status 등 상태 필드 조작 금지(2상태 원칙).
- 주기록은 언제나 FT 이벤트 로그 — cairn 이벤트는 부가 가시성이며 실패 시 degrade로 흡수.

**§5 tmuxc 경계 (합의 유지)**: 파이프라인 워커 오케스트레이션·모니터링·원장=FT / FT 오케스트레이터 세션 자체의 기동·리모트·tmux 복원=tmuxc / 세션 증류=tmuxc / FT 밖 신규 세션 기동=tmuxc. 금지: FT 파이프라인 내부 워커의 tmuxc 세션 스폰.

**§6 버저닝·절연 규칙 (합의 유지 + CWD 규칙 편입)**: ① 참조는 명령 인터페이스만(`~/.baton/current/bin/baton <verb>`, `~/.cairn/current/bin/cairn <verb>`, 슬래시 명령) — phase.json·plan.yaml·NEXT.md 스키마 파싱 금지(stdout 요약만 읽음). ② 명령 실패·인터페이스 변경은 degrade 경로로 흡수. ③ 파일 직접 Write 금지 — 공식 명령 경유만. ④ **§공통 CWD 규칙**(cairn=MAIN_ROOT 고정, baton=WT 고정, 세션 cd 금지)은 절연의 일부 — 위반 시 원장 파편화.

### 3.4 context-management.md — §5 교체

「§5 baton·cairn 연동 — `references/integrations.md` 참조 (프로파일 게이팅)」: 계층 분리 원칙·worktree 정합 항목 유지, 감지·훅 절차는 포인터로 대체. frontmatter 예시에 `cairn_task: none` 추가. "항상 디스크" 목록에 `cairn_task 포인터(연동 on 시)` 추가. §4-1 복원 진입에 §3.2 discovery 확장 1줄 반영.

### 3.5 orchestration-playbook.md·feature-interview.md — 각 1줄

playbook 파이프라인 0·6 줄 끝 `(+연동 훅 — integrations.md §1/§2 순서 준수)`. feature-interview §4에 "integrations on 시 부팅 보드에 워크트리·cairn 노드(spawn parent) 항목 포함" 1줄.

## 4. 검증 시나리오 (tester 실행 케이스)

1. **미설치 무저하**: off 또는 미설치 환경 피처 1건 부팅→종결 — 프로브 0회·추가 명령 0회.
2. **required 프로브 강제**: `baton: required` + `~/.baton/current` 리네임 → 허들 보고·대기. 무단 킥오프=실패.
3. **required × 훅 명령 실패**: cairn required + 프로브는 통과하되 spawn이 실패하도록 parent 노드 삭제 → 킥오프 훅 4에서 보고·대기(degrade 독립 진행하면 실패). headless(`claude -p`) + `deny` → fail-fast 종료 — **롤백 후 ACTIVE·state.md 미존재 && spawn 노드 부재(원장 잔존 0)** assert / `allow-degrade` → 속행 + 이벤트 로그·종결 보고 ⚠ 표기 assert.
4. **main 하위 디렉토리 킥오프**: `<MAIN_ROOT>/src/` CWD에서 트리거 → main 내부 판정(toplevel+브랜치) → wt-create → `$WT`에 `.fable-team/` 생성, main 루트 잔존 없음, **세션 CWD 불변** assert.
5. **CWD 원장 파편화 방지**: 킥오프·종결·블록 훅 전체 수행 후 `$WT/.cairn` **부재** && `$MAIN_ROOT/.cairn/plan.yaml` 단일 갱신 assert.
6. **complete 정상 닫힘**: spawn 경로 종결 시 `complete`가 `--force` 없이 성공 + return_to가 종결 보고에 포함. add-task 폴백은 `--force` 성공 + `forced_complete` 표식·이벤트 로그 사유 assert.
7. **reconcile 무오탐**: 킥오프 직후(워크트리 활성) `cairn reconcile` → 해당 노드 orphan 미보고(execution_ref=브랜치명 형식 검증). 워크트리 강제 삭제 후 재실행 → orphan 보고 + FT가 원장 자동 수정하지 않고 사용자 위임.
8. **session_ref 보존**: 킥오프 포인터 설정 → 블록 → 언블록 후 `session_chain`에 킥오프 포인터·blocked·active 3항 누적 && 최신 session_ref가 `fable-team:` 프리픽스 유지 assert. 어느 시점에도 `--session-ref` 재호출 0회.
9. **main root 재시작 discovery**: stage 3 세션 사망 → main root 새 세션 트리거 → 부팅 1에서 baton status+glob discovery → 발견 워크트리 절대경로로 §4 복원 1회(cd 0회). NEXT.md에 본문 있거나 복원 2경로 중복이면 실패.
10. **종결 순서·안전**: ①FT done+ACTIVE 제거 → ②baton save/finish → ③cairn complete → ④PR 권고. wt-clean 자동 실행 또는 ②③ 실패가 FT 종결 롤백시키면 실패.
11. **degrade 기록 내구성**: on + wt-create 실패 유도 → 킥오프 완료 후 state.md 이벤트 로그에 degrade 소급 기록 실재 assert(세션 컨텍스트에만 있으면 실패).
12. **워크트리 재사용 충돌**: 피처 A ACTIVE인 워크트리 안에서 피처 B 트리거 → 무단 재사용 없이 보고·사용자 결정 대기.

## 5. 리스크·미결

- **cairn CWD 파편화는 규율 의존** — §공통 서브셸 규칙을 안 지키면 워크트리 로컬 `.cairn`이 조용히 생긴다. 검증 5가 회귀 감시. 근본책(cairn `--root` 옵션)은 cairn 쪽 개선 후보로만 기록.
- **spawn parent 부재 프로젝트** — `.cairn/` 미초기화 또는 parent 없음이면 add-task 폴백조차 project/milestone 필요. 부팅 보드에서 "cairn 원장 미초기화 — init?" 1회 질문(자동 init 비권장 유지).
- **브랜치명 canonical의 전제** — wt-create가 만든 브랜치를 `git -C "$WT" branch --show-current`로 실측 취득(형식 하드코딩 금지). detached HEAD면 빈 문자열 — 그 경우 execution_ref 생략 + degrade 기록.
- **--add-session 노이즈** — 블록·언블록 반복 시 session_chain이 길어짐. 가시성 이벤트라 무해하나, 과다 시 FT 이벤트 로그만으로 축소 가능(cairn 이벤트는 옵션).
- **required 팩 배포 노출** — install.json은 로컬 산물, integrations.md §0에 "팩 기본 off" 명기로 방어.
- **check-only·문서만 수정 경계** — 워크트리 항목을 부팅 보드에서 사용자가 끌 수 있음(기존 컨펌 게이트 지원).
- baton 훅의 JOURNAL.md turn 누적 — 무해 노이즈, 절연 원칙상 FT가 끄지 않음.

## v2 변경 요약 (게이트 반영)

| # | finding (레벨) | 반영 위치 |
|---|----------------|-----------|
| 1 | cairn CWD 원장 파편화 (P1) | §3.3 §공통(MAIN_ROOT 고정 서브셸)·§6-④·리스크 1·검증 5 |
| 2 | complete 항상 차단 (P1) | §3.3 §1-4: **spawn 채택**(계보·정상 닫힘·1명령), add-task+`--force`는 폴백으로 격하 + 트레이드오프 명시·검증 6 |
| 3 | link session_ref 덮어쓰기 (P1) | §1-4(--session-ref 1회 원칙)·§4(--add-session 누적 + fable-team: 프리픽스)·검증 8 |
| 4 | reconcile 비교 기준 (P1) | canonical execution_ref=**브랜치명**(cairn.py:1106-1117 실측), `git -C $WT branch --show-current` 취득·검증 7 |
| 5 | required가 프로브만 차단 (P2) | §3.0 required 정의 확장(킥오프 훅 실패도 보고·대기)·검증 3 |
| 6 | required×headless 데드락 (P2) | §3.0 headless_override(allow-degrade=요란한 기록 / deny=fail-fast)·§3.1 질문 추가·검증 3 |
| 7 | discovery 부팅 미삽입 (P2) | §3.2 부팅 시퀀스 1 확장 문구 실삽입 |
| 8 | degrade 기록 휘발 (P2) | §1 순서 재정의: state.md 선생성(2) → 소급 기록(3) → cairn 훅(4)·검증 11 |
| 9 | main 판정·cd 금지 (P2) | §공통: toplevel+브랜치 판정, 절대경로 운용·서브셸, 세션 cd 금지·검증 4·9 |
| 10 | cairn map 발견 채널 불가 (P2) | §3: 발견=baton status+ACTIVE glob, cairn 제외(조회 표면 생길 때까지 보류) |
| 11 | 언블록 훅 누락 (P2) | §4 대칭 훅(`fable-team:active:<ts>`)·검증 8 |
| 12 | 워크트리 재사용 충돌 (P2) | §1-1 타 피처 ACTIVE 검사·검증 12 |
| 13 | install.json SSOT·우선순위 (P3) | §3.0: 발동 설치본 단일 파일, project>user, 병합 금지 |
| 14 | 검증 커버리지 (P3) | §4 시나리오 12건으로 재구성(신규: 3·4·5·6·8·9·11·12) |

불변 유지(양 리뷰 합의): 게이팅 3레벨·생명주기 경계 훅·포인터 원칙(FT state 유일 SSOT, cairn 2상태)·복원 정본=FT §4·버저닝 절연·wt-clean 사람 게이트·tmuxc 경계 표·종결 순서.
