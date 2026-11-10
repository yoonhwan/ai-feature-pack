#!/usr/bin/env bash
# compare.sh <fable-team 폴더> — claude·codex·opencode·cmd 의 열기 도구 출력(dry-run·꺼낸 블록)·도달 판정을 찍는다. base·new 두 번 돌려 diff.
set -uo pipefail
FT="$1"; H="$FT/harness"; KIT="$H/kit/fable-team/bin"; export FT_ALLOW_TRACKED_BIN=1
TMP="$(mktemp -d)"
. "$H/tests/lib/fake_resource_env.sh"; fake_resource_env "$TMP/sensors" ok >/dev/null 2>&1
REPO="$TMP/repo"; FAKE="$TMP/fakebin"; mkdir -p "$REPO/.fable-team/comm" "$REPO/design/v65/indices/inbox/master" "$FAKE"
git -C "$REPO" init -q; : > "$REPO/design/v65/SEATBELT-README.md"; echo '{}' > "$REPO/.fable-team/seats.json"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| v65 | `design/v65/` | x | 현역 |\n' > "$REPO/design/TEAMS.md"
printf '#!/usr/bin/env bash\ncase "$1" in has-session) exit 1;; *) exit 0;; esac\n' > "$FAKE/tmux"
printf '#!/usr/bin/env bash\necho "TMUXC $*"\n' > "$FAKE/tmuxc"; chmod +x "$FAKE/tmux" "$FAKE/tmuxc"
for A in claude:claude-opus-5-5[1m] codex:gpt-6-luna opencode:opencode/deepseek-v4.1-flash-free cmd:deepseek/deepseek-v4-flash; do
  ag="${A%%:*}"; m="${A#*:}"
  for SP in "$H/bin/ft-role-spawn.sh" "$KIT/ft-role-spawn.sh"; do
    echo "== role-spawn ${SP#"$H"/} $ag"
    (cd "$REPO" && FT_ROOT="$REPO" PATH="$FAKE:$PATH" bash "$SP" master --agent "$ag" --model "$m" --effort low --dry-run 2>&1) | sed "s|$TMP|<TMP>|g; s|$FT|<FT>|g"
  done
  for SP in "$H/bin/ft-nano-spawn.sh" "$KIT/ft-nano-spawn.sh" "$FT/skill/scripts/ft-nano-spawn.sh"; do
    echo "== nano-spawn OPEN ${SP#"$FT"/} $ag"
    { grep -E '^OPEN=\(tmuxc open "\$WTDIR"' "$SP"; grep -E '^\[ "\$AGENT" = claude \] && OPEN\+=\(--ctx 1m\)' "$SP"; grep -E '^case "\$AGENT" in claude\|cmd\|codex(\|pi)?\) OPEN\+=\(--effort' "$SP"; echo 'echo "${OPEN[*]}"'; } > "$TMP/open.sh"
    env -i PATH="$PATH" AGENT="$ag" MODEL="$m" EFFORT=high WTDIR=/w NAME=n bash "$TMP/open.sh" 2>&1
  done
  for SP in "$H/bin/ft-nano-spawn.sh" "$KIT/ft-nano-spawn.sh"; do
    echo "== nano-spawn 기본 모델 ${SP#"$H"/} $ag"
    _s="$(grep -n '^if \[ -z "\$MODEL" \]; then case' "$SP" | head -1 | cut -d: -f1)"
    { sed -n "${_s},\$p" "$SP" | awk '{print} /^fi$/{exit}'; echo 'echo "$AGENT|$MODEL"'; } > "$TMP/sel.sh"
    env -i PATH="$PATH" AGENT="$ag" MODEL= bash "$TMP/sel.sh" 2>&1
  done
  for TS in "$KIT/ft-tmux-spawn.sh" "$FT/skill/scripts/ft-tmux-spawn.sh"; do
    echo "== tmux-spawn 열기 인자 ${TS#"$FT"/} $ag"
    { echo 'set --'; sed -n '/^  case "\$AGENT" in$/,/^  esac$/p' "$TS" | head -5; echo 'echo "$*"'; } > "$TMP/ts.sh"
    env -i PATH="$PATH" AGENT="$ag" MODEL="$m" EFFORT=high bash "$TMP/ts.sh" 2>&1
  done
done
echo "== tmux-spawn 준비 확인 claude·codex 식 (pi 아닌 갈래)"
for TS in "$KIT/ft-tmux-spawn.sh" "$FT/skill/scripts/ft-tmux-spawn.sh"; do grep -E '^(CLAUDE_READY_RE|\[ -z "\$CODEX_READY_RE" \])' "$TS"; done
echo "== reach-check claude 좌석 (agentName + user 마커 · queue enqueue · 남의 파일만)"
PANE=/Users/x/p; RH="$TMP/rh"; CJ="$RH/.claude/projects/-Users-x-p"; mkdir -p "$CJ"
printf '#!/usr/bin/env bash\ncase "$*" in *pane_pid*) echo 4242;; *) echo "$PANE_CWD";; esac\n' > "$FAKE/tmux"
for case in user queued other; do
  rm -f "$CJ"/*.jsonl
  case $case in
    user)   printf '{"type":"agent-name","agentName":"s#1"}\n{"type":"user","message":{"content":"[발주 #9] x"}}\n' > "$CJ/a.jsonl";;
    queued) printf '{"type":"agent-name","agentName":"s#1"}\n{"type":"queue-operation","operation":"enqueue","content":"[발주 #9] x"}\n' > "$CJ/a.jsonl";;
    other)  printf '{"type":"agent-name","agentName":"t#1"}\n{"type":"user","message":{"content":"[발주 #9] x"}}\n' > "$CJ/b.jsonl";;
  esac
  for R in "$KIT/ft-reach-check.sh" "$H/comm/ft-reach-check.sh"; do
    echo "-- $case ${R#"$H"/}"; HOME="$RH" PANE_CWD="$PANE" PATH="$FAKE:$PATH" bash "$R" "s#1" "[발주 #9]" 1 0 2>&1 | sed "s|$TMP|<TMP>|g"; echo "rc=${PIPESTATUS[0]}"
  done
done
