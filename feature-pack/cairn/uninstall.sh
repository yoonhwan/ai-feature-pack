#!/usr/bin/env bash
# cairn 제거 — 전역 설치만 제거. 프로젝트별 .cairn/ 데이터는 보존(수동 삭제).
set -euo pipefail

echo "▶ cairn 제거"
read -r -p "  ~/.cairn + ~/.claude/{commands,skills}/cairn 제거? [y/N] " ans
[ "$ans" = "y" ] || { echo "취소"; exit 0; }

rm -rf "$HOME/.cairn"
rm -rf "$HOME/.claude/commands/cairn"
rm -rf "$HOME/.claude/skills/cairn"
echo "✅ 제거 완료. PATH 줄(~/.zshrc 또는 ~/.bashrc)은 수동 정리하세요."
echo "  프로젝트별 .cairn/ 원장은 보존됨 (사용자 데이터)."
