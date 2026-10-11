# 인덱스: 아침 매거진 미발행 — mbox 사본 회전본 이어 읽기 + install-magazine 설치 목록 누락 (판정 601 · master#21 쪽지 #67164 · 급함)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 판정 601(오늘 호 미발행 · 우선 최상)
- 상태: 대기
- 선행: 없음
- 시험 입력: 임시 폴더 jsonl 픽스처 + 키트 파일 목록(명령 실행·Slack 게시 0)
- 기준값: origin/main 키트 `scripts/harness-install/slack-mirror/magazine_collect_mbox.py` 97행 — `mailbox.log.jsonl` 하나만 읽고 첫 ts 가 창 시작보다 뒤면 raise. 실측: 현재 파일 첫 ts `2026-10-08T21:04:13` · 회전본 `mailbox.log.jsonl.1` 마지막 ts `2026-10-08T21:03:41`(5MB 회전 10-08 21:03) → 창 08:00 시작 호가 raise 로 미발행. `scripts/harness-install/slack-mirror/install-magazine.sh` REQUIRED·COMPANION 에 `magazine_collect_open.py` 없음(그런데 `magazine_collect.py:16` 이 import).
## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: C(배포 발행(슬랙) — 아침 매거진이 회전 뒤에도 나간다 · 키트 설치 목록 = 실제 import 집합). 핵심 한 줄: 창 앞부분이 회전본에 있으면 이어 읽어 발행하고, 그래도 못 덮으면 지금처럼 raise 한다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
아침 매거진(`scripts/harness-install/slack-mirror/byz_morning_magazine.py`)은 `magazine_collect.py` 의 `collect()` 에서 `collect_mbox(Path(mailbox), start, end)` 로 mbox 발신 로그 사본(`.fable-team/comm/mailbox.log.jsonl`)을 읽는다. mbox 는 이 로그가 5MB 를 넘으면 `mailbox.log.jsonl.1` 로 회전한다(같은 폴더 · 1개). `collect_mbox` 는 현재 파일 하나만 읽고 «첫 정상 기록 ts > 창 시작» 이면 raise(창 앞부분 누락을 숨기지 않기 위한 설계 · NO SILENT FALLBACK)라, 창 도중 회전이 일어난 날은 매거진이 통째로 안 나간다. 같은 사본을 `magazine_collect_decisions.py:50` 의 `collect_decisions` 도 `_read` 로 현재 파일만 읽는다(회전 앞쪽 판정을 «조용히» 놓침). 또 `install-magazine.sh` 설치 목록에 `magazine_collect_open.py` 가 빠져 새 머신 설치 시 ImportError 가 난다(이 Mac 홈에는 master 가 손으로 설치함).

