#!/usr/bin/env bash
# baton uninstall.sh

set -euo pipefail

echo "─────────────────────────────────────────"
echo "🗑️  baton uninstall"
echo "─────────────────────────────────────────"
echo
echo "다음을 제거합니다:"
echo "  ~/.baton/                       (multi-version 전체)"
echo "  ~/.claude/skills/baton/         (심볼릭 링크)"
echo "  ~/.claude/commands/baton/       (17개 .md)"
echo "  ~/.claude/settings.json         (baton hooks 항목 제거, 백업 보관)"
echo "  ~/.gemini/commands/baton/       (해당 시)"
echo "  ~/.config/opencode/commands/baton/  (해당 시)"
echo "  ~/.hermes/plugins/baton.py      (해당 시)"
echo
echo "보존:"
echo "  {project}/.baton/               (사용자 데이터, 수동 삭제 필요)"
echo
read -r -p "계속할까요? [y/N] " ans
[[ "${ans:-N}" =~ ^[Yy]$ ]] || { echo "취소됨"; exit 0; }

# 글로벌
[[ -d "$HOME/.baton" ]] && rm -rf "$HOME/.baton" && echo "✓ ~/.baton/"

# Claude Code
[[ -d "$HOME/.claude/skills/baton" ]] && rm -rf "$HOME/.claude/skills/baton" && echo "✓ ~/.claude/skills/baton/"
[[ -d "$HOME/.claude/commands/baton" ]] && rm -rf "$HOME/.claude/commands/baton" && echo "✓ ~/.claude/commands/baton/"

# settings.json hooks 제거 (baton 관련만)
settings="$HOME/.claude/settings.json"
if [[ -f "$settings" ]] && command -v jq >/dev/null; then
  cp "$settings" "$settings.baton-uninstall-backup"
  jq '
    if .hooks then
      .hooks |= with_entries(
        .value |= map(select(
          .hooks // [] | map(.command // "" | test("baton")) | any | not
        ))
      )
    else . end
    | if .hooks then .hooks |= with_entries(select(.value | length > 0)) else . end
  ' "$settings.baton-uninstall-backup" > "$settings"
  echo "✓ settings.json baton hooks 제거 (백업: .baton-uninstall-backup)"
fi

# 다른 에이전트
[[ -d "$HOME/.gemini/commands/baton" ]] && rm -rf "$HOME/.gemini/commands/baton" && echo "✓ ~/.gemini/commands/baton/"
[[ -d "$HOME/.config/opencode/commands/baton" ]] && rm -rf "$HOME/.config/opencode/commands/baton" && echo "✓ ~/.config/opencode/commands/baton/"
[[ -f "$HOME/.hermes/plugins/baton.py" ]] && rm -f "$HOME/.hermes/plugins/baton.py" && echo "✓ ~/.hermes/plugins/baton.py"

echo
echo "─────────────────────────────────────────"
echo "✅ 제거 완료"
echo "─────────────────────────────────────────"
echo "프로젝트 .baton/ 폴더는 보존됨. 필요시 수동 삭제."
