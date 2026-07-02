# fable-team 연동 — baton·cairn 프로파일 게이팅

**레이어 정의 (불변)**: FT state(`.fable-team/state/`) = 유일한 파이프라인 SSOT / baton(`.baton/`) = 워크트리·세션 간 내비게이션(앞뒤만, 중간은 포인터) / cairn(`.cairn/`) = 프로젝트 작업 원장(피처 1건 = 노드 1개, 생명주기 경계에서만 터치) / tmuxc = FT 밖(§5). 교환하는 것은 상태 본문이 아니라 **포인터와 이벤트**뿐이다.

## §0 게이팅 모델

`install.json`에 선언 (설치 인터뷰 §4.5에서 기록, "FT 업데이트"가 보존):

```json
"integrations": { "baton": "off|on|required", "cairn": "off|on|required", "headless_override": "deny|allow-degrade" }
```

- **SSOT·우선순위**: FT는 발동된 설치본의 install.json **단일 파일만** 읽는다(병합 금지). project 설치본과 user 설치본 공존 시 **project 우선**(발동된 쪽이 정본).
- **off** (팩 기본): 훅 전부 미실행, 프로브조차 안 돎 — 미설치 환경과 동일(기능 저하 없음).
- **on**: 부팅 허들에서 가용성 프로브 → 성공 시 훅 실행, 실패(프로브·훅 명령 모두) 시 **graceful degrade** — 이벤트 로그 1줄 기록 후 독립 속행(차단 금지).
- **required**: **프로브 실패뿐 아니라 킥오프 생명주기 훅 명령 실패(wt-create·spawn/add-task·link)도** 사용자 보고 후 대기 — 무단 독립 진행 금지. 사용자 "이번만 독립 진행" 승인 시에만 degrade. 종결 훅 실패는 FT 종결을 롤백하지 않되(§2-4) required면 "연동 종결 미완(cairn 미닫힘)"을 이벤트 로그에 기록하고 다음 행동 전 사용자 보고·대기.
- **required × 무인(headless) 데드락 방지**: AskUserQuestion 채널이 없는 실행(`claude -p` 등)에서 required 실패 시 — `headless_override: allow-degrade`가 **사전선언**돼 있으면 degrade 허용하되 **요란한 기록**(이벤트 로그 + 종결 보고 첫 줄 `⚠ required-integration degraded (headless override)`). 기본 `deny`면 **fail-fast 중단 + 롤백** — 허들 프로브 실패면 ACTIVE·state 생성 전이라 그대로 종료, **킥오프 훅 실패면(§1 순서상 state 선생성 뒤) 생성된 state.md·ACTIVE와 부분 cairn 부작용(spawn된 노드 → `remove-task <project> <milestone> <tid>` 3인자)을 롤백 후 종료**. 어느 경로든 "durable 부작용 없음" 계약 유지, 재트리거 시 신규 플로우(orphan ACTIVE 잔존 금지). 무한 대기 데드락 금지. 종결 훅 실패의 required 대기도 headless면 동일 override 정책 — `deny`는 대기 대신 "연동 종결 미완" 기록 후 종료(FT 종결은 이미 완료라 무해).

**가용성 프로브** (존재+응답만, 내부 스펙 불파싱): `bash ~/.baton/current/bin/baton status < /dev/null` exit 0, `(cd "$MAIN_ROOT" && bash ~/.cairn/current/bin/cairn status < /dev/null)` exit 0.

## §공통 — CWD·경로 규칙 (전 훅 적용)

- **세션 CWD는 절대 바꾸지 않는다**(cd 금지). 워크트리 작업은 절대경로 변수로: `MAIN_ROOT=$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')`(첫 항목=main 워크트리), `WT="$MAIN_ROOT/.worktrees/<slug>"`.
- **cairn 명령은 항상 프로젝트 루트 CWD 고정 서브셸**: `(cd "$MAIN_ROOT" && bash ~/.cairn/current/bin/cairn <verb> ...)` — cairn은 CWD의 git toplevel로 원장을 해석하고 `--file` 오버라이드가 없어, 워크트리 CWD 실행은 워크트리 로컬 `.cairn` **원장 파편화**를 만든다(baton 기본 shared_links에 `.cairn` 없음). 서브셸이라 세션 CWD 불변.
- **baton verb는 워크트리 CWD 고정 서브셸**: `(cd "$WT" && bash ~/.baton/current/bin/baton <verb>)` (main root에선 wt-create 등만, save/finish는 워크트리 안).
- **main 워크트리 내부 판정**: 경로 문자열이 아니라 `git rev-parse --show-toplevel` == `$MAIN_ROOT` **&&** `git branch --show-current` ∈ {main, master} — main 하위 디렉토리 CWD도 내부로 판정.

