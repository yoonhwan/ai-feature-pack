#!/usr/bin/env bash
# resume_chain.sh — 한 CLI로 페르소나 주입 + 다회 비대화 resume 체인
# Usage: resume_chain.sh <cli> <persona|-> "<round1>" ["<round2>" ...]
#   cli:     claude | codex | gemini | opencode | cursor-agent
#   persona: DA | designer | architect | -(없음)   (references/personas.md에서 로드)
# 환경: OPENCODE_MODEL(기본 opencode/deepseek-v4-flash-free) · CROSS_CLI_TIMEOUT(초, 기본 150)
# 주의: 자동주행 플래그 사용 — 격리/신뢰 워크스페이스에서만 실행.
set -uo pipefail
exec </dev/null

SDIR="$(cd "$(dirname "$0")/.." && pwd)"          # skill root (cross-cli/)
PERSONAS="$SDIR/references/personas.md"
CLI="${1:?usage: resume_chain.sh <cli> <persona|-> <round1> [round2 ...]}"
PERSONA="${2:?persona name or -}"; shift 2
[ $# -ge 1 ] || { echo "라운드 프롬프트가 최소 1개 필요합니다." >&2; exit 1; }
OPENCODE_MODEL="${OPENCODE_MODEL:-opencode/deepseek-v4-flash-free}"
TIMEOUT_S="${CROSS_CLI_TIMEOUT:-150}"

command -v "$CLI" >/dev/null 2>&1 || { echo "PATH에 '$CLI' 없음" >&2; exit 127; }

run_to(){ perl -e '
  my $t=shift @ARGV; my $pid=fork();
  if(!defined $pid){ exit 127 }
  if($pid==0){ setpgrp(0,0); exec @ARGV or exit 127 }
  local $SIG{ALRM}=sub{ kill("KILL", -$pid); }; alarm $t;
  waitpid($pid,0); my $rc=$?; alarm 0; exit($rc==0?0:($rc>>8||142));
' "$TIMEOUT_S" "$@"; }
get_persona(){ [ "$1" = "-" ] && return 0; awk -v h="## $1" 'index($0,h)==1{f=1;next} f&&/^## /{f=0} f{print}' "$PERSONAS"; }
sid_json(){ python3 -c "import json,sys
s=open(sys.argv[1]).read(); i=s.find('{')
try: print(json.loads(s[i:],strict=False).get('session_id','') if i>=0 else '')
except Exception: print('')" "$1" 2>/dev/null; }
res_key(){ python3 -c "import json,sys
s=open(sys.argv[1]).read(); i=s.find('{')
d=json.loads(s[i:],strict=False) if i>=0 else {}
print(d.get('result') or d.get('response') or '')" "$1" 2>/dev/null; }

P="$(get_persona "$PERSONA")"
TMP="$(mktemp -d)"; SID=""; n=0
for PROMPT in "$@"; do
  n=$((n+1))
  if [ "$n" -eq 1 ] && [ -n "$P" ]; then FULL="$P

$PROMPT"; else FULL="$PROMPT"; fi
  echo "── round $n ($CLI) ──" >&2
  case "$CLI" in
    claude)
      if [ -z "$SID" ]; then
        if [ -n "$P" ]; then PA=(--append-system-prompt "$P"); else PA=(); fi
        run_to claude -p "$PROMPT" "${PA[@]}" --dangerously-skip-permissions --output-format json >"$TMP/r$n.json"
        SID=$(sid_json "$TMP/r$n.json")
      else
        run_to claude -p "$PROMPT" --resume "$SID" --dangerously-skip-permissions --output-format json >"$TMP/r$n.json"
      fi
      res_key "$TMP/r$n.json" ;;
    codex)
      if [ -z "$SID" ]; then run_to codex exec --full-auto --skip-git-repo-check "$FULL"; SID=last
      else run_to codex exec resume --last --full-auto --skip-git-repo-check "$PROMPT"; fi ;;
    gemini)
      if [ -z "$SID" ]; then
        run_to gemini -p "$FULL" --approval-mode yolo -o json >"$TMP/r$n.json"; SID=$(sid_json "$TMP/r$n.json")
      else
        run_to gemini -p "$PROMPT" --resume "$SID" --approval-mode yolo -o json >"$TMP/r$n.json"
      fi
      res_key "$TMP/r$n.json" ;;
    opencode)
      if [ -z "$SID" ]; then run_to opencode run -m "$OPENCODE_MODEL" "$FULL"; SID=cont
      else run_to opencode run -c -m "$OPENCODE_MODEL" "$PROMPT"; fi ;;
    cursor-agent)
      if [ -z "$SID" ]; then
        run_to cursor-agent -p -f --output-format json "$FULL" >"$TMP/r$n.json"; SID=$(sid_json "$TMP/r$n.json")
      else
        run_to cursor-agent -p -f --output-format json --resume "$SID" "$PROMPT" >"$TMP/r$n.json"
      fi
      res_key "$TMP/r$n.json" ;;
    *) echo "미지원 cli: $CLI" >&2; exit 2 ;;
  esac
done
echo "session=$SID  work=$TMP" >&2