## 사전검증
- 소환: 아니오 (arch#22 설계 = 아래 닫힌 목록 · 급함 · 판정 601 최단 경로)
- 구현 DA: ★예 1회 · bounded 10분 + 정정 10분 · 2 HOLD 면 리뷰 종료★ — 질문 고정: Q1 회전 이어 읽기가 창 누락을 «조용히» 숨기는 경로 0(못 덮으면 raise 유지) · Q2 중복·순서(회전 경계 같은 seq) · Q3 설치 목록 = import 닫힘 전수.

## 설계 (닫힌 목록)
ⓐ `scripts/harness-install/slack-mirror/magazine_collect_mbox.py`:
  1. 새 함수 `read_window(path: Path, s: str) -> tuple[list[dict], int]` — `_read(path)` → (행 없음 또는 `rows[0]["ts"] > s`) 이고 같은 폴더 `<이름>.1` 이 «있으면» 그것을 `_read` 해 앞에 잇는다(깨진 줄 수 합산). 이어 붙인 뒤 `seq` 가 있는 행은 seq 기준 중복 제거(먼저 나온 것 유지 · seq 없는 행은 그대로). 그래도 행 없음 또는 첫 ts > s 면 raise — 메시지에 두 파일 경로와 각 첫 ts. `.1` 이 없으면 기존 메시지 그대로 raise.
  2. `collect_mbox` 의 `_read(path)` + 97~98행 검사를 `read_window(path, s)` 로 교체(나머지 계산 불변).
  3. 회전본은 «1개(.1)» 만 — `.2` 이상·글롭 탐색 0(mbox 회전 설계가 1개).
ⓐ' `scripts/harness-install/slack-mirror/magazine_collect_decisions.py:50` 의 `_read(Path(path))` 도 `read_window(Path(path), start.strftime(TS_FMT))` 로(같은 누락을 조용히 하지 않게 · import 1줄 + 호출 1줄).
ⓑ `scripts/harness-install/slack-mirror/install-magazine.sh` REQUIRED 에 `magazine_collect_open.py` 추가(`magazine_collect.py` 가 무조건 import 하므로 COMPANION 아님).

## 구현 범위 (닫힌 목록)
1. 위 ⓐ·ⓐ'·ⓑ.
2. 시험 `tests/scripts/test_magazine_collect_mbox.py` 에 행 추가: R1 현재 파일 첫 ts > 창 시작 + `.1` 이 덮음 → 창 안 행 수 = 두 파일 합(경계 같은 seq 1개 중복 → 1번만 셈) · R2 `.1` 있어도 못 덮음 → raise(메시지에 두 경로) · R3 `.1` 없음 → 기존 raise 메시지 · R4 현재 파일이 이미 덮으면 `.1` 을 읽지 않는다(`.1` 을 깨진 파일로 두고도 통과) · R5 decisions 가 `.1` 안의 판정을 잡는다.
3. 새 시험 `tests/harness/test_magazine_install_list.sh`(100줄 이하): 키트 폴더에서 `byz_morning_magazine.py`·`byz_proposal_publish.py`·`byz_thread_post.py` 로부터 같은 폴더 모듈 `import`/`from … import` 를 따라간 닫힘 집합 ⊆ REQUIRED ∪ COMPANION(install-magazine.sh 를 파싱) — 빠진 이름을 출력하고 rc=1. 변이: `magazine_collect_open.py` 를 목록에서 뺀 복사본 → rc=1.
4. 기존 시험 PASS: `tests/scripts/test_magazine_collect_mbox.py` · `tests/scripts/test_magazine_collect_detail.py` · `tests/scripts/test_magazine_cli.py` · `tests/harness/test_magazine_plist.sh`(pytest 는 `.venv/bin/python -m pytest --noconftest`).
커밋은 자기 브랜치, **push 금지**. **금지**: 홈 `~/.hermes/` 쓰기·launchd·Slack 게시(설치·재발행 = master).

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- 위 시험 rc=0 · 구현 DA 판정문 APPROVE(또는 2 HOLD 뒤 arch 서명).
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: .venv/bin/python -m pytest --noconftest tests/scripts/test_magazine_collect_mbox.py rc=0 · 이슈: 0`.
- 루트 지침(governance §9 · BOOT 19 · 판정 514·532): 완료 조건을 다 채운 «그 턴에» 증거 줄 기록 + arch#22 에 머리 `[완료·휴식]` 1통 → 쉰다.
- ★랜딩 뒤 master 집행(카드 밖)★: `install-magazine.sh` 로 홈 설치(cp · 백업은 스크립트가 함) → 실제 사본으로 수집만 dry 1회(오늘 창 · raise 0 확인) → 수동 재발행.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 1c2828e1f8c8c15d6d69cef28675c26329e27496 (spawn 2026-10-09)
- 2026-10-09 — 대기/ 생성 (byz-harness-arch-claude#22 · 판정 601 · master#21 쪽지 #67164).
- 정본 영향 없음: 하네스 매거진 키트·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-09 08:08 — 대기→진행 · 좌석 byz-harness-nano-mag601-mbox-rotation-and-install-list#0

## 결과 (나노 RESULT #67169 + r1 반송 · arch#22 재현 · master#21 옮김 2026-10-09)
세트: dd19902b7119a7d4aa1bbe5df59883004140df77 · 시험: .venv/bin/python -m pytest --noconftest tests/scripts/test_magazine_collect_mbox.py rc=0 · 이슈: 0
정본 영향 없음: 하네스 슬랙 미러 키트·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-09 08:26 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§102