## §1 킥오프 훅 (컨펌 게이트 직후 — 순서가 규범)

0. **check-only 형상은 워크트리·baton·cairn 훅 전체 skip** — `$WT`/`$BRANCH` 미정의이므로 §2(PR 권고 포함)·§4도 전체 skip.
1. (baton on/required && main 내부 && 코드 변경 형상) `/baton:wt-create <slug>` → `WT` 확정. **이미 워크트리 안이면**: 그 워크트리의 `state/ACTIVE` 확인 — **타 피처 ACTIVE 존재 시 무단 재사용 금지**, 보고 후 사용자 결정. `.worktree-info.json`·심링크는 baton이 생성 — FT는 존재 확인만.
2. **FT 킥오프 선행**: `$WT/.fable-team/state/ACTIVE` + state.md 생성(워크트리 없으면 현 루트). `.fable-team/`은 워크트리 루트에 — main 잔존 금지.
3. 1의 실패·degrade를 state.md 이벤트 로그에 **소급 기록**(기록처가 state.md 생성 뒤로 강제돼 휘발 없음).
4. cairn 훅 (state.md 생성 후 — 실패 즉시 이벤트 로그 기록 가능):
   - **정본 = spawn**: `(cd "$MAIN_ROOT" && cairn spawn ft-<slug> --from <parent> --return-to <parent> --worktree "$BRANCH" --session "fable-team:$WT/.fable-team/state/ACTIVE")` — 계보(return_to) 유지로 complete가 `--force` 없이 닫히고, execution_ref·session_ref 원자 설정. `BRANCH=$(git -C "$WT" branch --show-current)` — **execution_ref의 canonical 형식은 브랜치명**(reconcile이 브랜치와 대조 — 경로를 넣으면 항상 orphan 오보).
   - **폴백 = add-task** (parent 부재·사용자 미지정 시): `cairn add-task <project> <milestone> ft-<slug> [--days N]` → `cairn link <tid> --execution-ref "$BRANCH" --session-ref "fable-team:$WT/.fable-team/state/ACTIVE"` — **`--session-ref`는 이 1회뿐**(대입 덮어쓰기). 종결 시 `complete --force` 필요(`forced_complete` 표식) — 트레이드오프를 이벤트 로그에 명기.
   - 발급 노드의 **전체 주소를 write-through**: state.md frontmatter `cairn_task: <project>/<milestone>/<tid>` — 롤백 3인자·complete 인자의 유일한 출처(tid만 요구하는 명령은 마지막 요소 사용). **stage 전이·라운드는 cairn에 절대 기록하지 않는다**(2상태 원칙 — 열림→닫힘만).
5. **required 훅 실패 분기**: 대화형이면 보고·대기(§0). headless `deny`면 **롤백 후 종료** — state.md·ACTIVE 삭제 + `(cd "$MAIN_ROOT" && cairn remove-task <project> <milestone> <tid>)` — **3인자는 frontmatter `cairn_task` 전체 주소를 분해해 조립**(tid = spawn 발급 task id, 태스크 이름 아님). `allow-degrade`면 요란한 기록 후 독립 속행.

## §2 종결 훅 (stage 6 — status:done 기록·ACTIVE 제거 **후**)

