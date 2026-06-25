# cairn — 설계 문서 (Root Ledger 복구 레이어)

> 상태: **초안(리뷰 대기)** · 2026-06-24 · 입력: `root-ledger-planning-brief.md` + 적대 DA 2라운드(아키텍처·제품·실현가능성·가치 / 네이밍·패키징)
> 전신: `docs/design-v1.md` (BYZ-Plan v1, 확정·49 tests green) — cairn은 이를 **리브랜딩 + 복구 레이어 확장**한다.
> 검증 산출물: 워크플로우 `root-ledger-brief-analysis`, `naming-da-loop`

---

## 0. 한 줄 정의

> **cairn은 마일스톤·태스크 일정(기간·듀데이트·간트)을 관리하는 경량 일정관리 원장이며, 그 위에 멀티에이전트 fan-out 복구 레이어를 옵트인으로 얹는다.**
> 두 얼굴이 하나의 원장(`.cairn/plan.yaml`): 평소엔 **사람의 일정관리**, fan-out 시엔 **에이전트의 복귀경로 보존**. 복구는 새 저장소가 아니라 baton·git·tmuxc 위 **read-only join**.
> **baton = 앞으로 핸드오프(릴레이 바통). cairn = 일정 토대 + 돌탑 따라 돌아오는 길.**

### 0.1 cairn의 두 얼굴 (동일 원장 · 치우침 없음)

| 얼굴 | 누가/언제 | 무엇 | 위상 |
|---|---|---|---|
| **일정관리** | 사람, 평소 | 마일스톤/태스크 · 기간 · 듀데이트 · 간트 · 진행률 | **기본(토대)** |
| **복구** | 에이전트, fan-out 시 | spawn/return · worktree join · recovery-map | 확장(**옵트인**) |

같은 `.cairn/plan.yaml`, 같은 `cairn` CLI. 평범한 일정관리 사용자는 복구 메타를 볼 필요 없고, **복구 필드는 에이전트가 fan-out할 때만 채워진다.** 일정관리는 곁다리가 아니라 1급 토대다 — 복구로 치우치지 않는다.

---

## 1. 절대 제약 (전신에서 계승, 불변)

- 사용 규모: 1~10명, 프로젝트 4개 안팎 (소수 정예) + 멀티에이전트 fan-out
- 유지보수: 1인 → 한 사람 머릿속에 다 들어와야 함
- 가장 무서운 것: **과적합 + 운영 불가 무거운 시스템** / **stale 그래프가 틀린 복귀점을 자신있게 제시(false confidence)**
- 원칙: YAGNI 무자비. "이거 빼면 안 되나?"를 통과 못 하면 v0에서 제외.

---

## 2. Motivating Example — 이 기획 세션이 곧 살아있는 사례

cairn을 기획하는 이 세션에서, 사용자는 핵심 작업("브리프→기획 전환") 진행 중 추가 요청을 **세 번 연속 spawn**했다:
1. 그래프 렌더(termaid + 휘발성 뷰) 추가 고려
2. 정체성 재정의(.plan 폴더·듀얼모드·엔터프라이즈·자연어)
3. 네이밍·패키징 재정의

각 추가는 현재 태스크를 확장하고, 원장을 누적·오염시키며, 증류(컨텍스트 압축)로 이어지면 **원래 복귀점을 잃는** 전형적 패턴이다. 이것이 정확히 브리프가 말한 *"complete work locally but lose the path back."*

→ cairn이 있었다면: 세 추가는 현재 노드에서 자동 **spawn**되어 `return_to=브리프→기획`으로 매달리고, 각자 완료 후 **squash로 복귀**하며, 세션 간 통신으로 유실 없이 가볍게 처리됐을 것이다. **만든 사람조차 기획하는 순간 이 패턴이 터진다는 것이 dogfooding 부재 우려에 대한 가장 강한 반증이다.**

---

