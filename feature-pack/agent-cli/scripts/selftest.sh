#!/usr/bin/env bash
# selftest.sh — cross-cli 비대화·자율·resume 점검 하네스 (로그 영속 + 강제 타임아웃)
# Usage: bash selftest.sh [cli ...]      (기본: claude codex gemini opencode cursor-agent)
# 각 CLI: ① PATH 존재 ② 비대화+자율 R1(코드워드 주입) ③ resume R2(코드워드 회상)
# 로그: <skill>/logs/ 를 매 실행 삭제·재생성 → selftest.log + <cli>.r1/.r2/.err 원문 보존.
# 환경: OPENCODE_MODEL(기본 opencode/deepseek-v4-flash-free) · CROSS_CLI_LOGDIR · CROSS_CLI_TIMEOUT(초, 기본 150)
# 주의: 자동주행 플래그 사용 — 격리/신뢰 워크스페이스에서만.
set -uo pipefail
exec </dev/null   # 자식 CLI stdin EOF 즉시 — hang/3s 대기 방지

SDIR="$(cd "$(dirname "$0")/.." && pwd)"
LOGDIR="${CROSS_CLI_LOGDIR:-$SDIR/logs}"; LOG="$LOGDIR/selftest.log"
rm -rf "$LOGDIR"; mkdir -p "$LOGDIR"