1. baton: `save`(NEXT.md엔 **한 줄 포인터만**: "fable-team 파이프라인 — .fable-team/state/ACTIVE 참조, 재트리거 시 자동 복원") → `finish` — 워크트리 CWD 서브셸. **`wt-clean` 자동 실행 금지**(머지 = 사람 게이트).
2. cairn: `complete <tid>`(tid = `cairn_task` 주소의 마지막 요소. spawn 경로 — return_to 복귀점을 종결 보고에 포함) / add-task 폴백이면 `complete <tid> --force`.
3. PR 권고 보고: `.worktree-info.json` 경과일 + `git -C "$WT" log main..HEAD --oneline | wc -l` 커밋 수 + "PR → 머지 → `/baton:wt-clean --merged`" 1줄.
4. **훅 실패는 FT 종결을 막지 않는다**(순서가 보장). on=degrade 기록, required=§0 종결 미완 보고·대기(headless는 override 정책).

## §3 세션 재시작 — 발견 채널 vs 복원 정본

- 복원 **정본** = `.fable-team/state/ACTIVE` + state.md (context-management §4, 불변). 발견 채널의 포인터엔 stage·카운터 본문이 없어 **이중 복원이 구조적으로 불가**.
- **발견 채널** = `baton status`(1순위) + `<MAIN_ROOT>/.worktrees/*/.fable-team/state/ACTIVE` glob(보조 — FT 자기 자산이라 절연 무관). **cairn은 발견 채널에서 제외** — `map`은 파일 경로만 출력해 조회 표면이 아님(공식 조회 표면이 생기면 재검토).
- main 워크트리 내부 재트리거(ACTIVE 미발견) 시 discovery 수행 → 발견 워크트리로 **절대경로 운용** 복원(cd 금지). 활성 다수면 사용자 선택 질의. off/미감지면 신규 플로우.
- `cairn reconcile`은 자동 실행 금지 — 불일치 의심 시에만 1회, orphan 목록을 사용자 보고·결정 위임(원장 자동 교정 금지).

## §4 블록·언블록 훅 (cairn on/required — 상태 동기화가 아니라 가시성 이벤트)

- 블록(status: blocked 진입): `cairn link <cairn_task> --add-session "fable-team:blocked:<ts> <사유 한 줄>"` — **누적**. `--session-ref` 사용 금지(킥오프 포인터 덮어쓰기). 값에 `fable-team:` 프리픽스 강제.
- **언블록(대칭)**: 해제 시 `--add-session "fable-team:active:<ts>"` 1줄. set-status 등 상태 필드 조작 금지.
- 주기록은 언제나 FT 이벤트 로그 — cairn 이벤트는 부가 가시성, 실패는 degrade 흡수.

## §5 tmuxc 경계

| 영역 | 담당 |
|------|------|
| 파이프라인 워커 오케스트레이션·모니터링·원장 | **FT** (Agent/Workflow + state/) |
| FT 오케스트레이터 세션 자체의 기동·리모트·tmux 복원 | tmuxc |
| 세션 증류(distill) | tmuxc |
| FT 밖 신규 작업 세션 기동 | tmuxc |

금지: FT 파이프라인 워커의 **오케스트레이션을 tmuxc 세션으로 대체**하는 것(스폰 경로 분리 — 외부 CLI는 미들웨어 드라이버 서브에이전트가 Bash 실행). 가시성은 세션 우측 pane(서브에이전트)이 기본 담당 — tmux 테일러는 선택 보조(SKILL.md 가시성 규범).

## §6 버저닝·절연 규칙

① 참조는 명령 인터페이스만(`~/.baton/current/bin/baton <verb>`, `~/.cairn/current/bin/cairn <verb>`, 슬래시 명령) — phase.json·plan.yaml·NEXT.md 스키마 파싱 금지(stdout 요약만). ② 명령 실패·인터페이스 변경은 degrade 경로로 흡수(FT 파이프라인 무영향). ③ baton/cairn 파일 직접 Write 금지 — 공식 명령 경유만. ④ §공통 CWD 규칙(cairn=MAIN_ROOT 고정, baton=WT 고정, 세션 cd 금지)은 절연의 일부 — 위반 시 원장 파편화.

## 검증 시나리오

설계 문서 `docs/design-baton-cairn-integration.md` §4의 12개 시나리오가 정본 — 특히 ① off/미설치 무저하(프로브 0회) ② required 훅 실패 시 headless deny 롤백 후 원장 잔존 0 ③ CWD 원장 파편화 방지($WT/.cairn 부재) ④ session_ref 보존(session_chain 누적) ⑤ main root 재시작 discovery 단일 복원.
