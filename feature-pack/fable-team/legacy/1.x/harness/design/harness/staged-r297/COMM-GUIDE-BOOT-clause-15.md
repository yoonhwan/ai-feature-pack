# staged-r297 — COMM-GUIDE-BOOT 15 «master 손 = 집행뿐» 줄 끝 1구 (R297)

설치는 master 집행(라이브 BOOT 에 cp 전 `ft-version.sh check` 의 BOOT sha 대조 · 선복사 규칙). 이 폴더 파일은 «한 구절»만 담는다.

## 더하는 위치
`~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md` 15번 줄(`15. **master 손 = 집행뿐**…`) 맨 끝, 마침표 «앞» 문장 `정본 \`references/main-team-governance.md\` §6.` 바로 뒤에 아래 구를 이어 붙인다.

## 추가 구 (글자 그대로)
` · 세션만 닫기 = \`ft-seat-close.sh <좌석> --reason …\`(세션 kill + 명부 stop-ready 표기 · 명부 손 편집 0 · 현역 역할 좌석은 거절 → 승계 경로 · 계보 최신·재개 기록 없는 직전 세대는 kill 보류)`

## 검증
- `ft-seat-close.sh` 사본: `scripts/fable-team-bin/` = `scripts/harness-install/fable-team/bin/` cmp 0.
- 시험: `tests/harness/test_seat_close.sh` (명부 표기·kill·거절·틱 resume_rows 에서 빠짐).