## 3. DA 적대검증으로 살아남은 핵심 (생존논제)

4관점 DA(제품·아키텍처·실현가능성·가치)가 브리프를 강하게 공격한 뒤, 다음만 살아남았다 — cairn의 존재 이유:

1. **`return_to`/`merge_back_to`를 1급 필드로 명시** — 기존 도구(beads, GSD, git)는 parent/blocker는 잘 표현해도 "완료 후 어디로 돌아가는가"를 명시 필드로 두지 않는다. **진짜 비어있던 칸.**
2. **분산된 소스를 한 노드 아래 read-only join** — byzplan(계획)·baton(워크트리/세션 계보)·git(커밋)·tmuxc(런타임)가 흩어져 사람이 머릿속에서 합치는 마찰을 제거.
3. **distillation lineage + 압축 경고** — 반복 증류가 정보를 잃는다는 관찰은 타당. baton digest를 보완 (단 임계값은 자동측정 포기, count·depth 휴리스틱).
4. **append-only + regenerable projection 원칙** — "시각화 실패가 계획상태 손실이 되면 안 된다." byzplan render와 일치, 이미 검증.
5. **git-불변 복구 메타데이터** — `plan_ref`/`spawned_from`/`return_to`/`merge_back_to`/`fanout_depth`는 git lineage에 의존하지 않는 순수 ledger 사실 → squash와 무관하게 보존.

### DA가 무너뜨려 우리가 의도적으로 버린 것

| DA 반론 (critical/high) | cairn의 대응 (확정 결정으로) |
|---|---|
| **C1 자기모순**: drift하는 AI가 원장만 성실히 갱신? → stale = false confidence | **D2 훅 자동캡처** — 인프라가 갱신 보장, 에이전트 성실성에 의존 안 함 |
| **C3 동시성 충돌**: 병렬 fan-out ↔ 파일 SoT는 양립 불가 | **D3 단일 직렬 writer**(byzplan flock 계승) — 실행만 병렬, ledger 쓰기는 직렬 |
| **C4 git=원장 거짓**: squash/rebase가 lineage·SHA 파괴 | **D4** git=보조, cairn이 노드-수준 lineage 자체 소유. `current_branch`=내부 ID 참조 |
| **H1 리브랜딩**: bd+baton+GSD 합집합 | **D1 read-only join** — 새 SoT 금지, 기존 소스 위 join projection으로 격하 |
| **H4 MVP 과대**: 9커맨드=풀 PM 플랫폼 | **D5 최소 코어** — spawn/complete/return + map만. 나머지 v2 |

---

## 4. 확정 결정 (인터뷰 + DA 반영)

| # | 항목 | 결정 | 근거(대응 DA) |
|---|---|---|---|
| **D1** | 원장 형태 | **read-only join 레이어**. byzplan plan.yaml에 포인터 3개만 추가, 실데이터는 baton/git/tmuxc에 그대로 | H1 리브랜딩·governance 회피 |
| **D2** | 갱신 보장 | **훅 자동캡처**. git/baton/tmuxc 훅이 lineage 자동 기록. `return_to`만 명시 입력 + reconcile | C1 자기모순 출구 |
| **D3** | 동시성 | **단일 직렬 writer**(flock + 단일 plan.yaml, byzplan 계승). 실행은 병렬 | C3 충돌 |
| **D4** | git 관계 | **git=보조, cairn이 lineage 소유**. `current_branch`는 SHA 아닌 내부 ID | C4 squash 파괴 |
| **D5** | MVP 범위 | **최소 코어**: spawn/complete/return + recovery-map(termaid). gantt(있음)/dependency/orphan/distillation=v2 | H4 과대 MVP |
| **D6** | 패키징 | **독립 형제 + byzplan 리브랜딩**. byzplan(plan.py)→cairn으로 리네임 + 복구 확장. `.cairn` 폴더 설치. baton 통합 ❌ | 네이밍 DA: 3노드 분업·baton 비대 회피 |
| **D7** | 시각화 | **휘발성 즉시 렌더**. `/tmp/cairn/*.md` mermaid → termaid 터미널 렌더 → 휘발. 영구 대시보드 ❌ | "대시보드 무덤" 회피 |
| **D8** | distill 임계값 | **자동측정 포기**. `distill_count`+depth 거친 카운터 + N회 시 HIL 승인 | 정보보존도 측정 불가 |
| **D9** | 폴더/리브랜딩 | `plans/all.yaml`→`.cairn/plan.yaml` **이전(공존 불가)**, `plan.py`→`cairn` **즉시 리네임** | 단일 원장 폴더 일원화·점진전환 마찰 제거 |