CLIS=("$@"); [ ${#CLIS[@]} -eq 0 ] && CLIS=(claude codex gemini opencode cursor-agent)
TOKEN="BANANA-7"
R1="Remember this codeword: ${TOKEN}. Reply with exactly: OK ${TOKEN}"
R2="What was the codeword I gave you earlier? Reply with ONLY the codeword, nothing else."
OPENCODE_MODEL="${OPENCODE_MODEL:-opencode/deepseek-v4-flash-free}"
TIMEOUT_S="${CROSS_CLI_TIMEOUT:-150}"
ts="$(date '+%Y-%m-%d %H:%M:%S')"

# 강제 타임아웃: 자식을 새 프로세스그룹으로 fork → 초과 시 그룹째 SIGKILL(자식·손자 포함, 무시 불가).
run_to(){ perl -e '
  my $t=shift @ARGV; my $pid=fork();
  if(!defined $pid){ exit 127 }
  if($pid==0){ setpgrp(0,0); exec @ARGV or exit 127 }
  local $SIG{ALRM}=sub{ kill("KILL", -$pid); }; alarm $t;
  waitpid($pid,0); my $rc=$?; alarm 0; exit($rc==0?0:($rc>>8||142));
' "$TIMEOUT_S" "$@"; }
log(){ printf '%s\n' "$*" | tee -a "$LOG"; }
sid_json(){ python3 -c "import json,sys
s=open(sys.argv[1]).read(); i=s.find('{')
try: print(json.loads(s[i:],strict=False).get('session_id','') if i>=0 else '')
except Exception: print('')" "$1" 2>/dev/null; }
has(){ grep -q "$TOKEN" <<<"$1"; }

declare -a ROWS
run_one(){
  local cli="$1" r1="—" r2="—" sid="" o1="" o2="" base="$LOGDIR/$1"
  log ""; log "==================== $cli ===================="
  if ! command -v "$cli" >/dev/null 2>&1; then
    log "[$cli] SKIP — PATH에 없음"; ROWS+=("| $cli | ❌ SKIP(미설치) | — | — |"); return
  fi
  log "[$cli] bin=$(command -v "$cli") · timeout=${TIMEOUT_S}s"
  case "$cli" in
    claude)
      o1=$(run_to claude -p "$R1" --dangerously-skip-permissions --output-format json 2>"$base.err"); echo "$o1">"$base.r1"
      sid=$(sid_json "$base.r1"); has "$o1" && r1="✅" || r1="⚠️ R1불일치"
      log "[claude] R1 sid=$sid verdict=$r1"
      if [ -n "$sid" ]; then o2=$(run_to claude -p "$R2" --resume "$sid" --dangerously-skip-permissions --output-format json 2>>"$base.err"); echo "$o2">"$base.r2"; has "$o2" && r2="✅" || r2="❌ 미회상"; else r2="❌ sid없음"; fi
      log "[claude] R2 verdict=$r2" ;;
    codex)
      o1=$(run_to codex exec --full-auto --skip-git-repo-check "$R1" 2>"$base.err"); echo "$o1">"$base.r1"
      has "$o1" && r1="✅" || r1="⚠️ R1불일치"; log "[codex] R1 verdict=$r1"
      o2=$(run_to codex exec resume --last --full-auto --skip-git-repo-check "$R2" 2>>"$base.err"); echo "$o2">"$base.r2"
      has "$o2" && r2="✅" || r2="❌ 미회상"; log "[codex] R2(resume --last) verdict=$r2" ;;
    gemini)
      o1=$(run_to gemini -p "$R1" --approval-mode yolo -o json 2>"$base.err"); echo "$o1">"$base.r1"
      sid=$(sid_json "$base.r1"); has "$o1" && r1="✅" || r1="⚠️ R1불일치"
      log "[gemini] R1 sid=$sid verdict=$r1"
      if [ -n "$sid" ]; then o2=$(run_to gemini -p "$R2" --resume "$sid" --approval-mode yolo -o json 2>>"$base.err"); echo "$o2">"$base.r2"; has "$o2" && r2="✅" || r2="❌ 미회상"; else r2="❌ sid없음"; fi
      log "[gemini] R2(resume sid) verdict=$r2" ;;
    opencode)
      o1=$(run_to opencode run -m "$OPENCODE_MODEL" "$R1" 2>"$base.err"); echo "$o1">"$base.r1"; has "$o1" && r1="✅" || r1="⚠️ R1불일치"
      log "[opencode] R1 verdict=$r1 (model=$OPENCODE_MODEL)"
      o2=$(run_to opencode run -c -m "$OPENCODE_MODEL" "$R2" 2>>"$base.err"); echo "$o2">"$base.r2"; has "$o2" && r2="✅" || r2="❌ 미회상"
      log "[opencode] R2(-c) verdict=$r2" ;;
    cursor-agent)
      o1=$(run_to cursor-agent -p -f --output-format json "$R1" 2>"$base.err"); echo "$o1">"$base.r1"
      sid=$(sid_json "$base.r1"); has "$o1" && r1="✅" || r1="⚠️ R1불일치"
      log "[cursor-agent] R1 sid=$sid verdict=$r1"
      if [ -n "$sid" ]; then o2=$(run_to cursor-agent -p -f --output-format json --resume "$sid" "$R2" 2>>"$base.err"); echo "$o2">"$base.r2"; has "$o2" && r2="✅" || r2="❌ 미회상"; else r2="❌ sid없음"; fi
      log "[cursor-agent] R2 verdict=$r2" ;;
    *) log "[$cli] 미지원"; ROWS+=("| $cli | ❓ 미지원 | — | — |"); return ;;
  esac
  ROWS+=("| $cli | ✅ | $r1 | $r2 |")
}

log "# agent-cli selftest — $ts"
log "테스트: 비대화 + 자율(dangerous/full-auto/yolo/force) + resume 코드워드 회상(${TOKEN}) · timeout ${TIMEOUT_S}s"
log "로그: $LOG   원문: $LOGDIR/<cli>.r1 / .r2 / .err"
for c in "${CLIS[@]}"; do run_one "$c"; done
log ""; log "## 요약"
log "| CLI | 설치 | 비대화+자율 R1 | resume R2 회상 |"
log "|-----|------|----------------|----------------|"
for r in "${ROWS[@]}"; do log "$r"; done
log ""; log "_생성 $ts · 미회상/행은 <cli>.err 참조_"
echo "리포트: $LOG" >&2
