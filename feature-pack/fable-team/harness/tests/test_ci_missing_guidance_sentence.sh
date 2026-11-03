#!/usr/bin/env bash
# test_ci_missing_guidance_sentence.sh — r1353: «ci 가 안 돌면 결함 · 그 턴 [긴급] 1통» 문장이 6곳에 같게 있는가.
# 정적 검사(실행·네트워크·tmux 0 · 자기 재호출 0). 사본은 mktemp 임시 폴더만.
#   S1 곳마다 «rg+Read» 줄이 ≥1 이고, 줄마다 같은 줄 또는 다음 줄에 «[긴급]» 이 있다 (없으면 FAIL 파일:줄)
#   S2 sync-globals 뒤 codex·hermes·pi·opencode 의 CLAUDE_MASTER_SYNC 에 같은 문장 (글로벌 CORE 에 문장이 올라간 뒤에만 검사 — 전엔 SKIP)
#   S3 ft-nano-spawn.sh 의 _SRX(첫 발주문 고정 줄)에 문장이 정확히 1회
#   변이: 한 곳의 «[긴급]» 을 지우면 S1 FAIL · rg+Read 줄을 통째로 지워도 S1 FAIL
# 사용: bash test_ci_missing_guidance_sentence.sh [파일 …]   (인자 없으면 6곳 기본 경로 — BYZ_ROOT·GLOBAL_DIR 환경변수로 바꾼다)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BYZ_ROOT="${BYZ_ROOT:-$HOME/Project/Agent/BYZ-Work/BYZ-Agents}"
GLOBAL_DIR="${GLOBAL_DIR:-$HOME/.claude}"
NANO="$HERE/../bin/ft-nano-spawn.sh"
if [ "$#" -gt 0 ]; then FILES=("$@"); else
  FILES=("$NANO" "$HERE/../../../tmuxc/claude-code/skills/tmuxc/COMM-GUIDE-BOOT.md"
         "short:$BYZ_ROOT/CLAUDE.md" "$BYZ_ROOT/docs/rules/code-intel-usage.md"
         "$GLOBAL_DIR/CLAUDE.md" "$GLOBAL_DIR/guides/tools.md")
fi
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
RX='rg`?[[:space:]]*[+][[:space:]]*`?Read'

# check_file <파일> → 0 통과 / 1 실패 (실패 줄은 stdout 에 «파일:줄»)
check_file() {
  local f="$1" hits
  [ -f "$f" ] || { echo "$f: 파일 없음"; return 1; }
  hits="$(awk -v rx="$RX" '
    { line[NR]=$0 }
    END { n=0; for (i=1;i<=NR;i++) if (line[i] ~ rx) { n++;
            if (line[i] !~ /\[긴급\]/ && line[i+1] !~ /\[긴급\]/) print FILENAME ":" i ": rg+Read 줄에 [긴급] 없음" }
          if (n==0) print FILENAME ": rg+Read 줄 없음" }' "$f")"
  [ -z "$hits" ] && return 0
  echo "$hits"; return 1
}

# check_short <파일> — 용량 한도가 있는 파일(BYZ CLAUDE.md)용 짧은 꼴: «ci 안 돌면» 줄에 «[긴급]» 낱말이 있다 (전문은 code-intel-usage §5)
check_short() {
  local f="$1" n
  [ -f "$f" ] || { echo "$f: 파일 없음"; return 1; }
  n="$(grep -c 'ci 안 돌면.*\[긴급\]' "$f")"
  [ "$n" -ge 1 ] && return 0
  echo "$f: «ci 안 돌면 … [긴급]» 줄 없음"; return 1
}

# S1 — 인자/기본 목록에서 «short:<경로>» 는 짧은 꼴 검사
for f in "${FILES[@]}"; do
  case "$f" in
    short:*) p="${f#short:}"; out="$(check_short "$p")" && ok "S1(short) $p" || { bad "S1(short) $p"; echo "$out" | sed 's/^/     /'; } ;;
    *)       out="$(check_file "$f")" && ok "S1 $f" || { bad "S1 $f"; echo "$out" | sed 's/^/     /'; } ;;
  esac
done

# S3 — 첫 발주문 고정 줄에 문장 1회
if [ "$#" -eq 0 ] || [ "${FILES[0]}" = "$NANO" ]; then
  DEF="$(grep '^_SRX="' "$NANO")"
  if [ -n "$DEF" ]; then
    eval "$DEF"
    c="$(printf '%s' "$_SRX" | grep -o 'ci 가 안 돌면(끊김·미설치) 결함이다. 그 턴에 보고처(팀 master · master 는 harness master)에 \[긴급\] 1통을 보낸다' | wc -l | tr -d ' ')"
    [ "$c" = "1" ] && ok "S3 _SRX 문장 1회" || bad "S3 _SRX 문장 ${c}회 (기대 1)"
    unset _SRX
  else bad "S3 _SRX 줄 없음"; fi
fi

# S2 — sync 뒤 4곳 (글로벌 CORE 에 문장이 올라간 뒤에만)
if [ "$#" -eq 0 ]; then
  if grep -q '\[긴급\] 1통을 보낸다' "$GLOBAL_DIR/CLAUDE.md" 2>/dev/null; then
    for t in "$HOME/.codex/AGENTS.md" "$HOME/.hermes/SOUL.md" "$HOME/.pi/agent/AGENTS.md" "$HOME/.config/opencode/AGENTS.md"; do
      grep -q '\[긴급\] 1통을 보낸다' "$t" 2>/dev/null && ok "S2 $t" || bad "S2 $t 에 문장 없음 (sync-globals 미실행?)"
    done
  else echo "SKIP S2 (글로벌 CORE 에 문장 아직 없음 — master 가 고치고 sync 한 뒤 검사)"; fi
fi

# 변이 — 임시 사본에서 첫 파일의 [긴급] 삭제 / rg+Read 줄 삭제 → check_file 이 FAIL 이어야 한다
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
src="${FILES[0]}"
LC_ALL=C sed 's/\[긴급\]//g' "$src" > "$TMP/m1"
cmp -s "$src" "$TMP/m1" && bad "변이1: sed 가 [긴급] 을 못 지움"
check_file "$TMP/m1" >/dev/null && bad "변이1: [긴급] 지웠는데 PASS" || ok "변이1: [긴급] 삭제 → FAIL"
LC_ALL=C grep -Ev "$RX" "$src" > "$TMP/m2"
cmp -s "$src" "$TMP/m2" && bad "변이2: grep 이 rg+Read 줄을 못 지움"
check_file "$TMP/m2" >/dev/null && bad "변이2: rg+Read 줄 지웠는데 PASS" || ok "변이2: rg+Read 줄 삭제 → FAIL"

# 변이3 — 짧은 꼴 파일이 목록에 있으면 그 파일의 «[긴급]» 삭제 → check_short FAIL
for f in "${FILES[@]}"; do
  case "$f" in short:*)
    p="${f#short:}"; LC_ALL=C sed 's/\[긴급\]//g' "$p" > "$TMP/m3"
    cmp -s "$p" "$TMP/m3" && bad "변이3: sed 가 [긴급] 을 못 지움"
    check_short "$TMP/m3" >/dev/null && bad "변이3: 짧은 꼴 [긴급] 지웠는데 PASS" || ok "변이3: 짧은 꼴 [긴급] 삭제 → FAIL"
    break ;;
  esac
done

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILED=$fail"
exit "$fail"