---

## 5. 아키텍처

### 5.1 3-플러그인 분업 (스킬 간 유동 연결성)

```
        ┌─────────────────────────────────────────────────┐
        │  오케스트레이터: 사람 / LLM / Slack(Hermes, v1)   │
        └───────────────┬─────────────────────────────────┘
                        │ 자연어 또는 직접 CLI
   ┌────────────────────┼────────────────────┐
   ▼                    ▼                    ▼
[tmuxc]              [baton]              [cairn]
 실행(런타임)         기억(영속)           계획앵커 + 복구그래프
 세션 생성/통신/증류   워크트리/handoff/     ── read-only join ──┐
 hang 감지           digest/branches.json                      │
   │                    │                                       │
   └──── 훅 자동캡처 ────┴──── session_ref / execution_ref ─────┘
                        ▼
            [.cairn/plan.yaml]  (단일 직렬 writer, SoT)
                        │
                        ▼  cairn map (renderer)
            [/tmp/cairn/*.md] ──▶ termaid 터미널 렌더 ──▶ (휘발)
```

- **tmuxc** = 실행. 세션 라이프사이클·양방향 메시지·증류 트리거·hang 감지.
- **baton** = 기억. 워크트리·포트·심링크·4-template handoff·digest·`branches.json`(parent/child/merged_at).
- **cairn** = 계획 앵커 + 복구. 위 둘과 git을 **read-only join**해 recovery-map을 그림. 자체 쓰기는 plan.yaml(계획) + 복구 메타뿐.

`distill-to-worktree.sh`(구 세션 kill→새 워크트리→브리프+resume 자동주입)가 이미 "return_to의 수동 자동화"를 증명 — cairn은 이를 1급 명령/훅으로 승격.

### 5.2 3-레이어 모델 (전신 계승)

| 레이어 | cairn | 시점 |
|---|---|---|
| **① 도구(Tool)** | `cairn` CLI(=리브랜딩된 plan.py + 복구 명령). 파일을 만지는 유일 주체 | v0 |
| **② 지침(Skill)** | `cairn` SKILL.md — 언제 어떤 명령을 쓰는가 | v0~v1 |
| **③ 런타임(Runtime)** | Hermes 채널 → Slack 자연어 → cairn 호출 | v1 |

### 5.3 물리적 관리 vs 논리적 관리 (무엇을 누가 소유하나)

핵심 원칙: **cairn은 "논리(계획·복귀)"만 소유하고 쓰며, "물리(실행 아티팩트)"는 baton/git/tmuxc가 소유하고 cairn은 read-only로 참조한다.** 둘은 훅이 자동으로 잇는다(D1·D2·D4의 구체적 귀결).

