# AI RAG (`airag`) — 문서 안내

이 패키지의 기획 문서는 세 곳뿐이다. 매일 아래 흐름으로 고르면 된다.

| 새로 쓸 내용 | 여기에 |
|---|---|
| 새/변경된 아키텍트·사용자 결정 | [`DECISIONS.md`](DECISIONS.md) — D-ID 붙은 날짜별 기록 |
| 지금 구현 계획·작업·완성 기준·실제 현재 상태 | [`PLAN.md`](PLAN.md) — 결정에 근거한 단일 기획 원장 |
| 리서치, 다이어그램, 보고서, 과거 스냅숏 | [`artifacts/`](artifacts/) — 분류 강제 없음 |

`PLAN.md`의 각 요구사항/작업은 그 근거가 된 `DECISIONS.md`의 D-ID를 링크한다 — 결정과
계획이 따로 놀지 않게 한다.

## 이 패키지가 하는 일 (한 줄)

BYZ·KakaoBot 등 여러 프로젝트가 설치해 쓰는 암호화된 로컬 RAG 엔진. core는 명시적
요청만 처리하고, 파일 감지/워처/스케줄은 소비 프로젝트가 맡는다 — 자세한 내용과
근거는 [`DECISIONS.md`](DECISIONS.md)와 [`PLAN.md`](PLAN.md)에 있다.

사용자 투어는 [풀 투어 가이드](artifacts/full-tour-guide.md)를 따른다.
계획 합의부터 원본·검색·확장·변경·복원·사용자 확인까지 T00~T13으로 구성돼 있으며,
현재 진행 위치와 완료 상태는 [PLAN.md의 P-08](PLAN.md#p-08--사용자-투어)에서 확인한다.

## 과거 문서

이전에 더 세분화된 문서 구조(architecture/contracts/delivery/research/decisions/
visuals/archive)가 있었다. 그 내용은 위 두 문서로 통합됐고, 원문은
[`artifacts/previous-planning/`](artifacts/previous-planning/)에 이력으로만 남아 있다
— 활성 참조는 항상 `DECISIONS.md`/`PLAN.md`를 우선한다.
