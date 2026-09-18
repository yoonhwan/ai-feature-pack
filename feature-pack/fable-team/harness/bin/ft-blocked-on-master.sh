#!/bin/bash
# ★나를 기다리는 좌석★ — 좌석 pane 에서 「master 회신 대기」 형태를 찾아 세운다.
# 오늘 실측: astra#2 4시간 · arch#4 1시간 · tester#13 1시간 이 이 형태로 멈춰 있었다.
ROOT="$(git -C "$(dirname "$0")" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
[ -n "$ROOT" ] || ROOT=/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents
PAT='대기\(남의 회신\).*master|master.*회신 (대기|기다)|master 응답|master 에 발신하고 대기|master 판단|master 소관|발주 대기|다음 발주 대기'
hit=0
for s in $(tmux list-sessions -F '#S' 2>/dev/null | grep '^ft-v65' | grep -v 'master-claude#3'); do
  line=$(tmux capture-pane -p -S -25 -t "$s" 2>/dev/null | grep -nE "$PAT" | tail -1)
  [ -z "$line" ] && continue
  age=$(bash "$ROOT/.worktrees/v6-realtime-live/.fable-team/bin/ft-seat-status.sh" one "$s" 2>/dev/null | awk '{print $3}')
  printf '  ★%s★ (jsonl %ss 전)\n    %s\n' "$s" "${age:-?}" "$(echo "$line" | cut -c1-150)"
  hit=$((hit+1))
done
echo "BLOCKED-ON-MASTER=$hit"
