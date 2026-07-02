# cairn render 멀티뷰 — design

Date: 2026-07-02
Origin: plan.html(mermaid gantt)이 "사람이 이해 못 하는 그래프"라는 지적 → 표현방식 실험(scratchpad `plan-view-experiments.html`) → 칸반/트리/워크트리·브랜치 3뷰 채택. 이걸 cairn 기본 제공으로 승격.

## 문제

기존 `cairn render` 산출물(`.cairn/views/plan.md` + `plan.html`)은 mermaid **gantt** 하나뿐인데, 이 데이터엔 부적합하다:
- task가 대부분 `start == due`(생성일) → 시간축이 정보 0.
- `depends_on`·milestone 의존·`execution_ref`/`branch` 관계가 그래프에 안 나타남.
- 라벨이 문장 통째라 뭉갬. 상태(todo/doing/done) 구분 약함.

## 목표

`cairn render`가 **탭 전환형 단일 HTML**(자체완결, mermaid CDN)을 기본 산출. 3뷰:
1. **칸반** — 진행중/대기/완료 3열, 카드에 milestone·task·선행. "지금 뭐 도는가" 즉시 파악.
2. **아웃라인 트리 + 진행바** — 프로젝트›마일스톤(완료율%)›task 계층. 긴 라벨 전량 표시.
3. **워크트리/브랜치** — mermaid `gitGraph`. main→feature 브랜치에서 마일스톤이 브랜치로 fan-out, done만 merge. (recovery-graph = 기존 `cairn map` 지향과 합류)

공통: 카드/행 클릭 → **원장 다이얼로그**(전체 필드) + 기획 **SSOT 파일 링크**(있으면 `file://`로 열기). `execution_ref`/`branch`가 비면 다이얼로그에 "미기록(빨강)"으로 노출 → [agent-lifecycle-hook-design](agent-lifecycle-hook-design.md) 컴포넌트 5가 채워야 함을 사용자에게 상시 상기.

gantt는 폐기(정리).

## 설계

### 템플릿 + 생성기 분리
- **템플릿**: `docs/plan-view.template.html` (이 커밋에 포함, 실험본에서 데이터만 뽑아낸 것).
  - 치환 토큰 2개: `/*__CAIRN_PLAN_JSON__*/{}` (JS `plan` 객체), `__CAIRN_PROJECT_NAME__` (헤더 표기).
- **생성기**: `cairn.py`의 render 경로가 plan.yaml → 뷰 JSON으로 매핑 → `json.dumps` → 토큰 치환 → `plan.html` 기록. 템플릿을 문자열 치환만 하므로 로직 최소.

### 필드 매핑 (yaml → 템플릿 JS)

| cairn yaml | 템플릿 JS 키 | 비고 |
|-----------|-------------|------|
| milestone.status | (뷰에서 그대로) | done/active/planned/blocked |
| task.status | `s` | todo/doing/done/blocked |
| task.name | `name` | 전문 |
| task.depends_on | `dep` | 선행 표기 |
| task.execution_ref | `exec` | 없으면 다이얼로그 "미기록" |
| (현재 branch) | `branch` | execution_ref와 함께 훅이 기록 |
| task.ssot | `ssot` | **신규 필드 필요** — 아래 참조 |
| task.note | `note` | PR#8에서 이미 존재 |
| milestone.depends_on | (gitGraph 텍스트) | gitGraph 단일부모 한계로 텍스트 표기 |

### 의존 작업 (선행)
- **`ssot` per-task 필드 (확정: A안)**: task에 `ssot` 필드 신설 + `cairn set-ssot <project> <milestone> <task> <path>` 명령 추가. note와 역할 분리(의도 명확). validate에 ssot 경로 형식 검사(선택). 템플릿은 `t.ssot`를 읽음.
- **execution_ref/branch 채움**: [agent-lifecycle-hook-design](agent-lifecycle-hook-design.md) 컴포넌트 5. 이게 없으면 뷰3(워크트리/브랜치)이 계속 단일 워크트리로 뭉침 — 두 스펙은 상보.

### 기본 산출 (확정: 기본 대체)
- `cairn render`가 멀티뷰 HTML을 **기본 산출**(gantt 완전 폐기). `plan.md`(markdown)는 호환 위해 유지하되 내용은 gantt→트리 아웃라인(마일스톤 완료율 + task 리스트, 순수 markdown)으로 대체. `plan.html`이 멀티뷰 3탭.

## 테스트
- 생성기: 샘플 plan.yaml → plan.html 생성 후, 토큰 미잔존(`__CAIRN_`) + JSON 파싱가능 + task 수 일치 확인.
- 뷰 렌더: 브라우저 없이 검증 어려움 → 최소 HTML 구조/JSON 임베드 단위테스트 + 수동 브라우저 확인(실험본으로 이미 1차 확인).
- 빈 execution_ref → 다이얼로그 "미기록" 노출 확인.

