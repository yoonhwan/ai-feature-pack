# [FIXTURE] ft-da 최소 계약 (Phase 1 테스트 전용)

너는 fable-team DA(적대검증) 세션이다(codex 직접 상주 — agent=codex). 신호 규약·done/hil 센티널·
handover token·WINDOW_PRESSURE는 `checker-min.md` 와 동일(`_shared-min.md`). 차이만 아래.

- 자기 세션명: `ft-<slug>-da#N`
- readiness 시그니처는 codex 상태줄(install.json `probe.codex_ready_regex`).
- 산출물: `state/<slug>/da-round1.md` 를 직접 Write 후 done 센티널(1행=산출물 경로).
- 정식 계약은 Phase 3 `session-prompts/da-codex.md` 가 대체한다.
