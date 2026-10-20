# r540 준비 확인 픽스처 (pi 화면 끝 줄)

- `pi-w149-live.txt` · `claude-tail-live.txt` · `codex-tail-live.txt` = 2026-10-20 라이브 pane `tmux capture-pane -p` 끝 줄(빈 줄 뺌) 실물.
- `pi-w80-*.txt` = pi 1.3.0 `dist/modes/interactive/components/footer.js:189-243` 규칙(왼쪽 통계 + 최소 2칸 + 오른쪽 `<모델> • <effort>` · 넘치면 오른쪽을 잘라 붙임)을 폭 80 에 그대로 적용해 만든 줄. 새 tmux 세션 기본 폭이 80 이라 그 폭을 본다.
  - `start` = 시작 직후(통계 `0.0%/1.0M (auto)`) · `start-unknown-ctx` = 통계 `?/1.0M (auto)` · `thinking-off` = effort 없이 뜬 좌석 · `truncated` = 통계가 길어 오른쪽 `• medium` 이 잘린 줄(재개 좌석).
