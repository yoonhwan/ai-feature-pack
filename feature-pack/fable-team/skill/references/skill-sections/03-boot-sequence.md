## 부팅 시퀀스 — 3스텝 인터뷰 (트리거 시 강제 — 생략 금지)

허들 통과 후, 파이프라인을 임의로 시작하지 않는다. 아래 순서를 **생략 없이** 수행한다:

**스텝 -1 — 출력 스타일 (오케 필수, 2026-08-11)**: 오케 세션은 부팅 시퀀스 진입 시 `i-have-adhd` 스킬을 로드한다(`/i-have-adhd` 또는 Skill 도구). architect·DA 세션은 템플릿·COMM-GUIDE가 자체 로드하고, 작업자 워커(implementer/tester)·checker·analyst·pm은 로드 금지(보고 포맷 계약 보호 — COMM-GUIDE 「출력 스타일 스킬」).

**스텝 0 (질문 아님, 유지)**: `.fable-team/state/ACTIVE` 존재 → context-management §4 복원이 인터뷰 전체를 대체(브레인 선택 포함 — state.md의 `brains:` 라인 복원). **없고 integrations가 on/required이며 현 위치가 main 워크트리 내부면 discovery** — `baton status`(1순위) + `<MAIN_ROOT>/.worktrees/*/.fable-team/state/ACTIVE` glob(보조)으로 활성 FT 워크트리 탐색 → 발견 시 해당 워크트리 **절대경로 운용**으로 복원. **신규 세션만 스텝 1~3 진행.**

**스텝 1 — 브레인 선택 (세션 1회, AskUserQuestion 1개)**:
- 질문 대상은 `ask: true` 역할만 = **architect와 DA 레인**. 나머지(analyst/implementer/tester/checker)는 choices[0] 고정 — 언급만 하고 묻지 않는다.
- 선택지 형태 (조합 제시로 질문 1개 압축):
  - ① architect=sonnet-5(+fable-5 에스컬레이션), da=codex-5.6-sol, da2=grok-4.6 **[기본]** (2026-07-12 retro §8 — fable-5 상시는 ③으로 강등)
  - ② architect=sonnet-5(+fable-5 에스컬레이션), da=grok-4.6, da2=codex-5.6-sol
  - ③ architect=fable-5 상시 (구 기본 — 신규 아키텍처 설계 위주 세션에만 권장), da=codex-5.6-sol, da2=grok-4.6
  - ④ architect=codex-5.6-sol(→ft-architect-x), da=grok-4.6 고정, da2=claude-opus-4-6 — **author-review-split이 codex DA를 선택지에서 제거한 조합**
  - ⑤ 직접 조합 (자유 입력 — constraints 위반 시 재제시)
- 결과를 state.md `brains:` 라인에 write-through. **같은 세션에서 다시 묻지 않는다.**
- **미가용 발생 시 자동 대체 금지**: 브레인 실패(429·auth·CLI 부재)는 `BRAIN_UNAVAILABLE <role> <model> <사유>` 1줄 보고 → AskUserQuestion으로 남은 choices 재제시 → 사용자 선택 후 state.md 갱신.

**스텝 2 — 문제 입력 (AskUserQuestion 1개)**:
- 대화 컨텍스트에서 후보 추출 가능하면 ①② 추천(한 줄 요약), ③ 직접 입력(한 줄/파일 경로), ④ 채팅에서 구체화 후 재확인. **어떤 경로든 사용자 응답 없이 파이프라인 시작 금지.**

**스텝 3 — 배치 추천 → AskUserQuestion 킥오프 (1개)**:
- 오케가 `references/orchestration-cases.md` 케이스 하네스(4그룹·8케이스·모듈)로 분류 → AskUserQuestion 1개 발사. `question`에 압축 보드 인라인, `options`가 배치 선택지.
- **① = 오케 추천 배치, label에 `(Recommended)` 접미** — 엔터만 치면 ① 선택 = 즉시 킥오프.
- **어떤 옵션을 골라도 재확인 없이 즉시 킥오프** — 조정이 옵션에 내장. `직접 조합` 경로에서만 형상 1줄 재확인 1회 → 킥오프.
- 킥오프 = `state/ACTIVE` + state.md(brains·패턴·선택 형상) write-through → stage 0. 킥오프 확장 훅(워크트리·**PM 확보**·원장 등록)은 `references/integrations.md` §1의 **순서**를 따른다. **PM 확보**: 코드 변경 형상(standard/abbrev)이면 `ft-pm-<proj>#0` 존재 확인 후 부재 시 개설(check-only·P-DOC 미개설), 생존 시 재사용(KICKOFF만 송신) — 스텝3 보드에 `PM: ft-pm-<proj>#0 (상시)` 표기(§3-1). **컨펌 없이 워커를 스폰하지 않는다.**
- **같은 세션의 다음 피처는 스텝 2부터** (스텝 1 생략 — 세션 1회 원칙).

총 질문 수: 신규 세션 첫 피처 = 3개, 이후 피처 = 2개, 복원 세션 = 0개.

> 좌석 기억 로드(1회): `bash .fable-team/bin/ft-lessons.sh snapshot` — 3계층 ≤2KB 스냅샷. 세션 중 add 는 파일에만(다음 부팅 반영).