| 대상 | 논리 (cairn 원장이 소유) | 물리 (실제 저장·실행, 외부 소유) | 연결 방식 |
|---|---|---|---|
| **일정** | project→milestone→task 계층, 날짜(milestone), 의존(depends_on) | `.cairn/plan.yaml` (cairn CLI가 유일 writer, flock 원자 트랜잭션) | **cairn 직접 소유**(쓰기) |
| **프로젝트** | `projects[]` 노드(id·status·owner·priority·goal) | `.cairn/plan.yaml` 블록 (후일 split 분리) | cairn 직접 소유 |
| **세션** | `session_ref` 포인터 | tmux 세션 `{base}#{N}` + claude --remote-control (tmuxc) | read-only join, tmuxc 세션생성 훅이 자동 기록 |
| **테스트/실험** | task(subtype=experiment) + `acceptance` 기준 | 코드/CI 실행, dogfood sample-app | task 노드로 표현(일반 작업과 동일 그래프) |
| **워크트리** | `execution_ref` + `fanout_depth` | `.worktrees/<name>` + 포트·심링크 (baton wt-create) | read-only join, baton 훅이 자동 기록 |
| **브랜치** | `merge_back_to` + `return_to`(git-불변 메타) | git branch + `branches.json`(parent/child/merged_at) | read-only join, git post-merge 훅이 자동 |

**생명주기 한 바퀴 (spawn→complete→return):**
```
1) cairn spawn t2 --from t1 --worktree feat-x
   논리: plan.yaml에 t2 추가 (spawned_from=t1, return_to=t1, fanout_depth+1)
   물리: baton wt-create → .worktrees/feat-x + git branch + branches.json(parent=현재)
   연결: execution_ref=feat-x 자동 기록(baton 훅)
2) (작업) tmuxc 세션 생성 → session_ref 자동 기록(tmuxc 훅)
3) cairn complete t2
   논리: status=done, 복귀 대상(return_to=t1) 명시 노출
   물리: baton wt-clean --merged → git squash merge → branches.json.merged_at
   연결: git post-merge 훅 → merge_back_to 자동
4) cairn return  → t1으로 재앵커 (컨텍스트 재주입은 baton resume에 연결)
5) cairn map     → recovery-map을 termaid로 즉시 렌더(/tmp/cairn/)
```

**왜 이 분리가 안전한가:** 물리(브랜치/워크트리)는 squash·rebase·삭제로 늘 변하지만, cairn이 소유한 논리 메타(`return_to`/`merge_back_to`/`spawned_from`)는 git-불변이라 그대로 보존된다(D4). 물리가 사라져도 "어디로 돌아가야 하는가"는 안 사라진다 — 이것이 복구 원장의 본질.

---

## 6. 데이터 모델 — `.cairn/plan.yaml`

전신(project→milestone→task)을 **그대로 유지**하고, task에 **복구 메타만 추가**한다. 간트는 마일스톤 전용, progress는 계산값(전신 결정 유지).

```yaml
version: 2                      # cairn 스키마
projects:
  - id: byz-agents
    name: "BYZ Agents"
    status: active
    milestones:
      - id: ms1
        name: "Realtime v2"
        status: active
        start: 2026-06-20
        end: 2026-06-30
        depends_on: []
        tasks:
          - id: t1
            name: "STT 파이프라인"
            status: doing
            start: 2026-06-25         # 자동 = 생성일(오늘)
            due: 2026-06-25           # 기본 = 생성 당일. `--days N` 지정 시 start+N
            depends_on: []
            # ── cairn 복구 메타 (옵트인 — fan-out 시에만 채워짐) ──
            spawned_from: t0          # 분기 원점 (훅 자동 or spawn 명시)
            return_to: ms1            # 완료 후 복귀 대상 (★명시 입력 — 자동 불가)
            merge_back_to: ms1        # 머지 목표 (훅 자동: git merge-base)
            fanout_depth: 1           # 분기 깊이 (계산)
            execution_ref: WT-feat-stt   # → baton branches.json (read-only)
            session_ref: byz#3           # → tmuxc 세션명 (read-only)
            distill_ref: docs/digest/stt.md  # → baton digest (read-only)
            last_reconciled: 2026-06-24T12:00  # stale 방어
```

