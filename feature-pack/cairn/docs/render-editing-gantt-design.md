# cairn 웹 뷰어 — 편집·싱크·간트 확장 design

Date: 2026-07-02
Origin: 멀티뷰 뷰어([render-multiview-design](render-multiview-design.md)) "완벽 동작" 확인 후, 뷰어를 **읽기전용 → 읽기·편집**으로 확장 요청. fable5 서브에이전트 검토(간트 고급기능 감사 + 편집/싱크 스펙 허점 + 타입 매핑) 반영.

전제: 뷰어는 `cairn render --serve`(localhost)에서 편집 가능. 정적 `file://`는 읽기전용(브라우저가 쓰기·문서열기 차단).

## 0. 성패를 가르는 두 결정 (먼저 못박음)

1. **편집 페이로드 = ops 체인지셋 전용.** 브라우저는 손실 매핑된 뷰 JSON(`status→s`, `depends_on→dep` 등)만 갖는다. 이걸 역매핑해 yaml로 재직렬화하면 ruamel이 보존하는 **주석·키순서·인용부호**가 소실되고, 뷰 JSON에 없는 필드(`spawned_from`/`return_to`/`merge_back_to`/미래필드)가 **조용히 삭제**된다(=#0 RULE급 손실). 따라서 브라우저는 편집을 **op 리스트**로 축적해 전송하고, 서버가 **ruamel 로드된 원본 doc에 op만 적용**한다. 전체 문서 전송 금지.
   ```json
   [{"op":"set","target":["q3-launch","ms3","t8"],"field":"due","value":"2026-07-10"},
    {"op":"add-task","target":["q3-launch","ms4"],"task":{...}},
    {"op":"remove-task","target":["q3-launch","ms5","t12"]}]
   ```
2. **저장 = cairn core `transaction()` 1회 경유.** 직접 yaml 쓰기 금지. `transaction()`이 이미 flock → dirty-worktree 가드 → validate(의존 사이클·전역 task id 유니크·상태 어휘·역참조) → 원자쓰기 → view 재생성 → git commit → 실패 시 plan/view만 롤백을 제공한다. cairn은 "복구 CLI"라 `revert`/`reconcile`이 **커밋 이력**에 의존 — 파일만 쓰면 revert 불능 유령변경 + 다음 CLI transaction의 dirty-guard에 걸려 **모든 CLI 조작이 막힌다**. serve 핸들러가 cairn.py를 import해 `transaction(apply_ops, "web-sync: …")` 호출. **싱크 1회 = 커밋 1회**, 커밋 body에 op 요약.

## 1. 저장·싱크 모델 (확정)

- **명시적 싱크 버튼**(사용자 선택): 편집은 메모리에 dirty로 축적, 상단 싱크 버튼으로 일괄 저장. dirty 인디케이터 + `beforeunload` 경고 + 변경 0건이면 버튼 비활성.
- **충돌 감지 = 콘텐츠 해시**(mtime 아님 — FS 초해상도·git checkout이 mtime 흔듦): 페이지 생성 시 서버가 `sha256(plan.yaml)`를 `baseHash`로 임베드 → `/save` 페이로드에 동봉 → 서버가 flock 하에 현재 해시 비교 → 불일치 시 **409 + 현재 원장 재전송** → 클라이언트 "디스크 변경됨 — 재로드" 다이얼로그. (해시 일치해도 미커밋 수동변경은 transaction F2 가드가 2중 방어.)
- **외부 변경 배너**: 뷰어 포커스 복귀(`visibilitychange`) 시 `/hash` 폴링 → 변경 감지 시 상단 배너(편집 시작 전에 알림 → 편집 노동 안 버려짐). 훅(session-start→doing·execution_ref 기록)·CLI 커밋과의 경합 대비.
- v1은 3-way 머지 안 함 — 409면 재로드. (ops 방식이라 재로드 후 미충돌 op 재적용은 v2 후보.)
- **더 단순한 폴백(기록만)**: 구현이 무거워지면 "즉시 op 모드"(편집마다 `/op`→CLI 서브커맨드 즉시 transaction) 정당. 단 사용자가 명시적 싱크를 선택했으므로 배치안 유지.

## 2. serve 모드 보안 (프로토타입 갭 보정)

현 `serve_plan_view.py`는 `/open?path=`가 GET+무토큰+임의경로. 쓰기 추가 시:
- `/save`·`/open`은 **POST 전용** (GET `/open`은 악성 페이지 `<img src>`로 트리거됨).
- 기동 시 랜덤 토큰 → URL(`?t=`) 포함 → 모든 변이 요청 토큰 검증.
- `Host` 헤더 `localhost`/`127.0.0.1` 검증(DNS rebinding 방어). 127.0.0.1 바인드 유지.

## 3. 편집 UI (다이얼로그 + 타입별)

- **원장 다이얼로그 = 편집 폼**: name/status/dates/assignees·reporters·watchers/depends_on/ssot/note 편집. 저장은 메모리(dirty), 싱크로 반영.
- **상태 편집 = kind별 어휘 드롭다운**(task: todo/doing/done/blocked · ms: planned/active/blocked/done) — `active`를 task에 오입력하는 함정을 UI에서 원천 차단([agent-lifecycle-hook-design](agent-lifecycle-hook-design.md) 컴포넌트 4와 정합).
- **`execution_ref`/`branch`는 웹에서 읽기전용** — lifecycle 훅(컴포넌트 5)이 정본 기록자, 수동 편집은 훅의 멱등 갱신과 충돌.
- **추가/삭제(schedule)**: 툴바 `+마일스톤`/`+태스크` → 폼 다이얼로그(이름/사람/날짜). **삭제 포함** — 단 `remove-task`의 역참조 사전검사(depends_on·spawned_from 등이 참조 중이면 거부) 경로 재사용(웹에서 직접 지우면 이 가드 상실).
- 저장 성공 시 서버가 최신 뷰JSON+새 baseHash 반환 → 클라이언트 상태 리셋(재로드 없이 연속 편집).

## 4. 타입 ↔ 뷰 매핑 (확정)

`type` 값 = **`work`(기본) / `schedule`**. validate에 enum 검사(`∉{work,schedule}`→error), 필드 부재 시 `work`(하위호환), 별칭 금지. **type은 "③번째 뷰 스위치"일 뿐 데이터 제약이 아니다**(스펙 첫 규칙).

| 능력 | schedule (마일스톤/일정 버전) | work (테스트/코드관리 버전) |
|---|---|---|
| ①칸반 ②트리 | O | O |
| ③번째 뷰 | **간트** | **워크트리/브랜치 gitGraph**(읽기전용) |
| 필드 편집(name/status/note/사람/ssot/dep) | O | O |
| **날짜 필드 편집** | O | **O** (막는 건 간트 *드래그 UI*이지 날짜 데이터 아님 — `cairn set-date`/`overdue`는 타입 무관 동작) |
| 간트 바 드래그(이동/양끝) | O (전용) | X |
| execution_ref/branch | 읽기전용(훅 정본) | 읽기전용(훅 정본) |

- **혼합 원장**(schedule 마일스톤 + worktree 하위 태스크)은 이미 현실(예제 t5가 execution_ref/branch 보유). v1은 다이얼로그가 일정+exec/branch 전 필드를 다 보여주므로 **데이터/다이얼로그 레벨에서 수용됨** — 잃는 건 "브랜치 fan-out 그림" 하나뿐. per-milestone type 오버라이드·자동감지 탭은 **기각**(복잡도 폭발). 진짜 필요 시 **v2 = `views:[gantt,branches]` opt-in 듀얼 탭**(렌더러 둘 다 이미 구현, 탭 하나 추가가 전부).
- (v2 후보) 칸반 카드 컬럼 간 드래그 = status 변경 — 간트 드래그와 같은 ops 인프라 재사용, 양 타입 공통.

## 5. 간트 고급기능 (감사 결과)

프로토타입 기존: 줌(px/일)·마스크 스크롤·오늘선/중앙/‹›·상태색·섹션행·클릭 다이얼로그·담당자 툴팁.

### Must (편집과 같은 PR 묶음)
| 기능 | 근거 |
|---|---|
| **의존성 표시** | `depends_on`이 원장 1급 필드인데 간트에서 유일하게 안 보임 + 드래그 위반검출에도 필요. v1은 SVG 화살표 부담 시 "바 선택→선행/후행 테두리 강조"로 축소 가능 |
| **오버듀 자동 파생** | `due<today && status!=done` — `cairn overdue`에 로직 존재(cairn.py). 현재 예제는 t8을 수동 blocked로 표현(원장·시각 이중관리). **blocked(막힘)≠overdue(마감초과)** — 범례 합침 풀고 시각 분리(blocked=빨간 바 / overdue=빨간 외곽선·빗금) |
| **마일스톤 요약 바/다이아몬드** | schedule 정체가 "마일스톤"인데 현재 섹션행 track이 빈 div. start~end 요약 바 + start==end면 다이아몬드 |
| **드래그 스냅(일 단위)** | 스냅 없으면 소수점 날짜 → `YYYY-MM-DD` 원장에 못 씀. 드래그 전제조건 |
| **틱 월요일 정렬** | 현재 틱이 `min-3일`부터 7일 간격 = 임의 요일. min을 월요일 내림 정렬(주말 음영의 전제) |

### Nice (v1.x)
주말/기간외 음영 · zoom-to-fit+프리셋(주/월/분기) · 마일스톤 접기/펼치기 · 마일스톤 진행률 채움바(트리 완료율% 재사용) · 담당자 **필터**(`_task_matches` CLI 로직 재사용, 스윔레인 아님) · 줌 시 뷰포트중앙 앵커 유지(현재 무조건 오늘 재센터) · 드래그 중 날짜 툴팁.

### YAGNI (명시 스코프 아웃 — 재론 방지)
크리티컬 패스(duration 시맨틱 없음) · 태스크 %진행률(상태는 이산값, 필드 신설=원장 비대) · 담당자 스윔레인 · 키보드 이동 · PNG/CSV 내보내기(plan.yaml이 데이터·git이 이력) · 베이스라인 vs 실제(git 이력이 베이스라인) · 리소스 히스토그램/자동레벨링/반복일정(MS Project 영역, cairn 성격 반대).

## 6. 드래그 상세

- 바 몸통 드래그 = start·due 동시 이동 / 좌·우 핸들 = start·due 개별. 핸들 히트존 ≥8px, **최소 줌(4px/일)에서 핸들>바 문제** → 최소 줌에서 핸들 비활성 or 바 최소폭 보장.
- **의존 위반 = soft-warn(저장 허용), hard-block 기각** — 현실 일정은 의존을 임시로 깨며 조정. validate엔 날짜-의존 정합 검사가 없어 원래 합법(사이클·참조무결성만 검사). 자동 캐스케이드(후행 연쇄 이동) **기각**(클릭 한 번에 원장 10곳 변경=추적성 재앙). validate warning 레벨은 선택(error 금지 — 기존 원장 깨짐).
- 드래그 중 `start~due` 실시간 툴팁.

## 7. 스펙 필수 체크리스트

- [ ] 편집 페이로드 = ops 체인지셋 전용 (전체 직렬화·뷰JSON 역매핑 금지)
- [ ] `/save` = cairn core `transaction()` 1회 (validate+원자쓰기+view재생성+git commit+롤백 재사용, 신규 쓰기코드 0)
- [ ] 충돌 = baseHash(sha256) 임베드 → flock 하 비교 → 409+재로드 (mtime 금지)
- [ ] 포커스 복귀 시 `/hash` 폴링 → 외부변경 배너
- [ ] 드래그: 일 스냅 · 날짜 툴팁 · 의존위반 soft-warn · 자동캐스케이드 없음 · 최소줌 핸들 처리
- [ ] 추가/삭제: 삭제는 `remove-task` 역참조 사전검사 경로 재사용
- [ ] 상태 편집 = kind별 어휘 드롭다운 (active 오입력 원천차단)
- [ ] 미저장: dirty 인디케이터 + beforeunload + 변경0=싱크 비활성
- [ ] 커밋 메시지 = `web-sync:` 접두 + op 요약 body
- [ ] `/save`·`/open` POST 전용 + 세션 토큰 + Host 검증
- [ ] execution_ref/branch 웹에서 읽기전용 (훅이 정본)
- [ ] 저장 성공 → 최신 뷰JSON+새 baseHash 반환 → 재로드 없이 연속 편집
- [ ] type enum validate(work/schedule) + 기본 work
- [ ] 간트 Must 5종(의존표시·오버듀 자동파생[blocked와 분리]·마일스톤 요약바·스냅·틱 월요일정렬) 편집과 같은 묶음

## 8. 실행 우선순위
1. **P0 편집 기반**: ops 스키마 + `/save`→transaction + baseHash 409 + POST/토큰 보안.
2. **P0 간트 Must**: 스냅 · 오버듀 자동파생(blocked 분리) · 마일스톤 요약바 · 의존 표시(최소 하이라이트) · 틱 월요일 정렬.
3. **P1**: 드래그 soft-warn · 포커스복귀 해시폴링 · 미저장 가드 · 상태 드롭다운 · type enum validate.
4. **P2(Nice)**: 주말음영 · zoom-to-fit/프리셋 · 접기 · 진행률 요약바 · 담당자 필터 · 칸반 status 드래그.
5. **스코프 아웃 선언**: 크리티컬 패스 · 태스크 %진행률 · 스윔레인 · 내보내기 · 베이스라인 · per-milestone type · 자동 캐스케이드.

## 결정 로그
| 질문 | 결정 |
|------|------|
| 저장 방식 | 명시적 싱크 버튼 (dirty 축적 → 일괄) |
| 충돌 처리 | 변경 감지(sha256)→경고+재로드 |
| 편집 페이로드 | **ops 체인지셋 전용** (전체 직렬화 금지) |
| 저장 경로 | **cairn core transaction() 경유** (직접 yaml 쓰기 금지) |
| 추가 UI | 툴바 +버튼 폼 다이얼로그 + **삭제 포함**(역참조 가드 재사용) |
| 드래그 의존위반 | soft-warn(저장 허용), 캐스케이드 없음 |
| type 네이밍 | work/schedule 유지, enum validate, 기본 work |
| type 성격 | **뷰 스위치일 뿐 데이터 제약 아님** |
| 혼합 원장 | 다이얼로그가 전 필드 커버로 v1 종결, 듀얼탭 opt-in v2 |
| work 타입 날짜편집 | 다이얼로그 편집 허용(드래그 UI만 schedule 전용) |
| 테마 | 다크/라이트/시스템 — **프로토타입에 이미 반영(shipped)** |
