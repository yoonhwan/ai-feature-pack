# 재배치 증거 — fable-team 1.1.0 harness 합류 (r384 · 2026-10-18)

기준: BYZ-Agents `711199fd627deb033dd0ab5f54263282a458253d` → 팩 이력 병합 커밋(`git log --grep 'harness 합류 — BYZ 6경로 이력 병합'`).

## 경로 표

| BYZ | 팩 `feature-pack/fable-team/harness/` | 파일 수 |
|---|---|---|
| `scripts/fable-team-bin/` | `bin/` | 227 |
| `scripts/harness-install/` | `kit/` | 459 |
| `tools/comm-canonical/` | `comm/` | 31 |
| `design/teams/harness/` (이력의 옛 `design/harness/` 포함) | `design/harness/` | 756 |
| `tests/harness/` | `tests/` | 224 |
| `tests/scripts/` 중 `test_mbox*`·`test_magazine*` + 그 시험이 import 하는 닫힘(`_magazine_*`·`_thread_fakes.py`·`_proposal_fakes.py`·`conftest.py`·`fake_resource_env.py`) | `tests/scripts/` | 47 |
| `.fable-team/state/v6-*` | `evidence/state-v6/` | 88 |
| 합 | | 1832 |

- `tests/scripts` 행의 닫힘 9파일: 표의 글롭(`test_mbox*`·`test_magazine*`)만 옮기면 pytest collect 31 오류(`ModuleNotFoundError _magazine_fakes` 등). `_thread_fakes.py`(BYZ 다른 시험 8)·`_proposal_fakes.py`(4)·`conftest.py`·`fake_resource_env.py` 는 BYZ 쪽 다른 시험도 쓴다 — BYZ 삭제(r386) 때 지우지 않는다.
- `.fable-team/state` 의 `v6-` 들어간 경로 89 중 1(`ft-v65-tester0-parser-v6-prep-20260815.md`)은 `v6-*` 글롭 밖 — 옮기지 않음.

## 파일

| 파일 | 내용 |
|---|---|
| `byz-711199fd62.sha256` · `pack-merge.sha256` | 양쪽 sha256 목록(1832 · 경로만 표대로 다름) |
| `test_pack_relocation.out` | `harness/tests/test_pack_relocation.sh` 출력 원문 |
| `install-dry-run.out` | `harness/install.sh --dry-run --home <임시> --machine test` 출력 원문 |
| `extract.sh` | 이력 추출(`git filter-repo --path`·`--path-rename` · scratch clone) |
| `rewrite_tests.py` · `rewrite-subs.txt` | 시험 경로 치환 도구와 파일별 치환 수(203파일 398곳) |
| `rewrite-left-fixture-paths.txt` | 치환하지 않은 옛 경로 줄(픽스처·문자열 데이터 · 앵커 없음) |

## 범위 밖 (다음 카드)
- `harness/bin`·`kit` 의 BYZ 리포 루트 전제 → r385(B1). 그때까지 팩 시험 중 bin 을 BYZ 꼴 픽스처 밖에서 부르는 것은 실행이 갈릴 수 있다(문법·collect 는 0 오류).
- 라이브 설치(`--apply`)·LIVE_BIN 전환 → r385 · BYZ 삭제 → r386.
