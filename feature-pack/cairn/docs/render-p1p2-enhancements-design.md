# cairn 뷰어 P1/P2 후속 개선 design

Date: 2026-07-02
Origin: P0(편집·간트, PR #9) 병합 후. [render-editing-gantt-design](render-editing-gantt-design.md) §8의 P1 잔여 + P2(Nice) 항목을 하나의 후속 묶음으로 구체화. 연계: [render-multiview-design](render-multiview-design.md), `docs/plan-view.template.html`, `core/cairn.py`.

전제: 모든 편집은 `cairn render --serve`(localhost)에서만. 정적 `file://`는 읽기전용.

## 0. 불변규칙 재확인 (P0에서 확립 — 이 묶음도 동일 준수)

1. **편집 = ops 체인지셋 전용.** 신규 편집(칸반 status 드래그·MS 필드편집)도 `apply_ops`의 기존 op(`set`/`set-ms`/`remove-milestone`)만 사용. 뷰JSON 역매핑·전체직렬화 금지.
2. **저장 = `transaction()` 1회 경유.** 신규 쓰기 경로 0. 싱크 버튼으로 일괄 저장(`web-sync:` 커밋).
3. **`execution_ref`/`branch` 읽기전용** — 이 묶음의 어떤 편집도 건드리지 않음.
4. **validate는 error만, warning 신설 금지.** soft-warn(의존 위반)은 **클라이언트 계산·표시 전용** — 원장 스키마·validate 무변경.
5. 백엔드(`apply_ops`)는 P0에서 `set`/`set-ms`/`add-task`/`remove-task`/`add-milestone`/`remove-milestone` 6종 완비. **이 묶음은 대부분 프론트(템플릿 JS)만** 손대며, 신규 서버 op 불필요.

## 1. 드래그 의존위반 soft-warn 세부 (P1 — 유일한 P1 잔여)

P0은 드래그 일스냅·날짜 툴팁까지 구현. 의존 위반 경고 UI가 남음.

- **감지(클라):** task T의 날짜 변경 후 위반 판정
  - 선행 위반: `dep` 중 `due > T.start`인 선행 존재(선행이 안 끝났는데 T 시작).
  - 후행 위반: T를 `dep`로 갖는 후행 중 `T.due > 후행.start`.
- **soft 원칙(§6 준수):** 저장 **허용**, 자동 캐스케이드 **없음**, hard-block **없음**. 현실 일정은 의존을 임시로 깨며 조정.
- **UI:** 위반 바에 주황 점선 테두리(`.dep-violation`) + 상단 토스트 "⚠ t9: 선행 t7이 이후에 끝남 (저장은 됩니다)". 토스트는 3초 후 소멸, 위반 테두리는 다음 편집까지 유지.
- **계산 위치:** 드래그 종료 시 + reloadView 후 `markViolations()` 1패스(allTasks 순회, O(n·dep)). 원장 validate는 **호출 안 함**.
- **YAGNI:** 위반 목록 패널·일괄 해소 버튼 없음(테두리+토스트로 충분).

## 2. 주말 음영 (P2)

- 월요일 정렬 틱(P0 완료)을 전제로, 각 주의 토·일에 반투명 세로 음영.
- **구현:** `renderSchedule`에서 주 단위 순회 — 주 시작(월)+5일 지점부터 폭 `2*PX` 음영 div 1개(일자별 div 남발 방지). `.sg-weekend` 클래스, `z-index` 틱 아래·바 아래.
- **스코프 아웃:** "기간외 음영"(마일스톤/프로젝트 기간 밖)은 정의 모호 + 정보가치 낮음 → **제외**(YAGNI). 주말만.

## 3. zoom-to-fit + 프리셋 + 뷰포트 앵커 (P2)

- **fit 버튼:** `SG.px = max(2, floor((clientWidth - LABELW) / days))` → 전체 일정 한 화면.
- **프리셋:** 주(28px)/월(10px)/분기(5px) 버튼. 툴바에 fit + 3프리셋 추가.
- **뷰포트 중앙 앵커:** 현재는 줌마다 무조건 `centerToday`. 변경 — 줌 직전 뷰포트 중앙의 날짜를 계산해두고, 줌 후 그 날짜를 중앙에 재배치. "오늘" 버튼은 명시적으로 오늘 센터(기존 유지).
- **구현:** `zoomTo(px)` 헬퍼 신설(앵커 계산 → `renderSchedule` → 스크롤 복원). 기존 `＋/－`도 `zoomTo` 경유로 통일.

## 4. 칸반 status 드래그 (P2)

- 칸반 카드를 컬럼(진행중/대기/완료/블록) 간 드래그 → status 변경.
- **op 재사용:** drop 시 `pushSet(t, "status", 목표컬럼)` → 로컬 미러 갱신 → `renderKanban()`. 간트 드래그와 동일 ops 인프라.
- **양 타입 공통(work/schedule 무관).** `CAN_EDIT`일 때만 카드 `draggable`.
- **접근:** HTML5 native drag-and-drop(`dragstart`/`dragover`/`drop`). 컬럼이 dropzone, 드롭 시 `dataTransfer`의 tid로 op. 터치 지원은 v2(YAGNI).
- status 어휘는 kind별 4종(P0 `STATUS_TASK`). 컬럼 = 그 4종에 정확히 대응.

## 5. 마일스톤 접기/펼치기 (P2)

- 트리 뷰 + 간트 섹션행에서 마일스톤 단위 하위 task 접기.
- **UI:** 마일스톤 헤더 앞 `▾/▸` 토글. 접으면 하위 task 행 숨김(간트는 task 행 + 바 숨김, 섹션행 요약바는 유지).
- **상태:** 세션 메모리(`Set<msId>` collapsed) — localStorage 영속은 v2(YAGNI). reloadView 시 유지.
- MS 편집 다이얼로그(§8)와 클릭 충돌 방지: 토글은 `▾` 아이콘 클릭만, 헤더 본문 클릭은 다이얼로그.

## 6. 마일스톤 진행률 채움바 (P2)

- 트리 뷰는 이미 완료율% 진행바 보유 → **로직 재사용**(`done task / 전체 task`).
- **간트 확장:** 마일스톤 요약바(P0)에 완료율만큼 채움 오버레이(`.sg-msbar-fill`) + 섹션행 라벨에 `(3/5)` 텍스트.
- 완료율 헬퍼 `msProgress(m)` 추출 → 트리·간트 공유(중복 제거).

## 7. 담당자 필터 (P2)

- 상단(툴바/헤더)에 담당자 드롭다운(전체 담당자 목록 자동 수집 + "전체").
- **동작(스윔레인 아님, §5):** 선택 시 비매칭 task를 흐리게(`opacity:.25`) — 전 뷰 공통(칸반/트리/간트). 필터는 표시만, 편집·op 무관.
- **매칭:** `assignees`에 선택 담당자 포함(`cairn`의 `_task_matches` assignee 매칭을 클라에서 재현). reporters/watchers는 v1 제외(assignee만).
- 상태: 세션 메모리. reloadView 후 재적용.

## 8. 마일스톤 필드편집 다이얼로그 (P2 — set-ms UI)

- 마일스톤 헤더/섹션행 클릭 → 다이얼로그(task 다이얼로그와 동형).
- **편집 필드:** name / status(`STATUS_MS` 드롭다운: planned/active/blocked/done) / start / end / depends_on. → `set-ms` op.
- **삭제:** 빈 마일스톤이면 "삭제" 버튼 → `remove-milestone` op(역참조 가드는 서버 `_ms_removal_guard`가 재검증).
- **읽기전용:** 마일스톤엔 execution_ref/branch 없음(task 전용). id 읽기전용.
- 마일스톤 행에 `data-mid` 부여, 클릭 위임 분기(task=data-tid → openTask, ms=data-mid → openMilestone).
- 백엔드 `_op_set_ms`/`_op_remove_ms` P0 완비 → **프론트만**.

## 9. 실행 우선순위

1. **먼저(백엔드 무변경 확인 후 프론트):** §1 soft-warn · §8 MS 편집 다이얼로그 — 편집 완결성.
2. §4 칸반 status 드래그 · §5 접기 · §6 진행률바 — 상호작용.
3. §2 주말음영 · §3 zoom-fit/프리셋/앵커 · §7 담당자 필터 — 시각/탐색.

모든 항목 **프론트(`plan-view.template.html`) 전용** 예상. 서버 변경이 필요해지면(예상 밖) 별도 커밋 분리 + pytest. 항목별 작은 커밋([기능] 접두), 커밋마다 JS 문법(`node --check`) + 렌더 스모크 + 회귀(pytest 235 유지).

## 10. 검증 전략

- **백엔드 무변경 회귀:** 기존 pytest 235 그대로 통과(이 묶음이 서버를 안 건드림을 증명).
- **프론트:** `node --check`(JS 문법) + `build_view_html`로 schedule/work 예제 렌더 후 신규 요소(`.sg-weekend`/`.dep-violation`/`.sg-msbar-fill`/드래그·필터 핸들러) 임베드 확인.
- **육안(리뷰어):** 간트 드래그 위반 경고 · 칸반 카드 드래그 · 접기 · 필터 흐림 · MS 다이얼로그 저장 — 브라우저 수동.
- soft-warn이 원장 validate를 호출하지 않음을 코드리뷰로 확인(불변규칙 4).

## 결정 로그

| 질문 | 결정 |
|------|------|
| soft-warn 위치 | **클라 계산·표시 전용** (원장 validate·스키마 무변경, warning 인프라 신설 안 함) |
| 의존 위반 처리 | 저장 허용 + 테두리/토스트, 캐스케이드·hard-block 없음(§6) |
| 기간외 음영 | **제외**(YAGNI) — 주말만 |
| 줌 앵커 | 뷰포트 중앙 날짜 유지(오늘 버튼만 오늘 센터) |
| 칸반 드래그 | HTML5 native DnD, set status op 재사용, 터치는 v2 |
| 접기 상태 | 세션 메모리(localStorage 영속 v2) |
| 진행률바 | 트리 완료율 로직 재사용, 간트 요약바 채움 오버레이 |
| 담당자 필터 | 비매칭 흐림(스윔레인 아님), assignee만(reporters/watchers v2) |
| MS 편집 | 헤더 클릭 다이얼로그 → set-ms/remove-milestone op(백엔드 기존) |
| 서버 변경 | **없음 예상** — 전 항목 프론트. 필요 시 별도 커밋+pytest |