**태스크 일정 정책 (신규 — 일정관리 1급화):**
- `start`: 태스크 **생성일 자동 기록**(오늘). 불변.
- `due`: 미지정 시 **생성 당일**(= start). `cairn add-task --days N` 또는 `set-date`로 `start+N`일. 절대날짜 수기입력 대신 **상대 N일**이 기본 — 날짜 손관리 부담 제거.
- `overdue` = `due < today AND status != done`. **마일스톤(기간 start/end)과 태스크(due) 모두** 점검.
- 마일스톤은 기존대로 기간(start/end), 태스크는 듀데이트(due) — 간트는 마일스톤 막대 + 태스크 듀 마커.

**핵심 원칙:**
- `execution_ref`/`session_ref`/`distill_ref`는 **포인터일 뿐** — 실데이터는 baton/tmuxc/git에 산다(D1).
- `current_branch`/`current_worktree`/`current_session` 같은 가변 실행상태는 노드에 **직접 박지 않는다**(D4·설계원칙 "실행≠계획"). 필요 시 `.cairn/executions/` 별도 레코드로 분리.
- 복구 메타는 전부 **옵트인** — 에이전트 fan-out 시에만 채워지고, 없으면 일반 일정관리 task로 동작(하위호환). 일정 필드(start/due)는 기본, 복구 필드는 확장.

### 6.1 `.cairn/` 폴더 구조 (D9 — 공존 불가, 모든 원장 일원화)

```
.cairn/
  plan.yaml          # SoT (기존 plans/all.yaml 이전·리네임)
  config.yaml        # read-only join 소스 경로·설정 (baton/tmuxc/git 위치)
  executions/        # execution 레코드 (current_branch 등 노드에서 분리, D4·D7)
  views/             # 렌더 결과 보관(선택) — 휘발은 /tmp/cairn/
  cache/             # projection 캐시 (재생성 가능, gitignore)
```

기존 `plans/all.yaml`·`views/plan.md`는 **`.cairn/` 하위로 이전**한다(공존 불가). 모든 원장 파일이 `.cairn/` 한곳에 모인다 — `.baton`이 `.baton/`에 모이듯.

---

## 7. CLI — `cairn`

### 7.1 계승(리브랜딩) — 기존 14개 명령 그대로
`show · status · overdue · render · set-status · set-date · set-priority · add-task · add-milestone · new-project · revert · validate · self-test` (명령명·동작 동일, 진입점 `plan.py`→`cairn` **즉시 리네임**, 별칭 점진전환 ❌ — D9).

**일정관리 강화 (신규 — 태스크 일정 1급화):** `add-task`에 `--days N`(듀데이트=`start+N`, 미지정=당일), `set-date`가 태스크 `due`도 지원, `overdue`가 태스크 듀데이트도 점검, `render`(간트)에 태스크 듀 마커 추가. 태스크 `start`는 생성 시 자동.

### 7.2 신규 복구 코어 (D5 — v0 범위)

| 명령 | 동작 |
|---|---|
| `cairn spawn <task> --from <parent> [--worktree <path>]` | 현재 노드에서 하위 작업 분기. `spawned_from`·`return_to`·`fanout_depth` 자동 기록. baton wt-create 연동 가능 |
| `cairn complete <task>` | 완료 처리 + **복귀 대상(`return_to`)을 명시 노출** ("다음: ms1로 돌아가세요") |
| `cairn return [--to <node>]` | 운영자/에이전트를 부모 복구 노드로 재앵커. **cairn 자체 커맨드로 제공하되 컨텍스트 재주입은 baton resume에 연결**(위임 X, 연결 O — D9) |
| `cairn map [--focus <node>] [--render]` | recovery-map을 mermaid로 `/tmp/cairn/`에 생성 → termaid 즉시 렌더 |
| `cairn attach <orphan> --to <node>` | 고아 브랜치/세션을 노드에 연결. **항상 제안→승인**(자동확정 ❌) |

