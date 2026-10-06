# RELEASE 0.3 — Issue 기반 개선 체계 구현 + CI 비용 구멍 차단 (2026-10-06 · 축 C)

골 축: C 「업그레이드하고 레포에 커밋 푸시 … 배포 발행 수신해 반영」 · 닫는 증거 = 이 1장 + 머신별 「반영됨」 행. 설계 정본 = design/harness/issue-improvement/SPEC-github-issue-driven-20261006.md · 구현 판정 = design/harness/OPS-VERDICTS-20261006.md §1~§19.

## 변경
| # | 변경 | 근거 | sha |
|---|---|---|---|
| 1 | Issue 기반 개선 도구 일체: 분류기·등록 쌍 래퍼(봇 토큰 필수·폴백 0)·질문 원장·전이표·close 5항·재오픈·회귀 팩·기준값 lint·시험 묶음 상태 전이·좌석 필요 문구·브랜치 정리 후보 목록(삭제 0)·설치 키트 | PR #824 | 3928822c16 |
| 2 | CI 12개 잡 전부 timeout-minutes (6시간 멈춤 과금 차단) | PR #829 | 179469301d |
| 3 | CI Python RED 시험(284파일·2,203건)을 관찰 전용 잡으로 분리 — 차단 잡 28분→약 17분 | PR #830 | 28e0845bf1 |

효과: 좌석이 올리는 Issue 는 Tank 봇 계정 토큰으로만 등록되고(없으면 실패), 분류·닫기·재오픈 검사가 스크립트로 돈다. CI 는 멈춘 잡이 6시간씩 과금되지 않고, 차단 잡은 정상 시험만 돈다.

## 설치 명령 (머신별)
키트 변경이므로 해당 머신의 리포에서:
1. `git pull origin main`
2. `bash scripts/harness-install/fable-team/install.sh --machine <머신> --apply`
3. 확인: 부팅 보고의 `machine=<머신>` · `kit_sha=08fb68d946d2`(files=76) 가 이 RELEASE 의 값과 같은가.
4. Tank 봇 토큰: `~/.config/byz-harness/issue-bot.token`(chmod 600) 또는 `FT_ISSUE_BOT_TOKEN` — 오빠가 계정·토큰을 만든 뒤에만 `--apply` 등록이 동작한다.

## 시험 (로컬 검증)
- main 28e0845bf1 의 키트를 빈 HOME 에 `install.sh --apply` → rc=0 · files=76 · kit_sha=08fb68d946d2
- `tests/harness/test_*.sh` 14종 전부 rc=0 · ruff 키트·CI 스크립트 통과
- PR #830 CI: 차단 잡 외 전부 통과 · Python Test 는 v65 소유 실패 10건으로 빨강(수정 진행 중)

## 머신별 반영
값을 모르면 «미확인». 「반영됨」 행은 그 머신의 부팅 보고 값이 있을 때만 쓴다.

| 머신 | 상태 | sha |
|---|---|---|
| 이 Mac | 미반영 — 라이브 도구 폴더 이전은 오빠 승인 대기 | |
| jarvis | 미확인 | |
| byzs-mac-mini | 미확인 | |
