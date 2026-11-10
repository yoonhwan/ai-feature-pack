# RESULT — tmm 그룹 탭 일반화 (2026-10-07 · ft-harness-temp-tmm-group-tab-generalize#0)

골 축: 하네스 원문 5·7(머신별 독립 배분 · 식별 층). 닫는 증거: 아래 점검표 + `tests/harness/test_tmm_group.sh` ALL PASS + `~/.tmm` 변경 0.

## 한 줄 결론
새 이름 규칙(`<프로젝트>-<팀>-<역할>…`)에서 탭이 `byz` 한 곳으로 뭉치던 것을, `cat_of()` 에 일반 규칙 1개(3번째 토큰이 역할 예약어면 라벨 = 팀)를 넣어 팀별로 갈랐다. 프로젝트별 규칙 추가 0.

## 점검표 — 현재 `tmux ls` 전수(읽기 전용), 라벨 = 그룹 탭
| 세션 | 0.7.3 현행 | 후보 0.7.4 | 사실 |
|---|---|---|---|
| `FB_CFO#52` | cfo | cfo |  |
| `KakaoBot#14` | kakao | kakao |  |
| `KakaoBot#17` | kakao | kakao |  |
| `byz-cfo-master-claude#53` | byz | cfo | **갈라짐/정정** |
| `byz-issues-master-claude#1` | byz | issues | **갈라짐/정정** |
| `byz-planner-arch#3` | byz | planner | **갈라짐/정정** |
| `byz-planner-master-claude#4` | byz | planner | **갈라짐/정정** |
| `ft-airag-helm-claude#5` | airag | airag |  |
| `ft-airag-helm-claude#6` | airag | airag |  |
| `ft-airag-master-claude#2` | airag | airag |  |
| `ft-harness-arch#3` | harness | harness |  |
| `ft-harness-arch#4` | harness | harness |  |
| `ft-harness-ops#3` | harness | harness |  |
| `ft-harness-ops#5` | harness | harness |  |
| `ft-harness-ops#6` | harness | harness |  |
| `ft-harness-temp-tmm-group-tab-generalize#0` | harness | harness |  |
| `ft-v65-arch-claude#162` | v65 | v65 |  |
| `ft-v65-arch-claude#163` | v65 | v65 |  |
| `ft-v65-arch-claude#164` | v65 | v65 |  |
| `ft-v65-checker-claude#4` | v65 | v65 |  |
| `ft-v65-checker-claude#5` | v65 | v65 |  |
| `ft-v65-da-codex#26` | v65 | v65 |  |
| `ft-v65-da-codex#27` | v65 | v65 |  |
| `ft-v65-master-claude#140` | v65 | v65 |  |
| `ft-v65-master-claude#141` | v65 | v65 |  |
| `ft-v65-master-claude#142` | v65 | v65 |  |
| `ft-v65-temp-m5-autovad-longpara-dprime-hard-gate-rej#0` | v65 | v65 |  |
| `ft-v65-tester-claude#18` | v65 | v65 |  |
| `ft-v65-tester-claude#19` | v65 | v65 |  |
| `tmm` | tmm | tmm |  |

## 사실
- **뭉침**: 현행 0.7.3 에서 `byz-cfo-master-claude#53`·`byz-issues-master-claude#1`·`byz-planner-arch#3`·`byz-planner-master-claude#4` 4개가 전부 `byz` 한 탭. 후보에서는 `cfo`·`issues`·`planner` 로 갈라지고, `byz-cfo` 는 구 `FB_CFO#52` 와 같은 `cfo` 탭으로 합쳐진다(계보 연속).
- **회귀 0**: 구 이름 25개(`ft-*`·`FB_CFO`·`KakaoBot`·`tmm`)는 현행과 라벨 동일. `ft-harness-ops#N`(3번째 토큰 `ops` 는 역할 아님)은 기존 폴백 경로 그대로 `harness`.
- **충돌**: 현재 라이브에서 «다른 프로젝트가 같은 팀 글자» 0건. 시험 픽스처로만 확인(`byz-bot` vs `kakao-bot` → `b-bot`/`k-bot`, 충돌 없으면 `bot`). `ft-`·`FB_` 는 프로젝트가 아니라 구 접두라 `ft-v65` + `byz-v65` 는 충돌이 아니라 같은 `v65` 탭.
- **비용**: P6 형태 이름마다 `tmux list-sessions` 1회(충돌 판정). `cat_of` 는 `$(…)` 서브셸이라 캐시가 안 남는다 — 30세션 기준 체감 영향 미측정(`cmd_rows` 루프). 문제가 되면 호출부에서 1회 선계산으로 바꾸는 후속(이번 범위 밖).

## 변경
- `scripts/harness-install/tmm/tmm` — 0.7.3 복사본 + `cat_of()` 안에 P6 일반 규칙만 추가(그룹 키 8자·열 5자·`categories` 최우선 불변). `scripts/harness-install/tmm/VERSION` = `0.7.4-candidate`. 설치(`~/.tmm/versions/0.7.4/core/bin/tmm`·`core/VERSION` 배치 + `current` 전환)는 **오빠 승인 영역 — 미실행**.
- `tests/harness/test_tmm_group.sh` — bash -n · ROLES 일치(ft-name-lint.sh 와 같은 값) · 신 6 · 구 6 · 구신 공존 2 · 충돌 3 · 규칙파일 우선 1.
