#!/usr/bin/env bash
# test_r66_codex_serena_boot.sh — R66 시험: 스테이징 BOOT 는 홈 BOOT 에 1번 항목 한 문장만 덧붙인 것 · 프로젝트 Serena 지침에 codex 경로 줄 · 홈·루트·~/.codex 쓰기 0(읽기만).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."
STAGED="$ROOT/design/harness/staged-r66/COMM-GUIDE-BOOT.md"
HOME_BOOT="${R66_HOME_BOOT:-$HOME/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md}"
RULE="$ROOT/docs/rules/serena-mcp-usage.md"
BASE16="329582414d727dd5"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
skip(){ echo "SKIP $1"; }
sha16() { shasum -a 256 "$1" | cut -c1-16; }

[ -f "$STAGED" ] && ok "staged 존재" || { bad "staged 없음: $STAGED"; exit 1; }
[ -f "$HOME_BOOT" ] || { bad "홈 BOOT 없음: $HOME_BOOT"; exit 1; }

home_before="$(sha16 "$HOME_BOOT")"
staged_sha="$(sha16 "$STAGED")"

# ① 스테이징 vs 홈: 바뀐 줄 1개(1번 항목) · 추가 0 · 삭제 0 · 덧붙임만
if [ "$home_before" = "$staged_sha" ]; then
  skip "① 홈이 이미 스테이징과 같음(설치 뒤 재실행) — diff 시험 생략"
elif [ "$home_before" != "$BASE16" ]; then
  bad "① 홈 BOOT sha=$home_before — 기준 $BASE16 도 스테이징($staged_sha)도 아님(그사이 다른 판정이 바꿈)"
else
  d="$(diff "$HOME_BOOT" "$STAGED")"
  [ "$(printf '%s\n' "$d" | grep -c '^[0-9]')" = 1 ] && printf '%s\n' "$d" | grep -q '^7c7$' \
    && ok "① diff = 7c7 한 덩이" || bad "① diff 가 7c7 한 덩이가 아님: $(printf '%s' "$d" | head -3)"
  [ "$(printf '%s\n' "$d" | grep -c '^<')" = 1 ] && [ "$(printf '%s\n' "$d" | grep -c '^>')" = 1 ] \
    && ok "① 삭제 1(옛 줄)·추가 1(새 줄) — 줄 수 불변" || bad "① < > 줄 수가 1·1 이 아님"
  [ "$(wc -l < "$HOME_BOOT")" = "$(wc -l < "$STAGED")" ] && ok "① 총 줄 수 동일" || bad "① 총 줄 수 다름"
  old="$(printf '%s\n' "$d" | sed -n 's/^< //p')"; new="$(printf '%s\n' "$d" | sed -n 's/^> //p')"
  case "$new" in "$old"*) ok "① 새 줄 = 옛 줄 + 덧붙임(기존 문장 무변경)";; *) bad "① 새 줄이 옛 줄로 시작하지 않음";; esac
fi

# ② 스테이징 1번 줄에 세 문자열
line1="$(grep -m1 '^1\. \*\*Serena\*\*' "$STAGED")"
for s in 'activate_project(project=' 'session_id 가 없다' 'headroom_retrieve'; do
  printf '%s' "$line1" | grep -qF -- "$s" && ok "② 1번 줄에 «${s}»" || bad "② 1번 줄에 «${s}» 없음"
done

# ③ 기존 Claude 문장 그대로
printf '%s' "$line1" | grep -qF 'activate_project(project="<현재 워크트리 절대경로>", session_id=…)' \
  && ok "③ Claude 경로 문장(session_id=…) 유지" || bad "③ Claude 경로 문장이 사라짐"

# ④ 프로젝트 Serena 지침에 codex + activate_project 줄
grep -E 'codex' "$RULE" | grep -qF 'activate_project' \
  && ok "④ serena-mcp-usage.md 에 codex·activate_project 줄" || bad "④ serena-mcp-usage.md 에 codex·activate_project 줄 없음"

# ⑤ 시험이 홈을 바꾸지 않음
[ "$(sha16 "$HOME_BOOT")" = "$home_before" ] && ok "⑤ 홈 BOOT 쓰기 0" || bad "⑤ 홈 BOOT 가 시험 중 바뀜"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED=$fail"
exit "$fail"