### 7.3 v2
`gantt`(전신 render 확장)·`deps`(dependency graph)·`orphans`(자동 탐지·제안)·`distill-map`(증류 계보).

---

## 8. 훅 자동캡처 (D2 — 자기모순 C1의 출구)

에이전트 성실성에 의존하지 않고 **인프라가 lineage를 보장**한다:

| 트리거 | 자동 기록 |
|---|---|
| `git post-checkout` | 현재 worktree ↔ 노드 매핑 |
| `git post-merge` | `merge_back_to` + lineage (merge-base) |
| `baton wt-create` | `execution_ref` (새 워크트리) |
| `baton wt-clean --merged` | 머지 확정 → 노드 complete 후보 |
| `tmuxc 세션 생성(UC1)` | `session_ref` |
| **reconcile 패스**(주기/수동) | 활성 worktree ↔ 노드 대조. 누락=orphan 강등, hook 우회(force-push/GUI) 보정 |

`return_to`만 자동 불가 → **spawn 시 명시 입력**(+ git merge-base로 사후 검증). 누락 시 `complete` 차단(`--force` 우회) = 핵심 엣지만 hard gate, 나머지 soft(experimentation 보호).

---

## 9. 시각화 (D7 — termaid 휘발성 렌더)

- **필수 그래프(recovery-map)**: 현재 노드 중심 — 루트까지의 ancestry chain + spawned children + 미완 siblings + **복귀 대상**. `cairn map`이 mermaid로 `/tmp/cairn/<ts>-recovery.md` 생성 → termaid 터미널 렌더 → 휘발.
- **서포트 그래프(v2)**: milestone Gantt(전신 보유), worktree-map, distillation-lineage.
- **stale 방어**: `last_reconciled` 기준 "N일 미갱신=신뢰불가" 음영. stale projection을 의사결정 신뢰면으로 쓰지 못하게 차단(C2).
- 영구 웹 대시보드 ❌ → projection이 stale돼도 손실 0. (브리프 "regenerable views" 원칙 충실)

---

## 10. 로드맵 (D4 구축 순서 + 비전)

| 단계 | 범위 | dogfooding 게이트 |
|---|---|---|
| **v0 (지금)** | 개발용 단일 `.cairn`. byzplan 리브랜딩 + 복구 최소코어(spawn/complete/return/map) + termaid. byz-agent 하위에서 dogfooding | "복구 모델이 실제로 drift를 막는가" 단일 가설 검증 |
| **v1** | 마일스톤 전용 모드(회사 일정) + 자연어/Slack(Hermes 3-레이어 ③) | 자연어 일정관리 UX 증명 |
| **v2** | 엔터프라이즈 연합(일정 .cairn ↔ 개발 .cairn 네트워크 연결) + distillation graph + dependency/orphan auto | distillation 데이터(`sessions:[]`)가 실제로 채워지고 매일 쓰이는 것 확인 후에만 |

**비전(궁극)**: 작고 가볍고 확실한 LLM 드리븐 + Slack agent 드리븐 자연어 일정관리. 더 나아가 코딩 에이전트가 **cairn + baton + tmuxc 3종으로 "테스트 자연어 완성형 개발 주도"**.

---

## 10.5 검증 전략 — 완성의 정의 (사용자 기본 지침)

단위테스트 통과(pytest green)는 "구현"이지 "완성"이 아니다. cairn은 원장(데이터 무결성·복구경로)이 핵심이므로 다음 3단을 통과해야 "완성"으로 본다.

