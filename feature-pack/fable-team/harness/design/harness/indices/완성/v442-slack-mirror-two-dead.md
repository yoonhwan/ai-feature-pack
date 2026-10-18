# 인덱스: 슬랙 미러 둘 정지 복구 — github 미러 크래시 루프 + mbox 미러 planner 좌석명 불일치 (판정 442)
<!-- ledger: design/teams/harness/GOAL-harness.md -->
- Issue: 없음 → 판정 442(오빠 「슬랙 알림 전혀 안 옴」 · planner#11 #63101 · 우선 처리)
- 상태: 대기
- 선행: 없음
- 시험 입력: 임시 디렉터리 + 가짜 mailbox.jsonl 1행(planner 이름 `byz-planner-master-claude#11` 수신) + 가짜 GitHub 이슈 행 · 슬랙 호출은 스텁(실제 post 0)
- 기준값: ①`~/.hermes/logs/byz_github_slack_mirror.err` 마지막 줄 `TypeError: format_row() takes 5 positional arguments but 7 were given`(`byz_github_slack_mirror.py:57`) ②plist `--seat '^byz-planner-arch#[0-9]+$'` 가 현역 이름 `byz-planner-master-claude#N` 과 매칭 0

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「RELEASE-<ver>.md 1장 + 머신별 「반영됨 <machine> <sha>」 행 전부」.
골의 축: C(업그레이드·반영) — 슬랙 발행이 죽으면 오빠가 하네스 변화를 못 받는다. 핵심 한 줄: 두 미러가 실제로 슬랙에 1건씩 도착해야 닫힌다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
PR 911(10-08 14:28 설치)이 `mirror_lib.format_row` 시그니처를 `(row, label, mention, summary, text, *, block, ...)` 로 바꿨다(키트 `scripts/harness-install/slack-mirror/mirror_lib.py:181`). `byz_mbox_slack_mirror.py:145` 는 새 시그니처로 호출하지만 `byz_github_slack_mirror.py:57` 은 옛 위치 인자 7개로 호출해 TypeError 로 launchd 재시작 루프에 빠졌다(`com.hermes.byz-github-slack-mirror`). mbox 미러(`com.hermes.byz-mbox-slack-mirror`)는 살아 있지만 plist 의 `--seat '^byz-planner-arch#[0-9]+$'` 가 planner 이름이 `byz-planner-master-claude#N` 으로 바뀐 뒤 매칭 0 이라 무발행이다. 추가로 `com.hermes.byz-slack-mbox-inbound` plist 가 미로드다. 홈(`~/.hermes/scripts/`)과 키트 사본은 현재 같은 바이트(cmp 확인).

## 사전검증
- 소환: 아니오
- 면제: 호출부 시그니처 정합 + plist 좌석 정규식 갱신 + 시험 — 새 설계 없음 · master 우선 처리 지시(판정 442)

## 조사 근거
- 키트 `scripts/harness-install/slack-mirror/` : `byz_github_slack_mirror.py:57` · `byz_mbox_slack_mirror.py:145` · `mirror_lib.py:181` · `com.hermes.byz-mbox-slack-mirror.plist.template`(`--seat __SEAT__`) · `install.sh` · `install-github.sh` · `install-inbound.sh`.
- 홈 실물: `~/Library/LaunchAgents/com.hermes.byz-mbox-slack-mirror.plist` `:12` · `~/.hermes/logs/byz_github_slack_mirror.err`.
- 정본 설계 `design/teams/harness/DESIGN-slack-mirror.md`.

## 구현 범위 (닫힌 목록)
1. `byz_github_slack_mirror.py` 의 `format_row` 호출을 현행 시그니처에 맞춘다(github 행에 맞는 `block=` 값은 `mirror_lib` 의 기존 헬퍼를 읽고 결정 · 새 fallback 금지 — 값을 못 만들면 raise).
2. mbox 미러 좌석 정규식을 현역 planner 이름(`byz-planner-master-claude#N`, 옛 `byz-planner-arch#N` 도 매칭)에 맞게 plist 템플릿·`install.sh` 기본값에서 갱신. 홈 plist 는 설치 스크립트 경로로만 갱신(손 편집 0).
3. 시험 신규 파일 `tests/harness/test_slack_mirror_signature.sh`(기존 `tests/harness/test_kit_bin_sync.sh` 형식 참고): ①github 미러 `_item` 이 스텁 행으로 TypeError 없이 텍스트 생성 ②좌석 정규식이 `byz-planner-master-claude#11` 매칭 · 무관 이름 비매칭. 슬랙 실제 post 0.
4. `slack-mbox-inbound` plist 미로드 원인(설치 누락인지 의도인지)만 조사해 카드 증거 줄에 1줄 보고 — 이번 카드에서 로드는 하지 않는다.

커밋은 자기 브랜치(`nano/*`, base origin/main), **push 금지**. **금지**: 실제 슬랙 발행 · 라이브 launchctl 조작 · 홈 파일 직접 편집 · 미러 일반 리팩터.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_slack_mirror_signature.sh` rc=0 · `python3 -m py_compile` 변경 py · `ruff check` 변경 py · `shellcheck -S warning` 변경 sh · 키트 사본 cmp(`test_kit_bin_sync.sh` 해당 시 PASS).
- 카드 증거 줄 형식(필수): `세트: <40hex> · 시험: bash tests/harness/test_slack_mirror_signature.sh rc=0 · 이슈: 0`.
- 랜딩 뒤 master 집행(카드 밖): 키트 설치 → launchctl 재기동 → 실제 슬랙 1건 도착 확인 → planner 회신 1줄.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 58b39d8ec31f4a498a626b5832b55438771d2c11 (spawn 2026-10-08)
- 2026-10-08 — 대기/ 생성 (byz-harness-master-claude#16 · 판정 442 · 우선 처리).
- 정본 영향 없음: 하네스 미러 도구·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-08 16:07 — 대기→진행 · 좌석 byz-harness-nano-v442-slack-mirror-two-dead#0
세트: 37350a4a0463ada6b8ca7318ed96ba712a8123c0 · 시험: bash tests/harness/test_slack_mirror_signature.sh rc=0 · 이슈: 0
- 2026-10-08 17:57 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§68
