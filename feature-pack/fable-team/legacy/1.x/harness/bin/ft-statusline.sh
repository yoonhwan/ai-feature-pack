#!/bin/sh
# ft-statusline.sh — Claude Code statusLine. stdin JSON 1건 → 1줄. node 0 · jq 0 · git 0 · 상주 0.
# 글자 「ctx:」 는 ft-tmux-spawn.sh CLAUDE_READY_RE 1차 패턴 — 바꾸지 않는다.
# 팀 이름 칸: tmux 안이면 세션명(#S) → 아니면 stdin session_name → 없으면 ?
in=$(cat)
g() { printf '%s' "$in" | sed -n "s/.*\"$1\":[[:space:]]*\"\{0,1\}\([^\",}]*\).*/\1/p" | head -1; }
pct=$(g used_percentage); [ "$pct" = null ] && pct=
model=$(g display_name); eff=$(g level)
name=
[ -n "$TMUX" ] && name=$(tmux display -p '#S' 2>/dev/null)
[ -n "$name" ] || name=$(g session_name)
printf 'ctx:%s%% | %s %s | %s\n' "${pct:-?}" "$model" "$eff" "${name:-?}"