1. **DA approve 루프 (구현 단계)** — 각 P(특히 P3 복구 코어, P4 훅)는 구현 후 **적대 검증(DA) 루프**를 거쳐 approve 받는다. DA는 원장 무결성·복구경로·동시성·stale을 공격. subagent-driven task review 위에 얹는 추가 게이트.
2. **실증 생성 테스트 동반 (구현과 함께)** — 격리 단위테스트뿐 아니라 **실제 `.cairn/plan.yaml`에 마일스톤·태스크를 생성하고 spawn→complete→return을 실행하는 E2E 실증 테스트**를 동반. 실데이터로 원장 무결성·복구 메타·git lineage가 실제 보존되는지 증명.
3. **실사용 시나리오 랜덤 루프 시뮬레이션 (완성 게이트)** — 다 구현한 뒤, DA + **랜덤 시나리오 루프**로 마일스톤·개별작업을 다량 생성→완료→복구를 시뮬레이션 테스팅한다. 랜덤하게 spawn/complete/return/마일스톤/태스크를 섞어 돌려(property-based / simulation testing):
   - 원장이 어떤 순서에서도 깨지지 않는가 (`validate` 항상 통과)
   - 복구경로(`return_to`/`merge_back_to`)가 항상 유효한가 (끊긴 엣지 0)
   - fan-out/squash 후에도 복귀점이 보존되는가
   이 시뮬레이션이 통과해야 비로소 **"완성"**.

**적용**: P1/P2(일정관리 토대)는 단위테스트 + 실증으로, **P3/P4(복구) 완료 후 DA 루프 + 랜덤 시뮬레이션으로 v0 완성을 선언**한다. 이는 §10 로드맵의 dogfooding 게이트와 직결 — 만든 사람이 시뮬레이션을 매일 돌려 깨지지 않음을 확인한 기능만 "완성".

---

## 11. 비범위 (YAGNI — 의도적 제외)

- **멀티 writer 동시성** → 단일 직렬 writer 유지(D3). 멀티에이전트는 ledger의 read 소비자.
- **distill threshold 자동측정** → count/depth 휴리스틱 + HIL(D8).
- **git=recovery map 격상** → cairn이 lineage 소유, git 보조(D4).
- **풀 PM 기능**(권한·대시보드·자동 스케줄링) → 필요해질 때.
- **brief의 5레이어 파일구조(nodes/edges/executions/history/projections 분리)** → 단일 plan.yaml + 포인터로 축소(파일 폭발·쿼리비용 회피).

---

## 12. 확정 사항 (리뷰 완료) + 남은 미결

### 리뷰에서 확정 (2026-06-24)
1. **폴더 이전 (공존 불가)** — 기존 `plans/all.yaml` → `.cairn/plan.yaml`로 이전. 모든 원장을 `.cairn/` 하위로 일원화 (§6.1).
2. **즉시 리브랜딩** — `plan.py` → `cairn` 바로 리네임 (별칭 점진 ❌).
3. **`cairn return`은 자체 커맨드 + baton 연결** — cairn이 `return` 커맨드를 제공하되 내부에서 baton resume에 연결.
4. **README 히어로** — `assets/cairn-hero.png` 최상단 박음 (완료).

### 남은 미결 (구현 중 결정)
- baton `branches.json` 스키마 안정성에 read-only join이 의존 → baton 버전 핀 필요 여부.
- `.cairn/` 이전 시 기존 dogfood 데이터(`plans/all.yaml`, sample-app 시드) 마이그레이션 스크립트 형태.

---

## 부록 A. 이름의 유래

DA 네이밍 루프에서 clew(아리아드네 실타래)·tether(우주 안전줄)·homeport(모항)·lode(북극성) 등과 경쟁해 **cairn(케른, 등산로 돌탑)**이 선택됨. 선정 이유: 브랜드 DA 유일 keep, 충돌 위험 낮음, **map 렌더와 메타포 완벽 정합**(복구 그래프 = 돌탑들의 계보), baton과 형제 대칭(둘 다 손에 쥐는 사물 / 육상 vs 등산).

> 태그라인: *"Mark every fork. Never lose the trail back."*
> 분기점마다 돌탑을 세우고, 돌탑을 따라 길을 잃지 않고 돌아온다.
