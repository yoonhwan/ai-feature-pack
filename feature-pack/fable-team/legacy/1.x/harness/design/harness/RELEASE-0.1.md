# RELEASE 0.1 — harness-ops 첫 발행 (2026-10-04 · 축 C)

골 축: C 「업그레이드하고 레포에 커밋 푸시 … 배포 발행 수신해 반영」 · 닫는 증거 = 이 1장 + 머신별 「반영됨」 행.

## 변경
| # | 변경 | Issue | sha |
|---|---|---|---|
| 1 | `.claude/hooks/mbox-backtick-guard.sh` — 따옴표 heredoc 본문 검사 제외, mbox.sh 가 든 논리 줄만 검사 | #799 (R1) | 98abb2b63c |

효과: relay 안내대로 `cat > f <<'EOF'` 로 파일을 쓰는 명령(본문에 백틱 자유)이 더는 차단되지 않는다. mbox 인자 백틱은 그대로 차단.

## 설치 명령 (머신별)
프로젝트 훅이라 별도 설치 없음 — main 머지 뒤 해당 머신의 리포에서:
1. `git pull origin main` (워크트리는 `git checkout origin/main -- .claude/hooks/mbox-backtick-guard.sh`)
2. 확인: `bash -n .claude/hooks/mbox-backtick-guard.sh` → 셔뱅 그대로, 적용 뒤 첫 도구 호출에서 heredoc+relay 가 통과하는지.

## 시험 (로컬 검증)
셔뱅 `bash -n` OK · 6 케이스 PASS (허용: 따옴표 heredoc+relay · 비mbox · 다른 줄 백틱 / 차단: send 인자 · 비따옴표 heredoc 줄 · 백슬래시 연속줄).

## 머신별 반영
| 머신 | 상태 | sha |
|---|---|---|
| 로컬 · harness-ops 워크트리 | 반영됨 (라이브 heredoc 통과 확인) | dedceb2ba6 (main squash · PR #802) |
| 로컬 · 그 외 워크트리 130개 (10-04 측정) | 반영 1 · 구버전 85 · 훅 없음 44 (main 체크아웃·c-level-planning 포함) — 각 워크트리는 자기 브랜치가 main 을 병합할 때 반영됨, 일괄 덮어쓰기 안 함 | |
| 로컬 · v6-realtime-live | 구버전 (3a72b159de) — 다음 main 병합 때 반영 | |
| jarvis | 미반영 · 머신 키트 뒤 | |