## 결정 로그
| 질문 | 결정 |
|------|------|
| gantt 유지 여부 | 폐기(정리) |
| 채택 뷰 | 칸반 + 트리 + 워크트리/브랜치(gitGraph) |
| 상세 표시 방식 | 인라인 펼치기 아님 → **다이얼로그** + SSOT 파일 링크 |
| 기본 제공 여부 | **기본 대체 확정** — render가 멀티뷰 기본 산출, plan.md는 트리 아웃라인 |
| ssot 필드 | **A안 확정** — task.ssot 신설 + `cairn set-ssot` 명령 |

## 구현 확정 (2026-07-02 프로토타입 검증 완료)

프로토타입(`plan-view.template.html` + `gen_plan_view.py` + `serve_plan_view.py`, 예제 `examples/schedule-plan.example.yaml`)으로 아래를 실제 렌더·조작 검증했다. "완벽 동작" 확인.

### 프로젝트 `type` → 3번째 뷰 분기 (신규 확정)
프로젝트에 `type` 필드 신설(`work` 기본 / `schedule`). ①칸반 ②트리는 공통, **③번째 뷰만 타입별 분기**:
- `type: work` (코드 작업) → **워크트리/브랜치** = mermaid `gitGraph`. 날짜가 생성일뿐이라 간트 무의미, execution_ref/branch 토폴로지가 맞음.
- `type: schedule` (일정관리) → **간트**. 워크트리/브랜치 개념이 없고 실제 기간(start~due)이 있어 간트가 최적.

### 간트는 mermaid 아님 — 커스텀 HTML/CSS (신규 확정, 대안 기각 근거 포함)
mermaid 간트는 **px/일(줌) 미지원 · SVG 균일확대는 세로증가/텍스트왜곡 · 윈도우이동=재렌더 꼼수(깜빡임·부분바잘림) · today 마커 DOM탐지 취약 · 생성 시 텍스트조립/이스케이프 부담**. 따라서 schedule 간트는 **HTML/CSS div-바**로 직접 렌더:
- **줌(px/일) `＋/－`**: left/width 재계산만으로 시간축 밀도 조절.
- **고정 뷰어 박스(마스크)**: 좌측 라벨 sticky, 타임라인만 박스 안에서 가로 스크롤(세로 불변).
- **오늘 중앙 + `‹ 오늘 ›`**: 오늘선을 창 중앙으로, 절반씩 이동.
- 상태색(완료/진행/대기/**블록=마감넘김·막힘**), 바/행 클릭 → 원장 다이얼로그.
- mermaid는 `type: work`의 gitGraph에만 유지(정적 그래프엔 mermaid가 적합).
- 근거: ①②(칸반·트리)가 이미 순수 HTML이라 간트도 HTML이 **일관**하고, 생성은 JSON 주입만이라 **더 단순·안정**. (렌더 로직은 템플릿 JS 1곳.)

### SSOT 열기 = serve 모드 (신규 확정)
브라우저는 `file://` 페이지에서 로컬 문서 열기를 차단(클릭 시 깜빡+무반응). 따라서 `cairn render --serve` = **localhost 서버 + `/open?path=` 엔드포인트가 서버측 OS open 실행**. `file://` 직접 열람 시엔 경로복사+안내 폴백. (서버 스크립트 프로토타입: `serve_plan_view.py`; 실제 구현은 platform별 open/xdg-open/start 처리 필요.)

### 클릭 → 원장 다이얼로그 (전 뷰 일관)
칸반 카드 · 트리 행 · **간트 바** 모두 클릭 시 동일 다이얼로그(상태/사람/선행/SSOT/execution_ref/branch/일정/note). execution_ref·branch 빈 값은 "미기록(빨강)"으로 노출 → [agent-lifecycle-hook-design](agent-lifecycle-hook-design.md) 컴포넌트 5 필요성 상시 환기.

### 생성 파이프라인 (검증됨)
`plan.yaml → gen_plan_view.py (yaml→뷰 JSON 매핑) → 템플릿 데이터 블록 치환 → plan.html`. cairn.py의 render가 이 로직을 내장(JSON 주입만, 뷰 렌더는 템플릿 JS). 프로토타입은 `~/.cairn/venv`(ruamel.yaml)로 10마일스톤·19태스크 렌더 검증.

### 후속 구현 항목
1. cairn.py: render를 멀티뷰 생성기로 교체(gantt→멀티뷰), 템플릿 임베드 + JSON 주입.
2. 스키마: 프로젝트 `type`(work/schedule), task `ssot` 필드 + `cairn set-ssot`, validate 반영.
3. `cairn render --serve`(localhost + /open, platform별 open).
4. execution_ref/branch 자동기록(agent-lifecycle-hook 컴포넌트 5)과 합류 → work 타입 gitGraph 실데이터화.
